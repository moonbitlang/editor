///|
test "ViewerOptions builders preserve an immutable opaque snapshot" {
  let original = ViewerOptions::default()
  let updated = original
    .with_placeholder("loading")
    .with_theme("light")
    .with_render_whitespace(All)
    .with_render_control_characters(false)
    .with_render_line_highlight(Gutter)
    .with_render_line_highlight_only_when_focus(true)
    .with_render_validation_decorations(Off)
    .with_tab_size(4)
    .with_soft_wrap(true)
    .with_line_numbers_min_chars(3)
    .with_line_decorations_width(17)
    .with_line_height(21.0)
  assert_eq(
    updated,
    ViewerOptions(
      placeholder="loading",
      theme="light",
      render_whitespace=All,
      render_control_characters=false,
      render_line_highlight=Gutter,
      render_line_highlight_only_when_focus=true,
      render_validation_decorations=Off,
      tab_size=4,
      soft_wrap=true,
      line_numbers_min_chars=3,
      line_decorations_width=17,
      line_height=21.0,
    ),
  )
  assert_eq(original, ViewerOptions::default())
  assert_false(original.soft_wrap())
  assert_true(updated.soft_wrap())
  assert_eq(updated.line_height(), 21.0)
}

///|
test "ViewerOptions builders preserve constructor normalization" {
  assert_eq(
    ViewerOptions::default().with_tab_size(0),
    ViewerOptions(tab_size=1),
  )
  assert_eq(
    ViewerOptions::default().with_line_numbers_min_chars(0),
    ViewerOptions(line_numbers_min_chars=1),
  )
  assert_eq(
    ViewerOptions::default().with_line_decorations_width(-1),
    ViewerOptions(line_decorations_width=0),
  )
}
