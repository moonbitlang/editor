// The hover feature's registrations — the viewer's
// `vscode/src/vs/editor/contrib/hover/browser/hoverContribution.ts` +
// `hoverActions.ts` (scroll cluster) + `hoverActionIds.ts`. The controller
// state lives in the Viewer's central contribution entry, and the registry
// also inverts command/keyboard dispatch: the hover widget's keydown resolves
// through the keybinding table instead of an inline key map.

///|
/// `registerEditorContribution(ContentHoverController.ID, …,
/// BeforeFirstInteraction)` (`hoverContribution.ts:22`) plus the scroll
/// cluster of `hoverActions.ts` and `HideContentHoverAction`.
fn register_hover_contribution(registry : EditorContributionRegistry) -> Unit {
  registry.register_editor_contribution(
    "editor.contrib.contentHover",
    BeforeFirstInteraction,
    _viewer => ContentHover(ContentHoverContributionState()),
    _viewer => [],
  )
  // `HideContentHoverAction` (`hoverActions.ts`): Escape, gated on
  // `hoverVisible`.
  registry.register_editor_command(
    "editor.action.hideHover",
    viewer => viewer.content_hover_visible(),
    viewer => viewer.hide_content_hover(),
    [("Escape", false, false)],
  )
  // The scroll cluster (`hoverActions.ts:171+`), each gated on
  // `hoverFocused`; the arrow-key secondaries match the source
  // (`Alt+Arrow` pages, `CtrlCmd+Arrow` jumps to an edge).
  registry.register_editor_command(
    "editor.action.scrollUpHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.scroll_up()),
    [("ArrowUp", false, false)],
  )
  registry.register_editor_command(
    "editor.action.scrollDownHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.scroll_down()),
    [("ArrowDown", false, false)],
  )
  registry.register_editor_command(
    "editor.action.scrollLeftHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.scroll_left()),
    [("ArrowLeft", false, false)],
  )
  registry.register_editor_command(
    "editor.action.scrollRightHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.scroll_right()),
    [("ArrowRight", false, false)],
  )
  registry.register_editor_command(
    "editor.action.pageUpHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.page_up()),
    [("PageUp", false, false), ("ArrowUp", true, false)],
  )
  registry.register_editor_command(
    "editor.action.pageDownHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.page_down()),
    [("PageDown", false, false), ("ArrowDown", true, false)],
  )
  registry.register_editor_command(
    "editor.action.goToTopHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.go_to_top()),
    [("Home", false, false), ("ArrowUp", false, true)],
  )
  registry.register_editor_command(
    "editor.action.goToBottomHover",
    viewer => viewer.is_hover_focused(),
    viewer => viewer.with_hover_widget(widget => widget.go_to_bottom()),
    [("End", false, false), ("ArrowDown", false, true)],
  )
}

///|
/// Runs `f` on the persistent content-hover widget, the run-body plumbing of
/// `ContentHoverController.get(editor)?.scrollUp()`, with the source lookup
/// represented locally by the typed central contribution accessor.
fn Viewer::with_hover_widget(
  self : Viewer,
  f : (@hover_browser.ContentHoverWidget) -> Unit,
) -> Unit {
  match self.content_hover_contribution() {
    Some(state) =>
      match state.widget {
        Some(widget) => f(widget)
        None => ()
      }
    None => ()
  }
}

///|
/// The `EditorContextKeys.hoverFocused` context key as a live predicate:
/// whether the document's active element sits inside the hover widget.
fn Viewer::is_hover_focused(self : Viewer) -> Bool {
  match self.content_hover_contribution() {
    Some(state) =>
      match state.widget {
        Some(widget) =>
          @base_browser.element_contains_active_element(widget.wrapper)
        None => false
      }
    None => false
  }
}
