///|
/// A cmark-independent fenced or indented code block passed to a synchronous
/// renderer override. `language_id` is the first fenced-info token exactly as
/// parsed by cmark; an unlabelled or indented block has no language id.
pub(all) struct MarkdownCodeBlock {
  code : String
  language_id : String?
} derive(Eq, Debug)

///|
/// Safe HTML and the render fact browser consumers need for layout/class
/// decisions.
pub(all) struct MarkdownRenderFact {
  html : String
  has_code_block : Bool
} derive(Eq, Debug)

///|
/// Converts Markdown with cmark's safe HTML renderer. A code-block override is
/// synchronous and receives both the MoonBit-owned block value and the active
/// language id supplied by the caller. Conversion failures never expose raw
/// input as HTML: they produce one escaped plaintext paragraph.
pub fn render_markdown(
  markdown : String,
  language_id? : String,
  code_block_renderer? : (MarkdownCodeBlock, String?) -> String,
) -> MarkdownRenderFact {
  let saw_code_block = Ref(false)
  let code_override = @cmark_renderer.Renderer::new(block=fn(ctx, block) {
    match block {
      CodeBlock(node) => {
        saw_code_block.val = true
        let code_block = {
          code: markdown_code_block_text(node.v),
          language_id: markdown_code_block_language(node.v),
        }
        match render_diagram_code_block(code_block) {
          Some(html) => {
            ctx.string(html)
            true
          }
          None =>
            match code_block_renderer {
              Some(render) => {
                ctx.string(render(code_block, language_id))
                true
              }
              None => false
            }
        }
      }
      _ => false
    }
  })
  let doc = @cmark.Doc::from_string(markdown, strict=false)
  markdown_conversion_result(markdown, saw_code_block, () => {
    @cmark_html.renderer(safe=true).compose(code_override).doc_to_string(doc)
  })
}

///|
fn markdown_code_block_text(block : @cmark.CodeBlock) -> String {
  let lines : Array[String] = []
  for line in block.code {
    lines.push(line.v)
  }
  if lines.length() == 0 {
    ""
  } else {
    lines.join("\n") + "\n"
  }
}

///|
fn markdown_code_block_language(block : @cmark.CodeBlock) -> String? {
  block.info_string
  .map(info => info.v)
  .bind(@cmark.CodeBlock::language_of_info_string)
  .map(pair => pair.0)
}

///|
/// Kept as a narrow conversion seam so the otherwise exceptional fallback is
/// directly reproducible in the multi-target focused suite.
fn markdown_conversion_result(
  markdown : String,
  saw_code_block : Ref[Bool],
  convert : () -> String raise,
) -> MarkdownRenderFact {
  let html = convert() catch {
    _ =>
      return {
        html: "<p>" + markdown_escape_html(markdown) + "</p>\n",
        has_code_block: false,
      }
  }
  { html, has_code_block: saw_code_block.val }
}

///|
fn markdown_escape_html(text : String) -> String {
  let escaped = StringBuilder::new(size_hint=text.length())
  for char in text {
    match char {
      '&' => escaped.write_string("&amp;")
      '<' => escaped.write_string("&lt;")
      '>' => escaped.write_string("&gt;")
      '"' => escaped.write_string("&quot;")
      _ => escaped.write_char(char)
    }
  }
  escaped.to_string()
}
