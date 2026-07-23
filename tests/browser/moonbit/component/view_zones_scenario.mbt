// Real-Chromium conformance fixture for the public ViewZones transaction and
// the browser ViewPart's DOM ownership. Playwright drives the retained controls
// installed below; MoonBit owns every public-API call and callback.

///|
suberror ViewZonesFixtureError {
  ViewZonesFixtureError(String)
}

///|
extern "js" fn record_view_zones_order(label : String) -> Unit =
  #| (label) => globalThis.__viewZonesOrder?.push(label)

///|
/// Captures the exact add-time onComputedHeight phase before ViewZones is
/// allowed to mutate or mount either caller-owned node.
extern "js" fn computed_height_phase_snapshot(
  node : @rdom.Element,
  margin : @rdom.Element,
) -> String =
  #| (node, margin) => JSON.stringify({
  #|   nodeConnected: node.isConnected,
  #|   nodeParent: node.parentNode !== null,
  #|   nodePosition: node.style.position,
  #|   nodeWidth: node.style.width,
  #|   nodeDisplay: node.style.display,
  #|   nodeTop: node.style.top,
  #|   nodeHeight: node.style.height,
  #|   nodeZoneAttr: node.getAttribute('monaco-view-zone'),
  #|   nodeVisibleAttr: node.getAttribute('monaco-visible-view-zone'),
  #|   marginConnected: margin.isConnected,
  #|   marginParent: margin.parentNode !== null,
  #|   marginPosition: margin.style.position,
  #|   marginWidth: margin.style.width,
  #|   marginDisplay: margin.style.display,
  #|   marginTop: margin.style.top,
  #|   marginHeight: margin.style.height,
  #|   marginZoneAttr: margin.getAttribute('monaco-view-zone'),
  #| })

///|
fn view_zones_source_with_line_count(line_count : Int) -> String {
  let text = StringBuilder()
  for line in 1..<=line_count {
    if line > 1 {
      text.write_char('\n')
    }
    text.write_string("view_zone_line_\{line}")
  }
  text.to_string()
}

///|
fn view_zones_source() -> String {
  view_zones_source_with_line_count(80)
}

