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
/// Right-pointing chevron used as a tree twistie; CSS rotates it 90deg when
/// the folder row is expanded.
fn icon_chevron_right() -> @html.Html {
  icon_svg("icon-chevron-right", [
    @svg.path(
      d="M6.1 3.6 L5.2 4.5 L8.7 8 L5.2 11.5 L6.1 12.4 L10.5 8 Z",
      fill="currentColor",
    ),
  ])
}

///|
/// Plain document page with a folded corner.
fn icon_file() -> @html.Html {
  icon_svg("icon-file", [
    @svg.path(
      d="M4 1.5 L9.6 1.5 L12.5 4.4 L12.5 14.5 L4 14.5 Z M5 2.5 L5 13.5 L11.5 13.5 L11.5 5.5 L8.9 5.5 L8.9 2.5 Z M9.9 2.9 L9.9 4.5 L11.4 4.5 Z",
      fill="currentColor",
      attrs=@svg.Attrs::build().fill_rule("evenodd"),
    ),
  ])
}
