// Cursor/selection behavior suite — the slice of vscode's
// editor/test/browser/controller/cursor.test.ts that is pure semantic state
// (model/view selections), driven through the headless harness in
// `test_viewer_wbtest.mbt`. These never belonged in a browser: they assert on
// positions and ranges, not pixels.

///|
/// `MoveTo` (a plain click) collapses the selection at the target, reported in
/// model coordinates. With no wrapping the view position passed to `move_to`
/// equals the model position the converter derives.
test "MoveTo positions the cursor in model coordinates" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    @cursor.move_to(viewer.test_cursor(), Position(2, 5))
    assert_cursor(viewer, Selection(Position(2, 5), Position(2, 5)))
  })
}

///|
test "move_to collapses the selection at the target position" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    @cursor.move_to(viewer.test_cursor(), Position(1, 3))
    let selection = viewer.test_cursor().get_model_selection()
    assert_true(selection.is_empty())
    assert_position(selection.get_position(), Position(1, 3))
  })
}

///|
/// `MoveToSelect` (shift-click / drag) extends to the target while keeping the
/// existing anchor, so the result is a ranged selection.
test "move_to_select extends the selection from the anchor" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    let cursor = viewer.test_cursor()
    @cursor.move_to(cursor, Position(1, 3))
    @cursor.move_to_select(cursor, Position(1, 7))
    assert_cursor(viewer, Selection(Position(1, 3), Position(1, 7)))
  })
}

///|
test "move_to_select spans multiple model lines" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    let cursor = viewer.test_cursor()
    @cursor.move_to(cursor, Position(1, 6))
    @cursor.move_to_select(cursor, Position(3, 4))
    let selection = viewer.test_cursor().get_model_selection()
    assert_false(selection.is_empty())
    assert_position(selection.start(), Position(1, 6))
    assert_position(selection.end(), Position(3, 4))
  })
}

///|
/// Without wrapping the model and view selections coincide — the identity the
/// coordinates converter guarantees in the no-projection case.
test "view and model selections coincide without wrapping" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    let cursor = viewer.test_cursor()
    @cursor.move_to(cursor, Position(2, 2))
    @cursor.move_to_select(cursor, Position(2, 6))
    assert_selection_eq(
      cursor.get_view_selection(),
      cursor.get_model_selection(),
    )
  })
}

///|
/// `setPosition` (cew:670-682) builds a collapsed selection
/// (`selectionStart == position`); the read API reflects it immediately.
test "set_position collapses the selection at the target" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    viewer.set_position(Position(2, 5))
    assert_cursor(viewer, Selection(Position(2, 5), Position(2, 5)))
    assert_position(viewer.get_position().unwrap(), Position(2, 5))
    assert_true(viewer.get_selection().unwrap().is_empty())
  })
}

///|
/// `setSelection` preserves the anchor/active order it is given
/// (cursorCommon.ts:283-289 → `SingleCursorState.selection()`): anchor before
/// active is LTR, anchor after active (backward selecting) is RTL.
test "set_selection preserves direction for forward and backward input" {
  with_test_viewer("line one\nline two\nline three", viewer => {
    viewer.set_selection(Selection(Position(1, 3), Position(2, 4)))
    let forward = viewer.get_selection().unwrap()
    assert_true(forward.direction() == LTR)
    assert_position(forward.get_selection_start(), Position(1, 3))
    assert_position(forward.get_position(), Position(2, 4))
    viewer.set_selection(Selection(Position(2, 4), Position(1, 3)))
    let backward = viewer.get_selection().unwrap()
    assert_true(backward.direction() == RTL)
    assert_position(backward.get_selection_start(), Position(2, 4))
    assert_position(backward.get_position(), Position(1, 3))
  })
}

///|
/// Out-of-range input is clamped by the model, not stored raw
/// (oneCursor.ts:133-141: `validateRange` on the anchor, `validatePosition`
/// on the active end): a line past EOF snaps to the last line's max column, a
/// column past line-end snaps to the line's max column, and a column splitting
/// a surrogate pair snaps before the pair (the same snapping the
/// `validate_position` reference suite pins on this fixture).
test "set_selection clamps out-of-range positions to the model" {
  with_test_viewer("line one\nline two", viewer => {
    viewer.set_position(Position(99, 1))
    assert_position(viewer.get_position().unwrap(), Position(2, 9))
    viewer.set_selection(Selection(Position(1, 2), Position(1, 50)))
    assert_selection_eq(
      viewer.get_selection().unwrap(),
      Selection(Position(1, 2), Position(1, 9)),
    )
  })
  with_test_viewer("a\u{1F4DA}b", viewer => {
    // column 3 splits the U+1F4DA high-low pair; snaps before it, to column 2
    viewer.set_position(Position(1, 3))
    assert_cursor(viewer, Selection(Position(1, 2), Position(1, 2)))
  })
}