///|
fn run_view_zones_test() -> Unit {
  let ctx = @support.BrowserTestContext("view_zones")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }

  let focus_sink = document.create_element("button")
  focus_sink.set_attribute("class", "view-zones-focus-sink")
  focus_sink.set_inner_html("outside focus sink")
  app.append_child(focus_sink.as_node())
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host view-zones-host")
  host.set_attribute("style", "height:260px;width:320px;")
  app.append_child(host.as_node())

  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/view-zones.txt",
  )
  let model = @model.TextModel(
    uri,
    "view-zones.txt",
    "plaintext",
    1,
    "view-zones-rev-1",
    view_zones_source(),
  )
  let memory = @log.MemoryLogger()
  let log_service = @log.LogService(level=Trace, logger=memory)
  let services = @viewer.ViewerServices(log_service=log_service.log_handle())
  let viewer = @viewer.Viewer::create(host, services~)
  let public_zone_events = Ref(0)
  let public_mouse_events = Ref(0)
  let public_mouse_target_id = Ref("")
  let public_mouse_target_kind = Ref("other")
  viewer.on_did_change_view_zones(() => {
    public_zone_events.val += 1
    record_view_zones_order("public")
  })
  |> ignore
  viewer.on_mouse_down(event => {
    public_mouse_events.val += 1
    match event.target {
      MouseTargetViewZone(type_~, detail~, ..) => {
        public_mouse_target_id.val = detail.view_zone_id
        public_mouse_target_kind.val = match type_ {
          ContentViewZone => "content"
          GutterViewZone => "gutter"
          _ => "other"
        }
      }
      _ => {
        public_mouse_target_id.val = ""
        public_mouse_target_kind.val = "other"
      }
    }
  })
  |> ignore
  @viewer_testing.on_did_render_model(viewer.get_id(), _ => {
    record_view_zones_order("rendered")
  })
  |> ignore
  viewer.set_model(Some(model))
  viewer.handle_initialized()

  let primary_node = document.create_element("div")
  primary_node.set_attribute("class", "vz-primary host-primary preserved-class")
  primary_node.set_attribute(
    "style", "color:rgb(1,2,3);border-left:3px solid rgb(4,5,6);padding-left:7px;position:relative;width:37px;display:inline;top:7px;height:9px;",
  )
  primary_node.set_attribute("data-caller-owned", "primary")
  let primary_child = document.create_element("span")
  primary_child.set_attribute("class", "vz-primary-child")
  primary_child.set_attribute("data-caller-state", "preserved")
  primary_child.set_inner_html("preserved descendant")
  primary_node.append_child(primary_child.as_node())
  let primary_margin = document.create_element("div")
  primary_margin.set_attribute(
    "class", "vz-primary-margin host-margin preserved-margin-class",
  )
  primary_margin.set_attribute(
    "style", "background-color:rgb(7,8,9);border-right:2px solid rgb(10,11,12);position:relative;width:19px;display:inline;top:4px;height:8px;",
  )
  primary_margin.set_attribute("data-caller-owned", "margin")
  primary_margin.set_inner_html("preserved margin content")

  let primary_top_count = Ref(0)
  let primary_last_top = Ref(-2000000.0)
  let primary_computed_count = Ref(0)
  let primary_computed_phase = Ref("")
  let primary = @viewer.view_zone(
    1,
    primary_node,
    ordinal=20,
    height_in_px=32.0,
    min_width_in_px=700.0,
    margin_dom_node=primary_margin,
    on_dom_node_top=top => {
      primary_top_count.val += 1
      primary_last_top.val = top
    },
    on_computed_height=_ => {
      primary_computed_count.val += 1
      if primary_computed_phase.val == "" {
        primary_computed_phase.val = computed_height_phase_snapshot(
          primary_node, primary_margin,
        )
      }
    },
  )

  let secondary_node = document.create_element("div")
  secondary_node.set_attribute("class", "vz-secondary")
  secondary_node.set_inner_html("same-anchor lower ordinal")
  let secondary = @viewer.view_zone(
    1,
    secondary_node,
    ordinal=-10,
    height_in_px=20.0,
  )

  let error_node = document.create_element("div")
  error_node.set_attribute("class", "vz-error")
  error_node.set_inner_html("throwing callbacks stay contained")
  let error_zone = @viewer.view_zone(
    2,
    error_node,
    height_in_px=18.0,
    on_dom_node_top=_ => raise ViewZonesFixtureError("top"),
    on_computed_height=_ => raise ViewZonesFixtureError("height"),
  )
  let safe_node = document.create_element("div")
  safe_node.set_attribute("class", "vz-safe")
  safe_node.set_inner_html("later callback and zone still render")
  let safe_top_count = Ref(0)
  let safe_zone = @viewer.view_zone(
    2,
    safe_node,
    ordinal=200,
    height_in_px=18.0,
    on_dom_node_top=_ => safe_top_count.val += 1,
  )

  let suppress_node = document.create_element("div")
  suppress_node.set_attribute("class", "vz-suppress")
  suppress_node.set_inner_html("suppress mouse down content")
  let suppress_margin = document.create_element("div")
  suppress_margin.set_attribute("class", "vz-suppress-margin")
  suppress_margin.set_inner_html("suppress mouse down gutter")
  let suppress_zone = @viewer.view_zone(
    3,
    suppress_node,
    ordinal=50,
    suppress_mouse_down=true,
    height_in_px=32.0,
    margin_dom_node=suppress_margin,
  )

  let omitted_node = document.create_element("div")
  omitted_node.set_attribute("class", "vz-omitted-suppress")
  omitted_node.set_inner_html("omitted suppress mouse down")
  let omitted_zone = @viewer.view_zone(0, omitted_node, height_in_px=24.0)

  let line_height_node = document.create_element("div")
  line_height_node.set_attribute("class", "vz-line-height")
  line_height_node.set_inner_html("height in lines follows line height")
  let line_height_computed_count = Ref(0)
  let line_height_last_computed = Ref(-1.0)
  let line_height_zone = @viewer.view_zone(
    7,
    line_height_node,
    height_in_lines=1.5,
    on_computed_height=height => {
      line_height_computed_count.val += 1
      line_height_last_computed.val = height
      record_view_zones_order("computed:line-height")
    },
  )

  let negative_zero_node = document.create_element("div")
  negative_zero_node.set_attribute("class", "vz-negative-zero")
  let negative_zero_callback_preserved = Ref(false)
  let negative_zero_zone = @viewer.view_zone(
    0,
    negative_zero_node,
    height_in_px=-0.0,
    on_computed_height=height => {
      negative_zero_callback_preserved.val = (1.0 / height).is_neg_inf()
    },
  )

  let offscreen_node = document.create_element("div")
  offscreen_node.set_attribute("class", "vz-offscreen")
  offscreen_node.set_inner_html("offscreen view zone")
  let offscreen_top_count = Ref(0)
  let offscreen_last_top = Ref(-2000000.0)
  let offscreen_zone = @viewer.view_zone(
    40,
    offscreen_node,
    height_in_px=28.0,
    on_dom_node_top=top => {
      offscreen_top_count.val += 1
      offscreen_last_top.val = top
    },
  )

  let invalid_node = document.create_element("div")
  invalid_node.set_attribute("class", "vz-invalid-add-should-stay-detached")
  let invalid_zone = @viewer.view_zone(1, invalid_node, height_in_px=11.0)

  let primary_id = Ref("")
  let initial_primary_id = Ref("")
  let secondary_id = Ref("")
  let error_id = Ref("")
  let safe_id = Ref("")
  let suppress_id = Ref("")
  let omitted_id = Ref("")
  let line_height_id = Ref("")
  let negative_zero_id = Ref("")
  let offscreen_id = Ref("")
  let retained_normal_add : Ref[(() -> Unit)?] = Ref(None)
  let retained_normal_remove : Ref[(() -> Unit)?] = Ref(None)
  let retained_normal_layout : Ref[(() -> Unit)?] = Ref(None)
  viewer.change_view_zones(accessor => {
    retained_normal_add.val = Some(() => {
      accessor.add_zone(invalid_zone) |> ignore
    })
    retained_normal_remove.val = Some(() => accessor.remove_zone(primary_id.val))
    retained_normal_layout.val = Some(() => accessor.layout_zone(primary_id.val))
    primary_id.val = accessor.add_zone(primary)
    initial_primary_id.val = primary_id.val
    secondary_id.val = accessor.add_zone(secondary)
    error_id.val = accessor.add_zone(error_zone)
    safe_id.val = accessor.add_zone(safe_zone)
    suppress_id.val = accessor.add_zone(suppress_zone)
    omitted_id.val = accessor.add_zone(omitted_zone)
    line_height_id.val = accessor.add_zone(line_height_zone)
    negative_zero_id.val = accessor.add_zone(negative_zero_zone)
    offscreen_id.val = accessor.add_zone(offscreen_zone)
  })

  let replacement_node = document.create_element("div")
  replacement_node.set_attribute("class", "vz-replacement-should-stay-detached")
  let replacement_margin = document.create_element("div")
  replacement_margin.set_attribute(
    "class", "vz-margin-replacement-should-stay-detached",
  )
  let retained_throwing_add : Ref[(() -> Unit)?] = Ref(None)
  let retained_throwing_remove : Ref[(() -> Unit)?] = Ref(None)
  let retained_throwing_layout : Ref[(() -> Unit)?] = Ref(None)
  let ordered_node = document.create_element("div")
  ordered_node.set_attribute("class", "vz-ordered-throw")
  ordered_node.set_inner_html("throw-after-add still commits")
  let ordered_id = Ref("")
  let ordered_zone = @viewer.view_zone(
    6,
    ordered_node,
    height_in_px=21.0,
    on_computed_height=_ => record_view_zones_order("computed:add"),
    on_dom_node_top=_ => record_view_zones_order("top:add"),
  )

  let rail_spacer_node = document.create_element("div")
  rail_spacer_node.set_attribute("class", "vz-rail-spacer")
  let rail_target_node = document.create_element("div")
  rail_target_node.set_attribute("class", "vz-rail-target")
  rail_target_node.set_inner_html("big-number rail target")
  let rail_spacer_id = Ref("")
  let rail_target_id = Ref("")
  let rail_top_count = Ref(0)
  let rail_last_top = Ref(-2000000.0)
  let rail_spacer_zone = @viewer.view_zone(
    0,
    rail_spacer_node,
    ordinal=-1000000,
    height_in_px=500001.0,
  )
  let rail_target_zone = @viewer.view_zone(
    1,
    rail_target_node,
    ordinal=-1000000,
    height_in_px=20.0,
    on_dom_node_top=top => {
      rail_top_count.val += 1
      rail_last_top.val = top
    },
  )
  let post_dispose_node = document.create_element("div")
  post_dispose_node.set_attribute("class", "vz-post-dispose")
  let post_dispose_zone = @viewer.view_zone(
    1,
    post_dispose_node,
    height_in_px=10.0,
  )
  let post_dispose_callback_count = Ref(0)
  let post_dispose_id = Ref("")

  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("missing live View root")
    ctx.finish()
    return
  }
  install_view_zones_controls(
    root,
    focus_sink,
    primary_node,
    primary_child,
    primary_margin,
    replacement_node,
    replacement_margin,
    invalid_node,
    () => {
      let layout = viewer.get_layout_info()
      Json::object({
        "initialPrimaryId": initial_primary_id.val.to_json(),
        "primaryId": primary_id.val.to_json(),
        "secondaryId": secondary_id.val.to_json(),
        "errorId": error_id.val.to_json(),
        "safeId": safe_id.val.to_json(),
        "suppressId": suppress_id.val.to_json(),
        "omittedId": omitted_id.val.to_json(),
        "lineHeightId": line_height_id.val.to_json(),
        "negativeZeroId": negative_zero_id.val.to_json(),
        "negativeZeroCallbackPreserved": negative_zero_callback_preserved.val.to_json(),
        "offscreenId": offscreen_id.val.to_json(),
        "orderedId": ordered_id.val.to_json(),
        "zoneEvents": public_zone_events.val.to_json(),
        "mouseEvents": public_mouse_events.val.to_json(),
        "mouseTargetId": public_mouse_target_id.val.to_json(),
        "mouseTargetKind": public_mouse_target_kind.val.to_json(),
        "primaryTopCount": primary_top_count.val.to_json(),
        "primaryLastTop": Json::number(primary_last_top.val),
        "primaryComputedCount": primary_computed_count.val.to_json(),
        "primaryComputedPhase": primary_computed_phase.val.to_json(),
        "safeTopCount": safe_top_count.val.to_json(),
        "lineHeightComputedCount": line_height_computed_count.val.to_json(),
        "lineHeightLastComputed": Json::number(line_height_last_computed.val),
        "lineHeight": Json::number(viewer.get_options().line_height()),
        "offscreenTopCount": offscreen_top_count.val.to_json(),
        "offscreenLastTop": Json::number(offscreen_last_top.val),
        "railSpacerId": rail_spacer_id.val.to_json(),
        "railTargetId": rail_target_id.val.to_json(),
        "railTopCount": rail_top_count.val.to_json(),
        "railLastTop": Json::number(rail_last_top.val),
        "postDisposeCallbackCount": post_dispose_callback_count.val.to_json(),
        "postDisposeId": post_dispose_id.val.to_json(),
        "modelLineCount": model.get_line_count().to_json(),
        "hasViewDom": (viewer.get_dom_node() is Some(_)).to_json(),
        "scrollTop": Json::number(viewer.get_scroll_top()),
        "scrollWidth": Json::number(viewer.get_scroll_width()),
        "contentWidth": Json::number(viewer.get_content_width()),
        "contentLeft": Json::number(layout.content_left),
        "layoutContentWidth": Json::number(layout.content_width),
        "logs": Json::array(
          memory
          .entries()
          .map(entry => {
            Json::object({
              "category": entry.category.to_json(),
              "message": entry.message.to_json(),
            })
          }),
        ),
      }).stringify()
    },
    () => {
      viewer.change_view_zones(_ => record_view_zones_order("callback:noop"))
    },
    () => {
      viewer.change_view_zones(accessor => {
        record_view_zones_order("callback:empty-remove")
        accessor.remove_zone("")
      })
    },
    () => {
      viewer.change_view_zones(accessor => {
        record_view_zones_order("callback:missing-layout")
        accessor.layout_zone("missing-view-zone-id")
      })
    },
    () => {
      viewer.change_view_zones(accessor => {
        retained_throwing_add.val = Some(() => {
          accessor.add_zone(invalid_zone) |> ignore
        })
        retained_throwing_remove.val = Some(() => {
          accessor.remove_zone(primary_id.val)
        })
        retained_throwing_layout.val = Some(() => {
          accessor.layout_zone(primary_id.val)
        })
        record_view_zones_order("callback:throw-noop")
        raise ViewZonesFixtureError("throw-noop")
      })
    },
    () => {
      primary.after_line_number = 1
      primary.height_in_px = Some(36.0)
      primary.min_width_in_px = Some(20.0)
      primary.ordinal = Some(-1000)
      primary.dom_node = replacement_node
      primary.margin_dom_node = Some(replacement_margin)
      primary.on_dom_node_top = Some(top => {
        primary_top_count.val += 1
        primary_last_top.val = top
        record_view_zones_order("top:layout")
      })
      viewer.change_view_zones(accessor => accessor.layout_zone(primary_id.val))
    },
    () => {
      viewer.change_view_zones(accessor => accessor.remove_zone(primary_id.val))
    },
    () => {
      primary.dom_node = primary_node
      primary.margin_dom_node = Some(primary_margin)
      viewer.change_view_zones(accessor => {
        primary_id.val = accessor.add_zone(primary)
      })
    },
    () => {
      match retained_normal_add.val {
        Some(operation) => operation()
        None => ()
      }
    },
    () => {
      match retained_normal_remove.val {
        Some(operation) => operation()
        None => ()
      }
    },
    () => {
      match retained_normal_layout.val {
        Some(operation) => operation()
        None => ()
      }
    },
    () => {
      match retained_throwing_add.val {
        Some(operation) => operation()
        None => ()
      }
    },
    () => {
      match retained_throwing_remove.val {
        Some(operation) => operation()
        None => ()
      }
    },
    () => {
      match retained_throwing_layout.val {
        Some(operation) => operation()
        None => ()
      }
    },
    () => {
      viewer.change_view_zones(accessor => {
        retained_throwing_add.val = Some(() => {
          accessor.add_zone(invalid_zone) |> ignore
        })
        retained_throwing_remove.val = Some(() => {
          accessor.remove_zone(primary_id.val)
        })
        retained_throwing_layout.val = Some(() => {
          accessor.layout_zone(primary_id.val)
        })
        record_view_zones_order("callback:add")
        ordered_id.val = accessor.add_zone(ordered_zone)
        record_view_zones_order("callback:throw-after-add")
        raise ViewZonesFixtureError("throw-after-add")
      })
    },
    scroll_top => viewer.set_scroll_top(scroll_top),
    () => {
      let top = viewer.get_top_for_line_number(40, include_view_zones=true)
      viewer.set_scroll_top(top)
    },
    suppress => suppress_zone.suppress_mouse_down = Some(suppress),
    line_height => {
      let options = viewer.get_options()
      viewer.update_options(options.with_line_height(line_height))
    },
    suppress => primary.suppress_mouse_down = Some(suppress),
    () => {
      if rail_target_id.val == "" {
        viewer.change_view_zones(accessor => {
          rail_spacer_id.val = accessor.add_zone(rail_spacer_zone)
          rail_target_id.val = accessor.add_zone(rail_target_zone)
        })
      }
      viewer.set_scroll_top(viewer.get_top_for_line_number(1))
    },
    line_count => model.set_value(view_zones_source_with_line_count(line_count)),
    () => {
      viewer.dispose()
      services.dispose()
    },
    () => model.dispose(),
    () => {
      viewer.change_view_zones(accessor => {
        post_dispose_callback_count.val += 1
        post_dispose_id.val = accessor.add_zone(post_dispose_zone)
      })
    },
  )
  poll_view_zones_ready(ctx, 120)
}

