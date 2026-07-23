// Stage-1 white-box for the `renderWhitespace` / `renderControlCharacters`
// option passthrough (plan: monaco-render-whitespace-control-options-port.md).
// Asserts the headless `render_line_input_from_view_line_data` seam carries the
// option values into `RenderLineInput` — the values an embedder sets on
// `ViewerOptions`. The *rendering* of the resulting glyphs is already proven by
// the conformance suite in `view_line_renderer/`; here we only prove the feed.

///|
test "render line input passes through each content-only whitespace mode" {
  let doc = @model.TextSnapshot("  abc  ")
  let line = view_model_for(doc).lines().get_view_line_data(1)
  // None / Boundary / Trailing / All are pure passthroughs of the option value
  // (Stage 1 — no per-line selection needed).
  assert_true(
    @view_model.render_line_input_from_view_line_data(
      line,
      render_whitespace=None,
    ).render_whitespace ==
    None,
  )
  assert_true(
    @view_model.render_line_input_from_view_line_data(
      line,
      render_whitespace=Boundary,
    ).render_whitespace ==
    Boundary,
  )
  assert_true(
    @view_model.render_line_input_from_view_line_data(
      line,
      render_whitespace=Trailing,
    ).render_whitespace ==
    Trailing,
  )
  assert_true(
    @view_model.render_line_input_from_view_line_data(
      line,
      render_whitespace=All,
    ).render_whitespace ==
    All,
  )
}

///|
test "render line input passes through render_control_characters on a non-ascii line" {
  let doc = @model.TextSnapshot("café\u{202E}")
  let line = view_model_for(doc).lines().get_view_line_data(1)
  let on = @view_model.render_line_input_from_view_line_data(
    line,
    render_control_characters=true,
  )
  // A non-ASCII line is the case where the renderer's `!is_basic_ascii` control
  // gate fires; assert both the flag is carried and the line trips that gate.
  assert_true(on.render_control_characters)
  assert_false(on.is_basic_ascii)
  let off = @view_model.render_line_input_from_view_line_data(
    line,
    render_control_characters=false,
  )
  assert_false(off.render_control_characters)
}

///|
test "selection mode with no threaded selection is an inert no-op" {
  let doc = @model.TextSnapshot("  abc  ")
  let line = view_model_for(doc).lines().get_view_line_data(1)
  // Stage 1 has no path to thread per-line selection through this seam, so
  // Selection mode resolves to empty `selections_on_line`; the renderer's
  // Selection branch then produces nothing. The no-op is intentional, not a
  // silent gap — Stage 2 fills `selections_on_line`.
  let input = @view_model.render_line_input_from_view_line_data(
    line,
    render_whitespace=Selection,
  )
  assert_true(input.render_whitespace == Selection)
  assert_eq(input.selections_on_line.length(), 0)
}
