///|
test "model-line digit band preserves measured outer width before LayoutInfo" {
  with_test_viewer(["1", "2", "3", "4", "5", "6", "7", "8", "9"].join("\n"), viewer => {
    viewer.update_options(
      ViewerOptions(line_numbers_min_chars=1, folding=false),
    )
    viewer.test_set_viewport(width=360.0, height=180.0)
    let view_model = viewer.test_view_model()
    let configuration = viewer.configuration.snapshot()
    let previous_content_left = configuration.gutter_width(9)
    let current_content_left = configuration.gutter_width(10)
    assert_true(current_content_left > previous_content_left)
    let measured_outer_width = previous_content_left +
      configuration.content_width

    assert_true(viewer.sync_content_box_for_model_line_count(view_model, 10))
    let adjusted = viewer.configuration.snapshot()
    assert_eq(
      current_content_left + adjusted.content_width,
      measured_outer_width,
    )
    assert_eq(view_model.view_layout.dimensions().width, adjusted.content_width)
    let retained_width = adjusted.content_width
    viewer.configuration.set_line_counts(10, 10)
    assert_false(viewer.sync_content_box_for_model_line_count(view_model, 11))
    assert_eq(viewer.configuration.snapshot().content_width, retained_width)
  })
}
