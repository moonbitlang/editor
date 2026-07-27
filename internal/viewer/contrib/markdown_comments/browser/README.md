# internal/viewer/contrib/markdown_comments/browser

JS-only DOM and measurement ownership for rendered whole-line Markdown
comments. `MarkdownCommentDom` creates the stable ViewZone outer/content pair;
the root contribution retains the outer node as its ViewZone DOM and renders
shared Markdown into the inner node.

`observe_size` watches only the auto-height inner content. The root
contribution owns one model-scoped viewport-width observer and invalidates all
live comment size observers when that width changes. Resize notifications and
explicit viewport/renderer/image invalidations are coalesced through the
realm-global `base/browser` animation-frame coordinator. A connected offscreen
ViewZone is temporarily laid out invisibly using its already pinned
viewport-safe width and horizontal offset; measurement never replaces
`width` or `left`, and every touched inline style and priority is restored
before its integer height is reported. The returned
`MarkdownCommentSizeObserver` exposes `request_measure` and idempotent
`dispose`; zero-size restore notifications cannot create a feedback loop.
Disposal disconnects observation, cancels queued frame work, and makes late
notifications inert. The root contribution remains responsible for the shared
viewport observer, geometry lease, generation, and zone-id freshness.

`MarkdownCommentDiagramViewports` owns every successfully rendered direct
Diago SVG viewport inside one Markdown-comment target. It mounts the
transformable content, four controls, resize handle, listeners, animation
frame, and per-wrapper `ResizeObserver`, while leaving the target and original
wrapper caller-owned. MoonBit structs retain the group/controller lifetime and
all pan/zoom/fit/resize state. The root entry's disposal-before-replacement
contract gives the group exclusive wrapper ownership, so the implementation
does not place private ownership tokens on DOM nodes. A module-private
per-document coordinator grants at most one temporary body-cursor lease during
resize; it restores the exact prior inline value and priority on release.
Narrow FFI fills browser binding gaps only. Each inline viewport-height change
invokes the supplied `on_size_changed` callback; the root contribution wires
that callback to the existing coalesced
`MarkdownCommentSizeObserver::request_measure` path rather than introducing
another ViewZone height writer. The root entry disposes the diagram owner
before the shared Markdown renderer and size observer whenever the body is
replaced or its ViewZone is removed.

The emitted stylesheet remains at
`viewer/contrib/markdown_comments/browser/markdown_comments.css`. Run the
focused JS suite with:

```sh
moon test internal/viewer/contrib/markdown_comments/browser --target js
```
