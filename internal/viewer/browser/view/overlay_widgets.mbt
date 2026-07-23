// Ported from `vscode/src/vs/editor/browser/viewParts/overlayWidgets/overlayWidgets.ts`.
// The port carries the DOM shell plus the null-position widget registry
// (`addWidget`/`removeWidget` for widgets whose `getPosition()` is `null` —
// they position themselves, so `render`/`prepare_render` stay no-ops; the
// preference-position placement Monaco layers on top has no consumer yet).
// The narrow lifecycle adapter lives in
// `internal/viewer/browser/view/view_overlays_lifecycle.mbt`.

///|
/// Public overlay-widget owner for root callers. Package-local lifecycle code
/// reads/writes its private `should_render` state directly.
pub struct OverlayWidgets {
  priv dom_node : @rdom.Element
  priv overflowing_overlay_widgets_dom_node : @rdom.Element
  priv widgets : Map[String, @rdom.Element]
  priv mut should_render : Bool
}

///|
fn OverlayWidgets::OverlayWidgets(document : @rdom.Document) -> OverlayWidgets {
  let dom_node = document.create_element("div")
  dom_node.set_attribute("class", "overlayWidgets")
  dom_node.set_attribute("data-view-part", "overlayWidgets")
  let overflowing_overlay_widgets_dom_node = document.create_element("div")
  overflowing_overlay_widgets_dom_node.set_attribute(
    "class", "overflowingOverlayWidgets",
  )
  overflowing_overlay_widgets_dom_node.set_attribute(
    "data-view-part", "overflowingOverlayWidgets",
  )
  {
    dom_node,
    overflowing_overlay_widgets_dom_node,
    widgets: Map([]),
    should_render: true,
  }
}

///|
/// `OverlayWidgets.addWidget` for a null-position widget: mounts the node in
/// the viewport-fixed `.overlayWidgets` container. Re-adding an id replaces
/// the previous node. The container is `pointer-events: none`; interactive
/// widgets set `pointer-events: auto` on their own node.
pub fn OverlayWidgets::add_widget(
  self : OverlayWidgets,
  widget : @editor_browser.OverlayWidget,
) -> Unit {
  let widget_id = widget.get_id()
  let node = widget.get_dom_node()
  self.remove_widget(widget_id)
  node.set_attribute("data-overlay-widget-id", widget_id)
  // `widgetId` is the attribute Monaco's hit test resolves through
  // `HitTestContext.findAttribute` (overlayWidgets.ts:112).
  node.set_attribute("widgetId", widget_id)
  self.dom_node.append_child(node.as_node())
  self.widgets.set(widget_id, node)
}

///|
/// `OverlayWidgets.removeWidget`: unmounts the widget's node. Unknown ids are
/// ignored.
pub fn OverlayWidgets::remove_widget(
  self : OverlayWidgets,
  widget_id : String,
) -> Unit {
  match self.widgets.get(widget_id) {
    Some(node) => {
      self.dom_node.remove_child(node.as_node())
      self.widgets.remove(widget_id)
    }
    None => ()
  }
}

///|
fn OverlayWidgets::get_dom_node(self : OverlayWidgets) -> @rdom.Element {
  self.dom_node
}

///|
fn OverlayWidgets::overflowing_overlay_widgets_dom_node(
  self : OverlayWidgets,
) -> @rdom.Element {
  self.overflowing_overlay_widgets_dom_node
}
