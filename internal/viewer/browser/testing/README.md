# internal/viewer/browser/testing

This JS-only package is the internal workbench/browser-test bridge for viewer
telemetry and narrowly scoped controls. Entries are keyed by `Viewer::get_id`,
but this package never imports the root `viewer` package: root code registers
callback controls and publishes observations downward, while test-tier callers
subscribe by id.

Unregistering a viewer disposes all of its subscriptions. Registration handles
are idempotent and generation-aware, so an old handle cannot remove a later
registration that reuses the same id. Render observations intentionally omit
diagnostic payloads; hosts that need diagnostics read them from their retained
marker service.

The scroll-frame seam preserves raw duplicate observations in order:
`StateCommitted` after an accepted axis change is visible and before its render
is requested, then `RenderStarted` and `RenderFinished` immediately around
`View::render`. Each record carries Viewer id and both scroll axes. Viewer ids
isolate streams; listener disposal, unregister, and registration replacement
end the old stream. The publisher accepts primitives and checks
`Emitter::has_listeners` before constructing a record, so product execution is
disabled by default. Browser tests add the real DOM commit separately with a
`MutationObserver`; an internal render phase is not itself commit evidence.

## Focused validation

```sh
moon check internal/viewer/browser/testing --target js
moon test internal/viewer/browser/testing --target js -v
```
