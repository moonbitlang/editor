///|
/// Installs a small standards-shaped DOM used by the JS package tests. The
/// parser only implements the safe cmark output surface exercised here; DOM
/// policy remains product code in `install_markdown_dom`.
extern "js" fn install_markdown_test_dom() -> Unit =
  #| () => {
  #|   const voidTags = new Set(["AREA", "BASE", "BR", "COL", "EMBED", "HR", "IMG", "INPUT", "LINK", "META", "PARAM", "SOURCE", "TRACK", "WBR"]);
  #|   const decode = (value) => value
  #|     .replaceAll("&quot;", "\"")
  #|     .replaceAll("&#39;", "'")
  #|     .replaceAll("&lt;", "<")
  #|     .replaceAll("&gt;", ">")
  #|     .replaceAll("&amp;", "&");
  #|
  #|   class FakeTree extends EventTarget {
  #|     constructor(ownerDocument, nodeType, nodeName) {
  #|       super();
  #|       this.ownerDocument = ownerDocument;
  #|       this.nodeType = nodeType;
  #|       this.nodeName = nodeName;
  #|       this.parentNode = null;
  #|       this.childNodes = [];
  #|       this.__listeners = new Map();
  #|     }
  #|     addEventListener(type, listener, options) {
  #|       let values = this.__listeners.get(type);
  #|       if (!values) {
  #|         values = new Set();
  #|         this.__listeners.set(type, values);
  #|       }
  #|       values.add(listener);
  #|       super.addEventListener(type, listener, options);
  #|     }
  #|     removeEventListener(type, listener, options) {
  #|       this.__listeners.get(type)?.delete(listener);
  #|       super.removeEventListener(type, listener, options);
  #|     }
  #|     listenerCount(type) { return this.__listeners.get(type)?.size ?? 0; }
  #|     appendChild(child) {
  #|       if (child.nodeType === 11) {
  #|         for (const nested of Array.from(child.childNodes)) this.appendChild(nested);
  #|         child.childNodes = [];
  #|         return child;
  #|       }
  #|       child.parentNode?.removeChild(child);
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       const index = this.childNodes.indexOf(child);
  #|       if (index >= 0) this.childNodes.splice(index, 1);
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     replaceChildren(...children) {
  #|       for (const child of this.childNodes) child.parentNode = null;
  #|       this.childNodes = [];
  #|       for (const child of children) this.appendChild(child);
  #|     }
  #|     querySelectorAll(selector) {
  #|       const wanted = selector.split(",").map((part) => part.trim().toUpperCase());
  #|       const result = [];
  #|       const visit = (node) => {
  #|         for (const child of node.childNodes) {
  #|           if (child.nodeType === 1 && (wanted.includes("*") || wanted.includes(child.tagName))) result.push(child);
  #|           visit(child);
  #|         }
  #|       };
  #|       visit(this);
  #|       return result;
  #|     }
  #|     get textContent() { return this.childNodes.map((child) => child.textContent).join(""); }
  #|   }
  #|
  #|   class FakeText extends FakeTree {
  #|     constructor(ownerDocument, value) {
  #|       super(ownerDocument, 3, "#text");
  #|       this.value = decode(value);
  #|     }
  #|     get textContent() { return this.value; }
  #|   }
  #|
  #|   const parseInto = (root, html, ownerDocument) => {
  #|     root.replaceChildren();
  #|     const stack = [root];
  #|     const tokens = html.match(/<!--[\s\S]*?-->|<\/?[A-Za-z][^>]*>|[^<]+/g) || [];
  #|     for (const token of tokens) {
  #|       if (token.startsWith("<!--")) continue;
  #|       if (!token.startsWith("<")) {
  #|         stack.at(-1).appendChild(new FakeText(ownerDocument, token));
  #|         continue;
  #|       }
  #|       if (token.startsWith("</")) {
  #|         if (stack.length > 1) stack.pop();
  #|         continue;
  #|       }
  #|       const open = token.match(/^<([A-Za-z][A-Za-z0-9-]*)([\s\S]*?)\/?\s*>$/);
  #|       if (!open) continue;
  #|       const element = ownerDocument.createElement(open[1]);
  #|       const attributes = open[2];
  #|       const attributePattern = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  #|       let match;
  #|       while ((match = attributePattern.exec(attributes))) {
  #|         element.setAttribute(match[1], decode(match[2] ?? match[3] ?? match[4] ?? ""));
  #|       }
  #|       stack.at(-1).appendChild(element);
  #|       if (!voidTags.has(element.tagName) && !token.endsWith("/>")) stack.push(element);
  #|     }
  #|   };
  #|
  #|   class FakeFragment extends FakeTree {
  #|     constructor(ownerDocument) { super(ownerDocument, 11, "#document-fragment"); }
  #|   }
  #|
  #|   class FakeElement extends FakeTree {
  #|     constructor(ownerDocument, tag) {
  #|       super(ownerDocument, 1, tag.toUpperCase());
  #|       this.tagName = tag.toUpperCase();
  #|       this.attributes = new Map();
  #|       this.disabled = false;
  #|       if (this.tagName === "TEMPLATE") this.content = new FakeFragment(ownerDocument);
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name.toLowerCase(), String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name.toLowerCase()) ?? null; }
  #|     removeAttribute(name) { this.attributes.delete(name.toLowerCase()); }
  #|     remove() { this.parentNode?.removeChild(this); }
  #|     set innerHTML(value) { parseInto(this.tagName === "TEMPLATE" ? this.content : this, value, this.ownerDocument); }
  #|     get children() { return this.childNodes.filter((child) => child.nodeType === 1); }
  #|   }
  #|
  #|   class FakeDocument extends FakeTree {
  #|     constructor() {
  #|       super(null, 9, "#document");
  #|       this.ownerDocument = this;
  #|     }
  #|     createElement(tag) { return new FakeElement(this, tag); }
  #|   }
  #|
  #|   globalThis.document = new FakeDocument();
  #|   globalThis.Element = FakeElement;
  #| }

