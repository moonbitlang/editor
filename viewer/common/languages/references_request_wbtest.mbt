///|
priv struct RecordingReferencesProvider {
  locations : Array[@language.Location]
  calls : Ref[Int]
  observed_tokens : Array[@language.CancellationToken]
}

///|
impl @language.ReferencesProvider for RecordingReferencesProvider with fn provide_references(
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
priv struct FailingReferencesProvider {}

///|
impl @language.ReferencesProvider for FailingReferencesProvider with fn provide_references(
  _self,
  _model,
  _position,
  _token,
) {
  raise ReferencesTestProviderError
}

///|
priv suberror ReferencesTestProviderError {
  ReferencesTestProviderError
}

///|
priv struct ControlledReferencesProvider {
  started : @aqueue.Queue[@language.CancellationToken]
  gate : @aqueue.Queue[Unit]
}

///|
impl @language.ReferencesProvider for ControlledReferencesProvider with fn provide_references(
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
priv struct GatedReferencesProvider {
  id : Int
  started : @aqueue.Queue[Int]
  completed : @aqueue.Queue[Int]
  gate : @aqueue.Queue[Unit]
  location : @language.Location
}

///|
impl @language.ReferencesProvider for GatedReferencesProvider with fn provide_references(
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
async fn run_references_test_tasks_concurrently(
  tasks : Array[async () -> Unit],
) -> Unit {
  @async.with_task_group() <| group => {
    for task in tasks {
      group.spawn_bg(task)
    }
  }
}

///|
async test "references presence and query preserve selector and registration priority" {
  let languages = Languages()
  let model = test_model()
  let handle = languages.language_handle(@log.LogService().log_handle())
  assert_false(languages.has_references_provider(model))
  assert_false(handle.has_references_provider(model))

  let unmatched_calls = Ref(0)
  let unmatched = languages.register_references_provider(
    LanguageId("javascript"),
    RecordingReferencesProvider::{
      locations: [],
      calls: unmatched_calls,
      observed_tokens: [],
    },
  )
  let wildcard_uri = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/wildcard.mbt",
  )
  let wildcard_calls = Ref(0)
  let wildcard = languages.register_references_provider(LanguageId("*"), RecordingReferencesProvider::{
    locations: [{ uri: wildcard_uri, range: Range(7, 1, 7, 5) }],
    calls: wildcard_calls,
    observed_tokens: [],
  })
  let older_exact_uri = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/older-exact.mbt",
  )
  let older_exact_calls = Ref(0)
  let older_exact = languages.register_references_provider(
    LanguageId("moonbit"),
    RecordingReferencesProvider::{
      locations: [{ uri: older_exact_uri, range: Range(3, 2, 3, 8) }],
      calls: older_exact_calls,
      observed_tokens: [],
    },
  )
  let newer_exact_uri = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/newer-exact.mbt",
  )
  let newer_exact_calls = Ref(0)
  let observed_tokens : Array[@language.CancellationToken] = []
  let newer_exact = languages.register_references_provider(
    LanguageId("moonbit"),
    RecordingReferencesProvider::{
      locations: [
        { uri: model.uri, range: Range(1, 5, 1, 11) },
        { uri: newer_exact_uri, range: Range(9, 4, 9, 10) },
      ],
      calls: newer_exact_calls,
      observed_tokens,
    },
  )
  assert_true(languages.has_references_provider(model))
  assert_true(handle.has_references_provider(model))

  let token = @language.CancellationToken::new()
  let locations = handle.references_at(model, 3, token~)
  assert_eq(locations.length(), 4)
  assert_eq(locations[0].uri.to_string(), model.uri.to_string())
  assert_eq(locations[1].uri.to_string(), newer_exact_uri.to_string())
  assert_eq(locations[2].uri.to_string(), older_exact_uri.to_string())
  assert_eq(locations[3].uri.to_string(), wildcard_uri.to_string())
  assert_eq(newer_exact_calls.val, 1)
  assert_eq(older_exact_calls.val, 1)
  assert_eq(wildcard_calls.val, 1)
  assert_eq(unmatched_calls.val, 0)
  assert_eq(observed_tokens.length(), 1)
  assert_true(physical_equal(observed_tokens[0], token))

  newer_exact.dispose()
  older_exact.dispose()
  wildcard.dispose()
  unmatched.dispose()
  assert_false(languages.has_references_provider(model))
  assert_false(handle.has_references_provider(model))
}

