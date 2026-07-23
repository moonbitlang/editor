///|
/// Subscribes to changed hidden-area mappings. Delivery occurs after the
/// synchronous projection/layout/stable-viewport transaction has completed.
pub fn ViewModel::on_hidden_areas_changed(
  self : ViewModel,
  listener : (HiddenAreasChangedOutgoingEvent) -> Unit,
) -> @base_common.Disposable {
  self.cursor_event_dispatcher.on_hidden_areas_changed(listener)
}
