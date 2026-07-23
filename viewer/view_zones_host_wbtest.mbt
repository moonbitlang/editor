///|
test "root view_zone forwards the source-exclusion policy" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let zone = view_zone(
    7,
    @rdom.document().create_element("div"),
    show_in_hidden_areas=false,
    ignore_hidden_area_source="markdown-comments",
    height_in_px=12.0,
  )
  assert_eq(zone.after_line_number, 7)
  assert_true(zone.show_in_hidden_areas == Some(false))
  assert_true(zone.ignore_hidden_area_source == Some("markdown-comments"))
  assert_true(zone.height_in_px == Some(12.0))
}
