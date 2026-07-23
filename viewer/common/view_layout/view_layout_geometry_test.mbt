// Source-derived tests for `vscode/src/vs/editor/common/viewLayout/viewLayout.ts`
// (checked-in vscode submodule):
// EditorScrollDimensions, EditorScrollable content-size delivery, and the
// applicable fixed-option ViewLayout width/height feedback branches.

///|
fn inert_scheduler(_callback : () -> Unit) -> @base_common.Disposable {
  @base_common.Disposable::from(() => ())
}

///|
test "EditorScrollDimensions normalizes with JavaScript signed-32-bit coercion" {
  let ordinary = @view_layout.EditorScrollDimensions(-1.9, 12.9, 0.0, 20.1)
  assert_eq(ordinary.width, 0.0)
  assert_eq(ordinary.content_width, 12.0)
  assert_eq(ordinary.scroll_width, 12.0)
  assert_eq(ordinary.height, 0.0)
  assert_eq(ordinary.content_height, 20.0)
  assert_eq(ordinary.scroll_height, 20.0)
  let negative_axes = @view_layout.EditorScrollDimensions(1.0, -3.2, -4.7, -5.9)
  assert_eq(negative_axes.width, 1.0)
  assert_eq(negative_axes.content_width, 0.0)
  assert_eq(negative_axes.height, 0.0)
  assert_eq(negative_axes.content_height, 0.0)
  // `2147483648 | 0` is -2147483648 and therefore clamps to zero.
  let positive_wrap = @view_layout.EditorScrollDimensions(
    2147483648.0, 4294967297.0, 2147483647.9, -2147483649.0,
  )
  assert_eq(positive_wrap.width, 0.0)
  assert_eq(positive_wrap.content_width, 1.0)
  assert_eq(positive_wrap.height, 2147483647.0)
  // `-2147483649 | 0` wraps to positive 2147483647.
  assert_eq(positive_wrap.content_height, 2147483647.0)
  let smaller = @view_layout.EditorScrollDimensions(10.0, 5.0, 20.0, 15.0)
  assert_eq(smaller.scroll_width, 10.0)
  assert_eq(smaller.scroll_height, 20.0)
  let equal = @view_layout.EditorScrollDimensions(10.0, 10.0, 20.0, 20.0)
  assert_eq(equal.scroll_width, 10.0)
  assert_eq(equal.scroll_height, 20.0)
  let larger = @view_layout.EditorScrollDimensions(10.0, 15.0, 20.0, 25.0)
  assert_eq(larger.scroll_width, 15.0)
  assert_eq(larger.scroll_height, 25.0)
}

///|
test "EditorScrollable emits only exact content-size identity changes" {
  let scrollable = @view_layout.EditorScrollable(0.0, inert_scheduler, () => 0.0)
  let initial = scrollable.editor_dimensions()
  assert_true(initial == EditorScrollDimensions(0.0, 0.0, 0.0, 0.0))
  assert_true(
    scrollable.dimensions() ==
    { width: 0.0, scroll_width: 0.0, height: 0.0, scroll_height: 0.0 },
  )
  let changes : Array[@view_layout.ContentSizeChange] = []
  let listener = scrollable.on_did_content_size_change(change => {
    changes.push(change)
  })
  // Viewport-only changes reach the underlying Scrollable but not this event.
  assert_true(
    scrollable.set_editor_dimensions(
      EditorScrollDimensions(80.0, 0.0, 20.0, 0.0),
    )
    is Some(_),
  )
  assert_eq(changes.length(), 0)
  // Width only.
  scrollable.set_editor_dimensions(
    EditorScrollDimensions(80.0, 100.0, 20.0, 0.0),
  )
  |> ignore
  // Height only.
  scrollable.set_editor_dimensions(
    EditorScrollDimensions(80.0, 100.0, 20.0, 40.0),
  )
  |> ignore
  // Both.
  scrollable.set_editor_dimensions(
    EditorScrollDimensions(80.0, 120.0, 20.0, 60.0),
  )
  |> ignore
  assert_eq(changes.length(), 3)
  assert_true(
    changes[0] ==
    {
      old_content_width: 0.0,
      old_content_height: 0.0,
      content_width: 100.0,
      content_height: 0.0,
    },
  )
  assert_true(
    changes[1] ==
    {
      old_content_width: 100.0,
      old_content_height: 0.0,
      content_width: 100.0,
      content_height: 40.0,
    },
  )
  assert_true(
    changes[2] ==
    {
      old_content_width: 100.0,
      old_content_height: 40.0,
      content_width: 120.0,
      content_height: 60.0,
    },
  )
  // Complete identity is an early return: no write and no event.
  assert_true(
    scrollable.set_editor_dimensions(
      EditorScrollDimensions(80.0, 120.0, 20.0, 60.0),
    )
    is None,
  )
  assert_eq(changes.length(), 3)
  listener.dispose()
  scrollable.dispose()
}

