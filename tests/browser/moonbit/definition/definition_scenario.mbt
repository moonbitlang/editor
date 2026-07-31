// Real-Chromium fixture for goto-definition, definition-link, Peek Definition,
// and provider-backed Peek References. Playwright drives trusted mouse,
// modifier, wheel, and keyboard events; this MoonBit side supplies only the
// public Viewer, isolated language providers, and deterministic readback of
// public editor state.

///|
priv struct BrowserDefinitionProvider {
  calls : Ref[Int]
  location : @language.Location
  alternate_location : @language.Location?
  multiple : Ref[Bool]
  reference_line : Int
}

///|
impl @language.DefinitionProvider for BrowserDefinitionProvider with fn provide_definition(
  self,
  model,
  position,
  _token,
) {
  self.calls.val += 1
  if model.uri.to_string() == self.location.uri.to_string() &&
    position.line_number == self.reference_line &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    match (self.multiple.val, self.alternate_location) {
      (true, Some(alternate)) => [self.location, alternate]
      _ => [self.location]
    }
  } else {
    []
  }
}

///|
priv struct BrowserReferencesProvider {
  calls : Ref[Int]
  code_uri : @base_common.Uri
  markdown_uri : @base_common.Uri
}

///|
impl @language.ReferencesProvider for BrowserReferencesProvider with fn provide_references(
  self,
  model,
  position,
  _token,
) {
  self.calls.val += 1
  if model.uri.to_string() == self.code_uri.to_string() &&
    position.line_number == 2 &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    [
      { uri: self.code_uri, range: Range(1, 5, 1, 21) },
      { uri: self.code_uri, range: Range(2, 11, 2, 27) },
    ]
  } else if model.uri.to_string() == self.markdown_uri.to_string() &&
    position.line_number == 2 &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    [
      { uri: self.markdown_uri, range: Range(2, 11, 2, 27) },
      {
        uri: self.markdown_uri,
        range: Range(
          markdown_definition_line(),
          5,
          markdown_definition_line(),
          21,
        ),
      },
    ]
  } else {
    []
  }
}

///|
fn definition_reference_start_column() -> Int {
  11
}

///|
fn definition_reference_end_column() -> Int {
  27
}

///|
fn definition_source() -> String {
  let lines : Array[String] = [
    "let definition_alpha = 1", "let use = definition_alpha",
  ]
  for index in 3..<=90 {
    lines.push("filler_line_\{index}")
  }
  lines.join("\n")
}

///|
fn markdown_definition_source() -> String {
  let lines = [
    "```mbt check", "let use = definition_alpha", "```", "", "```mbt", "let ordinary = definition_alpha",
    "```", "",
  ]
  for index in 1..<=40 {
    lines.push("Markdown projection filler \{index}.")
  }
  lines.append(["", "```mbt check", "let definition_alpha = 1", "```"])
  lines.join("\n")
}

///|
fn markdown_definition_line() -> Int {
  51
}

///|
fn definition_state_json(
  viewer : @viewer.Viewer,
  provider_calls : Ref[Int],
  references_provider_calls : Ref[Int],
) -> String {
  let (line, column) = match viewer.get_position() {
    Some(position) => (position.line_number, position.column)
    None => (-1, -1)
  }
  let (anchor_line, anchor_column, active_line, active_column) = match
    viewer.get_selection() {
    Some(selection) => {
      let anchor = selection.get_selection_start()
      let active = selection.get_position()
      (anchor.line_number, anchor.column, active.line_number, active.column)
    }
    None => (-1, -1, -1, -1)
  }
  Json::object({
    "position": Json::object({
      "line": line.to_json(),
      "column": column.to_json(),
    }),
    "selection": Json::object({
      "anchorLine": anchor_line.to_json(),
      "anchorColumn": anchor_column.to_json(),
      "activeLine": active_line.to_json(),
      "activeColumn": active_column.to_json(),
    }),
    "providerCalls": provider_calls.val.to_json(),
    "referencesProviderCalls": references_provider_calls.val.to_json(),
    "scrollTop": viewer.get_scroll_top().to_json(),
    "scrollHeight": viewer.get_scroll_height().to_json(),
    "hasTextFocus": viewer.has_text_focus().to_json(),
  }).stringify()
}

