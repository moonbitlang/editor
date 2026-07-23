///|
#external
type DomPrimitiveFixture

///|
extern "js" fn new_dom_primitive_fixture() -> DomPrimitiveFixture =
  #| () => {
  #|   const child = {};
  #|   const style = new Map();
  #|   const ownerDocument = { activeElement: child };
  #|   const element = {
  #|     offsetWidth: 37,
  #|     offsetHeight: 19,
  #|     ownerDocument,
  #|     style: { setProperty: (name, value) => style.set(name, value) },
  #|     contains: candidate => candidate === element || candidate === child,
  #|     focus: options => { element.focusOptions = options; },
  #|     remove: () => { element.removed = true; },
  #|   };
  #|   return { element, child, ownerDocument, style };
  #| }

///|
extern "js" fn dom_primitive_fixture_element(
  fixture : DomPrimitiveFixture,
) -> @rdom.Element = "(fixture) => fixture.element"

///|
extern "js" fn dom_primitive_fixture_child(
  fixture : DomPrimitiveFixture,
) -> @rdom.Element = "(fixture) => fixture.child"

///|
extern "js" fn dom_primitive_fixture_style(
  fixture : DomPrimitiveFixture,
  name : String,
) -> String = "(fixture, name) => fixture.style.get(name) ?? ''"

///|
extern "js" fn dom_primitive_fixture_prevented_scroll(
  fixture : DomPrimitiveFixture,
) -> Bool = "(fixture) => fixture.element.focusOptions?.preventScroll === true"

///|
extern "js" fn dom_primitive_fixture_removed(
  fixture : DomPrimitiveFixture,
) -> Bool = "(fixture) => fixture.element.removed === true"

///|
extern "js" fn dom_primitive_fixture_focus_element(
  fixture : DomPrimitiveFixture,
) -> Unit = "(fixture) => { fixture.ownerDocument.activeElement = fixture.element; }"

///|
test "canonical DOM primitives preserve layout style lifecycle and focus semantics" {
  let fixture = new_dom_primitive_fixture()
  let element = dom_primitive_fixture_element(fixture)
  let child = dom_primitive_fixture_child(fixture)
  assert_eq(element_offset_width(element), 37.0)
  assert_eq(element_offset_height(element), 19.0)
  set_style_property(element, "width", "12px")
  assert_eq(dom_primitive_fixture_style(fixture, "width"), "12px")
  assert_true(element_contains(element, child))
  assert_true(element_contains_active_element(element))
  assert_false(element_has_focus(element))
  focus_prevent_scroll(element)
  assert_true(dom_primitive_fixture_prevented_scroll(fixture))
  dom_primitive_fixture_focus_element(fixture)
  assert_true(element_has_focus(element))
  remove_element(element)
  remove_element(element)
  assert_true(dom_primitive_fixture_removed(fixture))
}

///|
#external
type DomInputOwnershipFixture

///|
extern "js" fn new_dom_input_ownership_fixture() -> DomInputOwnershipFixture =
  #| () => {
  #|   const selector = '.caller-owned';
  #|   const makeElement = (parentElement = null, owned = false) => {
  #|     const element = {
  #|       nodeType: 1,
  #|       parentElement,
  #|       owned,
  #|       closest(candidate) {
  #|         if (candidate === '[') throw new SyntaxError('invalid selector');
  #|         if (candidate !== selector) return null;
  #|         for (let current = element; current; current = current.parentElement) {
  #|           if (current.owned) return current;
  #|         }
  #|         return null;
  #|       },
  #|       contains(candidate) {
  #|         for (let current = candidate; current; current = current.parentElement) {
  #|           if (current === element) return true;
  #|         }
  #|         return false;
  #|       },
  #|     };
  #|     return element;
  #|   };
  #|   const root = makeElement();
  #|   const plain = makeElement(root);
  #|   const owned = makeElement(root, true);
  #|   const ownedChild = makeElement(owned);
  #|   const ownedText = { nodeType: 3, parentElement: ownedChild };
  #|   const outsideOwned = makeElement(null, true);
  #|   const outsideChild = makeElement(outsideOwned);
  #|   const selection = {
  #|     isCollapsed: true,
  #|     anchorNode: plain,
  #|     focusNode: plain,
  #|   };
  #|   root.ownerDocument = { getSelection: () => selection };
  #|   return {
  #|     selector,
  #|     root,
  #|     targets: [root, plain, ownedChild, ownedText, outsideChild],
  #|     selection,
  #|   };
  #| }

///|
extern "js" fn dom_input_ownership_root(
  fixture : DomInputOwnershipFixture,
) -> @rdom.Element = "(fixture) => fixture.root"

///|
extern "js" fn dom_input_ownership_event(
  fixture : DomInputOwnershipFixture,
  target_index : Int,
) -> @rdom.Event = "(fixture, targetIndex) => ({ target: fixture.targets[targetIndex] })"

///|
extern "js" fn dom_input_ownership_set_selection(
  fixture : DomInputOwnershipFixture,
  anchor_index : Int,
  focus_index : Int,
  collapsed : Bool,
) -> Unit =
  #| (fixture, anchorIndex, focusIndex, collapsed) => {
  #|   fixture.selection.anchorNode = fixture.targets[anchorIndex];
  #|   fixture.selection.focusNode = fixture.targets[focusIndex];
  #|   fixture.selection.isCollapsed = collapsed;
  #| }

///|
test "event target probes distinguish the listener surface and bounded caller ancestry" {
  let fixture = new_dom_input_ownership_fixture()
  let root = dom_input_ownership_root(fixture)
  let root_event = dom_input_ownership_event(fixture, 0)
  let plain_event = dom_input_ownership_event(fixture, 1)
  let owned_event = dom_input_ownership_event(fixture, 2)
  let owned_text_event = dom_input_ownership_event(fixture, 3)
  let outside_event = dom_input_ownership_event(fixture, 4)
  assert_true(event_target_is(root_event, root))
  assert_false(event_target_is(plain_event, root))
  assert_false(
    event_target_has_matching_ancestor(plain_event, root, ".caller-owned"),
  )
  assert_true(
    event_target_has_matching_ancestor(owned_event, root, ".caller-owned"),
  )
  assert_true(
    event_target_has_matching_ancestor(owned_text_event, root, ".caller-owned"),
  )
  assert_false(
    event_target_has_matching_ancestor(outside_event, root, ".caller-owned"),
  )
  assert_false(event_target_has_matching_ancestor(owned_event, root, "["))
}

///|
test "native selection probe checks both non-collapsed bounded endpoints" {
  let fixture = new_dom_input_ownership_fixture()
  let root = dom_input_ownership_root(fixture)
  dom_input_ownership_set_selection(fixture, 1, 1, true)
  assert_false(
    native_selection_has_endpoint_in_matching_ancestor(root, ".caller-owned"),
  )
  dom_input_ownership_set_selection(fixture, 1, 3, false)
  assert_true(
    native_selection_has_endpoint_in_matching_ancestor(root, ".caller-owned"),
  )
  dom_input_ownership_set_selection(fixture, 3, 1, false)
  assert_true(
    native_selection_has_endpoint_in_matching_ancestor(root, ".caller-owned"),
  )
  dom_input_ownership_set_selection(fixture, 1, 4, false)
  assert_false(
    native_selection_has_endpoint_in_matching_ancestor(root, ".caller-owned"),
  )
  assert_false(native_selection_has_endpoint_in_matching_ancestor(root, "["))
}
