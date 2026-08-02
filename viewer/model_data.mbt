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
/// presentation -> root removal -> listener -> attached-view -> ViewModel
/// disposal order.
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
  presentation_kind : DocumentPresentationKind
  browser : BrowserPresentation?
  attached_view : @model.AttachedViewImpl
  listeners_to_remove : Array[@base_common.Disposable]
}

///|
/// Private automatic document-presentation selection. URI matching is exact
/// and case-sensitive; an in-memory/untitled `markdown` model also selects the
/// document view without inventing a file suffix.
priv enum DocumentPresentationKind {
  CodeDocument
  MarkdownDocument(@markdown_core.MarkdownResourceKind)
}

///|
/// The private closed family of mounted document presentations. Every root,
/// focus, theme, and lifecycle operation routes exhaustively through this
/// family instead of assuming a hidden code `View`.
priv enum BrowserPresentation {
  Code(CodeBrowserData)
  Markdown(MarkdownBrowserData)
}

///|
/// Root-owned composition for the Markdown presentation. The lower document
/// view remains contribution-free; this payload enforces cancel → retire
/// semantic lifetime → rerender → rebind/project ordering for every source or
/// theme replacement.
priv struct MarkdownBrowserData {
  view : @markdown_document.MarkdownDocumentView
  hover_bridge : @hover_browser.MarkdownDocumentHoverBridge
  definition_bridge : MarkdownDocumentDefinitionBridge
  fold : MarkdownFoldState
}

///|
fn MarkdownBrowserData::activate(self : MarkdownBrowserData) -> Unit {
  self.hover_bridge.activate()
  self.definition_bridge.activate()
}

///|
fn MarkdownBrowserData::replace_source(
  self : MarkdownBrowserData,
  source : String,
  source_model_version : Int,
) -> Unit {
  self.definition_bridge.before_projection_replaced()
  self.hover_bridge.before_projection_replaced()
  self.view.replace_source(source, source_model_version)
  // Fold reconciliation must land inside the replacement bracket: the
  // pending hover is already invalidated, and `after_projection_replaced`
  // may only refresh diagnostics once final visibility is installed.
  self.reconcile_markdown_folding(source)
  self.hover_bridge.after_projection_replaced()
  self.definition_bridge.after_projection_replaced()
}

///|
fn MarkdownBrowserData::apply_theme(
  self : MarkdownBrowserData,
  theme : String,
) -> Unit {
  self.definition_bridge.before_projection_replaced()
  self.hover_bridge.before_projection_replaced()
  self.view.apply_theme(theme)
  // The source is unchanged, so reconciliation preserves fold state exactly;
  // what needs re-publishing is the visibility and controls the re-rendered
  // article just lost.
  self.reconcile_markdown_folding(self.fold.source)
  self.hover_bridge.after_projection_replaced()
  self.definition_bridge.after_projection_replaced()
}

///|
fn MarkdownBrowserData::layout(
  self : MarkdownBrowserData,
  width : Double,
  height : Double,
) -> Unit {
  self.view.layout(width, height)
  self.hover_bridge.layout_changed()
  self.definition_bridge.layout_changed()
}

///|
fn MarkdownBrowserData::dispose(self : MarkdownBrowserData) -> Unit {
  self.definition_bridge.dispose()
  self.hover_bridge.dispose()
  self.view.dispose()
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
    Markdown(markdown) => markdown.view.root()
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
    Markdown(markdown) => markdown.apply_theme(theme)
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
    Markdown(_) => None
  }
}

///|
fn BrowserPresentation::markdown(
  self : BrowserPresentation,
) -> @markdown_document.MarkdownDocumentView? {
  match self {
    Code(_) => None
    Markdown(markdown) => Some(markdown.view)
  }
}

///|
fn BrowserPresentation::markdown_data(
  self : BrowserPresentation,
) -> MarkdownBrowserData? {
  match self {
    Code(_) => None
    Markdown(markdown) => Some(markdown)
  }
}

///|
fn BrowserPresentation::activate(self : BrowserPresentation) -> Unit {
  match self {
    Code(_) => ()
    Markdown(markdown) => markdown.activate()
  }
}

///|
fn BrowserPresentation::dispose(self : BrowserPresentation) -> Unit {
  match self {
    Code(code) => code.view.dispose()
    Markdown(markdown) => markdown.dispose()
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
fn Viewer::current_markdown_document(
  self : Viewer,
) -> @markdown_document.MarkdownDocumentView? {
  match self.current_browser_presentation() {
    Some(presentation) => presentation.markdown()
    None => None
  }
}

///|
fn Viewer::current_markdown_browser_data(self : Viewer) -> MarkdownBrowserData? {
  match self.current_browser_presentation() {
    Some(presentation) => presentation.markdown_data()
    None => None
  }
}

///|
/// Shared first half of the original ModelData order.
fn ModelData::dispose_listeners_and_attached_view(
  self : ModelData,
  after_model_detached : () -> Unit,
) -> Unit {
  for listener in self.listeners_to_remove {
    listener.dispose()
  }
  self.model.on_before_detached(self.attached_view)
  after_model_detached()
}

///|
/// Preserve Monaco's existing Code/headless order exactly: listeners,
/// attached-view handle, browser View when present, then ViewModel.
fn ModelData::dispose_code_or_headless(
  self : ModelData,
  after_model_detached : () -> Unit,
) -> Unit {
  self.dispose_listeners_and_attached_view(after_model_detached)
  match self.browser {
    Some(browser) => browser.dispose()
    None => ()
  }
  self.view_model.dispose()
}

///|
/// Retires the Markdown browser-owned bridge, renderer, and semantic registry
/// while its presentation root is still mounted.
fn ModelData::dispose_markdown_presentation(self : ModelData) -> Unit {
  match self.browser {
    Some(Markdown(markdown)) => markdown.dispose()
    Some(Code(_)) | None => ()
  }
}

///|
/// Remaining `ModelData` teardown (`cew:2133-2141`) after root Viewer has
/// removed the disposed presentation subtree: remove swap-scoped listeners,
/// release the attached-view handle, then unregister the ViewModel.
fn ModelData::dispose_after_markdown_root(
  self : ModelData,
  after_model_detached : () -> Unit,
) -> Unit {
  self.dispose_listeners_and_attached_view(after_model_detached)
  self.view_model.dispose()
}
