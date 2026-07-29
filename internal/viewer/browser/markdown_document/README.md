# internal/viewer/browser/markdown_document

JS-only document presentation owned by the Viewer layer. It keeps a focusable
root, a native scroll viewport, a reusable Markdown article target, and a
viewport-fixed overlay mount as separate DOM capabilities.

Rendering delegates to `internal/viewer/browser/markdown`. The retained
`MarkdownDocumentProjection` is therefore the exact projection produced by the
same cmark parse as the installed HTML. Every source or theme replacement
advances `projection_generation` and records the source model content version.
The single post-render pass stamps source anchors and leaves stable
`data-markdown-code-block="<block_index>"` wrappers for source-aware browser
features.

The package owns no model and no provider. Root `viewer` owns presentation
selection, content subscriptions, model-coordinate conversion, public routing,
and lifecycle. The overlay mount is deliberately outside the replaceable
article so a later hover lifetime cannot be deleted by a content refresh.

Run the focused suite with:

```sh
MOON_WORK=off moon test --target js internal/viewer/browser/markdown_document
```
