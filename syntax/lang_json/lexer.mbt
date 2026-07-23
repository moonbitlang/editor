///|
/// JSON (and JSONC comments) behind the `syntax.LineTokenizer` contract:
/// the trivial two-state machine. State "n" is normal; state "c" is
/// inside a `/* ... */` block comment, the one construct that carries
/// across lines.
pub struct JsonTokenizer {}

///|
/// Creates the JSON/JSONC tokenizer.
#alias(new, deprecated)
#warnings("-unnecessary_annotation")
pub fn JsonTokenizer::JsonTokenizer() -> JsonTokenizer {
  JsonTokenizer::{  }
}

///|
/// Initial JSON lexer state outside block comments.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn initial_state(_self) {
  TokenizerState("n")
}

///|
/// Tokenizes one JSON/JSONC line while carrying block-comment state.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  let mut in_comment = state == TokenizerState("c")
  let mut at = 0
  let mut view = line_text[:]
  while view.length() > 0 {
    let (op, rest) = if in_comment {
      comment_step(view)
    } else {
      normal_step(view)
    }
    let consumed = view.length() - rest.length()
    match op {
      Blank => ()
      Emit(tag) => tokens.push({ start: at, end: at + consumed, tag })
      EnterComment => {
        tokens.push({ start: at, end: at + consumed, tag: Comment })
        in_comment = true
      }
      LeaveComment => {
        tokens.push({ start: at, end: at + consumed, tag: Comment })
        in_comment = false
      }
    }
    at = at + consumed
    view = rest
  }
  (tokens, TokenizerState(if in_comment { "c" } else { "n" }))
}

///|
priv enum StepOp {
  Blank
  Emit(@syntax.HighlightTag)
  EnterComment
  LeaveComment
}

///|
fn normal_step(view : StringView) -> (StepOp, StringView) {
  lexscan view with longest {
    (re"^[ \t]+", after=rest) => (Blank, rest)
    (re"^//.*", after=rest) => (Emit(Comment), rest)
    (re"^/\*", after=rest) => (EnterComment, rest)
    // A terminated string is a property name when the next significant
    // character is a colon — the Monarch lookahead idiom done by peeking
    // the rest of the line instead.
    (re"^\"(?:\\.|[^\"\\])*\"", after=rest) =>
      (Emit(if colon_follows(rest) { Attribute } else { String }), rest)
    (re"^\"(?:\\.|[^\"\\])*", after=rest) => (Emit(String), rest)
    (re"^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?", after=rest) =>
      (Emit(Number), rest)
    (re"^[a-zA-Z_][a-zA-Z0-9_]*" as word, after=rest) =>
      (
        Emit(
          match word {
            "true" | "false" | "null" => Constant
            _ => Invalid
          },
        ),
        rest,
      )
    (re"^[{}\[\],:]", after=rest) => (Emit(Delimiter), rest)
    (re"^.", after=rest) => (Emit(Punctuation), rest)
    // Unreachable while `.` covers the full charset (it includes lone
    // surrogates); consumes the rest defensively so the driver loop can
    // never stall on zero progress.
    _ => (Blank, ""[:])
  }
}

///|
fn comment_step(view : StringView) -> (StepOp, StringView) {
  lexscan view with longest {
    (re"^\*/", after=rest) => (LeaveComment, rest)
    (re"^[^*]+", after=rest) => (Emit(Comment), rest)
    (re"^\*", after=rest) => (Emit(Comment), rest)
    _ => (Blank, ""[:])
  }
}

///|
fn colon_follows(rest : StringView) -> Bool {
  for i in 0..<rest.length() {
    let unit = rest[i].to_int()
    if unit == 32 || unit == 9 {
      continue
    }
    return unit == 58
  }
  false
}
