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
test "folding: public fold_top_level collapses every outer region only" {
  with_test_viewer("root\n  child\n    leaf\nnext\n  item\ntail", viewer => {
    let view_model = viewer.test_view_model()
    guard viewer.folding_controller() is Some(controller)
    guard controller.folding_model is Some(folding_model)
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
    guard viewer.get_selection() is Some(selection)
    assert_eq(selection.start().line_number, 1)
  })
}

///|
test "folding: MoonBit top-level functions preserve their complete signatures" {
  let text =
    #|fn f(
    #|  param1 : Int,
    #|) -> Int {
    #|  param1 + 1
    #|}
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  let view_model = viewer.test_view_model()
  guard viewer.folding_controller() is Some(controller)
  guard controller.folding_model is Some(folding_model)
  viewer.fold_top_level()
  let regions = folding_model.regions()
  assert_eq(regions.get_start_line_number(0), 1)
  assert_eq(regions.get_end_line_number(0), 5)
  assert_true(regions.is_collapsed(0))
  assert_eq(folding_model.collapsed_signature_start_line_for_suffix(3), Some(1))
  assert_eq(view_model.line_count(), 4)
  assert_eq(view_model.lines().get_view_line_content(1), "fn f(")
  assert_eq(view_model.lines().get_view_line_content(2), "  param1 : Int,")
  assert_eq(view_model.lines().get_view_line_content(3), ") -> Int")
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
  let mut saw_signature_fold = false
  let mut saw_hidden_suffix = false
  for decoration in folding_model.text_model().get_all_decorations() {
    match decoration.options.description {
      "folding-collapsed-highlighted-signature-visual-decoration" => {
        saw_signature_fold = true
        assert_true(decoration.options.after_content_class_name is None)
      }
      "folding-signature-hidden-suffix" => {
        saw_hidden_suffix = true
        assert_eq(decoration.range.start_line_number, 3)
        assert_eq(decoration.range.start_column, 9)
        assert_true(decoration.options.inline_hidden_suffix)
        assert_true(decoration.options.inline_class_name is None)
      }
      _ => ()
    }
  }
  assert_true(saw_signature_fold)
  assert_true(saw_hidden_suffix)
  folding_model.toggle_collapse_state([regions.to_region(0)])
  assert_eq(view_model.line_count(), 6)
  assert_false(
    folding_model
    .text_model()
    .get_all_decorations()
    .any(decoration => {
      decoration.options.description == "folding-signature-hidden-suffix"
    }),
  )
  viewer.dispose()
}

///|
test "folding: hidden signature suffix does not create soft-wrapped rows" {
  let text =
    #|fn f() -> Int { // this body suffix is deliberately long enough to wrap
    #|  1
    #|}
    #|tail
  let viewer = Viewer::Viewer(options=ViewerOptions(soft_wrap=true))
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.test_set_soft_wrap_column(20)
  let view_model = viewer.test_view_model()
  assert_true(view_model.line_count() > 4)
  viewer.fold_top_level()
  assert_eq(view_model.line_count(), 2)
  assert_eq(view_model.lines().get_view_line_content(1), "fn f() -> Int")
  assert_eq(view_model.lines().get_view_line_content(2), "tail")
  viewer.dispose()
}

///|
test "folding: cursor in a hidden signature suffix snaps to its visible end" {
  let text =
    #|fn f() -> Int { // body comment
    #|  1
    #|}
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.set_position(Position(1, 28))
  viewer.fold_top_level()
  guard viewer.get_position() is Some(position)
  assert_position(position, Position(1, 14))
  assert_eq(
    viewer.test_view_model().lines().get_view_line_content(1),
    "fn f() -> Int",
  )
  viewer.dispose()
}

///|
test "folding: later cursor moves cannot enter a hidden signature suffix" {
  let text =
    #|fn f() -> Int { // body comment
    #|  1
    #|}
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  viewer.set_position(Position(1, 28))
  guard viewer.get_position() is Some(position)
  assert_position(position, Position(1, 14))
  viewer.dispose()
}

///|
test "folding: suffix-only collapse clamps an existing cursor" {
  let text =
    #|fn f(
    #|) -> Int { 1 }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.set_position(Position(2, 12))
  viewer.fold_top_level()
  guard viewer.get_position() is Some(position)
  assert_position(position, Position(2, 9))
  assert_eq(viewer.test_view_model().line_count(), 3)
  viewer.dispose()
}

///|
test "folding: repeated top-level fold is visibility-idempotent" {
  let viewer = Viewer::Viewer()
  viewer.set_model(
    Some(test_model("fn f() -> Int {\n  1\n}\ntail", language_id="moonbit")),
  )
  let mut delivered = 0
  viewer.on_did_change_hidden_areas(() => delivered += 1) |> ignore
  viewer.fold_top_level()
  let delivered_after_first_fold = delivered
  viewer.fold_top_level()
  assert_eq(delivered, delivered_after_first_fold)
  viewer.dispose()
}

