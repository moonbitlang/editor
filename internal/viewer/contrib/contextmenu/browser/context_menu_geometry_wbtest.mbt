///|
fn assert_context_menu_point(
  actual : ContextMenuPoint,
  x : Double,
  y : Double,
) -> Unit raise {
  assert_eq(actual.x, x)
  assert_eq(actual.y, y)
}

///|
test "root context menu prefers right/down then flips and clamps" {
  let viewport : ContextMenuSize = { width: 800.0, height: 600.0 }
  let menu : ContextMenuSize = { width: 180.0, height: 120.0 }
  assert_context_menu_point(
    fit_root_context_menu({ x: 100.0, y: 90.0 }, menu, viewport),
    100.0,
    90.0,
  )
  assert_context_menu_point(
    fit_root_context_menu({ x: 790.0, y: 590.0 }, menu, viewport),
    610.0,
    470.0,
  )
  assert_context_menu_point(
    fit_root_context_menu({ x: -12.0, y: -8.0 }, menu, viewport),
    0.0,
    0.0,
  )
  assert_context_menu_point(
    fit_root_context_menu(
      { x: 10.0, y: 10.0 },
      { width: 900.0, height: 700.0 },
      viewport,
    ),
    0.0,
    0.0,
  )
}

///|
test "submenu prefers right/top and flips left/up at viewport edges" {
  let viewport : ContextMenuSize = { width: 800.0, height: 600.0 }
  let menu : ContextMenuSize = { width: 160.0, height: 100.0 }
  assert_context_menu_point(
    fit_submenu_context_menu(
      { left: 100.0, top: 80.0, right: 260.0, bottom: 104.0 },
      menu,
      viewport,
    ),
    260.0,
    80.0,
  )
  assert_context_menu_point(
    fit_submenu_context_menu(
      { left: 700.0, top: 570.0, right: 780.0, bottom: 594.0 },
      menu,
      viewport,
    ),
    540.0,
    494.0,
  )
}
