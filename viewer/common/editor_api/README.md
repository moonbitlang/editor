# Editor API value contracts

This multi-target package owns DOM-free values shared by the public Viewer
facade and lower editor packages. It is dependency-bottom: imports are limited
to `base/common` and `viewer/common/core`.

`CursorChangeReason`, cursor/model/scroll events, and
`ScrolledVisiblePosition` have one declaration here. Internal cursor,
view-model, browser, and root packages consume these types directly; they do
not define facade copies or translate variants.

Canonical editor option enums also live here: `WrappingIndent`,
`RenderWhitespace`, `RenderLineHighlight`, `RenderValidationDecorations`, and
`ShowFoldingControls`. Rendering, view-model, and folding packages retain the
behavior that interprets those values; they import the enum contract instead
of defining a package-local copy.
