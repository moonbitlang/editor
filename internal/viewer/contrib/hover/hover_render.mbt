///|
/// Hover's compatibility entry point for the shared Markdown renderer. The
/// DOM-free Markdown package owns cmark conversion, language selection, and
/// editor-token HTML; the optional second argument is the active model
/// language used when a fence has no info string.
pub fn render_hover_code_block(
  code_block : @markdown.MarkdownCodeBlock,
  active_language_id : String?,
) -> String {
  @markdown.render_tokenized_code_block(code_block, active_language_id)
}
