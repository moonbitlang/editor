// Fixed-font Chromium geometry fixture for the browser-geometry parity plan.
// Both fonts are tiny test-only TTFs embedded below as data URLs. Every glyph
// used by the fixture is owned by those fonts, so no host font or network
// lookup can affect the numeric assertions in Playwright.

///|
priv struct BrowserGeometryHoverProvider {}

///|
impl @language.HoverProvider for BrowserGeometryHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  match model.snapshot.text.find("anchor") {
    Some(start) =>
      if offset >= start && offset < start + "anchor".length() {
        Some({
          range: model.snapshot.range_of(
            OffsetRange(start, start + "anchor".length()),
          ),
          contents: [
            Markdown("[geometry focus target](https://example.invalid/)"),
          ],
        })
      } else {
        None
      }
    None => None
  }
}

///|
priv struct BrowserGeometryFixture {
  name : String
  viewer : @viewer.Viewer
  model : @model.TextModel
  view_line_count : Ref[Int]
  mut injection_ids : Array[String]
}

///|
/// Test-only content widget used to exercise the real ContentWidgets port in
/// a same-origin iframe whose owner window deliberately disagrees with the
/// top-level page.
priv struct BrowserIframeContentWidget {
  id : String
  node : @rdom.Element
  allow_overflow : Bool
  mut preference : Array[@view.ContentWidgetPositionPreference]
  mut after_position : String
  mut after_top : Double
  mut after_left : Double
}

///|
fn BrowserIframeContentWidget::content_widget_handle(
  self : BrowserIframeContentWidget,
) -> @view.ContentWidgetHandle {
  ContentWidgetHandle(
    () => self.id,
    () => self.node,
    () => {
      Some({
        position: Some(Position(1, 1)),
        secondary_position: None,
        preference: Some(self.preference),
        position_affinity: None,
      })
    },
    allow_editor_overflow=self.allow_overflow,
    before_render=() => Some({ width: 80.0, height: 30.0 }),
    after_render=(position, coordinate) => {
      self.after_position = match position {
        Some(Above) => "above"
        Some(Below) => "below"
        Some(Exact) => "exact"
        None => "null"
      }
      match coordinate {
        Some(coordinate) => {
          self.after_top = coordinate.top
          self.after_left = coordinate.left
        }
        None => {
          self.after_top = -9999.0
          self.after_left = -9999.0
        }
      }
    },
  )
}

///|
fn BrowserIframeContentWidget::new(
  document : @rdom.Document,
  id : String,
  allow_overflow : Bool,
) -> BrowserIframeContentWidget {
  let node = document.create_element("div")
  node.set_attribute("data-geometry-owner-widget", id)
  node.set_attribute(
    "data-geometry-owner-overflow",
    if allow_overflow {
      "true"
    } else {
      "false"
    },
  )
  node.set_attribute(
    "style", "box-sizing:border-box;width:80px;height:30px;background:rgba(0,128,255,.15)",
  )
  node.set_inner_html(id)
  {
    id,
    node,
    allow_overflow,
    preference: [Exact],
    after_position: "null",
    after_top: -9999.0,
    after_left: -9999.0,
  }
}

///|
priv struct BrowserIframeGeometryFixture {
  widgets : @view.ContentWidgets
  normal : BrowserIframeContentWidget
  overflow : BrowserIframeContentWidget
  anchor_left : Ref[Double]
  anchor_top : Ref[Double]
}

///|
fn BrowserIframeGeometryFixture::new() -> BrowserIframeGeometryFixture {
  let document = browser_geometry_create_owner_iframe()
  guard document.query_selector("#browser-geometry-owner-root").to_option()
    is Some(root) else {
    abort("browser geometry owner iframe root is missing")
  }
  let widgets = @view.ContentWidgets::ContentWidgets(document, root)
  let normal_container = widgets.dom_node()
  normal_container.set_attribute(
    "style", "position:absolute;top:0;left:0;width:430px;height:300px",
  )
  let overflow_container = widgets.overflowing_content_widgets_dom_node()
  overflow_container.set_attribute(
    "style", "position:absolute;top:0;left:0;width:430px;height:300px",
  )
  root.append_child(normal_container.as_node())
  root.append_child(overflow_container.as_node())
  let anchor_left = Ref(20.0)
  let anchor_top = Ref(50.0)
  widgets.install_live_view_context(() => (0.0, 430.0), position => {
    Some(position)
  })
  let normal = BrowserIframeContentWidget::new(document, "normal", false)
  let overflow = BrowserIframeContentWidget::new(document, "overflow", true)
  widgets.add_widget(normal.content_widget_handle())
  widgets.set_widget_position(normal.content_widget_handle())
  widgets.add_widget(overflow.content_widget_handle())
  widgets.set_widget_position(overflow.content_widget_handle())
  { widgets, normal, overflow, anchor_left, anchor_top }
}

