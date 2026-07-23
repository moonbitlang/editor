///|
/// Hand-computed cases for the 10k-line fixture geometry: 600px viewport,
/// 180000px content, 14px bar, no arrows, no paired bar.
fn large_doc_bar() -> @view_layout.ScrollbarState {
  let state = @view_layout.ScrollbarState(scrollbar_size=14.0)
  state.set_visible_size(600.0) |> ignore
  state.set_scroll_size(180000.0) |> ignore
  state
}

///|
test "slider geometry for overflowing content" {
  let state = large_doc_bar()
  assert_true(state.is_needed())
  assert_eq(state.rectangle_large_size(), 600.0)
  assert_eq(state.rectangle_small_size(), 14.0)
  // floor(600 * 600 / 180000) = 2 enlarges to the 20px minimum.
  assert_eq(state.slider_size(), 20.0)
  assert_eq(state.slider_position(), 0.0)
  // Mid-document: slider sits at round(89700 * 580/179400) = 290.
  state.set_scroll_position(89700.0) |> ignore
  assert_eq(state.slider_position(), 290.0)
  // Bottom: the slider reaches the end of its travel (600 - 20 = 580).
  state.set_scroll_position(179400.0) |> ignore
  assert_eq(state.slider_position(), 580.0)
}

///|
test "thumb drags and track jumps answer hand-computed positions" {
  let state = large_doc_bar()
  state.set_scroll_position(89700.0) |> ignore
  // Dragging the thumb 10px: round((290 + 10) * 179400 / 580) = 92793.
  assert_eq(state.desired_position_from_delta(10.0), 92793.0)
  // Centering the thumb on track offset 300: round((300 - 10) / ratio)
  // lands exactly back at 89700.
  assert_eq(state.desired_position_from_offset(300.0), 89700.0)
  // Paged jumps move one viewport from the current position, by side.
  state.set_scroll_position(1000.0) |> ignore
  // Slider sits at round(1000 * 580/179400) = 3.
  assert_eq(state.slider_position(), 3.0)
  assert_eq(state.desired_position_from_offset_paged(2.0), 400.0)
  assert_eq(state.desired_position_from_offset_paged(50.0), 1600.0)
}

///|
test "content inside the viewport needs no slider" {
  let state = @view_layout.ScrollbarState(scrollbar_size=14.0)
  state.set_visible_size(600.0) |> ignore
  state.set_scroll_size(400.0) |> ignore
  assert_false(state.is_needed())
  // The slider fills the representable track and ignores interactions.
  assert_eq(state.slider_size(), 600.0)
  assert_eq(state.slider_position(), 0.0)
  assert_eq(state.desired_position_from_delta(25.0), 0.0)
  assert_eq(state.desired_position_from_offset(300.0), 0.0)
}

///|
test "a paired scrollbar and arrows shrink the track" {
  let state = @view_layout.ScrollbarState(
    arrow_size=3.0,
    scrollbar_size=14.0,
    opposite_scrollbar_size=14.0,
  )
  state.set_visible_size(600.0) |> ignore
  state.set_scroll_size(1200.0) |> ignore
  // available = 600 - 14 = 586; representable = 586 - 6 = 580.
  assert_eq(state.rectangle_large_size(), 586.0)
  // floor(600 * 580 / 1200) = 290.
  assert_eq(state.slider_size(), 290.0)
  // ratio = (580 - 290) / (1200 - 600) = 290/600; at scroll 600 the
  // slider sits at its travel end: round(600 * 290/600) = 290.
  state.set_scroll_position(600.0) |> ignore
  assert_eq(state.slider_position(), 290.0)
}
