///|
/// Viewer-lifetime owner of the currently attached model bundle and the
/// monotonic generation captured by swap-scoped callbacks. Detach invalidates
/// the generation before cleanup but deliberately keeps `current` installed
/// until `ModelData::dispose` has completed.
priv struct ViewerModelSlot {
  mut generation : Int
  mut current : ModelData?
}

///|
fn ViewerModelSlot::ViewerModelSlot() -> ViewerModelSlot {
  { generation: 0, current: None }
}

///|
/// Advances the callback generation before one model attach begins.
fn ViewerModelSlot::begin_attach_generation(self : ViewerModelSlot) -> Int {
  self.generation += 1
  self.generation
}

///|
/// Invalidates swap-scoped callbacks before detach cleanup while leaving the
/// outgoing bundle available to the root transaction through its exact
/// listener -> attached-view -> View -> ViewModel disposal order.
fn ViewerModelSlot::invalidate_current_for_detach(
  self : ViewerModelSlot,
) -> ModelData? {
  guard self.current is Some(current) else { return None }
  self.generation += 1
  Some(current)
}

///|
fn ViewerModelSlot::install_current(
  self : ViewerModelSlot,
  model_data : ModelData,
) -> Unit {
  self.current = Some(model_data)
}

///|
/// Clears the outgoing bundle only after its owned resources have been
/// disposed. This must not be folded into `invalidate_current_for_detach`.
fn ViewerModelSlot::clear_current_after_dispose(self : ViewerModelSlot) -> Unit {
  self.current = None
}

///|
fn ViewerModelSlot::is_current_generation(
  self : ViewerModelSlot,
  generation : Int,
) -> Bool {
  self.current is Some(_) && self.generation == generation
}

///|
/// Monaco's `ModelData` (`codeEditorWidget.ts:2123-2143`): everything whose
/// lifetime is one model attach. `browser` is `None` only for the private
/// headless harness; a real browser View is always paired with its retained
/// MouseHandler reference and View-scoped render/reveal facts.
priv struct ModelData {
  model : @model.TextModel
  view_model : @view_model.ViewModel
  browser : ModelBrowserData?
  attached_view : @model.AttachedViewImpl
  listeners_to_remove : Array[@base_common.Disposable]
}

///|
/// The complete browser-only state for one attached model. `mouse_handler` is
/// retained for lifecycle commands, but `view` remains its sole disposable
/// owner through the disposable registered by `hook_view_input`.
priv struct ModelBrowserData {
  view : @view.View
  mouse_handler : @controller.MouseHandler
  mut rendered_window : @view_layout.LineWindow?
  mut horizontal_reveal_request : HorizontalRevealRangeRequest?
}

///|
fn ModelBrowserData::ModelBrowserData(
  view : @view.View,
  mouse_handler : @controller.MouseHandler,
) -> ModelBrowserData {
  {
    view,
    mouse_handler,
    rendered_window: None,
    horizontal_reveal_request: None,
  }
}

///|
fn ModelBrowserData::cancel_mouse_selection(self : ModelBrowserData) -> Unit {
  self.mouse_handler.cancel_selection()
}

///|
fn ModelBrowserData::invalidate_rendered_window(
  self : ModelBrowserData,
) -> Unit {
  self.rendered_window = None
}

///|
fn ModelBrowserData::sync_rendered_window(
  self : ModelBrowserData,
  view_model : @view_model.ViewModel,
) -> @view_layout.LineWindow {
  let window = view_model.clamp_window(view_model.view_layout.visible_window())
  self.rendered_window = Some(window)
  window
}

///|
fn Viewer::current_browser_data(self : Viewer) -> ModelBrowserData? {
  match self.model_slot.current {
    Some(model_data) => model_data.browser
    None => None
  }
}

///|
/// `ModelData.dispose` (`cew:2133-2141`): remove the swap-scoped listeners,
/// release the attached-view handle, dispose the View (which disposes its
/// MouseHandler exactly once), then unregister the ViewModel from the model.
fn ModelData::dispose(self : ModelData) -> Unit {
  for listener in self.listeners_to_remove {
    listener.dispose()
  }
  self.model.on_before_detached(self.attached_view)
  match self.browser {
    Some(browser) => browser.view.dispose()
    None => ()
  }
  self.view_model.dispose()
}