///|
fn BrowserIframeGeometryFixture::context(
  self : BrowserIframeGeometryFixture,
) -> @view.ContentWidgetsRenderContext {
  {
    vertical_offset_for_line: _ => self.anchor_top.val,
    line_height_for_line: _ => 20.0,
    visible_range_for_position: _ => Some(self.anchor_left.val),
    typical_fullwidth_character_width: 16.0,
    scroll_top: 0.0,
    scroll_left: 0.0,
    viewport_width: 500.0,
    viewport_height: 360.0,
  }
}

///|
fn BrowserIframeGeometryFixture::capture(
  _self : BrowserIframeGeometryFixture,
  widget : BrowserIframeContentWidget,
) -> Json {
  let rect = widget.node.get_bounding_client_rect()
  Json::object({
    "position": widget.after_position.to_json(),
    "top": Json::number(widget.after_top),
    "left": Json::number(widget.after_left),
    "rectLeft": Json::number(rect.get_left()),
    "rectTop": Json::number(rect.get_top()),
    "rectRight": Json::number(rect.get_right()),
    "rectBottom": Json::number(rect.get_bottom()),
  })
}

///|
fn BrowserIframeGeometryFixture::run_case(
  self : BrowserIframeGeometryFixture,
  widget : BrowserIframeContentWidget,
  left : Double,
  top : Double,
  preference : Array[@view.ContentWidgetPositionPreference],
) -> Json {
  self.anchor_left.val = left
  self.anchor_top.val = top
  widget.preference = preference
  self.widgets.set_widget_position(widget.content_widget_handle())
  self.widgets.prepare_render_widgets(self.context())
  self.widgets.render_widgets(0.0, 0.0)
  self.capture(widget)
}

///|
fn BrowserIframeGeometryFixture::run_matrix(
  self : BrowserIframeGeometryFixture,
) -> String {
  Json::object({
    "normalExact": self.run_case(self.normal, 20.0, 50.0, [Exact]),
    // Root page-left=40 and owner scrollX=31. These one-pixel overflow inputs
    // clamp the rendered edges to exactly 15px and innerWidth-15px.
    "leftClamp": self.run_case(self.overflow, 5.0, 100.0, [Below]),
    "rightClamp": self.run_case(self.overflow, 397.0, 100.0, [Below]),
    // Root page-top=80 and owner scrollY=47. With a 30px widget these anchor
    // tops put the box exactly on, then one pixel outside, each 22px fit edge.
    "topEqual": self.run_case(self.overflow, 100.0, 19.0, [Above, Below]),
    "topOutside": self.run_case(self.overflow, 100.0, 18.0, [Above, Below]),
    "bottomEqual": self.run_case(self.overflow, 100.0, 255.0, [Below, Above]),
    "bottomOutside": self.run_case(self.overflow, 100.0, 256.0, [Below, Above]),
  }).stringify()
}

///|
extern "js" fn browser_geometry_create_owner_iframe() -> @rdom.Document =
  #| () => {
  #|   document.getElementById('browser-geometry-owner-frame')?.remove();
  #|   const frame = document.createElement('iframe');
  #|   frame.id = 'browser-geometry-owner-frame';
  #|   frame.setAttribute('title', 'content widget owner geometry');
  #|   frame.width = '500';
  #|   frame.height = '360';
  #|   frame.style.cssText = 'width:500px;height:360px;border:0;position:absolute;left:620px;top:20px';
  #|   document.body.appendChild(frame);
  #|   const doc = frame.contentDocument;
  #|   doc.documentElement.style.cssText = 'margin:0;padding:0;width:1000px;height:900px';
  #|   doc.body.style.cssText = 'margin:0;padding:0;width:1000px;height:900px;position:relative';
  #|   const root = doc.createElement('div');
  #|   root.id = 'browser-geometry-owner-root';
  #|   root.style.cssText = 'position:absolute;left:40px;top:80px;width:430px;height:300px';
  #|   doc.body.appendChild(root);
  #|   frame.contentWindow.scrollTo(31, 47);
  #|   return doc;
  #| }

///|
fn browser_geometry_source(hidden_widest : Bool) -> String {
  let hidden_tail = if hidden_widest { "W".repeat(72) } else { "W".repeat(8) }
  [
    "iiiiWWWW",
    "a\tb\tc ｍ e\u{0301}",
    "pre anchor post",
    "visible_widest_" + "W".repeat(36),
    "line_05",
    "line_06",
    "line_07",
    "line_08",
    "line_09",
    "line_10",
    "line_11",
    "hidden_widest_" + hidden_tail,
    "line_13",
    "line_14",
    "line_15",
    "line_16",
    "line_17",
    "fold_header_" + "W".repeat(12),
    "  fold_child_one",
    "  fold_child_two",
    "after_fold",
    "line_22",
    "line_23",
    "line_24",
    "last_line_25",
  ].join("\n")
}

///|
fn browser_geometry_model(name : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="geometry",
      path="/" + name + ".txt",
    ),
    name + ".txt",
    "plaintext",
    1,
    "browser-geometry-" + name,
    browser_geometry_source(true),
  )
}

