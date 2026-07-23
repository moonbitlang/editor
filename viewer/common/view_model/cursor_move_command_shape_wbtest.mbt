///|
fn cursor_move_shape_model(text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="cursor-move-shape",
      path="/model.mbt",
    ),
    "cursor-move-shape",
    "plaintext",
    1,
    "",
    text,
  )
}

///|
test "moveTo resolves absent supplied and inconsistent view positions" {
  let view_model = ViewModel::with_options(
    cursor_move_shape_model("abcdefghij"),
    ViewModelOptions::soft_wrap(5),
  )
  let mut outgoing = 0
  view_model.on_cursor_state_changed(_ => outgoing += 1) |> ignore

  // Absent `viewPosition` converts the validated model position.
  view_model.move_cursor_to_model_position(Position(1, 6), false) |> ignore
  assert_true(view_model.cursor.model_state().position == Position(1, 6))
  assert_true(view_model.cursor.view_state().position == Position(2, 1))

  // Both sides of this wrap boundary map to model (1,6). A supplied valid
  // view position therefore stays authoritative instead of using the default
  // model-to-view side.
  assert_true(
    view_model.move_cursor_to_model_position(
      Position(1, 6),
      false,
      view_position=Position(1, 6),
    ),
  )
  assert_true(view_model.cursor.model_state().position == Position(1, 6))
  assert_true(view_model.cursor.view_state().position == Position(1, 6))
  assert_eq(outgoing, 1)

  // A supplied view position that maps somewhere else is rejected and the
  // validated model coordinate is converted instead.
  view_model.move_cursor_to_model_position(
    Position(1, 8),
    false,
    view_position=Position(1, 2),
  )
  |> ignore
  assert_true(view_model.cursor.model_state().position == Position(1, 8))
  assert_true(view_model.cursor.view_state().position == Position(2, 3))
}

///|
test "supplied injected-text interior keeps normalization residue" {
  let model = cursor_move_shape_model("abcdef")
  model.delta_decorations([], [
    {
      range: Range(1, 4, 1, 4),
      options: ModelDecorationOptions(
        "",
        description="cursor interior residue",
        show_if_collapsed=true,
        after=InjectedTextOptions("XYZ"),
      ),
    },
  ])
  |> ignore
  let view_model = ViewModel::with_options(model, ViewModelOptions::no_wrap())
  let converter = view_model.coordinates_converter()
  let mut candidate : (
    @base_common.Position,
    @base_common.Position,
    @base_common.Position,
  )? = None
  for column in 1..<=view_model.get_line_max_column(1) {
    let supplied = @base_common.Position::Position(1, column)
    let normalized = view_model.normalize_position(supplied, None)
    if candidate is None && supplied != normalized {
      candidate = Some(
        (
          supplied,
          normalized,
          converter.view_position_to_model_position(supplied),
        ),
      )
    }
  }
  guard candidate is Some((supplied, normalized, model_position)) else {
    fail("expected an injected-text interior view position")
  }
  view_model.move_cursor_to_model_position(
    model_position,
    false,
    view_position=supplied,
  )
  |> ignore
  let state = view_model.cursor.view_state()
  assert_true(state.position == normalized)
  assert_eq(state.leftover_visible_columns, supplied.column - normalized.column)
  assert_eq(
    state.selection_start_leftover_visible_columns,
    supplied.column - normalized.column,
  )
}

///|
test "line command covers optional view and final model line clamps" {
  let view_model = ViewModel::with_options(
    cursor_move_shape_model("abcdefghij\nz"),
    ViewModelOptions::soft_wrap(5),
  )

  // The absent view-position branch converts the model target before entering
  // Line selection; the model state selects through the next line's start.
  view_model.move_cursor_line(Position(1, 6), false) |> ignore
  let first = view_model.cursor.model_state()
  assert_true(first.selection_start_kind == Line)
  assert_true(first.selection_start_start == Position(1, 1))
  assert_true(first.selection_start_end == Position(2, 1))
  assert_true(first.position == Position(2, 1))

  // Entering on the last model line clamps the following-line target to that
  // line's maximum column.
  view_model.move_cursor_line(
    Position(2, 1),
    false,
    view_position=Position(3, 1),
  )
  |> ignore
  let last = view_model.cursor.model_state()
  assert_true(last.selection_start_start == Position(2, 1))
  assert_true(last.selection_start_end == Position(2, 2))
  assert_true(last.position == Position(2, 2))
}

///|
test "line continuation clamps a following view line beyond EOF" {
  let view_model = ViewModel::with_options(
    cursor_move_shape_model("a\nb"),
    ViewModelOptions::soft_wrap(20),
  )
  view_model.move_cursor_line(Position(1, 1), false) |> ignore
  // The target is after the entering line and its following view line would
  // be 3, beyond the two-line view. The command clamps to line 2 max column.
  view_model.move_cursor_line(
    Position(2, 1),
    true,
    view_position=Position(2, 1),
  )
  |> ignore
  assert_true(view_model.cursor.view_state().position == Position(2, 2))
  assert_eq(view_model.cursor.view_state().leftover_visible_columns, 0)
}
