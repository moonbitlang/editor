// Headless end-to-end tests for the folding contribution: the
// `FoldingController` chain from `onModelChanged` through the hidden-range
// model into `Viewer::set_hidden_areas` and the view axis.

///|
test "folding: contribution computes indent regions on model attach" {
  with_test_viewer("a\n  b\n  c\nd\n  e", viewer => {
    guard viewer.folding_controller() is Some(controller)
    guard controller.folding_model is Some(folding_model)
    let regions = folding_model.regions()
    assert_eq(regions.length(), 2)
    assert_eq(regions.get_start_line_number(0), 1)
    assert_eq(regions.get_end_line_number(0), 3)
    assert_eq(regions.get_start_line_number(1), 4)
    assert_eq(regions.get_end_line_number(1), 5)
  })
}

///|
test "folding: toggling a region folds its lines out of the view axis" {
  with_test_viewer("a\n  b\n  c\nd\n  e", viewer => {
    let view_model = viewer.test_view_model()
    assert_eq(view_model.line_count(), 5)
    guard viewer.folding_controller() is Some(controller)
    guard controller.folding_model is Some(folding_model)
    guard folding_model.get_region_at_line(1) is Some(region)
    folding_model.toggle_collapse_state([region])
    // Lines 2-3 fold away; the header and the second block stay.
    assert_eq(view_model.line_count(), 3)
    assert_eq(view_model.lines().get_view_line_content(1), "a")
    assert_eq(view_model.lines().get_view_line_content(2), "d")
    debug_inspect(
      view_model.get_hidden_areas(),
      content=(
        #|[
        #|  {
        #|    start_line_number: 2,
        #|    start_column: 1,
        #|    end_line_number: 3,
        #|    end_column: 1,
        #|  },
        #|]
      ),
    )
    // The folded header carries the collapsed chevron + `⋯` + highlight
    // decoration on the model.
    let mut saw_collapsed = false
    for decoration in folding_model.text_model().get_all_decorations() {
      if decoration.options.first_line_decoration_class_name
        is Some("codicon codicon-folding-collapsed") {
        saw_collapsed = true
        assert_true(
          decoration.options.after_content_class_name is Some("inline-folded"),
        )
        assert_eq(decoration.options.class_name, "folded-background")
      }
    }
    assert_true(saw_collapsed)
    // Toggling back restores every line.
    guard folding_model.get_region_at_line(1) is Some(region_again)
    folding_model.toggle_collapse_state([region_again])
    assert_eq(view_model.line_count(), 5)
    assert_eq(view_model.get_hidden_areas().length(), 0)
  })
}

///|
test "folding: fold and unfold actions work off the selection" {
  with_test_viewer("a\n  b\n  c\nd", viewer => {
    let view_model = viewer.test_view_model()
    viewer.set_position(Position(2, 1))
    assert_true(viewer.folding_enabled())
    viewer.folding_fold_action()
    assert_eq(view_model.line_count(), 2)
    // The caret was inside the fold; `onHiddenRangesChanges` snapped it to
    // the header line.
    guard viewer.get_selection() is Some(selection)
    assert_eq(selection.start().line_number, 1)
    viewer.set_position(Position(1, 1))
    viewer.folding_unfold_action()
    assert_eq(view_model.line_count(), 4)
  })
}

///|
test "folding: disabling the option clears folds and detaches the model state" {
  with_test_viewer("a\n  b\n  c\nd", viewer => {
    let view_model = viewer.test_view_model()
    guard viewer.folding_controller() is Some(controller)
    guard controller.folding_model is Some(folding_model)
    guard folding_model.get_region_at_line(1) is Some(region)
    folding_model.toggle_collapse_state([region])
    assert_eq(view_model.line_count(), 2)
    viewer.update_options(ViewerOptions(folding=false))
    // `onModelChanged` with folding off: the hidden-range model's dispose
    // fired an empty set through the still-live listener.
    assert_eq(view_model.line_count(), 4)
    assert_true(controller.folding_model is None)
    assert_false(viewer.folding_enabled())
  })
}

///|
test "folding: model swap rebuilds state on the same central controller" {
  let viewer = Viewer::Viewer()
  let first = test_model("a\n  b\n  c\nd")
  let second = test_model("root\n  child\n  leaf\ntail\n  end")
  viewer.set_model(Some(first))
  let controller = viewer.folding_controller().unwrap()
  let first_folding_model = controller.folding_model.unwrap()
  let first_view_model = viewer.test_view_model()
  let first_region = first_folding_model.get_region_at_line(1).unwrap()
  first_folding_model.toggle_collapse_state([first_region])
  assert_eq(first_view_model.line_count(), 2)
  viewer.set_model(Some(second))
  assert_true(physical_equal(controller, viewer.folding_controller().unwrap()))
  let second_folding_model = controller.folding_model.unwrap()
  assert_false(physical_equal(first_folding_model, second_folding_model))
  assert_true(physical_equal(second, second_folding_model.text_model()))
  assert_eq(second_folding_model.regions().length(), 2)
  assert_eq(viewer.test_view_model().line_count(), 5)
  assert_eq(viewer.test_view_model().get_hidden_areas().length(), 0)
  viewer.dispose()
}

///|
test "folding: contribution disposal clears folds before silencing listeners" {
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model("a\n  b\n  c\nd")))
  let controller = viewer.folding_controller().unwrap()
  let folding_model = controller.folding_model.unwrap()
  let region = folding_model.get_region_at_line(1).unwrap()
  folding_model.toggle_collapse_state([region])
  assert_eq(viewer.test_view_model().line_count(), 2)
  let entry = viewer.contributions.instances[@folding_browser.FOLDING_CONTROLLER_ID]
  assert_eq(entry.listeners.length(), 5)
  entry.dispose(viewer)
  // `clear_local` runs while the hidden-range listener is still live, so its
  // empty range publication restores the view before the root listeners go.
  assert_eq(viewer.test_view_model().line_count(), 4)
  assert_eq(entry.listeners.length(), 0)
  assert_true(controller.folding_model is None)
  assert_true(controller.hidden_range_model is None)
  assert_true(viewer.folding_controller() is None)
  viewer.set_model(Some(test_model("x\n  y\nz")))
  // Model-change/content listeners cannot recreate state after contribution
  // disposal; the retained concrete controller stays silent.
  assert_true(controller.folding_model is None)
  assert_true(controller.hidden_range_model is None)
  viewer.dispose()
}
