///|
test "cursors_layer_class ports _getClassName's reachable arms" {
  // viewCursors.ts:286-340 with readonly constants: line style, solid blink.
  inspect(
    cursors_layer_class(false),
    content="cursors-layer cursor-line-style cursor-solid",
  )
  // :288-290 — a non-empty selection adds `has-selection`.
  inspect(
    cursors_layer_class(true),
    content="cursors-layer has-selection cursor-line-style cursor-solid",
  )
}

///|
test "compute_screen_aware_size snaps to the device pixel grid" {
  // dom.ts computeScreenAwareSize: max(1, floor(dpr*css)) / dpr.
  inspect(compute_screen_aware_size(1.0, 2.0), content="2")
  inspect(compute_screen_aware_size(2.0, 2.0), content="2")
  // floor(1.25*2)=2 → 2/1.25 = 1.6 (a sub-CSS-pixel-snapped width).
  inspect(compute_screen_aware_size(1.25, 2.0), content="1.6")
  // The max(1, …) clamp: half a CSS pixel still paints one device pixel.
  inspect(compute_screen_aware_size(1.0, 0.5), content="1")
}

///|
test "prepare_cursor_render_data ports the Line-style arm" {
  // viewCursor.ts:196-200 — a caret at least 1px in and at least 2px wide
  // shifts left by a 1px padding so the bar straddles the boundary.
  debug_inspect(
    prepare_cursor_render_data(10.0, 36, 18, 1.0),
    content="{ top: 36, left: 9, padding_left: 1, width: 2, height: 18 }",
  )
  // left < 1 → no shift (the caret hugs the line start).
  debug_inspect(
    prepare_cursor_render_data(0.0, 0, 18, 1.0),
    content="{ top: 0, left: 0, padding_left: 0, width: 2, height: 18 }",
  )
  // width < 2 after device-pixel snapping → no shift either (`width >= 2`).
  debug_inspect(
    prepare_cursor_render_data(10.0, 0, 18, 1.25),
    content="{ top: 0, left: 10, padding_left: 0, width: 1.6, height: 18 }",
  )
}