///|
fn run_definition_browser_test() -> Unit {
  let ctx = @support.BrowserTestContext("definition")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell definition-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;padding:16px;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host definition-host")
  host.set_attribute("style", "height:360px;width:760px;")
  let markdown_host = document.create_element("div")
  markdown_host.set_attribute("class", "viewer-host definition-markdown-host")
  markdown_host.set_attribute(
    "style", "height:360px;width:760px;margin-top:16px;",
  )
  shell.append_child(host.as_node())
  shell.append_child(markdown_host.as_node())
  app.append_child(shell.as_node())

  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/definition-fixture.mbt",
  )
  let model = @model.TextModel(
    uri,
    "definition-fixture.mbt",
    "moonbit",
    1,
    "definition-rev-1",
    definition_source(),
  )
  let provider_calls = Ref(0)
  let provider_multiple = Ref(false)
  let provider = BrowserDefinitionProvider::{
    calls: provider_calls,
    location: { uri, range: Range(1, 5, 1, 21) },
    alternate_location: Some({ uri, range: Range(3, 1, 3, 14) }),
    multiple: provider_multiple,
    reference_line: 2,
  }
  let markdown_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/definition-fixture.mbt.md",
  )
  let markdown_model = @model.TextModel(
    markdown_uri,
    "definition-fixture.mbt.md",
    "moonbit",
    1,
    "definition-markdown-rev-1",
    markdown_definition_source(),
  )
  let markdown_provider_calls = Ref(0)
  let markdown_provider_multiple = Ref(false)
  let markdown_provider = BrowserDefinitionProvider::{
    calls: markdown_provider_calls,
    location: {
      uri: markdown_uri,
      range: Range(
        markdown_definition_line(),
        5,
        markdown_definition_line(),
        21,
      ),
    },
    alternate_location: None,
    multiple: markdown_provider_multiple,
    reference_line: 2,
  }
  let references_provider_calls = Ref(0)
  let references_provider = BrowserReferencesProvider::{
    calls: references_provider_calls,
    code_uri: uri,
    markdown_uri,
  }
  let languages = @languages.Languages()
  languages.register_definition_provider(LanguageId("moonbit"), provider)
  |> ignore
  languages.register_definition_provider(
    LanguageId("moonbit"),
    markdown_provider,
  )
  |> ignore
  languages.register_references_provider(
    LanguageId("moonbit"),
    references_provider,
  )
  |> ignore
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    log_service=log_handle,
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(
      soft_wrap=false,
      smooth_scrolling=false,
      folding=false,
    ),
  )
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 1))
  viewer.handle_initialized()
  let markdown_viewer = @viewer.Viewer::create(
    markdown_host,
    services~,
    options=ViewerOptions(
      soft_wrap=false,
      smooth_scrolling=false,
      folding=false,
    ),
  )
  markdown_viewer.set_model(Some(markdown_model))
  markdown_viewer.handle_initialized()
  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("mounted Viewer did not expose its root")
    ctx.finish()
    return
  }
  guard markdown_viewer.get_dom_node() is Some(markdown_root) else {
    ctx.fail("mounted Markdown Viewer did not expose its root")
    ctx.finish()
    return
  }
  install_definition_controls(
    root,
    markdown_root,
    () => {
      definition_state_json(viewer, provider_calls, references_provider_calls)
    },
    () => {
      definition_state_json(
        markdown_viewer, markdown_provider_calls, references_provider_calls,
      )
    },
    () => viewer.set_scroll_top(0.0),
    () => viewer.focus(),
    () => markdown_viewer.focus(),
    () => viewer.set_selection(Selection(Position(2, 11), Position(2, 27))),
    () => viewer.layout(),
    () => provider_multiple.val = true,
    () => {
      markdown_model.set_value(
        (
          $|\{markdown_definition_source()}
          $|
          $|Projection generation changed.
        ),
      )
    },
  )
  wait_for_definition_fixture(ctx, 100)
}

///|
fn wait_for_definition_fixture(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  if @support.query_text(".definition-host").contains("definition_alpha") &&
    @support.query_text(".definition-markdown-host").contains(
      "definition_alpha",
    ) {
    ctx.assert_true(
      @support.query_count(".definition-host > .monaco-editor.readonly-editor") ==
      1,
      "expected exactly one rendered outer Viewer",
    )
    ctx.finish()
    return
  }
  if remaining <= 0 {
    ctx.fail("timed out waiting for definition fixture render")
    ctx.finish()
    return
  }
  @support.set_timeout(
    () => wait_for_definition_fixture(ctx, remaining - 1),
    30,
  )
}

///|
extern "js" fn install_definition_controls(
  outer_root : @rdom.Element,
  markdown_root : @rdom.Element,
  state_json : () -> String,
  markdown_state_json : () -> String,
  reset_scroll : () -> Unit,
  focus_outer : () -> Unit,
  focus_markdown : () -> Unit,
  select_reference : () -> Unit,
  layout_outer : () -> Unit,
  enable_multiple_definitions : () -> Unit,
  replace_markdown_source : () -> Unit,
) -> Unit =
  #| (
  #|   outerRoot,
  #|   markdownRoot,
  #|   stateJson,
  #|   markdownStateJson,
  #|   resetScroll,
  #|   focusOuter,
  #|   focusMarkdown,
  #|   selectReference,
  #|   layoutOuter,
  #|   enableMultipleDefinitions,
  #|   replaceMarkdownSource,
  #| ) => {
  #|   globalThis.__definitionControls = {
  #|     outerRoot,
  #|     markdownRoot,
  #|     state: () => JSON.parse(stateJson()),
  #|     markdown_state: () => JSON.parse(markdownStateJson()),
  #|     reset_scroll: resetScroll,
  #|     focus_outer: focusOuter,
  #|     focus_markdown: focusMarkdown,
  #|     select_reference: selectReference,
  #|     layout_outer: layoutOuter,
  #|     enable_multiple_definitions: enableMultipleDefinitions,
  #|     replace_markdown_source: replaceMarkdownSource,
  #|   };
  #| }
