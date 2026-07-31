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
just build                       # production assets + native server
just dist-front-end              # production browser assets only
just build-browser-tests         # browser-correctness scenario bundles
just build-browser-perf-tests    # perf scenarios + pinned Monaco oracle
just                             # build and serve with repository defaults
just test-browser-component      # direct Viewer subset of browser correctness
just ROOT=. PORT=5173 dev        # build, serve, and print Local/Network URLs
just HOST=127.0.0.1 dev          # explicitly restrict access to loopback
just ROOT=~/git/other-repo dev   # browse another MoonBit repo with this viewer
just list                        # list every available recipe
```

Playwright owns `http://127.0.0.1:5174` by default and uses the deterministic
`tests/fixtures/workspace`. Set `READONLY_EDITOR_BASE_URL` to target an already
running server explicitly; only that opt-in path may reuse an existing server.
The direct Playwright CLI starts the native server without rebuilding assets
and assumes the matching browser-build profile has already run; use the
`just test-browser-*` recipes when bundle freshness matters.

`just dev` defaults to `HOST=0.0.0.0`: it binds every IPv4 interface and prints
reachable Local and detected Network URLs. Set `HOST=127.0.0.1` (before the
recipe name: `just HOST=127.0.0.1 dev`) to restrict the listener and startup
output to the Local URL. `ROOT` may point at any other MoonBit repository to
browse it readonly with hover and diagnostics from that root. The reusable server API, direct
CLI, and lower-level `just serve` recipe remain loopback-only by default.

**Warning:** the reference server has no authentication and exposes workspace
source files. The default `just dev` launcher is intended only for trusted LANs.

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

`viewer/references_peek_wbtest.mbt` uses this layer for the public
`show_references` guards, copied input, lazy per-group and selected-preview
resolver slots, exact lease counts, stale/wrong-URI rejection, Definition-intent
cancellation, reentrant teardown, and mode-neutral opening.
`viewer/definition_navigation_wbtest.mbt` retains the corresponding
Definition-provider and shared-Peek regression matrix.

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
top-level quality gates. GitHub Actions retries a failed browser test once in
a fresh Playwright worker because the hosted macOS runner can transiently stall
native input, layout, or fixture-watch delivery. Local runs do not retry, and
the failed CI attempt retains its trace; a deterministic regression therefore
fails both attempts and still fails the gate.

Compilation is `moon build`'s job: every js entry point declares
`supported_targets = "js"`, so one workspace build emits all of them. The
scripts only assemble those artifacts. `scripts/build-web.mbtx` stages the
production reference app and embed page, then owner-adjacent CSS and codicons,
under `web/dist`. `scripts/build-browser-tests.mbtx` has separate `smoke` and
`perf` profiles under `web/dist/browser-tests`. The smoke profile stages the
MoonBit scenarios used by browser correctness without touching the perf bundle
or Monaco. The perf profile stages only its local scenarios plus the pinned
Monaco oracle, which it builds with esbuild from the VS Code submodule. Before
staging, the browser-test assembler requires every selected bundle and source
map to exist in exactly one of the module-qualified or unqualified layouts; it
rejects ambiguous layouts rather than risking a stale artifact from a different
`moon.work` context.

The whole-line Markdown proof is the direct public-Viewer component scenario
`tests/browser/moonbit/component/markdown_comments_scenario.mbt`, loaded by
`component.html?markdownComments=1` and asserted by
`tests/browser/component/markdown_comments.spec.js`. It does not route through
the reference shell. The scenario owns its language configuration and models,
then exposes compact evidence for projected source replacement,
tokenized Markdown DOM, per-block exact-source switching and state retention,
CDN-backed Mermaid replacement/theme/freshness,
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
documentation, while the underlying model retains the raw `///|` and `///`
source.

The readonly Markdown document proof is the direct public-Viewer component
scenario
`tests/browser/moonbit/component/markdown_document_scenario.mbt`, loaded by
`component.html?markdownDocument=1` and asserted by
`tests/browser/component/markdown_document.spec.js`. It proves the closed
Code/Markdown root selection without a shell branch, retained same-parse
semantic rows for compiler-recognized `mbt check` fences, the exact-source
`///|` row's horizontal-divider presentation, shared interactive D2 and Mermaid
viewports with visible controls, zoom, drag-to-pan, and clean replacement
teardown, and a real caret
pointer translated back to the original model identity, URI, revision,
1-based provider position, and 0-based wire offset. The suite merges language
and marker hover rows, projects resolved diagnostic class/range/z-index and
the `showUnused` underline, rejects prose, ordinary fences, synthetic padding,
and trailing row space, and exercises two-Viewer isolation. Pending results
are rejected across pointer exit, content and theme reprojection, same-URI
model replacement, and disposal. `squiggly-inline-unnecessary` opacity and
`squiggly-inline-deprecated` strike-through remain an explicit deferral because
they require source-glyph mutation; this suite does not claim those Code-only
effects.

