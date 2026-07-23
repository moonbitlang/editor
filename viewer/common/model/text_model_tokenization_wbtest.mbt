///| TextModel-owned tokenization state, size policy, and scheduler epochs.

///|
priv struct ModelTokenizationCountingTokenizer {
  calls : Ref[Int]
}

///|
impl @syntax.LineTokenizer for ModelTokenizationCountingTokenizer with fn initial_state(
  _self,
) {
  TokenizerState("model-tokenization")
}

///|
impl @syntax.LineTokenizer for ModelTokenizationCountingTokenizer with fn tokenize_line(
  self,
  _line_text,
  state,
) {
  self.calls.val += 1
  ([], state)
}

///|
fn tokenization_model(text : String, language_id : String) -> TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="tokenization-model",
      path="/model.mbt",
    ),
    "model.mbt",
    language_id,
    1,
    "",
    text,
  )
}

///|
fn tokenization_model_with_resolver(
  text : String,
  language_id : String,
  resolve_support : (String) -> InternalTokenizationSupportAdapter?,
) -> (TextModel, Array[String]) {
  let reported : Array[String] = []
  let model = new_text_model(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="tokenization-model",
      path="/model.mbt",
    ),
    "model.mbt",
    language_id,
    1,
    "",
    text,
    Some(resolve_support),
    Some(message => reported.push(message)),
  )
  (model, reported)
}

///|
priv struct ModelIdleTask {
  callback : (TokenizationIdleDeadline) -> Unit
  active : Ref[Bool]
}

///|
priv struct ModelScheduledTask {
  active : Ref[Bool]
}

///|
priv struct ModelTokenizationSchedulerHarness {
  scheduler : TokenizationScheduler
  idle : Array[ModelIdleTask]
  zero : Array[ModelScheduledTask]
  delayed : Array[ModelScheduledTask]
  delay_milliseconds : Array[Int]
}

///|
fn model_tokenization_scheduler_harness() -> ModelTokenizationSchedulerHarness {
  let idle : Array[ModelIdleTask] = []
  let zero : Array[ModelScheduledTask] = []
  let delayed : Array[ModelScheduledTask] = []
  let delay_milliseconds : Array[Int] = []
  let scheduler = TokenizationScheduler(
    idle=callback => {
      let active = Ref(true)
      idle.push({ callback, active })
      @base_common.Disposable::from(() => active.val = false)
    },
    zero_timeout=_callback => {
      let active = Ref(true)
      zero.push({ active, })
      @base_common.Disposable::from(() => active.val = false)
    },
    delay=(milliseconds, _callback) => {
      let active = Ref(true)
      delay_milliseconds.push(milliseconds)
      delayed.push({ active, })
      @base_common.Disposable::from(() => active.val = false)
    },
    now=() => 0.0,
  )
  { scheduler, idle, zero, delayed, delay_milliseconds }
}

///|
fn assert_constructor_large_policy(
  text : String,
  language_id : String,
  expected : Bool,
) -> Unit raise {
  let model = tokenization_model(text, language_id)
  assert_eq(model.is_too_large_for_tokenization(), expected)
  model.dispose()
}

///|
test "large-file tokenization size and line thresholds are strict OR branches" {
  assert_eq(LARGE_FILE_SIZE_THRESHOLD, 20 * 1024 * 1024)
  assert_eq(LARGE_FILE_LINE_COUNT_THRESHOLD, 300 * 1000)

  assert_constructor_large_policy(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD - 1),
    "token-size-below",
    false,
  )
  assert_constructor_large_policy(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD),
    "token-size-equal",
    false,
  )
  assert_constructor_large_policy(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD + 1),
    "token-size-over",
    true,
  )

  assert_constructor_large_policy(
    "\n".repeat(LARGE_FILE_LINE_COUNT_THRESHOLD - 2),
    "token-lines-below",
    false,
  )
  assert_constructor_large_policy(
    "\n".repeat(LARGE_FILE_LINE_COUNT_THRESHOLD - 1),
    "token-lines-equal",
    false,
  )
  assert_constructor_large_policy(
    "\n".repeat(LARGE_FILE_LINE_COUNT_THRESHOLD),
    "token-lines-over",
    true,
  )

  // The predicate is an OR: each one-sided overage above is sufficient, and
  // crossing both boundaries keeps the predicate true (tokenization stays
  // disabled).
  assert_constructor_large_policy(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD + 1) +
    "\n".repeat(LARGE_FILE_LINE_COUNT_THRESHOLD),
    "token-size-and-lines-over",
    true,
  )
}

