///|
fn markdown_document_source() -> String {
  (
    #|# Readonly Markdown document
    #|
    #|The original source model remains the document of record.
    #|
    #|- [ ] this checkbox stays readonly
    #|
    #|```mbt check
    #|pub fn markdown_answer() -> Int {
    #|  42
    #|}
    #|```
  )
}

///|
fn markdown_document_replacement_source() -> String {
  (
    #|# Replaced Markdown document
    #|
    #|The article target is reused while this projection is replaced.
    #|
    #|```mbt check trailing
    #|pub fn replacement_answer() -> Int {
    #|  7
    #|}
    #|```
  )
}

///|
fn run_markdown_document_test() -> Unit {
  let ctx = @support.BrowserTestContext("markdown_document")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell markdown-document-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host markdown-document-host")
  host.set_attribute("style", "height:220px;width:720px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())

  let token_registration = @syntax.tokenization_registry.register(
    "moonbit",
    @lang_moonbit.MoonbitTokenizer(),
  )
  let markdown_model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="component",
      path="/literate.mbt.md",
    ),
    "literate.mbt.md",
    "moonbit",
    1,
    "markdown-document-rev-1",
    markdown_document_source(),
  )
  let code_model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="component",
      path="/ordinary.mbt",
    ),
    "ordinary.mbt",
    "moonbit",
    1,
    "markdown-document-code-rev-1",
    "pub fn ordinary_code() -> Int { 1 }",
  )
  let viewer = @viewer.Viewer::create(host, options=ViewerOptions(theme="dark"))
  viewer.set_model(Some(markdown_model))
  viewer.handle_initialized()
  install_markdown_document_controls(
    () => markdown_model.get_value(),
    () => viewer.set_value(markdown_document_replacement_source()),
    theme => viewer.update_options(viewer.get_options().with_theme(theme)),
    () => viewer.set_model(Some(code_model)),
    () => viewer.set_model(Some(markdown_model)),
    top => viewer.set_scroll_top(top),
    width => {
      host.set_attribute("style", "height:220px;width:\{width}px;")
      viewer.layout()
    },
    () => {
      viewer.dispose()
      markdown_model.dispose()
      code_model.dispose()
      token_registration.dispose()
    },
  )
  poll_markdown_document_ready(ctx, markdown_model, 100)
}

///|
fn poll_markdown_document_ready(
  ctx : @support.BrowserTestContext,
  model : @model.TextModel,
  remaining : Int,
) -> Unit {
  let root_count = @support.query_count(
    ".markdown-document-host > .moonbit-viewer-markdown-document",
  )
  let code_blocks = @support.query_count(
    ".markdown-document-host [data-markdown-code-block]",
  )
  let keyword_tokens = @support.query_count(
    ".markdown-document-host .moonbit-viewer-markdown-code-block .mtk3",
  )
  if root_count == 1 && code_blocks == 1 && keyword_tokens > 0 {
    ctx.assert_true(
      @support.query_count(".markdown-document-host > .monaco-editor") == 0,
      "Markdown presentation retained a hidden code-editor root",
    )
    ctx.assert_true(
      @support.query_attribute(
        ".markdown-document-host [data-markdown-code-block]", "data-markdown-semantic",
      ) ==
      "moonbit-check",
      "compiler-compatible .mbt.md fence was not classified semantically",
    )
    ctx.assert_true(
      @support.query_attribute(
        ".markdown-document-host > .moonbit-viewer-markdown-document", "data-source-uri",
      ) ==
      model.uri.to_string(),
      "Markdown root lost the original source URI",
    )
    ctx.assert_true(
      @support.query_count(
        ".markdown-document-host .moonbit-viewer-markdown-document-article input[disabled]",
      ) ==
      1,
      "Markdown checkbox was not rendered readonly",
    )
    ctx.metric_int("rootCount", root_count)
    ctx.metric_int("codeBlocks", code_blocks)
    ctx.metric_int("keywordTokens", keyword_tokens)
    ctx.metric_string(
      "sourceUri",
      @support.query_attribute(
        ".markdown-document-host > .moonbit-viewer-markdown-document", "data-source-uri",
      ),
    )
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail(
      "timed out waiting for Markdown document render: roots=\{root_count}, blocks=\{code_blocks}, tokens=\{keyword_tokens}",
    )
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_markdown_document_ready(ctx, model, remaining - 1),
      25,
    )
  }
}

///|
extern "js" fn install_markdown_document_controls(
  get_model_value : () -> String,
  replace_source : () -> Unit,
  update_theme : (String) -> Unit,
  show_code : () -> Unit,
  show_markdown : () -> Unit,
  set_scroll_top : (Double) -> Unit,
  resize_host : (Double) -> Unit,
  dispose : () -> Unit,
) -> Unit =
  #| (
  #|   getModelValue,
  #|   replaceSource,
  #|   updateTheme,
  #|   showCode,
  #|   showMarkdown,
  #|   setScrollTop,
  #|   resizeHost,
  #|   dispose,
  #| ) => {
  #|   globalThis.__markdownDocumentControls = {
  #|     getModelValue,
  #|     replaceSource,
  #|     updateTheme,
  #|     showCode,
  #|     showMarkdown,
  #|     setScrollTop,
  #|     resizeHost,
  #|     dispose,
  #|   };
  #| }