///|
/// The equality gate (cursor.ts:404-406): the first set fires both cursor
/// events carrying the new state; setting the exact same selection again
/// fires neither.
test "set_selection fires cursor events only when the state changes" {
  with_test_viewer("line one\nline two", viewer => {
    let mut position_fires = 0
    let mut selection_fires = 0
    let mut last_position : @base_common.Position = Position(1, 1)
    let mut last_selection = @core.Selection(Position(1, 1), Position(1, 1))
    viewer.on_did_change_cursor_position(event => {
      position_fires += 1
      last_position = event.position
    })
    |> ignore
    viewer.on_did_change_cursor_selection(event => {
      selection_fires += 1
      last_selection = event.selection
    })
    |> ignore
    let target = @core.Selection(Position(1, 3), Position(2, 4))
    viewer.set_selection(target)
    assert_eq(position_fires, 1)
    assert_eq(selection_fires, 1)
    assert_position(last_position, Position(2, 4))
    assert_selection_eq(last_selection, target)
    viewer.set_selection(target)
    assert_eq(position_fires, 1)
    assert_eq(selection_fires, 1)
  })
}

///|
/// With wrap on, the model selection is stored as given while the view state
/// is re-derived through the coordinates converter (oneCursor.ts:144-150):
/// "abcdefghij" wrapped at column 6 puts model column 7 on view line 2, so
/// the selection overlay's view range differs from the model selection.
test "set_selection re-derives the view state under wrap" {
  let options = ViewerOptions(soft_wrap=true)
  with_test_viewer(
    "abcdefghij",
    viewer => {
      viewer.test_set_soft_wrap_column(6)
      viewer.set_selection(Selection(Position(1, 3), Position(1, 9)))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(1, 3), Position(1, 9)),
      )
      let view_range = viewer.selection_view_range().unwrap()
      assert_eq(view_range.start_line_number, 1)
      assert_eq(view_range.start_column, 3)
      assert_eq(view_range.end_line_number, 2)
      assert_eq(view_range.end_column, 3)
    },
    options~,
  )
}

///|
/// The no-model guard (cew:671-673, :825-827): without a model both setters
/// are no-ops and no cursor event fires.
test "set_position and set_selection are no-ops without a model" {
  let viewer = Viewer::Viewer()
  let mut fires = 0
  viewer.on_did_change_cursor_position(_ => fires += 1) |> ignore
  viewer.on_did_change_cursor_selection(_ => fires += 1) |> ignore
  viewer.set_position(Position(2, 2))
  viewer.set_selection(Selection(Position(1, 1), Position(2, 2)))
  assert_eq(fires, 0)
  assert_true(viewer.get_selection() is None)
  viewer.dispose()
}

///|
/// A wrapping-width change re-projects the live selection *inside* the view
/// model (`_cursor.onLineMappingChanged`, `viewModelImpl.ts:287`): the model
/// selection is unchanged and the view selection lands on the new projection
/// with no Viewer-side re-point call in between.
test "wrap-width change re-projects the selection inside the view model" {
  let options = ViewerOptions(soft_wrap=true)
  with_test_viewer(
    "abcdefghij",
    viewer => {
      viewer.test_set_soft_wrap_column(6)
      viewer.set_selection(Selection(Position(1, 9), Position(1, 9)))
      // Wrapped at 6: model col 9 sits on view line 2, col 3.
      assert_position(
        viewer.test_cursor().get_view_selection().get_position(),
        Position(2, 3),
      )
      // Reflow to a narrower column through the Viewer/ViewModel path; the
      // headless harness observes the same committed cursor reprojection.
      viewer.test_set_soft_wrap_column(4)
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(1, 9), Position(1, 9)),
      )
      // Wrapped at 4: model col 9 starts the third view line.
      assert_position(
        viewer.test_cursor().get_view_selection().get_position(),
        Position(3, 1),
      )
    },
    options~,
  )
}
