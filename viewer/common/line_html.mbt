///|
/// The class of the line node itself. The former `CurrentLine`-decoration
/// merge is gone: the current-line highlight renders through its own overlay
/// since 2026-07-02, and no producer created `CurrentLine` decorations
/// anymore (decoration plan Phase 4 retirement, pulled forward with the
/// Phase-3 seam rewire).
pub fn render_line_class() -> String {
  "view-line"
}

///|
/// HTML-escapes text for element content or attribute values. This package
/// forwards to the shared base/common implementation.
pub fn escape_html(text : String) -> String {
  @base_common.escape_html(text)
}
