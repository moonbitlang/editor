///|
extern "js" fn install_markdown_comment_browser_test_dom() -> Unit =
  #| () => {
  #|   globalThis.__markdownCommentBrowserOriginals = {
  #|     document: globalThis.document,
  #|     Element: globalThis.Element,
  #|     ResizeObserver: globalThis.ResizeObserver,
  #|     requestAnimationFrame: globalThis.requestAnimationFrame,
  #|   };
  #|   globalThis.__markdownCommentBrowserFrames = [];
  #|   globalThis.__markdownCommentBrowserObservers = [];
  #|   globalThis.__markdownCommentHiddenMeasureCount = 0;
  #|
  #|   class TestStyle {
  #|     constructor() { this.values = new Map(); this.priorities = new Map(); }
  #|     getPropertyValue(name) { return this.values.get(name) ?? ""; }
  #|     getPropertyPriority(name) { return this.priorities.get(name) ?? ""; }
  #|     setProperty(name, value, priority = "") {
  #|       this.values.set(name, String(value));
  #|       if (priority) this.priorities.set(name, String(priority));
  #|       else this.priorities.delete(name);
  #|     }
  #|     removeProperty(name) {
  #|       const previous = this.getPropertyValue(name);
  #|       this.values.delete(name);
  #|       this.priorities.delete(name);
  #|       return previous;
  #|     }
  #|   }
  #|
  #|   class TestElement extends EventTarget {
  #|     constructor(ownerDocument, tag) {
  #|       super();
  #|       this.ownerDocument = ownerDocument;
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.tagName = this.nodeName;
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this.isConnected = false;
  #|       this.style = new TestStyle();
  #|       this.clientWidth = 0;
  #|       this.__offsetHeight = 0;
  #|       this.__hiddenHeights = null;
  #|     }
  #|     get offsetHeight() {
  #|       if (this.__offsetHeight > 0) return this.__offsetHeight;
  #|       const outer = this.parentNode;
  #|       if (!this.__hiddenHeights || outer?.style.getPropertyValue('display') !== 'block') return 0;
  #|       globalThis.__markdownCommentHiddenMeasureCount += 1;
  #|       const width = Number.parseInt(outer.style.getPropertyValue('width'), 10);
  #|       return this.__hiddenHeights.get(width) ?? 0;
  #|     }
  #|     set offsetHeight(value) { this.__offsetHeight = Number(value); }
  #|     setAttribute(name, value) { this.attributes.set(name, String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     closest(selector) {
  #|       if (!selector.startsWith('.')) return null;
  #|       const wanted = selector.slice(1);
  #|       for (let current = this; current; current = current.parentNode) {
  #|         const classes = (current.getAttribute?.('class') ?? '').split(/\s+/);
  #|         if (classes.includes(wanted)) return current;
  #|       }
  #|       return null;
  #|     }
  #|     appendChild(child) {
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter(candidate => candidate !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|   }
  #|
  #|   class TestResizeObserver {
  #|     constructor(callback) {
  #|       this.callback = callback;
  #|       this.target = null;
  #|       this.targets = [];
  #|       this.disconnectCount = 0;
  #|       globalThis.__markdownCommentBrowserObservers.push(this);
  #|     }
  #|     observe(target) {
  #|       this.target ??= target;
  #|       this.targets.push(target);
  #|     }
  #|     disconnect() { this.disconnectCount += 1; }
  #|     triggerLate(target = this.target) { this.callback([{ target }], this); }
  #|   }
  #|
  #|   const document = {
  #|     nodeType: 9,
  #|     createElement(tag) { return new TestElement(document, tag); },
  #|   };
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.ResizeObserver = TestResizeObserver;
  #|   globalThis.requestAnimationFrame = callback => {
  #|     globalThis.__markdownCommentBrowserFrames.push(callback);
  #|     return globalThis.__markdownCommentBrowserFrames.length;
  #|   };
  #| }

///|
extern "js" fn restore_markdown_comment_browser_test_dom() -> Unit =
  #| () => {
  #|   const originals = globalThis.__markdownCommentBrowserOriginals;
  #|   globalThis.document = originals.document;
  #|   globalThis.Element = originals.Element;
  #|   globalThis.ResizeObserver = originals.ResizeObserver;
  #|   globalThis.requestAnimationFrame = originals.requestAnimationFrame;
  #|   delete globalThis.__markdownCommentBrowserOriginals;
  #|   delete globalThis.__markdownCommentBrowserFrames;
  #|   delete globalThis.__markdownCommentBrowserObservers;
  #|   delete globalThis.__markdownCommentHiddenMeasureCount;
  #| }

///|
extern "js" fn markdown_comment_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element.getAttribute(name)"

///|
extern "js" fn markdown_comment_test_child_count(
  element : @rdom.Element,
) -> Int = "element => element.childNodes.length"

///|
extern "js" fn markdown_comment_test_first_child(
  element : @rdom.Element,
) -> @rdom.Element = "element => element.childNodes[0]"

