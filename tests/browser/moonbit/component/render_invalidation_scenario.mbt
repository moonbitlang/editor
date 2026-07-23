// Browser fixture for runtime render-invalidation coverage. Playwright drives
// the public Viewer option/decoration APIs through these controls and observes
// the real rendered DOM; no private view hook is used to manufacture a frame.

///|
priv struct RenderInvalidationHoverProvider {}

///|
priv struct RenderInvalidationTokenizer {}

///|
impl @syntax.LineTokenizer for RenderInvalidationTokenizer with fn initial_state(
  _self,
) {
  TokenizerState("render-invalidation")
}

///|
impl @syntax.LineTokenizer for RenderInvalidationTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  if line_text.length() > 0 {
    tokens.push({ start: 0, end: 1, tag: Keyword })
    if line_text.length() > 1 {
      tokens.push({
        start: line_text.length() - 1,
        end: line_text.length(),
        tag: Keyword,
      })
    }
  }
  (tokens, state)
}

///|
impl @language.HoverProvider for RenderInvalidationHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  for needle in ["anchor", "mapping-target"] {
    match model.snapshot.text.find(needle) {
      Some(start) =>
        if offset >= start && offset < start + needle.length() {
          return Some({
            range: model.snapshot.range_of(
              OffsetRange(start, start + needle.length()),
            ),
            contents: [PlainText("render invalidation hover")],
          })
        }
      None => ()
    }
  }
  None
}

///|
fn render_invalidation_source() -> String {
  "prefix anchor target  \u{202E}  \nthis is a deliberately long line with padding padding and enough trailing text to wrap into continuations when soft wrapping is enabled\n\ttab-stop\nmapping-target final line"
}

///|
fn render_invalidation_position_json(viewer : @viewer.Viewer) -> String {
  match viewer.get_position() {
    Some(position) =>
      "{\"line\":\{position.line_number},\"column\":\{position.column}}"
    None => "null"
  }
}

///|
fn render_invalidation_layout_json(viewer : @viewer.Viewer) -> String {
  let info = viewer.get_layout_info()
  "{\"width\":\{info.width},\"lineNumbersWidth\":\{info.line_numbers_width},\"decorationsWidth\":\{info.decorations_width},\"contentLeft\":\{info.content_left},\"contentWidth\":\{info.content_width}}"
}

