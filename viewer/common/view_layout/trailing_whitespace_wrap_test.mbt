// Stage-1 branch coverage for the `Trailing × continues_with_wrapped_line`
// gate (plan: monaco-render-whitespace-control-options-port.md test matrix).
// The conformance suite covers Trailing and `continues_with_wrapped_line`
// separately (`ws-trail-*`, `issue-38123` for Boundary) but not their
// intersection, which is the gate at `render_line_renderer.mbt:191`:
//   render_whitespace == Trailing && !continues_with_wrapped_line
// A soft-wrapped continuation suppresses the trailing-whitespace glyphs so the
// wrap join does not sprout dots; the final segment still renders them.

///|
test "trailing whitespace renders only when the line does not continue wrapped" {
  let rendered = mr(
    "ab  ",
    [p(4, 1)],
    use_monospace_optimizations=true,
    render_whitespace=Trailing,
    continues_with_wrapped_line=false,
  )
  assert_true(rendered.html.contains("mtkw"))
  let suppressed = mr(
    "ab  ",
    [p(4, 1)],
    use_monospace_optimizations=true,
    render_whitespace=Trailing,
    continues_with_wrapped_line=true,
  )
  assert_false(suppressed.html.contains("mtkw"))
}
