///|
/// Renders package-owned exact lowercase `d2` and `diago` fences before any
/// caller override. Unknown, unlabelled, and failed diagram blocks keep the
/// existing fallback.
///
/// ```d2
/// direction: right
///
/// fence: fenced block
/// language: exact d2 or diago?
/// compile: Diago compile to SVG
/// wrapper: diagram wrapper
/// fallback: ordinary code HTML
///
/// fence -> language
/// language -> compile: yes
/// language -> fallback: no
/// compile -> wrapper: success
/// compile -> fallback: failure
/// ```
fn render_diagram_code_block(code_block : MarkdownCodeBlock) -> String? {
  match code_block.language_id {
    Some("diago") | Some("d2") =>
      render_diago_svg(code_block.code).map(svg => {
        wrap_diagram_svg("diago", svg)
      })
    _ => None
  }
}

///|
fn render_diago_svg(source : String) -> String? {
  let svg = @diago.compile(
    source,
    options=@diago.CompileOptions::new().with_output_mode(Svg),
  ) catch {
    _ => return None
  }
  Some(svg)
}

///|
fn wrap_diagram_svg(language_id : String, svg : String) -> String {
  (
    $|<div class="moonbit-viewer-markdown-diagram" data-diagram-language="\{language_id}">
    $|\{svg}
    $|</div>
    $|
  )
}
