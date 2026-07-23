///|
/// Golden token-stream rendering: one `start-end tag text` line per token in
/// document offsets — lines split on `\n`, lexer state threaded line to line
/// exactly as the tokenization part's whole-document sweep does.
fn render_tokens(source : String) -> String {
  let tokenizer : &@syntax.LineTokenizer = @lang_json.JsonTokenizer()
  let rendered : Array[String] = []
  let mut state = tokenizer.initial_state()
  let mut line_start = 0
  for line in split_lines(source) {
    let (tokens, next_state) = tokenizer.tokenize_line(line, state)
    for token in tokens {
      let text = line[token.start:token.end].to_owned()
      rendered.push(
        "\{line_start + token.start}-\{line_start + token.end} \{token.tag} \{text}",
      )
    }
    state = next_state
    line_start += line.length() + 1
  }
  rendered.join("\n")
}

///|
/// Splits on `\n` only, matching the snapshot line table the part consumes.
fn split_lines(source : String) -> Array[String] {
  let lines : Array[String] = []
  let mut start = 0
  for i in 0..<source.length() {
    if source[i] == '\n' {
      lines.push(source[start:i].to_owned())
      start = i + 1
    }
  }
  lines.push(source[start:source.length()].to_owned())
  lines
}

///|
test "object with property names values and literals" {
  let source =
    #|{
    #|  "name": "fixture",
    #|  "size": -12.5e2,
    #|  "ok": true,
    #|  "tags": ["a", "b"],
    #|  "next": null
    #|}
  inspect(
    render_tokens(source),
    content=(
      #|0-1 Delimiter {
      #|4-10 Attribute "name"
      #|10-11 Delimiter :
      #|12-21 String "fixture"
      #|21-22 Delimiter ,
      #|25-31 Attribute "size"
      #|31-32 Delimiter :
      #|33-40 Number -12.5e2
      #|40-41 Delimiter ,
      #|44-48 Attribute "ok"
      #|48-49 Delimiter :
      #|50-54 Constant true
      #|54-55 Delimiter ,
      #|58-64 Attribute "tags"
      #|64-65 Delimiter :
      #|66-67 Delimiter [
      #|67-70 String "a"
      #|70-71 Delimiter ,
      #|72-75 String "b"
      #|75-76 Delimiter ]
      #|76-77 Delimiter ,
      #|80-86 Attribute "next"
      #|86-87 Delimiter :
      #|88-92 Constant null
      #|93-94 Delimiter }
    ),
  )
}

///|
test "jsonc comments carry block state across lines" {
  let source =
    #|// heading
    #|{ /* multi
    #|line */ "key": 1 }
  inspect(
    render_tokens(source),
    content=(
      #|0-10 Comment // heading
      #|11-12 Delimiter {
      #|13-15 Comment /*
      #|15-21 Comment  multi
      #|22-27 Comment line 
      #|27-29 Comment */
      #|30-35 Attribute "key"
      #|35-36 Delimiter :
      #|37-38 Number 1
      #|39-40 Delimiter }
    ),
  )
}

///|
test "block comment state round-trips through TokenizerState" {
  let lexer : &@syntax.LineTokenizer = @lang_json.JsonTokenizer()
  let (_, open_state) = lexer.tokenize_line("{ /* open", lexer.initial_state())
  assert_true(open_state == TokenizerState("c"))
  let (_, closed_state) = lexer.tokenize_line("still */ }", open_state)
  assert_true(closed_state == lexer.initial_state())
}

///|
test "bare words are invalid outside strings" {
  inspect(
    render_tokens("{ bad: 1 }"),
    content=(
      #|0-1 Delimiter {
      #|2-5 Invalid bad
      #|5-6 Delimiter :
      #|7-8 Number 1
      #|9-10 Delimiter }
    ),
  )
}
