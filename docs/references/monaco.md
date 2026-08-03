# Monaco Reference Map

Monaco/VS Code is the primary reference for this project. Use it for readonly
viewer behavior, API shape, rendering roles, widget behavior, and conformance
tests. Copy roles and observable behavior, not runtime code, services, or
package names.

The VS Code submodule contains Monaco's editor implementation under
`vscode/src/vs/editor`.

Use these as design references only. Do not import from them in product code.
When Monaco and current local docs disagree, treat current local docs as the
product boundary and Monaco as the source to research before changing it.

## Animation-frame scheduling and scroll commits

The unified scheduling behavior was audited against pinned VS Code revision
`b18492a288de038fbc7643aae6de8247029d11bd`:

- `src/vs/base/browser/dom.ts:396-498` defines cancellable current/next queues,
  descending priority, FIFO ties, one native request, same-drain append, and
  re-sorting after callbacks. These map to
  `base/browser/animation_frame.mbt`.
- `src/vs/editor/browser/view.ts:849-930` gives editor rendering priority
  `100`; root mounted rendering uses that priority. Monaco's cross-editor
  prepare/render phase coordinator remains `N-A`: the local selected contract
  is shared scheduling and commit-frame behavior, not a full coordinator port.
- `src/vs/editor/browser/widget/codeEditor/codeEditorWidget.ts:1764-1771`
  passes strict-next scheduling to the ViewModel, while
  `src/vs/base/common/scrollable.ts:246-251,293-383,475-480` owns smooth-loop
  registration, replacement, and disposal.
- `src/vs/base/browser/touch.ts:69-98,143-158,309-374` and
  `src/vs/editor/browser/controller/pointerHandler.ts:110-136` define touch
  sampling, friction, strict-next inertia, sign, and immediate layout change.
  Local zero-duration rejection, stopped-zero suppression, `touchcancel`, and
  per-View cancellation are recorded safety/lifecycle extensions.
- `src/vs/editor/browser/viewParts/viewLines/viewLines.ts:613-677` and
  `src/vs/base/browser/fastDomNode.ts:73-89` identify cached
  `.lines-content` `top`/`left` writes as the real rail commit. The browser
  oracle stays below Monaco's big-number translation regime, preserves raw
  style mutations, and deduplicates only the final top/left pair per observer
  batch.

Conformance uses scheduler reference tests plus a browser trace: local accepted
state and render phases come through the internal Viewer-id registry; both
local and Monaco commits come from `MutationObserver`. A page-owned rAF wrapper
installed before either editor groups callbacks and mutation microtasks by the
native timestamp, so callback registration order cannot invent a frame of
lag.

## Text model and tokenization

The upstream `common/model` tree, including its `model/tokens` subdirectory,
maps to the single multi-target local `viewer/common/model` package. Member-level
parity evidence remains in Git history and source citations. The tokenization
merge used the checked-in `vscode` submodule.

## View model and inline decorations

The upstream `common/viewModel/inlineDecorations.ts`,
`viewModelDecoration.ts`, and `viewModelDecorations.ts` units map to focused
files in the single multi-target local `viewer/common/view_model` package.
The upstream `test/common/viewModel/inlineDecorations.test.ts` suite maps to
`inline_decorations_reference_wbtest.mbt` in that package. The ownership
merge and its 23-case conformance denominator use the checked-in `vscode`
submodule; member-level dispositions and terminal product-reach deferrals
remain in Git history.

## Browser view and view parts

The implemented units from upstream `browser/view.ts`, `browser/view/*.ts`,
and `browser/viewParts/**/*.ts` map to focused files in the single js-only
local `internal/viewer/browser/view` package. Unsupported pinned view-part
units keep their reviewed `DEFERRED`/`N-A` dispositions in Git history:

- `browser/view.ts` maps to `view.mbt`;
- shared view machinery maps to source-shaped units such as
  `rendering_context.mbt`, `view_layer.mbt`, `view_overlays.mbt`,
  `view_part.mbt`, and `view_user_input_events.mbt`;