///|
test "folding: suffix-only re-collapse clamps an existing cursor" {
  let text =
    #|fn f(
    #|) -> Int { 1 }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  guard viewer.folding_controller() is Some(controller)
  guard controller.folding_model is Some(folding_model)
  viewer.fold_top_level()
  assert_eq(folding_model.collapsed_signature_suffix_column(2), Some(9))
  guard folding_model.get_region_at_line(1) is Some(collapsed)
  folding_model.toggle_collapse_state([collapsed])
  viewer.set_position(Position(2, 12))
  guard folding_model.get_region_at_line(1) is Some(expanded)
  folding_model.toggle_collapse_state([expanded])
  guard viewer.get_position() is Some(position)
  assert_position(position, Position(2, 9))
  viewer.dispose()
}

///|
test "folding: cursor in a hidden body snaps before the signature suffix" {
  let text =
    #|fn f() -> Int { // body comment
    #|  1
    #|}
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.set_position(Position(2, 2))
  viewer.fold_top_level()
  guard viewer.get_position() is Some(position)
  assert_position(position, Position(1, 14))
  viewer.dispose()
}

///|
test "folding: MoonBit signature scan ignores non-declarations and literal braces" {
  let text =
    #|extern "js" fn foreign() -> Int = "() => ({ value: 1 })"
    #|let callback : (Int) -> Int =
    #|  fn(value) {
    #|    value + 1
    #|  }
    #|let async_callback : (Int) -> Int =
    #|  async fn(value) {
    #|    value + 1
    #|  }
    #|let wrapped_callback : (Int) -> Int =
    #|  (fn(value) {
    #|    value + 1
    #|  })
    #|fn[T] real(value : T) -> T {
    #|  let quoted = "\{"}"}"
    #|  let block = /* { */ value /* } */
    #|  let raw =
    #|    #| }
    #|  let interpolated =
    #|    $| }
    #|  block
    #|}
    #|tail
  let model = test_model(text, language_id="moonbit")
  let ranges = moonbit_signature_folding_ranges(model.snapshot)
  debug_inspect(
    ranges,
    content=(
      #|[
      #|  {
      #|    start_line_number: 14,
      #|    end_line_number: 22,
      #|    first_hidden_line_number: 15,
      #|    hidden_suffix_line_number: 14,
      #|    hidden_suffix_column: 27,
      #|  },
      #|]
    ),
  )
}

///|
test "folding: signature scan excludes declare functions and accepts qualified methods" {
  let text =
    #|declare pub(all) fn foreign() -> Int
    #|declare pub type Foreign
    #|struct Box {
    #|  value : Int
    #|}
    #|fn @editor_browser.MouseTarget::create_unknown(
    #|  value : Int,
    #|) -> Int {
    #|  value
    #|}
  let model = test_model(text, language_id="moonbit")
  debug_inspect(
    moonbit_signature_folding_ranges(model.snapshot),
    content=(
      #|[
      #|  {
      #|    start_line_number: 6,
      #|    end_line_number: 10,
      #|    first_hidden_line_number: 9,
      #|    hidden_suffix_line_number: 8,
      #|    hidden_suffix_column: 9,
      #|  },
      #|]
    ),
  )
}

///|
test "folding: split function modifiers remain part of the visible signature" {
  let text =
    #|pub
    #|  fn f() -> Int {
    #|    1
    #|  }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 3)
  assert_eq(view_model.lines().get_view_line_content(1), "pub")
  assert_eq(view_model.lines().get_view_line_content(2), "  fn f() -> Int")
  assert_eq(view_model.lines().get_view_line_content(3), "tail")
  viewer.dispose()
}

///|
test "folding: split impl header remains part of the visible method signature" {
  let text =
    #|impl Eq for X with
    #|  fn equal(self, other) {
    #|    true
    #|  }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 3)
  assert_eq(view_model.lines().get_view_line_content(1), "impl Eq for X with")
  assert_eq(
    view_model.lines().get_view_line_content(2),
    "  fn equal(self, other)",
  )
  assert_eq(view_model.lines().get_view_line_content(3), "tail")
  viewer.dispose()
}

///|
test "folding: signature scan accepts Unicode names and escaped interpolation text" {
  let text =
    #|fn literal() -> String {
    #|  "\\{" }
    #|fn 你好(
    #|  value : Int,
    #|) -> Int {
    #|  value
    #|}
  let model = test_model(text, language_id="moonbit")
  debug_inspect(
    moonbit_signature_folding_ranges(model.snapshot),
    content=(
      #|[
      #|  {
      #|    start_line_number: 1,
      #|    end_line_number: 2,
      #|    first_hidden_line_number: 2,
      #|    hidden_suffix_line_number: 1,
      #|    hidden_suffix_column: 23,
      #|  },
      #|  {
      #|    start_line_number: 3,
      #|    end_line_number: 7,
      #|    first_hidden_line_number: 6,
      #|    hidden_suffix_line_number: 5,
      #|    hidden_suffix_column: 9,
      #|  },
      #|]
    ),
  )
}

