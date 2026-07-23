// The viewer facade's public overlay-widget API delegates to
// `internal/viewer/browser/view/overlay_widgets.mbt`. It lives here because every
// `Viewer::` method must be defined in `Viewer`'s package.

///|
/// Constructs an unmanaged null-position overlay widget. The caller retains
/// ownership of the supplied DOM node.
pub fn overlay_widget(
  widget_id : String,
  node : @rdom.Element,
) -> @editor_browser.OverlayWidget {
  @editor_browser.OverlayWidget::unmanaged(widget_id, node)
}

///|
/// Adds a null-position overlay widget — Monaco's
/// `ICodeEditor.addOverlayWidget` reduced to the immutable browser handle
/// because the viewer's only consumers position themselves.
/// Re-adding an id replaces the previous node — Monaco's `layoutOverlayWidget`
/// re-add semantics. The registration outlives any per-model view: the id →
/// handle map is Monaco's `_overlayWidgets`, re-added to every new view
/// (`cew:1901-1905`).
pub fn Viewer::add_overlay_widget(
  self : Viewer,
  widget : @editor_browser.OverlayWidget,
) -> Unit {
  let widget_id = widget.get_id()
  self.overlay_widgets[widget_id] = widget
  match self.get_view() {
    Some(view) => view.overlay_widgets.add_widget(widget)
    None => ()
  }
}

///|
/// Removes an overlay widget by its immutable id — Monaco's
/// `ICodeEditor.removeOverlayWidget`. A stale handle therefore removes the
/// current registration with the same id; unknown ids and a missing view are
/// no-ops. The caller-owned DOM node is only unmounted.
pub fn Viewer::remove_overlay_widget(
  self : Viewer,
  widget : @editor_browser.OverlayWidget,
) -> Unit {
  let widget_id = widget.get_id()
  self.overlay_widgets.remove(widget_id)
  match self.get_view() {
    Some(view) => view.overlay_widgets.remove_widget(widget_id)
    None => ()
  }
}

///|
/// Internal id lookup for contribution objects that retain their Monaco id
/// rather than a second public handle.
fn Viewer::overlay_widget_for_id(
  self : Viewer,
  widget_id : String,
) -> @editor_browser.OverlayWidget? {
  self.overlay_widgets.get(widget_id)
}