- each implemented `browser/viewParts/<part>/*.ts` unit maps to the
  corresponding part-named `.mbt` files in that same package, from
  `content_widgets.mbt` through `view_zones.mbt`.

These `.mbt` files preserve source-unit responsibilities for inventory,
citations, and parity review; they do not create MoonBit packages or
namespaces. The `viewer/browser/view_parts/*` directories are CSS asset paths
only, retained so the stylesheet build and provenance paths stay stable.

## Editor contribution ownership

The complete upstream
`browser/widget/codeEditor/codeEditorContributions.ts` unit, its bounded
`codeEditorWidget.ts` integration clusters, and the scoped hover, folding,
agent-feedback, quick-diff, context-menu, and definition controller lifetimes
map to the root
`viewer/editor_extensions.mbt` registry plus focused root registration/host
files. The local `Viewer.contributions` map is the one per-editor instance
store, corresponding to Monaco's `CodeEditorContributions._instances`.
Feature-specific root accessors are typed matches over that central map, not
independent editor-id-keyed stores. Its closed rows are feedback input,
feedback widgets, folding, Markdown comments, content hover, the local
quick-diff decorator, context menu, and definition navigation.
The registered Monaco timing modes remain recorded, but the current Viewer
constructs every row eagerly. Local quick diff is the per-Viewer reduction of
the workbench controller plus decorator, not a port of
`QuickDiffEditorController`.

The ownership migration used the checked-in `vscode` submodule. Its frozen
upstream/local ledgers, representation proof, lifetime trace, and seam-based
deviation remain in Git history; the completed outcome is summarized in
`docs/exec-plans/HISTORY.md`.

## HTML editor context menu

The editor context menu is a behavior port audited against pinned VS Code
revision `b18492a288de038fbc7643aae6de8247029d11bd`. It targets Monaco/VS Code
Web's HTML surface, not Electron's optional native desktop menu.

- `src/vs/editor/browser/controller/mouseHandler.ts:90-92,262-266`,
  `viewController.ts:406-408`, `viewUserInputEvents.ts:44-46`, and
  `browser/widget/codeEditor/codeEditorWidget.ts:179-180,1979-1983` define the
  hit-tested DOM-to-editor `contextmenu` event path.
- `src/vs/editor/contrib/contextmenu/browser/contextmenu.ts:31-248,391-412`
  supplies eligible-target filtering, selection-preserving cursor placement,
  live action collection, native fallback, pointer/cursor anchoring, and
  Shift+F10.
- `src/vs/platform/contextview/browser/contextMenuHandler.ts:42-164`,
  `src/vs/base/browser/ui/contextview/contextview.ts:184-279`, and
  `src/vs/base/browser/ui/menu/menu.ts:105-175,219-384,647-763,1019-1333`
  supply hide-before-run, focus restoration, dismissal, keyboard/submenu
  interaction, viewport fitting, ARIA roles/state, and the selected 24px-row
  HTML styling.
- `src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:44-49,274-312,
  343-374` supplies top-level `Go to Definition` and
  `Peek > Peek Definition`. As a deliberate local product choice, the Viewer
  flattens those into adjacent top-level `Go to Definition` and
  `Peek Definition` actions. The local closed command registry owns their
  labels, keybinding hints, ordering, and live preconditions; the browser
  widget receives only an immutable entry tree and opaque command ids.

Only Code content text/empty space and exact semantic Markdown source rows
suppress the native browser menu. Injected text, margins, widgets, scrollbars,
prose, ordinary fences, padding, unavailable action sets, and stale Markdown
projections fall through. A pointer hit outside the current selection moves
one cursor before menu resolution; a hit inside preserves the selection.
Shift+F10 and the Context Menu key use the same menu, actions close it before
dispatch, and Escape, Tab, outside primary pointer input, blur, model/content
change, scroll, or disposal close it.

