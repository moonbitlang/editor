// Ported from `vscode/src/vs/editor/browser/viewParts/editorScrollbar/editorScrollbar.ts`.
// The custom scrollbar geometry/DOM itself lives in
// `internal/viewer/ui/scrollbar`
// (Monaco's `base/browser/ui/scrollbar/`); `EditorScrollbar` is the thin
// view-part wrapper around it. Its lifecycle wiring lives in
// `internal/viewer/browser/view/view_overlays_lifecycle.mbt`.

///|
/// Public scrollbar owner for root callers. Package-local lifecycle code
/// reads/writes its private `should_render` state directly.
pub struct EditorScrollbar {
  priv editor_scrollable : @scrollbar.ScrollableElementDom
  priv scrollbar_dom_node : @scrollbar.CachedDomNode
  priv mut should_render : Bool
}

///|
fn EditorScrollbar::EditorScrollbar(
  lines_content : @scrollbar.CachedDomNode,
) -> EditorScrollbar {
  let editor_scrollable = @scrollbar.ScrollableElementDom(
    "lines-content moonbit-viewer-background",
    vertical_size=@core.editor_vertical_scrollbar_size,
    horizontal_size=@core.editor_horizontal_scrollbar_size,
    content=lines_content.element(),
  )
  editor_scrollable.set_wrapper_class(
    "monaco-scrollable-element editor-scrollable",
  )
  editor_scrollable.wrapper.set_attribute("data-view-part", "editor-scrollable")
  editor_scrollable.content.set_attribute("data-view-part", "lines-content")
  editor_scrollable.update_from_model(
    { width: 0.0, scroll_width: 0.0, height: 0.0, scroll_height: 0.0 },
    { scroll_left: 0.0, scroll_top: 0.0 },
  )
  let scrollbar_dom_node = @scrollbar.CachedDomNode(editor_scrollable.wrapper)
  scrollbar_dom_node.set_position("absolute")
  { editor_scrollable, scrollbar_dom_node, should_render: true }
}

///|
fn EditorScrollbar::get_dom_node(self : EditorScrollbar) -> @rdom.Element {
  self.editor_scrollable.wrapper
}

///|
pub fn EditorScrollbar::content(self : EditorScrollbar) -> @rdom.Element {
  self.editor_scrollable.content
}

///|
pub fn EditorScrollbar::scrollable(
  self : EditorScrollbar,
) -> @scrollbar.ScrollableElementDom {
  self.editor_scrollable
}
