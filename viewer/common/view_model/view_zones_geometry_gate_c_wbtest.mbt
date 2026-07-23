///|
fn geometry_carrier_model() -> @model.TextModel {
  TextModel(
    @base_common.Uri::file("/view-zones-geometry-carrier.txt"),
    "view-zones-geometry-carrier.txt",
    "plaintext",
    1,
    "view-zones-geometry-carrier-rev-1",
    "one\ntwo",
  )
}

///|
test "viewport carrier keeps ToInt32 start then advances later offsets as Double" {
  let model = geometry_carrier_model()
  let view_model = ViewModel(model)
  let layout = @view_layout.ViewLayout(line_height=10, line_count=2)
  layout.set_viewport_size(width=100.0, height=100.0) |> ignore
  layout.change_whitespace(accessor => {
    // Four maximum ToInt32 heights put line 1 at raw top 8589934588 (> 2^32),
    // whose explicit source ToInt32 value is -4.
    for ordinal in 0..<4 {
      accessor.insert_whitespace(0, ordinal, 2147483647.0, 0.0) |> ignore
    }
    // The next line advances by an ordinary Number addition, not Int wrap.
    accessor.insert_whitespace(1, 0, 2147483647.0, 0.0) |> ignore
  })
  |> ignore

  let viewport = viewport_data_from_view_model(
    view_model,
    { start: 1, end: 3 },
    line_height=10,
    layout~,
  )
  assert_eq(viewport.big_numbers_delta, 0)
  assert_eq(viewport.relative_vertical_offset.length(), 2)
  assert_eq(viewport.relative_vertical_offset[0], -4.0)
  assert_eq(viewport.relative_vertical_offset[1], 2147483653.0)
  assert_true(viewport.relative_vertical_offset[1] > 2147483647.0)

  assert_true(viewport.view_zones.length() > 0)
  let whitespace_top : Double = viewport.view_zones[0].vertical_offset
  assert_eq(whitespace_top, 0.0)

  let rail = @view_layout.ViewLayout(line_height=18, line_count=2)
  rail.set_viewport_size(width=100.0, height=20.0) |> ignore
  rail.change_whitespace(accessor => {
    accessor.insert_whitespace(0, 0, 500000.0, 0.0) |> ignore
  })
  |> ignore
  let partial = rail.get_lines_viewport_data_at_scroll_top(500000.0)
  let carried = viewport_data_from_view_model(
    view_model,
    { start: partial.start_line_number, end: partial.end_line_number + 1 },
    line_height=999,
    layout=rail,
    partial_viewport=partial,
  )
  assert_eq(carried.big_numbers_delta, partial.big_numbers_delta)
  assert_eq(carried.line_height, partial.line_height)
  assert_eq(carried.line_height, 18)
  assert_eq(
    carried.relative_vertical_offset.length(),
    partial.relative_vertical_offset.length(),
  )
  for index in 0..<partial.relative_vertical_offset.length() {
    assert_eq(
      carried.relative_vertical_offset[index],
      partial.relative_vertical_offset[index],
    )
  }
  assert_eq(carried.big_numbers_delta, 499986)
  assert_eq(carried.relative_vertical_offset[0], 14.0)
  let carried_without_layout = viewport_data_from_view_model(
    view_model,
    { start: 2, end: 3 },
    line_height=999,
    partial_viewport=partial,
  )
  assert_eq(carried_without_layout.start_line_number, partial.start_line_number)
  assert_eq(carried_without_layout.end_line_number, partial.end_line_number)
  assert_eq(carried_without_layout.big_numbers_delta, partial.big_numbers_delta)
  assert_eq(carried_without_layout.line_height, partial.line_height)
  assert_eq(
    carried_without_layout.relative_vertical_offset[0],
    partial.relative_vertical_offset[0],
  )
  view_model.dispose()
  model.dispose()
}
