///|
/// One fixed-position context-menu anchor in visual-viewport coordinates.
priv struct ContextMenuPoint {
  x : Double
  y : Double
}

///|
priv struct ContextMenuSize {
  width : Double
  height : Double
}

///|
priv struct ContextMenuRect {
  left : Double
  top : Double
  right : Double
  bottom : Double
}

///|
/// Root-menu point placement: prefer right/down from the pointer or cursor,
/// then flip left/up and clamp when the preferred side overflows.
fn fit_root_context_menu(
  anchor : ContextMenuPoint,
  menu : ContextMenuSize,
  viewport : ContextMenuSize,
) -> ContextMenuPoint {
  {
    x: fit_context_menu_axis(anchor.x, menu.width, viewport.width),
    y: fit_context_menu_axis(anchor.y, menu.height, viewport.height),
  }
}

///|
fn fit_context_menu_axis(
  anchor : Double,
  extent : Double,
  viewport_extent : Double,
) -> Double {
  if viewport_extent <= extent {
    0.0
  } else if anchor + extent <= viewport_extent {
    clamp_context_menu_coordinate(anchor, viewport_extent - extent)
  } else {
    clamp_context_menu_coordinate(anchor - extent, viewport_extent - extent)
  }
}

///|
/// Submenus prefer the parent row's right/top edges. Horizontal overflow
/// flips them to the row's left edge; vertical overflow aligns their bottom
/// with the row before clamping.
fn fit_submenu_context_menu(
  parent : ContextMenuRect,
  menu : ContextMenuSize,
  viewport : ContextMenuSize,
) -> ContextMenuPoint {
  let x = if parent.right + menu.width <= viewport.width {
    parent.right
  } else {
    parent.left - menu.width
  }
  let y = if parent.top + menu.height <= viewport.height {
    parent.top
  } else {
    parent.bottom - menu.height
  }
  {
    x: clamp_context_menu_coordinate(x, viewport.width - menu.width),
    y: clamp_context_menu_coordinate(y, viewport.height - menu.height),
  }
}

///|
fn clamp_context_menu_coordinate(value : Double, maximum : Double) -> Double {
  if maximum <= 0.0 || value <= 0.0 {
    0.0
  } else if value >= maximum {
    maximum
  } else {
    value
  }
}
