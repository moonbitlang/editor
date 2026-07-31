///|
/// Monaco's shared Definition/References Peek controller id. The contribution
/// is Viewer-owned; the DOM-free result model and browser shell remain in the
/// lower internal references packages.
let references_contribution_id : String = "editor.contrib.referencesController"

///|
/// Exact provider-query owner stamp. The session generation identifies both
/// the mounted shell and the query intent; model fields reject results after
/// replacement, reattachment, or content changes.
priv struct ReferencesQueryStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
}

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
  mut query_source : @language.CancellationTokenSource?
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
    query_source: None,
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
/// Retires a completed or stale provider query only when it is still the exact
/// source owned by this state. An older continuation therefore cannot cancel
/// a newer References session.
fn ReferencesContributionState::retire_query_source(
  self : ReferencesContributionState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.query_source {
    Some(current) if physical_equal(current, source) => {
      self.query_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
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
  registry.register_editor_command(
    "editor.action.referenceSearch.trigger",
    viewer => viewer.references_action_available(),
    viewer => viewer.start_peek_references(),
    [],
    shift_keybindings=[("F12", false, false)],
    title="Peek References",
    menu_keybinding_label=references_menu_keybinding_label(),
    menu_placements=[
      { menu_id: EditorContext, group: "navigation", order: 1.3 },
    ],
  )
}

///|
fn references_menu_keybinding_label() -> String {
  if @base_common.is_macintosh {
    "\u{21e7}F12"
  } else {
    "Shift+F12"
  }
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
