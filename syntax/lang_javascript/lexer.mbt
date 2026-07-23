///|
/// JavaScript behind the `syntax.LineTokenizer` contract, ported by hand
/// from the Monarch typescript grammar's structure. The carried
/// `TokenizerState` encodes the mode stack one character per mode,
/// bottom first:
///   'n' normal code (always the bottom)
///   'c' inside a `/* ... */` block comment (spans lines)
///   'd' inside a `/** ... */` doc comment (spans lines)
///   't' inside a template literal (spans lines)
///   'i' inside a `${ ... }` template interpolation (spans lines)
///   'b' inside a plain `{ ... }` brace pair nested in an interpolation
/// Quoted strings never span lines; regex literals are not detected
/// (the `/` ambiguity needs token-history heuristics) and lex as
/// operators.
pub struct JavascriptTokenizer {}

///|
/// Creates the JavaScript tokenizer.
#alias(new, deprecated)
#warnings("-unnecessary_annotation")
pub fn JavascriptTokenizer::JavascriptTokenizer() -> JavascriptTokenizer {
  JavascriptTokenizer::{  }
}

///|
/// Initial JavaScript lexer mode stack.
pub impl @syntax.LineTokenizer for JavascriptTokenizer with fn initial_state(
  _self,
) {
  TokenizerState("n")
}

///|
/// Tokenizes one JavaScript line while carrying comment/template state.
pub impl @syntax.LineTokenizer for JavascriptTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let stack = decode_stack(state)
  let tokens : Array[@syntax.LineToken] = []
  let mut at = 0
  let mut view = line_text[:]
  while view.length() > 0 {
    let top = stack[stack.length() - 1]
    let (op, rest) = match top {
      'c' => comment_step(view, Comment)
      'd' => comment_step(view, CommentDoc)
      't' => template_step(view)
      _ => normal_step(view, top)
    }
    let consumed = view.length() - rest.length()
    match op {
      Blank => ()
      Emit(tag) => push_token(tokens, at, at + consumed, tag)
      Push(tag, mode) => {
        push_token(tokens, at, at + consumed, tag)
        stack.push(mode)
      }
      Pop(tag) => {
        push_token(tokens, at, at + consumed, tag)
        if stack.length() > 1 {
          ignore(stack.pop())
        }
      }
    }
    at = at + consumed
    view = rest
  }
  (tokens, encode_stack(stack))
}

///|
fn decode_stack(state : @syntax.TokenizerState) -> Array[Char] {
  let stack : Array[Char] = []
  for mode in state.0 {
    stack.push(mode)
  }
  if stack.length() == 0 {
    stack.push('n')
  }
  stack
}

///|
fn encode_stack(stack : Array[Char]) -> @syntax.TokenizerState {
  let encoded = StringBuilder()
  for mode in stack {
    encoded.write_char(mode)
  }
  TokenizerState(encoded.to_string())
}

///|
priv enum StepOp {
  Blank
  Emit(@syntax.HighlightTag)
  Push(@syntax.HighlightTag, Char)
  Pop(@syntax.HighlightTag)
}

///|
/// Contiguous same-tag lexemes coalesce so a quoted string renders as a
/// single span.
fn push_token(
  tokens : Array[@syntax.LineToken],
  start : Int,
  end : Int,
  tag : @syntax.HighlightTag,
) -> Unit {
  if tokens.length() > 0 {
    let last = tokens[tokens.length() - 1]
    if last.tag == tag && last.end == start {
      tokens[tokens.length() - 1] = { start: last.start, end, tag }
      return
    }
  }
  tokens.push({ start, end, tag })
}

