# internal/shell/workbench

Reference browser composition root: a small `vs/workbench`-like shell around the
reusable `viewer`, file tree, remote transport, and browser-test observability.

## Runtime composition

- `start_app` creates and retains concrete language, marker, feedback,
  quick-diff, and logging backings, derives their narrow handles into an opaque
  `ViewerServices`, installs MoonBit/JSON/JavaScript tokenizers (TypeScript
  reuses JavaScript), remote hover/document-symbol providers, the private
  MoonBit Markdown-comment provider, and agent-feedback persistence; then it
  calls `mount_app`. The MoonBit adapter treats an exact `///|` line as an item
  anchor, omits that anchor from rendered Markdown, and renders only the
  immediately following `///` documentation lines. Undocumented anchors remain
  ordinary source.
- Rabbita owns topbar/sidebar/status/diagnostics/theme state and renders one
  stable, childless `.viewer-host`. After the first paint `Viewer::create`
  mounts the imperative editor into that element.
- `RemoteWorkspaceTreeProvider` maps one-level resolves to protocol requests.
  On connect/reconnect the tree refreshes; a bounded depth-first walk auto-opens
  the first MoonBit file (otherwise the first file).
- `RemoteDocumentProvider` maps read/watch/close to protocol packets. Active URI
  and generation guards discard stale async results. Every snapshot becomes a
  new `TextModel`; reloads save/restore viewer scroll state, while user opens
  reset it.
- The protocol client correlates in-flight requests by ID and resolves all
  pending requests on connection loss. Watch results and diagnostics are push
  paths; diagnostics update the workbench-retained `MarkerService` rather than
  a field recovered from `ViewerServices`.
- Public Viewer lifecycle subscriptions update shell state and drive tree
  `autoReveal`. Build/render/hover telemetry comes from the internal
  Viewer-id-keyed `internal/viewer/browser/testing` registry; diagnostic
  telemetry is reread from the retained marker store. Together they emit the
  structured harness events in `../../../docs/harness.md`.
- Agent-feedback state is enabled per opened resource and persisted in
  `localStorage`; this reference host has no agent execution loop.

The only exported functions are `start_app`, `mount_app`, and the harness-facing
`emit_event`; see `pkg.generated.mbti`.

## Boundary and validation

Composition belongs here. Viewer and file tree do not know about each other or
the transport. As an internal workbench-tier consumer this package may retain
feature implementations and use `internal/viewer/browser/testing`; external
embedders remain restricted to root `viewer`, `viewer/browser`, and
`viewer/common/**`. JavaScript FFI is limited to host capabilities, harness
events, storage, and protocol URL lookup.

Run `moon test internal/shell/workbench --target js`, `just check`, and the
relevant `just test-browser-*` suite.