///|
fn BrowserGeometryFixture::new(
  name : String,
  family : String,
  host : @rdom.Element,
) -> BrowserGeometryFixture {
  let languages = @languages.Languages()
  languages.register_hover_provider(LanguageId("plaintext"), BrowserGeometryHoverProvider::{

  })
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
      tab_size=4,
      render_whitespace=None,
      render_control_characters=false,
      render_line_highlight=None,
      folding=true,
      smooth_scrolling=false,
      font_family=family,
      font_weight="400",
      font_size=16.0,
      line_height=20.0,
      letter_spacing=0.0,
    ),
  )
  let view_line_count = Ref(0)
  @viewer_testing.on_did_render_model(viewer.get_id(), event => {
    view_line_count.val = event.line_count
  })
  |> ignore
  let model = browser_geometry_model(name)
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  let fixture : BrowserGeometryFixture = {
    name,
    viewer,
    model,
    view_line_count,
    injection_ids: [],
  }
  fixture.set_injected_text(false)
  fixture
}

///|
fn BrowserGeometryFixture::set_injected_text(
  self : BrowserGeometryFixture,
  wide : Bool,
) -> Unit {
  let content = if wide { "[WWWW]" } else { "[i]" }
  self.injection_ids = self.viewer.delta_decorations(self.injection_ids, [
    {
      range: Range(3, 5, 3, 5),
      options: ModelDecorationOptions(
        "",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          content,
          inline_class_name="geometry-injected",
        ),
        description="browser geometry injected text",
      ),
    },
  ])
}

///|
fn BrowserGeometryFixture::set_wrap(
  self : BrowserGeometryFixture,
  enabled : Bool,
) -> Unit {
  self.viewer.update_options(self.viewer.get_options().with_soft_wrap(enabled))
}

///|
fn BrowserGeometryFixture::set_hidden_widest(
  self : BrowserGeometryFixture,
  enabled : Bool,
) -> Unit {
  self.viewer.set_value(browser_geometry_source(enabled))
}

///|
fn BrowserGeometryFixture::state_json(
  self : BrowserGeometryFixture,
  line : Int,
  column : Int,
) -> String {
  let layout = self.viewer.get_layout_info()
  let visible = match
    self.viewer.get_scrolled_visible_position(Position(line, column)) {
    Some(position) =>
      Json::object({
        "top": Json::number(position.top),
        "left": Json::number(position.left),
        "height": Json::number(position.height),
      })
    None => Json::null()
  }
  Json::object({
    "name": self.name.to_json(),
    "softWrap": self.viewer.get_options().soft_wrap().to_json(),
    "modelLines": self.model.get_line_count().to_json(),
    "viewLines": self.view_line_count.val.to_json(),
    "contentWidth": Json::number(self.viewer.get_content_width()),
    "scrollWidth": Json::number(self.viewer.get_scroll_width()),
    "scrollLeft": Json::number(self.viewer.get_scroll_left()),
    "contentHeight": Json::number(self.viewer.get_content_height()),
    "scrollHeight": Json::number(self.viewer.get_scroll_height()),
    "scrollTop": Json::number(self.viewer.get_scroll_top()),
    "offset": Json::number(self.viewer.get_offset_for_column(line, column)),
    "lineWidth": Json::number(self.viewer.get_width_of_line(line)),
    "visible": visible,
    "layout": Json::object({
      "width": Json::number(layout.width),
      "height": Json::number(layout.height),
      "contentLeft": Json::number(layout.content_left),
      "contentWidth": Json::number(layout.content_width),
      "horizontalScrollbarHeight": Json::number(
        layout.horizontal_scrollbar_height,
      ),
      "verticalScrollbarWidth": Json::number(layout.vertical_scrollbar_width),
    }),
  }).stringify()
}

///|
fn browser_geometry_fixture_for(
  name : String,
  mono : BrowserGeometryFixture,
  proportional : BrowserGeometryFixture,
) -> BrowserGeometryFixture {
  if name == "proportional" {
    proportional
  } else {
    mono
  }
}

