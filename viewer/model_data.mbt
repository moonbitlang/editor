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
/// headless harness; every mounted model owns one closed browser presentation.
priv struct ModelData {
  model : @model.TextModel
  view_model : @view_model.ViewModel
  browser : BrowserPresentation?
  attached_view : @model.AttachedViewImpl
  listeners_to_remove : Array[@base_common.Disposable]
}

///|
/// The private closed family of mounted document presentations. Milestone 1
/// makes the existing code surface explicit; later variants must join these
/// exhaustive root helpers instead of leaking a hidden code `View`.
priv enum BrowserPresentation {
  Code(CodeBrowserData)
}

///|
/// The complete code-presentation state for one attached model.
/// `mouse_handler` is retained for lifecycle commands, but `view` remains its
/// sole disposable owner through the disposable registered by
/// `hook_view_input`.
priv struct CodeBrowserData {
  view : @view.View
  mouse_handler : @controller.MouseHandler
  mut rendered_window : @view_layout.LineWindow?
  mut horizontal_reveal_request : HorizontalRevealRangeRequest?
}

///|
fn CodeBrowserData::CodeBrowserData(
  view : @view.View,
  mouse_handler : @controller.MouseHandler,
) -> CodeBrowserData {
  {
    view,
    mouse_handler,
    rendered_window: None,
    horizontal_reveal_request: None,
  }
}

///|
fn CodeBrowserData::cancel_mouse_selection(self : CodeBrowserData) -> Unit {
  self.mouse_handler.cancel_selection()
}

///|
fn CodeBrowserData::invalidate_rendered_window(self : CodeBrowserData) -> Unit {
  self.rendered_window = None
}

///|
fn CodeBrowserData::sync_rendered_window(
  self : CodeBrowserData,
  view_model : @view_model.ViewModel,
) -> @view_layout.LineWindow {
  let window = view_model.clamp_window(view_model.view_layout.visible_window())
  self.rendered_window = Some(window)
  window
}

///|
fn BrowserPresentation::root(self : BrowserPresentation) -> @rdom.Element {
  match self {
    Code(code) => code.view.root
  }
}

///|
fn BrowserPresentation::apply_theme(
  self : BrowserPresentation,
  theme : String,
) -> Unit {
  match self {
    Code(code) => {
      code.view.root.set_attribute("data-theme", theme)
      code.view.apply_squiggly_theme()
    }
  }
}

///|
fn BrowserPresentation::focus(self : BrowserPresentation) -> Unit {
  @base_browser.focus_prevent_scroll(self.root())
}

///|
fn BrowserPresentation::contains_active_element(
  self : BrowserPresentation,
) -> Bool {
  @base_browser.element_contains_active_element(self.root())
}

///|
fn BrowserPresentation::code(self : BrowserPresentation) -> CodeBrowserData? {
  match self {
    Code(code) => Some(code)
  }
}

///|
fn BrowserPresentation::dispose(self : BrowserPresentation) -> Unit {
  match self {
    Code(code) => code.view.dispose()
  }
}

///|
fn Viewer::current_browser_presentation(self : Viewer) -> BrowserPresentation? {
  match self.model_slot.current {
    Some(model_data) => model_data.browser
    None => None
  }
}

///|
fn Viewer::active_presentation_root(self : Viewer) -> @rdom.Element? {
  match self.current_browser_presentation() {
    Some(presentation) => Some(presentation.root())
    None => None
  }
}

///|
fn Viewer::current_code_browser_data(self : Viewer) -> CodeBrowserData? {
  match self.current_browser_presentation() {
    Some(presentation) => presentation.code()
    None => None
  }
}

///|
/// `ModelData.dispose` (`cew:2133-2141`): remove the swap-scoped listeners,
/// release the attached-view handle, dispose the active presentation, then
/// unregister the ViewModel from the model.
fn ModelData::dispose(self : ModelData) -> Unit {
  for listener in self.listeners_to_remove {
    listener.dispose()
  }
  self.model.on_before_detached(self.attached_view)
  match self.browser {
    Some(browser) => browser.dispose()
    None => ()
  }
  self.view_model.dispose()
}