///|
extern "js" fn markdown_test_target() -> @rdom.Element = "() => document.createElement('div')"

///|
extern "js" fn markdown_test_count(target : @rdom.Element, tag : String) -> Int = "(target, tag) => target.querySelectorAll(tag).length"

///|
extern "js" fn markdown_test_find_text(
  target : @rdom.Element,
  tag : String,
  text : String,
) -> @rdom.Element =
  #| (target, tag, text) => target.querySelectorAll(tag).find((element) => element.textContent === text)

///|
extern "js" fn markdown_test_at(
  target : @rdom.Element,
  tag : String,
  index : Int,
) -> @rdom.Element = "(target, tag, index) => target.querySelectorAll(tag)[index]"

///|
extern "js" fn markdown_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element.getAttribute(name) ?? ''"

///|
extern "js" fn markdown_test_listener_count(
  element : @rdom.Element,
  event_type : String,
) -> Int = "(element, type) => element.listenerCount(type)"

///|
extern "js" fn markdown_test_same_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool = "(left, right) => left === right"

///|
extern "js" fn markdown_test_dispatch_mouse(
  element : @rdom.Element,
  event_type : String,
  button : Int,
) -> Bool =
  #| (element, type, button) => {
  #|   const event = new Event(type, { cancelable: true });
  #|   Object.defineProperty(event, "button", { value: button });
  #|   element.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
extern "js" fn markdown_test_dispatch_key(
  element : @rdom.Element,
  key : String,
) -> Bool =
  #| (element, key) => {
  #|   const event = new Event("keydown", { cancelable: true });
  #|   Object.defineProperty(event, "key", { value: key });
  #|   element.dispatchEvent(event);
  #|   return event.defaultPrevented;
  #| }

///|
extern "js" fn markdown_test_dispatch_load(element : @rdom.Element) -> Unit = "(element) => element.dispatchEvent(new Event('load'))"

///|
extern "js" fn markdown_test_dispatch_vertical_wheel(
  element : @rdom.Element,
  delta_y : Int,
  scroll_top : Int,
  client_height : Int,
  scroll_height : Int,
) -> Int =
  #| (element, deltaY, scrollTop, clientHeight, scrollHeight) => {
  #|   for (const [name, value] of Object.entries({
  #|     scrollLeft: 0,
  #|     clientWidth: 100,
  #|     scrollWidth: 100,
  #|     scrollTop,
  #|     clientHeight,
  #|     scrollHeight,
  #|   })) {
  #|     Object.defineProperty(element, name, { configurable: true, value });
  #|   }
  #|   const event = new Event("wheel", { bubbles: true, cancelable: true });
  #|   Object.defineProperties(event, {
  #|     deltaX: { value: 0 },
  #|     deltaY: { value: deltaY },
  #|     shiftKey: { value: false },
  #|   });
  #|   element.dispatchEvent(event);
  #|   return (event.cancelBubble ? 1 : 0) | (event.defaultPrevented ? 2 : 0);
  #| }