///|
test "large-file tokenization policy stays constructor-fixed across set_value" {
  let initially_smaller = tokenization_model(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD - 1),
    "token-fixed-smaller",
  )
  initially_smaller.set_value("x".repeat(LARGE_FILE_SIZE_THRESHOLD))
  assert_false(initially_smaller.is_too_large_for_tokenization())
  initially_smaller.set_value("x".repeat(LARGE_FILE_SIZE_THRESHOLD + 1))
  assert_false(initially_smaller.is_too_large_for_tokenization())
  initially_smaller.dispose()

  let initially_equal = tokenization_model(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD),
    "token-fixed-equal",
  )
  initially_equal.set_value("x".repeat(LARGE_FILE_SIZE_THRESHOLD - 1))
  assert_false(initially_equal.is_too_large_for_tokenization())
  initially_equal.set_value("x".repeat(LARGE_FILE_SIZE_THRESHOLD + 1))
  assert_false(initially_equal.is_too_large_for_tokenization())
  initially_equal.dispose()

  let initially_larger = tokenization_model(
    "x".repeat(LARGE_FILE_SIZE_THRESHOLD + 1),
    "token-fixed-larger",
  )
  initially_larger.set_value("x".repeat(LARGE_FILE_SIZE_THRESHOLD))
  assert_true(initially_larger.is_too_large_for_tokenization())
  initially_larger.set_value("x".repeat(LARGE_FILE_SIZE_THRESHOLD - 1))
  assert_true(initially_larger.is_too_large_for_tokenization())
  initially_larger.dispose()
}

///|
test "set_value updates shared token state and token_count stays passive" {
  let calls = Ref(0)
  let language_id = "text-model-live-token-state"
  let registration = @syntax.tokenization_registry.register(language_id, ModelTokenizationCountingTokenizer::{
    calls,
  })
  let model = tokenization_model("old\nvalue", language_id)
  assert_eq(model.tokenization_state.snapshot.val.get_value(), "old\nvalue")
  assert_eq(model.tokenization.token_count(), 2)
  assert_eq(calls.val, 0)

  model.set_value("new\nvalue\nnow")
  assert_eq(
    model.tokenization_state.snapshot.val.get_value(),
    "new\nvalue\nnow",
  )
  assert_eq(model.tokenization_state.snapshot.val.line_count(), 3)
  assert_eq(model.tokenization.get_line_tokens(3).get_line_content(), "now")
  assert_eq(model.tokenization.token_count(), 3)
  assert_eq(calls.val, 0)

  let view = model.on_before_attached()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2 }], true)
  assert_eq(calls.val, 2)
  let before_count = calls.val
  assert_eq(model.tokenization.token_count(), 3)
  assert_eq(calls.val, before_count)
  model.on_before_detached(view)
  model.dispose()
  registration.dispose()
}

