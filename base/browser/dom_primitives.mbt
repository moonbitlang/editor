///|
/// Reads the element's inner layout width, including padding but excluding
/// borders and scrollbars. This is the `clientWidth` used by Monaco's
/// `ElementSizeObserver`; unlike a bounding rect it ignores CSS transforms.
pub extern "js" fn element_client_width(element : @rdom.Element) -> Double =
  #| (element) => element?.clientWidth ?? 0

///|
/// Reads the element's inner layout height with `clientHeight` semantics.
pub extern "js" fn element_client_height(element : @rdom.Element) -> Double =
  #| (element) => element?.clientHeight ?? 0

///|
/// Reads the element's unscaled layout width. This intentionally remains
/// distinct from `get_bounding_client_rect`, whose dimensions include CSS
/// transforms.
pub extern "js" fn element_offset_width(element : @rdom.Element) -> Double =
  #| (element) => element?.offsetWidth ?? 0

///|
/// Reads the element's unscaled layout height.
pub extern "js" fn element_offset_height(element : @rdom.Element) -> Double =
  #| (element) => element?.offsetHeight ?? 0

///|
/// Writes one inline CSS property without replacing sibling properties.
pub extern "js" fn set_style_property(
  element : @rdom.Element,
  name : String,
  value : String,
) -> Unit =
  #| (element, name, value) => { element.style.setProperty(name, value); }

///|
/// Removes an element if attached. `HTMLElement.remove()` is idempotent; the
/// parent-node fallback preserves that behavior for narrow test DOMs.
pub extern "js" fn remove_element(element : @rdom.Element) -> Unit =
  #| (element) => {
  #|   if (typeof element?.remove === "function") element.remove();
  #|   else element?.parentNode?.removeChild(element);
  #| }

///|
/// Focuses an element without allowing the browser to scroll it into view.
pub extern "js" fn focus_prevent_scroll(element : @rdom.Element) -> Unit =
  #| (element) => element?.focus?.({ preventScroll: true })

///|
/// Whether `child` is the container itself or one of its descendants.
pub extern "js" fn element_contains(
  container : @rdom.Element,
  child : @rdom.Element,
) -> Bool =
  #| (container, child) => Boolean(container?.contains?.(child))

///|
/// Whether the element's owner document currently focuses the element.
pub extern "js" fn element_has_focus(element : @rdom.Element) -> Bool =
  #| (element) => Boolean(element?.ownerDocument?.activeElement === element)

///|
/// Whether the active element from this element's owner document is contained
/// by the element. Using the owner document preserves iframe/document seams.
pub extern "js" fn element_contains_active_element(
  element : @rdom.Element,
) -> Bool =
  #| (element) => {
  #|   const active = element?.ownerDocument?.activeElement;
  #|   return Boolean(active && element.contains(active));
  #| }

///|
/// Whether this DOM event originated exactly at `element`. This is stricter
/// than listener placement: a listener on `element` also receives events that
/// bubble from descendants.
pub extern "js" fn event_target_is(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool =
  #| (event, element) => event?.target === element

///|
/// Whether the event target is inside an ancestor matching `selector`, with
/// that matching ancestor itself contained by `boundary`. Text-node targets
/// start at their parent element. Invalid selectors and narrow test DOMs are
/// treated as misses rather than escaping the input boundary.
pub extern "js" fn event_target_has_matching_ancestor(
  event : @rdom.Event,
  boundary : @rdom.Element,
  selector : String,
) -> Bool =
  #| (event, boundary, selector) => {
  #|   const target = event?.target;
  #|   const element = target?.nodeType === 1 ? target : target?.parentElement;
  #|   try {
  #|     const match = element?.closest?.(selector);
  #|     return Boolean(match && boundary?.contains?.(match));
  #|   } catch {
  #|     return false;
  #|   }
  #| }

///|
/// Whether either endpoint of the owner document's non-collapsed native DOM
/// selection is inside an ancestor matching `selector`, bounded by
/// `boundary`. Both endpoints are checked deliberately: a selection crossing
/// into or out of caller-owned DOM must remain under the browser's copy path.
pub extern "js" fn native_selection_has_endpoint_in_matching_ancestor(
  boundary : @rdom.Element,
  selector : String,
) -> Bool =
  #| (boundary, selector) => {
  #|   const selection = boundary?.ownerDocument?.getSelection?.();
  #|   if (!selection || selection.isCollapsed) return false;
  #|   const endpointMatches = (node) => {
  #|     const element = node?.nodeType === 1 ? node : node?.parentElement;
  #|     try {
  #|       const match = element?.closest?.(selector);
  #|       return Boolean(match && boundary?.contains?.(match));
  #|     } catch {
  #|       return false;
  #|     }
  #|   };
  #|   return endpointMatches(selection.anchorNode) ||
  #|     endpointMatches(selection.focusNode);
  #| }
