///|
/// Pure line-HTML emission, the Monaco `viewLineRenderer` role: view-line
/// data plus its per-line `LineDecoration`s become the escaped inner HTML of
/// one `.view-line` node. No DOM types; the browser view assigns the result
/// with one `innerHTML` write per entering line.
pub fn render_line_html(
  line : @view_model.ViewLineData,
  line_decorations : Array[@view_layout.LineDecoration],
  render_whitespace? : @editor_api.RenderWhitespace = None,
  render_control_characters? : Bool = false,
) -> String {
  @view_layout.render_view_line2(
    @view_model.render_line_input_from_view_line_data(
      line,
      line_decorations~,
      render_whitespace~,
      render_control_characters~,
    ),
  ).html
}

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
/// HTML-escapes text for element content or attribute values.
pub fn escape_html(text : String) -> String {
  let html = StringBuilder()
  write_escaped(html, text)
  html.to_string()
}

///|
fn write_escaped(html : StringBuilder, text : String) -> Unit {
  for ch in text {
    match ch {
      '&' => html.write_string("&amp;")
      '<' => html.write_string("&lt;")
      '>' => html.write_string("&gt;")
      '"' => html.write_string("&quot;")
      _ => html.write_char(ch)
    }
  }
}