///|
test "attached epoch selects first scheduler, retains it, then cancels and clears" {
  let calls = Ref(0)
  let language_id = "text-model-scheduler-epoch"
  let registration = @syntax.tokenization_registry.register(language_id, ModelTokenizationCountingTokenizer::{
    calls,
  })
  let first_scheduler = model_tokenization_scheduler_harness()
  let later_scheduler = model_tokenization_scheduler_harness()
  let model = tokenization_model("one\ntwo\nthree\nfour\nfive", language_id)

  // None starts the epoch without selecting or enqueueing a host scheduler.
  let headless = model.on_before_attached()
  assert_eq(model.get_attached_editor_count(), 1)
  assert_true(model.is_attached_to_editor())
  assert_true(model.tokenization_state.scheduler.val is None)
  assert_true(first_scheduler.idle.is_empty())

  // The first late Some wakes the existing worker exactly once. Incrementing
  // 1 -> 2 must not synthesize another first-attach wake.
  let supplying = model.on_before_attached(scheduler=first_scheduler.scheduler)
  assert_eq(model.get_attached_editor_count(), 2)
  assert_true(model.tokenization_state.scheduler.val is Some(_))
  assert_eq(first_scheduler.idle.length(), 1)
  assert_true(first_scheduler.zero.is_empty())

  // Later Some and None candidates cannot replace the selected scheduler.
  let later = model.on_before_attached(scheduler=later_scheduler.scheduler)
  let another_headless = model.on_before_attached()
  assert_eq(model.get_attached_editor_count(), 4)
  assert_eq(first_scheduler.idle.length(), 1)
  assert_true(later_scheduler.idle.is_empty())
  later.set_visible_lines([{ start_line_number: 3, end_line_number: 3 }], false)
  another_headless.set_visible_lines(
    [{ start_line_number: 5, end_line_number: 5 }],
    false,
  )
  assert_eq(first_scheduler.delayed.length(), 2)
  assert_eq(first_scheduler.delay_milliseconds.length(), 2)
  assert_eq(first_scheduler.delay_milliseconds[0], 50)
  assert_eq(first_scheduler.delay_milliseconds[1], 50)
  assert_true(later_scheduler.delayed.is_empty())

  // Removing the Viewer that supplied the scheduler is nonfinal, so the
  // worker and selected scheduler remain live for headless/sibling views.
  model.on_before_detached(supplying)
  assert_eq(model.get_attached_editor_count(), 3)
  assert_true(first_scheduler.idle[0].active.val)
  assert_true(model.tokenization_state.scheduler.val is Some(_))
  headless.set_visible_lines(
    [{ start_line_number: 1, end_line_number: 1 }],
    false,
  )
  assert_eq(first_scheduler.delayed.length(), 3)
  assert_true(later_scheduler.delayed.is_empty())

  model.on_before_detached(later)
  model.on_before_detached(another_headless)
  assert_eq(model.get_attached_editor_count(), 1)
  assert_true(first_scheduler.idle[0].active.val)
  model.on_before_detached(headless)
  assert_eq(model.get_attached_editor_count(), 0)
  assert_false(model.is_attached_to_editor())
  assert_true(model.tokenization_state.scheduler.val is None)
  assert_false(first_scheduler.idle[0].active.val)
  for task in first_scheduler.delayed {
    assert_false(task.active.val)
  }

  // A hostile host invoking an old epoch callback cannot tokenize or disturb
  // the fresh epoch's coalescing state.
  (first_scheduler.idle[0].callback)(TokenizationIdleDeadline(() => 0.0))
  assert_eq(calls.val, 0)
  let fresh = model.on_before_attached(scheduler=later_scheduler.scheduler)
  assert_eq(later_scheduler.idle.length(), 1)
  assert_true(later_scheduler.idle[0].active.val)
  (first_scheduler.idle[0].callback)(TokenizationIdleDeadline(() => 0.0))
  assert_eq(calls.val, 0)
  assert_true(later_scheduler.idle[0].active.val)
  model.on_before_detached(fresh)
  assert_false(later_scheduler.idle[0].active.val)
  assert_true(model.tokenization_state.scheduler.val is None)

  // A subsequent fresh epoch can select again; model disposal owns worker
  // cancellation and clears the selected scheduler even with a live handle.
  let disposal_handle = model.on_before_attached(
    scheduler=later_scheduler.scheduler,
  )
  ignore(disposal_handle)
  assert_eq(later_scheduler.idle.length(), 2)
  assert_true(later_scheduler.idle[1].active.val)
  model.dispose()
  assert_false(later_scheduler.idle[1].active.val)
  assert_true(model.tokenization_state.scheduler.val is None)
  registration.dispose()
}

///|
test "attached event fires after tokenization only on zero-one and one-zero" {
  let calls = Ref(0)
  let language_id = "text-model-attached-event-boundaries"
  let registration = @syntax.tokenization_registry.register(language_id, ModelTokenizationCountingTokenizer::{
    calls,
  })
  let scheduler = model_tokenization_scheduler_harness()
  let model = tokenization_model("one\ntwo", language_id)
  let observed : Array[String] = []
  let subscription = model.on_did_change_attached(() => {
    let idle_state = if scheduler.idle.is_empty() {
      "none"
    } else if scheduler.idle[0].active.val {
      "active"
    } else {
      "cancelled"
    }
    observed.push("\{model.get_attached_editor_count()}:\{idle_state}")
  })
  assert_true(model.has_listeners())

  let first = model.on_before_attached(scheduler=scheduler.scheduler)
  assert_eq(observed.join(","), "1:active")
  let second = model.on_before_attached()
  assert_eq(observed.join(","), "1:active")
  model.on_before_detached(first)
  assert_eq(observed.join(","), "1:active")
  assert_true(scheduler.idle[0].active.val)
  model.on_before_detached(second)
  assert_eq(observed.join(","), "1:active,0:cancelled")

  // Model disposal owns and releases the event emitter. Disposing the old
  // subscription afterwards is harmless and the ownership query stays false.
  model.dispose()
  assert_false(model.attached_change_emitter.has_listeners())
  subscription.dispose()
  assert_false(model.has_listeners())
  registration.dispose()
}

///|
test "model listener ownership includes token-part listeners through disposal" {
  let model = tokenization_model("one", "text-model-token-listeners")
  assert_false(model.has_listeners())
  let first = model.on_did_change_tokens(_ => ())
  assert_true(model.has_listeners())
  first.dispose()
  assert_false(model.has_listeners())

  let live_at_disposal = model.on_did_change_tokens(_ => ())
  assert_true(model.has_listeners())
  model.dispose()
  assert_false(model.has_listeners())
  live_at_disposal.dispose()
  let after_disposal = model.on_did_change_tokens(_ => ())
  assert_false(model.has_listeners())
  after_disposal.dispose()
  assert_false(model.has_listeners())
}

