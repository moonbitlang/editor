///|
test "ViewerMount represents all headless and mounted model shapes" {
  let headless = Viewer::Viewer()
  let headless_model = test_model("headless")
  assert_true(headless.mount is Headless)
  assert_true(headless.get_model() is None)
  assert_true(headless.get_view() is None)
  assert_false(headless.mount.has_pending_render())
  headless.set_model(Some(headless_model))
  assert_true(headless.mount is Headless)
  assert_true(headless.get_model() is Some(_))
  assert_true(headless.current_browser_data() is None)
  assert_false(headless.mount.has_pending_render())
  headless.dispose()
  headless_model.dispose()

  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let mounted = Viewer::Viewer()
  defer mounted.dispose()
  let mounted_model = test_model("mounted")
  defer mounted_model.dispose()
  let host = @rdom.document().create_element("div")
  mounted.attach(host)
  assert_true(mounted.mount is Mounted(_))
  assert_true(mounted.get_model() is None)
  assert_true(mounted.get_view() is None)
  guard mounted.mount is Mounted(mounted_state) else {
    fail("attached Viewer did not publish Mounted state")
  }
  guard mounted_state.placeholder is Some(placeholder) else {
    fail("mounted no-model Viewer lost its placeholder pair")
  }
  assert_true(
    @base_browser.element_contains(mounted_state.container, placeholder.root),
  )
  mounted.set_model(Some(mounted_model))
  assert_true(mounted.mount is Mounted(_))
  assert_true(mounted.get_model() is Some(_))
  assert_true(mounted.current_browser_data() is Some(_))
  assert_false(
    @base_browser.element_contains(mounted_state.container, placeholder.root),
  )
}

///|
test "mount keeps one host and one placeholder pair across detach" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  defer viewer.dispose()
  let first = test_model("first")
  defer first.dispose()
  let second = test_model("second")
  defer second.dispose()
  let host = @rdom.document().create_element("div")
  let ignored_host = @rdom.document().create_element("div")
  viewer.attach(host)
  viewer.attach(ignored_host)
  assert_true(same_mounted_test_element(viewer.get_container_dom_node(), host))
  assert_eq(mounted_test_child_count(host), 1)
  assert_eq(mounted_test_child_count(ignored_host), 0)
  guard viewer.mount is Mounted(mounted) else {
    fail("attached Viewer did not publish Mounted state")
  }
  guard mounted.placeholder is Some(placeholder) else {
    fail("attached Viewer did not publish a complete placeholder")
  }
  let placeholder_root = placeholder.root
  let placeholder_text = placeholder.text

  // Attach owns exactly one coalesced no-model frame. Theme propagation is
  // synchronous; placeholder text is painted by that frame.
  viewer.layout()
  viewer.layout()
  assert_true(mounted.has_pending_render())
  assert_eq(mounted_test_frame_count(), 1)
  viewer.update_options(
    viewer
    .get_options()
    .with_theme("mount-test-theme")
    .with_placeholder("no model"),
  )
  assert_eq(placeholder_root.get_attribute("data-theme"), "mount-test-theme")
  flush_mounted_test_frames()
  assert_false(mounted.has_pending_render())
  assert_eq(mounted_test_node_value(placeholder_text), "no model")

  viewer.set_model(Some(first))
  assert_eq(mounted_test_child_count(host), 1)
  assert_false(@base_browser.element_contains(host, placeholder_root))
  guard mounted.placeholder is Some(installed_pair) else {
    fail("model attach discarded the retained placeholder pair")
  }
  assert_true(
    same_mounted_test_element(installed_pair.root, placeholder_root) &&
    same_mounted_test_element(installed_pair.text, placeholder_text),
  )

  viewer.focus()
  assert_true(viewer.has_text_focus())
  viewer.set_model(Some(second))
  assert_true(viewer.has_text_focus())
  assert_true(viewer.get_model().unwrap().same(second))
  assert_eq(mounted_test_child_count(host), 1)
  assert_false(@base_browser.element_contains(host, placeholder_root))
  let focus_seen_in_model_event = Ref(true)
  let subscription = viewer.on_did_change_model(_ => {
    focus_seen_in_model_event.val = viewer.has_text_focus()
  })
  viewer.set_model(None)
  assert_false(focus_seen_in_model_event.val)
  assert_false(viewer.has_text_focus())
  assert_eq(mounted_test_child_count(host), 1)
  assert_true(@base_browser.element_contains(host, placeholder_root))
  guard mounted.placeholder is Some(restored_pair) else {
    fail("ordinary detach did not retain the placeholder pair")
  }
  assert_true(
    same_mounted_test_element(restored_pair.root, placeholder_root) &&
    same_mounted_test_element(restored_pair.text, placeholder_text),
  )
  assert_eq(restored_pair.root.get_attribute("data-theme"), "mount-test-theme")
  subscription.dispose()
}

