///|
/// The fallback tokenizer used when no language is registered: the
/// original generic lexer (MoonBit-ish keywords, strings, numbers, line
/// comments) re-expressed line by line. It is stateless; its state is a
/// single value so every entry state compares equal.
pub struct PlainTokenizer {}

///|
/// Creates the stateless fallback tokenizer.
#alias(new, deprecated)
#warnings("-unnecessary_annotation")
pub fn PlainTokenizer::PlainTokenizer() -> PlainTokenizer {
  PlainTokenizer::{  }
}

///|
/// Entry state for the stateless fallback tokenizer.
pub impl LineTokenizer for PlainTokenizer with fn initial_state(_self) {
  TokenizerState("")
}

///|
/// Tokenizes one line with simple MoonBit-ish lexical classes.
pub impl LineTokenizer for PlainTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[LineToken] = []
  let mut offset = 0
  while offset < line_text.length() {
    let unit = line_text[offset].to_int()
    if is_space(unit) {
      offset = offset + 1
    } else if unit == 47 &&
      offset + 1 < line_text.length() &&
      line_text[offset + 1].to_int() == 47 {
      tokens.push({ start: offset, end: line_text.length(), tag: Comment })
      offset = line_text.length()
    } else if unit == 34 {
      let start = offset
      offset = consume_string(line_text, offset)
      tokens.push({ start, end: offset, tag: String })
    } else if is_digit(unit) {
      let start = offset
      offset = consume_while(line_text, offset, is_digit)
      tokens.push({ start, end: offset, tag: Number })
    } else if is_ident_start(unit) {
      let start = offset
      offset = consume_while(line_text, offset, is_ident_continue)
      tokens.push({
        start,
        end: offset,
        tag: if is_keyword(line_text[start:offset].to_owned()) {
          Keyword
        } else {
          Identifier
        },
      })
    } else {
      // A surrogate pair is one punctuation token: token boundaries must
      // stay on whole characters or downstream text slicing panics.
      let start = offset
      offset = if @base_common.is_high_surrogate(unit) &&
        offset + 1 < line_text.length() &&
        @base_common.is_low_surrogate(line_text[offset + 1].to_int()) {
        offset + 2
      } else {
        offset + 1
      }
      tokens.push({ start, end: offset, tag: Punctuation })
    }
  }
  (tokens, state)
}

///|
fn consume_string(text : String, offset : Int) -> Int {
  let mut at = offset + 1
  let mut escaped = false
  while at < text.length() {
    let unit = text[at].to_int()
    if escaped {
      escaped = false
    } else if unit == 92 {
      escaped = true
    } else if unit == 34 {
      return at + 1
    }
    at = at + 1
  }
  at
}

///|
fn consume_while(text : String, offset : Int, pred : (Int) -> Bool) -> Int {
  let mut at = offset
  while at < text.length() && pred(text[at].to_int()) {
    at = at + 1
  }
  at
}

///|
fn is_space(unit : Int) -> Bool {
  unit == 9 || unit == 10 || unit == 13 || unit == 32
}

///|
fn is_digit(unit : Int) -> Bool {
  48 <= unit && unit <= 57
}

///|
fn is_ident_start(unit : Int) -> Bool {
  (65 <= unit && unit <= 90) || (97 <= unit && unit <= 122) || unit == 95
}

///|
fn is_ident_continue(unit : Int) -> Bool {
  is_ident_start(unit) || is_digit(unit)
}

///|
fn is_keyword(text : String) -> Bool {
  text == "fn" ||
  text == "let" ||
  text == "pub" ||
  text == "struct" ||
  text == "enum" ||
  text == "match" ||
  text == "if" ||
  text == "else" ||
  text == "while" ||
  text == "for" ||
  text == "return" ||
  text == "test" ||
  text == "import"
}
