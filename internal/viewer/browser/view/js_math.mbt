// JavaScript numeric shims shared by this package's DOM geometry. They belong
// to no single Monaco source unit, so they live here rather than in whichever
// view part happened to need one first.

///|
/// JavaScript `Math.round` for finite CSS/DOM geometry. In particular, negative
/// half values round toward positive infinity (`Math.round(-7.5) === -7`),
/// unlike the usual ties-away-from-zero rule on some MoonBit backends. Callers
/// that need a pixel integer follow this with `to_int`; the style and placement
/// pipelines keep the `Double`.
fn js_math_round(value : Double) -> Double {
  (value + 0.5).floor()
}