The first surface intentionally omits Electron/native integration,
clipboard/edit/refactor/source/history and extension-contributed actions,
scrollbar-specific commands, touch long press, mnemonics/icons/check states,
visible disabled rows, and a public menu-extension API. The browser shell
supports one optional submenu level, although the current definition menu does
not use it; this is not a general port of `IContextMenuService`, `Menu`,
`ActionBar`, or workbench menu services. In particular, replacement is per
independent Viewer rather than serialized by a process-global context-menu
service.

## Definition navigation and References Peek

Goto Definition is a behavior port audited against pinned VS Code revision
`b18492a288de038fbc7643aae6de8247029d11bd`. The Ctrl/Command link gesture and
Peek ordering, selection, async ownership, and teardown use
algorithm-fidelity ports for the selected observable invariants below.

- `src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:105-167,177-248`
  owns request cancellation, no-result feedback, one-result opening through
  `ICodeEditorService.openCodeEditor`, the default multiple-result Peek policy,
  and delegation through `ReferencesController`; zero results stop before Peek.
  `DefinitionAction` and the F12/Web CtrlCmd+F12 and Alt+F12 registrations are
  at `:253-312,343-374`.
- `src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:644-727` owns
  provider-backed References actions. Upstream `Go to References` registers
  Shift+F12 and queries with `includeDeclaration=true`; `Peek References`
  registers the Peek-menu action. The local readonly product combines those
  observable seams into one direct Peek action and keeps it adjacent to
  Definition in the flattened navigation menu.
- `src/vs/editor/contrib/gotoSymbol/browser/goToSymbol.ts:23-91` queries every
  ordered matching References provider, isolates provider failure, observes
  cancellation, and retains provider order independently of completion order.
  The local References registry ports those query invariants; Moon IDE owns
  declaration inclusion.
- `src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:735-825,858-859`
  supplies the precomputed
  `peekLocations`/`showReferences` entry. Local
  `Viewer::show_references(Position, Array[Location])` is the corresponding
  MoonBit-native display seam; it copies exactly the supplied locations and
  never invokes a References provider.
- `src/vs/editor/common/languageFeatureRegistry.ts:171-212` and
  `languageSelector.ts:29-111` order matching providers by selector score
  descending and registration time descending. The local selector surface
  ports exact and wildcard language/scheme scoring, path-match scoring, list
  maxima, zero-score empty filters, and newer-first tie-breaking; definition
  and References results retain that priority regardless of concurrent
  completion order.
- `src/vs/editor/contrib/gotoSymbol/browser/link/goToDefinitionAtPosition.ts:
  47-79,111-224,266-315` resolves only eligible content-text targets, cancels
  prior work, validates position/value/selection/scroll freshness, decorates
  only a non-empty result, clears on cancel, and launches a fresh definition
  action on execution rather than consuming the preview result. The
  down-before-modifier and mouseup execution state belongs to
  `link/clickLinkGesture.ts:122-235`.
- `src/vs/editor/contrib/gotoSymbol/browser/referencesModel.ts:22-297` owns
  URI grouping, deterministic ordering/deduplication, nearest selection,
  circular navigation, and source previews. Local canonical URI strings retain
  fragments, and snippets retain three source strings instead of exposing
  string offsets.
- `src/vs/editor/contrib/gotoSymbol/browser/peek/referencesController.ts:
  36-304,318-420` owns the per-editor Peek request, stale-result
  disposal, model/widget teardown, focus restoration, result switching,
  confirmation, and F4/Shift+F4/Escape/Enter routing.
- `src/vs/editor/contrib/gotoSymbol/browser/peek/referencesWidget.ts:
  42-183,243-608` supplies reference decorations, the editor-owned zone shell,
  embedded preview editor, result UI, layout, and model-reference replacement:
  a late reference is released, the previous preview reference is released
  before replacement, and unavailable preview uses a fallback model.
