///|
fn register_shared_markdown_test_tokenizer() -> Unit {
  @syntax.tokenization_registry.register("moonbit", @syntax.PlainTokenizer())
  |> ignore
}

///|
test "shared tokenized code override emits editor classes and threads active language" {
  register_shared_markdown_test_tokenizer()
  let fenced = render_markdown(
    "```mbt\nlet answer = 42\n```",
    language_id="plaintext",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(fenced.has_code_block)
  assert_true(fenced.html.contains("monaco-tokenized-source"))
  assert_true(fenced.html.contains("class=\"mtk3\""))

  let active = render_markdown(
    "```\nfn active() -> Unit {}\n```",
    language_id="moonbit",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(active.html.contains("monaco-tokenized-source"))
  assert_true(active.html.contains("class=\"mtk3\""))
}

///|
test "shared tokenized code override keeps unknown-language source as safe default tokens" {
  let rendered = render_markdown(
    "```unknown\nnot really code\n```",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(rendered.has_code_block)
  assert_true(rendered.html.contains("monaco-tokenized-source"))
  assert_true(rendered.html.contains("class=\"mtk1\""))
  assert_true(rendered.html.contains("not really code"))
}
