///|
#external
type DefinitionPeekBrowserTestHarness

///|
extern "js" fn install_definition_peek_test_browser() -> DefinitionPeekBrowserTestHarness =
  #| () => {
  #|   const originals = {
  #|     document: globalThis.document,
  #|     Element: globalThis.Element,
  #|     HTMLElement: globalThis.HTMLElement,
  #|     Event: globalThis.Event,
  #|     KeyboardEvent: globalThis.KeyboardEvent,
  #|   };
  #|
  #|   class TestEvent {
  #|     constructor(type, options = {}) {
  #|       this.type = String(type);
  #|       this.bubbles = options.bubbles ?? true;
  #|       this.cancelable = options.cancelable ?? true;
  #|       this.defaultPrevented = false;
  #|       this.propagationStopped = false;
  #|       this.immediatePropagationStopped = false;
  #|       this.target = null;
  #|       this.currentTarget = null;
  #|     }
  #|     preventDefault() {
  #|       if (this.cancelable) this.defaultPrevented = true;
  #|     }
  #|     stopPropagation() { this.propagationStopped = true; }
  #|     stopImmediatePropagation() {
  #|       this.immediatePropagationStopped = true;
  #|       this.propagationStopped = true;
  #|     }
  #|   }
  #|
  #|   class TestKeyboardEvent extends TestEvent {
  #|     constructor(type, options = {}) {
  #|       super(type, options);
  #|       this.key = options.key ?? "";
  #|       this.code = options.code ?? "";
  #|       this.shiftKey = options.shiftKey ?? false;
  #|       this.altKey = options.altKey ?? false;
  #|       this.ctrlKey = options.ctrlKey ?? false;
  #|       this.metaKey = options.metaKey ?? false;
  #|       this.isComposing = false;
  #|       this.repeat = false;
  #|       this.location = 0;
  #|     }
  #|   }
  #|
  #|   class TestText {
  #|     constructor(text, ownerDocument) {
  #|       this.nodeType = 3;
  #|       this.nodeName = "#text";
  #|       this.textContent = String(text);
  #|       this.ownerDocument = ownerDocument;
  #|       this.parentNode = null;
  #|     }
  #|   }
  #|
  #|   class TestElement {
  #|     constructor(tag, ownerDocument) {
  #|       this.nodeType = 1;
  #|       this.nodeName = String(tag).toUpperCase();
  #|       this.tagName = this.nodeName;
  #|       this.ownerDocument = ownerDocument;
  #|       this.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = [];
  #|       this.attributes = new Map();
  #|       this.listeners = new Map();
  #|     }
  #|     setAttribute(name, value) {
  #|       this.attributes.set(String(name), String(value));
  #|     }
  #|     getAttribute(name) {
  #|       return this.attributes.has(String(name))
  #|         ? this.attributes.get(String(name))
  #|         : null;
  #|     }
  #|     hasAttribute(name) { return this.attributes.has(String(name)); }
  #|     removeAttribute(name) { this.attributes.delete(String(name)); }
  #|     appendChild(child) {
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       if (child.nodeType === 1) this.children.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter(value => value !== child);
  #|       this.children = this.children.filter(value => value !== child);
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     set innerHTML(_value) {
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = [];
  #|     }
  #|     get innerHTML() { return ""; }
  #|     addEventListener(type, listener) {
  #|       const listeners = this.listeners.get(type) ?? [];
  #|       if (!listeners.includes(listener)) listeners.push(listener);
  #|       this.listeners.set(type, listeners);
  #|     }
  #|     removeEventListener(type, listener) {
  #|       const listeners = this.listeners.get(type) ?? [];
  #|       this.listeners.set(
  #|         type,
  #|         listeners.filter(candidate => candidate !== listener),
  #|       );
  #|     }
  #|     dispatchEvent(event) {
  #|       if (!event.target) event.target = this;
  #|       event.currentTarget = this;
  #|       for (const listener of [...(this.listeners.get(event.type) ?? [])]) {
  #|         listener(event);
  #|         if (event.immediatePropagationStopped) break;
  #|       }
  #|       if (
  #|         event.bubbles &&
  #|         !event.propagationStopped &&
  #|         this.parentNode?.dispatchEvent
  #|       ) {
  #|         this.parentNode.dispatchEvent(event);
  #|       }
  #|       return !event.defaultPrevented;
  #|     }
  #|     focus(_options) { this.ownerDocument.activeElement = this; }
  #|     scrollIntoView(_options) {}
  #|   }
  #|
  #|   const document = {
  #|     nodeType: 9,
  #|     activeElement: null,
  #|     createElement(tag) { return new TestElement(tag, document); },
  #|     createTextNode(text) { return new TestText(text, document); },
  #|   };
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.HTMLElement = TestElement;
  #|   globalThis.Event = TestEvent;
  #|   globalThis.KeyboardEvent = TestKeyboardEvent;
  #|   return { originals, disposed: false };
  #| }

///|
extern "js" fn DefinitionPeekBrowserTestHarness::dispose(
  self : DefinitionPeekBrowserTestHarness,
) -> Unit =
  #| harness => {
  #|   if (harness.disposed) return;
  #|   harness.disposed = true;
  #|   const restore = (name, value) => {
  #|     if (value === undefined) delete globalThis[name];
  #|     else globalThis[name] = value;
  #|   };
  #|   restore("document", harness.originals.document);
  #|   restore("Element", harness.originals.Element);
  #|   restore("HTMLElement", harness.originals.HTMLElement);
  #|   restore("Event", harness.originals.Event);
  #|   restore("KeyboardEvent", harness.originals.KeyboardEvent);
  #| }

///|
extern "js" fn definition_peek_test_text_content(
  element : @rdom.Element,
) -> String =
  #| element => {
  #|   const read = node => node?.nodeType === 3
  #|     ? node.textContent
  #|     : (node?.childNodes ?? []).map(read).join("");
  #|   return read(element);
  #| }

///|
extern "js" fn definition_peek_test_has_attribute(
  element : @rdom.Element,
  name : String,
) -> Bool = "(element, name) => element.hasAttribute(name)"

///|
extern "js" fn definition_peek_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => element.getAttribute(name) ?? ""

///|
extern "js" fn definition_peek_test_child(
  element : @rdom.Element,
  index : Int,
) -> @rdom.Element =
  #| (element, index) => {
  #|   const child = element.children[index];
  #|   if (!child) throw new Error(`missing child ${index}`);
  #|   return child;
  #| }

///|
extern "js" fn definition_peek_test_listener_count(
  element : @rdom.Element,
  recursive : Bool,
) -> Int =
  #| (element, recursive) => {
  #|   const count = node => {
  #|     const own = [...node.listeners.values()]
  #|       .reduce((sum, values) => sum + values.length, 0);
  #|     return own + node.children.reduce(
  #|       (sum, child) => sum + count(child),
  #|       0,
  #|     );
  #|   };
  #|   if (recursive) return count(element);
  #|   return [...element.listeners.values()]
  #|     .reduce((sum, values) => sum + values.length, 0);
  #| }

///|
extern "js" fn definition_peek_test_dispatch(
  element : @rdom.Element,
  event_type : String,
) -> String =
  #| (element, eventType) => {
  #|   const event = new Event(eventType, { bubbles: true, cancelable: true });
  #|   element.dispatchEvent(event);
  #|   return `${event.defaultPrevented}:${event.propagationStopped}`;
  #| }

///|
extern "js" fn definition_peek_test_dispatch_key(
  element : @rdom.Element,
  key : String,
  shift : Bool,
) -> String =
  #| (element, key, shift) => {
  #|   const event = new KeyboardEvent(
  #|     "keydown",
  #|     { key, shiftKey: shift, bubbles: true, cancelable: true },
  #|   );
  #|   element.dispatchEvent(event);
  #|   return `${event.defaultPrevented}:${event.propagationStopped}`;
  #| }

///|
extern "js" fn definition_peek_test_is_active(element : @rdom.Element) -> Bool = "element => element.ownerDocument.activeElement === element"

///|
fn definition_peek_test_location(
  path : String,
  line : Int,
  column : Int,
) -> @language.Location {
  {
    uri: @base_common.Uri::file(path),
    range: Range(line, column, line, column + 1),
  }
}

///|
fn definition_peek_test_callbacks(
  close_count : Ref[Int],
  selected : Ref[Int],
  confirmed : Ref[Int],
  next_count : Ref[Int],
  previous_count : Ref[Int],
) -> DefinitionPeekWidgetCallbacks {
  {
    on_close: () => close_count.val = close_count.val + 1,
    on_select: index => selected.val = index,
    on_confirm: index => confirmed.val = index,
    on_next: () => next_count.val = next_count.val + 1,
    on_previous: () => previous_count.val = previous_count.val + 1,
  }
}

///|
test "peek shell renders loading unavailable and stable DOM hosts" {
  let harness = install_definition_peek_test_browser()
  defer harness.dispose()
  let widget = DefinitionPeekWidget(
    definition_peek_test_callbacks(Ref(0), Ref(-1), Ref(-1), Ref(0), Ref(0)),
  )
  assert_true(
    definition_peek_test_text_content(widget.get_dom_node()).contains(
      "Loading definitions",
    ),
  )
  assert_true(
    definition_peek_test_has_attribute(widget.get_list_node(), "hidden"),
  )
  assert_eq(
    definition_peek_test_attribute(widget.get_preview_host(), "aria-busy"),
    "true",
  )

  widget.show_unavailable("No preview available")
  assert_true(
    definition_peek_test_text_content(widget.get_dom_node()).contains(
      "No preview available",
    ),
  )
  assert_false(
    definition_peek_test_has_attribute(widget.get_preview_host(), "aria-busy"),
  )
  widget.focus()
  assert_true(definition_peek_test_is_active(widget.get_dom_node()))
  widget.dispose()
}

///|
test "peek result list updates selection and dispatches select and confirm" {
  let harness = install_definition_peek_test_browser()
  defer harness.dispose()
  let selected = Ref(-1)
  let confirmed = Ref(-1)
  let widget = DefinitionPeekWidget(
    definition_peek_test_callbacks(Ref(0), selected, confirmed, Ref(0), Ref(0)),
  )
  widget.set_locations(
    [
      definition_peek_test_location("/workspace/a.mbt", 2, 3),
      definition_peek_test_location("/workspace/b.mbt", 4, 5),
      definition_peek_test_location("/workspace/c.mbt", 6, 7),
    ],
    1,
  )
  let first = definition_peek_test_child(widget.get_list_node(), 0)
  let second = definition_peek_test_child(widget.get_list_node(), 1)
  let third = definition_peek_test_child(widget.get_list_node(), 2)
  assert_true(definition_peek_test_text_content(first).contains("a.mbt:2:3"))
  assert_eq(definition_peek_test_attribute(second, "aria-selected"), "true")

  widget.show_preview_loading()
  assert_true(
    definition_peek_test_text_content(widget.get_dom_node()).contains(
      "Loading preview",
    ),
  )
  assert_eq(widget.get_selected_index(), Some(1))
  assert_eq(definition_peek_test_listener_count(first, false), 2)
  widget.show_preview_unavailable("No preview available")
  assert_true(
    definition_peek_test_text_content(widget.get_dom_node()).contains(
      "No preview available",
    ),
  )
  assert_eq(widget.get_selected_index(), Some(1))
  assert_eq(definition_peek_test_listener_count(first, false), 2)
  widget.show_preview_ready()
  assert_false(
    definition_peek_test_text_content(widget.get_dom_node()).contains(
      "No preview available",
    ),
  )

  widget.set_selected_index(99)
  assert_eq(widget.get_selected_index(), Some(2))
  assert_eq(definition_peek_test_attribute(third, "aria-selected"), "true")
  assert_eq(definition_peek_test_dispatch(first, "click"), "true:true")
  assert_eq(selected.val, 0)
  assert_eq(widget.get_selected_index(), Some(0))
  assert_eq(definition_peek_test_dispatch(third, "dblclick"), "true:true")
  assert_eq(selected.val, 2)
  assert_eq(confirmed.val, 2)
  widget.dispose()
}

///|
test "peek shell routes Enter only from shell and result-list focus" {
  let harness = install_definition_peek_test_browser()
  defer harness.dispose()
  let close_count = Ref(0)
  let confirmed = Ref(-1)
  let next_count = Ref(0)
  let previous_count = Ref(0)
  let widget = DefinitionPeekWidget(
    definition_peek_test_callbacks(
      close_count,
      Ref(-1),
      confirmed,
      next_count,
      previous_count,
    ),
  )
  widget.set_locations(
    [definition_peek_test_location("/workspace/a.mbt", 1, 1)],
    0,
  )
  assert_eq(
    definition_peek_test_dispatch_key(widget.get_dom_node(), "Escape", false),
    "true:true",
  )
  assert_eq(close_count.val, 1)
  let header = definition_peek_test_child(widget.get_dom_node(), 0)
  let close = definition_peek_test_child(header, 1)
  assert_eq(
    definition_peek_test_dispatch_key(close, "Escape", false),
    "true:true",
  )
  assert_eq(close_count.val, 2)
  assert_eq(
    definition_peek_test_dispatch_key(widget.get_dom_node(), "Enter", false),
    "true:true",
  )
  assert_eq(confirmed.val, 0)
  let item = definition_peek_test_child(widget.get_list_node(), 0)
  assert_eq(
    definition_peek_test_dispatch_key(item, "Enter", false),
    "true:true",
  )
  assert_eq(confirmed.val, 0)
  confirmed.val = -1
  let preview_input = @rdom.document().create_element("textarea")
  widget.get_preview_host().append_child(preview_input.as_node())
  // Enter belongs to the nested preview. The shell still contains it so the
  // outer editor cannot act on it, but neither prevents its native default nor
  // confirms the selected definition.
  assert_eq(
    definition_peek_test_dispatch_key(preview_input, "Enter", false),
    "false:true",
  )
  assert_eq(confirmed.val, -1)
  // Session commands remain available while focus is inside the preview.
  assert_eq(
    definition_peek_test_dispatch_key(preview_input, "Escape", false),
    "true:true",
  )
  assert_eq(close_count.val, 3)
  assert_eq(
    definition_peek_test_dispatch_key(preview_input, "F4", false),
    "true:true",
  )
  assert_eq(next_count.val, 1)
  assert_eq(
    definition_peek_test_dispatch_key(widget.get_dom_node(), "F4", false),
    "true:true",
  )
  assert_eq(next_count.val, 2)
  assert_eq(
    definition_peek_test_dispatch_key(widget.get_dom_node(), "F4", true),
    "true:true",
  )
  assert_eq(previous_count.val, 1)
  // Unhandled keys still cannot bubble from the nested preview to the outer
  // editor, but retain their native default inside that preview.
  assert_eq(
    definition_peek_test_dispatch_key(preview_input, "a", false),
    "false:true",
  )
  widget.dispose()
}

///|
test "peek shell releases replaced row and persistent listeners once" {
  let harness = install_definition_peek_test_browser()
  defer harness.dispose()
  let selected = Ref(-1)
  let widget = DefinitionPeekWidget(
    definition_peek_test_callbacks(Ref(0), selected, Ref(-1), Ref(0), Ref(0)),
  )
  widget.set_locations(
    [definition_peek_test_location("/workspace/a.mbt", 1, 1)],
    0,
  )
  let stale_item = definition_peek_test_child(widget.get_list_node(), 0)
  assert_eq(definition_peek_test_listener_count(stale_item, false), 2)
  widget.set_locations(
    [definition_peek_test_location("/workspace/b.mbt", 2, 2)],
    0,
  )
  assert_eq(definition_peek_test_listener_count(stale_item, false), 0)

  widget.dispose()
  widget.dispose()
  assert_eq(definition_peek_test_listener_count(widget.get_dom_node(), true), 0)
  assert_eq(definition_peek_test_dispatch(stale_item, "click"), "false:false")
  assert_eq(selected.val, -1)
}

///|
test "definition message widget shows hides and disposes idempotently" {
  let harness = install_definition_peek_test_browser()
  defer harness.dispose()
  let widget = DefinitionMessageWidget()
  assert_true(
    definition_peek_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  widget.set_message("No definition found")
  widget.show_at(Position(2, 3))
  assert_eq(widget.position, Some(Position(2, 3)))
  widget.after_render(Some(Below))
  assert_true(
    widget.get_dom_node().get_attribute("class").unwrap().contains("below"),
  )
  assert_false(
    definition_peek_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  assert_eq(
    definition_peek_test_text_content(widget.get_dom_node()),
    "No definition found",
  )
  widget.hide()
  assert_true(widget.position is None)
  assert_true(
    definition_peek_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  widget.dispose()
  widget.dispose()
  widget.set_message("late")
  widget.show_at(Position(4, 5))
  assert_true(
    definition_peek_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  assert_eq(definition_peek_test_text_content(widget.get_dom_node()), "")
}
