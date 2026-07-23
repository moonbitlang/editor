// Original 16x16 icon shapes drawn for this project. They follow the visual
// vocabulary of common editor iconography without reusing any icon font or
// path data. All icons inherit `currentColor`.

///|
fn icon_svg(class : String, children : Array[@svg.Svg]) -> @html.Html {
  @svg.svg(
    class="icon " + class,
    width=16,
    height=16,
    view_box="0 0 16 16",
    children,
  )
}

///|
/// Half-filled disc representing the light/dark color-mode toggle.
fn icon_color_mode() -> @html.Html {
  icon_svg("icon-color-mode", [
    @svg.path(
      d="M8 1.5 A6.5 6.5 0 1 0 8 14.5 A6.5 6.5 0 1 0 8 1.5 Z M8 2.5 A5.5 5.5 0 0 1 8 13.5 Z",
      fill="currentColor",
      attrs=@svg.Attrs::build().fill_rule("evenodd"),
    ),
  ])
}
