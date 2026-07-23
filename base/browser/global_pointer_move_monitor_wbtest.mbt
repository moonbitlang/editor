///|
/// Installs a tiny EventTarget/Element/MouseEvent browser seam for the js
/// package test. It records listener and capture operations without importing
/// a DOM emulator into product code.
extern "js" fn install_pointer_monitor_test_browser() -> Unit =
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
  #|       super(type, { cancelable: true });
  #|       this.buttons = init.buttons ?? 0;
  #|       this.button = init.button ?? 0;
  #|       this.pointerId = init.pointerId ?? 0;
  #|       this.clientX = init.clientX ?? 0;
  #|       this.clientY = init.clientY ?? 0;
  #|     }
  #|   }
  #|   const globalWindow = new TrackingTarget();
  #|   const owningWindow = new TrackingTarget();
  #|   const ownerDocument = new TrackingTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.defaultView = owningWindow;
  #|   owningWindow.document = ownerDocument;
  #|   class TestElement extends TrackingTarget {
  #|     constructor(captureThrows, releaseThrows) {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.ownerDocument = ownerDocument;
  #|       this.captureThrows = captureThrows;
  #|       this.releaseThrows = releaseThrows;
  #|       this.captureCalls = 0;
  #|       this.releaseCalls = 0;
  #|     }
  #|     setPointerCapture(_pointerId) {
  #|       this.captureCalls += 1;
  #|       if (this.captureThrows) throw new DOMException("capture failed");
  #|     }
  #|     releasePointerCapture(_pointerId) {
  #|       this.releaseCalls += 1;
  #|       if (this.releaseThrows) throw new DOMException("release failed");
  #|     }
  #|   }
  #|   globalThis.window = globalWindow;
  #|   globalThis.document = ownerDocument;
  #|   globalThis.MouseEvent = TestMouseEvent;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__PointerMonitorTestElement = TestElement;
  #| }

///|
extern "js" fn pointer_monitor_test_element(
  capture_throws : Bool,
  release_throws : Bool,
) -> @rdom.Element =
  #| (captureThrows, releaseThrows) => new globalThis.__PointerMonitorTestElement(captureThrows, releaseThrows)

///|
extern "js" fn pointer_monitor_test_dispatch(
  element : @rdom.Element,
  on_owning_window : Bool,
  event_type : String,
  buttons : Int,
  pointer_id : Int,
) -> Bool =
  #| (element, onOwningWindow, type, buttons, pointerId) => {
  #|   const target = onOwningWindow ? element.ownerDocument.defaultView : element;
  #|   const event = new MouseEvent(type, { buttons, pointerId });
  #|   target.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
extern "js" fn pointer_monitor_test_dispatch_plain(
  element : @rdom.Element,
  event_type : String,
) -> Bool =
  #| (element, type) => {
  #|   const event = new Event(type, { cancelable: true });
  #|   element.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
extern "js" fn pointer_monitor_test_listener_count(
  element : @rdom.Element,
  on_owning_window : Bool,
  event_type : String,
) -> Int =
  #| (element, onOwningWindow, type) => {
  #|   const target = onOwningWindow ? element.ownerDocument.defaultView : element;
  #|   return target.listenerCount(type);
  #| }

///|
extern "js" fn pointer_monitor_test_global_listener_count(
  event_type : String,
) -> Int =
  #| (type) => window.listenerCount(type)

///|
extern "js" fn pointer_monitor_test_capture_calls(
  element : @rdom.Element,
) -> Int =
  #| (element) => element.captureCalls

///|
extern "js" fn pointer_monitor_test_release_calls(
  element : @rdom.Element,
) -> Int =
  #| (element) => element.releaseCalls

