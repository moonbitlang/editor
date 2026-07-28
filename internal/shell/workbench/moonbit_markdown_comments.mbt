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
/// the Markdown body. The rendered block is placed after the following item
/// signature, while its original source range remains the hidden doc lines.
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
        render_after_line_number: moonbit_signature_end_line_number(
          snapshot, line_number,
        ),
      })
    }
  }
  blocks
}

///|
/// Finds the last source line of the item signature following an anchored doc
/// block. MoonBit's tokenizer keeps braces in strings and comments out of the
/// delimiter stream, so a body-opening `{` is authoritative. Balanced `()` or
/// `[]` keep a multiline signature open, balanced attributes and implementation
/// comments are skipped, and a blank line before the declaration leaves detached
/// documentation at its source position.
fn moonbit_signature_end_line_number(
  snapshot : @model.TextSnapshot,
  first_line_number : Int,
) -> Int? {
  let line_count = snapshot.line_count()
  if first_line_number > line_count {
    return None
  }
  let tokenizer : &@syntax.LineTokenizer = @lang_moonbit.MoonbitTokenizer()
  let mut state = tokenizer.initial_state()
  let mut line_number = first_line_number
  let mut delimiter_depth = 0
  let mut attribute_depth = 0
  let mut fallback_line_number = first_line_number
  while line_number <= line_count {
    let line = snapshot.get_line_content(line_number)
    let (tokens, next_state) = tokenizer.tokenize_line(line, state)
    state = next_state
    if tokens.is_empty() {
      if delimiter_depth > 0 || attribute_depth > 0 {
        line_number += 1
        continue
      }
      return None
    }
    if line == "///|" {
      return None
    }
    if tokens[0].tag == Comment || tokens[0].tag == CommentDoc {
      line_number += 1
      continue
    }
    if tokens[0].tag == Attribute || attribute_depth > 0 {
      for token in tokens {
        if token.tag != Delimiter {
          continue
        }
        let delimiter = line[token.start:token.end].to_owned()
        for char in delimiter {
          match char {
            '(' | '[' => attribute_depth += 1
            ')' | ']' => attribute_depth = (attribute_depth - 1).max(0)
            _ => ()
          }
        }
      }
      fallback_line_number = line_number
      line_number += 1
      continue
    }
    for token in tokens {
      if token.tag != Delimiter {
        continue
      }
      let delimiter = line[token.start:token.end].to_owned()
      for char in delimiter {
        match char {
          '{' => if delimiter_depth == 0 { return Some(line_number) }
          '(' | '[' => delimiter_depth += 1
          ')' | ']' => delimiter_depth = (delimiter_depth - 1).max(0)
          _ => ()
        }
      }
    }
    fallback_line_number = line_number
    if delimiter_depth == 0 {
      return Some(line_number)
    }
    line_number += 1
  }
  Some(fallback_line_number)
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
