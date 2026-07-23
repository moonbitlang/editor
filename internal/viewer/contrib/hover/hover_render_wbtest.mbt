///|
/// Registers the fallback lexer for the `moonbit` fences (idempotent; the
/// global registry lives for the test binary).
fn register_hover_test_tokenizer() -> Unit {
  @syntax.tokenization_registry.register("moonbit", @syntax.PlainTokenizer())
  |> ignore
}

///|
fn render_hover_markdown_for_test(
  markdown : String,
) -> @markdown.MarkdownRenderFact {
  @markdown.render_markdown(
    markdown,
    language_id="moonbit",
    code_block_renderer=render_hover_code_block,
  )
}

///|
test "hover markdown delegates safe conversion to the shared core" {
  let rendered = render_hover_markdown_for_test(
    "<img src=x onerror=\"globalThis.__hoverUnsafe=1\"> [bad](javascript:alert(1)) **safe**",
  )
  assert_false(rendered.html.contains("<img"))
  assert_false(rendered.html.contains("onerror"))
  assert_false(rendered.html.contains("javascript:"))
  assert_true(rendered.html.contains("<strong>safe</strong>"))
  assert_false(rendered.has_code_block)
}

///|
test "hover fenced code renders through viewer token classes and reports the fact" {
  register_hover_test_tokenizer()
  let moonbit = render_hover_markdown_for_test(
    "```moonbit\nfn rendered() -> Unit {}\n```",
  )
  assert_true(moonbit.has_code_block)
  assert_true(moonbit.html.contains("monaco-tokenized-source"))
  assert_true(moonbit.html.contains("mtk3")) // keyword color id
  assert_true(moonbit.html.contains("fn"))

  let mbt_alias = render_hover_markdown_for_test("```mbt\nlet answer = 42\n```")
  assert_true(mbt_alias.has_code_block)
  assert_true(mbt_alias.html.contains("monaco-tokenized-source"))
  assert_true(mbt_alias.html.contains("mtk3")) // keyword color id
}

///|
test "unlabelled hover code uses the active model language" {
  register_hover_test_tokenizer()
  let rendered = render_hover_markdown_for_test(
    "```\nfn active_language() -> Unit {}\n```",
  )
  assert_true(rendered.has_code_block)
  assert_true(rendered.html.contains("monaco-tokenized-source"))
  assert_true(rendered.html.contains("mtk3"))
}

///|
test "hover unknown fenced code keeps content as default plain text" {
  register_hover_test_tokenizer()
  let rendered = render_hover_markdown_for_test(
    "```unknown\nnot really code\n```",
  )
  assert_true(rendered.has_code_block)
  assert_true(rendered.html.contains("monaco-tokenized-source"))
  assert_true(rendered.html.contains("not"))
  assert_true(rendered.html.contains("really"))
  assert_true(rendered.html.contains("code"))
  // No tokenizer for `unknown`: the whole line is one default-metadata token
  // (`mtk1`), never the variable/identifier color (`mtk4`).
  assert_true(rendered.html.contains("class=\"mtk1\""))
  assert_false(rendered.html.contains("mtk4"))
}