///|
fn normal_step(view : StringView, top : Char) -> (StepOp, StringView) {
  lexscan view with longest {
    (re"^[ \t]+", after=rest) => (Blank, rest)
    (re"^//.*", after=rest) => (Emit(Comment), rest)
    // The empty block comment first: longest-match would otherwise read
    // `/**/` as a doc-comment opener.
    (re"^/\*\*/", after=rest) => (Emit(Comment), rest)
    (re"^/\*\*", after=rest) => (Push(CommentDoc, 'd'), rest)
    (re"^/\*", after=rest) => (Push(Comment, 'c'), rest)
    (re"^'(?:\\.|[^'\\])*'", after=rest) => (Emit(String), rest)
    (re"^'(?:\\.|[^'\\])*", after=rest) => (Emit(String), rest)
    (re"^\"(?:\\.|[^\"\\])*\"", after=rest) => (Emit(String), rest)
    (re"^\"(?:\\.|[^\"\\])*", after=rest) => (Emit(String), rest)
    (re"^`", after=rest) => (Push(String, 't'), rest)
    (re"^0[xX][0-9a-fA-F_]+n?", after=rest) => (Emit(Number), rest)
    (re"^0[oO][0-7_]+n?", after=rest) => (Emit(Number), rest)
    (re"^0[bB][01_]+n?", after=rest) => (Emit(Number), rest)
    (re"^[0-9][0-9_]*(?:\.[0-9_]*)?(?:[eE][+\-]?[0-9]+)?n?", after=rest) =>
      (Emit(Number), rest)
    (re"^\.[0-9][0-9_]*(?:[eE][+\-]?[0-9]+)?", after=rest) =>
      (Emit(Number), rest)
    (re"^[a-zA-Z_\$][a-zA-Z0-9_\$]*" as word, after=rest) =>
      (Emit(classify_word(word)), rest)
    (re"^[+\-*/%=<>!&^~?\|]+", after=rest) => (Emit(Operator), rest)
    (re"^[()\[\],;:.]", after=rest) => (Emit(Delimiter), rest)
    (re"^[{]", after=rest) =>
      if top == 'i' || top == 'b' {
        (Push(Delimiter, 'b'), rest)
      } else {
        (Emit(Delimiter), rest)
      }
    (re"^[}]", after=rest) =>
      match top {
        'i' => (Pop(StringEscape), rest)
        'b' => (Pop(Delimiter), rest)
        _ => (Emit(Delimiter), rest)
      }
    (re"^.", after=rest) => (Emit(Punctuation), rest)
    // Unreachable while `.` covers the full charset (it includes lone
    // surrogates); consumes the rest defensively so the driver loop can
    // never stall on zero progress.
    _ => (Blank, ""[:])
  }
}

///|
fn comment_step(
  view : StringView,
  tag : @syntax.HighlightTag,
) -> (StepOp, StringView) {
  lexscan view with longest {
    (re"^\*/", after=rest) => (Pop(tag), rest)
    (re"^[^*]+", after=rest) => (Emit(tag), rest)
    (re"^\*", after=rest) => (Emit(tag), rest)
    _ => (Blank, ""[:])
  }
}

///|
fn template_step(view : StringView) -> (StepOp, StringView) {
  lexscan view with longest {
    (re"^\$[{]", after=rest) => (Push(StringEscape, 'i'), rest)
    (re"^\\.", after=rest) => (Emit(StringEscape), rest)
    (re"^`", after=rest) => (Pop(String), rest)
    (re"^[^`\\\$]+", after=rest) => (Emit(String), rest)
    (re"^.", after=rest) => (Emit(String), rest)
    _ => (Blank, ""[:])
  }
}

///|
fn classify_word(word : StringView) -> @syntax.HighlightTag {
  match word {
    "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "continue"
    | "debugger"
    | "default"
    | "delete"
    | "do"
    | "else"
    | "export"
    | "extends"
    | "finally"
    | "for"
    | "from"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "let"
    | "new"
    | "of"
    | "return"
    | "static"
    | "super"
    | "switch"
    | "throw"
    | "try"
    | "typeof"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield"
    | "async"
    | "await"
    | "get"
    | "set" => Keyword
    "true" | "false" | "null" | "undefined" | "NaN" | "Infinity" => Constant
    "this" => Variable
    _ => if @syntax.is_capitalized(word) { Type } else { Identifier }
  }
}
