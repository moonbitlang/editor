// Browser test for the Stage-1 `renderWhitespace` / `renderControlCharacters`
// option feed (plan: monaco-render-whitespace-control-options-port.md). It
// mounts a viewer with `ViewerOptions(render_whitespace=All,
// render_control_characters=true)` over a line that carries leading/trailing
// whitespace and a bidi control character, then asserts the inline renderer
// (already ported in `view_line_renderer`) became reachable through the real
// DOM path: `.mtkw` whitespace glyph spans appear and the control character
// renders as a `[U+202E]` placeholder. This is the end-to-end proof that an
// embedder can now turn either option on via `ViewerOptions` — the gap this
// port closes.

///|
/// The fixture line: two leading spaces, `ab`, U+202E (RIGHT-TO-LEFT OVERRIDE,
/// a `[U+…]`-class control character), `cd`, two trailing spaces. `All` mode
/// renders every whitespace run; the control character trips the renderer's
/// `render_control_characters && !is_basic_ascii` gate (U+202E > 127).
fn whitespace_source_text() -> String {
  "  ab\u{202E}cd  "
}

///|
fn run_whitespace_test() -> Unit {
  let ctx = @support.BrowserTestContext("whitespace")
  let done = Ref(false)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/whitespace.txt",
  )
  let model = @model.TextModel(
    uri,
    "whitespace.txt",
    "plaintext",
    1,
    "whitespace-rev-1",
    whitespace_source_text(),
  )
  match mount_host() {
    Some(host) => {
      let viewer = @viewer.Viewer::create(
        host,
        options=ViewerOptions(
          soft_wrap=false,
          render_whitespace=All,
          render_control_characters=true,
          placeholder="Loading whitespace fixture...",
        ),
      )
      viewer.set_model(Some(model))
      viewer.handle_initialized()
      @support.set_timeout(() => poll_whitespace(ctx, done, 100), 50)
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
fn poll_whitespace(
  ctx : @support.BrowserTestContext,
  done : Ref[Bool],
  remaining : Int,
) -> Unit {
  if done.val {
    return
  }
  if @support.query_count(".view-line") > 0 {
    assert_whitespace(ctx)
    done.val = true
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for the whitespace line to render")
    done.val = true
    ctx.finish()
  } else {
    @support.set_timeout(() => poll_whitespace(ctx, done, remaining - 1), 30)
  }
}

///|
fn assert_whitespace(ctx : @support.BrowserTestContext) -> Unit {
  // (1) `render_whitespace=All` materializes whitespace glyph spans. Monospace
  // optimizations are on by default, so they carry the `mtkw` class.
  let whitespace_spans = @support.query_count(".view-line .mtkw")
  ctx.assert_true(
    whitespace_spans > 0,
    "no .mtkw whitespace spans rendered with render_whitespace=All",
  )

  // (2) `render_control_characters=true` substitutes the U+202E control
  // character with a `[U+202E]` placeholder in an `.mtkcontrol` span.
  let control_spans = @support.query_count(".view-line .mtkcontrol")
  ctx.assert_true(
    control_spans > 0,
    "no .mtkcontrol span rendered with render_control_characters=true",
  )
  let line_text = @support.query_text(".view-line")
  ctx.assert_true(
    line_text.contains("[U+202E]"),
    "control-character placeholder [U+202E] not present (got: \{line_text})",
  )
  ctx.metric_int("whitespaceSpans", whitespace_spans)
  ctx.metric_int("controlSpans", control_spans)
}

///|
fn mount_host() -> @rdom.Element? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      host.set_attribute("style", "height:120px;width:320px;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}
