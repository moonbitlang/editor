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
/// Folder outline used by the repository picker.
fn icon_folder() -> @html.Html {
  icon_svg("icon-folder", [
    @svg.path(
      d="M1 3.5 A1.5 1.5 0 0 1 2.5 2 H6 L7.5 3.5 H13.5 A1.5 1.5 0 0 1 15 5 V12.5 A1.5 1.5 0 0 1 13.5 14 H2.5 A1.5 1.5 0 0 1 1 12.5 Z M2.5 3 A0.5 0.5 0 0 0 2 3.5 V12.5 A0.5 0.5 0 0 0 2.5 13 H13.5 A0.5 0.5 0 0 0 14 12.5 V5 A0.5 0.5 0 0 0 13.5 4.5 H7.1 L5.6 3 Z",
      fill="currentColor",
      attrs=@svg.Attrs::build().fill_rule("evenodd"),
    ),
  ])
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

///|
/// Split-pane outline representing the workspace explorer sidebar.
fn icon_sidebar() -> @html.Html {
  icon_svg("icon-sidebar", [
    @svg.path(
      d="M2.5 1.5 H13.5 A1 1 0 0 1 14.5 2.5 V13.5 A1 1 0 0 1 13.5 14.5 H2.5 A1 1 0 0 1 1.5 13.5 V2.5 A1 1 0 0 1 2.5 1.5 Z M2.5 2.5 V13.5 H5.5 V2.5 Z M6.5 2.5 V13.5 H13.5 V2.5 Z",
      fill="currentColor",
      attrs=@svg.Attrs::build().fill_rule("evenodd"),
    ),
  ])
}
