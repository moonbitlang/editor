# internal/viewer/contrib/markdown_comments/browser

JS-only DOM and measurement ownership for rendered whole-line Markdown
comments. `MarkdownCommentDom` creates the stable ViewZone outer/content pair;
the root contribution retains the outer node as its ViewZone DOM and renders
shared Markdown into the inner node.

`observe_size` watches the auto-height inner content and its nearest editor
content viewport. Resize notifications and explicit renderer/image
invalidations are coalesced through the realm-global `base/browser`
animation-frame coordinator. A connected offscreen ViewZone is temporarily
laid out invisibly at viewport width, then every touched inline style and
priority is restored before its integer height is reported. The returned
`MarkdownCommentSizeObserver` exposes `request_measure` and idempotent
`dispose`; zero-size restore notifications cannot create a feedback loop.
Disposal disconnects observation, cancels queued frame work, and makes late
notifications inert. The root contribution remains responsible for generation
and zone-id freshness.

The emitted stylesheet remains at
`viewer/contrib/markdown_comments/browser/markdown_comments.css`. Run the
focused JS suite with:

```sh
moon test internal/viewer/contrib/markdown_comments/browser --target js
```
