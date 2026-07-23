// Headless behavior-variable matrix for the 16 bound cursor navigation keys.
// Real KeyboardEvent/default/focus coverage lives in the component browser
// scenario; this file owns state axes that require direct model/view reads.

///|
test "Home End cover whitespace empty wrapped continuation and boundaries" {
  let options = ViewerOptions(soft_wrap=true)
  with_test_viewer(
    "   \n\n  abcdefghij",
    viewer => {
      viewer.test_set_soft_wrap_column(6)

      viewer.set_position(Position(1, 2))
      assert_true(dispatch_navigation_key(viewer, "Home"))
      assert_position(viewer.get_position().unwrap(), Position(1, 1))
      viewer.set_position(Position(1, 2))
      assert_true(dispatch_navigation_key(viewer, "End"))
      assert_position(viewer.get_position().unwrap(), Position(1, 4))

      viewer.set_position(Position(2, 1))
      let mut events = 0
      viewer.on_did_change_cursor_position(_ => events += 1) |> ignore
      assert_true(dispatch_navigation_key(viewer, "Home"))
      assert_true(dispatch_navigation_key(viewer, "End"))
      assert_position(viewer.get_position().unwrap(), Position(2, 1))
      assert_eq(events, 0)

      let view_model = viewer.test_view_model()
      view_model.move_cursor_to(Position(4, 4), false) |> ignore
      let first_non_blank = @base_common.first_non_whitespace_index(
          view_model.get_line_content(4),
        ) +
        1
      assert_true(dispatch_navigation_key(viewer, "Home"))
      assert_position(
        viewer.test_cursor().view_state().position,
        Position(4, first_non_blank),
      )
      assert_true(dispatch_navigation_key(viewer, "Home"))
      assert_position(
        viewer.test_cursor().view_state().position,
        Position(3, 3),
      )
      assert_true(dispatch_navigation_key(viewer, "Home"))
      assert_position(
        viewer.test_cursor().view_state().position,
        Position(3, 1),
      )

      view_model.move_cursor_to(Position(4, 3), false) |> ignore
      let view_end = view_model.get_line_max_column(4)
      assert_true(dispatch_navigation_key(viewer, "End"))
      assert_position(
        viewer.test_cursor().view_state().position,
        Position(4, view_end),
      )

      viewer.set_position(Position(3, 13))
      let before = viewer.test_cursor().get_primary_cursor_state()
      assert_true(dispatch_navigation_key(viewer, "End"))
      assert_true(viewer.test_cursor().get_primary_cursor_state() == before)
    },
    options~,
  )
}

///|
test "nonempty selection collapse paths cover Left Right Up Down" {
  with_test_viewer("abcdefgh\nabcdefgh\nabcdefgh\nabcdefgh\nabcdefgh", viewer => {
    let selection = @core.Selection(Position(2, 3), Position(4, 5))
    viewer.set_selection(selection)
    assert_true(dispatch_navigation_key(viewer, "ArrowLeft"))
    assert_position(viewer.get_position().unwrap(), Position(2, 3))
    assert_true(viewer.get_selection().unwrap().is_empty())

    viewer.set_selection(selection)
    assert_true(dispatch_navigation_key(viewer, "ArrowRight"))
    assert_position(viewer.get_position().unwrap(), Position(4, 5))
    assert_true(viewer.get_selection().unwrap().is_empty())

    viewer.set_selection(selection)
    assert_true(dispatch_navigation_key(viewer, "ArrowUp"))
    assert_position(viewer.get_position().unwrap(), Position(1, 3))
    assert_true(viewer.get_selection().unwrap().is_empty())

    viewer.set_selection(selection)
    assert_true(dispatch_navigation_key(viewer, "ArrowDown"))
    assert_position(viewer.get_position().unwrap(), Position(5, 5))
    assert_true(viewer.get_selection().unwrap().is_empty())
  })
}

///|
test "wrapped vertical navigation converts across folded model lines" {
  with_test_viewer("one\ntwo\nthree\nfour\nfive", viewer => {
    let view_model = viewer.test_view_model()
    assert_true(view_model.set_hidden_areas([Range(2, 1, 4, 1)]))
    viewer.set_position(Position(1, 2))
    assert_true(dispatch_navigation_key(viewer, "ArrowDown"))
    assert_position(viewer.get_position().unwrap(), Position(5, 2))
    assert_position(viewer.test_cursor().view_state().position, Position(2, 2))
    assert_true(dispatch_navigation_key(viewer, "ArrowUp"))
    assert_position(viewer.get_position().unwrap(), Position(1, 2))
    assert_position(viewer.test_cursor().view_state().position, Position(1, 2))
  })
}

///|
test "set_selections keeps only primary with default and override metadata" {
  with_test_viewer("one\ntwo", viewer => {
    let positions : Array[@editor_api.CursorPositionChangedEvent] = []
    let selections : Array[@editor_api.CursorSelectionChangedEvent] = []
    viewer.on_did_change_cursor_position(event => positions.push(event))
    |> ignore
    viewer.on_did_change_cursor_selection(event => selections.push(event))
    |> ignore
    let primary = @core.Selection(Position(2, 1), Position(2, 3))
    let secondary = @core.Selection(Position(1, 1), Position(1, 2))
    viewer.set_selections([primary, secondary])
    assert_true(viewer.get_selections().unwrap() == [primary])
    assert_eq(positions.length(), 1)
    assert_eq(selections.length(), 1)
    assert_eq(positions[0].secondary_positions.length(), 0)
    assert_eq(selections[0].secondary_selections.length(), 0)
    assert_eq(positions[0].source, "api")
    assert_true(positions[0].reason == NotSet)
    assert_eq(selections[0].source, "api")
    assert_true(selections[0].reason == NotSet)

    viewer.set_selections([secondary, primary], source="override", reason=Paste)
    assert_true(viewer.get_selections().unwrap() == [secondary])
    assert_eq(positions[1].source, "override")
    assert_true(positions[1].reason == Paste)
    assert_eq(selections[1].source, "override")
    assert_true(selections[1].reason == Paste)
  })
}

///|
test "one-element set_selections forwards exact source and reason" {
  with_test_viewer("one\ntwo", viewer => {
    let outgoing : Array[@view_model.CursorStateChangedEvent] = []
    let positions : Array[@editor_api.CursorPositionChangedEvent] = []
    let selections : Array[@editor_api.CursorSelectionChangedEvent] = []
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => outgoing.push(event))
    |> ignore
    viewer.on_did_change_cursor_position(event => positions.push(event))
    |> ignore
    viewer.on_did_change_cursor_selection(event => selections.push(event))
    |> ignore
    let expected = @core.Selection(Position(2, 1), Position(2, 3))
    viewer.set_selections([expected], source="one-element", reason=Redo)
    assert_true(viewer.get_selections().unwrap() == [expected])
    assert_eq(outgoing.length(), 1)
    assert_true(outgoing[0].selections == [expected])
    assert_eq(outgoing[0].source, "one-element")
    assert_true(outgoing[0].reason == Redo)
    assert_eq(positions.length(), 1)
    assert_eq(positions[0].source, "one-element")
    assert_true(positions[0].reason == Redo)
    assert_eq(selections.length(), 1)
    assert_selection_eq(selections[0].selection, expected)
    assert_eq(selections[0].source, "one-element")
    assert_true(selections[0].reason == Redo)
  })
}
