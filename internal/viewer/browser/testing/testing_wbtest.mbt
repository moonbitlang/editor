///|
fn test_model(name : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="browser-testing",
      path="/\{name}.mbt",
    ),
    "\{name}.mbt",
    "moonbit",
    1,
    "revision-1",
    "one\ntwo",
  )
}

///|
test "observations are isolated by viewer id and disposable" {
  let first_model = test_model("first")
  defer first_model.dispose()
  let second_model = test_model("second")
  defer second_model.dispose()
  let first_registration = register_viewer(
    "observations-first",
    has_model=() => true,
    set_hidden_areas=(_ranges, _source, _force) => (),
  )
  defer first_registration.dispose()
  let second_registration = register_viewer(
    "observations-second",
    has_model=() => true,
    set_hidden_areas=(_ranges, _source, _force) => (),
  )
  defer second_registration.dispose()
  let build_models : Array[Int] = []
  let build_counts : Array[Int] = []
  let render_facts : Array[(Int, Int, Bool)] = []
  let hover_facts : Array[(Bool, String)] = []
  let first_build = on_did_build_view_model("observations-first", observation => {
    build_models.push(observation.model.identity())
    build_counts.push(observation.token_count)
  })
  let first_render = on_did_render_model("observations-first", observation => {
    render_facts.push(
      (observation.line_count, observation.rendered_lines, observation.fresh),
    )
  })
  let first_hover = on_did_resolve_hover("observations-first", observation => {
    hover_facts.push((observation.ok, observation.revision))
  })
  defer first_render.dispose()
  defer first_hover.dispose()
  publish_view_model_built("observations-second", {
    model: second_model,
    line_count: 2,
    token_count: 20,
    tokenize_ms: 1.0,
    build_ms: 2.0,
  })
  publish_view_model_built("observations-first", {
    model: first_model,
    line_count: 2,
    token_count: 7,
    tokenize_ms: 3.0,
    build_ms: 4.0,
  })
  publish_model_rendered("observations-first", {
    model: first_model,
    line_count: 2,
    rendered_lines: 2,
    patch_ms: 5.0,
    fresh: true,
  })
  publish_hover_resolved("observations-first", {
    ok: true,
    revision: "revision-1",
  })
  assert_true(build_models == [first_model.identity()])
  assert_true(build_counts == [7])
  assert_true(render_facts == [(2, 2, true)])
  assert_true(hover_facts == [(true, "revision-1")])
  first_build.dispose()
  first_build.dispose()
  publish_view_model_built("observations-first", {
    model: first_model,
    line_count: 2,
    token_count: 99,
    tokenize_ms: 0.0,
    build_ms: 0.0,
  })
  assert_true(build_counts == [7])
}

///|
test "controls and replacement cleanup are deterministic" {
  let present = Ref(true)
  let captured_ranges : Array[@base_common.Range] = []
  let captured_source : Ref[String?] = Ref(None)
  let captured_force = Ref(false)
  let old_registration = register_viewer(
    "controls-reused-id",
    has_model=() => false,
    set_hidden_areas=(_ranges, _source, _force) => (),
  )
  let old_events = Ref(0)
  let old_subscription = on_did_resolve_hover("controls-reused-id", _ => {
    old_events.val += 1
  })
  let replacement = register_viewer(
    "controls-reused-id",
    has_model=() => present.val,
    set_hidden_areas=(ranges, source, force) => {
      captured_ranges.clear()
      captured_ranges.append(ranges)
      captured_source.val = source
      captured_force.val = force
    },
  )
  defer replacement.dispose()
  old_registration.dispose()
  old_registration.dispose()
  assert_true(has_model("controls-reused-id"))
  present.val = false
  assert_false(has_model("controls-reused-id"))
  assert_true(
    set_hidden_areas(
      "controls-reused-id",
      [Range(2, 1, 3, 1)],
      source="folding",
      force_update=true,
    ),
  )
  assert_eq(captured_ranges.length(), 1)
  assert_eq(captured_ranges[0].start_line_number, 2)
  assert_eq(captured_source.val, Some("folding"))
  assert_true(captured_force.val)
  publish_hover_resolved("controls-reused-id", {
    ok: true,
    revision: "replacement",
  })
  assert_eq(old_events.val, 0)
  old_subscription.dispose()
  replacement.dispose()
  replacement.dispose()
  assert_false(has_model("controls-reused-id"))
  assert_false(set_hidden_areas("controls-reused-id", [Range(1, 1, 1, 1)]))
  unregister_viewer("controls-reused-id")
}

