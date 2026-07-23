///|
/// Closed event-receipt capability index. The order of the array built by
/// `default_view_event_handlers` mirrors the source `ViewContext` registration
/// order; each variant holds the same stateful value used by the ordinary
/// render-part index where that capability applies.
priv enum ViewEventHandlerHandle {
  ViewLinesHandler(ViewLines)
  ViewZonesHandler(ViewZones)
  ContentViewOverlaysHandler(ContentViewOverlays)
  MarginViewOverlaysHandler(MarginViewOverlays)
  ContentWidgetsHandler(ContentWidgets)
  ViewCursorsHandler(ViewCursors)
  OverlayWidgetsHandler(OverlayWidgets)
  EditorScrollbarHandler(EditorScrollbar)
}

///|
/// Closed ordinary render-part capability index. `ViewLines` is deliberately
/// absent because its source lifecycle is the dedicated `renderText` path.
priv enum ViewPartHandle {
  ViewZonesPart(ViewZones)
  ContentViewOverlaysPart(ContentViewOverlays)
  MarginViewOverlaysPart(MarginViewOverlays)
  ContentWidgetsPart(ContentWidgets)
  ViewCursorsPart(ViewCursors)
  OverlayWidgetsPart(OverlayWidgets)
  EditorScrollbarPart(EditorScrollbar)
}

///|
/// Capability-minimal form of `ViewEventHandler.handleEvents`: visit the full
/// batch in FIFO order, OR invalidation decisions, then force dirtiness once.
fn handle_view_event_batch(
  events : Array[ViewEvent],
  on_event : (ViewEvent) -> Bool,
  force_dirty : () -> Unit,
) -> Unit {
  let mut should_render = false
  for event in events {
    if on_event(event) {
      should_render = true
    }
  }
  if should_render {
    force_dirty()
  }
}

///|
fn ViewEventHandlerHandle::handle_view_events(
  self : ViewEventHandlerHandle,
  events : Array[ViewEvent],
) -> Unit {
  handle_view_event_batch(events, event => self.on_view_event(event), () => {
    self.force_should_render()
  })
}

///|
fn ViewEventHandlerHandle::on_view_event(
  self : ViewEventHandlerHandle,
  event : ViewEvent,
) -> Bool {
  match self {
    ViewLinesHandler(part) => view_lines_on_view_event(part, event)
    ViewZonesHandler(part) => view_zones_on_view_event(part, event)
    ContentViewOverlaysHandler(part) =>
      content_view_overlays_on_view_event(part, event)
    MarginViewOverlaysHandler(part) =>
      margin_view_overlays_on_view_event(part, event)
    ContentWidgetsHandler(part) => content_widgets_on_view_event(part, event)
    ViewCursorsHandler(part) => view_cursors_on_view_event(part, event)
    OverlayWidgetsHandler(part) => overlay_widgets_on_view_event(part, event)
    EditorScrollbarHandler(part) => editor_scrollbar_on_view_event(part, event)
  }
}

///|
fn ViewEventHandlerHandle::force_should_render(
  self : ViewEventHandlerHandle,
) -> Unit {
  match self {
    ViewLinesHandler(part) => part.should_render = true
    ViewZonesHandler(part) => part.force_should_render()
    ContentViewOverlaysHandler(part) => part.should_render = true
    MarginViewOverlaysHandler(part) => part.should_render = true
    ContentWidgetsHandler(part) => part.should_render = true
    ViewCursorsHandler(part) => part.should_render = true
    OverlayWidgetsHandler(part) => part.should_render = true
    EditorScrollbarHandler(part) => part.should_render = true
  }
}

///|
/// View-owned teardown (`view.ts:503-519`). ViewLines cancels its delayed
/// width sweep first; the resource-free DOM parts need no active teardown,
/// and the scrollbar cancels its hide timer here.
fn ViewPartHandle::dispose(self : ViewPartHandle) -> Unit {
  match self {
    ViewZonesPart(part) => part.dispose()
    ContentViewOverlaysPart(_) => ()
    MarginViewOverlaysPart(_) => ()
    ContentWidgetsPart(_) => ()
    ViewCursorsPart(_) => ()
    OverlayWidgetsPart(_) => ()
    EditorScrollbarPart(part) => part.scrollable().dispose()
  }
}

///|
/// Source `ViewPart.onBeforeRender` phase. Only ContentWidgets owns scoped
/// behavior here; the other retained viewer parts have no applicable pre-text
/// writes in this parity slice.
fn ViewPartHandle::on_before_render(
  self : ViewPartHandle,
  viewport : @view_layout.ViewportData,
) -> Unit {
  match self {
    ContentWidgetsPart(part) =>
      part.on_before_render_widgets(
        viewport.start_line_number,
        viewport.end_line_number,
      )
    _ => ()
  }
}

