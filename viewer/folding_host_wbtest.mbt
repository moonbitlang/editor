// Headless end-to-end tests for the folding contribution: the
// `FoldingController` chain from `onModelChanged` through the hidden-range
// model into `Viewer::set_hidden_areas` and the view axis.

///|
test "folding: contribution computes indent regions on model attach" {
  with_test_viewer("a\n  b\n  c\nd\n  e", viewer => {
    guard viewer.folding_controller() is Some(controller) else {
      fail("expected a folding controller")
    }
    guard controller.folding_model is Some(folding_model) else {
      fail("expected an attached folding model")
    }
    let regions = folding_model.regions()
    assert_eq(regions.length(), 2)
    assert_eq(regions.get_start_line_number(0), 1)
    assert_eq(regions.get_end_line_number(0), 3)
    assert_eq(regions.get_start_line_number(1), 4)
    assert_eq(regions.get_end_line_number(1), 5)
  })
}

///|
test "folding: public fold_top_level collapses every outer region only" {
  with_test_viewer("root\n  child\n    leaf\nnext\n  item\ntail", viewer => {
    let view_model = viewer.test_view_model()
    guard viewer.folding_controller() is Some(controller) else {
      fail("expected a folding controller")
    }
    guard controller.folding_model is Some(folding_model) else {
      fail("expected an attached folding model")
    }
    let regions = folding_model.regions()
    assert_eq(regions.length(), 3)
    viewer.set_position(Position(3, 1))
    viewer.fold_top_level()
    assert_true(regions.is_collapsed(0))
    assert_false(regions.is_collapsed(1))
    assert_true(regions.is_collapsed(2))
    assert_eq(view_model.line_count(), 3)
    assert_eq(view_model.lines().get_view_line_content(1), "root")
    assert_eq(view_model.lines().get_view_line_content(2), "next")
    assert_eq(view_model.lines().get_view_line_content(3), "tail")
    // The API does not preserve a blocked selection: folding the containing
    // outer region snaps the caret to its header.
    guard viewer.get_selection() is Some(selection) else {
      fail("expected a selection")
    }
    assert_eq(selection.start().line_number, 1)
  })
}

///|
test "folding: MoonBit outline keeps the complete signature and opening brace" {
  let text =
    #|fn f(
    #|  display_param : X,
    #|) -> ReturnType {
    #|  use(display_param)
    #|}
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.set_position(Position(4, 3))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  guard viewer.folding_controller() is Some(controller) else {
    fail("expected a folding controller")
  }
  guard controller.folding_model is Some(folding_model) else {
    fail("expected an attached folding model")
  }
  guard folding_model.get_region_at_line(3) is Some(region) else {
    fail("expected a folding region at line 3")
  }
  assert_eq(region.start_line_number(), 3)
  assert_eq(region.end_line_number(), 5)
  assert_true(region.is_collapsed())
  assert_eq(view_model.line_count(), 4)
  assert_eq(view_model.lines().get_view_line_content(1), "fn f(")
  assert_eq(view_model.lines().get_view_line_content(2), "  display_param : X,")
  assert_eq(view_model.lines().get_view_line_content(3), ") -> ReturnType {")
  assert_eq(view_model.lines().get_view_line_content(4), "tail")
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 4,
      #|    start_column: 1,
      #|    end_line_number: 5,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  guard viewer.get_position() is Some(position) else {
    fail("expected a cursor position")
  }
  assert_position(position, Position(3, 18))
  let mut saw_outline_body = false
  for decoration in folding_model.text_model().get_all_decorations() {
    if decoration.options.description ==
      "folding-collapsed-outline-body-highlighted-visual-decoration" {
      saw_outline_body = true
      assert_eq(decoration.options.after_content_class_name, None)
      assert_eq(decoration.range.start_line_number, 3)
    }
  }
  assert_true(saw_outline_body)
  folding_model.toggle_collapse_state([region])
  assert_eq(view_model.line_count(), 6)
  viewer.dispose()
}

///|
test "folding: MoonBit outline scan ignores bodyless functions and literal braces" {
  let text =
    #|extern "js" fn foreign() -> Int = "() => ({ value: 1 })"
    #|let callback : (Int) -> Int =
    #|  fn(value) {
    #|    value + 1
    #|  }
    #|declare pub fn declared() -> Int
    #|fn[T] real(value : T) -> T {
    #|  let quoted = "\{"}"}"
    #|  let block = /* { */ value /* } */
    #|  let raw =
    #|    #| }
    #|  let interpolated =
    #|    $| }
    #|  block
    #|}
  let model = test_model(text, language_id="moonbit")
  let folds = moonbit_function_body_folds(model.snapshot)
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].declaration_start_line_number, 7)
  assert_eq(folds[0].body_start_line_number, 7)
  assert_eq(folds[0].body_end_line_number, 15)
}

///|
test "folding: formatted modifiers and impl headers remain visible" {
  let text =
    #|pub
    #|  fn first() -> Int {
    #|    1
    #|  }
    #|impl Eq for X with
    #|  fn equal(self, other) {
    #|    true
    #|  }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 5)
  assert_eq(view_model.lines().get_view_line_content(1), "pub")
  assert_eq(
    view_model.lines().get_view_line_content(2),
    "  fn first() -> Int {",
  )
  assert_eq(view_model.lines().get_view_line_content(3), "impl Eq for X with")
  assert_eq(
    view_model.lines().get_view_line_content(4),
    "  fn equal(self, other) {",
  )
  assert_eq(view_model.lines().get_view_line_content(5), "tail")
  viewer.dispose()
}