///|
fn run_browser_geometry_test() -> Unit {
  let ctx = @support.BrowserTestContext("browser_geometry")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell browser-geometry-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute(
    "style", "height:100vh;display:flex;gap:24px;align-items:flex-start;",
  )
  let style = document.create_element("style")
  style.set_inner_html(
    ".geometry-injected{color:#b5cea8}.browser-geometry-host{height:140px;width:360px;position:relative;flex:none}",
  )
  shell.append_child(style.as_node())
  let mono_host = browser_geometry_host(document, "monospace")
  let proportional_host = browser_geometry_host(document, "proportional")
  shell.append_child(mono_host.as_node())
  shell.append_child(proportional_host.as_node())
  app.append_child(shell.as_node())
  load_browser_geometry_fonts(loaded => {
    if !loaded {
      ctx.fail("embedded geometry fonts did not load")
      ctx.finish()
      return
    }
    let mono = BrowserGeometryFixture::new(
      "monospace", "Geometry Mono", mono_host,
    )
    let proportional = BrowserGeometryFixture::new(
      "proportional", "Geometry Proportional", proportional_host,
    )
    let iframe_geometry = BrowserIframeGeometryFixture::new()
    let fixture = name => browser_geometry_fixture_for(name, mono, proportional)
    install_browser_geometry_controls(
      (name, line, column) => fixture(name).state_json(line, column),
      (name, enabled) => fixture(name).set_wrap(enabled),
      (name, left, top) => {
        fixture(name).viewer.set_scroll_position(
          scroll_top=top,
          scroll_left=left,
        )
      },
      (name, line, column) => {
        fixture(name).viewer.set_position(Position(line, column))
      },
      name => fixture(name).viewer.focus(),
      (name, wide) => fixture(name).set_injected_text(wide),
      (name, enabled) => fixture(name).set_hidden_widest(enabled),
      (name, hidden) => {
        @viewer_testing.set_hidden_areas(
          fixture(name).viewer.get_id(),
          if hidden {
            [Range(3, 1, 3, 1)]
          } else {
            []
          },
          source="browser-geometry",
        )
        |> ignore
      },
      () => iframe_geometry.run_matrix(),
    )
    poll_browser_geometry_ready(ctx, 120)
  })
}

///|
fn browser_geometry_host(
  document : @rdom.Document,
  name : String,
) -> @rdom.Element {
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host browser-geometry-host")
  host.set_attribute("data-geometry-font", name)
  host
}

///|
fn poll_browser_geometry_ready(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  if @support.query_count(
      ".browser-geometry-host .monaco-editor.readonly-editor",
    ) ==
    2 &&
    @support.query_count(".browser-geometry-host .geometry-injected") == 2 &&
    @support.query_count(".browser-geometry-host .view-line") > 0 {
    ctx.metric_number("devicePixelRatio", browser_geometry_pixel_ratio())
    ctx.metric_int(
      "fontFaces",
      @support.query_count("style[data-browser-geometry-fonts]"),
    )
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for fixed-font geometry fixtures")
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_browser_geometry_ready(ctx, remaining - 1),
      30,
    )
  }
}

///|
extern "js" fn browser_geometry_pixel_ratio() -> Double =
  #| () => globalThis.devicePixelRatio || 1

///|
extern "js" fn install_browser_geometry_controls(
  state_json : (String, Int, Int) -> String,
  set_wrap : (String, Bool) -> Unit,
  set_scroll : (String, Double, Double) -> Unit,
  set_position : (String, Int, Int) -> Unit,
  focus : (String) -> Unit,
  set_injected : (String, Bool) -> Unit,
  set_hidden_widest : (String, Bool) -> Unit,
  set_anchor_hidden : (String, Bool) -> Unit,
  iframe_geometry : () -> String,
) -> Unit =
  #| (stateJson, setWrap, setScroll, setPosition, focus, setInjected,
  #|  setHiddenWidest, setAnchorHidden, iframeGeometry) => {
  #|   globalThis.__browserGeometryControls = Object.freeze({
  #|     state(name, line = 3, column = 6) {
  #|       return JSON.parse(stateJson(name, line, column));
  #|     },
  #|     set_wrap: setWrap,
  #|     set_scroll: setScroll,
  #|     set_position: setPosition,
  #|     focus,
  #|     set_injected: setInjected,
  #|     set_hidden_widest: setHiddenWidest,
  #|     set_anchor_hidden: setAnchorHidden,
  #|     iframe_geometry() {
  #|       return JSON.parse(iframeGeometry());
  #|     },
  #|     font_status() {
  #|       return {
  #|         mono: document.fonts.check('16px "Geometry Mono"', 'iiiiWWWWｍ'),
  #|         proportional: document.fonts.check(
  #|           '16px "Geometry Proportional"', 'iiiiWWWWｍ'
  #|         ),
  #|         pixelRatio: globalThis.devicePixelRatio || 1,
  #|       };
  #|     },
  #|   });
  #| }