///|
fn default_view_parts(
  view_zones : ViewZones,
  content_view_overlays : ContentViewOverlays,
  margin_view_overlays : MarginViewOverlays,
  content_widgets : ContentWidgets,
  view_cursors : ViewCursors,
  overlay_widgets : OverlayWidgets,
  editor_scrollbar : EditorScrollbar,
) -> Array[ViewPartHandle] {
  [
    ViewZonesPart(view_zones),
    ContentViewOverlaysPart(content_view_overlays),
    MarginViewOverlaysPart(margin_view_overlays),
    ContentWidgetsPart(content_widgets),
    // Monaco pushes `viewCursors` after content widgets, before overlay
    // widgets (`view.ts:246-252`).
    ViewCursorsPart(view_cursors),
    OverlayWidgetsPart(overlay_widgets),
    EditorScrollbarPart(editor_scrollbar),
  ]
}

///|
fn default_view_event_handlers(
  view_lines : ViewLines,
  view_zones : ViewZones,
  content_view_overlays : ContentViewOverlays,
  margin_view_overlays : MarginViewOverlays,
  content_widgets : ContentWidgets,
  view_cursors : ViewCursors,
  overlay_widgets : OverlayWidgets,
  editor_scrollbar : EditorScrollbar,
) -> Array[ViewEventHandlerHandle] {
  [
    ViewLinesHandler(view_lines),
    ViewZonesHandler(view_zones),
    ContentViewOverlaysHandler(content_view_overlays),
    MarginViewOverlaysHandler(margin_view_overlays),
    ContentWidgetsHandler(content_widgets),
    // Monaco registers `viewCursors` after content widgets and before overlay
    // widgets (`view.ts:246-252`).
    ViewCursorsHandler(view_cursors),
    OverlayWidgetsHandler(overlay_widgets),
    EditorScrollbarHandler(editor_scrollbar),
  ]
}

///|
fn ViewPartHandle::should_render(self : ViewPartHandle) -> Bool {
  match self {
    ViewZonesPart(part) => part.should_render()
    ContentViewOverlaysPart(part) => part.should_render
    MarginViewOverlaysPart(part) => part.should_render
    ContentWidgetsPart(part) => part.should_render
    ViewCursorsPart(part) => part.should_render
    OverlayWidgetsPart(part) => part.should_render
    EditorScrollbarPart(part) => part.should_render
  }
}

///|
fn ViewPartHandle::prepare_render(
  self : ViewPartHandle,
  context : RenderingContext,
) -> Unit {
  match self {
    ViewZonesPart(part) => view_zones_prepare_render(part, context)
    ContentViewOverlaysPart(part) =>
      content_view_overlays_prepare_render(part, context)
    MarginViewOverlaysPart(part) =>
      margin_view_overlays_prepare_render(part, context)
    ContentWidgetsPart(part) => content_widgets_prepare_render(part, context)
    ViewCursorsPart(part) => view_cursors_prepare_render(part, context)
    OverlayWidgetsPart(part) => overlay_widgets_prepare_render(part, context)
    EditorScrollbarPart(part) => editor_scrollbar_prepare_render(part, context)
  }
}

///|
fn ViewPartHandle::render(
  self : ViewPartHandle,
  context : RestrictedRenderingContext,
) -> Unit {
  match self {
    ViewZonesPart(part) => view_zones_render(part, context)
    ContentViewOverlaysPart(part) => content_view_overlays_render(part, context)
    MarginViewOverlaysPart(part) => margin_view_overlays_render(part, context)
    ContentWidgetsPart(part) => content_widgets_render(part, context)
    ViewCursorsPart(part) => view_cursors_render(part, context)
    OverlayWidgetsPart(part) => overlay_widgets_render(part, context)
    EditorScrollbarPart(part) => editor_scrollbar_render(part, context)
  }
}

///|
fn ViewPartHandle::on_did_render(self : ViewPartHandle) -> Unit {
  match self {
    ViewZonesPart(part) => part.did_render()
    ContentViewOverlaysPart(part) => part.should_render = false
    MarginViewOverlaysPart(part) => part.should_render = false
    ContentWidgetsPart(part) => part.should_render = false
    ViewCursorsPart(part) => part.should_render = false
    OverlayWidgetsPart(part) => part.should_render = false
    EditorScrollbarPart(part) => part.should_render = false
  }
}
