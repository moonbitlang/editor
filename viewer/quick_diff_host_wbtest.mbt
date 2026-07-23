// Headless end-to-end tests for the quick-diff contribution: service
// original → piediff-backed computer → gutter decorations on the model,
// through the registered `quickDiff.decorator` contribution.

///|
/// The gutter decorations the quick-diff contribution currently maintains on
/// the viewer's model, rendered `"<range> <linesDecorationsClassName>"`.
fn quick_diff_gutter_decorations(viewer : Viewer) -> Array[String] {
  guard viewer.get_model() is Some(model) else { return [] }
  let rendered : Array[String] = []
  for decoration in model.get_all_decorations() {
    match decoration.options.lines_decorations_class_name {
      Some(class_name) =>
        if class_name.contains("dirty-diff") {
          rendered.push(decoration.range.to_string() + " " + class_name)
        }
      None => ()
    }
  }
  rendered
}

///|
test "quick diff: stored original decorates the gutter on model attach" {
  let backings = RootTestServiceBackings::new()
  let quick_diff = backings.quick_diff
  let viewer = Viewer::Viewer(services=backings.services)
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  quick_diff.set_original_content(
    resource,
    Some(["a", "old", "b", "tail"].join("\n")),
  )
  // test_model builds its TextModel on the same inmemory://model/test-model
  // resource the service was primed with.
  viewer.set_model(Some(test_model("a\nnew\nb\ninserted\ntail")))
  assert_eq(
    quick_diff_gutter_decorations(viewer).join("; "),
    "[2,1 -> 2,1] dirty-diff-glyph dirty-diff-modified primary; " +
    "[4,1 -> 4,1] dirty-diff-glyph dirty-diff-added primary",
  )
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: original arriving after attach updates, clearing removes" {
  let backings = RootTestServiceBackings::new()
  let quick_diff = backings.quick_diff
  let viewer = Viewer::Viewer(services=backings.services)
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  viewer.set_model(Some(test_model("a\nb")))
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  // The service event re-decorates the already-attached model. The
  // decorator requests the MAX_VALUE column and the model validates it down
  // to the end of line 1 ("a" → column 2), as Monaco's deltaDecorations
  // does.
  quick_diff.set_original_content(resource, Some("a\nx\nb"))
  assert_eq(
    quick_diff_gutter_decorations(viewer).join("; "),
    "[1,2 -> 1,2] dirty-diff-glyph dirty-diff-deleted primary",
  )
  // Clearing the original clears the gutter.
  quick_diff.set_original_content(resource, None)
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: an original for another resource does not decorate" {
  let backings = RootTestServiceBackings::new()
  let quick_diff = backings.quick_diff
  let viewer = Viewer::Viewer(services=backings.services)
  let other = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/other-model",
  )
  viewer.set_model(Some(test_model("a\nb")))
  quick_diff.set_original_content(other, Some("a\nx\nb"))
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: identical original decorates nothing" {
  let backings = RootTestServiceBackings::new()
  let quick_diff = backings.quick_diff
  let viewer = Viewer::Viewer(services=backings.services)
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  quick_diff.set_original_content(resource, Some("a\nb"))
  viewer.set_model(Some(test_model("a\nb")))
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: one central state follows model swap, removal, and reattach" {
  let backings = RootTestServiceBackings::new()
  let quick_diff = backings.quick_diff
  let viewer = Viewer::Viewer(services=backings.services)
  let state = viewer.quick_diff_contribution().unwrap()
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  let first = test_model("a\nfirst\ntail")
  let second = test_model("a\nsecond\ntail")
  quick_diff.set_original_content(resource, Some("a\nold\ntail"))
  viewer.set_model(Some(first))
  assert_true(state.collection.length() > 0)
  assert_true(first.get_all_decorations().length() > 0)
  viewer.set_model(Some(second))
  assert_true(physical_equal(state, viewer.quick_diff_contribution().unwrap()))
  assert_eq(first.get_all_decorations().length(), 0)
  assert_true(second.get_all_decorations().length() > 0)
  viewer.set_model(None)
  assert_eq(state.collection.length(), 0)
  assert_eq(second.get_all_decorations().length(), 0)
  viewer.set_model(Some(first))
  assert_true(physical_equal(state, viewer.quick_diff_contribution().unwrap()))
  assert_true(first.get_all_decorations().length() > 0)
  viewer.dispose()
  first.dispose()
  second.dispose()
  backings.dispose()
}

///|
test "quick diff: disposal window is live and later service events are silent" {
  let backings = RootTestServiceBackings::new()
  let quick_diff = backings.quick_diff
  let viewer = Viewer::Viewer(services=backings.services)
  let state = viewer.quick_diff_contribution().unwrap()
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  let model = test_model("a\nnew\ntail")
  quick_diff.set_original_content(resource, Some("a\nold\ntail"))
  viewer.set_model(Some(model))
  assert_true(state.collection.length() > 0)
  let original_change_deliveries = Ref(0)
  state.listeners.push(
    quick_diff.on_did_change_original(_ => original_change_deliveries.val += 1),
  )
  let callback_seen = Ref(false)
  let contribution_live_in_callback = Ref(false)
  viewer.on_did_dispose(() => {
    callback_seen.val = true
    contribution_live_in_callback.val = viewer.contributions.lookup(
        "quickDiff.decorator",
      )
      is Some(_)
    // Contribution listeners are intentionally live during `onDidDispose`;
    // with the model already detached this synchronous service emission is a
    // guarded no-op.
    quick_diff.set_original_content(resource, Some("replacement"))
  })
  |> ignore
  viewer.dispose()
  assert_true(callback_seen.val)
  assert_true(contribution_live_in_callback.val)
  assert_eq(original_change_deliveries.val, 1)
  assert_eq(state.collection.length(), 0)
  quick_diff.set_original_content(resource, Some("after dispose"))
  assert_eq(original_change_deliveries.val, 1)
  assert_eq(state.collection.length(), 0)
  model.dispose()
  backings.dispose()
}