///|
extern "js" fn load_browser_geometry_fonts(ready : (Bool) -> Unit) -> Unit =
  #| (ready) => {
  #|   const mono = 'AAEAAAAKAIAAAwAgT1MvMkhvxTsAAAEoAAAAYGNtYXD8aX3aAAADJAAAAGxnbHlm1yxehwAABGAAAApSaGVhZC7+ugYAAACsAAAANmhoZWEHbwNMAAAA5AAAACRobXR48WgAAAAAAYgAAAGcbG9jYYWGiCUAAAOQAAAA0G1heHAAagAKAAABCAAAACBuYW1lZ1gIfgAADrQAAAG5cG9zdOw+mZ4AABBwAAAEFQABAAAAAQAAatNXZ18PPPUAAQPoAAAAAOZ5OvkAAAAA5nk6+f56ADwEfgL4AAAAAwACAAAAAAAAAAEAAAMg/zgAAASwAAD+/ARMAAEAAAAAAAAAAAAAAAAAAABnAAEAAABnAAgAAgAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAwJeAZAABQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAABDAAAAYAAAABAAAAAAPz8/PwAAACD/TQMg/zgAAAMgAMgAAAAAAAAAAAH0ArwAAAAgAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAJYAAACWAAAAlgAAAAAAAACWAAAAlgAAAJYAAAEsAAAAAAAAgAAAAMAAAAUAAMAAQAAABQABABYAAAAEgAQAAMAAgB+AKAAtwMBIZIi7y4x/03//wAAACAAoAC3AwEhkiLvLjH/Tf///+H/wP+q/WHe0d110jQBGQABAAAAAAAAAAAAAAAAAAAAAAAAAAAAFQAVACIALwA8AEkAVgBjAHAAfQCKAJcApACxAL4AywDYAOUA8gD/AQwBGQEmATMBQAFNAVoBZwF0AYEBjgGbAagBtQHCAc8B3AHpAfYCAwIQAh0CKgI3AkQCUQJeAmsCeAKFApICnwKsArkCxgLTAuAC7QL6AwcDFAMhAy4DOwNIA1UDYgNvA3wDiQOWA6MDsAO9A8oD1wPkA/ED/gQLBBgEJQQyBD8ETARZBGYEcwSABI0EmgSnBLQEwQTOBNsE2wToBPUFAgUPBRwFKQACADwAPAIcAuQAAwAHAAA3IREhExEhETwB4P4gUAFAPAKo/agCCP34AAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAf56AmL/fgL4AAMAAAEzNyP+erRQtAJilgABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAR+AtAAAwAANyERITIETPu0UAKAAAAAAAAMAJYAAQAAAAAAAQANAAAAAQAAAAAAAgAHAA0AAQAAAAAAAwAZABQAAQAAAAAABAAVAC0AAQAAAAAABQALAEIAAQAAAAAABgAUAE0AAwABBAkAAQAaAGEAAwABBAkAAgAOAHsAAwABBAkAAwAyAIkAAwABBAkABAAqALsAAwABBAkABQAWAOUAAwABBAkABgAoAPtHZW9tZXRyeSBNb25vUmVndWxhckdlb21ldHJ5IE1vbm8gUmVndWxhciAxLjBHZW9tZXRyeSBNb25vIFJlZ3VsYXJWZXJzaW9uIDEuMEdlb21ldHJ5TW9uby1SZWd1bGFyAEcAZQBvAG0AZQB0AHIAeQAgAE0AbwBuAG8AUgBlAGcAdQBsAGEAcgBHAGUAbwBtAGUAdAByAHkAIABNAG8AbgBvACAAUgBlAGcAdQBsAGEAcgAgADEALgAwAEcAZQBvAG0AZQB0AHIAeQAgAE0AbwBuAG8AIABSAGUAZwB1AGwAYQByAFYAZQByAHMAaQBvAG4AIAAxAC4AMABHAGUAbwBtAGUAdAByAHkATQBvAG4AbwAtAFIAZQBnAHUAbABhAHIAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABnAAAAAwECAQMBBAEFAQYBBwEIAQkBCgELAQwBDQEOAQ8BEAERARIBEwEUARUBFgEXARgBGQEaARsBHAEdAR4BHwEgASEBIgEjASQBJQEmAScBKAEpASoBKwEsAS0BLgEvATABMQEyATMBNAE1ATYBNwE4ATkBOgE7ATwBPQE+AT8BQAFBAUIBQwFEAUUBRgFHAUgBSQFKAUsBTAFNAU4BTwFQAVEBUgFTAVQBVQFWAVcBWAFZAVoBWwFcAV0BXgFfAWABYQFiAWMBZAFlAWYHdW5pMDAyMQd1bmkwMDIyB3VuaTAwMjMHdW5pMDAyNAd1bmkwMDI1B3VuaTAwMjYHdW5pMDAyNwd1bmkwMDI4B3VuaTAwMjkHdW5pMDAyQQd1bmkwMDJCB3VuaTAwMkMHdW5pMDAyRAd1bmkwMDJFB3VuaTAwMkYHdW5pMDAzMAd1bmkwMDMxB3VuaTAwMzIHdW5pMDAzMwd1bmkwMDM0B3VuaTAwMzUHdW5pMDAzNgd1bmkwMDM3B3VuaTAwMzgHdW5pMDAzOQd1bmkwMDNBB3VuaTAwM0IHdW5pMDAzQwd1bmkwMDNEB3VuaTAwM0UHdW5pMDAzRgd1bmkwMDQwB3VuaTAwNDEHdW5pMDA0Mgd1bmkwMDQzB3VuaTAwNDQHdW5pMDA0NQd1bmkwMDQ2B3VuaTAwNDcHdW5pMDA0OAd1bmkwMDQ5B3VuaTAwNEEHdW5pMDA0Qgd1bmkwMDRDB3VuaTAwNEQHdW5pMDA0RQd1bmkwMDRGB3VuaTAwNTAHdW5pMDA1MQd1bmkwMDUyB3VuaTAwNTMHdW5pMDA1NAd1bmkwMDU1B3VuaTAwNTYHdW5pMDA1Nwd1bmkwMDU4B3VuaTAwNTkHdW5pMDA1QQd1bmkwMDVCB3VuaTAwNUMHdW5pMDA1RAd1bmkwMDVFB3VuaTAwNUYHdW5pMDA2MAd1bmkwMDYxB3VuaTAwNjIHdW5pMDA2Mwd1bmkwMDY0B3VuaTAwNjUHdW5pMDA2Ngd1bmkwMDY3B3VuaTAwNjgHdW5pMDA2OQd1bmkwMDZBB3VuaTAwNkIHdW5pMDA2Qwd1bmkwMDZEB3VuaTAwNkUHdW5pMDA2Rgd1bmkwMDcwB3VuaTAwNzEHdW5pMDA3Mgd1bmkwMDczB3VuaTAwNzQHdW5pMDA3NQd1bmkwMDc2B3VuaTAwNzcHdW5pMDA3OAd1bmkwMDc5B3VuaTAwN0EHdW5pMDA3Qgd1bmkwMDdDB3VuaTAwN0QHdW5pMDA3RQRuYnNwB3VuaTAwQjcHdW5pMDMwMQd1bmkyMTkyB3VuaTIyRUYHdW5pMkUzMQd1bmlGRjREAAAA';
  #|   const proportional = 'AAEAAAAKAIAAAwAgT1MvMkhvxSIAAAEoAAAAYGNtYXD8aX3aAAADJAAAAGxnbHlmgCjBpgAABGAAAAo6aGVhZC7+ugYAAACsAAAANmhoZWEHbwNMAAAA5AAAACRobXR452gAAAAAAYgAAAGcbG9jYYQ/htkAAAOQAAAA0G1heHAAagAKAAABCAAAACBuYW1l2HdCVwAADpwAAAIZcG9zdOw+mZ4AABC4AAAEFQABAAAAAQAATSofyV8PPPUAAQPoAAAAAOZ5OvkAAAAA5nk6+f56ADwEfgL4AAAAAwACAAAAAAAAAAEAAAMg/zgAAASwAAD+/ARMAAEAAAAAAAAAAAAAAAAAAABnAAEAAABnAAgAAgAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAwJFAZAABQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAABDAAAAYAAAABAAAAAAPz8/PwAAACD/TQMg/zgAAAMgAMgAAAAAAAAAAAH0ArwAAAAgAAACWAAAASwAAAEsAAACWAAAAlgAAAJYAAADhAAAAlgAAAEsAAAB9AAAAfQAAAJYAAACWAAAASwAAAJYAAABLAAAAlgAAAJEAAACRAAAAkQAAAJEAAACRAAAAkQAAAJEAAACRAAAAkQAAAJEAAABLAAAASwAAAJYAAACWAAAAlgAAAJYAAADhAAAArwAAAK8AAACvAAAArwAAAK8AAACvAAAArwAAAK8AAABLAAAArwAAAK8AAACvAAAA4QAAAK8AAACvAAAArwAAAK8AAACvAAAArwAAAK8AAACvAAAArwAAAOEAAACvAAAArwAAAK8AAAB9AAAAlgAAAH0AAACWAAAAlgAAAJYAAACCAAAAggAAAIIAAACCAAAAggAAAIIAAACCAAAAggAAAEsAAACCAAAAggAAAEsAAADhAAAAggAAAIIAAACCAAAAggAAAIIAAACCAAAAggAAAIIAAACCAAAA4QAAAIIAAACCAAAAggAAAH0AAABLAAAAfQAAAJYAAABLAAAASwAAAAAAAACvAAAAlgAAAEsAAAEsAAAAAAAAgAAAAMAAAAUAAMAAQAAABQABABYAAAAEgAQAAMAAgB+AKAAtwMBIZIi7y4x/03//wAAACAAoAC3AwEhkiLvLjH/Tf///+H/wP+q/WHe0d110jQBGQABAAAAAAAAAAAAAAAAAAAAAAAAAAAAFQAVACEALgA7AEgAVQBiAG4AewCIAJUAogCuALsAxwDUAOEA7gD7AQgBFQEiAS8BPAFJAVYBYgFuAXsBiAGVAaIBrwG8AckB1gHjAfAB/QIKAhcCIwIwAj0CSgJXAmQCcQJ+AosCmAKlArICvwLMAtkC5gLzAwADDQMaAycDNANBA04DWwNoA3UDggOPA5wDqQO2A8IDzwPcA+gD9QQCBA8EHAQpBDYEQwRQBF0EagR3BIQEkQSeBKsEtwTEBNEE0QTdBOoE9wUEBRAFHQACADwAPAIcAuQAAwAHAAA3IREhExEhETwB4P4gUAFAPAKo/agCCP34AAABACMAUAEJAtAAAwAANzMRIyPm5lACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUANSAtAAAwAANyERITIDIPzgUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAjAFABCQLQAAMAADczESMj5uZQAoAAAQAyAFABwgLQAAMAADchESEyAZD+cFACgAABADIAUAHCAtAAAwAANyERITIBkP5wUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABACMAUAEJAtAAAwAANzMRIyPm5lACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAIwBQAQkC0AADAAA3MxEjI+bmUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACEgLQAAMAADchESEyAeD+IFACgAABADIAUAISAtAAAwAANyERITIB4P4gUAKAAAEAMgBQAhIC0AADAAA3IREhMgHg/iBQAoAAAQAyAFACEgLQAAMAADchESEyAeD+IFACgAABADIAUAISAtAAAwAANyERITIB4P4gUAKAAAEAMgBQAhIC0AADAAA3IREhMgHg/iBQAoAAAQAyAFACEgLQAAMAADchESEyAeD+IFACgAABADIAUAISAtAAAwAANyERITIB4P4gUAKAAAEAMgBQAhIC0AADAAA3IREhMgHg/iBQAoAAAQAyAFACEgLQAAMAADchESEyAeD+IFACgAABACMAUAEJAtAAAwAANzMRIyPm5lACgAABACMAUAEJAtAAAwAANzMRIyPm5lACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQA1IC0AADAAA3IREhMgMg/OBQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAIwBQAQkC0AADAAA3MxEjI+bmUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQA1IC0AADAAA3IREhMgMg/OBQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFADUgLQAAMAADchESEyAyD84FACgAABADIAUAKKAtAAAwAANyERITICWP2oUAKAAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACigLQAAMAADchESEyAlj9qFACgAABADIAUAHCAtAAAwAANyERITIBkP5wUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFABwgLQAAMAADchESEyAZD+cFACgAABADIAUAImAtAAAwAANyERITIB9P4MUAKAAAEAMgBQAiYC0AADAAA3IREhMgH0/gxQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAjAFABCQLQAAMAADczESMj5uZQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAIwBQAQkC0AADAAA3MxEjI+bmUAKAAAEAMgBQA1IC0AADAAA3IREhMgMg/OBQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAyAFADUgLQAAMAADchESEyAyD84FACgAABADIAUAHWAtAAAwAANyERITIBpP5cUAKAAAEAMgBQAdYC0AADAAA3IREhMgGk/lxQAoAAAQAyAFAB1gLQAAMAADchESEyAaT+XFACgAABADIAUAHCAtAAAwAANyERITIBkP5wUAKAAAEAIwBQAQkC0AADAAA3MxEjI+bmUAKAAAEAMgBQAcIC0AADAAA3IREhMgGQ/nBQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABACMAUAEJAtAAAwAANzMRIyPm5lACgAAB/noCYv9+AvgAAwAAATM3I/56tFC0AmKWAAEAMgBQAooC0AADAAA3IREhMgJY/ahQAoAAAQAyAFACJgLQAAMAADchESEyAfT+DFACgAABACMAUAEJAtAAAwAANzMRIyPm5lACgAABADIAUAR+AtAAAwAANyERITIETPu0UAKAAAAAAAAMAJYAAQAAAAAAAQAVAAAAAQAAAAAAAgAHABUAAQAAAAAAAwAhABwAAQAAAAAABAAdAD0AAQAAAAAABQALAFoAAQAAAAAABgAcAGUAAwABBAkAAQAqAIEAAwABBAkAAgAOAKsAAwABBAkAAwBCALkAAwABBAkABAA6APsAAwABBAkABQAWATUAAwABBAkABgA4AUtHZW9tZXRyeSBQcm9wb3J0aW9uYWxSZWd1bGFyR2VvbWV0cnkgUHJvcG9ydGlvbmFsIFJlZ3VsYXIgMS4wR2VvbWV0cnkgUHJvcG9ydGlvbmFsIFJlZ3VsYXJWZXJzaW9uIDEuMEdlb21ldHJ5UHJvcG9ydGlvbmFsLVJlZ3VsYXIARwBlAG8AbQBlAHQAcgB5ACAAUAByAG8AcABvAHIAdABpAG8AbgBhAGwAUgBlAGcAdQBsAGEAcgBHAGUAbwBtAGUAdAByAHkAIABQAHIAbwBwAG8AcgB0AGkAbwBuAGEAbAAgAFIAZQBnAHUAbABhAHIAIAAxAC4AMABHAGUAbwBtAGUAdAByAHkAIABQAHIAbwBwAG8AcgB0AGkAbwBuAGEAbAAgAFIAZQBnAHUAbABhAHIAVgBlAHIAcwBpAG8AbgAgADEALgAwAEcAZQBvAG0AZQB0AHIAeQBQAHIAbwBwAG8AcgB0AGkAbwBuAGEAbAAtAFIAZQBnAHUAbABhAHIAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABnAAAAAwECAQMBBAEFAQYBBwEIAQkBCgELAQwBDQEOAQ8BEAERARIBEwEUARUBFgEXARgBGQEaARsBHAEdAR4BHwEgASEBIgEjASQBJQEmAScBKAEpASoBKwEsAS0BLgEvATABMQEyATMBNAE1ATYBNwE4ATkBOgE7ATwBPQE+AT8BQAFBAUIBQwFEAUUBRgFHAUgBSQFKAUsBTAFNAU4BTwFQAVEBUgFTAVQBVQFWAVcBWAFZAVoBWwFcAV0BXgFfAWABYQFiAWMBZAFlAWYHdW5pMDAyMQd1bmkwMDIyB3VuaTAwMjMHdW5pMDAyNAd1bmkwMDI1B3VuaTAwMjYHdW5pMDAyNwd1bmkwMDI4B3VuaTAwMjkHdW5pMDAyQQd1bmkwMDJCB3VuaTAwMkMHdW5pMDAyRAd1bmkwMDJFB3VuaTAwMkYHdW5pMDAzMAd1bmkwMDMxB3VuaTAwMzIHdW5pMDAzMwd1bmkwMDM0B3VuaTAwMzUHdW5pMDAzNgd1bmkwMDM3B3VuaTAwMzgHdW5pMDAzOQd1bmkwMDNBB3VuaTAwM0IHdW5pMDAzQwd1bmkwMDNEB3VuaTAwM0UHdW5pMDAzRgd1bmkwMDQwB3VuaTAwNDEHdW5pMDA0Mgd1bmkwMDQzB3VuaTAwNDQHdW5pMDA0NQd1bmkwMDQ2B3VuaTAwNDcHdW5pMDA0OAd1bmkwMDQ5B3VuaTAwNEEHdW5pMDA0Qgd1bmkwMDRDB3VuaTAwNEQHdW5pMDA0RQd1bmkwMDRGB3VuaTAwNTAHdW5pMDA1MQd1bmkwMDUyB3VuaTAwNTMHdW5pMDA1NAd1bmkwMDU1B3VuaTAwNTYHdW5pMDA1Nwd1bmkwMDU4B3VuaTAwNTkHdW5pMDA1QQd1bmkwMDVCB3VuaTAwNUMHdW5pMDA1RAd1bmkwMDVFB3VuaTAwNUYHdW5pMDA2MAd1bmkwMDYxB3VuaTAwNjIHdW5pMDA2Mwd1bmkwMDY0B3VuaTAwNjUHdW5pMDA2Ngd1bmkwMDY3B3VuaTAwNjgHdW5pMDA2OQd1bmkwMDZBB3VuaTAwNkIHdW5pMDA2Qwd1bmkwMDZEB3VuaTAwNkUHdW5pMDA2Rgd1bmkwMDcwB3VuaTAwNzEHdW5pMDA3Mgd1bmkwMDczB3VuaTAwNzQHdW5pMDA3NQd1bmkwMDc2B3VuaTAwNzcHdW5pMDA3OAd1bmkwMDc5B3VuaTAwN0EHdW5pMDA3Qgd1bmkwMDdDB3VuaTAwN0QHdW5pMDA3RQRuYnNwB3VuaTAwQjcHdW5pMDMwMQd1bmkyMTkyB3VuaTIyRUYHdW5pMkUzMQd1bmlGRjREAAAA';
  #|   const style = document.createElement('style');
  #|   style.dataset.browserGeometryFonts = 'embedded';
  #|   style.textContent = `
  #|     @font-face {
  #|       font-family: "Geometry Mono";
  #|       src: url(data:font/ttf;base64,${mono}) format("truetype");
  #|       font-style: normal;
  #|       font-weight: 400;
  #|       font-display: block;
  #|     }
  #|     @font-face {
  #|       font-family: "Geometry Proportional";
  #|       src: url(data:font/ttf;base64,${proportional}) format("truetype");
  #|       font-style: normal;
  #|       font-weight: 400;
  #|       font-display: block;
  #|     }
  #|   `;
  #|   document.head.appendChild(style);
  #|   const corpus = ' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~ ·́→⋯⸱ｍ';
  #|   Promise.all([
  #|     document.fonts.load('16px "Geometry Mono"', corpus),
  #|     document.fonts.load('italic 16px "Geometry Mono"', corpus),
  #|     document.fonts.load('bold 16px "Geometry Mono"', corpus),
  #|     document.fonts.load('16px "Geometry Proportional"', corpus),
  #|     document.fonts.load('italic 16px "Geometry Proportional"', corpus),
  #|     document.fonts.load('bold 16px "Geometry Proportional"', corpus),
  #|     document.fonts.ready,
  #|   ]).then(() => {
  #|     ready(
  #|       document.fonts.check('16px "Geometry Mono"', corpus) &&
  #|       document.fonts.check('16px "Geometry Proportional"', corpus)
  #|     );
  #|   }, () => ready(false));
  #| }
