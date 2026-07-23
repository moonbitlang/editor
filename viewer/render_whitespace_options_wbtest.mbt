// Stage-1 white-box for the viewport render path of the `renderWhitespace` /
// `renderControlCharacters` options (plan:
// monaco-render-whitespace-control-options-port.md). Proves the private
// `render_line_input_for_viewport` seam carries the values sourced from
// `ViewerOptions` into the per-line `RenderLineInput`, the same wiring
// the ViewLines live configuration reader performs.

///|
/// Builds the viewport a headless viewer projects for its first render, the
/// input `render_line_input_for_viewport` consumes during `render_text`.
fn viewport_of(viewer : Viewer) -> @view_layout.ViewportData {
  let configuration = viewer.configuration.snapshot().view_lines_configuration()
  @view_model.viewport_data_from_view_model(
    viewer.test_view_model(),
    viewer.test_window(),
    line_height=configuration.line_height,
  )
}

///|
fn retained_line_options_of(viewer : Viewer) -> @view.ViewLineOptions {
  viewer.configuration.snapshot().view_lines_configuration().view_line_options
}

///|
test "viewer options default to Selection whitespace and control characters on" {
  let options = ViewerOptions::default()
  assert_true(options.render_whitespace == Selection)
  assert_true(options.render_control_characters)
}

///|
test "viewport line input carries each content-only whitespace mode from options" {
  let modes : Array[@editor_api.RenderWhitespace] = [
    None,
    Boundary,
    Trailing,
    All,
  ]
  for mode in modes {
    let options = ViewerOptions(render_whitespace=mode)
    with_test_viewer(
      "  abc  ",
      viewer => {
        let input = @view.render_line_input_for_viewport(
          viewport_of(viewer),
          0,
          retained_line_options_of(viewer),
          selection_view_range=None,
        )
        assert_true(input.render_whitespace == mode)
      },
      options~,
    )
  }
}

///|
test "viewport line input carries render_control_characters on a non-ascii line" {
  let options = ViewerOptions(render_control_characters=true)
  with_test_viewer(
    "café\u{202E}",
    viewer => {
      let input = @view.render_line_input_for_viewport(
        viewport_of(viewer),
        0,
        retained_line_options_of(viewer),
        selection_view_range=None,
      )
      assert_true(input.render_control_characters)
      assert_false(input.is_basic_ascii)
    },
    options~,
  )
}

///|
test "viewport line input leaves Selection mode inert without a threaded selection" {
  let options = ViewerOptions(render_whitespace=Selection)
  with_test_viewer(
    "  abc  ",
    viewer => {
      let input = @view.render_line_input_for_viewport(
        viewport_of(viewer),
        0,
        retained_line_options_of(viewer),
        selection_view_range=None,
      )
      assert_true(input.render_whitespace == Selection)
      // With no selection threaded, Selection mode resolves to an empty range
      // set and the renderer's Selection branch renders nothing.
      assert_eq(input.selections_on_line.length(), 0)
    },
    options~,
  )
}

///|
test "retained options carry same-space font axes into render input" {
  with_test_viewer(" a ", viewer => {
    let base = retained_line_options_of(viewer)
    let options = @view.ViewLineOptions::ViewLineOptions(
      line_height=base.line_height,
      space_width=base.space_width,
      middot_width=base.space_width + 1.0,
      wsmiddot_width=base.space_width + 2.0,
      use_monospace_optimizations=false,
      can_use_halfwidth_rightwards_arrow=base.can_use_halfwidth_rightwards_arrow,
      stop_rendering_line_after=17,
      render_whitespace=All,
      render_control_characters=true,
      font_ligatures=true,
      vertical_scrollbar_size=19.0,
    )
    let input = @view.render_line_input_for_viewport(
      viewport_of(viewer),
      0,
      options,
      selection_view_range=None,
    )
    assert_eq(input.space_width, base.space_width)
    assert_eq(input.render_space_width, base.space_width + 1.0)
    assert_eq(input.render_space_char_code, 0x00B7)
    assert_false(input.use_monospace_optimizations)
    assert_eq(input.stop_rendering_line_after, 17)
    assert_true(input.render_whitespace == All)
    assert_true(input.render_control_characters)
    assert_true(input.font_ligatures)
    assert_eq(input.vertical_scrollbar_size, 19.0)
  })
}
