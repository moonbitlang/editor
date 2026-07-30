///|
priv struct RecordingDefinitionProvider {
  locations : Array[@language.Location]
  calls : Ref[Int]
  observed_tokens : Array[@language.CancellationToken]
}

///|
impl @language.DefinitionProvider for RecordingDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  token,
) {
  self.calls.val += 1
  self.observed_tokens.push(token)
  self.locations.copy()
}

///|
priv struct FailingDefinitionProvider {}

///|
impl @language.DefinitionProvider for FailingDefinitionProvider with fn provide_definition(
  _self,
  _model,
  _position,
  _token,
) {
  raise DefinitionTestProviderError
}

///|
priv suberror DefinitionTestProviderError {
  DefinitionTestProviderError
}

///|
priv struct ControlledDefinitionProvider {
  started : @aqueue.Queue[@language.CancellationToken]
  gate : @aqueue.Queue[Unit]
}

///|
impl @language.DefinitionProvider for ControlledDefinitionProvider with fn provide_definition(
  self,
  model,
  _position,
  token,
) {
  self.started.put(token)
  self.gate.get()
  [{ uri: model.uri, range: Range(1, 1, 1, 3) }]
}

///|
priv struct GatedDefinitionProvider {
  id : Int
  started : @aqueue.Queue[Int]
  completed : @aqueue.Queue[Int]
  gate : @aqueue.Queue[Unit]
  location : @language.Location
}

///|
impl @language.DefinitionProvider for GatedDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  self.started.put(self.id)
  self.gate.get()
  self.completed.put(self.id)
  [self.location]
}

///|
async test "definition presence and query aggregate provider and location order" {
  let languages = Languages()
  let model = test_model()
  let handle = languages.language_handle(@log.LogService().log_handle())
  assert_true(!languages.has_definition_provider(model))
  assert_true(!handle.has_definition_provider(model))

  let unmatched = languages.register_definition_provider(
    LanguageId("javascript"),
    RecordingDefinitionProvider::{
      locations: [],
      calls: Ref(0),
      observed_tokens: [],
    },
  )
  assert_true(!languages.has_definition_provider(model))

  let empty_calls = Ref(0)
  let empty_tokens : Array[@language.CancellationToken] = []
  let empty = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [],
    calls: empty_calls,
    observed_tokens: empty_tokens,
  })
  let target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/target.mbt",
  )
  let result_calls = Ref(0)
  let result_tokens : Array[@language.CancellationToken] = []
  let result = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [
      { uri: model.uri, range: Range(1, 4, 1, 8) },
      { uri: target, range: Range(7, 2, 7, 6) },
    ],
    calls: result_calls,
    observed_tokens: result_tokens,
  })
  let later_target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/later.mbt",
  )
  let later_calls = Ref(0)
  let later_tokens : Array[@language.CancellationToken] = []
  let later = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [{ uri: later_target, range: Range(4, 3, 4, 7) }],
    calls: later_calls,
    observed_tokens: later_tokens,
  })
  assert_true(languages.has_definition_provider(model))
  assert_true(handle.has_definition_provider(model))

  let token = @language.CancellationToken::new()
  let locations = handle.definition_at(model, 3, token~)
  assert_eq(empty_calls.val, 1)
  assert_eq(result_calls.val, 1)
  assert_eq(later_calls.val, 1)
  assert_true(physical_equal(empty_tokens[0], token))
  assert_true(physical_equal(result_tokens[0], token))
  assert_true(physical_equal(later_tokens[0], token))
  assert_eq(locations.length(), 3)
  assert_eq(locations[0].uri.to_string(), model.uri.to_string())
  assert_true(locations[0].range == Range(1, 4, 1, 8))
  assert_eq(locations[1].uri.to_string(), target.to_string())
  assert_true(locations[1].range == Range(7, 2, 7, 6))
  assert_eq(locations[2].uri.to_string(), later_target.to_string())
  assert_true(locations[2].range == Range(4, 3, 4, 7))

  empty.dispose()
  result.dispose()
  later.dispose()
  assert_true(!languages.has_definition_provider(model))
  assert_true(!handle.has_definition_provider(model))
  unmatched.dispose()
}