///|
extern "js" fn markdown_comment_test_same_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool = "(left, right) => left === right"

///|
extern "js" fn markdown_comment_test_set_measurement(
  element : @rdom.Element,
  connected : Bool,
  height : Double,
) -> Unit =
  #| (element, connected, height) => {
  #|   element.isConnected = connected;
  #|   element.offsetHeight = height;
  #| }

///|
extern "js" fn markdown_comment_test_trigger_resize() -> Unit =
  #| () => {
  #|   const observer = globalThis.__markdownCommentBrowserObservers.at(-1);
  #|   if (!observer) throw new Error("missing ResizeObserver");
  #|   observer.triggerLate();
  #| }

///|
extern "js" fn markdown_comment_test_trigger_resize_for(
  element : @rdom.Element,
) -> Unit =
  #| element => {
  #|   const observer = globalThis.__markdownCommentBrowserObservers.at(-1);
  #|   if (!observer) throw new Error("missing ResizeObserver");
  #|   observer.triggerLate(element);
  #| }

///|
extern "js" fn markdown_comment_test_observes(element : @rdom.Element) -> Bool =
  #| element => globalThis.__markdownCommentBrowserObservers.at(-1)?.targets.includes(element) === true

///|
extern "js" fn markdown_comment_test_mount_offscreen(
  outer : @rdom.Element,
  content : @rdom.Element,
  viewport_width : Int,
  wide_height : Int,
  narrow_width : Int,
  narrow_height : Int,
) -> @rdom.Element =
  #| (outer, content, viewportWidth, wideHeight, narrowWidth, narrowHeight) => {
  #|   const viewport = document.createElement('div');
  #|   viewport.setAttribute('class', 'editor-scrollable');
  #|   viewport.clientWidth = viewportWidth;
  #|   viewport.isConnected = true;
  #|   viewport.appendChild(outer);
  #|   outer.isConnected = true;
  #|   content.isConnected = true;
  #|   outer.style.setProperty('display', 'none');
  #|   outer.style.setProperty('height', '0px');
  #|   outer.style.setProperty('width', '100%');
  #|   outer.style.setProperty('top', '7px');
  #|   outer.style.setProperty('left', '3px');
  #|   content.__hiddenHeights = new Map([
  #|     [viewportWidth, wideHeight],
  #|     [narrowWidth, narrowHeight],
  #|   ]);
  #|   return viewport;
  #| }

///|
extern "js" fn markdown_comment_test_set_viewport_width(
  viewport : @rdom.Element,
  width : Int,
) -> Unit = "(viewport, width) => { viewport.clientWidth = width; }"

///|
extern "js" fn markdown_comment_test_outer_style(
  element : @rdom.Element,
) -> String =
  #| element => ['display', 'visibility', 'pointer-events', 'height', 'width', 'top', 'left']
  #|   .map(name => `${name}=${element.style.getPropertyValue(name)}!${element.style.getPropertyPriority(name)}`)
  #|   .join(';')

///|
extern "js" fn markdown_comment_test_hidden_measure_count() -> Int = "() => globalThis.__markdownCommentHiddenMeasureCount"

///|
extern "js" fn markdown_comment_test_disconnect_count() -> Int =
  #| () => globalThis.__markdownCommentBrowserObservers.at(-1)?.disconnectCount ?? 0

///|
extern "js" fn markdown_comment_test_pending_frame_count() -> Int = "() => globalThis.__markdownCommentBrowserFrames.length"

///|
extern "js" fn markdown_comment_test_flush_frame() -> Unit =
  #| () => {
  #|   const callback = globalThis.__markdownCommentBrowserFrames.shift();
  #|   if (!callback) throw new Error("missing animation frame");
  #|   callback(0);
  #| }

///|
test "MarkdownCommentDom creates the stable half-open ViewZone target shape" {
  install_markdown_comment_browser_test_dom()
  let dom = MarkdownCommentDom(3, 7)
  assert_eq(
    markdown_comment_test_attribute(dom.outer, "class"),
    "moonbit-viewer-markdown-comment",
  )
  assert_eq(markdown_comment_test_attribute(dom.outer, "data-start-line"), "3")
  assert_eq(markdown_comment_test_attribute(dom.outer, "data-end-line"), "7")
  assert_eq(
    markdown_comment_test_attribute(dom.content, "class"),
    "moonbit-viewer-markdown-comment-content",
  )
  assert_eq(markdown_comment_test_child_count(dom.outer), 1)
  assert_true(
    markdown_comment_test_same_element(
      markdown_comment_test_first_child(dom.outer),
      dom.content,
    ),
  )
  restore_markdown_comment_browser_test_dom()
}