///|
test "subscriptions to missing ids are inert" {
  let calls = Ref(0)
  let subscription = on_did_resolve_hover("never-registered", _ => {
    calls.val += 1
  })
  subscription.dispose()
  subscription.dispose()
  publish_hover_resolved("never-registered", { ok: false, revision: "missing" })
  assert_eq(calls.val, 0)
  assert_false(has_model("never-registered"))
}

///|
test "scroll frame observations preserve order isolation and lifetimes" {
  let first_registration = register_viewer(
    "scroll-trace-first",
    has_model=() => true,
    set_hidden_areas=(_ranges, _source, _force) => (),
  )
  let second_registration = register_viewer(
    "scroll-trace-second",
    has_model=() => true,
    set_hidden_areas=(_ranges, _source, _force) => (),
  )
  defer second_registration.dispose()

  // A registered viewer without a listener is the ordinary disabled state.
  // The primitive publisher constructs no observation before its
  // `has_listeners` guard.
  publish_scroll_frame("scroll-trace-first", StateCommitted, 1.0, 2.0)

  let first_events : Array[ScrollFrameObservation] = []
  let second_events : Array[ScrollFrameObservation] = []
  let first_subscription = on_did_observe_scroll_frame("scroll-trace-first", event => {
    first_events.push(event)
  })
  let second_subscription = on_did_observe_scroll_frame("scroll-trace-second", event => {
    second_events.push(event)
  })
  defer second_subscription.dispose()

  // Raw duplicates and phase order are intentional evidence, not coalesced
  // by the registry.
  publish_scroll_frame("scroll-trace-first", StateCommitted, 10.0, 4.0)
  publish_scroll_frame("scroll-trace-first", StateCommitted, 10.0, 4.0)
  publish_scroll_frame("scroll-trace-first", RenderStarted, 10.0, 4.0)
  publish_scroll_frame("scroll-trace-first", RenderFinished, 10.0, 4.0)
  publish_scroll_frame("scroll-trace-second", StateCommitted, 20.0, 8.0)
  assert_eq(first_events.length(), 4)
  assert_true(
    first_events.map(event => event.phase) ==
    [StateCommitted, StateCommitted, RenderStarted, RenderFinished],
  )
  assert_true(
    first_events.map(event => event.viewer_id) ==
    [
      "scroll-trace-first", "scroll-trace-first", "scroll-trace-first", "scroll-trace-first",
    ],
  )
  assert_eq(second_events.length(), 1)
  assert_eq(second_events[0].viewer_id, "scroll-trace-second")

  first_subscription.dispose()
  first_subscription.dispose()
  publish_scroll_frame("scroll-trace-first", StateCommitted, 30.0, 12.0)
  assert_eq(first_events.length(), 4)

  // Re-registration disposes old listeners; an older generation handle
  // cannot remove the replacement.
  let replacement = register_viewer(
    "scroll-trace-first",
    has_model=() => true,
    set_hidden_areas=(_ranges, _source, _force) => (),
  )
  defer replacement.dispose()
  first_registration.dispose()
  let replacement_events : Array[ScrollFrameObservation] = []
  let replacement_subscription = on_did_observe_scroll_frame(
    "scroll-trace-first",
    event => replacement_events.push(event),
  )
  defer replacement_subscription.dispose()
  publish_scroll_frame("scroll-trace-first", RenderStarted, 40.0, 16.0)
  assert_eq(replacement_events.length(), 1)

  let missing_calls = Ref(0)
  let missing = on_did_observe_scroll_frame("scroll-trace-missing", _ => {
    missing_calls.val += 1
  })
  missing.dispose()
  publish_scroll_frame("scroll-trace-missing", StateCommitted, 50.0, 20.0)
  assert_eq(missing_calls.val, 0)
}
