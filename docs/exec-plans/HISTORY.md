# Execution Plan History

This is the compressed index of completed execution plans and removed obsolete
plans. The full plan text remains available in Git history:

```sh
git log --all --full-history -- docs/exec-plans/<plan>.md
git show <revision>:docs/exec-plans/<plan>.md
```

Current behavior and ownership live in `docs/architecture.md`, `docs/harness.md`,
`docs/quality.md`, package READMEs, generated interfaces, source, and tests.
Historical plans are evidence of how a change landed, not current contracts.

As of 2026-07-30 there are no active checked-in execution plans.

## Completed Work

### HTML editor context menu behavior port

The browser Viewer now renders a Monaco-shaped HTML editor context menu instead
of relying on the browser-native surface for eligible definition targets. The
port used the pinned `vscode` gitlink at
`b18492a288de038fbc7643aae6de8247029d11bd`: DOM event routing, target and
selection policy, live grouped actions, focus/dismissal, keyboard/submenu
interaction, viewport fitting, and CSS were reviewed in behavior-port mode.
This targets Monaco/VS Code Web, not Electron's optional native desktop menu.

A real `contextmenu` event now travels through the existing mouse factory,
hit-test controller, model-coordinate conversion, and public Viewer event
surface before root policy runs. Code content text and empty-space hits focus
the editor and move one cursor only when outside every current selection.
Exact semantic Markdown rows map the pointer to the original model and share
the same commands. Injected text, widgets, margins, scrollbars, prose, ordinary
fences, padding, stale projections, and empty action sets retain the native
browser menu; an unhandled native-fallback event also retires any stale custom
menu and Markdown definition anchor.

The closed editor registry now stores command titles, keybinding labels,
ordered menu placements, and the `EditorContextPeek` submenu. Preconditions are
resolved at each show, empty groups/submenus disappear, and separators occur
only between nonempty groups. The selected surface contains top-level
`Go to Definition` and `Peek > Peek Definition`, reusing the existing F12 and
Alt+F12 implementations. Shift+F10 and the Context Menu key open the same menu
at the rendered Code cursor or the latest valid semantic Markdown anchor.

One lazy JS-only widget per Viewer owns detached body-level DOM, copied theme
tokens, temporary listeners, focus return, submenu timers, geometry, and
idempotent disposal. Its 24px rows, menu/menuitem roles, submenu ARIA state,
83ms fade, shadow, corners, and keybinding layout follow the selected upstream
HTML surface. Up/Down/Home/End/PageUp/PageDown, Enter/Space, Right/Left,
250/750ms submenu hover, Escape, Tab, outside primary input, focus/window blur,
model/content changes, scroll, replacement, and action-hide-before-run are
covered. Root and submenu overlays prefer right/down placement and flip/clamp
inside the visual viewport.

Intentional exclusions are Electron/native integration, clipboard/edit/
refactor/source/history and extension-contributed actions, scrollbar commands,
touch long press, settings, icons/mnemonics/check states, visible disabled
rows, deeper flyouts, and a public menu API. Independent Viewers each own their
menu rather than sharing VS Code's process-global `IContextMenuService`.

Focused evidence passed 2 geometry tests, all 14 editor-registry tests, and all
9 definition/context-menu Chromium scenarios. Final validation passed 1,669 JS
and 1,104 native MoonBit tests (wasm and wasm-gc have no test entries) and 113
of 114 browser scenarios, with the existing opt-in live-CDN Mermaid diagnostic
skipped. `moon info --target all`, `moon fmt --check`, `just check`,
`just test`, `just build`, `just test-browser-smoke`, JavaScript syntax checks,
and diff checks passed. Existing inexhaustive-test-guard and fixture-package
warnings remain unchanged. Milestones were `f3c9876` (plan), `6e6bc15`
(hit-tested event path), `af66c25` (implementation), and `72cfc4e`
(validation record).

Former artifact: `html-context-menu-behavior-port.md`.

### Definition navigation parity remediation

Definition navigation now uses the `vscode` gitlink at
`b18492a288de038fbc7643aae6de8247029d11bd` as its pinned behavioral oracle.
Provider/result dispatch and user-visible feedback were reviewed as a behavior
port; modifier gestures, request generations, Peek replacement, and teardown
ordering received algorithm-fidelity review. This was not a full source-unit
port of VS Code's editor services.