///|
test "size observation coalesces and reports positive changed integer heights" {
  install_markdown_comment_browser_test_dom()
  let dom = MarkdownCommentDom(1, 2)
  let observed : Array[Int] = []
  let lifetime = dom.observe_size(height => observed.push(height))
  assert_true(markdown_comment_test_observes(dom.content))
  markdown_comment_test_set_measurement(dom.content, true, 18.9)
  markdown_comment_test_trigger_resize()
  markdown_comment_test_trigger_resize()
  markdown_comment_test_trigger_resize()
  assert_eq(markdown_comment_test_pending_frame_count(), 1)
  // The frame reads the latest geometry, not the first observer payload.
  markdown_comment_test_set_measurement(dom.content, true, 27.9)
  markdown_comment_test_flush_frame()
  assert_eq(observed, [27])

  markdown_comment_test_trigger_resize()
  markdown_comment_test_flush_frame()
  assert_eq(observed, [27])

  markdown_comment_test_set_measurement(dom.content, true, 31.0)
  markdown_comment_test_trigger_resize()
  markdown_comment_test_trigger_resize()
  assert_eq(markdown_comment_test_pending_frame_count(), 1)
  markdown_comment_test_flush_frame()
  assert_eq(observed, [27, 31])
  lifetime.dispose()
  lifetime.dispose()
  assert_eq(markdown_comment_test_disconnect_count(), 1)
  restore_markdown_comment_browser_test_dom()
}

///|
test "disconnected zero queued and late observer callbacks are inert" {
  install_markdown_comment_browser_test_dom()
  let dom = MarkdownCommentDom(5, 6)
  let observed : Array[Int] = []
  let lifetime = dom.observe_size(height => observed.push(height))

  markdown_comment_test_set_measurement(dom.content, false, 20.0)
  markdown_comment_test_trigger_resize()
  markdown_comment_test_flush_frame()
  assert_true(observed.is_empty())

  markdown_comment_test_set_measurement(dom.content, true, 0.0)
  markdown_comment_test_trigger_resize()
  markdown_comment_test_flush_frame()
  assert_true(observed.is_empty())

  markdown_comment_test_set_measurement(dom.content, true, 22.0)
  markdown_comment_test_trigger_resize()
  markdown_comment_test_flush_frame()
  assert_eq(observed, [22])

  markdown_comment_test_set_measurement(dom.content, true, 40.0)
  markdown_comment_test_trigger_resize()
  assert_eq(markdown_comment_test_pending_frame_count(), 1)
  lifetime.dispose()
  lifetime.dispose()
  assert_eq(markdown_comment_test_disconnect_count(), 1)
  // The native frame still drains the shared coordinator, whose canceled
  // registration and disposed guard both keep the root callback inert.
  markdown_comment_test_flush_frame()
  assert_eq(observed, [22])

  // Simulate a browser-delivered ResizeObserver callback that was already
  // queued when disconnect ran.
  markdown_comment_test_trigger_resize()
  assert_eq(markdown_comment_test_pending_frame_count(), 0)
  assert_eq(observed, [22])
  restore_markdown_comment_browser_test_dom()
}

///|
test "offscreen measurement uses viewport width restores styles and avoids zero feedback" {
  install_markdown_comment_browser_test_dom()
  let dom = MarkdownCommentDom(81, 91)
  let viewport = markdown_comment_test_mount_offscreen(
    dom.outer,
    dom.content,
    320,
    96,
    180,
    154,
  )
  let original_style = markdown_comment_test_outer_style(dom.outer)
  let observed : Array[Int] = []
  let observer = dom.observe_size(height => observed.push(height))
  assert_true(markdown_comment_test_observes(dom.content))
  assert_true(markdown_comment_test_observes(viewport))

  observer.request_measure()
  observer.request_measure()
  assert_eq(markdown_comment_test_pending_frame_count(), 1)
  markdown_comment_test_flush_frame()
  assert_eq(observed, [96])
  assert_eq(markdown_comment_test_hidden_measure_count(), 1)
  assert_eq(markdown_comment_test_outer_style(dom.outer), original_style)

  // The zero-size target callback caused by restoring `display:none` must not
  // enter the forced hidden path again or produce a frame-to-frame loop.
  markdown_comment_test_trigger_resize_for(dom.content)
  markdown_comment_test_flush_frame()
  assert_eq(observed, [96])
  assert_eq(markdown_comment_test_hidden_measure_count(), 1)

  // A viewport observation is an explicit width invalidation even while the
  // ViewZone remains display:none.
  markdown_comment_test_set_viewport_width(viewport, 180)
  markdown_comment_test_trigger_resize_for(viewport)
  markdown_comment_test_flush_frame()
  assert_eq(observed, [96, 154])
  assert_eq(markdown_comment_test_hidden_measure_count(), 2)
  assert_eq(markdown_comment_test_outer_style(dom.outer), original_style)

  observer.dispose()
  observer.request_measure()
  assert_eq(markdown_comment_test_pending_frame_count(), 0)
  assert_eq(markdown_comment_test_disconnect_count(), 1)
  restore_markdown_comment_browser_test_dom()
}
