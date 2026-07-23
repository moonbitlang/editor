///|
test "scrollable clamps positions inside its dimensions" {
  let scrollable = @view_layout.Scrollable(force_integer_values=false)
  // Without dimensions the validated position clamps to the origin, while
  // Monaco retains the changed raw request and therefore emits an event.
  assert_true(
    scrollable.set_position({ scroll_left: 50.0, scroll_top: 100.0 }) is Some(_),
  )
  scrollable.set_dimensions({
    width: 800.0,
    scroll_width: 1000.0,
    height: 600.0,
    scroll_height: 1800.0,
  })
  |> ignore
  // Expanding the dimensions recovers the retained raw request.
  assert_true(scrollable.position() == { scroll_left: 50.0, scroll_top: 100.0 })
  assert_true(
    scrollable.set_position({ scroll_left: 50.0, scroll_top: 100.0 }) is None,
  )
  // Overshoot clamps to content minus viewport; undershoot clamps to zero.
  scrollable.set_position({ scroll_left: 9999.0, scroll_top: 99999.0 })
  |> ignore
  debug_inspect(
    scrollable.position(),
    content=(
      #|{ scroll_left: 200, scroll_top: 1200 }
    ),
  )
  scrollable.set_position({ scroll_left: -5.0, scroll_top: -5.0 }) |> ignore
  debug_inspect(
    scrollable.position(),
    content=(
      #|{ scroll_left: 0, scroll_top: 0 }
    ),
  )
  // A different raw request still changes ScrollState even when both values
  // clamp to the same validated origin.
  assert_true(
    scrollable.set_position({ scroll_left: -1.0, scroll_top: -1.0 }) is Some(_),
  )
}

///|
test "shrinking dimensions re-clamps the position as one change fact" {
  let scrollable = @view_layout.Scrollable(force_integer_values=false)
  scrollable.set_dimensions({
    width: 100.0,
    scroll_width: 100.0,
    height: 100.0,
    scroll_height: 1000.0,
  })
  |> ignore
  scrollable.set_position({ scroll_left: 0.0, scroll_top: 900.0 }) |> ignore
  let change = scrollable.set_dimensions({
    width: 100.0,
    scroll_width: 100.0,
    height: 100.0,
    scroll_height: 400.0,
  })
  guard change is Some(change) else { fail("expected a dimension change") }
  assert_true(change.position == { scroll_left: 0.0, scroll_top: 300.0 })
  assert_eq(change.delta_top, -600.0)
  assert_true(change.top_changed && change.dimensions_changed)
  // Base Scrollable preserves the supplied extents; EditorScrollDimensions
  // is the source layer that maxes content extents against the viewport.
  scrollable.set_dimensions({
    width: 500.0,
    scroll_width: 10.0,
    height: 600.0,
    scroll_height: 10.0,
  })
  |> ignore
  debug_inspect(
    scrollable.dimensions(),
    content=(
      #|{ width: 500, scroll_width: 10, height: 600, scroll_height: 10 }
    ),
  )
}

///|
/// Monaco `ScrollState`'s `width | 0` block under `forceIntegerValues: true`
/// (the editor's configuration): raw dimensions and positions truncate toward
/// zero before clamping, so scroll truth is always whole pixels.
test "force_integer_values truncates dimensions and positions" {
  let scrollable = @view_layout.Scrollable(force_integer_values=true)
  scrollable.set_dimensions({
    width: 800.4,
    scroll_width: 1000.9,
    height: 600.7,
    scroll_height: 1800.2,
  })
  |> ignore
  debug_inspect(
    scrollable.dimensions(),
    content=(
      #|{ width: 800, scroll_width: 1000, height: 600, scroll_height: 1800 }
    ),
  )
  // A fractional trackpad delta lands on the truncated integer...
  scrollable.set_position({ scroll_left: 0.0, scroll_top: 2.37 }) |> ignore
  debug_inspect(
    scrollable.position(),
    content=(
      #|{ scroll_left: 0, scroll_top: 2 }
    ),
  )
  // ...and truncation happens on the raw request, not the accumulated sum:
  // 2 + 2.37 = 4.37 truncates to 4 (fractions never accumulate).
  scrollable.scroll_by(delta_top=2.37) |> ignore
  debug_inspect(
    scrollable.position(),
    content=(
      #|{ scroll_left: 0, scroll_top: 4 }
    ),
  )
}