- `src/vs/editor/contrib/gotoSymbol/browser/peek/referencesTree.ts:
  29-61,65-103,107-223` supplies lazy group-model resolution, file groups,
  counts, snippets, match spans, and accessible labels. The local feature owns
  a closed file/reference ARIA tree instead of importing VS Code's generic
  Workbench tree/list infrastructure.
- `src/vs/editor/standalone/browser/standaloneCodeEditorService.ts:25-41,
  63-103` handles same-current-model navigation locally and declines other
  resource URIs. `standaloneEditor.ts:456-497` exposes consumer-owned
  `registerEditorOpener`; local `LocationOpenerHandle` is the single
  host-neutral equivalent and adds source Viewer identity plus Current/Side
  intent without workspace or editor-group types.
- `src/vs/editor/common/services/resolverService.ts:14-34,44-90` defines the
  disposable target-model reference contract. Monaco standalone resolves only
  models already registered in its process-wide model service
  (`standaloneServices.ts:157-183`, registered at `:1192`, with model creation
  at `standaloneEditor.ts:225-235`). The local editor deliberately has no global
  model registry: same-resource Peek reuses the attached caller-owned model;
  each cross-resource expanded-group snippet request and selected preview uses
  an optional caller-supplied resolver and its own exactly-once model lease.

Intentional local differences and exclusions:

- The browser-only Viewer uses Alt+F12 on all platforms and CtrlCmd+F12 as a web
  Definition binding; VS Code overrides Peek Definition to
  CtrlCmd+Shift+F10 on Linux. Shift+F12 directly opens Peek References locally:
  the readonly Viewer has no `multipleReferences` goto preference or editable
  navigation history through which to route an intermediate Go to References
  action.
- The local link trigger is exact platform Ctrl/Command. VS Code can remap it
  from `multiCursorModifier` and also supports side/middle-click variants.
  Local preview caching requires the same model identity, attachment
  generation, content version, and word range; execution records the
  mouse-down line and rechecks current target eligibility on mouseup, matching
  the upstream gesture boundary.
- Link hover source previews, `originSelectionRange`/`targetSelectionRange`,
  multi-definition hover-count text, middle-click,
  definition-link-opens-in-Peek, and link open-to-side are N-A.
- Local selector patterns intentionally support only exact paths or one `*`
  prefix/suffix wildcard. Monaco's full glob surface (`**`, `?`, braces,
  character ranges, and relative-pattern bases) remains deferred.
- Same-resource Current opening paints the upstream-shaped 350 ms
  `symbolHighlight`. Cross-resource target decoration remains host policy
  because `LocationOpenerHandle` reports acceptance without returning an
  installed target Viewer/model.
- Workbench navigation history, alternative commands, `gotoAndPeek`, stable
  Peek, editor-group migration, drag-and-drop, sash, persisted Peek layout, and
  a general-purpose reusable Tree/List abstraction are N-A.
- The local Peek uses a blank ViewZone spacer plus Viewer overlay and nested
  readonly Viewer instead of `PeekViewWidget` plus
  `EmbeddedCodeEditorWidget`. The selected fidelity contract includes the
  default 18-line requested height, the inherited 80%-of-viewport reduction
  with a 12-line floor, preview-left and results-right split, grouped
  file/reference rows, lazy snippets,
  filename/directory/result counts, one decoration for every reference in the
  previewed resource plus a distinct selected decoration, post-insertion
  anchor-to-next-line reveal, request generation/cancellation, stale-reference
  release, preview replacement, child/group teardown, close/focus ordering,
  recursive Peek suppression, and the shared Viewer custom scrollbar around
  the result tree's native scrolling content. Upstream unavailable preview
  uses a fallback text model, while the local shell removes its child/reference
  and shows an unavailable state.
  Upstream same-Peek toggle accepts a range containing the widget position; the
  local readonly anchor is exact model/generation/version/position. Empty
  precomputed or provider-backed References locations retain an accessible
  empty dialog;
  Definition's zero-result request still stops Peek and uses its existing
  feedback.