///|
async test "definition provider failures are logged and isolated" {
  let languages = Languages()
  let failed = languages.register_definition_provider(LanguageId("moonbit"), FailingDefinitionProvider::{

  })
  let calls = Ref(0)
  let good = languages.register_definition_provider(LanguageId("moonbit"), RecordingDefinitionProvider::{
    locations: [{ uri: test_model().uri, range: Range(1, 1, 1, 2) }],
    calls,
    observed_tokens: [],
  })
  let memory = @log.MemoryLogger()
  let locations = languages.definition_at(
    test_model(),
    3,
    @log.LogService(logger=memory),
  )
  assert_eq(locations.length(), 1)
  assert_eq(calls.val, 1)
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, "language.definition")
  assert_true(entries[0].details[2] == ("providerIndex", "0"))
  failed.dispose()
  good.dispose()
}

///|
async test "definition cancellation and disposal reject late data silently" {
  let languages = Languages()
  let started = @aqueue.Queue(kind=Unbounded)
  let gate = @aqueue.Queue(kind=Unbounded)
  let registration = languages.register_definition_provider(
    LanguageId("moonbit"),
    ControlledDefinitionProvider::{ started, gate },
  )
  let model = test_model()
  let memory = @log.MemoryLogger()
  let token = @language.CancellationToken::new()
  @async.with_task_group() <| group => {
    let request = group.spawn(() => {
      languages.definition_at(model, 3, @log.LogService(logger=memory), token~)
    })
    let observed = started.get()
    assert_true(physical_equal(observed, token))
    token.cancel()
    registration.dispose()
    gate.put(())
    assert_eq(request.wait().length(), 0)
  }
  assert_eq(memory.entries().length(), 0)
}

///|
async test "definition providers start concurrently and late disposal drops data" {
  let languages = Languages()
  let model = test_model()
  let started = @aqueue.Queue(kind=Unbounded)
  let completed = @aqueue.Queue(kind=Unbounded)
  let first_gate = @aqueue.Queue(kind=Unbounded)
  let second_gate = @aqueue.Queue(kind=Unbounded)
  let first_target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/first.mbt",
  )
  let second_target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/second.mbt",
  )
  let first = languages.register_definition_provider(LanguageId("moonbit"), GatedDefinitionProvider::{
    id: 0,
    started,
    completed,
    gate: first_gate,
    location: { uri: first_target, range: Range(2, 1, 2, 4) },
  })
  let second = languages.register_definition_provider(LanguageId("moonbit"), GatedDefinitionProvider::{
    id: 1,
    started,
    completed,
    gate: second_gate,
    location: { uri: second_target, range: Range(5, 2, 5, 6) },
  })
  let observed_starts : Array[Int] = []
  let observed_completions : Array[Int] = []
  @async.with_task_group() <| group => {
    let request = group.spawn(() => {
      languages.definition_at(model, 3, LogService())
    })
    match @async.with_timeout_opt(1000, () => started.get()) {
      Some(id) => observed_starts.push(id)
      None => ()
    }
    match @async.with_timeout_opt(1000, () => started.get()) {
      Some(id) => observed_starts.push(id)
      None => ()
    }
    first_gate.put(())
    match @async.with_timeout_opt(1000, () => completed.get()) {
      Some(id) => observed_completions.push(id)
      None => ()
    }
    first.dispose()
    second_gate.put(())
    let locations = request.wait()
    assert_eq(locations.length(), 1)
    assert_eq(locations[0].uri.to_string(), second_target.to_string())
    assert_true(locations[0].range == Range(5, 2, 5, 6))
  }
  assert_eq(observed_starts.length(), 2)
  assert_true(observed_starts.contains(0))
  assert_true(observed_starts.contains(1))
  assert_eq(observed_completions.length(), 1)
  assert_eq(observed_completions[0], 0)
  second.dispose()
}
