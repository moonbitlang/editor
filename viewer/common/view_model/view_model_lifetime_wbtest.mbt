///|
test "ViewModel dispose clears only projected owner-0 hidden decorations" {
  let model = cursor_reference_model("one\ntwo\nthree\nfour")
  let unrelated_owner0 = model.delta_decorations([], [
    {
      range: Range(1, 1, 1, 2),
      options: ModelDecorationOptions("", description="unrelated-owner-0"),
    },
  ])
  let unrelated_editor = model.delta_decorations(
    [],
    [
      {
        range: Range(4, 1, 4, 2),
        options: ModelDecorationOptions(
          "",
          description="unrelated-editor-owner",
        ),
      },
    ],
    owner_id=73,
  )
  let view_model = ViewModel(model)
  assert_true(view_model.set_hidden_areas([Range(2, 1, 3, 1)]))
  assert_eq(view_model.lines.hidden_areas_decoration_ids.length(), 1)
  assert_eq(model.get_all_decorations().length(), 3)

  view_model.dispose()
  assert_eq(view_model.lines.hidden_areas_decoration_ids.length(), 0)
  assert_eq(model.get_all_decorations().length(), 2)
  assert_true(model.get_decoration_range(unrelated_owner0[0]) is Some(_))
  assert_true(model.get_decoration_range(unrelated_editor[0]) is Some(_))

  // The stored id array is already empty, so repeated disposal is harmless.
  view_model.dispose()
  assert_eq(model.get_all_decorations().length(), 2)
}

///|
test "projected dispose clears zero one and many hidden decoration ids" {
  let zero_model = cursor_reference_model("one\ntwo")
  let zero = ViewModel(zero_model)
  zero.lines.dispose()
  assert_eq(zero_model.get_all_decorations().length(), 0)

  let many_model = cursor_reference_model("one\ntwo\nthree\nfour\nfive")
  let many = ViewModel(many_model)
  assert_true(many.set_hidden_areas([Range(2, 1, 2, 1), Range(4, 1, 4, 1)]))
  assert_eq(many.lines.hidden_areas_decoration_ids.length(), 2)
  many.lines.dispose()
  assert_eq(many.lines.hidden_areas_decoration_ids.length(), 0)
  assert_eq(many_model.get_all_decorations().length(), 0)
}
