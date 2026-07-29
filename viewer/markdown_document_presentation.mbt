///|
/// Exact automatic presentation classifier. Lowercase `.md` includes
/// `.mbt.md`; the language-id arm supports in-memory and untitled Markdown
/// models. No query/fragment text participates because matching is on the
/// decoded URI path component.
fn document_presentation_kind(
  model : @model.TextModel,
) -> DocumentPresentationKind {
  if model.uri.path.has_suffix(".md") || model.get_language_id() == "markdown" {
    let resource_kind = if model.uri.path.has_suffix(".mbt.md") {
      @markdown_core.MarkdownResourceKind::MoonBitMarkdown
    } else {
      OrdinaryMarkdown
    }
    MarkdownDocument(resource_kind)
  } else {
    CodeDocument
  }
}

///|
fn Viewer::on_markdown_document_focus_changed(
  self : Viewer,
  focused : Bool,
) -> Unit {
  match self.mount {
    Headless => ()
    Mounted(mounted) =>
      if mounted.set_editor_focus(focused) {
        self.emit_view_event(ViewFocusChanged(ViewFocusChangedEvent(focused)))
        self.schedule_render()
      }
  }
}

///|
fn Viewer::on_markdown_document_scroll(self : Viewer) -> Unit {
  guard self.current_markdown_document() is Some(_) else { return }
  self.scroll_dirty = true
  self.schedule_render()
}

///|
fn Viewer::on_markdown_document_size_changed(self : Viewer) -> Unit {
  guard self.current_markdown_document() is Some(_) else { return }
  self.scroll_dirty = true
  self.schedule_render()
}
