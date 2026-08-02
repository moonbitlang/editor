///|
/// Walks one JSON line through the public lexer -> model encoder -> view-token
/// -> HTML pipeline. Each snapshot uses a list comprehension so the opaque
/// token stores are shown through the same public reads used by consumers.
test "JSON tokens flow from lexer spans to rendered HTML" {
  let source = "{ \"answer\": 42 }"
  let tokenizer : &@syntax.LineTokenizer = @lang_json.JsonTokenizer()
  let (lexer_tokens, end_state) = tokenizer.tokenize_line(
    source,
    tokenizer.initial_state(),
  )
  // Stage 1: the lexer emits highlighted spans and leaves whitespace as gaps.
  debug_inspect(
    (
      [
        for token in lexer_tokens => {
          (
            source[token.start:token.end].to_owned(),
            token.start,
            token.end,
            token.tag,
          )
        }
      ],
      end_state,
    ),
    content=(
      #|(
      #|  [
      #|    ("{", 0, 1, Delimiter),
      #|    ("\"answer\"", 2, 10, Attribute),
      #|    (":", 10, 11, Delimiter),
      #|    ("42", 12, 14, Number),
      #|    ("}", 15, 16, Delimiter),
      #|  ],
      #|  TokenizerState("n"),
      #|)
    ),
  )

  let line_tokens = @model.line_tokens_from_lexer_tokens(
    source, lexer_tokens, @services.language_id_codec,
  )
  // Stage 2: the model encoder fills gaps and assigns renderer class metadata.
  debug_inspect(
    [
      for i in 0..<line_tokens.get_count() => {
        let start = line_tokens.get_start_offset(i)
        let end = if i + 1 < line_tokens.get_count() {
          line_tokens.get_start_offset(i + 1)
        } else {
          source.length()
        }
        (
          source[start:end].to_owned(),
          start,
          end,
          @tokens.TokenMetadata::get_class_name(line_tokens.get_metadata(i)),
        )
      }
    ],
    content=(
      #|[
      #|  ("{", 0, 1, "mtk8"),
      #|  (" ", 1, 2, "mtk1"),
      #|  ("\"answer\"", 2, 10, "mtk4"),
      #|  (":", 10, 11, "mtk8"),
      #|  (" ", 11, 12, "mtk1"),
      #|  ("42", 12, 14, "mtk6"),
      #|  (" ", 14, 15, "mtk1"),
      #|  ("}", 15, 16, "mtk8"),
      #|]
    ),
  )

  let view_tokens = line_tokens.inflate()
  // Stage 3: renderers consume the full-or-sliced ViewLineTokens interface.
  debug_inspect(
    [
      for i in 0..<view_tokens.get_count() => {
        (
          view_tokens.get_token_text(i),
          view_tokens.get_end_offset(i),
          view_tokens.get_class_name(i),
        )
      }
    ],
    content=(
      #|[
      #|  ("{", 1, "mtk8"),
      #|  (" ", 2, "mtk1"),
      #|  ("\"answer\"", 10, "mtk4"),
      #|  (":", 11, "mtk8"),
      #|  (" ", 12, "mtk1"),
      #|  ("42", 14, "mtk6"),
      #|  (" ", 15, "mtk1"),
      #|  ("}", 16, "mtk8"),
      #|]
    ),
  )

  // Stage 4: the HTML renderer resolves token classes through the color map.
  debug_inspect(
    @languages.tokenize_line_to_html(
      source,
      view_tokens,
      @model.default_token_color_map(),
      0,
      source.length(),
      4,
      true,
    ),
    content=(
      #|"<div><span style=\"color: var(--vscode-token-punctuation);\">{</span><span style=\"color: var(--vscode-editor-foreground);\"> </span><span style=\"color: var(--vscode-token-variable);\">\"answer\"</span><span style=\"color: var(--vscode-token-punctuation);\">:</span><span style=\"color: var(--vscode-editor-foreground);\"> </span><span style=\"color: var(--vscode-token-number);\">42</span><span style=\"color: var(--vscode-editor-foreground);\"> </span><span style=\"color: var(--vscode-token-punctuation);\">}</span></div>"
    ),
  )
}
