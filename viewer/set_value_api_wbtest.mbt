///| Headless behavior tests for the `set_value` public API (plan
/// `monaco-set-value-api-port.md`, Tracks D/E) over the `test_viewer`
/// harness: the flush keeps the model / view-model instances (unlike
/// `set_model`'s detach-then-attach), re-fires `onDidChangeModelContent`,
/// marks the rendered content stale, resets the cursor, and the
/// content-change consumers (quick diff, markers) re-derive the decorations
/// the flush destroyed.

///|
test "set_value keeps the model and view model instances" {
  with_test_viewer("one\ntwo", viewer => {
    let model_before = viewer.get_model().unwrap()
    let model_data_generation_before = viewer.model_slot.generation
    viewer.set_value("a\nb\nc")
    assert_true(viewer.get_model().unwrap().same(model_before))
    assert_eq(viewer.model_slot.generation, model_data_generation_before)
    assert_eq(viewer.get_value(), "a\nb\nc")
    assert_eq(viewer.test_view_model().line_count(), 3)
  })
}

///|
test "set_value re-fires onDidChangeModelContent with the flush payload" {
  with_test_viewer("one", viewer => {
    let events : Array[@model.ModelContentChangedEvent] = []
    let _sub = viewer.on_did_change_model_content(e => events.push(e))
    viewer.set_value("two\nthree")
    assert_eq(events.length(), 1)
    assert_eq(events[0].is_flush, true)
    assert_eq(events[0].changes[0].text, "two\nthree")
  })
}

///|
test "set_value without a model is a no-op (cew:490-492)" {
  let viewer = Viewer::Viewer()
  viewer.set_value("anything")
  assert_true(viewer.get_model() is None)
  viewer.dispose()
}

///|
extern "js" fn same_test_model_browser_data(
  left : ModelBrowserData,
  right : ModelBrowserData,
) -> Bool = "(left, right) => left === right"

///|
test "set_value marks mounted rendered content stale on the same browser data" {
  with_mounted_test_viewer("one\ntwo", viewer => {
    let browser = viewer.current_browser_data().unwrap()
    browser.rendered_window = Some({ start: 1, end: 2 })
    viewer.set_value("a")
    assert_true(browser.rendered_window is None)
    assert_true(
      same_test_model_browser_data(
        viewer.current_browser_data().unwrap(),
        browser,
      ),
    )
  })
}

///|
test "set_value preserves the headless model slot without browser state" {
  with_test_viewer("one\ntwo", viewer => {
    guard viewer.model_slot.current is Some(before) else {
      fail("headless model data missing before set_value")
    }
    assert_true(before.browser is None)
    viewer.set_value("a")
    guard viewer.model_slot.current is Some(after) else {
      fail("headless model data missing after set_value")
    }
    assert_true(after.browser is None)
  })
}

///|
test "set_value resets the cursor to the origin" {
  with_test_viewer("one\ntwo\nthree", viewer => {
    viewer.test_cursor().move_to(Position(3, 2), false) |> ignore
    assert_true(viewer.get_position().unwrap() == Position(3, 2))
    viewer.set_value("a\nb")
    assert_true(viewer.get_position().unwrap() == Position(1, 1))
  })
}

///|
test "quick diff re-renders its gutter decorations after a flush (Track E)" {
  let backings = RootTestServiceBackings::new()
  let viewer = Viewer::Viewer(services=backings.services)
  let model = test_model("alpha\nbravo")
  backings.quick_diff.set_original_content(model.uri, Some("alpha\nbravo"))
  viewer.set_model(Some(model))
  // identical content: no dirty-diff decorations yet
  assert_eq(model.get_all_decorations().length(), 0)
  viewer.set_value("alpha\nCHANGED")
  // the contribution's content-change subscription re-ran the decorator
  // against the new snapshot
  assert_eq(model.get_all_decorations().length(), 1)
  viewer.dispose()
  backings.dispose()
}

///|
test "marker decorations re-seed after a flush (Track E)" {
  let backings = RootTestServiceBackings::new()
  let viewer = Viewer::Viewer(services=backings.services)
  let model = test_model("alpha\nbravo")
  // Host diagnostics may predate attachment. Acquiring the model seeds them;
  // ordinary detach and set_value never clear the host-owned store.
  backings.markers.change_one("owner", model.uri, [
    MarkerData(
      severity=Error,
      message="broken",
      start_line_number=1,
      start_column=1,
      end_line_number=1,
      end_column=3,
    ),
  ])
  viewer.set_model(Some(model))
  assert_eq(model.get_all_decorations().length(), 1)
  viewer.set_value("alpha\nCHANGED")
  // The service's one per-identity content watch re-seeded the decoration;
  // Viewer content delivery does not acquire another lease.
  assert_eq(model.get_all_decorations().length(), 1)
  viewer.dispose()
  backings.dispose()
}
