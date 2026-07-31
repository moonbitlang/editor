# Peek References UI

Status: proposed
Date: 2026-07-31
Oracle: VS Code gitlink `b18492a288de038fbc7643aae6de8247029d11bd`

## Goal

Add the Monaco-shaped Peek References presentation to the reusable Viewer.
This slice starts with already-computed `Location` values and ends with a
usable, accessible Peek: grouped reference results on the right, a readonly
preview on the left, result navigation, source snippets, match highlights, and
correct model/reference teardown.

This is deliberately a UI slice. It does **not** register or invoke a
`ReferencesProvider`, add Shift+F12 or context-menu commands, parse
`moon ide find-references`, or route the reference wire protocol. The minimal
product entry is a MoonBit-native equivalent of Monaco's
`editor.action.showReferences`:

```mbt nocheck
viewer.show_references(anchor_position, locations)
```

The method consumes locations supplied by the caller and never tries to
discover them. A later feature can call this entry after provider, protocol, or
CodeLens work without changing the Peek UI contract.

## Scope and Mode

### Upstream source

The pinned behavioral source is:

- `vscode/src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:784-859`
  for the precomputed-locations `peekLocations` / `showReferences` entry;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/referencesModel.ts:147-297`
  for grouping, sorting, exact deduplication, nearest selection, and circular
  next/previous navigation;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesController.ts:
  77-304,318-420` for one controller per outer editor, replacement, focus,
  selection, close, and navigation behavior;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesWidget.ts:
  243-608` for the 18-line Peek shell, preview, result pane, title, model
  replacement, and unavailable-preview behavior;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesTree.ts:
  107-223` for file groups, count badges, source snippets, match highlighting,
  keyboard labels, and accessible descriptions;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesWidget.css:
  7-85` for the selected presentation roles and theme tokens.

This is not a full audit of those units.

### Port mode

- The public display entry, visible shell, result hierarchy, labels, focus
  domains, and pointer/keyboard interactions are a **behavior port**.
- Result ordering, nearest-result choice, circular navigation, async
  model-reference replacement, stale-result rejection, and teardown ordering
  are **algorithm-fidelity ports** because their ordering and lifetime are
  observable.
- VS Code service topology, class inheritance, generic Workbench tree/list
  infrastructure, and editor-group behavior are not representation contracts.

### Local boundary

The current implementation already supplies most of the shell and ownership
machinery:

- `internal/viewer/contrib/definition/browser/definition_peek_widget.mbt`
  owns the present header, fixed preview/results split, status surface, and
  flat location rows.
- `viewer/definition_peek_host.mbt` owns the Code ViewZone plus overlay,
  semantic-Markdown overlay mount, nested Viewer, model resolver leases,
  request generations, preview replacement, focus, and disposal.
- `viewer/common/navigation_api` already supplies host-neutral
  `LocationOpenerHandle` and `TextModelResolverHandle` capabilities.
- the root Viewer already supplies ViewZones, overlays, model decorations,
  nested readonly Viewers, and the central contribution lifetime.

The missing UI is the reference-specific result model and accessible grouped
tree. There is no reusable Viewer tree, SplitView, or Sash primitive today.
The planning baseline was a clean `main` checkout with Moon
`0.1.20260730 (7611a39)` and the gitlink recorded above; Gate A must recheck
those facts before implementation.

### Adopted behavior

- one outer-Viewer Peek controller shared by Definition and References;
- a programmatic `Viewer::show_references(Position, Array[Location])` entry;
- an 18-line Peek shell, capped by the live Viewer viewport;
- preview on the left and results on the right;
- deterministic URI/range grouping, sorting, and exact duplicate removal;
- file rows with basename, parent path, and reference-count badge;
- reference rows with source text and exact match highlight, with a
  `filename:line:column` fallback when no model can be resolved;
- nearest initial selection and circular F4 / Shift+F4 navigation;
- lazy file-group snippet resolution and selected-target preview resolution;
- all-reference and selected-reference decorations in the active preview;
- mouse, keyboard, focus, ARIA, stale-result, and disposal behavior described
  below;
- Code ViewZone and semantic-Markdown overlay mounting through the existing
  presentation-specific host paths.

### Out of scope

- `ReferencesProvider`, `ReferenceContext.includeDeclaration`, the language
  registry, native or remote provider adapters, and cancellation of a
  reference query;
- `Go to References`, `Peek References`, `Find References`, Shift+F12,
  context-menu placement, alternative commands, and command argument plumbing;
- VS Code's Workbench References View, Activity Bar container, history,
  refresh, copy, clear, and preferred-location setting;
- Reference CodeLens and Document/Symbol Highlight;
- overview ruler and minimap marks;
- a reusable general-purpose Tree/List framework;
- result filtering, type-ahead search, drag-and-drop, multi-selection, and
  virtualization;
- draggable Sash, vertical resizing, and persisted Peek size/split ratio;
- stable Peek, cross-editor Peek transfer, navigation history, and editor-group
  migration.

## Confirmed Current Gaps

| Area | Current local state | Required by this plan |
| --- | --- | --- |
| Display entry | Definition-only private entry populated by a definition request | Public precomputed-location `show_references` entry; no provider query |
| Ownership | Peek state is embedded in `DefinitionContributionState` | Shared References/locations controller consumed by Definition and References |
| Result model | Flat sorted locations in root state | URI groups, flat reference order, exact deduplication, nearest and circular navigation |
| Result DOM | One `listbox` of filename/position buttons | Feature-local accessible tree with file groups, badges, snippets, and match spans |
| Row source | Only `Location` labels | Lazy same-resource/resolved-model snippets with a location fallback |
| Preview decoration | Selected definition range only | Every reference in the previewed resource plus a distinct selected match |
| Layout | Fixed 72%/28% CSS grid | Retain it for this slice; no new Sash primitive |
| Provider path | `language.ReferencesProvider` exists, but Viewer registration/host adapters do not | Explicitly excluded |

## Locked Decisions

### D1. The input seam is precomputed locations

Add:

```mbt nocheck
pub fn Viewer::show_references(
  self : Viewer,
  anchor : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit
```

The Viewer validates `anchor` against the current model and copies `locations`
before normalization. It displays exactly the supplied location set after
exact URI/range deduplication. It does not add or remove a declaration and does
not infer provider semantics.

The entry is available only on a live, mounted `OuterViewer` with a current Code
or Markdown presentation. A nested preview cannot recursively open Peek.
Calling it again at the exact same model/generation/version/anchor toggles the
current Peek closed. Calling it at another anchor replaces the current session.
An empty array opens the shell's accessible `No references found` state so the
UI contract can represent an already-computed empty result without a separate
message-controller dependency.

### D2. Extract one shared References controller

Monaco uses `ReferencesController` and `ReferenceWidget` for definitions as
well as references. Follow that ownership:

- add a central per-Viewer References contribution;
- move the generic Peek phase, anchor, widget, preview child, resolver lease,
  generations, focus frame, ViewZone/overlay, and teardown order out of
  `DefinitionContributionState`;
- keep provider requests, definition links, definition no-result messages,
  and direct definition opening in the Definition contribution;
- make Definition Peek populate the shared controller with the title
  `Definitions`;
- make `show_references` populate it with the title `References`.

The Definition commands and gestures must retain their current behavior.
Their results pane intentionally adopts the shared grouped/snippet
presentation; do not keep a second flat Peek implementation or duplicate the
root lifecycle.

### D3. Build a feature-local result tree

Implement `ReferenceResultsTree` under the new references contribution browser
package. Do not import `internal/shell/widgets/file_tree`, and do not create a
generic public `Tree<T>` abstraction.

The tree is a closed two-row family:

- file group: basename, parent path, count badge, expanded state;
- reference: source snippet or location fallback, selected state.

For one resource, omit the redundant file row and show its references directly.
For multiple resources, show file rows; expand the initially selected group and
leave other groups collapsed until the user opens them.

Render all current rows into the scroll container. Virtualization is deferred;
the implementation must keep model and DOM ownership separate so a later
virtualized renderer can replace the row materialization without changing the
public Viewer API.

### D4. Keep ordering and identity deterministic

The DOM-free result model:

1. copies caller input;
2. sorts by canonical `Uri::to_string()`, then `Range` start/end;
3. removes exact URI-string plus range duplicates, retaining the first sorted
   occurrence;
4. builds resource groups and one flat reference sequence.

Initial selection follows the pinned `nearestReference` behavior: prefer the
resource with the longest common URI-string prefix to the source resource, then
the smallest `abs(line delta) * 100 + abs(column delta)`, then stable sorted
order. F4 and Shift+F4 cycle through the flat sequence and wrap across resource
boundaries. Selecting a hidden child expands its parent before revealing it.

The canonical URI-string comparison is the local representation decision.
Do not add filesystem case policy or import shell path services into Viewer.

### D5. Derive snippets without exposing string offsets

Use the current `TextModel` for its own resource. Resolve another resource only
through `TextModelResolverHandle`, lazily when its group first needs rows or a
selected reference needs preview.

Represent a row preview as three strings:

```mbt nocheck
struct ReferenceSnippet {
  before : String
  matched : String
  after : String
}
```

Build those parts through `TextModel` range operations, using the upstream
eight-column/word context and trimming leading/trailing row whitespace. Render
the match as its own DOM span. This preserves 1-based UTF-16 `Range` behavior
without slicing a MoonBit string by an unlabelled integer offset. Normalize
embedded line breaks to display whitespace so every result remains one visual
row.

If the model is absent, resolution fails, the returned model URI is wrong, or
the range cannot produce a valid snippet, retain
`basename:line:column`. A failed snippet must not make the reference
unselectable.

### D6. Root owns async resources

The browser widget emits typed callbacks such as select, confirm, open-side,
next, previous, close, and expand-group. It does not resolve models, create a
nested Viewer, or own a `TextModelReference`.

The root References contribution owns:

- one cancellation/generation slot per pending group resolution;
- retained group-preview references until the session closes;
- the selected preview request and installed nested Viewer/reference;
- all preview decorations;
- Code ViewZone/overlay or Markdown overlay;
- scheduled focus/layout work.

Every async completion checks Viewer disposal, source model identity,
attachment generation, content version, session generation, and its own
request identity before mutating DOM. A stale or wrong-URI returned reference
is released exactly once.

Close and replacement atomically detach all owner slots before cancellation or
disposal callbacks. Teardown order is nested Viewer, selected preview
reference, group-preview references, decorations, browser widget/overlay, then
ViewZone or Markdown mount. Reentrant release callbacks must not find a
half-owned session.

### D7. Interaction and accessibility contract

- The shell is `role="dialog"` with the mode-specific label
  `Peek Definition` or `Peek References`.
- The result container is `role="tree"` and exposes an accessible result
  summary.
- File and reference rows are `role="treeitem"` with `aria-level`,
  `aria-posinset`, `aria-setsize`; file rows also expose `aria-expanded`, and
  reference rows expose `aria-selected`.
- Use roving `tabindex`: exactly one visible tree row is the keyboard focus
  target. Selection and keyboard focus move together within the tree.
- Up/Down move through visible rows; Home/End choose the first/last visible
  row; Right expands a file or enters its first child; Left collapses a file or
  returns from a child to its file row.
- Single-clicking a reference selects it and updates the preview. Clicking a
  file toggles it.
- Enter on a reference tree row and double-click confirm it in `Current` mode,
  close Peek, and use the existing opener/current-model path. Ctrl+Enter
  confirms in `Side` mode through `LocationOpenerHandle`.
- Enter inside the nested preview retains its native editor behavior.
- F4 and Shift+F4 select the next/previous reference from either tree or
  preview focus without closing Peek.
- Escape closes and restores outer focus. A focus move made by the user while
  preview resolution is pending wins over automatic focus restoration.

VS Code's Peek-mode Enter can re-anchor and keep the widget open after moving
the outer editor. That requires a host contract for same-Viewer model transfer
which the current opener intentionally does not expose; the close-and-open
behavior above is the selected standalone deviation.

### D8. Reuse the current fixed layout

Keep the existing 18-line height cap, blank Code ViewZone spacer, overlay
alignment, semantic-Markdown overlay, and responsive fixed CSS split. Move
generic Peek/results styles to an owner-adjacent references stylesheet; leave
definition-link and definition-message styles with Definition.

Do not add SplitView, Sash, persisted ratios, drag resizing, or a ViewContainer
as part of this plan.

## Target Ownership

Exact filenames may be adjusted during implementation, but ownership may not:

| Owner | Planned responsibility |
| --- | --- |
| `internal/viewer/contrib/references` | DOM-free result/group/snippet values, normalization, nearest selection, circular navigation, session phase |
| `internal/viewer/contrib/references/browser` | Peek shell, `ReferenceResultsTree`, ARIA/roving-focus behavior, row listeners, browser-only DOM |
| root `viewer` | central References contribution, public `show_references`, presentation mount, resolver and lease lifetime, nested Viewer, decorations, opening |
| `internal/viewer/contrib/definition` | definition request/link state only; no generic Peek resource ownership |
| `internal/viewer/contrib/definition/browser` | definition message shell only after Peek extraction |
| `viewer/common/navigation_api` | existing Current/Side opener and model-reference capabilities; wording generalized from definition-only use |
| `viewer/contrib/references/browser/references.css` | shared Peek and reference-results styling |
| direct Viewer browser scenario | public-API proof without workbench, protocol, or reference provider |

Do not introduce an import from any Viewer package to `internal/shell/**`.
Review every new `moon.pkg` edge against `docs/architecture.md`, and regenerate
every changed `pkg.generated.mbti` only with `moon info`.

## Evidence Map

| Behavior or invariant | Source | MoonBit disposition | Planned evidence |
| --- | --- | --- | --- |
| Precomputed locations can open Peek without a provider | `goToCommands.ts:784-859` | `Viewer::show_references` direct method | mounted Viewer white-box plus direct component scenario |
| One controller owns Definition and References Peek | `referencesController.ts:36-77` and Definition action use of it | central closed References contribution | Definition regression suite plus contribution ownership test |
| Sort, group, exact-dedup, nearest, wrap | `referencesModel.ts:147-297` | DOM-free concrete result model | `references_model_reference_wbtest.mbt` |
| One-resource result omits a redundant group row | `referencesWidget.ts:520-537` | tree receives group children directly | browser-package white-box DOM test |
| File row path/count and reference snippet/highlight | `referencesTree.ts:107-223` | feature-local two-row renderer | browser-package white-box plus Playwright role/text assertions |
| Lazy group resolution and location fallback | `referencesTree.ts:18-49`, `referencesModel.ts:45-145` | root resolver lease plus typed snippet update | stale/failure/wrong-URI mounted tests and component scenario |
| Preview follows selection and highlights references | `referencesWidget.ts:538-608` | nested Viewer plus decoration collections | mounted lifecycle test and visible component assertion |
| F4/Shift+F4, Escape, focus domains | `referencesController.ts:189-235,318-379` | existing shell routing generalized to references | browser widget tests plus real keyboard Playwright test |
| Accessible tree/group/row semantics | `referencesTree.ts:65-105,215-223` | native ARIA tree with roving focus | DOM contract tests and Playwright role assertions |
| Late results cannot commit; references release once | `referencesController.ts:77-187`, `referencesWidget.ts:280-298,482-608` | generation-stamped root ownership | mounted reentrant/stale-resolution tests |
| Fixed split without Sash persistence | `referencesWidget.ts:338-468` | selected reduced layout | browser geometry assertion; Sash marked deferred |
| Workbench view, provider path, CodeLens, highlights absent | separate VS Code workbench/language features | N-A for this UI slice | scope review; no shell/protocol/provider dependency diff |

## Milestones

### 0. Gate A: inventory and representation review

- Re-read the pinned source clusters above and the current Definition Peek
  packages before editing.
- Record the current `vscode` gitlink, Moon toolchain, working-tree status,
  affected `moon.pkg` files, and generated interfaces.
- Confirm the public signature and the new contribution/package dependency
  direction.
- Review D1-D8 against the current source. This is an internal execution gate,
  not a user-approval pause; stop only if the current source makes one of the
  locked decisions impossible without changing scope.

Exit: scope, port mode, package ownership, public API, and evidence denominator
are current and recorded in this plan.

### 1. DOM-free result model and shared-controller extraction

- Add the references core package and focused reference tests for normalization,
  grouping, nearest selection, circular movement, and snippet parts.
- Add the central References contribution entry and move generic Peek state out
  of `DefinitionContributionState`.
- Rewire Peek Definition through the shared controller without changing its
  provider request, direct goto, link gesture, no-result, or opener behavior.
- Preserve same-anchor toggle, nested-Peek suppression, Code/Markdown mounting,
  focus scheduling, preview staging, and child-before-reference teardown.
- Regenerate and review affected interfaces.

Focused gate:

```sh
moon test internal/viewer/contrib/references --target all
moon test viewer --target js
moon check --target all --warn-list +73
moon fmt --check
```

Commit the coherent, green extraction milestone.

### 2. Reference tree and browser shell

- Add the references browser package and move the generic Peek shell out of the
  definition browser package.
- Implement file/reference rows, count badges, one-resource flattening,
  expansion, roving focus, keyboard movement, selection, and typed callbacks.
- Add mode-specific title, loading, empty, unavailable, preview, and dialog
  labels.
- Split the shared Peek CSS into the references stylesheet, keep definition-only
  CSS with Definition, and stage the new asset in `scripts/build-web.mbtx`.
- Add browser-package white-box tests for row shape, ARIA, focus movement,
  callbacks, clamping, rerender, and listener disposal.

Focused gate:

```sh
moon test internal/viewer/contrib/references/browser --target js
moon test internal/viewer/contrib/definition/browser --target js
moon check --target all --warn-list +73
moon fmt --check
```

Commit the coherent, green browser-widget milestone.

### 3. Public display entry, snippets, preview, and opening

- Add and document `Viewer::show_references`.
- Populate the shared controller directly from copied locations; do not touch
  the language registry.
- Resolve group snippets lazily, retain and release their model references, and
  rerender only the affected current group.
- Reuse the selected-preview replacement path and decorate every reference in
  the active resource with a distinct selected match.
- Wire Current and Side confirmation through the existing host-neutral opener
  boundary.
- Add mounted tests for same-resource and cross-resource results, missing
  resolver, wrong URI, failed/late resolution, model/content replacement,
  repeated anchor, reentrant release, focus, and disposal.
- Add a direct public-Viewer browser scenario and Playwright spec for the
  multi-file tree, snippet match, expand/collapse, selection/preview, F4 cycle,
  Enter, Ctrl+Enter, Escape, Definition regression, and Markdown overlay.

Focused browser gate:

```sh
just build-browser-tests
./node_modules/.bin/playwright test tests/browser/component/peek_references.spec.js
```

Commit the coherent, green integrated UI milestone.

### 4. Contracts and final validation

- Update `docs/architecture.md`, `docs/references/monaco.md`,
  `docs/harness.md`, root Viewer and owning package READMEs, and
  `viewer/common/navigation_api/README.mbt.md`.
- Regenerate interfaces with `moon info --target all`; review the public
  `Viewer::show_references` addition and every new internal package surface.
- Confirm no references registry, server/workbench adapter, remote-protocol
  change, command/keybinding, CodeLens, References View, or generic tree
  framework entered the diff.
- Run the repository gates:

```sh
moon info --target all
moon check --target all --warn-list +73
moon fmt --check
just test
just build
just test-browser-smoke
git diff --check
```

- Record focused evidence and any real environment limitation. A repository
  check alone is not parity evidence.
- Compress the landed ownership/behavior/evidence into
  `docs/exec-plans/HISTORY.md` and delete this detailed plan.

Commit the validation/history milestone.

## Test Matrix

### DOM-free cases

- empty, one, duplicate, unsorted, one-resource, and multi-resource inputs;
- same start with different end ranges remains two references;
- URI/range ordering and exact deduplication;
- nearest same-resource result, common-prefix fallback, line/column tie, and
  stable final tie;
- forward/backward navigation within a file and wrapping across files;
- leading/trailing whitespace, empty lines, multi-line ranges, invalid ranges,
  and non-BMP UTF-16 text in snippet parts.

### Browser widget cases

- one resource renders only reference rows;
- multiple resources render file rows, parent paths, count badges, and the
  selected group expanded;
- group click and Left/Right update visible rows and `aria-expanded`;
- Up/Down/Home/End maintain one roving `tabindex`;
- selected reference exposes `aria-selected`, scrolls into view, and updates
  its accessible label;
- snippet match has one exact highlight span; fallback remains selectable;
- Enter, Ctrl+Enter, F4, Shift+F4, and Escape route only from the allowed
  focus domains;
- result replacement and disposal release every installed listener once.

### Root/lifecycle cases

- public call validates the anchor, copies caller input, and never invokes a
  provider;
- same-resource rows and preview need no resolver lease;
- group and selected-preview leases have distinct, exactly-once ownership;
- stale, cancelled, wrong-URI, post-model-swap, and post-dispose results cannot
  update the widget;
- replacement retains the installed preview until a current replacement can
  commit;
- all preview decorations update when selection changes resource;
- same anchor toggles closed; another anchor replaces;
- nested Viewer cannot open another Peek;
- Code ViewZone geometry and Markdown overlay geometry remain bounded;
- Definition Peek remains operational through the shared controller.

## Behavioral Deviations and Deferrals

- The local fixed 72%/28% split and viewport-capped 18-line height remain;
  draggable/persisted SplitView and Sash behavior is
  `DEFERRED (no reusable Viewer primitive and not required by this UI slice)`.
- The feature-local tree renders all visible rows;
  virtualization/filter/type-ahead/DnD are
  `DEFERRED (Workbench list infrastructure is outside the standalone Viewer)`.
- Enter confirms and closes before opening. VS Code Peek mode can move the
  outer editor and re-anchor the still-open widget; this is
  `N-A (the host-neutral opener does not guarantee same-Viewer model transfer)`.
- An empty precomputed input remains visible as `No references found`; Monaco's
  direct `findReferences` controller can show this state, while its
  `showReferences` action path suppresses the empty widget. The local direct
  Viewer entry selects the visible controller-level state so callers do not
  need a second message UI.
- Focus switching uses native focus movement plus the selected keys above;
  VS Code's Ctrl/Cmd+K F2 chord is
  `DEFERRED (the local keybinding registry has no chord primitive)`.
- Stable Peek, cross-editor transfer, editor groups, and history are
  `N-A (host/workbench policy)`.
- References View, CodeLens, Document Highlight, minimap/overview ruler,
  provider/query plumbing, and Go/Peek References commands are
  `N-A (explicitly outside this UI-only plan)`.

## Exit Gate

- [ ] pinned source revision and selected behavior/algorithm clusters reviewed
- [ ] shared-controller and feature-local-tree representation reviewed
- [ ] public `show_references` contract documented and generated
- [ ] Definition Peek has no duplicate generic Peek owner
- [ ] grouping, snippets, preview, navigation, accessibility, and lifecycle
      behaviors have focused evidence
- [ ] every exclusion/deviation remains explicit
- [ ] generated interfaces and dependency edges reviewed
- [ ] required MoonBit, build, and browser gates green
- [ ] completed plan compressed into `HISTORY.md` and removed