///|
fn run_render_invalidation_test() -> Unit {
  let ctx = @support.BrowserTestContext("render_invalidation")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell render-invalidation-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let style = document.create_element("style")
  style.set_inner_html(
    ".render-invalidation-spacing { letter-spacing: 8px !important; }",
  )
  shell.append_child(style.as_node())
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host render-invalidation-host")
  host.set_attribute("style", "height:180px;width:420px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/render-invalidation.txt",
    ),
    "render-invalidation.txt",
    "plaintext",
    1,
    "render-invalidation-rev-1",
    render_invalidation_source(),
  )
  let languages = @languages.Languages()
  languages.register_hover_provider(LanguageId("plaintext"), RenderInvalidationHoverProvider::{

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
      render_whitespace=None,
      render_control_characters=false,
      render_line_highlight=None,
      render_line_highlight_only_when_focus=false,
      render_validation_decorations=On,
      smooth_scrolling=false,
    ),
  )
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  viewer.set_position(Position(1, 21))
  viewer.delta_decorations([], [
    {
      range: Range(2, 1, 2, 7),
      options: ModelDecorationOptions(
        "squiggly-warning",
        message="render invalidation validation",
        show_if_collapsed=true,
        description="render invalidation validation",
      ),
    },
  ])
  |> ignore
  let spacing_ids : Ref[Array[String]] = Ref([])
  let token_registration : Ref[@base_common.Disposable?] = Ref(None)
  let zone_generation = Ref(0)
  let first_zone_top_count = Ref(0)
  let second_zone_top_count = Ref(0)
  let zone_node = document.create_element("div")
  zone_node.set_attribute("data-zone-generation", "1")
  zone_node.set_inner_html("zone-1")
  let zone_delegate = @viewer.view_zone(2, zone_node, height_in_px=18.0, on_dom_node_top=_ => {
    first_zone_top_count.val += 1
  })
  let zone_id = Ref("")
  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("viewer did not expose its root DOM node")
    ctx.finish()
    return
  }
  install_render_invalidation_controls(
    root,
    mode => {
      match mode {
        "none" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(None),
          )
        "boundary" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(Boundary),
          )
        "selection" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(Selection),
          )
        "trailing" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(Trailing),
          )
        "all" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(All),
          )
        _ => ()
      }
    },
    enabled => {
      viewer.update_options(
        viewer.get_options().with_render_control_characters(enabled),
      )
    },
    mode => {
      match mode {
        "none" =>
          viewer.update_options(
            viewer.get_options().with_render_line_highlight(None),
          )
        "gutter" =>
          viewer.update_options(
            viewer.get_options().with_render_line_highlight(Gutter),
          )
        "line" =>
          viewer.update_options(
            viewer.get_options().with_render_line_highlight(Line),
          )
        "all" =>
          viewer.update_options(
            viewer.get_options().with_render_line_highlight(All),
          )
        _ => ()
      }
    },
    enabled => {
      viewer.update_options(
        viewer.get_options().with_render_line_highlight_only_when_focus(enabled),
      )
    },
    mode => {
      match mode {
        "editable" =>
          viewer.update_options(
            viewer.get_options().with_render_validation_decorations(Editable),
          )
        "on" =>
          viewer.update_options(
            viewer.get_options().with_render_validation_decorations(On),
          )
        "off" =>
          viewer.update_options(
            viewer.get_options().with_render_validation_decorations(Off),
          )
        _ => ()
      }
    },
    tab_size => {
      viewer.update_options(viewer.get_options().with_tab_size(tab_size))
    },
    enabled => {
      viewer.update_options(viewer.get_options().with_soft_wrap(enabled))
    },
    () => {
      let original = viewer.get_options()
      viewer.update_options(original.with_render_whitespace(All))
      viewer.update_options(original)
    },
    (line, column) => {
      let position : @base_common.Position = Position(line, column)
      viewer.set_position(position)
      viewer.reveal_position(position)
    },
    () => {
      if spacing_ids.val.length() > 0 {
        viewer.remove_decorations(spacing_ids.val)
      }
      spacing_ids.val = viewer.delta_decorations([], [
        {
          range: Range(1, 1, 1, 7),
          options: ModelDecorationOptions(
            "",
            inline_class_name="render-invalidation-spacing",
            inline_class_name_affects_letter_spacing=true,
            description="render invalidation spacing",
          ),
        },
      ])
    },
    () => {
      viewer.remove_decorations(spacing_ids.val)
      spacing_ids.val = []
    },
    () => {
      let ids = viewer.delta_decorations([], [
        {
          range: Range(1, 1, 1, 7),
          options: ModelDecorationOptions(
            "",
            inline_class_name="render-invalidation-spacing",
            inline_class_name_affects_letter_spacing=true,
            description="render invalidation spacing round trip",
          ),
        },
      ])
      viewer.remove_decorations(ids)
    },
    () => render_invalidation_position_json(viewer),
    () => viewer.focus(),
    () => {
      viewer.update_options(
        viewer
        .get_options()
        .with_line_numbers_min_chars(4)
        .with_line_decorations_width(17),
      )
    },
    () => render_invalidation_layout_json(viewer),
    min_chars => {
      viewer.update_options(
        viewer.get_options().with_line_numbers_min_chars(min_chars),
      )
    },
    line_count => {
      let lines : Array[String] = []
      for index in 1..<=line_count {
        lines.push("line " + index.to_string())
      }
      viewer.set_value(lines.join("\n"))
    },
    () => {
      zone_generation.val += 1
      let generation = zone_generation.val
      if generation == 1 {
        viewer.change_view_zones(accessor => {
          zone_id.val = accessor.add_zone(zone_delegate)
        })
      } else {
        // `layout_zone` rereads mutable geometry and callbacks but retains the
        // insertion-time DOM node, ordinal, and minimum width.
        zone_delegate.on_dom_node_top = Some(_ => second_zone_top_count.val += 1)
        zone_delegate.after_line_number = 2
        zone_delegate.height_in_px = Some(18.0)
        viewer.change_view_zones(accessor => accessor.layout_zone(zone_id.val))
      }
    },
    () => {
      "{\"first\":\{first_zone_top_count.val},\"second\":\{second_zone_top_count.val}}"
    },
    () => {
      match token_registration.val {
        Some(registration) => registration.dispose()
        None => ()
      }
      token_registration.val = Some(
        languages.set_tokens_provider("plaintext", RenderInvalidationTokenizer::{

        }),
      )
    },
  )
  @support.set_timeout(() => poll_render_invalidation_ready(ctx, root, 100), 30)
}

