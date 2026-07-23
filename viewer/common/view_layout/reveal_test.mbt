///|
/// Builds a 1000-line layout with an 18px line height and a 180px (10-line)
/// viewport scrolled so view lines 21..30 are visible
/// (`viewport_start_y = 360`, `viewport_end_y = 540`). With no view zones,
/// `vertical_offset_for_line(n) == (n - 1) * 18`, so every expectation below is
/// hand-computable.
fn reveal_layout() -> @view_layout.ViewLayout {
  let layout = @view_layout.ViewLayout(line_height=18, line_count=1000)
  layout.set_viewport_size(width=800.0, height=180.0) |> ignore
  layout.scroll_to(scroll_top=360.0) |> ignore
  layout
}

///|
test "reveal Simple scrolls a line just into view" {
  let layout = reveal_layout()
  // Line above the viewport: scroll up so its top aligns.
  assert_eq(layout.compute_scroll_top_to_reveal_range(5, 5, Simple), 72.0)
  // Line already inside the viewport: no scroll.
  assert_eq(layout.compute_scroll_top_to_reveal_range(25, 25, Simple), 360.0)
  // Line below the viewport: scroll down, keeping the +1 bottom pad clear of
  // the horizontal scrollbar (box_end 918 - viewport 180 = 738).
  assert_eq(layout.compute_scroll_top_to_reveal_range(50, 50, Simple), 738.0)
}

///|
test "minimal reveal omits cursor bottom padding at viewport edge" {
  let layout = reveal_layout()
  // View line 30 ends exactly at the viewport bottom. The ordinary keyboard
  // reveal keeps one more line clear; a pointer-command minimal reveal does
  // not move it at all.
  assert_eq(layout.compute_scroll_top_to_reveal_range(30, 30, Simple), 378.0)
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(
      30,
      30,
      Simple,
      source="mouse",
      minimal_reveal=true,
    ),
    360.0,
  )
  // Outside the viewport the same omission is exactly one line (18px).
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(
      50,
      50,
      Simple,
      source="mouse",
      minimal_reveal=true,
    ),
    720.0,
  )
}

///|
test "non-minimal mouse reveal adds one line above" {
  let layout = reveal_layout()
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(
      20,
      20,
      Simple,
      source="mouse",
      minimal_reveal=false,
    ),
    324.0,
  )
}

///|
test "reveal Center and CenterIfOutsideViewport" {
  let layout = reveal_layout()
  // Center: box middle 891, minus half the viewport (90) = 801.
  assert_eq(layout.compute_scroll_top_to_reveal_range(50, 50, Center), 801.0)
  // CenterIfOutsideViewport, already visible: no scroll.
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(25, 25, CenterIfOutsideViewport),
    360.0,
  )
  // CenterIfOutsideViewport, outside: same as Center.
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(50, 50, CenterIfOutsideViewport),
    801.0,
  )
}

///|
test "reveal NearTop and NearTopIfOutsideViewport" {
  let layout = reveal_layout()
  // NearTop: 20% of 180 = 36, but min 5 lines = 90 wins; box top 882 - 90 = 792
  // (and the min-scroll-top floor 900 - 180 = 720 does not bind).
  assert_eq(layout.compute_scroll_top_to_reveal_range(50, 50, NearTop), 792.0)
  // NearTopIfOutsideViewport, already visible: no scroll.
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(25, 25, NearTopIfOutsideViewport),
    360.0,
  )
  // NearTopIfOutsideViewport, outside: same as NearTop.
  assert_eq(
    layout.compute_scroll_top_to_reveal_range(50, 50, NearTopIfOutsideViewport),
    792.0,
  )
}

///|
test "reveal Top and Bottom align to viewport edges" {
  let layout = reveal_layout()
  // Top: box top straight to the viewport top (no +1 bottom pad).
  assert_eq(layout.compute_scroll_top_to_reveal_range(50, 50, Top), 882.0)
  // Bottom: +1 bottom pad, box_end 918 - viewport 180 = 738.
  assert_eq(layout.compute_scroll_top_to_reveal_range(50, 50, Bottom), 738.0)
}

