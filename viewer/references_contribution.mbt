///|
/// Monaco's shared Definition/References Peek controller id. The contribution
/// is Viewer-owned; the DOM-free result model and browser shell remain in the
/// lower internal references packages.
let references_contribution_id : String = "editor.contrib.referencesController"

///|
/// One root-owned lazy snippet-resolution slot. The group index is immutable;
/// each request bumps `generation`, and the optional source/reference are
/// detached before cancellation or lease-release callbacks can re-enter.
priv struct ReferencesGroupPreviewOwner {
  group_index : Int
  mut generation : Int
  mut source : @language.CancellationTokenSource?
  mut reference : @navigation_api.TextModelReference?
}

///|
fn ReferencesGroupPreviewOwner::ReferencesGroupPreviewOwner(
  group_index : Int,
) -> ReferencesGroupPreviewOwner {
  { group_index, generation: 0, source: None, reference: None }
}

///|
/// Central per-Viewer owner for the presentation and lifetime shared by
/// Definition Peek and the precomputed-locations References entry. Definition
/// provider requests stay in `DefinitionContributionState`; every field here
/// belongs to the already-computed result session and its selected preview.
priv struct ReferencesContributionState {
  mut disposed : Bool
  mut generation : Int
  mut mode : @references.ReferencesPeekMode?
  mut phase : @references.ReferencesPeekPhase
  mut preview_generation : Int
  mut preview_source : @language.CancellationTokenSource?
  mut model : @references.ReferencesModel?
  mut selected_index : Int
  mut session_key : @references.ReferencesSessionKey?
  mut widget : @references_browser.ReferencesPeekWidget?
  mut zone_id : String?
  mut overlay_widget : @editor_browser.OverlayWidget?
  mut markdown_projection_generation : Int?
  mut preview_viewer : Viewer?
  mut preview_reference : @navigation_api.TextModelReference?
  mut preview_decorations : EditorDecorationsCollection?
  mut preview_layout_frame : @base_common.Disposable?
  mut preview_resize_observer : @base_common.Disposable?
  mut group_preview_owners : Array[ReferencesGroupPreviewOwner]
  mut focus_frame : @base_common.Disposable?
  mut launch_async_task : (async () -> Unit noraise) -> Unit
}

///|
fn ReferencesContributionState::ReferencesContributionState() -> ReferencesContributionState {
  {
    disposed: false,
    generation: 0,
    mode: None,
    phase: PeekClosed,
    preview_generation: 0,
    preview_source: None,
    model: None,
    selected_index: -1,
    session_key: None,
    widget: None,
    zone_id: None,
    overlay_widget: None,
    markdown_projection_generation: None,
    preview_viewer: None,
    preview_reference: None,
    preview_decorations: None,
    preview_layout_frame: None,
    preview_resize_observer: None,
    group_preview_owners: [],
    focus_frame: None,
    launch_async_task,
  }
}

///|
/// Disposal delegates to the shared root teardown while the central
/// contribution row is still lookuppable. That teardown atomically detaches
/// the session before invoking cancellation or lease-release callbacks.
fn ReferencesContributionState::dispose(
  self : ReferencesContributionState,
  viewer : Viewer,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  viewer.close_references_peek(restore_focus=false)
}

///|
fn register_references_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    references_contribution_id,
    Lazy,
    _viewer => References(ReferencesContributionState()),
    _viewer => [],
  )
}

///|
fn Viewer::references_contribution(
  self : Viewer,
) -> ReferencesContributionState? {
  match self.contributions.lookup(references_contribution_id) {
    Some(entry) =>
      match entry.instance {
        References(state) => Some(state)
        _ => None
      }
    None => None
  }
}