The Markdown section-folding proof is the direct public-Viewer component
scenario `tests/browser/moonbit/component/markdown_folding_scenario.mbt`,
loaded by `component.html?markdownFolding=1` and asserted by
`tests/browser/component/markdown_folding.spec.js`. It proves the seeded
auto-fold policy, real toggle clicks with accessible state, semantic hover in a
sibling section while another is collapsed, hover inside a just-revealed fence
with the projection generation unchanged, and both pending-hover interleavings
of the fold ordering rule (programmatic collapse and agent-style
`replace_source`), plus reconciliation in both directions and disposal. The
synchronous fold state machine itself is pinned one layer down by
`viewer/markdown_folding_wbtest.mbt`.

The definition and HTML-context-menu proof is the direct public-Viewer scenario
`tests/browser/moonbit/definition/definition_scenario.mbt`, loaded by
`definition.html` and asserted by
`tests/browser/component/definition_navigation.spec.js`. Real right-click and
keyboard gestures cover selection-preserving Code anchoring, the shared
semantic Markdown command path, native fallback on ordinary Markdown and the
Code scrollbar, live definition actions, ARIA and 24px-row styling,
hide-before-run/focus restoration, top-level keyboard navigation, and
bottom-right viewport fitting. Command grouping/preconditions and lifecycle
stay in Viewer white-box tests; pure placement boundaries stay in the
context-menu browser package. The same fixture also keeps one browser
regression proving Definition uses the shared mode-labelled Peek dialog and
reference tree.

The precomputed References Peek proof is the direct public-Viewer scenario
`tests/browser/moonbit/peek_references/peek_references_scenario.mbt`, staged as
`/browser-tests/peek_references.html` and asserted by
`tests/browser/component/peek_references.spec.js`. It calls only the public
`Viewer::show_references` entry and supplies its own caller-owned Code,
Markdown, and resolved target models plus opener/resolver handles. Real browser
assertions cover the ARIA group/reference tree, lazy snippets and lease reuse,
all-reference plus selected preview decorations, F4 focus preservation,
Current/Side opening, exact-anchor toggle/replacement, accessible empty state,
bounded Markdown overlay, and Definition's shared-shell regression.

Use the routine component gate for this fixture:

```sh
just test-browser-component
```

After `just build` and `just build-browser-tests`, its focused Playwright
diagnostic is:

```sh
./node_modules/.bin/playwright test tests/browser/component/peek_references.spec.js
```

The shell-independent selection and native integration layer uses
`tests/fixtures/workspace/README.md` and
`tests/fixtures/workspace/src/literate.mbt.md` from
`tests/browser/smoke/viewer.spec.js`. The workbench supplies ordinary
URI-backed models through the remote protocol; the Viewer selects the
presentation, and a real pointer in the `.mbt.md` semantic fence reaches the
native `moon ide hover` adapter with the original source range. The embedded
smoke in `tests/browser/smoke/embed.spec.js` separately opens an in-memory
`README.md` through the same public `Viewer::set_model` path, proving that
neither the workbench nor the remote protocol owns selection.

The folding-versus-own-hidden-source branch stays in the focused mounted
Viewer/ViewZones matrices: it is a source-membership and whitespace-visibility
contract, not a browser-geometry dependency.

The API-document presentation branch is covered by that real-shell test: its
documented fixture verifies the first-line collapsed preview, bounded toggle,
mouse expansion, keyboard collapse, accessible state, and ViewZone height
change; undocumented separators remain control-free.

## Browser Rules

- Smoke tests use the sidebar and remote protocol when testing the workbench;
  the active file is application state, not a URL query/hash.
- Prefer real gestures and visible outcomes. Use deterministic test globals only
  when no user path exists.
- Markdown semantic hover tests derive a point from the rendered text range and
  move `page.mouse` there. Test globals may hold an async provider completion
  or expose readback, but must not bypass caret hit testing, coordinate
  conversion, or presentation routing.
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
