# internal/viewer/contrib/hover/browser

The JS-only content-hover browser implementation. It owns mouse-target event
reduction, anchor discovery, the concrete hover controller, DOM rendering and
geometry, and the persistent scrollable content widget. The root Viewer owns
the controller lifetime, timers, provider execution, decorations, and widget
mounting.

DOM-free hover state, participants, reconciliation, and fenced-code
tokenization live in `internal/viewer/contrib/hover`. The widget builds the
Monaco-shaped row/wrapper DOM and renders Markdown through
`internal/viewer/browser/markdown` into retained `.hover-contents` targets. It
owns every returned render disposable and clears those lifetimes on content
replacement, hide, and retained-widget teardown. Browser view and scrollbar
dependencies are internal packages under `internal/viewer/**`. The emitted
stylesheet remains at `viewer/contrib/hover/hover.css`.

`render_hover_rows` is the shared safe row-rendering boundary. It returns a
single-owner `HoverRowsRender`: `mount_into` succeeds at most once, and
`dispose` is idempotent and releases every nested Markdown renderer. Both the
Code content widget and the Markdown document bridge use this lifetime, so
they share content and sanitization policy without sharing widget state.

`MarkdownDocumentHoverBridge` is a presentation-local bridge over the original
`TextModel` and owns one retained `MarkdownDocumentHoverWidget`. Browser FFI
supplies only caret text-node offsets and measured DOM rectangles; MoonBit
resolves the retained semantic row, converts its UTF-16 boundary to the
original model position, runs `ContentHoverComputer`, projects live marker
decorations, and owns request cancellation. A changing pointer replaces one
clearable first-wait timer; only a source boundary held for the shared 150 ms
first-wait launches semantic work, and a still-pending request displays the
shared loading row roughly 900 ms after the pointer settles (plus synchronous
computation time). This presentation-local bridge intentionally omits Code's
separate 300 ms display gate. Every async completion is gated by model identity,
caller and content versions, URI/revision, attach generation, projection
generation/source version, block identity, source offset, and request token.
Content, theme, and model replacement invalidate the relevant state before
presentation DOM replacement. Layout may update geometry synchronously first;
layout, marker change, pointer exit, and disposal still invalidate freshness
before a pending async hover may commit. Before measuring each row set, the
widget temporarily releases its previous locked box against the full Markdown
viewport, then clamps and locks the resulting readable natural size.

Projected diagnostics consume the marker package's resolved class, z-index,
and range metadata in the same overlay order as Code. Markdown owns the visible
severity squiggles plus the `showUnused` underline gate. Monaco's inline
unnecessary opacity and deprecated strike change the actual source glyphs;
those text-mutating effects are intentionally deferred for the readonly
Markdown projection rather than approximated on an empty overlay span.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/hover/browser --target js
```