Language-provider snapshots now follow the represented Monaco selector
priority: exact language, scheme, and supported pattern matches score above
wildcards, selector arrays take their best score, and newer registrations win
ties. Definition requests create one wait-all task per matching live provider
and concatenate successful results in that stable snapshot order, independently
of completion order. The common package keeps a sequential default task runner
for target portability, while the browser Viewer injects a concurrent JS
runner; cancellation, disposed registrations, and individual provider failures
cannot strand the aggregate request. Hover and document-symbol consumers share
the same ordered snapshots, and the public optional `run_tasks` hook records the
scheduling boundary without exposing browser policy to the registry.

F12 and definition-link execution now share one resolved-result dispatcher.
They run a fresh action request, open one definition directly, put multiple
definitions into Peek when that host is mounted, and retain provider-first
direct opening as the deterministic headless fallback. Ordinary F12 reports an
empty result; modifier hover stays silent. Link preview is cached by
model/version/word, while execution is line-scoped and independent of preview
completion. Trigger-key identity and edge, mouse detail, scroll, blur, drag
selection, unrelated modifier chords, model/content changes, Markdown source
anchors, and post-execution cleanup are all explicit gesture-state boundaries.

Peek now captures its source model, version, projection generation, position,
and focus state. An exact repeated anchor toggles it closed; an already-resolved
multi-result action populates it without querying providers again. Display
locations sort by URI and range, the nearest source location is selected for
the preview, and zero results close the loading shell. Replacement is staged so
the installed child and model reference remain usable until the current
replacement can commit. Focus is sampled at commit time, Code focus waits for
the ViewZone to become visible, Enter is scoped to the active Peek, and confirm
tasks carry an opener generation so stale work cannot overwrite newer
navigation intent.

Preview replacement and session close now atomically detach every request,
child Viewer, model reference, widget, and zone from the owning state before
invoking synchronous cancellation or disposal callbacks. Child-before-
reference-before-shell teardown is therefore safe even when those callbacks
close Peek or start a new one reentrantly. The outer workbench Viewer likewise
enters a `Closing` phase and releases its definition leases before the preview
cache retires remaining entries. Late opener feedback is rejected after a new
navigation, cursor move, or plain Markdown click.

The browser scenario builder now writes only to `_build/browser-tests`, removes
the exact stale candidate bundle before compiling, and accepts both plain and
module-qualified Moon build paths. The component fixture covers direct,
multiple-result, F4, link, empty-result, and Markdown navigation behavior.

Intentional exclusions remain explicit. `LocationLink` origin and target
selection ranges, source-preview hover content, multiple-definition hover
counts, configurable `multiCursorModifier`, middle/side/open-to-side gestures,
`definitionLinkOpensInPeek`, alternative commands, history, stable Peek,
groups/tree/sash/cross-editor behavior, and the 350 ms symbol highlight are
deferred or N-A for this readonly Viewer. The local selector pattern contract
supports exact paths and one `*`, not Monaco's full `**`, `?`, brace, range, or
relative-base glob syntax. Same-resource direct navigation still centers an
off-screen target instead of using upstream `NearTopIfOutsideViewport`; exact
anchor equality replaces upstream range containment for Peek toggle; an
unavailable preview uses the shell instead of a fallback text model; and the
upstream word-specific no-result text, reference ARIA announcement, 250 ms
progress indication, and internal scheme filtering are absent or N-A.

Final validation passed 1,663 JS and 1,104 native MoonBit tests (the wasm and
wasm-gc targets currently have no test entry), all 6 focused definition
component cases, and 110 of 111 full browser-smoke cases with the existing
opt-in live-network Mermaid case skipped. The focused definition suites passed
18 Viewer cases, 29 common-language cases, and 17 language-registry cases.
`moon info --target all`, `moon fmt --check`, `just check`, `just test`,
`just build`, `just test-browser-smoke`, and `git diff --check` passed. The
remaining warning output is the repository's pre-existing inexhaustive-test-
guard set.

Former artifact: `definition-navigation-parity-remediation.md`.

