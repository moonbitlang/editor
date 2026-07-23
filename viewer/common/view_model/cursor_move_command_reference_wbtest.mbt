///| Faithful selected ports from
/// `vscode/src/vs/editor/test/browser/controller/cursorMoveCommand.test.ts` in
/// the checked-in vscode source.
///
/// All 10 labels in the approved exact-label set are present verbatim. These
/// cases exercise `CursorMoveCommands.simpleMove` count/unit routing through
/// the source-shaped ViewModel adapter.
///
/// SKIPPED — `move left should move to left by half line` and `move right
/// should move to right by half line`: D1 HalfLine is unbound/deferred.
///
/// SKIPPED — `move to first character of line from middle`, `move to first
/// character of line from first non white space character`, `move to first
/// character of line from first character`, `move to first non white space
/// character of line from middle`, `move to first non white space character
/// of line from first non white space character`, `move to first non white
/// space character of line from first character`, `move to end of line from
/// middle`, `move to end of line from last non white space character`, `move
/// to end of line from line end`, `move to last non white space character from
/// middle`, `move to last non white space character from last non white space
/// character`, `move to last non white space character from line end`,
/// `move to center of line not from center`, `move to center of line from
/// center`, `move to center of line from start`, and `move to center of line
/// from end` at lines 98-224: D1 generic cursorMove directions are not
/// substitutes for the separately ported bound Home/End commands.
///
/// SKIPPED — `move up by model line cursor move command` and `move down by
/// model line cursor move command`: D1 model-line unit.
///
/// SKIPPED — viewport placement at lines 322-419:
/// `move to view top line moves to first visible line if it is first line`;
/// `move to view top line moves to top visible line when first line is not
/// visible`; `move to view top line moves to nth line from top`; `move to view
/// top line moves to last line if n is greater than last visible line number`;
/// `move to view center line moves to the center line`; `move to view bottom
/// line moves to last visible line if it is last line`; `move to view bottom
/// line moves to last visible line when last line is not visible`; `move to
/// view bottom line moves to nth line from bottom`; and `move to view bottom
/// line moves to first line if n is lesser than first visible line number`.
///
/// SKIPPED — blank-line movement at lines 422-507:
/// `move down should move to start of next blank line`; `move up should move
/// to start of previous blank line`; `move down should skip over whitespace
/// if already on blank line`; `move up should skip over whitespace if already
/// on blank line`; `move up should go to first column of first line if not
/// empty`; `move down should go to first column of last line if not empty`;
/// `select down should select to start of next blank line`; and `select up
/// should select to start of previous blank line`.
///
/// SKIPPED — folded-line movement at lines 512-615:
/// `move down by foldedLine skips a fold below the cursor`; `move up by
/// foldedLine skips a fold above the cursor`; `move down by foldedLine with
/// count treats each fold as one step`; `move down by foldedLine skips a
/// multi-line fold as one step`; `move down by foldedLine at last line stays
/// at last line`; `move up by foldedLine at first line stays at first line`;
/// `move down by foldedLine with count clamps to last visible line after
/// fold`; and `move up by foldedLine with count clamps to first visible line
/// before fold`. All three clusters are D1 generic directions.

///|
test "move left should move to left character" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  cursor_reference_move_left(view_model)
  cursor_reference_assert_position(view_model, 1, 7)
}

///|
test "move left should move to left by n characters" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  cursor_reference_move_left(view_model, value=3)
  cursor_reference_assert_position(view_model, 1, 5)
}

///|
test "move left moves to previous line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 2, 3)
  cursor_reference_move_left(view_model, value=10)
  cursor_reference_assert_position(view_model, 1, 21)
}

///|
test "move right should move to right character" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 5)
  cursor_reference_move_right(view_model)
  cursor_reference_assert_position(view_model, 1, 6)
}

///|
test "move right should move to right by n characters" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 2)
  cursor_reference_move_right(view_model, value=6)
  cursor_reference_assert_position(view_model, 1, 8)
}

///|
test "move right moves to next line" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 8)
  cursor_reference_move_right(view_model, value=100)
  cursor_reference_assert_position(view_model, 2, 1)
}

///|
test "move up by cursor move command" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 5)
  cursor_reference_move_up(view_model, value=2)
  cursor_reference_assert_position(view_model, 1, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 1)
}

///|
test "move up with selection by cursor move command" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 3, 5)
  cursor_reference_move_up(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 3, 5, 2, 2)
  cursor_reference_move_up(view_model, select=true)
  cursor_reference_assert_cursor(view_model, 3, 5, 1, 5)
}

///|
test "move up and down with tabs by cursor move command" {
  let view_model = cursor_reference_view_model()
  cursor_reference_set_position(view_model, 1, 5)
  cursor_reference_move_down(view_model, value=4)
  cursor_reference_assert_position(view_model, 5, 2)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 4, 1)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 3, 5)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 2, 2)
  cursor_reference_move_up(view_model)
  cursor_reference_assert_position(view_model, 1, 5)
}

///|
test "move up and down with end of lines starting from a long one by cursor move command" {
  let view_model = cursor_reference_view_model()
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
  cursor_reference_end(view_model)
  cursor_reference_assert_position(view_model, 1, 21)
  cursor_reference_move_down(view_model, value=2)
  cursor_reference_assert_position(view_model, 3, 17)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 4, 1)
  cursor_reference_move_down(view_model)
  cursor_reference_assert_position(view_model, 5, 2)
  cursor_reference_move_up(view_model, value=4)
  cursor_reference_assert_position(view_model, 1, 21)
}