///|
test "GlobalPointerMoveMonitor capture, fallback, stop, restart, and dispose lifecycle" {
  install_pointer_monitor_test_browser()

  // Capture success keeps both gesture listeners on the initial element.
  let moved = Ref(0)
  let stopped = Ref(0)
  let changed_buttons_forwarded_event = Ref(false)
  let captured = pointer_monitor_test_element(false, false)
  let monitor = GlobalPointerMoveMonitor()
  monitor.start_monitoring(captured, 41, 1, _ => moved.val += 1, event => {
    stopped.val += 1
    changed_buttons_forwarded_event.val = event is Some(_)
  })
  assert_true(monitor.is_monitoring())
  assert_eq(pointer_monitor_test_capture_calls(captured), 1)
  assert_eq(
    pointer_monitor_test_listener_count(captured, false, "pointermove"),
    1,
  )
  assert_eq(
    pointer_monitor_test_listener_count(captured, true, "pointermove"),
    0,
  )
  assert_true(
    pointer_monitor_test_dispatch(captured, false, "pointermove", 1, 41),
  )
  assert_eq(moved.val, 1)
  assert_false(pointer_monitor_test_dispatch_plain(captured, "pointermove"))
  assert_eq(moved.val, 1)
  assert_true(monitor.is_monitoring())

  // A changed buttons mask stops before preventDefault or move dispatch.
  assert_false(
    pointer_monitor_test_dispatch(captured, false, "pointermove", 0, 41),
  )
  assert_false(monitor.is_monitoring())
  assert_eq(moved.val, 1)
  assert_eq(stopped.val, 1)
  assert_false(changed_buttons_forwarded_event.val)
  assert_eq(pointer_monitor_test_release_calls(captured), 1)
  assert_eq(
    pointer_monitor_test_listener_count(captured, false, "pointermove"),
    0,
  )

  // Restart releases the old capture without invoking its stop callback.
  let first = pointer_monitor_test_element(false, false)
  let second = pointer_monitor_test_element(false, false)
  let old_stops = Ref(0)
  let new_stops = Ref(0)
  let pointer_up_forwarded_event = Ref(false)
  monitor.start_monitoring(first, 1, 1, _ => (), _ => old_stops.val += 1)
  monitor.start_monitoring(second, 2, 1, _ => (), event => {
    new_stops.val += 1
    pointer_up_forwarded_event.val = event is Some(_)
  })
  assert_eq(old_stops.val, 0)
  assert_eq(pointer_monitor_test_release_calls(first), 1)
  assert_eq(pointer_monitor_test_capture_calls(second), 1)
  assert_false(pointer_monitor_test_dispatch(second, false, "pointerup", 0, 2))
  assert_eq(new_stops.val, 1)
  assert_false(pointer_up_forwarded_event.val)
  assert_false(monitor.is_monitoring())

  // Explicit false/true stop flags differ only in callback invocation.
  let explicit_stops = Ref(0)
  monitor.start_monitoring(captured, 42, 1, _ => (), _ => {
    explicit_stops.val += 1
  })
  monitor.stop_monitoring(false)
  assert_eq(explicit_stops.val, 0)
  monitor.start_monitoring(captured, 43, 1, _ => (), _ => {
    explicit_stops.val += 1
  })
  monitor.stop_monitoring(true)
  assert_eq(explicit_stops.val, 1)
  // Inactive stop is a no-op.
  monitor.stop_monitoring(true)
  assert_eq(explicit_stops.val, 1)

  // Release exceptions are deliberately swallowed.
  let release_throws = pointer_monitor_test_element(false, true)
  monitor.start_monitoring(release_throws, 7, 1, _ => (), _ => ())
  monitor.stop_monitoring(false)
  assert_eq(pointer_monitor_test_release_calls(release_throws), 1)
  assert_false(monitor.is_monitoring())

  // Capture exceptions select the element's owning window, not the element.
  let capture_throws = pointer_monitor_test_element(true, false)
  let fallback_moves = Ref(0)
  let fallback_stops = Ref(0)
  monitor.start_monitoring(capture_throws, 9, 1, _ => fallback_moves.val += 1, _ => {
    fallback_stops.val += 1
  })
  assert_eq(pointer_monitor_test_capture_calls(capture_throws), 1)
  assert_eq(
    pointer_monitor_test_listener_count(capture_throws, false, "pointermove"),
    0,
  )
  assert_eq(
    pointer_monitor_test_listener_count(capture_throws, true, "pointermove"),
    1,
  )
  assert_eq(pointer_monitor_test_global_listener_count("pointermove"), 0)
  assert_true(
    pointer_monitor_test_dispatch(capture_throws, true, "pointermove", 1, 9),
  )
  assert_eq(fallback_moves.val, 1)
  pointer_monitor_test_dispatch(capture_throws, true, "pointerup", 0, 9)
  |> ignore
  assert_eq(fallback_stops.val, 1)
  assert_eq(pointer_monitor_test_release_calls(capture_throws), 0)

  // Disposal closes the monitor permanently, even if start is attempted.
  let after_dispose = pointer_monitor_test_element(false, false)
  monitor.dispose()
  monitor.dispose()
  monitor.start_monitoring(after_dispose, 11, 1, _ => (), _ => ())
  assert_false(monitor.is_monitoring())
  assert_eq(pointer_monitor_test_capture_calls(after_dispose), 0)
  assert_eq(
    pointer_monitor_test_listener_count(after_dispose, false, "pointermove"),
    0,
  )
}