### Readonly Markdown document presentation

The public Viewer now owns a closed `Code`/`Markdown` presentation family.
An exact lowercase URI-path `.md` suffix, including `.mbt.md`, or the exact
`markdown` language id selects a retained readonly Markdown root; every other
model keeps the Code presentation. Both variants retain the caller's original
`TextModel`, URI, revision, and `ViewModel` as source truth. Workbench and
embedded hosts still pass ordinary models through `Viewer::set_model`; they do
not parse Markdown, select a presentation, or depend on the document-view
implementation.

One safe cmark parse now produces both installed HTML and a source projection.
Compiler-compatible `.mbt.md` fences whose first two nonempty ASCII-space
tokens are exact lowercase `mbt check` or `moonbit check` retain tokenized,
source-bearing DOM rows and UTF-16 boundary maps; ordinary fences, prose,
synthetic indentation, and mismatched projections fail closed. A
presentation-local bridge converts a real DOM caret back to the original
one-based model position and zero-based wire offset, runs the existing hover
computer against that model, merges language and marker rows, and projects
live resolved marker ranges/classes/z-index into semantic rows. Request,
model/content, URI/revision, attach, projection, block, offset, and
cancellation stamps reject every reviewed stale completion before an async DOM
commit.

The remote boundary was tightened at the same time: hover and diagnostics now
require exact current model identity, versions, URI, revision, normalized
text, and disk snapshot. Native hover uses ordinary `moon ide hover` across
coherent pre/post disk guards, while `MoonCheckDiagnostics` records producing
state, reruns dirty single-flight work, and replays or clears only compatible
sets. Markdown detach retires the bridge and renderer while their root remains
mounted, removes the inert root, and then releases listeners, the attached-view
handle, and the `ViewModel`. Code-only contributions remain dormant on the
Markdown variant, and two Viewers over one model keep independent
presentation/request lifetimes.

Gate A pinned the `vscode` gitlink at
`b18492a288de038fbc7643aae6de8247029d11bd`. Selection, ownership, shell
independence, and user-visible behavior used a behavior port; coordinate,
projection, freshness, and lifetime state machines used
algorithm-fidelity review. No notebook, editing surface, virtual fenced model,
shell Markdown adapter, definition/reference bridge, or quick-diff gutter was
introduced. Incremental DOM patching, persistent synchronized LSP transport,
and prose editing remain deferred. Monaco's
`squiggly-inline-unnecessary` source-glyph opacity and
`squiggly-inline-deprecated` source-glyph strike-through also remain explicit
deferrals; Markdown reuses the resolved severity squiggle and `showUnused`
underline without faking text-mutating effects.

Consumer evidence opens real `README.md` and `src/literate.mbt.md` fixtures
through the sidebar/native protocol and obtains
`fn literate_answer() -> Int` at original range `4:4-4:19` from one
Range-derived pointer entry. A separate in-memory `memory://` README proves the
same public Viewer selection without workbench, remote protocol, or WebSocket.
The final browser gate also made the existing async model-ownership scenario
wait for painted `set_value` content before pointer input; this is a harness
ordering repair, not a product behavior change.

Final validation passed 1,600 JS and 1,081 native MoonBit tests (the wasm and
wasm-gc targets currently have no test entry), all 26 smoke tests, and 76 of 77
component browser tests with the existing opt-in live-network Mermaid case
skipped. The native Markdown hover passed three consecutive focused runs, and
the repaired async ownership scenario passed ten consecutive focused runs.
`moon info --target all`, `just check`, `just test`, `just build`,
`just test-browser-smoke`, and `git diff --check` passed. Every generated
interface and changed `moon.pkg` edge was reviewed; the public Viewer interface
remained byte-identical at SHA-256
`0b1ef32ddc28847e96dc826455ac7bb7f26b22942279d6e616e3fa4f1cea7595`.

Former artifact: `readonly-markdown-document-presentation.md`.

### Markdown-comment Diago viewport controls

