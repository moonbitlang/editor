///|
#external
type DefinitionMessageBrowserTestHarness

///|
extern "js" fn install_definition_message_test_browser() -> DefinitionMessageBrowserTestHarness =
  #| () => {
  #|   const originals = {
  #|     document: globalThis.document,
  #|     Element: globalThis.Element,
  #|     HTMLElement: globalThis.HTMLElement,
  #|   };
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
  #|       this.childNodes.push(child);
  #|       if (child.nodeType === 1) this.children.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     set innerHTML(_value) {
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       this.children = [];
  #|     }
  #|     get innerHTML() { return ""; }
  #|   }
  #|
  #|   const document = {
  #|     nodeType: 9,
  #|     createElement(tag) { return new TestElement(tag, document); },
  #|     createTextNode(text) { return new TestText(text, document); },
  #|   };
  #|   globalThis.document = document;
  #|   globalThis.Element = TestElement;
  #|   globalThis.HTMLElement = TestElement;
  #|   return { originals, disposed: false };
  #| }

///|
extern "js" fn DefinitionMessageBrowserTestHarness::dispose(
  self : DefinitionMessageBrowserTestHarness,
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
  #| }

///|
extern "js" fn definition_message_test_text_content(
  element : @rdom.Element,
) -> String =
  #| element => {
  #|   const read = node => node?.nodeType === 3
  #|     ? node.textContent
  #|     : (node?.childNodes ?? []).map(read).join("");
  #|   return read(element);
  #| }

///|
extern "js" fn definition_message_test_has_attribute(
  element : @rdom.Element,
  name : String,
) -> Bool = "(element, name) => element.hasAttribute(name)"

///|
test "definition message widget shows hides and disposes idempotently" {
  let harness = install_definition_message_test_browser()
  defer harness.dispose()
  let widget = DefinitionMessageWidget()
  assert_true(
    definition_message_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  widget.set_message("No definition found")
  widget.show_at(Position(2, 3))
  assert_eq(widget.position, Some(Position(2, 3)))
  widget.after_render(Some(Below))
  assert_true(
    widget.get_dom_node().get_attribute("class").unwrap().contains("below"),
  )
  assert_false(
    definition_message_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  assert_eq(
    definition_message_test_text_content(widget.get_dom_node()),
    "No definition found",
  )
  widget.hide()
  assert_true(widget.position is None)
  assert_true(
    definition_message_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  widget.dispose()
  widget.dispose()
  widget.set_message("late")
  widget.show_at(Position(4, 5))
  assert_true(
    definition_message_test_has_attribute(widget.get_dom_node(), "hidden"),
  )
  assert_eq(definition_message_test_text_content(widget.get_dom_node()), "")
}
