// The viewer core's side of the `internal/viewer/browser/controller` seam: it
// builds the input controller's `PointerHandlerHelper`, the local analog of
// Monaco's `View._createPointerHandlerHelper` (view.ts:378-429) plus the
// `ViewContext`/`ViewController` reads the helper substitutes for (the
// helper's header in `mouse_handler.mbt` records the grouping). The closures
// capture the view and the viewer so the controller never names the concrete
// `View`/`Viewer`.

///|
fn Viewer::pointer_handler_helper(
  self : Viewer,
  view : @view.View,
) -> @controller.PointerHandlerHelper {
  {
    // --- IPointerHandlerHelper members ---
    view_dom_node: view.root,
    lines_content_dom_node: view.editor_scrollbar.content(),
    view_lines_dom_node: view.view_lines.get_dom_node(),
    // No textarea part: the root section is the focusable surface
    // (mouse_handler.mbt header).
    focus_text_area: () => @base_browser.focus_prevent_scroll(view.root),
    get_last_render_data: () => {
      last_view_cursors_render_data: view.view_cursors.get_last_render_data(),
    },
    render_now: () => self.flush_render(),
    should_suppress_mouse_down_on_view_zone: id => {
      view.should_suppress_mouse_down_on_view_zone(id)
    },
    get_position_from_dom_info: (span_node, offset) => {
      match self.get_view_model() {
        Some(view_model) =>
          view.view_lines.get_position_from_dom_info(
            view_model, span_node, offset,
          )
        None => None
      }
    },
    visible_range_for_position: (line_number, column) => {
      view.visible_range_for_position(line_number, column)
    },
    get_line_width: line_number => view.view_lines.get_line_width(line_number),
    // --- ViewContext substitutes ---
    view_model: () => self.get_view_model(),
    get_layout_info: () => self.get_layout_info(),
    get_font_info: () => self.configuration.snapshot().font_info,
    get_current_selection: () => self.view_selection(),
    // --- ViewController substitutes ---
    dispatch_mouse: data => self.dispatch_mouse(data),
    emit_mouse_down: (event, target) => self.emit_mouse_down(event, target),
    emit_mouse_up: (event, target) => self.emit_mouse_up(event, target),
    emit_mouse_move: (event, target) => self.emit_mouse_move(event, target),
    emit_mouse_drag: (event, target) => self.emit_mouse_drag(event, target),
    emit_mouse_leave: event => self.emit_mouse_leave(event),
    // --- retained viewer scroll seams ---
    overflow_guard: view.overflow_guard,
    editor_scrollable: view.editor_scrollbar.scrollable(),
    hover_scrollable: () => {
      match self.content_hover_contribution() {
        Some(state) =>
          match state.widget {
            Some(widget) => Some(widget.scrollable)
            None => None
          }
        None => None
      }
    },
    view_layout: () => {
      match self.get_view_model() {
        Some(view_model) => Some(view_model.view_layout)
        None => None
      }
    },
    schedule_render: () => self.schedule_render(),
  }
}

///|
/// Cancels an in-progress mouse selection on viewer lifecycle resets (model
/// change/clear). No-op before the view (and its controller) exist.
fn Viewer::cancel_mouse_selection(self : Viewer) -> Unit {
  match self.current_browser_data() {
    Some(browser) => browser.cancel_mouse_selection()
    None => ()
  }
}