Successful direct Diago SVGs inside whole-line Markdown comments now mount as
independent bounded viewports with pan mode, zoom out, zoom in, true Fit, and a
pointer/keyboard resize handle. Ordinary wheel input reaches the editor;
Alt-wheel and Ctrl-pinch zoom the diagram, Alt or toggled primary drag pans,
and the fixed first-version geometry preserves Diago's aspect ratio, defers
zero-size initialization, uses a 100px resize floor, and preserves the visible
origin across host-width changes. Hover and agent-feedback diagrams remain
native inner scrollers, failed fences and other Markdown nodes are untouched,
and replacing a rendered body intentionally starts with fresh viewport state.

Gate A froze the `vscode` gitlink
`b18492a288de038fbc7643aae6de8247029d11bd`. DOM, accessibility, event
ownership, and disposal used a behavior port; pan/zoom/fit/resize and
host-resize geometry used an algorithm-fidelity port; configuration and
cross-render state received behavior accounting only. The reviewed product
deviations keep Diago's SVG sizing metadata, expose true Fit with 16px padding
instead of preview Reset Zoom, add no settings or global manager, and perform
stronger zero-geometry and cleanup handling.

Milestone 1 evidence is the focused JS reference suite for direct-target
selection, DOM/ARIA structure, positive and deferred geometry, fit and zoom
boundaries, pan and resize branches, responsive arithmetic, independent
diagrams, cursor ownership, and idempotent cleanup. Milestone 2 stores the
opaque viewport group beside each rendered Markdown lifetime, disposes it
before renderer replacement and zone removal, dynamically bypasses the generic
diagram wheel listener through an event-time marker, and routes every inline
height change through the existing coalesced size observer and
generation-checked ViewZone writer. The emitted CSS and existing codicon font
own the viewport presentation without a new public Viewer option or package
edge. Real-browser geometry keeps the focus border out of the border-box height
and reserves the editor's 20px overlay-scrollbar/layout strip while preserving
the Markdown surface's 12px inner trailing gap.

Milestone 3 evidence extends the direct public-Viewer component scenario over
initial and offscreen layout, two independent diagrams, four controls,
modifier input, pointer/keyboard resize relayout, ordinary-wheel editor
scrolling, host resize, same-key replacement, model swap, double disposal, and
hidden/visible scrollbar-rail hit testing while retaining the existing
Markdown image, link, selection, folding, source-truth, and ViewZone cells.

Final validation passed the focused shared-Markdown, diagram-controller, and
Viewer JS suites at 6, 18, and 241 tests; all 1,555 JS and 1,053 native
MoonBit tests; the 8-test focused Markdown-comments Playwright spec; and all
100 browser tests. `moon info --target all`, `moon fmt`,
`just build-browser-tests`, `just check`, `just test`, `just build`,
`just test-browser`, and `git diff --check` also passed. The generated
interface changed only for the opaque viewport handle, constructor, and
`dispose`; no `moon.pkg` edge changed.

Former artifact: `markdown-comment-diagram-viewport-port.md`.

### Markdown-comment Mermaid CDN rendering

Whole-line Markdown comments now opt exact lowercase `mermaid` fences into the
browser Markdown lifetime while preserving their safely escaped, editor-
tokenized source as the pending/error fallback. The JS FFI lazily imports
Mermaid 11.16.0 from the fixed jsDelivr ESM URL, calls the official asynchronous
`render(id, source)` API, commits only a successful returned SVG, and then
invokes `bindFunctions` on the retained wrapper. No npm dependency, Mermaid
bundle/chunk, production loader override, public CDN option, or MoonBit Mermaid
renderer was added; Diago, hover, and agent-feedback behavior is unchanged.

The internal browser Markdown contract gained `MermaidTheme::{Light, Dark}`, an
optional render setting, and in-place theme rerendering. One realm-wide module
promise retries after load failure, while a shared queue serializes
`initialize + render` with `startOnLoad=false`, `securityLevel=strict`,
suppressed error rendering, and protected theme configuration. Random
realm-nonce ids plus a counter avoid host and Mermaid temporary-element
collisions. Per-diagram epochs, active lifetime checks, target ownership, and
DOM containment prevent late content, model, theme, target-reuse, and disposal
promises from committing. Failed theme redraws retain the last successful SVG.

