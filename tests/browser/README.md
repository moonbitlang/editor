# Browser Tests

Playwright coverage for behavior that needs a real browser. The complete
harness split and commands live in `docs/harness.md`; this file contains only
browser-suite authoring contracts.

## Suites

```text
support/    Playwright fixtures, app helpers, logging, reporter
smoke/      user workflows against the workbench or embedded viewer
component/  loaders/assertions for direct MoonBit Viewer pages
perf/       opt-in performance diagnostics and scroll-frame traces
moonbit/    js-target MoonBit scenario packages
```

`just test-browser-smoke` is the routine browser-correctness gate and runs both
the `smoke/` and `component/` directories. `just test-browser-perf` is reserved
for performance investigation and perf-harness changes.

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
  mounts a public Viewer and overlay widget in a same-origin iframe whose
  scroll and viewport deliberately differ from the top window, covering
  public owner-document mounting. Exact overflowing content-widget page
  layout and its 15px/22px boundaries are covered by
  `internal/viewer/browser/view/content_widgets_wbtest.mbt`.
- `component.html?markdownDocument=1` mounts two public Viewers over shared
  services and an ordinary `.mbt.md` model. The suite uses real
  Range-derived `page.mouse` positions over semantic nested fence text; it
  never bypasses presentation routing or caret mapping through a test control.
  `__markdownDocumentControls` performs model replacement through public
  `Viewer::set_model`, releases deterministic async provider gates, mutates
  fixture inputs, and exposes readback. Assertions cover
  original model identity/URI/revision, 1-based provider positions, 0-based
  wire offsets, returned ranges, diagnostic projection, unsafe pointer zones,
  independent Viewer owners, and stale completion rejection across
  pointer/content/theme/model/disposal boundaries.
- `smoke/viewer.spec.js` opens `README.md` and `src/literate.mbt.md` from the
  deterministic workspace fixture through the sidebar and native protocol.
  The host supplies unchanged URI-backed models; the Viewer alone selects
  Markdown, and the `.mbt.md` pointer reaches native `moon ide hover`.
  `smoke/embed.spec.js` proves the same selection through the in-memory
  standalone embed with no workbench, remote protocol, or WebSocket.
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
- Markdown presentation:
  `.moonbit-viewer-markdown-document`,
  `.moonbit-viewer-markdown-document-viewport`,
  `.moonbit-viewer-markdown-document-article`, and
  `.moonbit-viewer-markdown-document-overlays`. Source-bearing semantic rows
  use `[data-markdown-code-line]` under a
  `[data-markdown-code-block][data-markdown-semantic="moonbit-check"]`.
  Diagnostics use `.moonbit-viewer-markdown-diagnostic`; the retained widget
  uses `.moonbit-viewer-markdown-hover-widget` and records accepted original
  model/source/wire/range facts in `data-markdown-hover-*` attributes.
- Definition navigation: a dedicated public-Viewer fixture drives plain clicks,
  Ctrl/Cmd definition links, goto, and Alt+F12 Peek with trusted browser input.
  Its semantic `.mbt.md` cases assert exact projected link spans, ordinary-fence
  exclusion, source-replacement cancellation, same-model reveal, a
  projection-scoped Peek overlay inside a constrained host, nested preview,
  Escape focus restoration, and replacement teardown.
- Product observability: `__readonlyEditorEvent`, `__readonlyEditorModel`,
  `__readonlyEditorDocument`, `__readonlyEditorSource`,
  `__readonlyEditorCopiedText`, and `__readonlyEditorCopiedHtml`.
- Reporter callback: `__readonlyEditorBrowserTestReport`; the Playwright
  reporter stores received payloads in `__readonlyEditorBrowserTestReports`.

MoonBit scenarios are built by `scripts/build-browser-tests.mbtx` into
`web/dist/browser-tests/`. A report has the shape
`{"suite":"viewer_api","status":"passed","failures":[],"metrics":{}}`.
Only the perf build requires the pinned VS Code checkout at
`vscode/src/vs/editor/editor.main.ts`; the routine browser-correctness build
does not build the Monaco oracle.

Markdown diagnostic overlays assert the live resolved class/range/z-index
policy and `showUnused` underline. They intentionally do not claim Code's
`squiggly-inline-unnecessary` opacity or
`squiggly-inline-deprecated` strike-through: those effects mutate source
glyphs and are explicitly deferred for the readonly Markdown projection.

`support/test.js` captures runner logs, console/page/request/HTTP failures,
traces, and failure screenshots. Set `READONLY_EDITOR_TEST_VERBOSE=1` or
`PW_VERBOSE=1` to mirror logs to the terminal.
