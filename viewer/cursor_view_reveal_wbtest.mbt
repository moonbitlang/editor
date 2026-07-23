///|
/// Cursor-command reveal consumes the already-resolved view position. The
/// injected text below gives one model position more than one valid projected
/// location (the upstream issue #140195 shape); a model round-trip would reveal
/// view `(2,8)` instead of the authoritative movement result `(5,19)`.
test "cursor navigation reveal keeps the authoritative injected-text view position" {
  let model = test_model("Word1 Word2 Word3 Word4\nWord5 Word6 Word7 Word8")
  model.delta_decorations([], [
    {
      range: Range(1, 22, 1, 22),
      options: ModelDecorationOptions(
        "",
        description="cursor reveal ambiguity",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          "some very very very very very very very very long text",
        ),
      ),
    },
  ])
  |> ignore
  let viewer = Viewer::Viewer(
    options=ViewerOptions(
      soft_wrap=true,
      tab_size=4,
      wrapping_indent=Indent,
      font_size=12,
      line_height=18,
    ),
  )
  viewer.set_model(Some(model))
  viewer.test_set_soft_wrap_column(20)
  viewer.test_set_viewport(width=400.0, height=18.0)
  viewer.run_cursor_move(Down, false, unit=WrappedLine) |> ignore
  viewer.test_view_model().view_layout.scroll_to(scroll_top=0.0) |> ignore
  viewer.run_cursor_move(Down, false, unit=WrappedLine) |> ignore
  let view_position = viewer.test_cursor().view_state().position
  assert_position(view_position, Position(5, 19))
  let expected = viewer.test_view_model().view_layout.compute_scroll_top_to_reveal_range(
    5,
    5,
    Simple,
  )
  assert_eq(
    viewer.test_view_model().view_layout.position().scroll_top,
    expected,
  )
  assert_eq(expected, 72.0)
  viewer.dispose()
  model.dispose()
}

///|
test "navigation reveal forwards the command source" {
  with_test_viewer(long_document(40), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.set_position(Position(31, 1))
    let layout = viewer.test_view_model().view_layout
    layout.scroll_to(scroll_top=540.0) |> ignore
    let expected = layout.compute_scroll_top_to_reveal_range(
      30,
      30,
      Simple,
      source="mouse",
      minimal_reveal=false,
    )
    let hard_coded_keyboard = layout.compute_scroll_top_to_reveal_range(
      30,
      30,
      Simple,
      source="keyboard",
      minimal_reveal=false,
    )
    assert_true(expected != hard_coded_keyboard)
    assert_true(
      viewer.run_cursor_move(Up, false, unit=WrappedLine, source="mouse"),
    )
    assert_position(viewer.get_position().unwrap(), Position(30, 1))
    assert_eq(layout.position().scroll_top, expected)
  })
}
