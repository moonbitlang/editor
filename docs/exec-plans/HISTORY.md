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

As of 2026-07-21 there are no active checked-in execution plans.

## Completed Work

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
