///| Faithful port of vscode's `common/languages/textToHtmlTokenizer.ts` (pinned
/// `vscode/` checked-in submodule): the two pure HTML emitters
/// `tokenizeLineToHTML` and `_tokenizeToString`, consuming the ported
/// `@tokens.LineTokens`/`ViewLineTokens` (as in Monaco, where this file
/// imports `tokens/lineTokens`).
///
/// `_tokenizeToString`'s `IReducedTokenizationSupport` is adapted to the viewer
/// seam as a stateless `tokenize_encoded : (String) -> Array[UInt]` closure
/// returning a line's raw start-offset token pairs (even = start offset, odd =
/// metadata word) — matching the conformance suite's `Mode`, whose
/// `tokenizeEncoded` ignores tokenization state.

///|
/// Splits `text` on `\r\n` / `\r` / `\n`. Mirrors `strings.splitLines`.
fn split_lines(text : String) -> Array[String] {
  let lines = []
  let start = StringBuilder::new()
  let len = text.length()
  let mut i = 0
  while i < len {
    let code = text[i].to_int()
    if code == 13 { // \r
      lines.push(start.to_string())
      start.reset()
      if i + 1 < len && text[i + 1].to_int() == 10 {
        i += 1 // consume the \n of a \r\n pair
      }
    } else if code == 10 { // \n
      lines.push(start.to_string())
      start.reset()
    } else {
      start.write_string(text[i:i + 1].to_owned())
    }
    i += 1
  }
  lines.push(start.to_string())
  lines
}

///|
/// Renders a single line's tokens to HTML with inline styles, expanding tabs and
/// (when `use_nbsp`) collapsing runs of spaces to `&#160;`. Faithful port of
/// `tokenizeLineToHTML`.
pub fn tokenize_line_to_html(
  text : String,
  view_line_tokens : @tokens.ViewLineTokens,
  color_map : Array[String],
  start_offset : Int,
  end_offset : Int,
  tab_size : Int,
  use_nbsp : Bool,
) -> String {
  let result = StringBuilder::new()
  result.write_string("<div>")
  let mut char_index = 0
  let mut width = 0
  let mut prev_is_space = true
  let token_count = view_line_tokens.get_count()
  for token_index in 0..<token_count {
    let token_end_index = view_line_tokens.get_end_offset(token_index)
    let part = StringBuilder::new()
    while char_index < token_end_index && char_index < end_offset {
      let char_code = text[char_index].to_int()
      let is_tab = char_code == 9
      width += if @base_common.is_full_width_character(char_code) {
        2
      } else if is_tab {
        0
      } else {
        1
      }
      if char_index < start_offset {
        if is_tab {
          let remainder = width % tab_size
          width += if remainder == 0 { tab_size } else { tab_size - remainder }
        }
        char_index += 1
        continue
      }
      if char_code == 9 { // Tab
        let remainder = width % tab_size
        let insert_spaces_count = if remainder == 0 {
          tab_size
        } else {
          tab_size - remainder
        }
        width += insert_spaces_count
        let mut spaces_remaining = insert_spaces_count
        while spaces_remaining > 0 {
          if use_nbsp && prev_is_space {
            part.write_string("&#160;")
            prev_is_space = false
          } else {
            part.write_string(" ")
            prev_is_space = true
          }
          spaces_remaining -= 1
        }
      } else if char_code == 60 { // <
        part.write_string("&lt;")
        prev_is_space = false
      } else if char_code == 62 { // >
        part.write_string("&gt;")
        prev_is_space = false
      } else if char_code == 38 { // &
        part.write_string("&amp;")
        prev_is_space = false
      } else if char_code == 0 { // Null
        part.write_string("&#00;")
        prev_is_space = false
      } else if char_code == 65279 ||
        char_code == 8232 ||
        char_code == 8233 ||
        char_code == 133 {
        // UTF8_BOM, LINE_SEPARATOR, PARAGRAPH_SEPARATOR, NEXT_LINE
        part.write_string("\u{FFFD}")
        prev_is_space = false
      } else if char_code == 13 { // CarriageReturn (zero-width space)
        part.write_string("&#8203")
        prev_is_space = false
      } else if char_code == 32 { // Space
        if use_nbsp && prev_is_space {
          part.write_string("&#160;")
          prev_is_space = false
        } else {
          part.write_string(" ")
          prev_is_space = true
        }
      } else {
        part.write_string(text[char_index:char_index + 1].to_owned())
        prev_is_space = false
      }
      char_index += 1
    }
    if token_end_index <= start_offset {
      continue
    }
    result.write_string("<span style=\"")
    result.write_string(
      view_line_tokens.get_inline_style(token_index, color_map),
    )
    result.write_string("\">")
    result.write_string(part.to_string())
    result.write_string("</span>")
    if token_end_index > end_offset ||
      char_index >= end_offset ||
      start_offset >= end_offset {
      break
    }
  }
  result.write_string("</div>")
  result.to_string()
}

///|
/// Renders `text` to class-based token spans inside a
/// `<div class="monaco-tokenized-source">`, lines separated by `<br/>`. Faithful
/// port of `_tokenizeToString`; `tokenize_encoded` is the per-line tokenization
/// seam (see file header).
pub fn tokenize_to_string(
  text : String,
  codec : @services.LanguageIdCodec,
  tokenize_encoded : (String) -> Array[UInt],
) -> String {
  let result = StringBuilder::new()
  result.write_string("<div class=\"monaco-tokenized-source\">")
  let lines = split_lines(text)
  for i, line in lines {
    if i > 0 {
      result.write_string("<br/>")
    }
    let tokens = tokenize_encoded(line)
    @tokens.LineTokens::convert_to_end_offset(tokens, line.length())
    let line_tokens = @tokens.LineTokens(tokens, line, codec)
    let view_line_tokens = line_tokens.inflate()
    let mut start_offset = 0
    for j in 0..<view_line_tokens.get_count() {
      let type_ = view_line_tokens.get_class_name(j)
      let end_index = view_line_tokens.get_end_offset(j)
      result.write_string("<span class=\"")
      result.write_string(type_)
      result.write_string("\">")
      result.write_string(
        @base_common.escape(line[start_offset:end_index].to_owned()),
      )
      result.write_string("</span>")
      start_offset = end_index
    }
  }
  result.write_string("</div>")
  result.to_string()
}
