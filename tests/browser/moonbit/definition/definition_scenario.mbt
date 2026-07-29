// Real-Chromium fixture for goto-definition, definition-link, and Peek
// Definition. Playwright drives trusted mouse, modifier, wheel, and keyboard
// events; this MoonBit side supplies only the public Viewer, an isolated
// definition provider, and deterministic readback of public editor state.

///|
priv struct BrowserDefinitionProvider {
  calls : Ref[Int]
  location : @language.Location
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
    position.line_number == 2 &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    [self.location]
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
fn definition_state_json(
  viewer : @viewer.Viewer,
  provider_calls : Ref[Int],
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
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())

  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/definition-fixture.mbt",
  )
  let model = TextModel(
    uri,
    "definition-fixture.mbt",
    "moonbit",
    1,
    "definition-rev-1",
    definition_source(),
  )
  let provider_calls = Ref(0)
  let provider = BrowserDefinitionProvider::{
    calls: provider_calls,
    location: { uri, range: Range(1, 5, 1, 21) },
  }
  let languages = @languages.Languages()
  languages.register_definition_provider(
    LanguageSelector::LanguageId("moonbit"),
    provider,
  )
  |> ignore
  let log_service = LogService()
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
  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("mounted Viewer did not expose its root")
    ctx.finish()
    return
  }
  install_definition_controls(
    root,
    () => definition_state_json(viewer, provider_calls),
    () => viewer.set_scroll_top(0.0),
    () => viewer.focus(),
  )
  wait_for_definition_fixture(ctx, 100)
}

///|
fn wait_for_definition_fixture(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  if @support.query_text(".definition-host").contains("definition_alpha") {
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
  state_json : () -> String,
  reset_scroll : () -> Unit,
  focus_outer : () -> Unit,
) -> Unit =
  #| (outerRoot, stateJson, resetScroll, focusOuter) => {
  #|   globalThis.__definitionControls = {
  #|     outerRoot,
  #|     state: () => JSON.parse(stateJson()),
  #|     reset_scroll: resetScroll,
  #|     focus_outer: focusOuter,
  #|   };
  #| }
