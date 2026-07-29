// MoonBit documentation comments and item separators are anchored by the
// formatter's top-level `///|` delimiter, either alone or followed by an ASCII
// space and the first documentation line. The generic `///` detector cannot
// distinguish that delimiter from Markdown content, so the reference shell
// owns this language-specific adapter and keeps the reusable Viewer
// language-neutral.

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
/// Recognizes a MoonBit item delimiter and returns optional documentation from
/// the same line. Requiring an ASCII space after `///|` keeps near-misses such
/// as `///|not-a-boundary` out of the item stream.
fn moonbit_markdown_item_boundary_content(line : String) -> String? {
  if line == "///|" {
    return Some("")
  }
  if !line.has_prefix("///| ") {
    return None
  }
  Some(line.unsafe_substring(start=5, end=line.length()))
}

///|
/// Returns anchored MoonBit documentation and item-separator blocks. Every
/// `///|` delimiter becomes a Markdown horizontal rule. Text after `///| ` is
/// the first documentation line; consecutive `///` lines, when present,
/// continue that body. The source marker and documentation lines are hidden
/// together.
fn moonbit_markdown_comments_in_snapshot(
  snapshot : @model.TextSnapshot,
) -> Array[@language.MarkdownCommentBlock] {
  let blocks : Array[@language.MarkdownCommentBlock] = []
  let line_count = snapshot.line_count()
  let mut line_number = 1
  while line_number <= line_count {
    let boundary_content = match
      moonbit_markdown_item_boundary_content(
        snapshot.get_line_content(line_number),
      ) {
      Some(content) => content
      None => {
        line_number += 1
        continue
      }
    }
    let start_line_number = line_number
    line_number += 1
    let contents : Array[String] = []
    if !boundary_content.is_empty() {
      contents.push(boundary_content)
    }
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
    blocks.push({
      line_range: LineRange(start_line_number, line_number),
      markdown: if contents.is_empty() {
        "---"
      } else {
        "---\n\n" + contents.join("\n")
      },
    })
  }
  blocks
}

///|
/// Strips exactly `///` and at most one following ASCII space. A second exact
/// or inline `///|` delimiter is a new item boundary, not documentation owned
/// by the current one.
fn moonbit_markdown_comment_line_content(line : String) -> String? {
  if moonbit_markdown_item_boundary_content(line) is Some(_) ||
    !line.has_prefix("///") {
    return None
  }
  let mut content_start = 3
  if content_start < line.length() && line[content_start].to_int() == 32 {
    content_start += 1
  }
  Some(line.unsafe_substring(start=content_start, end=line.length()))
}
