///| Ordinary source-derived PageUp/PageDown coverage.
///
/// Neither `cursor.test.ts` nor `cursorMoveCommand.test.ts` in the checked-in
/// vscode source contains a Page label, so these
/// tests deliberately remain outside the reference files and do not invent
/// upstream names.

///|
test "cursor page size uses exact viewport formula and marker fallbacks" {
  let view_model = cursor_reference_view_model()
  view_model.view_layout.set_viewport_size(width=400.0, height=200.0) |> ignore
  let expected = ((200.0 / view_model.view_layout.line_height().to_double())
  .floor()
  .to_int() -
  2).max(1)
  assert_eq(view_model.cursor_page_size(), expected)
  cursor_reference_set_position(view_model, 5, 1)
  view_model.move_cursor_page(Up, false, page_size=-1) |> ignore
  cursor_reference_assert_position(view_model, 1, 1)
  cursor_reference_set_position(view_model, 1, 1)
  view_model.move_cursor_page(Down, false, page_size=0) |> ignore
  cursor_reference_assert_position(view_model, 5, 2)
}

///|
test "cursor page positive override and selection use wrapped-line movement" {
  let text = "a\nbb\nccc\ndddd\neeeee\nffffff\nggggggg"
  let view_model = ViewModel::with_options(
    cursor_reference_model(text),
    ViewModelOptions(tab_size=4),
  )
  cursor_reference_set_position(view_model, 4, 3)
  view_model.move_cursor_page(Up, true, page_size=2) |> ignore
  cursor_reference_assert_cursor(view_model, 4, 3, 2, 3)
  view_model.move_cursor_page(Down, true, page_size=2) |> ignore
  cursor_reference_assert_cursor(view_model, 4, 3, 4, 3)
}

///|
test "cursor page preserves desired column across an empty target line" {
  let view_model = ViewModel::with_options(
    cursor_reference_model("abc\n\nxyz"),
    ViewModelOptions(tab_size=4),
  )
  cursor_reference_set_position(view_model, 1, 3)
  view_model.move_cursor_page(Down, false, page_size=1) |> ignore
  cursor_reference_assert_position(view_model, 2, 1)
  assert_eq(view_model.cursor.view_state().leftover_visible_columns, 2)
  view_model.move_cursor_page(Down, false, page_size=1) |> ignore
  cursor_reference_assert_position(view_model, 3, 3)
  assert_eq(view_model.cursor.view_state().leftover_visible_columns, 0)
}

///|
test "cursor page lands on wrapped continuation view lines" {
  let view_model = ViewModel::with_options(
    cursor_reference_model("abcdefghij"),
    ViewModelOptions::soft_wrap(4, tab_size=4, wrapping_indent=None),
  )
  cursor_reference_set_position(view_model, 1, 2)
  view_model.move_cursor_page(Down, false, page_size=1) |> ignore
  cursor_reference_assert_view_position(view_model, 2, 2)
  assert_true(view_model.cursor.model_state().position == Position(1, 6))
  view_model.move_cursor_page(Down, false, page_size=1) |> ignore
  cursor_reference_assert_view_position(view_model, 3, 2)
  assert_true(view_model.cursor.model_state().position == Position(1, 10))
}

///|
test "cursor page tiny viewport clamps computed size to one" {
  let view_model = cursor_reference_view_model()
  view_model.view_layout.set_viewport_size(width=400.0, height=0.0) |> ignore
  assert_eq(view_model.cursor_page_size(), 1)
  cursor_reference_set_position(view_model, 3, 5)
  view_model.move_cursor_page(Up, false) |> ignore
  cursor_reference_assert_position(view_model, 2, 2)
}

///|
test "cursor simple model last non-whitespace adapter covers model and view" {
  let view_model = ViewModel::with_options(
    cursor_reference_model("  abc  \n \t"),
    ViewModelOptions(tab_size=4),
  )
  assert_eq(
    CursorMoveModel::Model(view_model.model).get_line_last_non_whitespace_column(
      1,
    ),
    6,
  )
  assert_eq(
    CursorMoveModel::View(view_model).get_line_last_non_whitespace_column(1),
    6,
  )
  assert_eq(
    CursorMoveModel::Model(view_model.model).get_line_last_non_whitespace_column(
      2,
    ),
    0,
  )
  assert_eq(
    CursorMoveModel::View(view_model).get_line_last_non_whitespace_column(2),
    0,
  )
  view_model.dispose()
}
