///|
test "AbstractScrollbar Windows orthogonal reset uses strict greater than 140" {
  @base_common.set_is_windows_for_testing(value=true)
  assert_false(scrollbar_drag_should_reset(10.0, 149.0))
  assert_false(scrollbar_drag_should_reset(10.0, 150.0))
  assert_true(scrollbar_drag_should_reset(10.0, 151.0))
  assert_false(scrollbar_drag_should_reset(150.0, 10.0))
  assert_true(scrollbar_drag_should_reset(151.0, 10.0))

  @base_common.set_is_windows_for_testing(value=false)
  assert_false(scrollbar_drag_should_reset(10.0, 151.0))
  @base_common.set_is_windows_for_testing()
}

///|
extern "js" fn install_scrollbar_input_test_browser() -> Unit =
  #| () => {
  #|   class TrackingTarget extends EventTarget {
  #|     constructor() {
  #|       super();
  #|       this.__listeners = new Map();
  #|     }
  #|     addEventListener(type, listener, options) {
  #|       let listeners = this.__listeners.get(type);
  #|       if (!listeners) {
  #|         listeners = new Set();
  #|         this.__listeners.set(type, listeners);
  #|       }
  #|       listeners.add(listener);
  #|       super.addEventListener(type, listener, options);
  #|     }
  #|     removeEventListener(type, listener, options) {
  #|       this.__listeners.get(type)?.delete(listener);
  #|       super.removeEventListener(type, listener, options);
  #|     }
  #|     listenerCount(type) {
  #|       return this.__listeners.get(type)?.size ?? 0;
  #|     }
  #|   }
  #|   class TestMouseEvent extends Event {
  #|     constructor(type, init = {}) {
  #|       super(type, { cancelable: true, bubbles: true });
  #|       this.button = init.button ?? 0;
  #|       this.buttons = init.buttons ?? 0;
  #|       this.pointerId = init.pointerId ?? 0;
  #|       this.clientX = init.clientX ?? 0;
  #|       this.clientY = init.clientY ?? 0;
  #|       this.pageX = this.clientX;
  #|       this.pageY = this.clientY;
  #|       this.offsetX = this.clientX;
  #|       this.offsetY = this.clientY;
  #|       this.detail = init.detail ?? 1;
  #|       this.ctrlKey = false;
  #|       this.shiftKey = false;
  #|       this.altKey = false;
  #|       this.metaKey = false;
  #|     }
  #|   }
  #|   const owningWindow = new TrackingTarget();
  #|   const ownerDocument = new TrackingTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.defaultView = owningWindow;
  #|   owningWindow.document = ownerDocument;
  #|   owningWindow.__rafNextId = 1;
  #|   owningWindow.__rafHistory = [];
  #|   owningWindow.__rafActive = new Map();
  #|   owningWindow.__rafCancelCount = 0;
  #|   owningWindow.requestAnimationFrame = (callback) => {
  #|     const id = owningWindow.__rafNextId++;
  #|     owningWindow.__rafHistory.push(callback);
  #|     owningWindow.__rafActive.set(id, callback);
  #|     return id;
  #|   };
  #|   owningWindow.cancelAnimationFrame = (id) => {
  #|     owningWindow.__rafCancelCount += 1;
  #|     owningWindow.__rafActive.delete(id);
  #|   };
  #|   class TestElement extends TrackingTarget {
  #|     constructor(tag = "div") {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.ownerDocument = ownerDocument;
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this.scrollTop = 0;
  #|       this.scrollLeft = 0;
  #|       this.scrollWidth = 1000;
  #|       this.scrollHeight = 1000;
  #|       this.rectWidth = 100;
  #|       this.rectHeight = 100;
  #|       this.captureCalls = 0;
  #|       this.releaseCalls = 0;
  #|     }
  #|     setAttribute(name, value) {
  #|       const stringValue = String(value);
  #|       this.attributes.set(name, stringValue);
  #|       if (name === "class" && stringValue === "slider active") {
  #|         globalThis.__scrollbarInputTrace?.push("active");
  #|       }
  #|       if (name === "class" && stringValue === "visible scrollbar vertical") {
  #|         globalThis.__scrollbarInputTrace?.push("drag-start");
  #|       }
  #|     }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     appendChild(child) {
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter((item) => item !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     getBoundingClientRect() {
  #|       return {
  #|         x: 0, y: 0, left: 0, top: 0,
  #|         right: this.rectWidth, bottom: this.rectHeight,
  #|         width: this.rectWidth, height: this.rectHeight,
  #|       };
  #|     }
  #|     setPointerCapture(_pointerId) {
  #|       this.captureCalls += 1;
  #|       globalThis.__scrollbarInputTrace?.push("monitor");
  #|     }
  #|     releasePointerCapture(_pointerId) { this.releaseCalls += 1; }
  #|   }
  #|   ownerDocument.createElement = (tag) => new TestElement(tag);
  #|   globalThis.window = owningWindow;
  #|   globalThis.document = ownerDocument;
  #|   globalThis.MouseEvent = TestMouseEvent;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__ScrollbarInputTestElement = TestElement;
  #|   globalThis.__scrollbarInputTrace = [];
  #| }

///|
extern "js" fn scrollbar_input_test_element() -> @rdom.Element =
  #| () => new globalThis.__ScrollbarInputTestElement()

///|
extern "js" fn scrollbar_input_test_set_geometry(
  element : @rdom.Element,
  width : Double,
  height : Double,
  scroll_width : Double,
  scroll_height : Double,
) -> Unit =
  #| (element, width, height, scrollWidth, scrollHeight) => {
  #|   element.rectWidth = width;
  #|   element.rectHeight = height;
  #|   element.scrollWidth = scrollWidth;
  #|   element.scrollHeight = scrollHeight;
  #| }

///|
/// Bit 0 = defaultPrevented; bit 1 = propagation stopped.
extern "js" fn scrollbar_input_test_dispatch_mouse(
  element : @rdom.Element,
  event_type : String,
  button : Int,
  buttons : Int,
  pointer_id : Int,
  client_x : Int,
  client_y : Int,
) -> Int =
  #| (element, type, button, buttons, pointerId, clientX, clientY) => {
  #|   const event = new MouseEvent(type, {
  #|     button, buttons, pointerId, clientX, clientY,
  #|   });
  #|   element.dispatchEvent(event);
  #|   return (event.defaultPrevented ? 1 : 0) | (event.cancelBubble ? 2 : 0);
  #| }

///|
extern "js" fn scrollbar_input_test_non_element_mouse(
  button : Int,
  buttons : Int,
  pointer_id : Int,
) -> @rdom.MouseEvent =
  #| (button, buttons, pointerId) => {
  #|   const event = new MouseEvent("pointerdown", {
  #|     button, buttons, pointerId, clientX: 0, clientY: 0,
  #|   });
  #|   window.dispatchEvent(event);
  #|   return event;
  #| }

///|
extern "js" fn scrollbar_input_test_listener_count(
  element : @rdom.Element,
  event_type : String,
) -> Int =
  #| (element, type) => element.listenerCount(type)

///|
extern "js" fn scrollbar_input_test_reset_trace() -> Unit =
  #| () => { globalThis.__scrollbarInputTrace = []; }

///|
extern "js" fn scrollbar_input_test_trace() -> String =
  #| () => globalThis.__scrollbarInputTrace.join(",")

///|
extern "js" fn scrollbar_input_test_raf_cancel_count() -> Int =
  #| () => window.__rafCancelCount

///|
extern "js" fn scrollbar_input_test_run_raf_history() -> Unit =
  #| () => {
  #|   for (const callback of window.__rafHistory) callback(0);
  #| }

///|
fn scrollbar_input_test_handler(
  editor_scrollable : @scrollbar.ScrollableElementDom,
  hover_scrollable : @scrollbar.ScrollableElementDom,
) -> MouseHandler {
  let root = scrollbar_input_test_element()
  MouseHandler({
    view_dom_node: root,
    lines_content_dom_node: scrollbar_input_test_element(),
    view_lines_dom_node: scrollbar_input_test_element(),
    focus_text_area: () => (),
    get_last_render_data: () => abort("unused test helper"),
    render_now: () => (),
    should_suppress_mouse_down_on_view_zone: _ => false,
    get_position_from_dom_info: (_element, _offset) => None,
    visible_range_for_position: (_line, _column) => None,
    get_line_width: _ => 0.0,
    view_model: () => None,
    get_layout_info: () => abort("unused test helper"),
    get_font_info: () => abort("unused test helper"),
    get_current_selection: () => None,
    dispatch_mouse: _ => (),
    emit_mouse_down: (_event, _target) => (),
    emit_mouse_up: (_event, _target) => (),
    emit_mouse_move: (_event, _target) => (),
    emit_mouse_drag: (_event, _target) => (),
    emit_mouse_leave: _ => (),
    overflow_guard: scrollbar_input_test_element(),
    editor_scrollable,
    hover_scrollable: () => Some(hover_scrollable),
    view_layout: () => None,
    schedule_render: () => (),
  })
}

///|
fn prepare_scrollbar_input_test_scrollable(
  scrollable : @scrollbar.ScrollableElementDom,
  scroll_top : Double,
) -> Unit {
  scrollbar_input_test_set_geometry(
    scrollable.content,
    100.0,
    100.0,
    1000.0,
    1000.0,
  )
  scrollable.content.set_scroll_top(scroll_top)
  scrollable.update_from_model(
    { width: 100.0, scroll_width: 1000.0, height: 100.0, scroll_height: 1000.0 },
    { scroll_left: 0.0, scroll_top },
  )
}

///|
test "AbstractScrollbar gesture owns listeners, drag state, and reset branches" {
  install_scrollbar_input_test_browser()
  let editor_scrollable = @scrollbar.ScrollableElementDom("editor")
  let hover_scrollable = @scrollbar.ScrollableElementDom("hover")
  prepare_scrollbar_input_test_scrollable(editor_scrollable, 0.0)
  prepare_scrollbar_input_test_scrollable(hover_scrollable, 200.0)
  let handler = scrollbar_input_test_handler(
    editor_scrollable, hover_scrollable,
  )
  handler.hook_scrollable_scrollbar_input(
    hover_scrollable,
    HoverScrollableElement,
  )
  let slider = hover_scrollable.slider(true)

  // Only the normalized left button starts and consumes a slider gesture.
  assert_eq(
    scrollbar_input_test_dispatch_mouse(slider, "pointerdown", 2, 2, 1, 10, 10),
    0,
  )
  assert_true(handler.drag is None)
  assert_eq(slider.get_attribute("class"), "slider")
  assert_eq(
    scrollbar_input_test_dispatch_mouse(slider, "click", 2, 0, 1, 10, 10),
    0,
  )
  assert_eq(
    scrollbar_input_test_dispatch_mouse(slider, "click", 0, 0, 1, 10, 10),
    2,
  )

  // The source's invalid-target guard runs before active state or callbacks.
  handler.start_scrollable_drag(
    hover_scrollable,
    HoverScrollableElement,
    vertical=true,
    scrollbar_input_test_non_element_mouse(0, 1, 2),
  )
  assert_true(handler.drag is None)
  assert_false(hover_scrollable.is_dragging)

  // A normal along-axis move applies the captured slider delta.
  scrollbar_input_test_reset_trace()
  assert_eq(
    scrollbar_input_test_dispatch_mouse(slider, "pointerdown", 0, 1, 3, 10, 10),
    3,
  )
  assert_true(handler.drag is Some(_))
  assert_true(hover_scrollable.is_dragging)
  assert_eq(slider.get_attribute("class"), "slider active")
  assert_eq(scrollbar_input_test_trace(), "active,monitor,drag-start")
  let expected_from_pointerdown = match handler.drag {
    Some(drag) => drag.initial_state.desired_position_from_delta(20.0)
    None => abort("expected active drag")
  }
  // 100px visible / 1000px content yields a non-integer 80/900 slider
  // ratio; the exact cloned state maps this delta to 428.
  assert_eq(expected_from_pointerdown, 428.0)
  // Mutating live geometry after pointerdown must not change the cloned
  // state's delta mapping.
  scrollbar_input_test_set_geometry(
    hover_scrollable.content,
    100.0,
    250.0,
    1000.0,
    5000.0,
  )
  hover_scrollable.update_from_model(
    { width: 100.0, scroll_width: 1000.0, height: 250.0, scroll_height: 5000.0 },
    { scroll_left: 0.0, scroll_top: 200.0 },
  )
  assert_eq(
    scrollbar_input_test_dispatch_mouse(slider, "pointermove", 0, 1, 3, 10, 30),
    1,
  )
  assert_eq(
    hover_scrollable.content.get_scroll_top(),
    expected_from_pointerdown,
  )
  scrollbar_input_test_dispatch_mouse(slider, "pointerup", 0, 0, 3, 10, 30)
  |> ignore
  assert_true(handler.drag is None)
  assert_false(hover_scrollable.is_dragging)
  assert_eq(slider.get_attribute("class"), "slider")
  assert_eq(scrollbar_input_test_listener_count(slider, "pointermove"), 0)
  // A second pointerup has no retained stop callback or state transition.
  scrollbar_input_test_dispatch_mouse(slider, "pointerup", 0, 0, 3, 10, 30)
  |> ignore
  assert_true(handler.drag is None)

  // Windows 139/140 remain ordinary moves; 141 resets to the initial scroll.
  @base_common.set_is_windows_for_testing(value=true)
  for orthogonal_distance in [139, 140, 141] {
    prepare_scrollbar_input_test_scrollable(hover_scrollable, 200.0)
    scrollbar_input_test_dispatch_mouse(
      slider,
      "pointerdown",
      0,
      1,
      10 + orthogonal_distance,
      10,
      10,
    )
    |> ignore
    scrollbar_input_test_dispatch_mouse(
      slider,
      "pointermove",
      0,
      1,
      10 + orthogonal_distance,
      10 + orthogonal_distance,
      30,
    )
    |> ignore
    if orthogonal_distance > 140 {
      assert_eq(hover_scrollable.content.get_scroll_top(), 200.0)
    } else {
      assert_true(hover_scrollable.content.get_scroll_top() > 200.0)
    }
    scrollbar_input_test_dispatch_mouse(
      slider,
      "pointerup",
      0,
      0,
      10 + orthogonal_distance,
      10 + orthogonal_distance,
      30,
    )
    |> ignore
  }
  @base_common.set_is_windows_for_testing()

  // Disposing an active handler ends the drag and removes every hook exactly
  // once; post-dispose pointerdown is inert.
  prepare_scrollbar_input_test_scrollable(hover_scrollable, 200.0)
  scrollbar_input_test_dispatch_mouse(slider, "pointerdown", 0, 1, 99, 10, 10)
  |> ignore
  handler.dispose()
  handler.dispose()
  assert_true(handler.drag is None)
  assert_false(hover_scrollable.is_dragging)
  assert_eq(slider.get_attribute("class"), "slider")
  assert_eq(scrollbar_input_test_listener_count(slider, "pointerdown"), 0)
  assert_eq(
    scrollbar_input_test_dispatch_mouse(
      slider, "pointerdown", 0, 1, 100, 10, 10,
    ),
    0,
  )
}

///|
test "DragScrolling disposal cancels and disables its pending animation frame" {
  install_scrollbar_input_test_browser()
  let root = scrollbar_input_test_element()
  let editor_scrollable = @scrollbar.ScrollableElementDom("editor")
  let hover_scrollable = @scrollbar.ScrollableElementDom("hover")
  let helper : PointerHandlerHelper = {
    view_dom_node: root,
    lines_content_dom_node: scrollbar_input_test_element(),
    view_lines_dom_node: scrollbar_input_test_element(),
    focus_text_area: () => (),
    get_last_render_data: () => abort("disposed rAF reached render data"),
    render_now: () => abort("disposed rAF rendered"),
    should_suppress_mouse_down_on_view_zone: _ => false,
    get_position_from_dom_info: (_element, _offset) => None,
    visible_range_for_position: (_line, _column) => None,
    get_line_width: _ => 0.0,
    view_model: () => abort("disposed rAF read the ViewModel"),
    get_layout_info: () => abort("disposed rAF read layout"),
    get_font_info: () => abort("disposed rAF read font info"),
    get_current_selection: () => None,
    dispatch_mouse: _ => abort("disposed rAF dispatched"),
    emit_mouse_down: (_event, _target) => (),
    emit_mouse_up: (_event, _target) => (),
    emit_mouse_move: (_event, _target) => (),
    emit_mouse_drag: (_event, _target) => (),
    emit_mouse_leave: _ => (),
    overflow_guard: scrollbar_input_test_element(),
    editor_scrollable,
    hover_scrollable: () => Some(hover_scrollable),
    view_layout: () => None,
    schedule_render: () => (),
  }
  let factory = MouseTargetFactory(helper)
  let mouse = scrollbar_input_test_non_element_mouse(0, 1, 77)
  let editor_event = @editor_browser.EditorDomMouseEvent(mouse, true, root)
  let operation = DragScrollingOperation::new(
    TopBottom,
    helper,
    factory,
    (_position, _in_selection_mode, _reveal_type) => {
      abort("disposed rAF dispatched")
    },
    @editor_browser.MouseTarget::create_outside_editor(
      1,
      Position(1, 1),
      Below,
      20.0,
    ),
    editor_event,
  )
  assert_true(operation.animation_frame_id is Some(_))
  operation.dispose()
  operation.dispose()
  assert_true(operation.disposed)
  assert_true(operation.animation_frame_id is None)
  assert_eq(scrollbar_input_test_raf_cancel_count(), 1)
  // Force even the cancelled browser callback to run: the disposed guard must
  // return before any ViewModel/layout/render/dispatch seam above is touched.
  scrollbar_input_test_run_raf_history()
}
