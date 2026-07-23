# internal/viewer/contrib/hover

The DOM-free content-hover model, ported from Monaco's
`editor/contrib/hover/browser/` so its state, participants, reconciliation,
timing, and rendering can be tested on JS and native targets.

## Contract

- `HoverAnchor` models range and injected-text foreign-element anchors.
  Foreign anchors carry an explicit editor-scoped participant-owner identity;
  equality/adoption/filter helpers decide whether a visible result survives a
  pointer move without conflating rebuilt participants or separate Viewers.
- `HoverOperation` and `HoverController` are the pure delayed-operation state
  machine. Typed start modes/sources preserve the source branches;
  `HoverRequestStamp` combines stable model identity, internal content
  version, monotonic generation, and caller token. Sync and streamed async
  parts are merged into `HoverView`/`HoverWidgetView`; content invalidation can
  cancel pending work while preserving an already shown view. The browser/root
  host owns clearable timers and executes the requested computations.
- `HoverParticipantHandle` is a value-level adapter with required ordinal and
  synchronous computation plus independently optional anchor suggestion,
  asynchronous computation, and loading-message callbacks.
  `HoverParticipantRegistry` builds participants from
  `HoverParticipantServices`; the process-wide registry currently installs
  marker and language-Markdown participants.
- `ContentHoverComputer` runs those participants. Marker tooltips are
  synchronous; registered language hover providers are asynchronous. The
  caller token/freshness predicate guard both sides of each await, and an
  injected task runner lets the browser merge participant results in completion
  order without a multi-target runtime dependency.
- `render_hover_code_block` preserves hover's synchronous compatibility
  surface while delegating fenced/active-language selection and editor-token
  HTML to `internal/viewer/markdown`'s shared override. This package neither
  imports cmark types nor creates DOM nodes.

## Browser and Viewer ownership

`internal/viewer/contrib/hover/browser` owns everything whose contract carries
DOM or a browser `MouseTarget`: candidate discovery, editor-event reduction,
the `ContentHoverController` implementation, geometry, and the persistent
`ContentHoverWidget`. The feature package has no process-global per-editor
controller map. The root `viewer` package constructs the concrete controller
into its sole per-Viewer contribution registry, recovers it through a private
typed central accessor, routes events/timers/provider work, owns hover
decorations, and mounts/synchronizes the widget. Controller reset and disposal
operate on that stored payload directly. The same controller survives model
removal, replacement, and reattachment while its model-scoped timers, request,
and decoration state reset. The widget exposes a generic `ContentWidgetHandle`
and mounts in the overflowing layer.

Compared with Monaco, there are no resize sashes, hover status bar,
accessibility view, color picker, code-action participant, or context-key/DI
framework. Exact APIs are in `pkg.generated.mbti`; browser-only APIs are in
`browser/pkg.generated.mbti`.

## Boundary

This package is multi-target and imports no Rabbita or browser/view package.
It may depend on base/language/log/syntax, the DOM-free shared Markdown core,
and DOM-free viewer common packages, but never on the root Viewer or shell.

Run the focused suite on both supported targets with:

```sh
moon test internal/viewer/contrib/hover --target js
moon test internal/viewer/contrib/hover --target native
```
