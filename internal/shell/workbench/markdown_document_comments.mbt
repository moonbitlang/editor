// An opened `.md` document reads best as one rendered Markdown surface. The
// reference shell owns this adapter so the reusable Viewer stays
// language-neutral: the whole file becomes a single whole-line Markdown block
// and flows through the same rendering pipeline as API documentation —
// tokenized code fences, Mermaid, and Diago included.

///|
priv struct MarkdownDocumentCommentProvider {}

///|
impl @language.MarkdownCommentProvider for MarkdownDocumentCommentProvider with fn provide_markdown_comments(
  _self,
  model,
) {
  markdown_document_comments_in_snapshot(model.snapshot())
}

///|
fn install_markdown_document_comment_provider(
  languages : @languages.Languages,
) -> Unit {
  languages.register_markdown_comment_provider(LanguageId("markdown"), MarkdownDocumentCommentProvider::{

  })
  |> ignore
}

///|
/// Returns one block covering every line but the last. The view projection
/// cannot hide the entire model, so the final line stays visible: a
/// newline-terminated document leaves only its empty last line as source,
/// while a file without a trailing newline keeps its last raw line below the
/// rendered document. Blank documents render as ordinary source.
fn markdown_document_comments_in_snapshot(
  snapshot : @model.TextSnapshot,
) -> Array[@language.MarkdownCommentBlock] {
  let line_count = snapshot.line_count()
  if line_count < 2 {
    return []
  }
  let contents : Array[String] = []
  for line_number in 1..<line_count {
    contents.push(snapshot.get_line_content(line_number))
  }
  let markdown = contents.join("\n")
  if markdown.trim().is_empty() {
    return []
  }
  [{ line_range: LineRange(1, line_count), markdown }]
}