///|
/// The zero-based view-zone semantics now live in the `ViewLayout` adapter
/// (over the faithful 1-based `LinesLayout`); this is the regression net that
/// confirms the migration preserved that behavior.
test "lines layout answers offsets and lines for uniform heights" {
  let lines = @view_layout.ViewLayout(line_height=18, line_count=100)
  assert_eq(lines.vertical_offset_for_line(1), 0.0)
  assert_eq(lines.vertical_offset_for_line(11), 180.0)
  // One past the end probes the bottom edge; beyond clamps.
  assert_eq(lines.vertical_offset_for_line(101), 1800.0)
  assert_eq(lines.vertical_offset_for_line(1000), 1800.0)
  assert_eq(lines.line_at_vertical_offset(0.0), 1)
  assert_eq(lines.line_at_vertical_offset(17.9), 1)
  assert_eq(lines.line_at_vertical_offset(18.0), 2)
  assert_eq(lines.line_at_vertical_offset(99999.0), 100)
  assert_eq(lines.get_content_height(), 1800.0)
  let empty = @view_layout.ViewLayout(line_height=18)
  assert_eq(empty.line_at_vertical_offset(50.0), 1)
  assert_eq(empty.get_content_height(), 0.0)
}

///|
test "lines layout accounts for view zone displacement" {
  let lines = @view_layout.ViewLayout(line_height=18, line_count=5)
  let ids : Array[String] = []
  lines.change_whitespace(accessor => {
    ids.push(accessor.insert_whitespace(1, 0, 36.0, 0.0))
    ids.push(accessor.insert_whitespace(3, 1, 18.0, 0.0))
    ids.push(accessor.insert_whitespace(2, 2, 0.0, 0.0))
  })
  |> ignore
  assert_eq(lines.vertical_offset_for_line(1), 0.0)
  assert_eq(lines.vertical_offset_for_line(2), 54.0)
  assert_eq(lines.vertical_offset_for_line(4), 108.0)
  assert_eq(lines.vertical_offset_for_line(6), 144.0)
  assert_eq(lines.get_content_height(), 144.0)
  assert_eq(lines.line_at_vertical_offset(18.0), 2)
  assert_eq(lines.line_at_vertical_offset(53.0), 2)
  assert_eq(lines.line_at_vertical_offset(54.0), 2)
  assert_eq(lines.line_at_vertical_offset(90.0), 4)
  lines.change_whitespace(accessor => {
    for id in ids {
      accessor.remove_whitespace(id)
    }
  })
  |> ignore
  assert_eq(lines.vertical_offset_for_line(6), 90.0)
  assert_eq(lines.get_content_height(), 90.0)
}

///|
test "lines layout supports top and bottom view zones" {
  let lines = @view_layout.ViewLayout(line_height=18, line_count=3)
  lines.set_viewport_size(width=100.0, height=84.0) |> ignore
  lines.change_whitespace(accessor => {
    accessor.insert_whitespace(0, 0, 10.0, 0.0) |> ignore
    accessor.insert_whitespace(3, 1, 20.0, 0.0) |> ignore
  })
  |> ignore
  assert_eq(lines.vertical_offset_for_line(1), 10.0)
  assert_eq(lines.vertical_offset_for_line(4), 84.0)
  assert_eq(lines.get_content_height(), 84.0)
  let whitespace = lines.get_whitespace_viewport_data()
  assert_eq(whitespace.length(), 2)
  assert_true(whitespace[0].id != whitespace[1].id)
  assert_eq(whitespace[0].after_line_number, 0)
  assert_eq(whitespace[0].height, 10)
  assert_eq(whitespace[0].vertical_offset, 0)
  assert_eq(whitespace[1].after_line_number, 3)
  assert_eq(whitespace[1].height, 20)
  assert_eq(whitespace[1].vertical_offset, 64)
  lines.set_line_count(2) |> ignore
  let retained = lines.get_whitespaces()
  assert_eq(retained.length(), 2)
  assert_eq(retained[0].after_line_number, 0)
  assert_eq(retained[0].height, 10)
  assert_eq(retained[1].after_line_number, 3)
  assert_eq(retained[1].height, 20)
}