///|
test "mounted scheduler clears publication before a reentrant schedule" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  defer viewer.dispose()
  let host = @rdom.document().create_element("div")
  viewer.attach(host)
  flush_mounted_test_frames()
  guard viewer.mount is Mounted(mounted) else {
    fail("attached Viewer did not publish Mounted state")
  }
  let calls = Ref(0)
  let slot_was_clear = Ref(true)
  mounted.schedule_render(() => {
    slot_was_clear.val = slot_was_clear.val && !mounted.has_pending_render()
    calls.val += 1
    mounted.schedule_render(() => {
      slot_was_clear.val = slot_was_clear.val && !mounted.has_pending_render()
      calls.val += 1
    })
  })
  assert_true(mounted.has_pending_render())
  assert_eq(mounted_test_frame_count(), 1)
  flush_mounted_test_frames()
  assert_eq(calls.val, 2)
  assert_true(slot_was_clear.val)
  assert_false(mounted.has_pending_render())
}

///|
test "mounted render joins a strict-next tick at priority 100" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  defer viewer.dispose()
  let host = @rdom.document().create_element("div")
  viewer.attach(host)
  flush_mounted_test_frames()
  guard viewer.mount is Mounted(mounted) else {
    fail("attached Viewer did not publish Mounted state")
  }
  let events : Array[String] = []
  @base_browser.schedule_at_next_animation_frame(
    () => {
      events.push("tick")
      mounted.schedule_render(() => events.push("render-100"))
      @base_browser.schedule_at_next_animation_frame(() => {
        events.push("next-tick")
      })
      |> ignore
    },
    priority=200,
  )
  |> ignore
  @base_browser.schedule_at_next_animation_frame(
    () => events.push("before-render-101"),
    priority=101,
  )
  |> ignore
  @base_browser.schedule_at_next_animation_frame(
    () => events.push("after-render-99"),
    priority=99,
  )
  |> ignore
  assert_eq(mounted_test_frame_count(), 1)
  run_one_mounted_test_frame()
  assert_true(
    events == ["tick", "before-render-101", "render-100", "after-render-99"],
  )
  assert_eq(mounted_test_frame_count(), 1)
  run_one_mounted_test_frame()
  assert_true(events.last() == Some("next-tick"))
}

///|
test "two mounted Viewers share one request and isolate cancellation" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let first = Viewer::Viewer()
  defer first.dispose()
  let second = Viewer::Viewer()
  defer second.dispose()
  first.attach(@rdom.document().create_element("div"))
  second.attach(@rdom.document().create_element("div"))
  flush_mounted_test_frames()
  guard first.mount is Mounted(first_mounted) else {
    fail("first Viewer did not publish Mounted state")
  }
  guard second.mount is Mounted(second_mounted) else {
    fail("second Viewer did not publish Mounted state")
  }
  let first_model = test_model(long_document(100))
  let second_model = test_model(long_document(100))
  first.set_model(Some(first_model))
  second.set_model(Some(second_model))
  first.test_set_viewport(width=800.0, height=180.0)
  second.test_set_viewport(width=800.0, height=180.0)
  first.configuration.clear_measure_request()
  second.configuration.clear_measure_request()
  first.cancel_render_frame()
  second.cancel_render_frame()
  let first_trace : Array[@viewer_testing.ScrollFrameObservation] = []
  let second_trace : Array[@viewer_testing.ScrollFrameObservation] = []
  let first_trace_subscription = @viewer_testing.on_did_observe_scroll_frame(
    first.get_id(),
    observation => first_trace.push(observation),
  )
  let second_trace_subscription = @viewer_testing.on_did_observe_scroll_frame(
    second.get_id(),
    observation => second_trace.push(observation),
  )
  first.set_scroll_top(18.0)
  second.set_scroll_top(36.0)
  assert_eq(first_trace.length(), 1)
  assert_eq(second_trace.length(), 1)
  assert_eq(first_trace[0].viewer_id, first.get_id())
  assert_eq(first_trace[0].scroll_top, 18.0)
  assert_eq(second_trace[0].viewer_id, second.get_id())
  assert_eq(second_trace[0].scroll_top, 36.0)
  first.cancel_render_frame()
  second.cancel_render_frame()
  first_trace_subscription.dispose()
  second_trace_subscription.dispose()
  let events : Array[String] = []
  first_mounted.schedule_render(() => events.push("first"))
  second_mounted.schedule_render(() => events.push("second"))
  assert_eq(mounted_test_frame_count(), 1)
  run_one_mounted_test_frame()
  assert_true(events == ["first", "second"])

  events.clear()
  first_mounted.schedule_render(() => events.push("disposed-first"))
  second_mounted.schedule_render(() => events.push("live-second"))
  assert_eq(mounted_test_frame_count(), 1)
  first.dispose()
  run_one_mounted_test_frame()
  assert_true(events == ["live-second"])
  assert_false(first_mounted.has_pending_render())
  assert_false(second_mounted.has_pending_render())
  second.dispose()
  first_model.dispose()
  second_model.dispose()
}

