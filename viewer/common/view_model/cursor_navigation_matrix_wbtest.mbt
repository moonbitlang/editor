// Behavior-variable matrix supplement for the approved cursor movement port.
// These are ordinary source-derived tests: no pinned upstream suite labels are
// invented beyond the reference files that own the exact-label denominator.

///|
test "SimpleMoveDirection and Unit retain their exact source member contracts" {
  let simple_directions : Array[SimpleMoveDirection] = [
    Left,
    Right,
    Up,
    Down,
    PrevBlankLine,
    NextBlankLine,
    WrappedLineStart,
    WrappedLineFirstNonWhitespaceCharacter,
    WrappedLineColumnCenter,
    WrappedLineEnd,
    WrappedLineLastNonWhitespaceCharacter,
  ]
  let directions : Array[CursorMoveDirection] = [
    Left,
    Right,
    Up,
    Down,
    PrevBlankLine,
    NextBlankLine,
    WrappedLineStart,
    WrappedLineFirstNonWhitespaceCharacter,
    WrappedLineColumnCenter,
    WrappedLineEnd,
    WrappedLineLastNonWhitespaceCharacter,
    ViewPortTop,
    ViewPortCenter,
    ViewPortBottom,
    ViewPortIfOutside,
  ]
  let units : Array[CursorMoveUnit] = [
    None,
    Line,
    WrappedLine,
    Character,
    HalfLine,
    FoldedLine,
  ]
  assert_eq(simple_directions.length(), 11)
  assert_eq(directions.length(), 15)
  assert_eq(units.length(), 6)
  let arguments = SimpleMoveArguments(Left, WrappedLine, true, 3)
  assert_true(arguments.direction == Left)
  assert_true(arguments.unit == WrappedLine)
  assert_true(arguments.select)
  assert_eq(arguments.value, 3)

  let view_model = cursor_reference_view_model()
  let before = view_model.cursor.get_primary_cursor_state()
  for index in 4..<simple_directions.length() {
    let direction = simple_directions[index]
    assert_false(view_model.move_cursor(direction, false))
    assert_true(view_model.cursor.get_primary_cursor_state() == before)
  }
  for index in 11..<directions.length() {
    assert_true(directions[index].as_simple() is None)
    assert_false(view_model.move_cursor_direction(directions[index], false))
    assert_true(view_model.cursor.get_primary_cursor_state() == before)
  }
  for unit in [Line, Character, HalfLine, FoldedLine] {
    assert_false(view_model.move_cursor(Up, false, unit~))
    assert_true(view_model.cursor.get_primary_cursor_state() == before)
  }
  assert_false(view_model.move_cursor(Left, false, unit=HalfLine))
  assert_false(view_model.move_cursor(Right, false, unit=HalfLine))
  assert_true(view_model.cursor.get_primary_cursor_state() == before)
}

///|
test "PageUp PageDown preserve visible-column leftovers at tab sizes two and four" {
  for tab_size in [2, 4] {
    let view_model = ViewModel::with_options(
      cursor_reference_model("\t123456\nx\n\t123456"),
      ViewModelOptions(tab_size~),
    )
    cursor_reference_set_position(view_model, 1, 5)
    assert_true(view_model.move_cursor_page(Down, false, page_size=1))
    let short_down = view_model.cursor.get_primary_cursor_state()
    cursor_reference_assert_position(view_model, 2, 2)
    assert_eq(short_down.view_state.leftover_visible_columns, tab_size + 2)
    assert_eq(short_down.model_state.leftover_visible_columns, tab_size + 2)
    assert_true(view_model.move_cursor_page(Down, false, page_size=1))
    cursor_reference_assert_position(view_model, 3, 5)
    assert_eq(view_model.cursor.view_state().leftover_visible_columns, 0)

    assert_true(view_model.move_cursor_page(Up, false, page_size=1))
    let short_up = view_model.cursor.get_primary_cursor_state()
    cursor_reference_assert_position(view_model, 2, 2)
    assert_eq(short_up.view_state.leftover_visible_columns, tab_size + 2)
    assert_true(view_model.move_cursor_page(Up, false, page_size=1))
    cursor_reference_assert_position(view_model, 1, 5)
    assert_eq(view_model.cursor.view_state().leftover_visible_columns, 0)

    cursor_reference_set_position(view_model, 1, 5)
    assert_true(view_model.move_cursor_page(Down, true, page_size=1))
    cursor_reference_assert_cursor(view_model, 1, 5, 2, 2)
    let selected = view_model.cursor.view_state()
    assert_eq(selected.selection_start_leftover_visible_columns, 0)
    assert_eq(selected.leftover_visible_columns, tab_size + 2)
    assert_true(view_model.move_cursor_page(Down, true, page_size=1))
    cursor_reference_assert_cursor(view_model, 1, 5, 3, 5)
    assert_eq(view_model.cursor.view_state().leftover_visible_columns, 0)
  }
}

///|
test "Page axes cover marker zero positive and selection combinations" {
  let view_model = ViewModel::with_options(
    cursor_reference_model(
      "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine",
    ),
    ViewModelOptions(tab_size=4),
  )
  view_model.view_layout.set_viewport_size(width=400.0, height=90.0) |> ignore
  let page_size = view_model.cursor_page_size()
  assert_true(page_size >= 1)
  cursor_reference_set_position(view_model, 5, 2)
  assert_true(view_model.move_cursor_page(Up, false, page_size=-1))
  cursor_reference_assert_position(view_model, 5 - page_size, 2)
  cursor_reference_set_position(view_model, 5, 2)
  assert_true(view_model.move_cursor_page(Down, false, page_size=0))
  cursor_reference_assert_position(view_model, 5 + page_size, 2)
  cursor_reference_set_position(view_model, 5, 2)
  assert_true(view_model.move_cursor_page(Up, true, page_size=2))
  cursor_reference_assert_cursor(view_model, 5, 2, 3, 2)
  cursor_reference_set_position(view_model, 5, 2)
  assert_true(view_model.move_cursor_page(Down, true, page_size=2))
  cursor_reference_assert_cursor(view_model, 5, 2, 7, 2)
}

///|
test "value greater than one keeps surrogate-safe orthogonal Left Right steps" {
  let view_model = ViewModel::with_options(
    cursor_reference_model("a🐶bc"),
    ViewModelOptions(tab_size=4),
  )
  cursor_reference_set_position(view_model, 1, 5)
  assert_true(view_model.move_cursor(Left, false, value=2, unit=None))
  cursor_reference_assert_position(view_model, 1, 2)
  cursor_reference_set_position(view_model, 1, 1)
  assert_true(view_model.move_cursor(Right, false, value=2, unit=None))
  cursor_reference_assert_position(view_model, 1, 4)
}

///|
test "sticky End remains an explicit no-mutation deferral" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  let before = view_model.cursor.get_primary_cursor_state()
  assert_false(view_model.move_cursor_to_line_end(false, sticky=true))
  assert_true(view_model.cursor.get_primary_cursor_state() == before)
}

///|
test "moveDown retry normalization stops at the exact cap of ten" {
  let mut calls = 0
  let target = cursor_move_down_with_retry(3, 100, i => {
    calls += 1
    ({ line_number: 4 + i, column: 1, leftover_visible_columns: 0 }, 3)
  })
  assert_eq(calls, 11)
  assert_eq(target.line_number, 14)
}
