///|
test "viewer options default to Selection whitespace and control characters on" {
  let options = ViewerOptions::default()
  assert_true(options.render_whitespace == Selection)
  assert_true(options.render_control_characters)
}
