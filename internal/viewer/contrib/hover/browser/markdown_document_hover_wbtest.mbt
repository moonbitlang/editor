///|
test "Markdown hover geometry uses pointer x line rect and viewport clamps" {
  // Fits below; x is relative to the viewport.
  assert_eq(
    markdown_hover_clamped_origin(
      180.0, 120.0, 140.0, 100.0, 100.0, 400.0, 300.0, 120.0, 80.0,
    ),
    (40.0, 80.0),
  )
  // Does not fit below, so use the rendered line's top edge and clamp both
  // axes into the viewport.
  assert_eq(
    markdown_hover_clamped_origin(
      590.0, 350.0, 370.0, 100.0, 100.0, 400.0, 300.0, 120.0, 100.0,
    ),
    (150.0, 280.0),
  )
}

///|
test "Markdown hover geometry coalesces client rects within visual rows" {
  assert_eq(
    markdown_hover_fragment_geometry([
      // Computed line height and the logical line's two-row box height.
      20.0, 40.0,
      // Raw client rects are deliberately out of visual order.
       2.0, 23.0, 8.0, 14.0, 15.0, 3.0, 7.0, 14.0, 10.0, 3.0, 5.0, 14.0,
      // A same-row bidi-style gap remains a separate fragment.
       40.0, 3.0, 4.0, 14.0,
    ]),
    [10.0, 0.0, 12.0, 20.0, 40.0, 0.0, 4.0, 20.0, 2.0, 20.0, 8.0, 20.0],
  )
  // Monaco's non-showIfCollapsed hover decoration does not widen an empty
  // range merely to make it visible.
  assert_eq(
    markdown_hover_fragment_geometry([20.0, 20.0, 5.0, 3.0, 0.0, 14.0]),
    [5.0, 0.0, 0.0, 20.0],
  )
}

///|
test "caret FFI exposes one text node while MoonBit owns UTF-16 tree mapping" {
  install_markdown_caret_test_document()
  defer restore_markdown_caret_test_document()
  let document = @rdom.document()
  let line = document.create_element("span")
  let prefix = document.create_element("span")
  prefix.append_child(document.create_text_node("ab").as_node())
  let nested = document.create_element("strong")
  let target = document.create_text_node("🪐z")
  nested.append_child(target.as_node())
  line.append_child(prefix.as_node())
  line.append_child(nested.as_node())
  markdown_caret_test_set_hit(target.as_node(), 2)
  let hit = markdown_native_caret_hit(line, 10.0, 20.0)
  assert_true(markdown_native_caret_hit_ok(hit))
  let hit_node = markdown_native_caret_hit_node(hit)
  assert_true(hit_node.is_same_node(target.as_node()))
  assert_eq(markdown_native_caret_hit_offset(hit), 2)
  assert_true(markdown_node_is_descendant_of(hit_node, line))
  let (found, displayed_boundary) = markdown_text_units_before_node(
    line.as_node(),
    hit_node,
    2,
  )
  assert_true(found)
  // "ab" = 2 UTF-16 units, the astral symbol = 2 more.
  assert_eq(displayed_boundary, 4)

  // Range endpoint lookup is also MoonBit-owned. Preserve the old TreeWalker
  // bias at adjacent text-node boundaries and count astral text in UTF-16
  // units.
  guard markdown_text_boundary_at(line.as_node(), 2) is Some(prefix_end) else {
    fail("expected prefix boundary")
  }
  assert_true(prefix_end.node.is_same_node(prefix.get_child(0)))
  assert_eq(prefix_end.offset, 2)
  guard markdown_text_boundary_at(line.as_node(), 4) is Some(target_boundary) else {
    fail("expected nested text boundary")
  }
  assert_true(target_boundary.node.is_same_node(target.as_node()))
  assert_eq(target_boundary.offset, 2)
  assert_true(markdown_text_boundary_at(line.as_node(), 6) is None)

  // WebKit's legacy Range-shaped caret answer passes through the same
  // primitive accessors and MoonBit text-node validation.
  markdown_caret_test_use_range_api()
  markdown_caret_test_set_hit(target.as_node(), 1)
  let range_hit = markdown_native_caret_hit(line, 10.0, 20.0)
  assert_true(markdown_native_caret_hit_ok(range_hit))
  assert_true(
    markdown_native_caret_hit_node(range_hit).is_same_node(target.as_node()),
  )
  assert_eq(markdown_native_caret_hit_offset(range_hit), 1)

  // Element-container hits are rejected before block lookup, so no source
  // request can be invented from them.
  markdown_caret_test_set_hit(line.as_node(), 0)
  assert_false(
    markdown_native_caret_hit_ok(markdown_native_caret_hit(line, 10.0, 20.0)),
  )
}

///|
extern "js" fn install_markdown_caret_test_document() -> Unit =
  #| () => {
  #|   globalThis.__markdownCaretPreviousDocument = globalThis.document;
  #|   const document = {
  #|     __hitNode: null,
  #|     __hitOffset: 0,
  #|     createElement(tag) {
  #|       const element = {
  #|         nodeType: 1,
  #|         nodeName: String(tag).toUpperCase(),
  #|         ownerDocument: document,
  #|         parentNode: null,
  #|         childNodes: [],
  #|         appendChild(child) {
  #|           child.parentNode = this;
  #|           this.childNodes.push(child);
  #|           return child;
  #|         },
  #|         isSameNode(other) { return this === other; },
  #|       };
  #|       return element;
  #|     },
  #|     createTextNode(text) {
  #|       return {
  #|         nodeType: 3,
  #|         nodeName: "#text",
  #|         ownerDocument: document,
  #|         parentNode: null,
  #|         childNodes: [],
  #|         textContent: String(text),
  #|         isSameNode(other) { return this === other; },
  #|       };
  #|     },
  #|     caretPositionFromPoint() {
  #|       return {
  #|         offsetNode: document.__hitNode,
  #|         offset: document.__hitOffset,
  #|       };
  #|     },
  #|   };
  #|   globalThis.document = document;
  #| }

///|
extern "js" fn markdown_caret_test_set_hit(
  node : @rdom.Node,
  offset : Int,
) -> Unit =
  #| (node, offset) => {
  #|   globalThis.document.__hitNode = node;
  #|   globalThis.document.__hitOffset = offset;
  #| }

///|
extern "js" fn markdown_caret_test_use_range_api() -> Unit =
  #| () => {
  #|   const document = globalThis.document;
  #|   document.caretPositionFromPoint = undefined;
  #|   document.caretRangeFromPoint = () => ({
  #|     startContainer: document.__hitNode,
  #|     startOffset: document.__hitOffset,
  #|   });
  #| }

///|
extern "js" fn restore_markdown_caret_test_document() -> Unit =
  #| () => {
  #|   const previous = globalThis.__markdownCaretPreviousDocument;
  #|   if (previous === undefined) delete globalThis.document;
  #|   else globalThis.document = previous;
  #|   delete globalThis.__markdownCaretPreviousDocument;
  #| }