///|
fn poll_view_zones_ready(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  let primary_visible = @support.query_count(
      ".view-zones-host .vz-primary[monaco-visible-view-zone]",
    ) ==
    1
  let safe_visible = @support.query_count(
      ".view-zones-host .vz-safe[monaco-visible-view-zone]",
    ) ==
    1
  let controls_ready = view_zones_controls_installed()
  if primary_visible && safe_visible && controls_ready {
    ctx.metric_int(
      "registeredZones",
      @support.query_count(".view-zones-host [monaco-view-zone]"),
    )
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for ViewZones fixture")
    ctx.finish()
  } else {
    @support.set_timeout(() => poll_view_zones_ready(ctx, remaining - 1), 30)
  }
}

///|
extern "js" fn view_zones_controls_installed() -> Bool =
  #| () => Boolean(globalThis.__viewZonesControls)

///|
extern "js" fn install_view_zones_controls(
  root : @rdom.Element,
  focus_sink : @rdom.Element,
  primary : @rdom.Element,
  primary_child : @rdom.Element,
  primary_margin : @rdom.Element,
  replacement : @rdom.Element,
  replacement_margin : @rdom.Element,
  invalid_node : @rdom.Element,
  state_json : () -> String,
  noop : () -> Unit,
  empty_remove : () -> Unit,
  missing_layout : () -> Unit,
  throw_noop : () -> Unit,
  layout_primary : () -> Unit,
  remove_primary : () -> Unit,
  readd_primary : () -> Unit,
  invalid_normal_add : () -> Unit,
  invalid_normal_remove : () -> Unit,
  invalid_normal_layout : () -> Unit,
  invalid_throw_add : () -> Unit,
  invalid_throw_remove : () -> Unit,
  invalid_throw_layout : () -> Unit,
  add_then_throw : () -> Unit,
  set_scroll_top : (Double) -> Unit,
  show_offscreen : () -> Unit,
  set_suppress : (Bool) -> Unit,
  set_line_height : (Double) -> Unit,
  set_primary_suppress : (Bool) -> Unit,
  enable_rail : () -> Unit,
  set_model_line_count : (Int) -> Unit,
  dispose_viewer : () -> Unit,
  dispose_model : () -> Unit,
  probe_after_dispose : () -> Unit,
) -> Unit =
  #| (root, focusSink, primary, primaryChild, primaryMargin, replacement,
  #|  replacementMargin, invalidNode, stateJson, noop, emptyRemove,
  #|  missingLayout, throwNoop,
  #|  layoutPrimary, removePrimary, readdPrimary, invalidNormalAdd,
  #|  invalidNormalRemove, invalidNormalLayout, invalidThrowAdd,
  #|  invalidThrowRemove, invalidThrowLayout, addThenThrow, setScrollTop,
  #|  showOffscreen, setSuppress, setLineHeight, setPrimarySuppress,
  #|  enableRail, setModelLineCount, disposeViewer, disposeModel,
  #|  probeAfterDispose) => {
  #|   primary.__callerState = { retained: true };
  #|   primaryChild.__callerState = { retained: true };
  #|   primaryMargin.__callerState = { retained: true };
  #|   let primaryClicks = 0;
  #|   let childClicks = 0;
  #|   let marginClicks = 0;
  #|   primary.addEventListener('click', () => { primaryClicks += 1; });
  #|   primaryChild.addEventListener('click', () => { childClicks += 1; });
  #|   primaryMargin.addEventListener('click', () => { marginClicks += 1; });
  #|   const mouseRecords = [];
  #|   root.addEventListener('mousedown', (event) => {
  #|     const zone = event.target.closest?.('[monaco-view-zone]');
  #|     mouseRecords.push({
  #|       button: event.button,
  #|       defaultPrevented: event.defaultPrevented,
  #|       activeRoot: document.activeElement === root,
  #|       zoneId: zone?.getAttribute('monaco-view-zone') ?? '',
  #|       margin: Boolean(zone?.closest('.margin-view-zones')),
  #|     });
  #|   });
  #|   const invalidActions = {
  #|     normalAdd: invalidNormalAdd,
  #|     normalRemove: invalidNormalRemove,
  #|     normalLayout: invalidNormalLayout,
  #|     throwAdd: invalidThrowAdd,
  #|     throwRemove: invalidThrowRemove,
  #|     throwLayout: invalidThrowLayout,
  #|   };
  #|   let originalRequestAnimationFrame = null;
  #|   const stopOrderProbe = () => {
  #|     const result = [...(globalThis.__viewZonesOrder ?? [])];
  #|     if (originalRequestAnimationFrame) {
  #|       globalThis.requestAnimationFrame = originalRequestAnimationFrame;
  #|       originalRequestAnimationFrame = null;
  #|     }
  #|     return result;
  #|   };
  #|   globalThis.__viewZonesControls = {
  #|     root,
  #|     originalPrimary: primary,
  #|     originalPrimaryChild: primaryChild,
  #|     originalPrimaryMargin: primaryMargin,
  #|     replacement,
  #|     replacementMargin,
  #|     invalidNode,
  #|     state: () => JSON.parse(stateJson()),
  #|     noop,
  #|     empty_remove: emptyRemove,
  #|     missing_layout: missingLayout,
  #|     throw_noop: throwNoop,
  #|     layout_primary: layoutPrimary,
  #|     remove_primary: removePrimary,
  #|     readd_primary: readdPrimary,
  #|     add_then_throw: addThenThrow,
  #|     set_scroll_top: setScrollTop,
  #|     show_offscreen: showOffscreen,
  #|     set_suppress: setSuppress,
  #|     set_line_height: setLineHeight,
  #|     set_primary_suppress: setPrimarySuppress,
  #|     enable_rail: enableRail,
  #|     set_model_line_count: setModelLineCount,
  #|     dispose_viewer: disposeViewer,
  #|     dispose_model: disposeModel,
  #|     probe_after_dispose: probeAfterDispose,
  #|     focus_sink: () => focusSink.focus(),
  #|     clear_mouse: () => { mouseRecords.length = 0; },
  #|     mouse_records: () => [...mouseRecords],
  #|     click_counts: () => ({ primary: primaryClicks, child: childClicks, margin: marginClicks }),
  #|     click_original_child: () => primaryChild.dispatchEvent(new MouseEvent('click', { bubbles: true })),
  #|     click_original_margin: () => primaryMargin.dispatchEvent(new MouseEvent('click', { bubbles: true })),
  #|     identity: () => ({
  #|       primary: document.querySelector('.vz-primary') === primary,
  #|       child: primary.querySelector('.vz-primary-child') === primaryChild,
  #|       margin: document.querySelector('.vz-primary-margin') === primaryMargin,
  #|       primaryState: primary.__callerState?.retained === true,
  #|       childState: primaryChild.__callerState?.retained === true,
  #|       marginState: primaryMargin.__callerState?.retained === true,
  #|       replacementConnected: replacement.isConnected,
  #|       replacementMarginConnected: replacementMargin.isConnected,
  #|       invalidConnected: invalidNode.isConnected,
  #|     }),
  #|     invoke_invalid: (name) => {
  #|       try {
  #|         invalidActions[name]();
  #|         return { name, thrown: false, message: null };
  #|       } catch (error) {
  #|         return { name, thrown: true, message: String(error?.message ?? error) };
  #|       }
  #|     },
  #|     start_order_probe: () => {
  #|       if (originalRequestAnimationFrame) stopOrderProbe();
  #|       globalThis.__viewZonesOrder = [];
  #|       originalRequestAnimationFrame = globalThis.requestAnimationFrame;
  #|       globalThis.requestAnimationFrame = (callback) => {
  #|         globalThis.__viewZonesOrder.push('raf-request');
  #|         return originalRequestAnimationFrame(callback);
  #|       };
  #|     },
  #|     stop_order_probe: stopOrderProbe,
  #|   };
  #| }
