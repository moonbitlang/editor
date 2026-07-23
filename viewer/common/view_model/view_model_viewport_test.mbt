///|
test "validation decoration filtering preserves readonly policy" {
  assert_true(@view_model.filter_validation_decorations(Editable))
  assert_false(@view_model.filter_validation_decorations(On))
  assert_true(@view_model.filter_validation_decorations(Off))
}

///|
test "view model produces viewport data from layout window" {
  let view_model = @view_model.ViewModel(plain_text_model("a\nbb\nccc"))
  let viewport = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 2, end: 4 },
    line_height=18,
  )
  assert_eq(viewport.start_line_number, 2)
  assert_eq(viewport.end_line_number, 3)
  assert_eq(viewport.line_data(2).unwrap().content, "bb")
  assert_eq(viewport.line_data(3).unwrap().content, "ccc")
  debug_inspect(
    viewport.relative_vertical_offset,
    content=(
      #|[0, 18]
    ),
  )
  let layout = @view_layout.ViewLayout(line_height=18, line_count=3)
  layout.set_viewport_size(width=400.0, height=100.0) |> ignore
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(1, 0, 36.0, 0.0) |> ignore
  })
  |> ignore
  let displaced = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 2, end: 4 },
    line_height=18,
    layout~,
  )
  debug_inspect(
    displaced.relative_vertical_offset,
    content=(
      #|[54, 72]
    ),
  )
  assert_eq(displaced.view_zones.length(), 1)
  assert_true(displaced.view_zones[0].id.length() > 0)
  assert_eq(displaced.view_zones[0].after_line_number, 1)
  assert_eq(displaced.view_zones[0].height, 36)
  assert_eq(displaced.view_zones[0].vertical_offset, 18)
}

///|
/// End-to-end Phase-3 chain: decorations stored on the model reach the
/// viewport's per-line `LineDecoration`s through `ViewModelDecorations` →
/// `InlineModelDecorationsComputer` → `line_decorations_for_line`.
test "viewport line decorations come from model decoration storage" {
  let text = "alpha beta\ngamma delta\nepsilon"
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/storage.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    text,
  )
  let _ = model.delta_decorations([], [
    {
      range: Range(1, 1, 1, 6),
      options: ModelDecorationOptions(
        "squiggly-warning",
        inline_class_name="squiggly-inline-unnecessary",
        show_if_collapsed=true,
        description="test",
      ),
    },
    // collapsed marker at EOL: only the transitional className span renders
    // (1ch wide), never the inline class (Monaco drops empty-range inline
    // decorations)
    {
      range: Range(2, 12, 2, 12),
      options: ModelDecorationOptions(
        "squiggly-error",
        show_if_collapsed=true,
        description="test",
      ),
    },
  ])
  register_plain_moonbit()
  let view_model = @view_model.ViewModel::with_options(
    model,
    ViewModelOptions(render_validation_decorations=On),
  )
  let viewport = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 1, end: 4 },
    line_height=18,
  )
  // The inline chain feeds the line spans; className decorations render
  // through the DecorationsOverlay instead (never as line spans).
  let line1 = viewport.line_decorations[0]
  assert_true(
    line1.any(d => {
      d.class_name == "squiggly-inline-unnecessary" &&
      d.start_column == 1 &&
      d.end_column == 6
    }),
  )
  assert_false(line1.any(d => d.class_name == "squiggly-warning"))
  assert_eq(viewport.line_decorations[1].length(), 0)
  assert_eq(viewport.line_decorations[2].length(), 0)
  // …while the viewport collection carries both className decorations for
  // the overlay.
  let collection = view_model
    .decorations()
    .get_decorations_viewport_data(Range(1, 1, 3, 8))
  let class_names = collection.decorations.map(d => d.options.class_name)
  assert_true(class_names.contains("squiggly-warning"))
  assert_true(class_names.contains("squiggly-error"))
  // renderValidationDecorations=Off filters squiggly-error/warning/info out
  let filtered_view_model = @view_model.ViewModel::with_options(
    model,
    ViewModelOptions(render_validation_decorations=Off),
  )
  let filtered = @view_model.viewport_data_from_view_model(
    filtered_view_model,
    { start: 1, end: 4 },
    line_height=18,
  )
  assert_eq(filtered.line_decorations[0].length(), 0)
  assert_eq(filtered.line_decorations[1].length(), 0)
}
