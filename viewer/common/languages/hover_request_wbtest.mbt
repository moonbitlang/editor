///|
priv struct RecordingHoverProvider {
  text : String
  calls : Ref[Int]
  observed_tokens : Array[@language.CancellationToken]
  empty : Bool
}

///|
priv struct NoneHoverProvider {
  calls : Ref[Int]
  observed_tokens : Array[@language.CancellationToken]
}

///|
impl @language.HoverProvider for NoneHoverProvider with fn provide_hover(
  self,
  _model,
  _position,
  token,
) {
  self.calls.val += 1
  self.observed_tokens.push(token)
  None
}

///|
impl @language.HoverProvider for RecordingHoverProvider with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  self.calls.val += 1
  self.observed_tokens.push(token)
  let offset = model.get_offset_at(position)
  Some({
    range: model.get_range_at(offset, offset + 1),
    contents: if self.empty {
      []
    } else {
      [PlainText(self.text)]
    },
  })
}

///|
priv struct ControlledHoverProvider {
  started : @aqueue.Queue[@language.CancellationToken]
  gate : @aqueue.Queue[Unit]
  fail_when_cancelled : Bool
}

///|
priv suberror HoverTestProviderError {
  HoverTestProviderError
}

///|
impl @language.HoverProvider for ControlledHoverProvider with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  self.started.put(token)
  self.gate.get()
  if self.fail_when_cancelled && token.is_cancellation_requested() {
    raise HoverTestProviderError
  }
  let offset = model.get_offset_at(position)
  Some({
    range: model.get_range_at(offset, offset + 1),
    contents: [PlainText("late")],
  })
}

///|
async test "hover forwards caller token and skips empty provider results" {
  let languages = Languages()
  let empty_calls = Ref(0)
  let empty_tokens : Array[@language.CancellationToken] = []
  let good_calls = Ref(0)
  let good_tokens : Array[@language.CancellationToken] = []
  let empty = RecordingHoverProvider::{
    text: "empty",
    calls: empty_calls,
    observed_tokens: empty_tokens,
    empty: true,
  }
  let good = RecordingHoverProvider::{
    text: "good",
    calls: good_calls,
    observed_tokens: good_tokens,
    empty: false,
  }
  let empty_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    empty,
  )
  let good_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    good,
  )
  let token = @language.CancellationToken::new()
  let hover = languages.hover_at(test_model(), 3, LogService(), token~)
  assert_hover_text(hover, "good")
  assert_eq(empty_calls.val, 1)
  assert_eq(good_calls.val, 1)
  assert_true(physical_equal(empty_tokens[0], token))
  assert_true(physical_equal(good_tokens[0], token))
  empty_registration.dispose()
  good_registration.dispose()
}

///|
async test "hover skips a provider None result and continues in order" {
  let languages = Languages()
  let none_calls = Ref(0)
  let none_tokens : Array[@language.CancellationToken] = []
  let good_calls = Ref(0)
  let good_tokens : Array[@language.CancellationToken] = []
  let none_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    NoneHoverProvider::{ calls: none_calls, observed_tokens: none_tokens },
  )
  let good_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    RecordingHoverProvider::{
      text: "after-none",
      calls: good_calls,
      observed_tokens: good_tokens,
      empty: false,
    },
  )
  let token = @language.CancellationToken::new()
  let hover = languages.hover_at(test_model(), 3, LogService(), token~)
  assert_hover_text(hover, "after-none")
  assert_eq(none_calls.val, 1)
  assert_eq(good_calls.val, 1)
  assert_true(physical_equal(none_tokens[0], token))
  assert_true(physical_equal(good_tokens[0], token))
  none_registration.dispose()
  good_registration.dispose()
}

///|
async test "hover pre-cancellation avoids provider launch" {
  let languages = Languages()
  let calls = Ref(0)
  let provider = RecordingHoverProvider::{
    text: "unused",
    calls,
    observed_tokens: [],
    empty: false,
  }
  let registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    provider,
  )
  let token = @language.CancellationToken::new()
  token.cancel()
  let hover = languages.hover_at(test_model(), 3, LogService(), token~)
  assert_true(hover is None)
  assert_eq(calls.val, 0)
  registration.dispose()
}

///|
async test "hover cancellation during await is silent and rejects late data" {
  let languages = Languages()
  let started = @aqueue.Queue(kind=Unbounded)
  let gate = @aqueue.Queue(kind=Unbounded)
  let provider = ControlledHoverProvider::{
    started,
    gate,
    fail_when_cancelled: true,
  }
  let registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    provider,
  )
  let memory = @log.MemoryLogger()
  let log_service = @log.LogService(logger=memory)
  let model = test_model()
  let token = @language.CancellationToken::new()
  @async.with_task_group() <| group => {
    let request = group.spawn(() => {
      languages.hover_at(model, 3, log_service, token~)
    })
    let observed_token = started.get()
    assert_true(physical_equal(observed_token, token))
    token.cancel()
    gate.put(())
    assert_true(request.wait() is None)
  }
  assert_eq(memory.entries().length(), 0)
  registration.dispose()
}

///|
async test "hover rejects a registration disposed during await" {
  let languages = Languages()
  let started = @aqueue.Queue(kind=Unbounded)
  let gate = @aqueue.Queue(kind=Unbounded)
  let provider = ControlledHoverProvider::{
    started,
    gate,
    fail_when_cancelled: false,
  }
  let registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    provider,
  )
  let model = test_model()
  @async.with_task_group() <| group => {
    let request = group.spawn(() => languages.hover_at(model, 3, LogService()))
    started.get() |> ignore
    registration.dispose()
    gate.put(())
    assert_true(request.wait() is None)
  }
}
