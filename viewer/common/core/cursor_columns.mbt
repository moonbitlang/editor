// Port of Monaco/VS Code's CursorColumns visible-column math.
//
// Source: vscode/src/vs/editor/common/core/cursorColumns.ts
//   with isFullWidthCharacter / isEmojiImprecise / getNextCodePoint from
//   vscode/src/vs/base/common/strings.ts
// (checked-in vscode submodule).
//
// A "visible column" is a rough horizontal screen position: tabs advance to the
// next tab stop, full-width/emoji code points count as two, everything else as
// one.
//
// Adaptation: the upstream column<->visible-column helpers iterate graphemes via
// Intl segmentation; this port iterates code points. The two agree for any
// input without multi-code-point graphemes (no ZWJ emoji / combining marks),
// which covers the conformance corpus.

///|
fn compute_code_point(high : Int, low : Int) -> Int {
  (high - 0xD800) * 0x400 + (low - 0xDC00) + 0x10000
}

///|
fn get_next_code_point(str : String, len : Int, offset : Int) -> Int {
  let char_code = str[offset].to_int()
  if @base_common.is_high_surrogate(char_code) && offset + 1 < len {
    let next_char_code = str[offset + 1].to_int()
    if @base_common.is_low_surrogate(next_char_code) {
      return compute_code_point(char_code, next_char_code)
    }
  }
  char_code
}

///|
fn code_point_utf16_length(code_point : Int) -> Int {
  if code_point >= 0x10000 {
    2
  } else {
    1
  }
}

///|
fn is_emoji_imprecise(x : Int) -> Bool {
  (x >= 0x1F1E6 && x <= 0x1F1FF) ||
  x == 8986 ||
  x == 8987 ||
  x == 9200 ||
  x == 9203 ||
  (x >= 9728 && x <= 10175) ||
  x == 11088 ||
  x == 11093 ||
  (x >= 127744 && x <= 128591) ||
  (x >= 128640 && x <= 128764) ||
  (x >= 128992 && x <= 129008) ||
  (x >= 129280 && x <= 129535) ||
  (x >= 129648 && x <= 129782)
}

///|
fn next_visible_column(
  code_point : Int,
  visible_column : Int,
  tab_size : Int,
) -> Int {
  if code_point == 9 {
    return next_render_tab_stop(visible_column, tab_size)
  }
  if @base_common.is_full_width_character(code_point) ||
    is_emoji_imprecise(code_point) {
    return visible_column + 2
  }
  visible_column + 1
}

///|
/// Returns a visible column from a (1-based) column.
pub fn visible_column_from_column(
  line_content : String,
  column : Int,
  tab_size : Int,
) -> Int {
  let text_len = if column - 1 < line_content.length() {
    column - 1
  } else {
    line_content.length()
  }
  let mut result = 0
  let mut offset = 0
  while offset < text_len {
    let code_point = get_next_code_point(line_content, text_len, offset)
    offset += code_point_utf16_length(code_point)
    result = next_visible_column(code_point, result, tab_size)
  }
  result
}

///|
/// Returns the value to display as "Col" in the status bar (1-based, code
/// points, tabs snap to tab stops).
pub fn to_statusbar_column(
  line_content : String,
  column : Int,
  tab_size : Int,
) -> Int {
  let text_len = if column - 1 < line_content.length() {
    column - 1
  } else {
    line_content.length()
  }
  let mut result = 0
  let mut offset = 0
  while offset < text_len {
    let code_point = get_next_code_point(line_content, text_len, offset)
    offset += code_point_utf16_length(code_point)
    if code_point == 9 {
      result = next_render_tab_stop(result, tab_size)
    } else {
      result = result + 1
    }
  }
  result + 1
}

///|
/// Returns a (1-based) column from a visible column.
pub fn column_from_visible_column(
  line_content : String,
  visible_column : Int,
  tab_size : Int,
) -> Int {
  if visible_column <= 0 {
    return 1
  }
  let line_content_length = line_content.length()
  let mut before_visible_column = 0
  let mut before_column = 1
  let mut offset = 0
  while offset < line_content_length {
    let code_point = get_next_code_point(
      line_content, line_content_length, offset,
    )
    offset += code_point_utf16_length(code_point)
    let after_visible_column = next_visible_column(
      code_point, before_visible_column, tab_size,
    )
    let after_column = offset + 1
    if after_visible_column >= visible_column {
      let before_delta = visible_column - before_visible_column
      let after_delta = after_visible_column - visible_column
      if after_delta < before_delta {
        return after_column
      } else {
        return before_column
      }
    }
    before_visible_column = after_visible_column
    before_column = after_column
  }
  line_content_length + 1
}

///|
/// ATTENTION: this works with 0-based columns (as opposed to the regular
/// 1-based columns).
pub fn next_render_tab_stop(visible_column : Int, tab_size : Int) -> Int {
  visible_column + tab_size - visible_column % tab_size
}

///|
/// ATTENTION: this works with 0-based columns.
pub fn next_indent_tab_stop(visible_column : Int, indent_size : Int) -> Int {
  next_render_tab_stop(visible_column, indent_size)
}

///|
/// ATTENTION: this works with 0-based columns.
pub fn prev_render_tab_stop(column : Int, tab_size : Int) -> Int {
  let value = column - 1 - (column - 1) % tab_size
  if value > 0 {
    value
  } else {
    0
  }
}

///|
/// ATTENTION: this works with 0-based columns.
pub fn prev_indent_tab_stop(column : Int, indent_size : Int) -> Int {
  prev_render_tab_stop(column, indent_size)
}
