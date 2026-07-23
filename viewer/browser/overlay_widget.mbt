///|
/// Immutable unmanaged overlay-widget handle for the viewer's existing
/// null-position/self-positioned subset. The caller retains DOM ownership.
pub struct OverlayWidget {
  priv id : String
  priv dom_node : @rdom.Element
}

///|
pub fn OverlayWidget::unmanaged(
  id : String,
  dom_node : @rdom.Element,
) -> OverlayWidget {
  { id, dom_node }
}

///|
pub fn OverlayWidget::get_id(self : OverlayWidget) -> String {
  self.id
}

///|
pub fn OverlayWidget::get_dom_node(self : OverlayWidget) -> @rdom.Element {
  self.dom_node
}
