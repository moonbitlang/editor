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
async test "definition presence and query preserve provider and location order" {
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
  assert_true(languages.has_definition_provider(model))
  assert_true(handle.has_definition_provider(model))

  let token = @language.CancellationToken::new()
  let locations = handle.definition_at(model, 3, token~)
  assert_eq(empty_calls.val, 1)
  assert_eq(result_calls.val, 1)
  assert_true(physical_equal(empty_tokens[0], token))
  assert_true(physical_equal(result_tokens[0], token))
  assert_eq(locations.length(), 2)
  assert_eq(locations[0].uri.to_string(), model.uri.to_string())
  assert_true(locations[0].range == Range(1, 4, 1, 8))
  assert_eq(locations[1].uri.to_string(), target.to_string())
  assert_true(locations[1].range == Range(7, 2, 7, 6))

  empty.dispose()
  result.dispose()
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
