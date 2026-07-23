# Harness

Use the lowest layer that can observe the behavior. Browser tests are for DOM,
pointer, browser-layout, and full-shell behavior—not for state that a MoonBit
test can assert directly.

## Commands

```sh
just check                   # check all targets and source formatting
just test                    # all MoonBit tests
just build                   # check + browser assets + native server
just test-browser            # all Playwright suites
just test-browser-smoke      # reference app and user workflows
just test-browser-component  # direct Viewer component pages
just test-browser-perf       # commit-frame conformance + non-budgeted timing
just dev ROOT=. PORT=5173    # build and run the reference app
```

Playwright defaults to `http://127.0.0.1:5173` and the deterministic
`tests/fixtures/workspace`. Set `READONLY_EDITOR_BASE_URL` to target an already
running server.

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
  perf/        correctness traces plus non-budgeted timing evidence
  moonbit/     js-target scenario packages
  support/     Playwright fixtures, logging, and reporters
```

`scripts/build-web.mbtx` builds the reference app, embed page, and MoonBit
scenario bundles, then assembles owner-adjacent CSS and codicons under
`web/dist`.

The whole-line Markdown proof is the direct public-Viewer component scenario
`tests/browser/moonbit/component/markdown_comments_scenario.mbt`, loaded by
`component.html?markdownComments=1` and asserted by
`tests/browser/component/markdown_comments.spec.js`. It does not route through
the reference shell. The scenario owns its language configuration and models,
then exposes compact evidence for projected source replacement,
tokenized Markdown DOM, built-in Diago SVG layout/overflow, measured/offscreen
ViewZone geometry, native link/selection input, resize/image updates, model
flush/swap, and disposal.

The corresponding real-shell proof is
`tests/browser/smoke/viewer.spec.js`: it opens the fixture through the native
remote protocol and verifies that the workbench-installed MoonBit provider
renders the anchored documentation while the underlying model retains the raw
`///|` and `///` source.

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
  ambient cadence remains diagnostic rather than a budget.
- The MoonBit reporter only emits data; Playwright validates the report and
  owns pass/fail.

## Failure Evidence

`tests/browser/support/test.js` records `runner.log`, console/page/request
failures, traces, and screenshots under `test-results/browser/**`. Component and
perf suites also attach their JSON reports. Set
`READONLY_EDITOR_TEST_VERBOSE=1` or `PW_VERBOSE=1` to mirror logs to the terminal.

Package globals, selectors, and scenario-authoring details live in
`tests/browser/README.md`.