Viewer `light` maps to Mermaid `default`; every other Viewer theme maps to
`dark`. Accepted SVGs use the existing renderer size callback, observer,
generation check, and sole ViewZone height writer. Host documentation records
the pinned CDN and relative-chunk CSP requirement, inline SVG styling
requirement, lack of dynamic-import SRI, and visible offline/blocked fallback.

Final validation passed 12 browser-Markdown JS tests, the 243-test mounted
Viewer suite, 1,549 JS tests, 1,053 native tests, all 12 default Mermaid
component scenarios, and the full Playwright result of 104 passed with the
opt-in live-CDN diagnostic skipped. The separately enabled real jsDelivr smoke
also passed. `moon info --target all`, `moon fmt`, `just check`, `just test`,
`just build`, `just test-browser`, and `git diff --check` passed. Production
artifacts retain only the fixed remote import, package/lockfiles and the public
Viewer interface are unchanged, and only the internal browser Markdown
interface changed.

Former artifact: `markdown-comment-mermaid-cdn-rendering.md`.

### Diago Markdown code-block rendering

The shared multi-target Markdown boundary now recognizes only the exact
lowercase `diago` fenced-info id and synchronously compiles it through
`Milky2018/diago@0.3.0` with explicit SVG output before any caller code-block
override. Successful output is wrapped in
`.moonbit-viewer-markdown-diagram`; every Diago error rejoins the existing
tokenized or cmark code fallback. Unlabelled, indented, differently cased,
unknown, `uml`, and `plantuml` blocks remain ordinary code, and
`has_code_block` remains true on success and failure.

Hover constrains diagrams through its existing outer scroller. Agent feedback
and whole-line Markdown comments additionally cap diagram wrappers at
`min(50vh, 480px)` while retaining the SVG's intrinsic aspect ratio; the shared
browser Markdown lifetime keeps native wheel scrolling inside a diagram until
the current delta reaches its boundary, then hands the event back to the owning
surface. The direct public-Viewer component scenario proves inline SVG, width
and overflow, positive geometry, measured ViewZone height,
source-hidden/model-source truth, flush and swap behavior, input, and disposal.
No renderer registry, public option or API, asynchronous placeholder, worker,
SVG security policy, or UML adapter was added.

The selected direct synchronous root facade increased the unminified editor
bundle from 5,030,179 to 22,704,766 bytes and its gzip size from 552,524 to
3,316,248 bytes. Inspection found the expected Diago parser, layout, SVG, and
font payload rather than a duplicate import or build failure; lazy loading and
bundle splitting remain outside this completed scope.

Final validation passed 11 shared Markdown tests on JS and native, 6 browser
Markdown JS tests, 1,537 JS tests, 1,052 native tests, all 64 component browser
tests, all 96 Playwright tests, `moon info --target all`, `just check`,
`just test`, `just build`, `just test-browser`, and `git diff --check`. The
generated Markdown interface had no public change.

Former artifact: `markdown-diagram-code-block-rendering.md`.

### Whole-line Markdown comment rendering

Mounted Viewers now resolve normalized whole-line comment blocks from the first
matching language provider or the language comment configuration, remove only
those source lines from the view projection, and retain one safe rendered
Markdown ViewZone per stable half-open range. Model text, coordinates, tokens,
selection, and code-copy behavior remain source truth; headless Viewers and
whole-model comment coverage keep the source visible.

The prerequisite slices landed as independent milestones: normalized line and
block comment configuration plus provider/detector APIs; changed-only public
hidden-area notification after projection/layout stabilization; one shared safe
cmark/browser renderer used by hover, agent feedback, and Markdown comments;
generic native DOM copy/key ownership; and source-excluding ViewZone visibility
so a replacement ignores its own hidden source but still obeys folding.

The root contribution owns generation-checked provider/reconciliation work,
one hidden source, model/content subscriptions, retained zone ids and DOM
targets, and detach-before-View-disposal cleanup. Its JS-only DOM child owns a
coalesced size observer. The reviewed implementation refined the plan's plain
`Disposable` sketch into an opaque `MarkdownCommentSizeObserver` with explicit
`request_measure` plus idempotent `dispose`, allowing renderer/image changes
and connected offscreen zones to measure at the editor viewport width before
first reveal while restoring every temporary inline style and avoiding
ResizeObserver feedback loops. Fenced code uses the shared editor-token
renderer and existing `mtk*` classes.