///|
test "safe DOM and native-link URI policy resolve only allowed schemes" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let options = MarkdownRenderOptions(
    base_uri=try! @base_common.Uri::parse(
      "https://docs.example.test/base/index.html",
    ),
  )
  ignore(
    render_markdown(
      "<a href=\"https://raw.example\">raw</a>\n\n" +
      "[absolute](https://example.test/a) [relative](guide) " +
      "[mail](mailto:dev@example.test) [file](file:///tmp/a) " +
      "[command](command:test) [javascript](javascript:alert(1)) " +
      "[data](data:text/plain,x)",
      options~,
      target~,
    ),
  )
  // Raw HTML is omitted by the pure safe renderer; only Markdown anchors exist.
  assert_eq(markdown_test_count(target, "a"), 7)
  let absolute = markdown_test_find_text(target, "a", "absolute")
  assert_eq(markdown_test_attribute(absolute, "href"), "https://example.test/a")
  assert_eq(markdown_test_attribute(absolute, "target"), "_blank")
  assert_eq(markdown_test_attribute(absolute, "rel"), "noopener noreferrer")
  let relative = markdown_test_find_text(target, "a", "relative")
  assert_eq(
    markdown_test_attribute(relative, "href"),
    "https://docs.example.test/base/guide",
  )
  let mail = markdown_test_find_text(target, "a", "mail")
  assert_eq(markdown_test_attribute(mail, "href"), "mailto:dev@example.test")
  for text in ["file", "command", "javascript", "data"] {
    let inert = markdown_test_find_text(target, "a", text)
    assert_eq(markdown_test_attribute(inert, "href"), "")
    assert_eq(markdown_test_attribute(inert, "target"), "")
  }
}

///|
test "action links use only the handler for mouse and keyboard activation" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let activations : Array[String] = []
  let rendered = render_markdown(
    "[run](./run)",
    options=MarkdownRenderOptions(
      base_uri=try! @base_common.Uri::parse("https://example.test/docs/page"),
      action_handler=uri => activations.push(uri),
    ),
    target~,
  )
  let anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_attribute(anchor, "href"), "")
  assert_eq(markdown_test_attribute(anchor, "role"), "link")
  assert_eq(markdown_test_attribute(anchor, "tabindex"), "0")
  assert_true(markdown_test_dispatch_mouse(anchor, "click", 0))
  assert_true(markdown_test_dispatch_mouse(anchor, "auxclick", 1))
  assert_true(markdown_test_dispatch_key(anchor, "Enter"))
  assert_true(markdown_test_dispatch_key(anchor, " "))
  assert_true(markdown_test_dispatch_key(anchor, "Space"))
  assert_eq(activations.length(), 5)
  for uri in activations {
    assert_eq(uri, "https://example.test/docs/run")
  }
  rendered.dispose.dispose()
  rendered.dispose.dispose()
  assert_eq(markdown_test_listener_count(anchor, "click"), 0)
  assert_false(markdown_test_dispatch_mouse(anchor, "click", 0))
  assert_eq(activations.length(), 5)
}

///|
test "target reuse replaces children and releases every prior listener" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let activations : Array[String] = []
  let options = MarkdownRenderOptions(action_handler=uri => {
    activations.push(uri)
  })
  let first = render_markdown(
    "[first](https://example.test/first)",
    options~,
    target~,
  )
  let first_anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_listener_count(first_anchor, "click"), 1)
  assert_eq(markdown_test_listener_count(first_anchor, "auxclick"), 1)
  assert_eq(markdown_test_listener_count(first_anchor, "keydown"), 1)

  let second = render_markdown(
    "[second](https://example.test/second)",
    options~,
    target~,
  )
  assert_true(markdown_test_same_element(first.element, second.element))
  assert_eq(markdown_test_count(target, "a"), 1)
  let second_anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_listener_count(first_anchor, "click"), 0)
  assert_false(markdown_test_dispatch_mouse(first_anchor, "click", 0))
  first.dispose.dispose()
  // Disposing the superseded result cannot tear down the current lifetime.
  assert_eq(markdown_test_listener_count(second_anchor, "click"), 1)
  assert_true(markdown_test_dispatch_mouse(second_anchor, "click", 0))
  assert_eq(activations, ["https://example.test/second"])

  let third = render_markdown(
    "[third](https://example.test/third)",
    options~,
    target~,
  )
  let third_anchor = markdown_test_at(target, "a", 0)
  assert_eq(markdown_test_listener_count(second_anchor, "click"), 0)
  assert_eq(markdown_test_listener_count(third_anchor, "click"), 1)
  second.dispose.dispose()
  assert_eq(markdown_test_listener_count(third_anchor, "click"), 1)
  third.dispose.dispose()
  third.dispose.dispose()
  assert_eq(markdown_test_listener_count(third_anchor, "click"), 0)
}

