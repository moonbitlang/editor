///|
fn hidden_area_zone_test_height(viewer : Viewer, zone_id : String) -> Int {
  for whitespace in viewer.test_view_model().get_whitespaces() {
    if whitespace.id == zone_id {
      return whitespace.height
    }
  }
  abort("missing source-aware ViewZone whitespace")
}

///|
test "raw hidden-source changes refresh source-aware zones without a mapping change" {
  with_mounted_test_viewer("first\nmarkdown\nthird", viewer => {
    let zone_id = Ref("")
    let zone = view_zone(
      2,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="markdown",
      height_in_px=19.0,
    )
    viewer.change_view_zones(accessor => zone_id.val = accessor.add_zone(zone))
    viewer.set_hidden_areas([Range(2, 1, 2, 1)], source="markdown")
    assert_eq(hidden_area_zone_test_height(viewer, zone_id.val), 19)

    let mut zone_changes = 0
    let listener = viewer.on_did_change_view_zones(() => zone_changes += 1)
    defer listener.dispose()
    // The folding range is entirely covered by the Markdown range. The view
    // line mapping stays identical, but the zone must now be suppressed by
    // the non-ignored source.
    viewer.set_hidden_areas([Range(2, 1, 2, 1)], source="folding")
    assert_eq(hidden_area_zone_test_height(viewer, zone_id.val), 0)
    assert_eq(zone_changes, 1)

    viewer.set_hidden_areas([], source="folding")
    assert_eq(hidden_area_zone_test_height(viewer, zone_id.val), 19)
    assert_eq(zone_changes, 2)
    viewer.set_hidden_areas([], source="folding")
    assert_eq(zone_changes, 2)
  })
}
