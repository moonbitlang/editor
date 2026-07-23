///|
/// Delegates one nonraising whitespace transaction to ViewLayout and returns
/// whether any accessor operation was requested. Browser-safe callback
/// containment happens before this common-tier boundary.
pub fn ViewModel::change_whitespace(
  self : ViewModel,
  callback : (@view_layout.WhitespaceChangeAccessor) -> Unit,
) -> Bool {
  self.view_layout.change_whitespace(callback)
}

///|
/// Returns a shallow snapshot of every current ID-bearing whitespace.
pub fn ViewModel::get_whitespaces(
  self : ViewModel,
) -> Array[@view_layout.EditorWhitespace] {
  self.view_layout.get_whitespaces()
}

///|
/// Subscribes to the ViewModel's dedicated outgoing ViewZones event alias.
/// The shared CodeEditorWidget cross-event delivery queue remains absent.
pub fn ViewModel::on_view_zones_changed(
  self : ViewModel,
  listener : (ViewZonesChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.cursor_event_dispatcher.on_view_zones_changed(listener)
}

///|
/// Emits one outgoing ViewZones fact after the browser tier has completed its
/// internal `ViewZonesChanged` delivery.
pub fn ViewModel::emit_view_zones_changed(self : ViewModel) -> Unit {
  self.cursor_event_dispatcher.emit_view_zones_changed(ViewZonesChangedEvent())
}