///|
/// The window is exactly the `getLinesViewportData` band — every line
/// intersecting `[scrollTop, scrollTop + height)`, partial edge lines
/// included, no overscan.
test "view layout window is exactly the viewport lines" {
  let layout = @view_layout.ViewLayout(line_height=18, line_count=10000)
  layout.set_viewport_size(width=800.0, height=600.0) |> ignore
  // 600px / 18px = 33.3 line heights: 34 lines intersect the viewport.
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 1, end: 35 }
    ),
  )
  layout.scroll_to(scroll_top=9000.0) |> ignore
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 501, end: 535 }
    ),
  )
  // Bottom of the document clamps the end.
  layout.scroll_to(scroll_top=179400.0) |> ignore
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 9967, end: 10001 }
    ),
  )
  // Tiny documents render entirely.
  let tiny = @view_layout.ViewLayout(line_height=18, line_count=10)
  tiny.set_viewport_size(width=800.0, height=600.0) |> ignore
  debug_inspect(
    tiny.visible_window(),
    content=(
      #|{ start: 1, end: 11 }
    ),
  )
}

///|
/// Every full-line scroll shifts the window immediately (no hysteresis);
/// a sub-line scroll inside the same band keeps it.
test "view layout window tracks every scroll" {
  let layout = @view_layout.ViewLayout(line_height=18, line_count=10000)
  layout.set_viewport_size(width=800.0, height=600.0) |> ignore
  layout.scroll_to(scroll_top=9000.0) |> ignore
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 501, end: 535 }
    ),
  )
  layout.scroll_to(scroll_top=9018.0) |> ignore
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 502, end: 536 }
    ),
  )
  // 9 px further is still inside line 502's band.
  layout.scroll_to(scroll_top=9027.0) |> ignore
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 502, end: 536 }
    ),
  )
}

///|
test "view layout windows and dimensions account for view zones" {
  let layout = @view_layout.ViewLayout(line_height=18, line_count=20)
  layout.set_viewport_size(width=200.0, height=54.0) |> ignore
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(1, 0, 36.0, 0.0) |> ignore
  })
  |> ignore
  assert_eq(layout.dimensions().scroll_height, 396.0)
  // Line 1 (18px) plus the 36px zone fill the 54px viewport exactly; line 2
  // starts at the bottom edge and is not rendered.
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 1, end: 2 }
    ),
  )
  layout.scroll_to(scroll_top=54.0) |> ignore
  debug_inspect(
    layout.visible_window(),
    content=(
      #|{ start: 2, end: 5 }
    ),
  )
  assert_eq(
    layout.relative_vertical_offset_for_line({ start: 2, end: 5 }, 3),
    72,
  )
}

///|
test "view layout derives scroll dimensions from document and viewport" {
  let layout = @view_layout.ViewLayout(line_height=18, line_count=10000)
  layout.set_viewport_size(width=800.0, height=600.0) |> ignore
  debug_inspect(
    layout.dimensions(),
    content=(
      #|{ width: 800, scroll_width: 800, height: 600, scroll_height: 180000 }
    ),
  )
  // The widest measured line drives horizontal scrolling.
  layout.set_content_width(2000.0) |> ignore
  // The compatibility setter now feeds ViewLayout's max-line-width owner;
  // non-wrapping content also reserves the fixed 14px vertical scrollbar.
  assert_eq(layout.dimensions().scroll_width, 2014.0)
  // Replacing the document re-clamps the scroll position.
  layout.scroll_to(scroll_top=179400.0) |> ignore
  let change = layout.set_line_count(100)
  guard change is Some(change) else { fail("expected a dimension change") }
  assert_true(change.position == { scroll_left: 0.0, scroll_top: 1212.0 })
  assert_eq(change.delta_top, -178188.0)
  assert_true(change.top_changed && change.dimensions_changed)
  // The window origin is the content-space top of the window start (the
  // 1-based start line's offset, `(start - 1) * line_height`).
  let window = layout.visible_window()
  assert_eq(layout.window_origin(window), ((window.start - 1) * 18).to_double())
}