///|
test "folding: visible signature selection survives provider reconciliation" {
  let text =
    #|fn f(
    #|  value : Int,
    #|) -> Int {
    #|  value
    #|}
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  viewer.set_position(Position(2, 3))
  let options = viewer.get_options()
  viewer.update_options({
    ..options,
    folding_highlight: !options.folding_highlight,
  })
  guard viewer.folding_controller() is Some(controller)
  guard controller.folding_model is Some(folding_model)
  guard folding_model.get_region_at_line(1) is Some(region)
  assert_true(region.is_collapsed())
  assert_eq(viewer.test_view_model().line_count(), 3)
  viewer.dispose()
}

///|
test "folding: stale signature coordinates do not restyle replacement folds" {
  let viewer = Viewer::Viewer()
  viewer.set_model(
    Some(test_model("fn f() -> Int {\n  1\n}", language_id="moonbit")),
  )
  guard viewer.folding_controller() is Some(controller)
  guard controller.folding_model is Some(folding_model)
  viewer.fold_top_level()
  viewer.set_value("struct Box {\n  value : Int\n}")
  @folding_browser.set_collapse_state_at_level(folding_model, 1, true, [])
  let mut saw_plain_fold = false
  for decoration in folding_model.text_model().get_all_decorations() {
    if decoration.options.description ==
      "folding-collapsed-highlighted-visual-decoration" {
      saw_plain_fold = true
      assert_eq(
        decoration.options.after_content_class_name,
        Some("inline-folded"),
      )
    }
    assert_false(
      decoration.options.description == "folding-signature-hidden-suffix",
    )
  }
  assert_true(saw_plain_fold)
  viewer.dispose()
}

///|
test "folding: nested folds keep signature hidden ranges ordered" {
  let text =
    #|fn f(
    #|  callback : (Int) -> Int =
    #|    fn(x) {
    #|      x + 1
    #|    },
    #|) -> Int {
    #|  callback(1)
    #|}
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  guard viewer.folding_controller() is Some(controller)
  guard controller.folding_model is Some(folding_model)
  guard controller.hidden_range_model is Some(hidden_range_model)
  viewer.fold_top_level()
  guard folding_model.get_region_at_line(1) is Some(outer)
  folding_model.toggle_collapse_state([outer])
  guard folding_model.get_region_at_line(2) is Some(nested)
  folding_model.toggle_collapse_state([nested])
  guard folding_model.get_region_at_line(1) is Some(outer_again)
  folding_model.toggle_collapse_state([outer_again])
  debug_inspect(
    hidden_range_model.hidden_ranges(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 3,
      #|    start_column: 1,
      #|    end_line_number: 5,
      #|    end_column: 1,
      #|  },
      #|  {
      #|    start_line_number: 7,
      #|    start_column: 1,
      #|    end_line_number: 8,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  assert_true(hidden_range_model.is_hidden(4))
  assert_true(hidden_range_model.is_hidden(7))
  let mut saw_visible_nested_fold = false
  for decoration in folding_model.text_model().get_all_decorations() {
    if decoration.range.start_line_number == 2 &&
      decoration.range.end_line_number == 5 {
      assert_false(
        decoration.options.description == "folding-hidden-range-decoration",
      )
      if decoration.options.after_content_class_name == Some("inline-folded") {
        saw_visible_nested_fold = true
      }
    }
  }
  assert_true(saw_visible_nested_fold)
  viewer.dispose()
}

///|
test "folding: partially overlapping hidden ranges coalesce" {
  let text =
    #|fn f(
    #|  a : Int,
    #|    b : Int,
    #|    c : Int) -> Int {
    #|    let x = 1
    #|    x
    #|  }
    #|tail
  let viewer = Viewer::Viewer()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  guard viewer.folding_controller() is Some(controller)
  guard controller.folding_model is Some(folding_model)
  guard controller.hidden_range_model is Some(hidden_range_model)
  viewer.fold_top_level()
  guard folding_model.get_region_at_line(1) is Some(outer)
  folding_model.toggle_collapse_state([outer])
  guard folding_model.get_region_at_line(2) is Some(nested)
  folding_model.toggle_collapse_state([nested])
  guard folding_model.get_region_at_line(1) is Some(outer_again)
  folding_model.toggle_collapse_state([outer_again])
  debug_inspect(
    hidden_range_model.hidden_ranges(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 3,
      #|    start_column: 1,
      #|    end_line_number: 7,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  let selections = [
    @core.Selection::from_positions(Position(5, 2), Position(5, 2)),
  ]
  assert_true(hidden_range_model.adjust_selections(selections))
  assert_false(hidden_range_model.is_hidden(selections[0].start().line_number))
  assert_eq(selections[0].start().line_number, 2)
  viewer.dispose()
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
