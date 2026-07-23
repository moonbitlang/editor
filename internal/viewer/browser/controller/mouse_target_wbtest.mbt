///|
/// `ElementPath` predicate coverage (mouseTarget.ts:157-235) over literal
/// fingerprint paths — the byte values are `PartFingerprint::to_int`
/// (OverflowGuard=3, OverlayWidgets=4, OverflowingOverlayWidgets=5,
/// ScrollableElement=6, ViewLines=8, and lines-content is unstamped=0).
test "element path predicates classify fingerprint paths" {
  // overflow-guard > scrollable > lines-content > view-lines [> line]
  let view_line_path : Bytes = [3, 6, 0, 8]
  let strict_view_line_path : Bytes = [3, 6, 0, 8, 0]
  assert_true(ElementPath::is_child_of_view_lines(view_line_path))
  assert_true(ElementPath::is_child_of_view_lines(strict_view_line_path))
  assert_false(ElementPath::is_strict_child_of_view_lines(view_line_path))
  assert_true(ElementPath::is_strict_child_of_view_lines(strict_view_line_path))
  // overflow-guard > scrollable (scrollbar parts). Note `.lines-content`
  // ([3, 6, 0]) also satisfies this predicate — Monaco's dispatch order
  // simply reaches the residual `_hitTestScrollbar` arm last.
  let scrollable_path : Bytes = [3, 6]
  assert_true(ElementPath::is_child_of_scrollable_element(scrollable_path))
  assert_false(ElementPath::is_child_of_scrollable_element([3, 4]))
  // overflow-guard > scrollable > lines-content > contentWidgets
  let content_widget_path : Bytes = [3, 6, 0, 1]
  assert_true(ElementPath::is_child_of_content_widgets(content_widget_path))
  assert_false(ElementPath::is_child_of_content_widgets(view_line_path))
  // overflow-guard > overlayWidgets vs the overflowing layers at the root
  let overlay_path : Bytes = [3, 4]
  let overflowing_content_path : Bytes = [2]
  let overflowing_overlay_path : Bytes = [5]
  assert_true(ElementPath::is_child_of_overlay_widgets(overlay_path))
  assert_true(
    ElementPath::is_child_of_overflowing_content_widgets(
      overflowing_content_path,
    ),
  )
  assert_true(
    ElementPath::is_child_of_overflowing_overlay_widgets(
      overflowing_overlay_path,
    ),
  )
  assert_true(ElementPath::is_child_of_overflow_guard(overlay_path))
  assert_false(
    ElementPath::is_child_of_overflow_guard(overflowing_content_path),
  )
  // No textarea part is ever stamped, but the predicate itself is 1:1.
  let textarea_path : Bytes = [3, 7]
  assert_true(ElementPath::is_text_area(textarea_path))
  assert_false(ElementPath::is_text_area(overlay_path))
  // Minimap slot (never produced by this viewer).
  let minimap_path : Bytes = [3, 9]
  assert_true(ElementPath::is_child_of_minimap(minimap_path))
}

///|
/// `MouseTargetFactory._getMouseColumn` (mouseTarget.ts:866-872).
test "mouse column derives from the halfwidth character width" {
  // negative offsets clamp to column 1
  assert_eq(get_mouse_column_static(-3.0, 8.0), 1)
  // Math.round semantics: 11.9px / 8px rounds to 1 char -> column 2
  assert_eq(get_mouse_column_static(11.9, 8.0), 2)
  // 12px / 8px rounds to 2 chars -> column 3
  assert_eq(get_mouse_column_static(12.0, 8.0), 3)
  assert_eq(get_mouse_column_static(0.0, 8.0), 1)
}

///|
fn zone_test_view_model() -> @view_model.ViewModel {
  @syntax.tokenization_registry.register("moonbit", @syntax.PlainTokenizer())
  |> ignore
  let model : @model.TextModel = TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/zones.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    "line one\nline two\nline three",
  )
  let view_model = @view_model.ViewModel(model)
  view_model.view_layout.change_whitespace(accessor => {
    accessor.insert_whitespace(1, 0, 36.0, 0.0) |> ignore
  })
  |> ignore
  view_model
}

///|
/// static `HitTestContext.getZoneAtCoord` (mouseTarget.ts:269-308): the
/// mid-point rule picks `positionBefore` above the middle and
/// `positionAfter` below it; offsets outside every zone yield `None`.
test "get zone at coord resolves the zone band with the midpoint rule" {
  let view_model = zone_test_view_model()
  let line_height = view_model.view_layout.line_height().to_double()
  // The zone sits after line 1: band [line_height, line_height + 36).
  let above_middle = hit_test_get_zone_at_coord(view_model, line_height + 1.0)
  guard above_middle is Some(above) else {
    fail("expected the upper half of the whitespace to resolve a zone")
  }
  let generated_id = view_model.view_layout.get_whitespaces()[0].id
  assert_eq(above.view_zone_id, generated_id)
  assert_true(above.position_before == Some(Position(1, 9)))
  assert_true(above.position_after == Some(Position(2, 1)))
  assert_true(above.position == Position(1, 9))
  assert_eq(above.after_line_number, 1)
  let below_middle = hit_test_get_zone_at_coord(view_model, line_height + 35.0)
  guard below_middle is Some(below) else {
    fail("expected the lower half of the whitespace to resolve a zone")
  }
  assert_eq(below.view_zone_id, generated_id)
  assert_true(below.position_before == Some(Position(1, 9)))
  assert_true(below.position_after == Some(Position(2, 1)))
  assert_true(below.position == Position(2, 1))
  assert_eq(below.after_line_number, 1)
  // Inside line 1's own band there is no zone.
  assert_true(hit_test_get_zone_at_coord(view_model, 0.0) is None)
}