///|
fn poll_render_invalidation_ready(
  ctx : @support.BrowserTestContext,
  root : @rdom.Element,
  remaining : Int,
) -> Unit {
  let line_count = @support.query_count(".render-invalidation-host .view-line")
  let validation_count = @support.query_count(
    ".render-invalidation-host .cdr.squiggly-warning",
  )
  if line_count > 0 && validation_count > 0 {
    ctx.assert_true(
      root.get_attribute("class").contains("readonly-editor"),
      "viewer root did not finish mounting",
    )
    ctx.metric_int("initialLines", line_count)
    ctx.metric_int("initialValidationDecorations", validation_count)
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for render-invalidation fixture")
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_render_invalidation_ready(ctx, root, remaining - 1),
      30,
    )
  }
}

///|
extern "js" fn install_render_invalidation_controls(
  root : @rdom.Element,
  set_whitespace : (String) -> Unit,
  set_control : (Bool) -> Unit,
  set_highlight : (String) -> Unit,
  set_focus_only : (Bool) -> Unit,
  set_validation : (String) -> Unit,
  set_tab_size : (Int) -> Unit,
  set_wrap : (Bool) -> Unit,
  whitespace_round_trip : () -> Unit,
  set_position : (Int, Int) -> Unit,
  add_spacing_decoration : () -> Unit,
  remove_spacing_decoration : () -> Unit,
  decoration_round_trip : () -> Unit,
  position_json : () -> String,
  focus : () -> Unit,
  set_compensated_layout : () -> Unit,
  layout_json : () -> String,
  set_min_chars : (Int) -> Unit,
  set_line_count : (Int) -> Unit,
  replace_zone : () -> Unit,
  zone_counts_json : () -> String,
  recolor_tokens : () -> Unit,
) -> Unit =
  #| (root, setWhitespace, setControl, setHighlight, setFocusOnly,
  #|  setValidation, setTabSize, setWrap, whitespaceRoundTrip,
  #|  setPosition, addSpacingDecoration, removeSpacingDecoration,
  #|  decorationRoundTrip, positionJson, focus, setCompensatedLayout,
  #|  layoutJson, setMinChars, setLineCount, replaceZone, zoneCountsJson,
  #|  recolorTokens) => {
  #|   let originalRequestAnimationFrame = null;
  #|   let animationFrameCount = 0;
  #|   let mutationCount = 0;
  #|   let mutationTargets = [];
  #|   let writeTargets = [];
  #|   let observer = null;
  #|   let originalSetAttribute = null;
  #|   let originalSetProperty = null;
  #|   const stopProbe = () => {
  #|     const result = {
  #|       frames: animationFrameCount,
  #|       mutations: mutationCount,
  #|       targets: [...new Set(mutationTargets)],
  #|       writes: [...new Set(writeTargets)],
  #|     };
  #|     if (originalRequestAnimationFrame) {
  #|       window.requestAnimationFrame = originalRequestAnimationFrame;
  #|       originalRequestAnimationFrame = null;
  #|     }
  #|     if (originalSetAttribute) {
  #|       Element.prototype.setAttribute = originalSetAttribute;
  #|       originalSetAttribute = null;
  #|     }
  #|     if (originalSetProperty) {
  #|       CSSStyleDeclaration.prototype.setProperty = originalSetProperty;
  #|       originalSetProperty = null;
  #|     }
  #|     observer?.disconnect();
  #|     observer = null;
  #|     return result;
  #|   };
  #|   globalThis.__renderInvalidationControls = {
  #|     root,
  #|     set_whitespace: setWhitespace,
  #|     set_control: setControl,
  #|     set_highlight: setHighlight,
  #|     set_focus_only: setFocusOnly,
  #|     set_validation: setValidation,
  #|     set_tab_size: setTabSize,
  #|     set_wrap: setWrap,
  #|     whitespace_round_trip: whitespaceRoundTrip,
  #|     set_position: setPosition,
  #|     add_spacing_decoration: addSpacingDecoration,
  #|     remove_spacing_decoration: removeSpacingDecoration,
  #|     decoration_round_trip: decorationRoundTrip,
  #|     position: () => JSON.parse(positionJson()),
  #|     layout: () => JSON.parse(layoutJson()),
  #|     focus,
  #|     set_compensated_layout: setCompensatedLayout,
  #|     set_min_chars: setMinChars,
  #|     set_line_count: setLineCount,
  #|     replace_zone: replaceZone,
  #|     zone_counts: () => JSON.parse(zoneCountsJson()),
  #|     recolor_tokens: recolorTokens,
  #|     blur: () => root.blur(),
  #|     start_probe: () => {
  #|       if (originalRequestAnimationFrame || observer) stopProbe();
  #|       animationFrameCount = 0;
  #|       mutationCount = 0;
  #|       mutationTargets = [];
  #|       writeTargets = [];
  #|       originalRequestAnimationFrame = window.requestAnimationFrame.bind(window);
  #|       window.requestAnimationFrame = (callback) => {
  #|         animationFrameCount += 1;
  #|         return originalRequestAnimationFrame(callback);
  #|       };
  #|       originalSetAttribute = Element.prototype.setAttribute;
  #|       Element.prototype.setAttribute = function(name, value) {
  #|         if (name === 'style' && this.matches('.cursor')) {
  #|           writeTargets.push('cursor');
  #|         }
  #|         if (name === 'style' && this.hasAttribute('data-content-widget')) {
  #|           writeTargets.push('contentWidget');
  #|         }
  #|         return originalSetAttribute.call(this, name, value);
  #|       };
  #|       originalSetProperty = CSSStyleDeclaration.prototype.setProperty;
  #|       CSSStyleDeclaration.prototype.setProperty = function(name, value, priority) {
  #|         const cursor = root.querySelector('.cursor');
  #|         const widget = root.querySelector('[data-content-widget]');
  #|         if (cursor && this === cursor.style) writeTargets.push('cursor');
  #|         if (widget && this === widget.style) writeTargets.push('contentWidget');
  #|         return originalSetProperty.call(this, name, value, priority);
  #|       };
  #|       observer = new MutationObserver((records) => {
  #|         mutationCount += records.length;
  #|         for (const record of records) {
  #|           const target = record.target;
  #|           if (!(target instanceof Element)) continue;
  #|           if (target.matches('.cursor')) mutationTargets.push('cursor');
  #|           if (target.hasAttribute('data-content-widget')) {
  #|             mutationTargets.push('contentWidget');
  #|           }
  #|           if (target.matches('.view-line, .view-lines') || target.closest('.view-line')) {
  #|             mutationTargets.push('viewLine');
  #|           }
  #|         }
  #|       });
  #|       observer.observe(root, {
  #|         subtree: true,
  #|         childList: true,
  #|         attributes: true,
  #|         characterData: true,
  #|       });
  #|     },
  #|     stop_probe: stopProbe,
  #|   };
  #| }