The selected behavior ports covered language configuration, hidden-area event
delivery, safe Markdown lifetime/input behavior, and native DOM ownership;
algorithm-fidelity review covered hidden-event ordering, normalized block
reconciliation, and measured-height relayout. Product-specific Markdown
replacement remained behavior-first. The pinned source oracle was the `vscode`
gitlink `b18492a288de038fbc7643aae6de8247029d11bd`.

Final validation passed 1,526 JS tests, 1,047 native tests, the 237-test root
Viewer suite, the JS/native detector and shared-renderer suites, the four-case
DOM observer suite, all five direct public-Viewer Markdown browser cells, and
all 94 Playwright tests. `moon info --target all`, `just check`, `just test`,
`just build`, and `git diff --check` also passed with generated interfaces and
package edges reviewed. The existing all-lines-visible fallback and
`aria-hidden=true` ViewZone accessibility behavior remain explicit product
deferrals.

Former artifact: `whole-line-markdown-comment-rendering.md`.

### Reference shell, remote protocol, and embedding

The browser shell moved to MoonBit/Rabbita, the native host serves the app and
semantic remote protocol, the explorer became a provider-backed optional
widget, and the embedded example proves the viewer can run without the shell.

Former artifacts: `browser-remote-renderer.md`, `rabbita-browser-backend.md`,
`native-hosted-readonly-editor.md`, `remove-local-dom-package.md`,
`pluggable-viewer-and-file-tree.md`.

### Viewer model, provider, and public naming foundations

The reusable boundary converged on `TextModel`, semantic language providers,
host-owned composition, compile-time tokenization registration, and the
`viewer/*` namespace. Several of these files retained stale proposed/no-status
headers after the implementation landed; source and current contracts confirm
the completed outcome.

Former artifacts: `viewer-input-providers-and-virtualization.md`,
`lexmatch-tokenization-registry.md`, `monaco-model-viewer-api.md`,
`viewer-languages-api.md`, `vscode-shaped-editor-feature-services.md`,
`viewer-package-namespace-rename.md`.

### Rendering and package architecture foundations

The renderer moved to a MoonBit-owned imperative view, source-shaped render-line
IR, Monaco-role package tiers, concrete view-part ownership, and the enforced
common/browser/contribution directory split.

Former artifacts: `monaco-ir-and-imperative-view.md`,
`monaco-render-line-ir-layer.md`, `monaco-role-aligned-viewer-architecture.md`,
`monaco-renderer-model-structure.md`,
`monaco-view-part-ownership-architecture.md`,
`viewer-browser-package-decomposition.md`, `viewer-directory-mirror.md`.

### Harness and reference-test structure

Browser suites were split by purpose, a real headless Viewer harness was added,
and the selected readonly Monaco reference suites were ported or explicitly
bounded.

Former artifacts: `browser-test-harness-split.md`,
`headless-viewer-test-harness.md`, `monaco-test-conformance-port.md`.

### DOM and hover foundations

The browser DOM became Monaco-shaped, the content-hover subtree and sizing
lifecycle were implemented, and scrollbar behavior received focused
conformance coverage.

Former artifacts: `monaco-shaped-dom-rendering.md`,
`monaco-exact-hover-widget.md`, `monaco-hover-scrollbar-conformance.md`.

### Rendering, selection, decoration, and scrolling parity

The viewer landed selection hit testing, production line-token rendering,
whitespace/control-character options, marker decorations, current-line/cursor
rendering, model decorations, and scroll render/animation behavior.

Former artifacts: `monaco-faithful-selection-hit-testing.md`,
`production-line-tokens-pipeline.md`,
`faithful-view-line-tokens-render-span-removal.md`,
`monaco-render-whitespace-control-options-port.md`,
`monaco-marker-render-port.md`, `monaco-view-cursors-current-line-port.md`,
`monaco-decoration-system-port.md`,
`monaco-scroll-render-and-animation-parity.md`.

### Unified frame scheduling and real scroll commits

