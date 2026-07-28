// MoonBit documentation comments and item separators are anchored by the
// formatter's exact top-level `///|` marker. The generic `///` detector cannot
// distinguish that marker from Markdown content, so the reference shell owns
// this language-specific adapter and keeps the reusable Viewer language-neutral.

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
/// Returns anchored MoonBit documentation and item-separator blocks. Every
/// exact `///|` becomes a Markdown horizontal rule; consecutive `///` lines,
/// when present, follow that separator as the documentation body. Documented
/// blocks render after the following item signature; undocumented separators
/// remain at their source position. The source marker and documentation lines
/// are hidden together.
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
    blocks.push({
      line_range: LineRange(start_line_number, line_number),
      markdown: if contents.is_empty() {
        "---"
      } else {
        "---\n\n" + contents.join("\n")
      },
      render_after_line_number: if contents.is_empty() {
        None
      } else {
        moonbit_signature_end_line_number(snapshot, line_number)
      },
    })
  }
  blocks
}

///|
/// Finds the last source line of the item signature following an anchored doc
/// block. MoonBit's tokenizer keeps braces in strings and comments out of the
/// delimiter stream, so a body-opening `{` is authoritative. Balanced `()` or
/// `[]` keep a multiline signature open, `where { ... }` specifications and
/// balanced attributes are crossed, and implementation comments are skipped. A
/// blank line or an attribute/comment-only tail without a declaration leaves
/// detached documentation at its source position.
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
  let mut specification_depth = 0
  let mut awaiting_specification_block = false
  let mut saw_signature_candidate = false
  let mut fallback_line_number = first_line_number
  while line_number <= line_count {
    let line = snapshot.get_line_content(line_number)
    let (tokens, next_state) = tokenizer.tokenize_line(line, state)
    state = next_state
    if tokens.is_empty() {
      if delimiter_depth > 0 ||
        attribute_depth > 0 ||
        specification_depth > 0 ||
        awaiting_specification_block {
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
      line_number += 1
      continue
    }
    saw_signature_candidate = true
    for token in tokens {
      let token_text = line[token.start:token.end].to_owned()
      if token.tag == Keyword &&
        token_text == "where" &&
        specification_depth == 0 {
        awaiting_specification_block = true
        continue
      }
      if token.tag != Delimiter {
        continue
      }
      for char in token_text {
        if specification_depth > 0 {
          match char {
            '{' => specification_depth += 1
            '}' => specification_depth -= 1
            _ => ()
          }
          continue
        }
        match char {
          '{' =>
            if awaiting_specification_block {
              specification_depth = 1
              awaiting_specification_block = false
            } else if delimiter_depth == 0 {
              return Some(line_number)
            }
          '(' | '[' => delimiter_depth += 1
          ')' | ']' => delimiter_depth = (delimiter_depth - 1).max(0)
          _ => ()
        }
      }
    }
    fallback_line_number = line_number
    if delimiter_depth == 0 &&
      specification_depth == 0 &&
      !awaiting_specification_block {
      return Some(line_number)
    }
    line_number += 1
  }
  if saw_signature_candidate {
    Some(fallback_line_number)
  } else {
    None
  }
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