///|
test "mounted scroll trace publishes committed axis state by viewer id" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  defer viewer.dispose()
  let model = test_model(long_document(100))
  defer model.dispose()
  viewer.attach(@rdom.document().create_element("div"))
  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=800.0, height=180.0)
  viewer.configuration.clear_measure_request()
  viewer.cancel_render_frame()

  let observations : Array[@viewer_testing.ScrollFrameObservation] = []
  let subscription = @viewer_testing.on_did_observe_scroll_frame(
    viewer.get_id(),
    observation => observations.push(observation),
  )
  defer subscription.dispose()
  viewer.set_scroll_top(18.0)
  assert_eq(observations.length(), 1)
  assert_eq(observations[0].phase, StateCommitted)
  assert_eq(observations[0].scroll_top, 18.0)
  assert_eq(mounted_test_frame_count(), 1)
  assert_eq(observations[0].viewer_id, viewer.get_id())
  assert_eq(observations[0].scroll_left, 0.0)
  viewer.cancel_render_frame()
}

///|
priv enum PendingSmoothExit {
  ReplaceModel
  DetachModel
  DisposeViewer
}

///|
fn assert_pending_smooth_exit_cancels(exit : PendingSmoothExit) -> Unit raise {
  let viewer = Viewer::Viewer(
    options=ViewerOptions(smooth_scrolling=true, font_size=12, line_height=18),
  )
  let first = test_model(
    "01\n02\n03\n04\n05\n06\n07\n08\n09\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20",
  )
  let replacement = test_model("replacement")
  viewer.attach(@rdom.document().create_element("div"))
  viewer.set_model(Some(first))
  // This test needs the mounted ViewModel and held native queue, not a DOM
  // measurement pass from the intentionally minimal fake document.
  viewer.cancel_render_frame()
  guard viewer.get_view_model() is Some(old_view_model) else {
    fail("mounted Viewer did not install its ViewModel")
  }
  let observations : Array[@viewer_testing.ScrollFrameObservation] = []
  let subscription = @viewer_testing.on_did_observe_scroll_frame(
    viewer.get_id(),
    observation => observations.push(observation),
  )
  defer subscription.dispose()
  old_view_model.view_layout.scroll_to_smooth(scroll_top=90.0)
  assert_true(old_view_model.view_layout.has_pending_scroll_animation())
  assert_eq(mounted_test_frame_count(), 1)
  match exit {
    ReplaceModel => viewer.set_model(Some(replacement))
    DetachModel => viewer.set_model(None)
    DisposeViewer => viewer.dispose()
  }
  // The assertion targets the retired model's smooth item. Cancel the new
  // model/placeholder paint so this minimal DOM fixture only drains canceled
  // queue entries after the lifecycle transition.
  viewer.cancel_render_frame()
  assert_false(old_view_model.view_layout.has_pending_scroll_animation())
  run_one_mounted_test_frame()
  assert_eq(old_view_model.view_layout.position().scroll_top, 0.0)
  assert_true(observations.is_empty())
  viewer.dispose()
  first.dispose()
  replacement.dispose()
}

///|
test "model replacement detach and disposal cancel pending smooth frames" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  assert_pending_smooth_exit_cancels(ReplaceModel)
  assert_pending_smooth_exit_cancels(DetachModel)
  assert_pending_smooth_exit_cancels(DisposeViewer)
}

///|
test "dispose retains mount and host until and after the dispose event" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  let model = test_model("focused")
  let host = @rdom.document().create_element("div")
  let ignored_after_dispose = @rdom.document().create_element("div")
  viewer.attach(host)
  viewer.set_model(Some(model))
  viewer.focus()
  assert_true(viewer.has_text_focus())
  let event_saw_mounted_host = Ref(false)
  let event_saw_placeholder_pair = Ref(false)
  let event_saw_focus = Ref(false)
  let event_saw_cleared_frame = Ref(false)
  viewer.on_did_dispose(() => {
    match viewer.mount {
      Headless => ()
      Mounted(mounted) => {
        event_saw_mounted_host.val = same_mounted_test_element(
          mounted.container,
          host,
        )
        event_saw_placeholder_pair.val = mounted.placeholder is Some(_)
        event_saw_focus.val = mounted.editor_has_focus
        event_saw_cleared_frame.val = !mounted.has_pending_render()
      }
    }
  })
  |> ignore

  viewer.dispose()
  assert_true(event_saw_mounted_host.val)
  assert_true(event_saw_placeholder_pair.val)
  assert_true(event_saw_focus.val)
  assert_true(event_saw_cleared_frame.val)
  guard viewer.mount is Mounted(disposed_mount) else {
    fail("disposed mounted Viewer transitioned back to Headless")
  }
  assert_true(same_mounted_test_element(disposed_mount.container, host))
  assert_true(disposed_mount.placeholder is None)
  assert_false(disposed_mount.has_pending_render())
  assert_false(disposed_mount.editor_has_focus)
  assert_eq(mounted_test_child_count(host), 0)
  assert_true(same_mounted_test_element(viewer.get_container_dom_node(), host))

  // Both the ordinary second attach and attach-after-dispose are ignored;
  // the original caller host remains the only retained container.
  viewer.attach(ignored_after_dispose)
  assert_true(same_mounted_test_element(viewer.get_container_dom_node(), host))
  assert_eq(mounted_test_child_count(ignored_after_dispose), 0)
  assert_false(model.is_disposed())
  model.dispose()
}
