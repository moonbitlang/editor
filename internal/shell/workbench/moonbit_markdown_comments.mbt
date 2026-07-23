// MoonBit documentation comments are anchored by the formatter's exact
// top-level `///|` separator. The generic `///` detector cannot distinguish
// that marker from Markdown content, so the reference shell owns this
// language-specific adapter and keeps the reusable Viewer language-neutral.

///|
priv struct MoonBitMarkdownCommentProvider {}

///|
impl @language.MarkdownCommentProvider for MoonBitMarkdownCommentProvider with fn provide_markdown_comments(
  _self,
  model,
) {
  moonbit_markdown_comments_in_snapshot(model.snapshot())
}

///|
fn install_moonbit_markdown_comment_provider(
  languages : @languages.Languages,
) -> Unit {
  languages.register_markdown_comment_provider(LanguageId("moonbit"), MoonBitMarkdownCommentProvider::{

  })
  |> ignore
}

///|
/// Returns anchored MoonBit documentation blocks. An undocumented `///|`
/// remains ordinary source; an anchored block hides the marker together with
/// its consecutive `///` documentation lines while omitting the marker from
/// the Markdown body.
fn moonbit_markdown_comments_in_snapshot(
  snapshot : @model.TextSnapshot,
) -> Array[@language.MarkdownCommentBlock] {
  let blocks : Array[@language.MarkdownCommentBlock] = []
  let line_count = snapshot.line_count()
  let mut line_number = 1
  while line_number <= line_count {
    if snapshot.get_line_content(line_number) != "///|" {
      line_number += 1
      continue
    }
    let start_line_number = line_number
    line_number += 1
    let contents : Array[String] = []
    while line_number <= line_count {
      match
        moonbit_markdown_comment_line_content(
          snapshot.get_line_content(line_number),
        ) {
        Some(content) => {
          contents.push(content)
          line_number += 1
        }
        None => break
      }
    }
    if !contents.is_empty() {
      blocks.push({
        line_range: LineRange(start_line_number, line_number),
        markdown: contents.join("\n"),
      })
    }
  }
  blocks
}

///|
/// Strips exactly `///` and at most one following ASCII space. A second exact
/// `///|` is a new item boundary, not documentation owned by the current one.
fn moonbit_markdown_comment_line_content(line : String) -> String? {
  if line == "///|" || !line.has_prefix("///") {
    return None
  }
  let mut content_start = 3
  if content_start < line.length() && line[content_start].to_int() == 32 {
    content_start += 1
  }
  Some(line.unsafe_substring(start=content_start, end=line.length()))
}
