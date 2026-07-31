///|
test "Markdown hover geometry uses pointer x line rect and viewport clamps" {
  // Fits below; x is relative to the viewport.
  assert_eq(
    markdown_hover_clamped_origin(
      180.0, 120.0, 140.0, 100.0, 100.0, 400.0, 300.0, 120.0, 80.0,
    ),
    (40.0, 80.0),
  )
  // Does not fit below, so use the rendered line's top edge and clamp both
  // axes into the viewport.
  assert_eq(
    markdown_hover_clamped_origin(
      590.0, 350.0, 370.0, 100.0, 100.0, 400.0, 300.0, 120.0, 100.0,
    ),
    (150.0, 280.0),
  )
}

///|
test "Markdown hover geometry coalesces client rects within visual rows" {
  assert_eq(
    markdown_hover_fragment_geometry([
      // Computed line height and the logical line's two-row box height.
      20.0, 40.0,
      // Raw client rects are deliberately out of visual order.
       2.0, 23.0, 8.0, 14.0, 15.0, 3.0, 7.0, 14.0, 10.0, 3.0, 5.0, 14.0,
      // A same-row bidi-style gap remains a separate fragment.
       40.0, 3.0, 4.0, 14.0,
    ]),
    [10.0, 0.0, 12.0, 20.0, 40.0, 0.0, 4.0, 20.0, 2.0, 20.0, 8.0, 20.0],
  )
  // Monaco's non-showIfCollapsed hover decoration does not widen an empty
  // range merely to make it visible.
  assert_eq(
    markdown_hover_fragment_geometry([20.0, 20.0, 5.0, 3.0, 0.0, 14.0]),
    [5.0, 0.0, 0.0, 20.0],
  )
}
