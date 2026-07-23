# viewer/common

A small compatibility facade over the focused common-layer packages.

The only production implementation is `line_html.mbt`:

- `escape_html`
- `render_line_class`
- `render_line_html`, which adapts `view_model.ViewLineData` and
  `view_layout.LineDecoration[]` to the DOM-free Monaco-shaped view-line renderer

Mouse targets and hit testing do **not** live here. Browser event/target values are
in `viewer/browser`, and the hit-test implementation is in
`internal/viewer/browser/controller`.

This package may depend on `viewer/common/editor_api`,
`viewer/common/view_layout`, and `viewer/common/view_model`; it must remain
DOM/FFI/host independent and build for JS and native. The complete surface is
`pkg.generated.mbti`; run
`moon test --target js viewer/common` for focused coverage.