Browser animation work now shares one `base/browser` realm coordinator with
strict-next/current-or-next queues, stable priority ordering, cancellation, and
Viewer render priority `100`. Smooth scrolling and touch inertia use the shared
strict-next queue, while animation-driven state can append the coalesced Viewer
render to the same native frame. A disabled Viewer-id trace plus a
native-timestamp classifier and real `.lines-content` mutation observer prove
state/render/commit ordering in vertical, horizontal, diagonal, boundary, and
mid-document wheel/touch cells against pinned Monaco. Lifecycle coverage proves
model replacement, detach, and disposal leave no retired animation, render,
public scroll event, or rail mutation. Native cadence remains diagnostic;
state-to-real-commit lag and structural/public behavior are the gates. The
supported owner is one JavaScript realm; Monaco's per-window mapping and
cross-editor phased rendering remain outside the local contract.

Final validation passed 1,452 JS tests, 1,011 native tests, the 10 scheduler,
220 Viewer, 11 controller, and 4 internal trace focused tests, all 8 browser
performance/conformance tests, all 23 browser smoke tests, all 88 Playwright
tests, generated-interface review, repository checks, and the production build.

Former artifact: `monaco-unified-frame-scheduling-and-commit-parity.md`.

### Public editor and base APIs

The readonly public surface gained Monaco-shaped read, reveal, selection,
set-value/flush, and URI/path behavior with focused tests at the appropriate
layers.

Former artifacts: `monaco-public-read-api-port.md`,
`monaco-reveal-range-api-port.md`, `monaco-set-selection-api-port.md`,
`monaco-uri-system-port.md`, `monaco-set-value-api-port.md`.

### Architecture and deviation closeouts

These reviews removed duplicated helpers and dead surface, reconciled package
and ownership deviations, aligned import rules, and recorded the remaining
intentional readonly-product boundaries.

Former artifacts: `std-dedup-and-divergence-review.md`,
`monaco-port-fidelity-and-deadcode-review.md`,
`monaco-port-fidelity-and-deadcode-review-findings.md`,
`monaco-arch-divergence-closeout.md`, `monaco-port-deviations-closeout.md`,
`viewer-import-rule-monaco-alignment.md`,
`monaco-ownership-divergence-closeout.md`.

### Viewer–Monaco parity remediation program

The coordinated P1 program closed async freshness, cursor/input events, render
invalidation, browser geometry, model/service ownership, ViewZones, normalized
text-buffer behavior, and tokenization lifecycle. Deferred rows remain product
scope decisions, not unfinished execution of these frozen plans.

Former artifacts: `viewer-monaco-parity-remediation.md`,
`viewer-async-model-features-parity.md`,
`viewer-cursor-input-events-parity.md`,
`viewer-render-invalidation-parity.md`, `viewer-browser-geometry-parity.md`,
`viewer-model-lifecycle-ownership-parity.md`, `viewer-view-zones-parity.md`,
`viewer-text-buffer-eol-parity.md`, `viewer-tokenization-parity.md`.

### MoonBit-native representation cleanup

The coordinates converter became a closed concrete enum and the browser `View`
lifecycle moved from awkward trait-object seams to concrete handles, enums, and
responsibility-split lifecycle files.

Former artifacts: `coordinates-converter-concrete-enum-refactor.md`,
`moonbit-idiomatic-view-lifecycle-refactor.md`.

### Browser view package consolidation

The implementation-only browser view packages were consolidated into
`viewer/browser/view` while preserving source-unit files, CSS paths, render
order, and browser behavior. The Gate A ledgers were folded into this record.

Former artifacts: `browser-view-package-consolidation.md`,
`browser-view-package-consolidation-gate-a.md`,
`browser-view-package-consolidation-gate-a-local.md`,
`browser-view-package-consolidation-gate-a-tests.md`,
`browser-view-package-consolidation-gate-a-upstream.md`.

### Editor contribution single ownership

Five contribution instances moved to the one per-Viewer
`EditorContributions.instances` map with two-phase construction and explicit
model/disposal lifetimes. The Gate A ledgers were folded into this record.

Former artifacts: `editor-contribution-single-ownership.md`,
`editor-contribution-single-ownership-gate-a.md`,
`editor-contribution-single-ownership-gate-a-local.md`,
`editor-contribution-single-ownership-gate-a-upstream.md`,
`editor-contribution-single-ownership-gate-a-lifetime.md`.

