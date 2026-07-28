# Harness

Use the lowest layer that can observe the behavior. Browser tests are for DOM,
pointer, browser-layout, and full-shell behavior—not for state that a MoonBit
test can assert directly.

## Commands

```sh
just test                    # MoonBit correctness
just test-browser-smoke      # browser correctness: smoke + component
just test-browser-perf       # opt-in performance diagnostics
```

`just test-browser` is an alias for `just test-browser-smoke`. Routine
development does not run the perf suite; use it when investigating performance
or changing the perf harness and its scroll-frame oracle.

Focused build and development commands are:

```sh
just check                       # check all targets and source formatting
just build                       # check + production assets + native server
just build-moon-web              # production browser assets only
just build-browser-tests         # browser-correctness scenario bundles
just build-browser-perf-tests    # perf scenarios + pinned Monaco oracle
just                             # check, build, and serve with repository defaults
just test-browser-component      # direct Viewer subset of browser correctness
just dev ROOT=. PORT=5173        # build and run the reference app
just list                        # list every available recipe
```

Playwright owns `http://127.0.0.1:5174` by default and uses the deterministic
`tests/fixtures/workspace`. Set `READONLY_EDITOR_BASE_URL` to target an already
running server explicitly; only that opt-in path may reuse an existing server.
The direct Playwright CLI starts the native server without rebuilding assets
and assumes the matching browser-build profile has already run; use the
`just test-browser-*` recipes when bundle freshness matters.

## Test Layers

### MoonBit package tests

Use ordinary tests for DOM-free algorithms and `*_reference_test.mbt` /
`*_reference_wbtest.mbt` for traceable Monaco conformance ports. See
`docs/quality.md` for the reference-test contract.

### Headless Viewer tests

`viewer/test_viewer_wbtest.mbt` constructs a real, unattached `Viewer`, installs
a `TextModel`, and exercises its synchronous model/view-model/cursor/layout
state. No browser `View`, DOM measurement, or animation frame is created.

Useful white-box seams are:

- `with_test_viewer`
- `test_view_model` and `test_cursor`
- `test_window`
- `test_set_soft_wrap_column`
- `test_set_viewport`

Use this layer for positions, selections, wrapping, model/view conversion,
visible windows, scroll/reveal math, decoration inputs, and contribution state.

### Mounted Viewer white-box tests

`with_mounted_test_viewer` is a package-private `_wbtest` fixture, not a public
Viewer or host API. It installs the smallest fake DOM/browser runtime and holds
the animation-frame queue so MoonBit tests can inspect synchronous
model-browser ownership, render/reveal requests, and lifecycle ordering before
a flush consumes them. Use Playwright component tests instead for real DOM
layout, focus, pointer input, and native animation-frame behavior.

### Browser suites

```text
tests/browser/
  smoke/       real workbench/embed workflows and real pointer input
  component/   direct public-Viewer scenarios reported as compact JSON
  perf/        opt-in performance diagnostics and scroll-frame traces
  moonbit/     js-target scenario packages
  support/     Playwright fixtures, logging, and reporters
```

The browser-correctness gate runs both `smoke/` and `component/`. Their
directory names describe how they reach the browser surface, not separate
top-level quality gates.

`scripts/build-web.mbtx` builds only the production reference app and embed page,
then assembles owner-adjacent CSS and codicons under `web/dist`.
`scripts/build-browser-tests.mbtx` has separate `smoke` and `perf` profiles
under `web/dist/browser-tests`. The smoke profile builds the MoonBit scenarios
used by browser correctness without touching the perf bundle or Monaco. The
perf profile builds only its local scenarios plus the pinned Monaco oracle.

The whole-line Markdown proof is the direct public-Viewer component scenario
`tests/browser/moonbit/component/markdown_comments_scenario.mbt`, loaded by
`component.html?markdownComments=1` and asserted by
`tests/browser/component/markdown_comments.spec.js`. It does not route through
the reference shell. The scenario owns its language configuration and models,
then exposes compact evidence for projected source replacement,
tokenized Markdown DOM, CDN-backed Mermaid replacement/theme/freshness,
measured/offscreen ViewZone geometry, native link/selection input,
resize/image updates, model flush/swap, and disposal. Its Diago cells exercise
the public Viewer surface rather than a private controller seam: initial
bounded layout, independent diagrams, all four controls, modifier zoom/pan,
pointer and keyboard resizing, ordinary-wheel handoff, host-width response,
same-key fresh state, retained-node teardown, and editor-scrollbar rail hit
testing. The required suite intercepts the exact pinned Mermaid CDN module with
a self-contained ESM fixture, so CI never depends on public network access; the
explicit live-CDN smoke remains opt-in diagnostic coverage.

The corresponding real-shell proof is
`tests/browser/smoke/viewer.spec.js`: it opens fixtures through the native
remote protocol and verifies that the workbench-installed MoonBit provider
renders every `///|` item separator, including the separators above anchored
documentation and a documented block with no following top-level declaration,
while the underlying model retains the raw `///|` and `///` source.

The folding-versus-own-hidden-source branch stays in the focused mounted
Viewer/ViewZones matrices: it is a source-membership and whitespace-visibility
contract, not a browser-geometry dependency.

## Browser Rules

- Smoke tests use the sidebar and remote protocol when testing the workbench;
  the active file is application state, not a URL query/hash.
- Prefer real gestures and visible outcomes. Use deterministic test globals only
  when no user path exists.
- Use Playwright for caret-API hit testing, measured selection/widget geometry,
  browser event wiring, server/file-watch integration, and screenshots/traces.
- Monaco parity comes from an explicit behavior mapping plus focused
  conformance evidence, not from copying TypeScript representation or relying
  on browser DOM snapshots against Monaco. Source-shaped control flow is
  required only for algorithm-fidelity slices where ordering or arithmetic is
  part of the contract.
- A targeted real-commit comparison may observe the same concrete DOM effect
  in both implementations when that effect is the selected behavior. The
  scroll-frame oracle records accepted state and local render phases, then
  observes `.lines-content` `top`/`left` mutations. It groups callbacks by the
  native rAF timestamp; getter samples alone remain state/cadence evidence, and
  ambient cadence remains diagnostic rather than a budget. This oracle belongs
  to the opt-in perf workflow, not the routine correctness gate.
- The MoonBit reporter only emits data; Playwright validates the report and
  owns pass/fail.

## Failure Evidence

`tests/browser/support/test.js` records `runner.log`, console/page/request
failures, traces, and screenshots under `test-results/browser/**`. Component and
perf suites also attach their JSON reports. Set
`READONLY_EDITOR_TEST_VERBOSE=1` or `PW_VERBOSE=1` to mirror logs to the terminal.

Package globals, selectors, and scenario-authoring details live in
`tests/browser/README.md`.
