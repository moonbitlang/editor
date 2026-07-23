# Browser Tests

Playwright coverage for behavior that needs a real browser. The complete
harness split and commands live in `docs/harness.md`; this file contains only
browser-suite authoring contracts.

## Suites

```text
support/    Playwright fixtures, app helpers, logging, reporter
smoke/      user workflows against the workbench or embedded viewer
component/  loaders/assertions for direct MoonBit Viewer pages
perf/       correctness traces plus structured non-budgeted timing evidence
moonbit/    js-target MoonBit scenario packages
```

- Smoke tests prefer real gestures and visible outcomes. Use helpers from
  `support/app.js`; do not call deterministic state-control globals when a
  user path exists. Workbench files are selected through the sidebar and
  remote protocol—the active document is not URL state.
- Component pages construct the public Viewer directly and report compact JSON
  through `__readonlyEditorBrowserTestReport`. Playwright validates the report,
  browser/page/request errors, and visible state and owns final pass/fail.
- `component.html?browserGeometry=1` is the fixed geometry oracle: it embeds
  tiny self-owned monospace and proportional TTF data URLs, awaits
  `document.fonts.ready`, and runs at deviceScaleFactor 1. Its Playwright suite
  compares public Viewer dimensions/positions with DOM Ranges and rendered
  line/widget boxes within the plan's 1 CSS px tolerance. The same scenario
  also mounts test-only normal and overflowing `ContentWidgets` in a real
  same-origin iframe whose scroll and viewport deliberately differ from the
  top window, covering owner-window width/scroll and exact 15px/22px edges.
- Perf tests may enforce deterministic correctness contracts while attaching
  structured timing evidence. `scroll_frame_parity.spec.js` wraps rAF before
  either implementation loads, preserves raw state/render/mutation records,
  groups callbacks by native timestamp, and correlates real
  `.lines-content` `top`/`left` commits for local Viewer and pinned Monaco.
  The local phases come from the internal Viewer-id seam, not the public API;
  raw duplicates remain in the report and unmatched/coalesced states or
  unmatched commits fail. Fixtures stay below Monaco's big-number translation
  regime, so effective rail positions are `-top`/`-left`.
  Cadence and dropped-frame summaries do not fail on a timing budget unless
  one is explicitly documented.
- Monaco parity normally belongs in ported MoonBit unit/reference tests, not
  browser DOM snapshot comparison. The selected scroll commit-frame contract
  is the narrow exception: it compares one real rail write source-relatively,
  not general DOM structure or pixels.

## Stable selectors and observability

- Shell: `.editor-shell` with `data-status`, `data-theme`, `data-line-count`,
  and `data-source-uri`.
- Tree rows: `.workspace-sidebar [data-workspace-id]` with
  `data-workspace-kind`, `aria-expanded`, and `aria-selected`.
- Viewer: `.monaco-editor.readonly-editor` and `.view-line[data-line]`.
- Product observability: `__readonlyEditorEvent`, `__readonlyEditorModel`,
  `__readonlyEditorDocument`, `__readonlyEditorSource`,
  `__readonlyEditorCopiedText`, and `__readonlyEditorCopiedHtml`.
- Reporter callback: `__readonlyEditorBrowserTestReport`; the Playwright
  reporter stores received payloads in `__readonlyEditorBrowserTestReports`.

MoonBit scenarios are built by `scripts/build-web.mbtx` into
`web/dist/browser-tests/`. A report has the shape
`{"suite":"viewer_api","status":"passed","failures":[],"metrics":{}}`.

`support/test.js` captures runner logs, console/page/request/HTTP failures,
traces, and failure screenshots. Set `READONLY_EDITOR_TEST_VERBOSE=1` or
`PW_VERBOSE=1` to mirror logs to the terminal.