///|
test "reveal oversized single range scrolls to its top, never -1" {
  let layout = reveal_layout()
  // Lines 5..30 span 26 lines (468px) > the 180px viewport. A single range, so
  // Monaco reveals its top rather than aborting with -1.
  assert_eq(layout.compute_scroll_top_to_reveal_range(5, 30, Simple), 72.0)
  assert_eq(layout.compute_scroll_top_to_reveal_range(5, 30, Center), 72.0)
  assert_eq(layout.compute_scroll_top_to_reveal_range(5, 30, Top), 72.0)
}

///|
test "reveal NearTop near the document top yields an unclamped offset" {
  let layout = reveal_layout()
  // Box top 0 (line 1) - desired gap 90 = -90; min-scroll-top -180 does not
  // bind. The core returns the raw -90; Scrollable clamps it to 0 downstream.
  assert_eq(layout.compute_scroll_top_to_reveal_range(1, 1, NearTop), -90.0)
}

///|
/// Builds the same layout with a 2000px-wide content extent so horizontal
/// scrolling has room. Viewport width 800, vertical scrollbar 14 ⇒
/// `viewport_end_x = scroll_left + 800 - 14`.
fn horizontal_layout() -> @view_layout.ViewLayout {
  let layout = @view_layout.ViewLayout(line_height=18, line_count=1000)
  layout.set_viewport_size(width=800.0, height=180.0) |> ignore
  layout.set_content_width(2000.0) |> ignore
  layout
}

///|
test "compute_scroll_left_to_reveal scrolls a box right of the viewport" {
  let layout = horizontal_layout()
  // Box at content x 1000..1050, padded by -30 left / +15 right to 970..1065.
  // viewport 0..786, so the box sits to the right: scroll to
  // box_end - viewport_length = 1065 - 786 = 279.
  debug_inspect(
    layout.compute_scroll_left_to_reveal(
      [(1000.0, 50.0)],
      vertical_scrollbar_width=14.0,
    ),
    content="Some(279)",
  )
}

///|
test "minimal horizontal reveal omits left and right padding" {
  let layout = horizontal_layout()
  debug_inspect(
    layout.compute_scroll_left_to_reveal(
      [(1000.0, 50.0)],
      vertical_scrollbar_width=14.0,
      minimal_reveal=true,
    ),
    content="Some(264)",
  )
  debug_inspect(
    layout.compute_scroll_left_to_reveal(
      [(1000.0, 0.0)],
      vertical_scrollbar_width=14.0,
      minimal_reveal=true,
    ),
    content="Some(214)",
  )
}

///|
test "compute_scroll_left_to_reveal leaves an in-view box untouched" {
  let layout = horizontal_layout()
  // Box at 100..150, padded to 70..180, fully inside viewport 0..786.
  debug_inspect(
    layout.compute_scroll_left_to_reveal(
      [(100.0, 50.0)],
      vertical_scrollbar_width=14.0,
    ),
    content="Some(0)",
  )
}

///|
test "compute_scroll_left_to_reveal scrolls back to a box left of the viewport" {
  let layout = horizontal_layout()
  layout.scroll_to(scroll_top=0.0, scroll_left=500.0) |> ignore
  // Box at 100..150 padded to 70..180; viewport 500..1286, box is to the left:
  // scroll left to the box start (70).
  debug_inspect(
    layout.compute_scroll_left_to_reveal(
      [(100.0, 50.0)],
      vertical_scrollbar_width=14.0,
    ),
    content="Some(70)",
  )
}

///|
test "compute_scroll_left_to_reveal handles a collapsed caret (zero-width rect)" {
  let layout = horizontal_layout()
  // A `reveal_position` caret measures to a single zero-width rect at its x
  // (Monaco keeps it). Box collapses to 1000..1000, padded to 970..1015;
  // viewport 0..786 → scroll to box_end - viewport_length = 1015 - 786 = 229.
  debug_inspect(
    layout.compute_scroll_left_to_reveal(
      [(1000.0, 0.0)],
      vertical_scrollbar_width=14.0,
    ),
    content="Some(229)",
  )
}

///|
test "compute_scroll_left_to_reveal returns None when nothing was measured" {
  let layout = horizontal_layout()
  assert_true(
    layout.compute_scroll_left_to_reveal([], vertical_scrollbar_width=14.0)
    is None,
  )
}