///|
test "TextModel disposal marks disposed between token part and registered resources" {
  let trace : Array[String] = []
  let is_disposing = Ref(false)
  let tokenization_disposed = Ref(false)
  let is_disposed = Ref(false)

  run_text_model_dispose_sequence(
    set_disposing=value => {
      trace.push(
        "disposing=\{value}:\{is_disposing.val}:" +
        "\{tokenization_disposed.val}:\{is_disposed.val}",
      )
      is_disposing.val = value
    },
    fire_will_dispose=() => {
      trace.push(
        "willDispose:\{is_disposing.val}:" +
        "\{tokenization_disposed.val}:\{is_disposed.val}",
      )
    },
    dispose_tokenization=() => {
      trace.push(
        "tokenization.dispose:\{is_disposing.val}:" +
        "\{tokenization_disposed.val}:\{is_disposed.val}",
      )
      tokenization_disposed.val = true
    },
    set_disposed=() => {
      trace.push(
        "isDisposed=true:\{is_disposing.val}:" +
        "\{tokenization_disposed.val}:\{is_disposed.val}",
      )
      is_disposed.val = true
    },
    dispose_registered_resources=() => {
      trace.push(
        "super.dispose:\{is_disposing.val}:" +
        "\{tokenization_disposed.val}:\{is_disposed.val}",
      )
    },
  )

  assert_eq(
    trace.join(","),
    "disposing=true:false:false:false,willDispose:true:false:false," +
    "tokenization.dispose:true:false:false,isDisposed=true:true:true:false," +
    "super.dispose:true:true:true,disposing=false:true:true:true",
  )
  assert_false(is_disposing.val)
}

///|
test "Some then None scheduler epoch retains supplier until final detach" {
  let calls = Ref(0)
  let language_id = "text-model-scheduler-some-none"
  let registration = @syntax.tokenization_registry.register(language_id, ModelTokenizationCountingTokenizer::{
    calls,
  })
  let scheduler = model_tokenization_scheduler_harness()
  let model = tokenization_model("one\ntwo\nthree", language_id)

  // First Some selects before the 0 -> 1 tokenization notification. The
  // following None increments to two without another wake.
  let supplier = model.on_before_attached(scheduler=scheduler.scheduler)
  assert_eq(scheduler.idle.length(), 1)
  let sibling = model.on_before_attached()
  assert_eq(scheduler.idle.length(), 1)
  assert_eq(model.get_attached_editor_count(), 2)

  // Removing the supplier is nonfinal: the selected scheduler and worker stay
  // alive and the remaining view continues to schedule through that epoch.
  model.on_before_detached(supplier)
  assert_eq(model.get_attached_editor_count(), 1)
  assert_true(scheduler.idle[0].active.val)
  assert_true(model.tokenization_state.scheduler.val is Some(_))
  sibling.set_visible_lines(
    [{ start_line_number: 2, end_line_number: 2 }],
    false,
  )
  assert_eq(scheduler.delayed.length(), 1)

  // Final detach notifies/cancels before clearing the epoch scheduler.
  model.on_before_detached(sibling)
  assert_eq(model.get_attached_editor_count(), 0)
  assert_false(scheduler.idle[0].active.val)
  assert_false(scheduler.delayed[0].active.val)
  assert_true(model.tokenization_state.scheduler.val is None)
  assert_eq(calls.val, 0)
  model.dispose()
  registration.dispose()
}

///|
priv suberror ModelProductionTokenizationError {
  InitialStateFailure
}

///|
test "TextModel reports a failing tokenizer and remains live for later reset" {
  let attempts = Ref(0)
  let tokenizer_calls = Ref(0)
  let (model, reported) = tokenization_model_with_resolver(
    "one\ntwo",
    "text-model-production-error-reporter",
    _ => {
      Some(
        InternalTokenizationSupportAdapter(
          initial_state=() => {
            attempts.val += 1
            if attempts.val == 1 {
              raise ModelProductionTokenizationError::InitialStateFailure
            }
            TokenizerState("healthy")
          },
          tokenize_encoded=(text, _has_eol, _state) => {
            tokenizer_calls.val += 1
            {
              tokens: [0, tag_to_metadata(Plain)],
              end_state: TokenizerState(text),
            }
          },
        ),
      )
    },
  )
  assert_eq(reported.length(), 1)
  assert_true(reported[0].contains("InitialStateFailure"))
  assert_eq(model.get_value(), "one\ntwo")
  assert_eq(tokenizer_calls.val, 0)

  // A later production flush reacquires support after the reported failure;
  // an attached visible range can then tokenize normally.
  model.set_value("still\nlive")
  let view = model.on_before_attached()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2 }], true)
  // One successful reset probes support and then seeds the state store, so
  // the initial-state callback runs twice after the first reported failure.
  assert_eq(attempts.val, 3)
  assert_eq(tokenizer_calls.val, 2)
  assert_eq(model.get_value(), "still\nlive")
  model.on_before_detached(view)
  model.dispose()
}
