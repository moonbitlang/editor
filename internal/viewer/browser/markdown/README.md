# internal/viewer/browser/markdown

MoonBit-owned DOM policy and lifetime management for shared browser Markdown
rendering, with narrow JS bindings for browser parsing, URL resolution, target
registries, dynamic import, and Mermaid API calls.

`render_markdown` converts through `internal/viewer/markdown`, postprocesses the
result in an inert template, and then replaces the children of an explicit
reusable target (or a newly created `div`). Links and images are resolved and
sanitized before insertion. Action-handler links never retain native
navigation; native links are limited to HTTP, HTTPS, and mailto. Images are
removed by default and, when enabled, are limited to HTTP(S).

`RenderedMarkdown.projection` is the exact DOM-free
`MarkdownDocumentProjection` produced by the same cmark parse and configuration
as its installed HTML. Browser consumers must retain this value instead of
parsing source again. `open_external_link` is the shared action-handler
capability for already-sanitized links; it opens with
`noopener,noreferrer` and clears the returned window's opener.

Scrollable diagram wrappers retain native wheel scrolling while they can
consume the current delta. When neither axis can consume it, the event is
allowed to reach the owning hover, widget, or editor scroller.

`moonbit-viewer-markdown-diagram-viewport` is an event-time ownership marker:
while a wrapper carries it, this generic listener never stops ordinary wheel
input. The Markdown-comment viewport controller can therefore mount after the
renderer listener and return ordinary wheel input to the editor while owning
its modifier-zoom events. Removing the marker restores the native inner-scroll
handoff, so hover and agent-feedback diagrams keep their existing behavior.

Mermaid rendering is an explicit browser-only opt-in. Pass
`mermaid_theme=Light` or `mermaid_theme=Dark` and emit a
`div.moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]` whose
text content is the safe source fallback. The adapter lazily imports Mermaid's
official ESM build from the pinned URL
`https://cdn.jsdelivr.net/npm/mermaid@11.16.0/dist/mermaid.esm.min.mjs`; no
marked wrapper means no import. `Light` selects Mermaid's `default` theme and
`Dark` selects `dark`. Call `RenderedMarkdown::rerender_mermaid` when the
retained target's theme changes. Source extraction preserves the tokenized
fallback's line structure by translating its `<br>` elements back to newline
characters before invoking Mermaid.

One realm-wide MoonBit runtime caches the loaded Mermaid API, retries after a
failed load, and serializes `initialize` plus `render`. It applies strict
security, suppresses source-side error rendering, and protects theme
configuration from diagram frontmatter. MoonBit-owned per-diagram epochs,
target ownership, and containment checks reject stale commits. A successful
SVG replacement invokes the existing size callback. Loading, CSP, syntax,
stale-result, target-reuse, and disposal failures retain the source fallback or
last successful SVG.

Hosts using Mermaid must allow `https://cdn.jsdelivr.net` in the applicable
module-script CSP directive, including Mermaid's relative ESM chunks, and allow
Mermaid's inline SVG styling. Dynamic `import()` has no SRI parameter, so the
exact versioned URL is the reproducibility boundary. Offline or blocked-CDN
operation remains usable through the visible source fallback.

The returned `RenderedMarkdown.dispose` releases the MoonBit-owned listener
disposables and makes late load and Mermaid callbacks inert. A realm-wide
`WeakMap` only registers the current MoonBit lifetime token for each reusable
target; rendering into that target first disposes its previous renderer-owned
lifetime while leaving the caller-owned target itself in place.

Run the focused JS suite with:

```sh
moon test internal/viewer/browser/markdown --target js
```
