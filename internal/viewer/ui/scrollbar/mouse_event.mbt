///|
/// `StandardWheelEvent` (vs/base/browser/mouseEvent.ts): a browser wheel
/// event normalized into Monaco wheel units — positive scrolls up/left, one
/// unit is one physical wheel notch (120 legacy `wheelDelta`, 40 pixels, or
/// one line). Only the modern `e.type === 'wheel'` branch is ported: the
/// legacy `wheelDeltaY / 120` and Gecko `detail / 3` branches read fields
/// rabbita/dom does not bind, and on Chromium/WebKit `wheelDeltaY` is
/// `3 × -deltaY`, so `wheelDeltaY / 120` and `-deltaY / 40` are the same
/// number. (deviation: the Firefox-on-non-mac line-mode `/ 3` quirk rides
/// on the dropped browser sniffing and is omitted with it.)
pub struct StandardWheelEvent {
  delta_x : Double
  delta_y : Double
}

///|
/// `WheelEvent.DOM_DELTA_LINE`: the deltas are expressed in lines.
const DOM_DELTA_LINE : Int = 1

///|
#alias(new)
pub fn StandardWheelEvent::StandardWheelEvent(
  e : @rdom.WheelEvent,
) -> StandardWheelEvent {
  if e.get_delta_mode() == DOM_DELTA_LINE {
    { delta_x: -e.get_delta_x(), delta_y: -e.get_delta_y() }
  } else {
    { delta_x: -e.get_delta_x() / 40.0, delta_y: -e.get_delta_y() / 40.0 }
  }
}