///|
test "ViewLayout starts with zero measured width before its first line read" {
  let layout = @view_layout.ViewLayout(line_height=10, line_count=5)
  assert_eq(layout.get_content_width(), 0.0)
  layout.set_viewport_size(width=100.0, height=50.0) |> ignore
  assert_eq(layout.get_content_width(), 0.0)
  // Changing into the wrapping arm forces a content-width recomputation. Its
  // result remains zero, proving the retained max-line-width seed is zero.
  layout.set_is_viewport_wrapping(true) |> ignore
  assert_eq(layout.get_content_width(), 0.0)
  assert_eq(layout.get_scroll_width(), 100.0)
  layout.dispose()
}

///|
test "ViewLayout measured width feeds fixed scrollbar bottom extent in source order" {
  let layout = @view_layout.ViewLayout(
    line_height=10,
    line_count=5,
    vertical_scrollbar_width=14.0,
    horizontal_scrollbar_height=12.0,
  )
  layout.set_viewport_size(width=100.0, height=50.0) |> ignore
  // Non-wrapping reserves the vertical scrollbar. Smaller and equal content
  // widths do not make the horizontal scrollbar visible.
  layout.set_max_line_width(80.0) |> ignore
  assert_eq(layout.get_content_width(), 94.0)
  assert_eq(layout.get_content_height(), 50.0)
  layout.set_max_line_width(86.0) |> ignore
  assert_eq(layout.get_content_width(), 100.0)
  assert_eq(layout.get_content_height(), 50.0)
  let changes : Array[@view_layout.ContentSizeChange] = []
  let scroll_changes : Array[@view_layout.ScrollChange] = []
  let listener = layout.on_did_content_size_change(change => {
    changes.push(change)
  })
  let scroll_listener = layout.on_did_scroll(change => {
    scroll_changes.push(change)
  })
  // Crossing into overflow publishes width first, then the 12px height
  // extension; crossing back reverses the same two-stage feedback.
  let entering_overflow = layout.set_max_line_width(87.0)
  guard entering_overflow is Some(entering_overflow) else {
    fail("overflow transition must return its combined scroll change")
  }
  assert_eq(layout.get_content_width(), 101.0)
  assert_eq(layout.get_content_height(), 62.0)
  assert_true(entering_overflow.scroll_width_changed)
  assert_true(entering_overflow.scroll_height_changed)
  assert_eq(entering_overflow.old_scroll_width, 100.0)
  assert_eq(entering_overflow.scroll_width, 101.0)
  assert_eq(entering_overflow.old_scroll_height, 50.0)
  assert_eq(entering_overflow.scroll_height, 62.0)
  assert_eq(changes.length(), 2)
  assert_eq(scroll_changes.length(), 2)
  assert_true(scroll_changes[0].scroll_width_changed)
  assert_false(scroll_changes[0].scroll_height_changed)
  assert_false(scroll_changes[1].scroll_width_changed)
  assert_true(scroll_changes[1].scroll_height_changed)
  assert_true(
    changes[0] ==
    {
      old_content_width: 100.0,
      old_content_height: 50.0,
      content_width: 101.0,
      content_height: 50.0,
    },
  )
  assert_true(
    changes[1] ==
    {
      old_content_width: 101.0,
      old_content_height: 50.0,
      content_width: 101.0,
      content_height: 62.0,
    },
  )
  layout.set_max_line_width(86.0) |> ignore
  assert_eq(layout.get_content_height(), 50.0)
  assert_eq(changes.length(), 4)
  assert_eq(scroll_changes.length(), 4)
  assert_true(scroll_changes[2].scroll_width_changed)
  assert_false(scroll_changes[2].scroll_height_changed)
  assert_false(scroll_changes[3].scroll_width_changed)
  assert_true(scroll_changes[3].scroll_height_changed)
  listener.dispose()
  scroll_listener.dispose()
  layout.dispose()
}

///|
test "ViewLayout wrapping returns the measured maximum and fixed scrollbar sizes" {
  let wrapped = @view_layout.ViewLayout(
    line_height=10,
    line_count=5,
    is_viewport_wrapping=true,
    vertical_scrollbar_width=14.0,
    horizontal_scrollbar_height=12.0,
  )
  wrapped.set_viewport_size(width=100.0, height=50.0) |> ignore
  wrapped.set_max_line_width(100.0) |> ignore
  assert_eq(wrapped.get_content_width(), 100.0)
  assert_eq(wrapped.get_content_height(), 50.0)
  wrapped.set_max_line_width(101.0) |> ignore
  assert_eq(wrapped.get_content_width(), 101.0)
  assert_eq(wrapped.get_content_height(), 62.0)
  wrapped.set_is_viewport_wrapping(false) |> ignore
  assert_eq(wrapped.get_content_width(), 115.0)
  let zero_bar = @view_layout.ViewLayout(
    line_height=10,
    line_count=5,
    vertical_scrollbar_width=0.0,
    horizontal_scrollbar_height=0.0,
  )
  zero_bar.set_viewport_size(width=100.0, height=50.0) |> ignore
  zero_bar.set_max_line_width(101.0) |> ignore
  assert_eq(zero_bar.get_content_width(), 101.0)
  assert_eq(zero_bar.get_content_height(), 50.0)
  wrapped.dispose()
  zero_bar.dispose()
}
