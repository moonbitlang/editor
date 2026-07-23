///|
test "exact diago fence renders wrapped SVG before the caller override" {
  let override_called = Ref(false)
  let rendered = render_markdown("```diago extra\na -> b\n```", code_block_renderer=fn(
    _,
    _,
  ) {
    override_called.val = true
    "<pre data-fallback=\"caller\">fallback</pre>"
  })
  assert_false(override_called.val)
  assert_true(
    rendered.html.contains(
      "class=\"moonbit-viewer-markdown-diagram\" data-diagram-language=\"diago\"",
    ),
  )
  assert_true(rendered.html.contains("<svg"))
  assert_false(rendered.html.contains("data-fallback=\"caller\""))
  assert_true(rendered.has_code_block)
}

///|
test "invalid diago falls through to the supplied tokenized renderer" {
  let rendered = render_markdown(
    "```diago\na ->\n```",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(rendered.html.contains("monaco-tokenized-source"))
  assert_true(rendered.html.contains("a"))
  assert_false(rendered.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(rendered.has_code_block)
}

///|
test "invalid diago without an override falls through to cmark code HTML" {
  let rendered = render_markdown("```diago\na ->\n```")
  assert_true(rendered.html.contains("<pre><code class=\"language-diago\">"))
  assert_true(rendered.html.contains("a -&gt;"))
  assert_false(rendered.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(rendered.has_code_block)
}

///|
test "unsupported and differently cased fences remain ordinary cmark code" {
  let unknown = render_markdown("```graph\na -> b\n```")
  assert_true(unknown.html.contains("<pre><code class=\"language-graph\">"))
  assert_false(unknown.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(unknown.has_code_block)

  let uml = render_markdown("```uml\nAlice -> Bob\n```")
  assert_true(uml.html.contains("<pre><code class=\"language-uml\">"))
  assert_false(uml.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(uml.has_code_block)

  let plantuml = render_markdown("```plantuml\nAlice -> Bob\n```")
  assert_true(plantuml.html.contains("<pre><code class=\"language-plantuml\">"))
  assert_false(plantuml.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(plantuml.has_code_block)

  let differently_cased = render_markdown("```Diago\na -> b\n```")
  assert_true(
    differently_cased.html.contains("<pre><code class=\"language-Diago\">"),
  )
  assert_false(
    differently_cased.html.contains("moonbit-viewer-markdown-diagram"),
  )
  assert_true(differently_cased.has_code_block)
}

///|
test "active diago language does not turn unlabelled or indented code into diagrams" {
  let unlabelled = render_markdown(
    "```\na -> b\n```",
    language_id="diago",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(unlabelled.html.contains("monaco-tokenized-source"))
  assert_false(unlabelled.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(unlabelled.has_code_block)

  let indented = render_markdown(
    "    a -> b",
    language_id="diago",
    code_block_renderer=render_tokenized_code_block,
  )
  assert_true(indented.html.contains("monaco-tokenized-source"))
  assert_false(indented.html.contains("moonbit-viewer-markdown-diagram"))
  assert_true(indented.has_code_block)
}