///|
test "diagram wheel stays native until the scroll boundary and listener disposal" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  let rendered = render_markdown(
    "```graph\nsource\n```",
    options=MarkdownRenderOptions(code_block_renderer=fn(_block, _language) {
      "<div class=\"moonbit-viewer-markdown-diagram\" data-diagram-language=\"diago\"><svg></svg></div>"
    }),
    target~,
  )
  let diagram = markdown_test_at(target, "div", 0)
  assert_eq(markdown_test_listener_count(diagram, "wheel"), 1)
  // Downward motion inside the available range stays with the diagram and is
  // not preventDefault-ed, so the browser retains its native scrolling.
  assert_eq(markdown_test_dispatch_vertical_wheel(diagram, 120, 0, 100, 300), 1)
  assert_eq(
    markdown_test_dispatch_vertical_wheel(diagram, -120, 100, 100, 300),
    1,
  )
  // At either boundary the event is handed back to the owning surface.
  assert_eq(
    markdown_test_dispatch_vertical_wheel(diagram, -120, 0, 100, 300),
    0,
  )
  assert_eq(
    markdown_test_dispatch_vertical_wheel(diagram, 120, 200, 100, 300),
    0,
  )
  rendered.dispose.dispose()
  assert_eq(markdown_test_listener_count(diagram, "wheel"), 0)
  assert_eq(markdown_test_dispatch_vertical_wheel(diagram, 120, 0, 100, 300), 0)
}

///|
test "remote images are opt-in and load callbacks become inert after dispose" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  ignore(
    render_markdown(
      "![denied](image.png)",
      options=MarkdownRenderOptions(
        base_uri=try! @base_common.Uri::parse("https://img.example.test/docs/"),
      ),
      target~,
    ),
  )
  assert_eq(markdown_test_count(target, "img"), 0)

  let size_changes = Ref(0)
  let allowed = render_markdown(
    "![allowed](image.png)",
    options=MarkdownRenderOptions(
      base_uri=try! @base_common.Uri::parse("https://img.example.test/docs/"),
      on_size_changed=() => size_changes.val += 1,
      allow_remote_images=true,
    ),
    target~,
  )
  assert_eq(markdown_test_count(target, "img"), 1)
  let image = markdown_test_at(target, "img", 0)
  assert_eq(
    markdown_test_attribute(image, "src"),
    "https://img.example.test/docs/image.png",
  )
  assert_eq(markdown_test_listener_count(image, "load"), 1)
  markdown_test_dispatch_load(image)
  assert_eq(size_changes.val, 1)
  allowed.dispose.dispose()
  assert_eq(markdown_test_listener_count(image, "load"), 0)
  markdown_test_dispatch_load(image)
  assert_eq(size_changes.val, 1)
}

///|
test "postprocess removes non-checkbox inputs and disables task checkboxes" {
  install_markdown_test_dom()
  let target = markdown_test_target()
  ignore(
    render_markdown(
      "```\nignored\n```",
      options=MarkdownRenderOptions(code_block_renderer=fn(_block, _language) {
        "<input type=\"text\"><input type=\"checkbox\">"
      }),
      target~,
    ),
  )
  assert_eq(markdown_test_count(target, "input"), 1)
  let checkbox = markdown_test_at(target, "input", 0)
  assert_eq(markdown_test_attribute(checkbox, "type"), "checkbox")
  // Boolean disabled attributes serialize as the empty string in the fake DOM.
  assert_eq(markdown_test_attribute(checkbox, "disabled"), "")
}