### Inline-decoration and tokenization package merges

Inline-decoration resolution was folded into `viewer/common/view_model`, and
the model-owned tokenization subtree was folded into
`viewer/common/model`. Generated interfaces, tests, and dependency rules were
validated after both moves.

Former artifacts: `inline-decorations-view-model-package-merge.md`,
`inline-decorations-view-model-package-merge-gate-a.md`,
`inline-decorations-view-model-package-merge-2026-07-14-test-addendum.md`,
`text-model-tokenization-package-merge.md`,
`text-model-tokenization-package-merge-gate-a.md`,
`text-model-tokenization-package-merge-2026-07-14-addendum.md`.

### Public editor API boundary

The root `viewer` facade became opaque and deliberate, shared public values
moved to canonical common/browser owners, concrete services became capability
handles, and test/debug seams moved out of the external API. The Gate A public,
upstream, dependency, and review ledgers were folded into this record.

Former artifacts: `viewer-public-editor-api-boundary.md`,
`viewer-public-editor-api-boundary-gate-a.md`,
`viewer-public-editor-api-boundary-gate-a-public.md`,
`viewer-public-editor-api-boundary-gate-a-upstream.md`,
`viewer-public-editor-api-boundary-gate-a-dependencies.md`.

### Final warning, FFI, dead-surface, and Viewer-state cleanup

Browser FFI was centralized, warning-only/dead production seams were removed,
and the root `Viewer` state was split into lifecycle-domain owners without
changing its public interface or browser behavior.

Former artifacts: `warning-ffi-dead-surface-cleanup-2026-07-15-addendum.md`,
`viewer-lifecycle-domain-aggregates.md`,
`viewer-lifecycle-domain-aggregates-gate-a.md`.

### MoonBit-native API and internal Viewer boundary

The reviewed visibility ledger narrowed 116 public representations and made
five implementation carriers private while preserving ten caller-constructed
contracts and two open provider traits. Mouse-target factories became
package-private local methods on the foreign browser target type, and the
controller's test-only boundary became white-box.

Ninety product constructors plus the internal browser-test context now use
canonical `Type(...)` construction with compatibility entry points declared as
`#alias(new, deprecated)`.
The two prefix-sum implementations use `ArrayView[Int]` primary constructors,
copy their inputs, and retain `new(Array[Int])` compatibility wrappers;
selected private read-only helpers also accept views without broad public
signature churn.

Twelve concrete browser runtime, scrollbar, testing, and contribution packages
moved below `internal/viewer/**`. Root `viewer`, public `viewer/browser`, and
the public common/capability packages remain the supported embedding surface.
All twenty CSS/font assets retained their original paths and hashes. Final
validation passed 1,438 JS tests, 1,011 native tests, all 83 Playwright tests,
the production build, generated-interface review, and the module-internal
package checks.

Former artifacts:
`moonbit-native-api-visibility-and-internal-boundary-refactor.md`,
`moonbit-native-api-visibility-and-internal-boundary-refactor-gate-a.md`.

## Removed Obsolete Incomplete Plans

These plans were not compressed as completed work. Their original scopes no
longer match the current package graph, public boundary, or porting policy. If
the underlying feature is requested again, write a new plan from current source
instead of reviving the old file.

- `document-snapshot-viewer-api.md`: superseded by the model-based viewer API
  and the later public API boundary.
- `monaco-core-viewer-api-and-docs.md`: superseded by the model-based viewer API
  and current package contracts.
- `monaco-hover-logic-chain-port.md`: partially executed; the remaining
  verbosity, glyph-hover, sash, and focus scopes were overtaken by later hover
  ownership and behavior work.
- `monaco-one-to-one-port.md`: broad source-shaped umbrella superseded by the
  behavior-first port playbook and focused remediation plans.
- `monaco-view-part-render-architecture.md`: partially implemented and
  superseded by the landed role-aligned architecture, lifecycle refactor, and
  browser-view consolidation.
- `production-lsp-client.md`: its old renderer/dom/package assumptions are
  obsolete. The current native host uses semantic remote protocol boundaries
  and `moon ide hover`/`moon check`; a general LSP client needs a fresh plan.