- Upstream's aliased precomputed action titles its model `Locations`, while the
  provider-backed action uses `References`. Both the local public entry and
  provider action use the product-facing `References` title.
- Upstream F4/Shift+F4 also performs Peek-mode goto and re-anchors the outer
  editor. The local keys change only tree selection and the nested preview
  because the host-neutral opener does not expose same-Viewer model transfer.
- Upstream's generic tree keeps focus on one active-descendant container. The
  feature-local tree uses roving row `tabindex` plus explicit
  dialog/tree/treeitem roles and selection/position metadata.
- Upstream's visible fallback adds one to already 1-based line/column values
  while its accessible label does not. The local fallback and label both keep
  the repository's 1-based `Range` coordinates.
- Local Enter/double-click confirmation closes Peek before Current/Side
  opening. Keeping and re-anchoring the shell after same-editor movement is
  N-A for the current host contract. VS Code's Ctrl/Cmd+K F2 focus-switch chord
  remains deferred because the local keybinding registry has no chord
  primitive.
- `IModelService`, `ITextModelContentProvider`, filesystem/network loading, tab
  policy, and HTTP window fallback are N-A. The host resolver owns all loading
  and model lifetime policy. Definition opener rejection and unavailable
  selected preview produce local non-destructive feedback; References opener
  rejection has no Definition-message side effect.
- Upstream places Peek References under `EditorContextPeek`; the local HTML
  menu deliberately keeps it as a top-level navigation row immediately after
  Peek Definition. The local provider contract has no `ReferenceContext`;
  Moon IDE's `find-references` result already includes the declaration.
  Go to References, CodeLens, document highlights, the Workbench References
  View, filtering, virtualization, and result copy/history actions remain
  outside this feature.
- Same-resource goto reveals in the center only when outside the viewport;
  upstream uses `NearTopIfOutsideViewport`. Upstream word-specific no-result
  text remains Definition-only, and 250 ms action progress is not reproduced.
  VS Code internal-scheme filtering in `getLocationLinks` is N-A because local
  locations have no editor-internal scheme contract.

## Public editor API ownership

The scoped public clusters from upstream `common/config/editorOptions.ts`,
`common/editorCommon.ts`, the complete cursor-event source unit,
`browser/editorBrowser.ts`, `browser/widget/codeEditor/codeEditorWidget.ts`,
`editor.api.ts`, `editor.main.ts`, and the generated Monaco declarations map to
these local owners:

- DOM-free cursor/model/scroll events and editor-option enums map to the single
  multi-target `viewer/common/editor_api` package.
- Public mouse, ViewZone/accessor, and unmanaged overlay-widget contracts map
  to `viewer/browser`; mutable/rendered zone and widget state remains private in
  `internal/viewer/browser/view`.
- The opaque `Viewer`, `ViewerOptions`, `ViewerServices`, and `ViewerViewState`
  facade maps to root `viewer`. Root factories let external hosts construct the
  browser-owned zone/widget values without importing browser internals.
- Language, marker, feedback, quick-diff, and logging service seams map to
  opaque handles beside their public vocabularies. Concrete feature services
  remain caller-retained common values or module-private
  `internal/viewer/contrib/**` implementations and never appear in the root
  generated interface.
- Root debug subscriptions have no public upstream/API role. Internal
  workbench/browser observability maps to the local Viewer-id-keyed
  `internal/viewer/browser/testing` seam, while the embedded host uses the
  semantic model-change event plus a URI-guarded native animation frame.

The boundary migration uses the checked-in `vscode` submodule. Its closed local
and upstream ledgers, dependency proof, and generated-interface snapshots
remain in Git history; the completed outcome is summarized in
`docs/exec-plans/HISTORY.md`.