///|
async test "references provider failures are logged and isolated" {
  let languages = Languages()
  let failed = languages.register_references_provider(LanguageId("moonbit"), FailingReferencesProvider::{

  })
  let calls = Ref(0)
  let good = languages.register_references_provider(LanguageId("moonbit"), RecordingReferencesProvider::{
    locations: [{ uri: test_model().uri, range: Range(1, 1, 1, 2) }],
    calls,
    observed_tokens: [],
  })
  let memory = @log.MemoryLogger()
  let locations = languages.references_at(
    test_model(),
    3,
    LogService(logger=memory),
  )
  assert_eq(locations.length(), 1)
  assert_eq(calls.val, 1)
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, "language.references")
  assert_true(entries[0].details[2] == ("providerIndex", "0"))
  failed.dispose()
  good.dispose()
}

///|
async test "references cancellation and disposal reject late data silently" {
  let languages = Languages()
  let started = @aqueue.Queue(kind=Unbounded)
  let gate = @aqueue.Queue(kind=Unbounded)
  let registration = languages.register_references_provider(
    LanguageId("moonbit"),
    ControlledReferencesProvider::{ started, gate },
  )
  let model = test_model()
  let memory = @log.MemoryLogger()
  let token = @language.CancellationToken::new()
  @async.with_task_group() <| group => {
    let request = group.spawn(() => {
      languages.references_at(model, 3, LogService(logger=memory), token~)
    })
    let observed = started.get()
    assert_true(physical_equal(observed, token))
    token.cancel()
    registration.dispose()
    gate.put(())
    assert_true(request.wait().is_empty())
  }
  assert_eq(memory.entries().length(), 0)
}

///|
async test "references providers start concurrently and retain registry order" {
  let languages = Languages()
  let model = test_model()
  let started = @aqueue.Queue(kind=Unbounded)
  let completed = @aqueue.Queue(kind=Unbounded)
  let first_gate = @aqueue.Queue(kind=Unbounded)
  let second_gate = @aqueue.Queue(kind=Unbounded)
  let first_target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/first-reference.mbt",
  )
  let second_target = try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/second-reference.mbt",
  )
  let first = languages.register_references_provider(LanguageId("moonbit"), GatedReferencesProvider::{
    id: 0,
    started,
    completed,
    gate: first_gate,
    location: { uri: first_target, range: Range(2, 1, 2, 4) },
  })
  let second = languages.register_references_provider(LanguageId("moonbit"), GatedReferencesProvider::{
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
      languages.references_at(
        model,
        3,
        LogService(),
        run_tasks=run_references_test_tasks_concurrently,
      )
    })
    match @async.with_timeout_opt(1000, () => started.get()) {
      Some(id) => observed_starts.push(id)
      None => ()
    }
    match @async.with_timeout_opt(1000, () => started.get()) {
      Some(id) => observed_starts.push(id)
      None => ()
    }
    second_gate.put(())
    match @async.with_timeout_opt(1000, () => completed.get()) {
      Some(id) => observed_completions.push(id)
      None => ()
    }
    first_gate.put(())
    match @async.with_timeout_opt(1000, () => completed.get()) {
      Some(id) => observed_completions.push(id)
      None => ()
    }
    let locations = request.wait()
    assert_eq(locations.length(), 2)
    assert_eq(locations[0].uri.to_string(), second_target.to_string())
    assert_eq(locations[1].uri.to_string(), first_target.to_string())
  }
  assert_eq(observed_starts.length(), 2)
  assert_true(observed_starts.contains(0))
  assert_true(observed_starts.contains(1))
  assert_eq(observed_completions, [1, 0])
  first.dispose()
  second.dispose()
}
