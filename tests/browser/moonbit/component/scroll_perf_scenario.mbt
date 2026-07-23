// Local half of the pinned-Monaco scroll-frame oracle. Query parameters select
// the viewport line count and smoothScrolling value; the Playwright harness
// supplies the same text, dimensions, wheel event, and decoration density to
// this Viewer and to the pinned VS Code standalone editor.

///|
fn run_scroll_perf_test() -> Unit {
  let visible_lines = scroll_perf_int_param("lines", 10)
  let smooth = scroll_perf_bool_param("smooth")
  let wide = scroll_perf_bool_param("wide")
  guard scroll_perf_mount_host(visible_lines) is Some(host) else { return }
  let source = scroll_perf_source_text(wide)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/scroll-perf.txt",
  )
  let model = @model.TextModel(
    uri, "scroll-perf.txt", "plaintext", 1, "scroll-perf-rev-1", source,
  )
  let replacement_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/scroll-perf-replacement.txt",
  )
  let replacement = @model.TextModel(
    replacement_uri, "scroll-perf-replacement.txt", "plaintext", 1, "scroll-perf-rev-2",
    source,
  )
  let decorations : Array[@model.ModelDeltaDecoration] = []
  for line in 1..<=3000 {
    if line % 2 == 0 {
      decorations.push({
        range: Range(line, 1, line, 10),
        options: ModelDecorationOptions(
          "scroll-perf-line",
          inline_class_name="scroll-perf-inline",
          description="scroll performance oracle",
        ),
      })
    }
  }
  model.delta_decorations([], decorations) |> ignore
  let viewer = @viewer.Viewer::create(
    host,
    options=ViewerOptions(
      soft_wrap=false,
      smooth_scrolling=smooth,
      folding=false,
      line_height=18.0,
      font_size=13.0,
    ),
  )
  let public_scroll_events = Ref(0)
  viewer.on_did_scroll_change(event => {
    if event.scroll_top_changed || event.scroll_left_changed {
      public_scroll_events.val += 1
    }
  })
  |> ignore
  @viewer_testing.on_did_render_model(viewer.get_id(), event => {
    if event.fresh {
      host.set_attribute("data-scroll-ready", "true")
      host.set_attribute("data-visible-lines", visible_lines.to_string())
      host.set_attribute("data-smooth", smooth.to_string())
    }
  })
  |> ignore
  @viewer_testing.on_did_observe_scroll_frame(viewer.get_id(), event => {
    let phase = match event.phase {
      StateCommitted => "state-committed"
      RenderStarted => "render-started"
      RenderFinished => "render-finished"
    }
    forward_scroll_perf_phase(
      event.viewer_id,
      phase,
      event.scroll_top,
      event.scroll_left,
    )
  })
  |> ignore
  let zone = @rdom.document().create_element("div")
  zone.set_inner_html("scroll performance view zone")
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  viewer.change_view_zones(accessor => {
    accessor.add_zone(@viewer.view_zone(5, zone, height_in_px=18.0)) |> ignore
  })
  install_scroll_perf_controls(
    (scroll_top, scroll_left) => {
      viewer.set_scroll_position(scroll_top~, scroll_left~)
    },
    () => viewer.get_scroll_top(),
    () => viewer.get_scroll_left(),
    () => public_scroll_events.val,
    () => {
      viewer.set_model(Some(replacement))
      viewer.handle_initialized()
    },
    () => viewer.set_model(None),
    () => viewer.dispose(),
    line => {
      viewer.set_selection(
        @core.Selection::from_positions(Position(line, 1), Position(line, 5)),
      )
    },
  )
}

///|
fn scroll_perf_mount_host(visible_lines : Int) -> @rdom.Element? {
  match @rdom.document().query_selector("#app").to_option() {
    Some(app) => {
      let host = @rdom.document().create_element("div")
      host.set_attribute("class", "viewer-host scroll-perf-host")
      host.set_attribute(
        "style",
        "width:800px;height:" +
        (visible_lines * 18).to_string() +
        "px;overflow:hidden;",
      )
      app.append_child(host.as_node())
      Some(host)
    }
    None => None
  }
}

///|
fn scroll_perf_source_text(wide : Bool) -> String {
  let builder = StringBuilder()
  for line in 1..<=3000 {
    builder.write_string("perf line " + line.to_string() + " ")
    let repetitions = if wide { 24 } else { 1 }
    for _ in 0..<repetitions {
      builder.write_string("alpha beta gamma delta epsilon zeta eta theta ")
    }
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
extern "js" fn scroll_perf_int_param(name : String, fallback : Int) -> Int =
  #| (name, fallback) => {
  #|   const value = Number(new URLSearchParams(location.search).get(name));
  #|   return Number.isFinite(value) && value > 0 ? Math.trunc(value) : fallback;
  #| }

///|
extern "js" fn scroll_perf_bool_param(name : String) -> Bool =
  #| (name) => new URLSearchParams(location.search).get(name) === 'true'

///|
extern "js" fn install_scroll_perf_controls(
  set_scroll_position : (Double, Double) -> Unit,
  get_scroll_top : () -> Double,
  get_scroll_left : () -> Double,
  get_public_scroll_events : () -> Int,
  replace_model : () -> Unit,
  detach_model : () -> Unit,
  dispose_viewer : () -> Unit,
  set_selection : (Int) -> Unit,
) -> Unit =
  #| (
  #|   setScrollPosition,
  #|   getScrollTop,
  #|   getScrollLeft,
  #|   getPublicScrollEvents,
  #|   replaceModel,
  #|   detachModel,
  #|   disposeViewer,
  #|   setSelection,
  #| ) => {
  #|   globalThis.__scrollPerfControls = {
  #|     reset: () => setScrollPosition(0, 0),
  #|     setScrollPosition,
  #|     setScrollTop: (top) => setScrollPosition(top, getScrollLeft()),
  #|     setScrollLeft: (left) => setScrollPosition(getScrollTop(), left),
  #|     getScrollTop,
  #|     getScrollLeft,
  #|     getPublicScrollEvents,
  #|     replaceModel,
  #|     detachModel,
  #|     dispose: disposeViewer,
  #|     setSelection,
  #|   };
  #| }

///|
extern "js" fn forward_scroll_perf_phase(
  viewer_id : String,
  phase : String,
  scroll_top : Double,
  scroll_left : Double,
) -> Unit =
  #| (viewerId, phase, scrollTop, scrollLeft) => {
  #|   globalThis.__scrollProbe?.recordLocalPhase({
  #|     viewerId,
  #|     phase,
  #|     scrollTop,
  #|     scrollLeft,
  #|   });
  #| }
