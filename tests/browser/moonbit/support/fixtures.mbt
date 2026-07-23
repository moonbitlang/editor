///|
/// Text content for the first element matching `selector`.
pub extern "js" fn query_text(selector : String) -> String =
  #| (selector) => document.querySelector(selector)?.textContent ?? ""

///|
/// Number of elements matching `selector`.
pub extern "js" fn query_count(selector : String) -> Int =
  #| (selector) => document.querySelectorAll(selector).length

///|
/// Attribute value for the first element matching `selector`.
pub extern "js" fn query_attribute(selector : String, name : String) -> String =
  #| (selector, name) => document.querySelector(selector)?.getAttribute(name) ?? ""

///|
/// Browser timer helper for MoonBit-authored test code.
pub extern "js" fn set_timeout(callback : () -> Unit, ms : Int) -> Unit =
  #| (callback, ms) => {
  #|   globalThis.setTimeout(callback, Number(ms) || 0);
  #| }

///|
/// Monotonic browser timestamp in milliseconds.
pub extern "js" fn now_ms() -> Double =
  #| () => globalThis.performance?.now() ?? Date.now()