///|
test "folding: repeated MoonBit outline fold is idempotent" {
  let viewer = Viewer::Viewer()
  viewer.set_model(
    Some(test_model("fn f() -> Int {\n  1\n}\ntail", language_id="moonbit")),
  )
  let mut hidden_area_changes = 0
  viewer.on_did_change_hidden_areas(() => hidden_area_changes += 1) |> ignore
  viewer.fold_top_level()
  let changes_after_first_fold = hidden_area_changes
  viewer.fold_top_level()
  assert_eq(hidden_area_changes, changes_after_first_fold)
  viewer.dispose()
}

///|
test "folding: MoonBit outline survives folding decoration option updates" {
  let viewer = Viewer::Viewer()
  viewer.set_model(
    Some(test_model("fn f() -> Int {\n  1\n}\ntail", language_id="moonbit")),
  )
  viewer.fold_top_level()
  guard viewer.folding_controller() is Some(controller) else {
    fail("expected a folding controller")
  }
  guard controller.folding_model is Some(folding_model) else {
    fail("expected an attached folding model")
  }
  viewer.update_options(ViewerOptions(show_folding_controls=Never))
  let regions = folding_model.regions()
  assert_eq(regions.length(), 1)
  assert_eq(regions.get_start_line_number(0), 1)
  assert_eq(regions.get_end_line_number(0), 3)
  assert_eq(
    regions.get_type(0),
    Some(@folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE),
  )
  assert_true(regions.is_collapsed(0))
  assert_eq(viewer.test_view_model().line_count(), 2)
  let mut saw_outline_body = false
  for decoration in folding_model.text_model().get_all_decorations() {
    if decoration.options.description ==
      "folding-no-controls-outline-body-range-decoration" {
      saw_outline_body = true
      assert_eq(decoration.options.after_content_class_name, None)
    }
  }
  assert_true(saw_outline_body)
  viewer.dispose()
}

///|
test "folding: MoonBit outline respects the configured folding limit" {
  let viewer = Viewer::Viewer(options=ViewerOptions(folding_maximum_regions=1))
  viewer.set_model(
    Some(
      test_model(
        "fn f() -> Int {\n  1\n}\nfn g() -> Int {\n  2\n}\ntail",
        language_id="moonbit",
      ),
    ),
  )
  viewer.fold_top_level()
  guard viewer.folding_controller() is Some(controller) else {
    fail("expected a folding controller")
  }
  guard controller.folding_model is Some(folding_model) else {
    fail("expected an attached folding model")
  }
  let regions = folding_model.regions()
  assert_eq(regions.length(), 1)
  assert_eq(
    regions.get_type(0),
    Some(@folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE),
  )
  assert_true(regions.is_collapsed(0))
  viewer.dispose()
}

///|
test "folding: MoonBit outline preserves signatures with same-line bodies" {
  let text =
    #|fn f(
    #|  display_param : X,
    #|) -> ReturnType { display_param }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  guard viewer.folding_controller() is Some(controller) else {
    fail("expected a folding controller")
  }
  guard controller.folding_model is Some(folding_model) else {
    fail("expected an attached folding model")
  }
  assert_eq(folding_model.regions().length(), 0)
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 4)
  assert_eq(view_model.lines().get_view_line_content(1), "fn f(")
  assert_eq(view_model.lines().get_view_line_content(2), "  display_param : X,")
  assert_eq(
    view_model.lines().get_view_line_content(3),
    ") -> ReturnType { display_param }",
  )
  assert_eq(view_model.lines().get_view_line_content(4), "tail")
  viewer.dispose()
}

///|
test "folding: toggling a region folds its lines out of the view axis" {
  with_test_viewer("a\n  b\n  c\nd\n  e", viewer => {
    let view_model = viewer.test_view_model()
    assert_eq(view_model.line_count(), 5)
    guard viewer.folding_controller() is Some(controller) else {
      fail("expected a folding controller")
    }
    guard controller.folding_model is Some(folding_model) else {
      fail("expected an attached folding model")
    }
    guard folding_model.get_region_at_line(1) is Some(region) else {
      fail("expected a folding region at line 1")
    }
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
    guard folding_model.get_region_at_line(1) is Some(region_again) else {
      fail("expected a folding region at line 1")
    }
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
    guard viewer.get_selection() is Some(selection) else {
      fail("expected a selection")
    }
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
    guard viewer.folding_controller() is Some(controller) else {
      fail("expected a folding controller")
    }
    guard controller.folding_model is Some(folding_model) else {
      fail("expected an attached folding model")
    }
    guard folding_model.get_region_at_line(1) is Some(region) else {
      fail("expected a folding region at line 1")
    }
    folding_model.toggle_collapse_state([region])
    assert_eq(view_model.line_count(), 2)
    viewer.update_options(ViewerOptions(folding=false))
    // `onModelChanged` with folding off: the hidden-range model's dispose
    // fired an empty set through the still-live listener.
    assert_eq(view_model.line_count(), 4)
    assert_true(controller.folding_model is None)
    assert_false(viewer.folding_enabled())
    viewer.fold_top_level()
    assert_eq(view_model.line_count(), 4)
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
