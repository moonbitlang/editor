///|
test "safe conversion keeps raw HTML inert and removes unsafe link schemes" {
  let rendered = render_markdown(
    "<img src=x onerror=alert(1)> [unsafe](javascript:alert(1)) **safe**",
  )
  assert_false(rendered.html.contains("<img"))
  assert_false(rendered.html.contains("onerror"))
  assert_false(rendered.html.contains("javascript:"))
  assert_true(rendered.html.contains("<strong>safe</strong>"))
  assert_false(rendered.has_code_block)
}

///|
test "conversion failure becomes one escaped plaintext paragraph" {
  let rendered = markdown_conversion_result("<unsafe> & plain", Ref(true), () => {
    raise @cmark_renderer.RenderError("forced conversion failure")
  })
  assert_eq(rendered.html, "<p>&lt;unsafe&gt; &amp; plain</p>\n")
  assert_false(rendered.has_code_block)
}

///|
test "code override receives MoonBit DTO, fence language, and active language" {
  let observed_code = Ref("")
  let observed_fence = Ref("")
  let observed_active = Ref("")
  let rendered = render_markdown(
    "```mbt extra\nlet answer = 42\n```",
    language_id="moonbit",
    code_block_renderer=fn(block, active_language_id) {
      observed_code.val = block.code
      observed_fence.val = block.language_id.unwrap_or("")
      observed_active.val = active_language_id.unwrap_or("")
      "<pre data-rendered=\"yes\">override</pre>"
    },
  )
  assert_eq(observed_code.val, "let answer = 42\n")
  assert_eq(observed_fence.val, "mbt")
  assert_eq(observed_active.val, "moonbit")
  assert_eq(rendered.html, "<pre data-rendered=\"yes\">override</pre>")
  assert_true(rendered.has_code_block)
}

///|
test "default code rendering still reports code-block fact" {
  let rendered = render_markdown("    plain code")
  assert_true(rendered.html.contains("<pre><code>plain code\n</code></pre>"))
  assert_true(rendered.has_code_block)
}
