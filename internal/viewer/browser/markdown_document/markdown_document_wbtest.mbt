///|
fn projected_document_code_block(
  source : String,
) -> @markdown_core.MarkdownCodeBlock {
  let rendered = @markdown_core.render_markdown(source)
  guard rendered.projection.code_blocks is [block, ..] else {
    abort("fixture did not produce a projected code block")
  }
  block
}

///|
test "document code wrapper keeps stable block identity and semantic opt-in" {
  let first = projected_document_code_block(
    (
      #|```mbt check trailing
      #|fn first() -> Int { 1 }
      #|```
    ),
  )
  let ordinary = render_markdown_document_code_block(
    first,
    Some("moonbit"),
    OrdinaryMarkdown,
  )
  let semantic = render_markdown_document_code_block(
    first,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(ordinary.contains("data-markdown-code-block=\"0\""))
  assert_false(ordinary.contains("data-markdown-semantic"))
  assert_true(semantic.contains("data-markdown-code-block=\"0\""))
  assert_true(semantic.contains("data-markdown-semantic=\"moonbit-check\""))

  let second = @markdown_core.render_markdown(
      (
        #|```mbt check
        #|fn same() {}
        #|```
        #|
        #|```mbt check
        #|fn same() {}
        #|```
      ),
    ).projection.code_blocks[1]
  let second_html = render_markdown_document_code_block(
    second,
    Some("moonbit"),
    MoonBitMarkdown,
  )
  assert_true(second_html.contains("data-markdown-code-block=\"1\""))
}

///|
test "document Mermaid theme follows the active presentation theme" {
  assert_true(markdown_document_mermaid_theme("light") == Light)
  assert_true(markdown_document_mermaid_theme("dark") == Dark)
  assert_true(markdown_document_mermaid_theme("custom-dark") == Dark)
}
