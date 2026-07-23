// Public mouse events — Monaco `ICodeEditor.onMouseDown` / `onMouseUp` /
// `onMouseMove` / `onMouseLeave` (`codeEditorWidget.ts:161-186`), fed by the
// controller's emit seams below (Monaco's `ViewController.emit*` →
// `ViewUserInputEvents` → widget re-emission collapses into these methods —
// the viewer's emitters play `ViewUserInputEvents`' callback role). Targets
// are converted to **model** coordinates at this boundary
// (`convertViewToModelMouseTarget`), exactly like the source.
//
// The canonical hit-tested wrappers live in `viewer/browser`; the raw
// `editorDom.ts` event there is named `EditorDomMouseEvent`.
//
// Omissions: `onMouseDrag`/`onMouseDrop`/`onMouseDropCanceled` (drag-and-drop
// text move is not ported), `onContextMenu`, `onMouseWheel` — no consumers.

///|
/// Fires on editor mousedown with the hit-tested target — Monaco's
/// `onMouseDown`.
pub fn Viewer::on_mouse_down(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_down.event(listener)
}

///|
/// Fires on editor mouseup with the hit-tested target — Monaco's
/// `onMouseUp`.
pub fn Viewer::on_mouse_up(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_up.event(listener)
}

///|
/// Fires on editor mousemove with the hit-tested target — Monaco's
/// `onMouseMove`.
pub fn Viewer::on_mouse_move(
  self : Viewer,
  listener : (@editor_browser.EditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_move.event(listener)
}

///|
/// Fires when the pointer leaves the editor — Monaco's `onMouseLeave`
/// (`IPartialEditorMouseEvent`; the target is always `None` for leaves).
pub fn Viewer::on_mouse_leave(
  self : Viewer,
  listener : (@editor_browser.PartialEditorMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_mouse_leave.event(listener)
}

///|
/// The view→model target conversion applied at the public boundary —
/// `ViewUserInputEvents._convertViewToModelMouseEvent`.
fn Viewer::convert_mouse_target(
  self : Viewer,
  target : @editor_browser.MouseTarget,
) -> @editor_browser.MouseTarget {
  match self.get_view_model() {
    Some(view_model) =>
      @view.convert_view_to_model_mouse_target(
        target,
        view_model.coordinates_converter(),
      )
    None => target
  }
}

///|
/// `ViewUserInputEvents.emitMouseDown` → public event, then the hover
/// controller's `_onEditorMouseDown` (its subscription in the source).
fn Viewer::emit_mouse_down(
  self : Viewer,
  event : @editor_browser.EditorDomMouseEvent,
  target : @editor_browser.MouseTarget,
) -> Unit {
  self.did_mouse_down.fire({ event, target: self.convert_mouse_target(target) })
  // The hover measures its widget with `getBoundingClientRect`, so it reads
  // client coordinates (the recorded deviation on client- vs page-space).
  let client = event.pos.to_client_coordinates()
  self.on_editor_mouse_down(client.client_x, client.client_y)
}

///|
/// `ViewUserInputEvents.emitMouseUp` → public event.
fn Viewer::emit_mouse_up(
  self : Viewer,
  event : @editor_browser.EditorDomMouseEvent,
  target : @editor_browser.MouseTarget,
) -> Unit {
  self.did_mouse_up.fire({ event, target: self.convert_mouse_target(target) })
  self.on_editor_mouse_up()
}

///|
/// `ViewUserInputEvents.emitMouseMove` → public event, then the hover
/// controller's `_onEditorMouseMove`.
fn Viewer::emit_mouse_move(
  self : Viewer,
  event : @editor_browser.EditorDomMouseEvent,
  target : @editor_browser.MouseTarget,
) -> Unit {
  let converted = self.convert_mouse_target(target)
  self.did_mouse_move.fire({ event, target: converted })
  let client = event.pos.to_client_coordinates()
  self.record_hover_pointer(client.client_x, client.client_y, {
    ctrl: event.ctrl_key,
    meta: event.meta_key,
    alt: event.alt_key,
  })
  self.on_editor_mouse_move(converted)
}

///|
/// `ViewUserInputEvents.emitMouseDrag`. The drag events have no public
/// consumers (header); the hover keeps tracking the pointer during drags the
/// way Monaco's controller ignores them (`_mouseDown` guard N-A here).
fn Viewer::emit_mouse_drag(
  self : Viewer,
  _event : @editor_browser.EditorDomMouseEvent,
  _target : @editor_browser.MouseTarget,
) -> Unit {
  ignore(self)
}

///|
/// `ViewUserInputEvents.emitMouseLeave` → public event, then the hover
/// controller's `_onEditorMouseLeave`.
fn Viewer::emit_mouse_leave(
  self : Viewer,
  event : @editor_browser.EditorDomMouseEvent,
) -> Unit {
  self.did_mouse_leave.fire({ event, target: None })
  let client = event.pos.to_client_coordinates()
  self.on_editor_mouse_leave(client.client_x, client.client_y)
}
