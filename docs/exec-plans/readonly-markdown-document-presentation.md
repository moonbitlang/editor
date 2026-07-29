# Readonly Markdown Document Presentation

Status: proposed
Date: 2026-07-28
Oracle: VS Code `b18492a288de038fbc7643aae6de8247029d11bd`

## Goal

Make Markdown a presentation that the reusable `viewer` facade selects and
owns when its current `TextModel` represents a `*.md` resource. An embedder or
the reference workbench must only create the ordinary model and call
`Viewer::set_model`; it must not parse Markdown, create a second viewer, or
install Markdown-specific shell logic.

The first shipped slice must provide:

- rendered, readonly Markdown for ordinary `.md` files;
- the same rendered presentation for `.mbt.md` while preserving the model's
  existing `moonbit` language id;
- editor-token syntax highlighting for fenced code;
- language hover and diagnostic marker presentation inside compiler-recognized
  `mbt check ...` and `moonbit check ...` fences in `.mbt.md`;
- original model identity, URI, revision, and explicitly typed UTF-16
  coordinates at every language-provider, wire, and marker boundary;
- model-content refresh, theme refresh, scroll/focus, model replacement, and
  disposal behavior owned by `Viewer`.

The implementation is readonly. Interactive editing, undo/redo, task-checkbox
mutation, and every Notebook/cell-document mechanism are outside this plan.

## Scope and Port Mode

### Primary source

The primary structure oracle is VS Code's Experimental Markdown Editor, not the
classic Markdown Preview and not Notebook:

- `vscode/extensions/markdown-language-features/src/preview/markdownEditorProvider.ts:9-86`
  keeps one `TextDocument` as source of truth, initializes one custom editor,
  forwards document changes, and disposes the document/view bridge.
- `vscode/extensions/markdown-language-features/markdown-editor-src/editor.ts:23-125`
  owns one `EditorModel`, creates one `EditorView` and `EditorController`,
  supplies code-block rendering/highlighting, and omits the edit autorun in
  readonly mode.
- `vscode/extensions/markdown-language-features/markdown-editor-src/markdownEditor.css:6-22`
  gives that view the complete host box and its own scrolling surface.
- `vscode/extensions/markdown-language-features/src/preview/markdownEditorProvider.ts:128-151`
  is the host-side syntax-highlighting bridge.
- `vscode/extensions/markdown-language-features/markdown-editor-src/syntaxHighlighter.ts:96-215`
  owns per-code-block highlighting sessions, dense offset-based tokens,
  stale-text rejection, theme refresh, and disposal.
- `vscode/src/vscode-dts/vscode.proposed.documentSyntaxHighlighting.d.ts:8-34`
  defines dense whole-source token coverage, the unstyled fallback, and theme
  invalidation observed by that bridge.
- `vscode/extensions/markdown-language-features/src/extension.shared.ts:49-55`
  registers the editor and its lifetime.
- `vscode/extensions/markdown-language-features/package.json:859-879` declares
  the `*.md` selector and experimental editor identity.
- `vscode/src/vs/workbench/services/editor/common/editorResolverService.ts:40-59`
  shows that VS Code can choose this editor as the Markdown presentation in the
  Agents window.

`@vscode/markdown-editor` is consumed as an external package by the pinned VS
Code tree. This plan ports only the behavior visible through the checked-in
provider, editor wrapper, and syntax-highlighter bridge. It does not claim a
full source audit of that package.

### MoonBit semantic and backend sources

VS Code remains the sole structure/lifecycle oracle. The MoonBit-specific
fence grammar is a secondary product-semantic source: MoonBit compiler commit
`4ca4d3ef1213bcf038d88edadb79ae3a7ae8c23a`,
`lib/xml/parsing/md_test_extraction.ml:40-58`, splits only on ASCII space,
removes empty tokens, and recognizes the prefixes `mbt check` and
`moonbit check`. It therefore allows repeated spaces and trailing tokens, is
case-sensitive, and does not treat a tab as the separator.

The local remote-language path is also product evidence, not a VS Code parity
claim. Its request/response and revision behavior is audited below because the
Markdown surface must not make a stale backend result appear current.

### Selected modes

- **Behavior port**: document selection, source-of-truth ownership, readonly
  presentation, update/theme/lifecycle behavior, safe Markdown rendering,
  focus/scroll routing, and fenced-code language-feature behavior.
- **Algorithm-fidelity port**: displayed fenced-code UTF-16 boundary to source
  offset mapping, source range projection back into rendered code, and
  asynchronous hover freshness/cancellation ordering. These values determine
  which symbol and diagnostic the user sees and cannot be approximated.
- **Not a full source audit**: TypeScript classes, webview messages, custom
  editor registration types, and the external component's internal AST are not
  local representation contracts.

### Local boundary and consumers

The reusable boundary is the root `viewer` package. The direct embedded
example and `internal/shell/workbench` remain ordinary consumers:

```text
host-owned TextModel
  -> Viewer::set_model
  -> model-owned ViewModel and services
  -> BrowserPresentation
       Code(CodeBrowserData)
       Markdown(MarkdownDocumentView)
  -> active DOM
```

The browser Markdown view is selected from the model URI/path, not solely from
`language_id`. This is required because
`internal/shell/workspace/source.mbt:90-100` intentionally maps `.mbt.md` to
`moonbit` and ordinary `.md` to `markdown`.

## Current Repository Inventory

- `viewer/model_data.mbt` currently assumes the mounted presentation is one
  `ModelBrowserData` containing a code `View` and mouse handler.
- `viewer/attach_model.mbt` always creates that code `View`.
- `viewer/view_host.mbt`, `viewer/viewer.mbt`, `viewer/reveal.mbt`, and the
  public read/scroll/focus helpers directly assume the active browser surface
  is the code `View`.
- `viewer/editor_extensions.mbt` owns optional editor contributions. A complete
  document presentation is not one of those optional features.
- `internal/viewer/markdown/markdown.mbt` owns safe cmark conversion, but
  `MarkdownCodeBlock` currently retains only normalized code and the first
  fenced-info token. It loses the `check` remainder and every source offset.
- `internal/viewer/browser/markdown` already owns inert DOM construction,
  URL/media policy, target reuse, Mermaid lifetime, and deterministic disposal.
- `internal/viewer/markdown/tokenized_code_block.mbt` already maps `mbt` to
  `moonbit` and renders registered tokenizer output with the editor's `mtk*`
  classes.
- `internal/viewer/contrib/hover` already computes marker and language hover
  parts over an original `TextModel`; its browser package owns safe hover-row
  rendering. The existing content widget is tied to code-View coordinates and
  cannot be mounted unchanged on the Markdown document surface.
- `viewer/common/languages` registers hover but not definition, references, or
  semantic-token presentation. Diagnostics enter through
  `viewer/common/markers`.
- `internal/shell/workbench/language_client.mbt:48-64` converts the repository's
  1-based model position to a 0-based absolute UTF-16 offset and sends the
  original URI/revision. It currently accepts any correlated hover payload
  without checking the returned URI/revision.
- `internal/shell/server/server.mbt:378-400` validates URI/revision before
  invoking the provider and converts the 0-based offset back through the cached
  full document. It does not revalidate the cached snapshot after the provider
  returns.
- `internal/shell/server_host_native/language_provider.mbt:25-55` invokes
  `moon ide hover` with the real `.mbt.md` path and original 1-based UTF-16
  line/column, but the command reads the file on disk rather than the supplied
  model text.
- `internal/shell/remote_protocol/protocol.mbt:98-114` carries URI/revision on
  diagnostics and hover responses. `internal/shell/workbench/language_client.mbt:68-80`
  currently discards the diagnostics revision.
- `internal/shell/server_host_native/moon_check.mbt:38-49,77-116` stores
  diagnostics without the producing revision, replays them under the latest
  revision, and stamps a completed run from the revision map at publish time.
  A run that races a document update can therefore be mislabeled as current.
- `internal/shell/workbench/app.mbt:381-402` already performs the desired host
  flow: `set_model`, optional view-state restore, then `handle_initialized`.
  It must not gain Markdown-specific branching.

## Product Contract

### Presentation selection

`Viewer` selects the Markdown presentation when either:

1. the URI path ends in exact lowercase `.md`, including `.mbt.md`; or
2. the model language id is `markdown`, to support untitled/in-memory Markdown
   models without a filename.

URI suffix wins over language id. A `.mbt.md` model stays `moonbit` for
provider/tokenizer selection but is rendered as Markdown. A non-Markdown URI
with language id `moonbit` continues to use the code presentation.

The selection is private and automatic. This plan adds no public
`render_markdown`, `editor_kind`, or presentation option.

### One source of truth

- The caller-owned `TextModel` is the only document identity and text source.
- The existing `ViewModel`, marker lease, attached-view handle, version, and
  model/content events remain model-scoped and are created for both
  presentations.
- A Markdown code projection is a display index into that model. It is never a
  `TextModel`, never registered with language services, and has no URI or
  revision of its own.
- `Viewer::get_model`, `get_value`, `set_value`, model events, decorations, and
  provider calls continue to refer to the original model.
- A same-model `set_value` rerenders from the new model snapshot and invalidates
  remote hover/diagnostic freshness for the previous content version. A model
  swap disposes the old presentation before the new one becomes active.

### Readonly Markdown behavior

- Headings, paragraphs, lists, links, images, fenced code, existing Diago, and
  existing Mermaid behavior render through the shared safe Markdown boundary.
- Raw HTML and scripts remain inert under the current safe-cmark and inert-DOM
  policy.
- Links and images use the existing URI resolver/allowlist. Document links use
  the existing external-action policy; remote images follow the already
  reviewed whole-line Markdown policy rather than adding a shell-owned loader.
- Fenced code uses its info-string language first and the model language only
  as fallback. The existing aliases (`mbt`, `js`, `ts`) remain canonicalized by
  the shared token renderer.
- Token runs cover each displayed code string exactly; a missing tokenizer
  yields the existing default/unstyled coverage instead of dropping text.
- Theme changes reuse the retained document target, refresh code token classes,
  and rerender Mermaid through its existing stale-safe lifetime.
- External model changes replace presentation content; there is no DOM-to-model
  edit path.

### `.mbt.md` IDE behavior

Only a fenced block in a `.mbt.md` resource whose parsed info string has the
compiler-recognized first two ASCII-space tokens `mbt check` or
`moonbit check` opts into the first semantic slice. Empty tokens from repeated
spaces are ignored and later tokens are allowed. Matching is case-sensitive;
a tab does not separate the two tokens.

For those blocks:

- pointer hover resolves a displayed UTF-16 boundary to an original model
  offset and calls the existing `ContentHoverComputer` with that original
  model and range anchor;
- language-provider hover and marker hover are merged and rendered with the
  existing safe hover-content renderer;
- diagnostics whose original ranges intersect the block are projected onto
  rendered code, with severity styling and diagnostic text available through
  marker hover;
- a provider result range is highlighted only where it maps back into the same
  current projection; valid hover content may still display when the returned
  range extends outside that block;
- pointer positions on the fence delimiter, info string, synthetic indentation
  padding, or non-code Markdown do not issue a MoonBit hover request.

Plain `mbt`, `mbt test`, `mbt nocheck`, differently cased, tab-separated,
malformed, and unlabelled blocks still receive ordinary static code rendering
but do not opt into semantic hover in this milestone.

## Representation Decision

Use a closed, private presentation enum owned by one `ModelData` attachment:

```text
BrowserPresentation
  Code(CodeBrowserData)
  Markdown(MarkdownDocumentView)
```

This is a closed family with exhaustive root dispatch, so an enum is preferable
to a trait or open registry. `ModelData.browser` remains `None` only for the
headless harness and becomes `Some(BrowserPresentation)` for every mounted
model.

The current `ModelBrowserData` becomes the code-specific payload. The Markdown
payload lives in a new lower-level JS-only package and is created through a
narrow capability record supplied by the root. That package must not import
the root `viewer` facade.

Do **not** implement the primary surface as an editor contribution layered over
or hiding the code `View`. Experimental Markdown Editor creates an independent
`EditorView` over the same source document; a model-scoped presentation owner
matches that lifetime and prevents public DOM/focus/scroll APIs from pointing
at a hidden source editor. Contributions remain optional behaviors attached to
the code editor. Code-only folding, quick-diff gutter, feedback widgets,
Markdown comments, ViewZones, and overlay/content widgets become explicit
no-ops when no code `View` is active unless a later plan gives them a Markdown
presentation.

The root owns all cross-presentation ordering. Lower packages expose concrete
MoonBit values and small capability records; browser-only primitives that
Rabbita does not provide may use narrow JS FFI. No JavaScript object owns
feature lifecycle or freshness state.

## Presentation Routing Contract

The zero-behavior-change refactor must first make every current code-View use
explicit. Add private root helpers such as:

- current browser presentation;
- current code browser data / code `View`;
- active presentation root;
- active focus and focus containment;
- active layout/render;
- active scroll state and content extents;
- active disposal and root removal.

The public surface is then partitioned as follows:

| Public behavior | Markdown disposition |
|---|---|
| model/value/version/revision, model events, decorations | Preserve original `TextModel`/`ViewModel` behavior |
| `get_dom_node`, `focus`, text/widget focus, `layout` | Route to the Markdown root |
| scroll getters/setters, save/restore view state, content/scroll extents, scroll event | Route to the Markdown scroll container |
| theme and model-content refresh | Route to the retained Markdown view |
| reveal line/position/range | Scroll to the owning source-mapped Markdown block; use the nearest preceding mapped block when prose has no finer anchor |
| visible source ranges | Derive from source-mapped Markdown blocks intersecting the viewport; return the full model range only when no block anchor exists |
| cursor/selection getters, setters, and commands | Code-presentation-only; use the existing no-model sentinel/no-op required by each signature and never expose hidden `ViewModel` cursor state |
| source line width/column and code-View-only pixel queries | Retain their `ViewModel`-based source answer where possible; return the existing empty/zero fallback when a real code `View` is required |
| mouse events, ViewZones, overlay widgets, folding, quick-diff gutter, feedback widgets, Markdown comments | Code-presentation-only in this plan; no synthetic code-editor event is emitted from prose |
| lifecycle and metadata (`create`, `dispose`, container/id/type/options/init/dispose event) | Preserve current behavior; root removal dispatches the active presentation and `get_editor_type` remains `vs.editor.ICodeEditor` |

Gate A must enumerate every `Viewer` public method from
`viewer/pkg.generated.mbti` under one of these rows and record any mismatch in
this plan before implementation. No public signature is expected to change.

Gate A inventory (83 methods):

- **Model/value/events/decorations (11):**
  `create_decorations_collection`, `delta_decorations`,
  `get_decorations_in_range`, `get_line_decorations`, `get_model`,
  `get_value`, `on_did_change_model`, `on_did_change_model_content`,
  `remove_decorations`, `set_model`, `set_value`.
- **Active root/focus/layout (5):** `focus`, `get_dom_node`,
  `has_text_focus`, `has_widget_focus`, `layout`.
- **Active scroll/state/extents (12):** `get_content_height`,
  `get_content_width`, `get_scroll_height`, `get_scroll_left`,
  `get_scroll_top`, `get_scroll_width`, `on_did_scroll_change`,
  `restore_view_state`, `save_view_state`, `set_scroll_left`,
  `set_scroll_position`, `set_scroll_top`.
- **Theme refresh (1):** `update_options`.
- **Reveal (18):** every `reveal_line*`, `reveal_lines*`,
  `reveal_position*`, and `reveal_range*` method in the generated interface.
- **Visible source ranges (1):** `get_visible_ranges`.
- **Code-only cursor (8):** `get_position`, `get_selection`,
  `get_selections`, `on_did_change_cursor_position`,
  `on_did_change_cursor_selection`, `set_position`, `set_selection`,
  `set_selections`.
- **Source/code geometry (9):** `get_bottom_for_line_number`,
  `get_layout_info`, `get_line_height_for_position`,
  `get_offset_for_column`, `get_scrolled_visible_position`,
  `get_top_for_line_number`, `get_top_for_position`,
  `get_visible_column_from_position`, `get_width_of_line`.
- **Code-only features/events (10):** `add_overlay_widget`,
  `change_view_zones`, `fold_top_level`, `on_did_change_hidden_areas`,
  `on_did_change_view_zones`, all four `on_mouse_*` methods, and
  `remove_overlay_widget`. Overlay add/remove always updates the
  Viewer-lifetime registration map; only mounting/unmounting is a no-op
  without Code.
- **Lifecycle/metadata (8):** `create`, `dispose`,
  `get_container_dom_node`, `get_editor_type`, `get_id`, `get_options`,
  `handle_initialized`, `on_did_dispose`.

## Source Projection and Coordinate Contract

### Coordinate ledger

Do not label the whole chain merely "UTF-16 position." Each boundary has one
explicit representation:

| Boundary | Representation |
|---|---|
| Markdown projection and DOM code-line maps | 0-based, half-open absolute UTF-16 `OffsetRange`/boundary offsets |
| `TextModel`, language-provider input, hover/diagnostic `Range` | repository `Position`/`Range`: 1-based UTF-16 line and column |
| `DocumentPositionRequest` on the remote wire | 0-based absolute UTF-16 document offset |
| hover/diagnostic ranges on the current remote wire | repository 1-based UTF-16 `Range`, serialized without rebasing |
| native `moon ide hover --loc` and `moon check` locations | 1-based line and column, converted once at the host adapter |
| a future standard LSP adapter | 0-based UTF-16 line and character only inside that adapter |

`TextSnapshot::get_offset_at/get_position_at` is the only conversion between
the first two local spaces. The remote server converts the request offset back
through the cached snapshot before invoking a provider. No presentation or
browser FFI performs `+1`/`-1` arithmetic. Gate A also corrects the stale
"zero-based position" comment on `language.HoverProvider`; its actual
`@base_common.Position` contract is 1-based.

### DOM-free values

Extend the shared Markdown core with MoonBit-owned values equivalent to:

```text
MarkdownCodeBlock
  code
  language_id
  full_info_string
  info_remainder
  block_source_range
  code_lines

MarkdownCodeLine
  displayed_text
  source_line_number
  source_range
  displayed_boundary_to_source_offset

MarkdownDocumentProjection
  ordered block anchors
  ordered code-block projections
```

Names may be refined during implementation, but the fields and ownership may
not be weakened. Ranges are 0-based, half-open UTF-16 `OffsetRange` values over
`TextSnapshot::get_value`. Every displayed boundary in a code line has an
explicit original offset. Do not encode the mapping as one document-wide line
or column delta.

Parse the same LF-normalized snapshot the model exposes. Use cmark with
`layout=true` and `locs=true`; retain the full info string and each code
`StringNode` location before converting to the cmark-independent values.
Rendering and projection must come from the same parse/configuration so a
projection cannot describe a different interpretation of the source.

Convert a non-empty cmark `TextLoc` from its inclusive
`first_ccode..last_ccode` form to
`OffsetRange(first_ccode, last_ccode + 1)`. Use each code-line `StringNode`
location rather than deriving all lines from the enclosing block range. For a
line whose rendered value is longer than its source span because cmark inserted
leading padding, mark those leading displayed boundaries non-semantic and map
the remaining equal-length UTF-16 units one-to-one. If the rendered/source
relationship is not representable by that reviewed rule, keep the static code
render but make the line non-semantic instead of issuing a request at a guessed
position. Ordered prose/block anchors use `Block::meta` through the same
inclusive-to-half-open conversion.

For cmark-inserted padding caused by nested containers or a partially consumed
tab, boundaries that do not correspond to an original code unit are marked
non-semantic. A pointer on those boundaries does not launch hover. All other
display boundaries round-trip:

```text
display boundary
  -> source offset
  -> TextSnapshot::get_position_at
  -> TextModel provider
  -> returned source Range
  -> source offsets
  -> current display boundaries
```

### Required mapping cases

The algorithm-fidelity suite must cover:

- zero and multiple fenced blocks, including identical code text;
- `mbt check`, repeated ASCII spaces, and trailing tokens versus plain/test,
  differently cased, and tab-separated non-opt-in info strings;
- LF input and CRLF/lone-CR input normalized by `TextSnapshot`;
- astral characters and isolated UTF-16 surrogate code units before and inside
  a block;
- blank first/last code lines and a missing closing fence;
- fences nested under block quotes and list items;
- spaces and tabs before code, including partially consumed tabs;
- a diagnostic/provider range wholly inside, crossing a line, and extending
  outside a block;
- mapping at the first code-unit boundary, end-of-line boundary, and
  end-exclusive block boundary.

## Async and Lifecycle Contract

The Markdown view owns one monotonic projection generation and one current
hover request source. A request stamp contains:

- physical model identity;
- model URI and caller-owned revision;
- model content version;
- `ViewerModelSlot` attach generation;
- Markdown projection generation;
- code-block identity;
- original source offset;
- caller cancellation token/source.

Before and after every await, the completion verifies the complete stamp.
Moving to another semantic boundary, leaving the presentation, content flush,
theme-triggered projection replacement, model replacement, model disposal, or
Viewer disposal cancels and retires the request. A late result may not mutate
DOM, hover state, diagnostic styling, or test observability.

### Remote language freshness

The presentation freshness stamp is necessary but not sufficient. Before the
real backend is exposed in Markdown, close the existing remote gaps:

- The workbench hover client accepts a correlated response only when
  `payload.uri` and `payload.revision` equal the request model and the captured
  model identity/version is still current. A mismatch returns no hover and is
  observable in focused protocol tests.
- `RemoteServer::hover` captures the cached document snapshot before invoking
  the provider and rechecks the cached URI, revision, and normalized text after
  it returns. A changed snapshot is rejected rather than packaged as the old
  request.
- The readonly native CLI adapter may continue using `moon ide hover`, but it
  must compare the disk document's normalized text/content signature with the
  supplied model immediately before the command and verify the same disk
  signature immediately after it. A mismatch drops the result; a later pointer
  request may retry after document sync. This is the selected first-slice
  strategy instead of introducing a persistent synchronized LSP session.
- Diagnostics stored by `MoonCheckDiagnostics` carry the revision that
  produced them. A run captures the revision and disk-signature maps at start;
  any document sync or signature change during the run marks it dirty, discards
  that run's output, and schedules the existing follow-up run.
  `note_document` replays only an exact-revision set.
- The workbench applies a diagnostics payload only to the same registered
  model identity/version/URI/revision. A model content change or replacement
  invalidates that registration and clears owner `moon` markers; only a fresh
  document sync establishes another acceptable generation. It never stamps or
  retains a previous content generation's diagnostics under the current model.

These are backend correctness fixes, not Markdown-specific shell selection or
rendering. If editable/unsaved documents enter scope later, replace the native
disk guard with a persistent language server that synchronizes the original
document; do not create block-local virtual documents.

The Markdown browser payload owns:

- document root and scroll container;
- retained `RenderedMarkdown`;
- source projection and DOM block registry;
- code-line pointer listeners and caret hit-testing adapter;
- diagnostic projection;
- hover request owner and DOM-anchored hover widget;
- image/Mermaid/size listeners and scheduled render handles.

Disposal is idempotent and ordered: cancel hover and pending work, dispose hover
rendering, dispose code-line listeners/registries, dispose the shared Markdown
renderer, remove the presentation root, then release the remaining model
attachment through the existing `ModelData` order.

## Evidence Map

| Behavior or invariant | Source | MoonBit disposition | Focused evidence |
|---|---|---|---|
| One source document backs the alternate Markdown surface | `markdownEditorProvider.ts:9-86`; `editor.ts:23-55` | Original `TextModel` and `ViewModel` survive; presentation is model-scoped | Viewer white-box identity/content tests plus direct public-Viewer component |
| One independent Markdown view/controller, not an overlay on a text editor | `editor.ts:71-125` | `BrowserPresentation::Markdown` owns its root, renderer, scroll, and controller | zero-change Code variant tests plus model swap/dispose DOM test |
| Readonly suppresses every DOM-to-source edit | `editor.ts:71-92,115-124` | No edit callback, checkbox mutation, or editing command | component proves model value unchanged after Markdown interaction |
| External source updates refresh the presentation | `markdownEditorProvider.ts:71-76`; `editor.ts:51-55` | same-model content event rebuilds the current projection/target | focused content-flush test and component replacement test |
| Code block chooses a language-specific syntax highlighter | `editor.ts:74-76`; `syntaxHighlighter.ts:149-181` | shared tokenizer-backed code renderer | shared Markdown JS/native tests and component token-class assertion |
| Stale highlighter result cannot overwrite newer text | `syntaxHighlighter.ts:96-146` | synchronous tokens need no await; async hover/Mermaid paths use full freshness stamps | mapping/freshness white-box tests and deferred-hover component |
| Theme refresh re-highlights active blocks | `markdownEditorProvider.ts:147-149`; `syntaxHighlighter.ts:198-215` | retained Markdown target refreshes code/theme and Mermaid | browser component theme test |
| `*.md` selects the Markdown editor | `package.json:859-879`; `editorResolverService.ts:40-59` | private automatic URI/language selection in `Viewer::set_model` | workspace classifier test remains green; direct `.md`/`.mbt.md` component and smoke |
| `.mbt.md` retains MoonBit document identity | Local workspace/client/server/native chain above | presentation selection is URI-based; provider sees original model/URI/revision/position | DOM-free recording provider plus real backend smoke |
| Coordinate bases stay explicit across projection/provider/wire/CLI | `base/common/text.mbt:2-20`; `text_snapshot.mbt:220-234`; `remote_protocol/protocol.mbt:51-58` | convert only through `TextSnapshot` and the native host adapter | boundary-value protocol tests plus astral/first-position projection tests |
| Hover and markers target precise rendered code | Local product extension; upstream only bridges syntax highlighting | exact per-line UTF-16 projection into existing hover/marker computers | algorithm-fidelity mapping suite, marker suite, real pointer component |
| Hover result belongs to the requested snapshot | `language_client.mbt:48-64`; `server.mbt:378-400`; `language_provider.mbt:25-55` | client URI/revision/version gate plus server post-check and native disk pre/post guard | fake delayed response tests, disk-race native test, and real backend smoke |
| Diagnostics belong to the producing revision | `language_client.mbt:68-80`; `moon_check.mbt:38-49,77-116` | revision-bearing stored set, dirty-run discard/rerun, exact client apply/clear | deterministic delayed-check and revision-transition tests |
| Safe same-realm Markdown DOM | Upstream webview CSP is `markdownEditorProvider.ts:154-175` | keep current safe cmark, inert DOM, URI allowlist; do not enable raw HTML/scripts | browser Markdown security regressions plus document component |
| Multiple editor instances have independent state | `extension.shared.ts:49-55` allows multiple editors per document | every `Viewer`/`ModelData` owns its presentation and request generation | two-Viewer white-box/component test |
| Quick-diff gutter in Experimental Markdown Editor | `markdownEditorProvider.ts:89-126`; `editor.ts:57-63` | `DEFERRED` — first slice has no Markdown gutter contract | explicit deferred row, existing code presentation remains green |
| Interactive editing/checkboxes | `markdownEditorProvider.ts:49-67`; `editor.ts:77-92,115-123` | `N-A` — product is readonly | no edit bridge exists; readonly component assertion |
| Webview CSP/message transport | `markdownEditorProvider.ts:28-36,128-175` | `N-A` — local renderer is in the Viewer realm | current browser Markdown policy/lifecycle tests |
| Notebook/cell document identity and lifecycle | none in selected oracle | `N-A` — explicitly excluded by product scope | no Notebook import, URI, model, package, fixture, or test |

Classic Markdown Preview may be consulted only for a focused safe-resource or
source-anchor edge that the Experimental Editor wrapper leaves unspecified. It
must not become the architecture or lifecycle oracle, and any such use must be
recorded as a secondary evidence row before code is ported.

## Implementation Milestones

Each milestone is reviewed, validated at its stated layer, and committed as one
coherent change. Review gates are internal checkpoints and do not pause
execution unless they expose a material unresolved public API, package, or
behavior choice.

### Gate A — Freeze the contract and routing inventory

1. Reconfirm the `vscode` gitlink is the oracle revision recorded above and the
   worktree contains no unreviewed oracle changes.
2. Reconfirm the MoonBit compiler fence parser at the recorded commit, record
   the active `moon`/`moonc` versions, and behavior-probe the accepted and
   rejected info-string cases.
3. Enumerate every public `Viewer` method into the presentation-routing table.
4. Confirm the root generated interface is expected to remain unchanged.
5. Record the planned `moon.pkg` edges:
   - DOM-free source projection stays in `internal/viewer/markdown`;
   - browser presentation lives below `internal/viewer/browser/**`;
   - root `viewer` imports the browser implementation;
   - no reusable package imports `internal/shell`.
6. Audit every coordinate conversion against the coordinate ledger and correct
   the stale `HoverProvider` coordinate comment.
7. Confirm the space-token prefix fence grammar and prove the planned real
   fixture with `moon ide hover --loc` before making a browser assertion depend
   on it.
8. Inventory the hover/diagnostics revision gaps as required prerequisite work;
   they may not be deferred while real backend smoke remains in scope.
9. Append the reviewed Gate A result and any resolved refinements to the
   execution log in this file.

Exit: scope, routing, package edges, coordinate bases, fixture semantics,
backend freshness, and public API expectation are fully accounted for.

### Milestone 1 — Introduce the presentation seam with Code-only behavior

1. Replace the implicit `ModelBrowserData` assumption with the private closed
   `BrowserPresentation` enum and a code-specific payload.
2. Move every direct `.view`/`.mouse_handler` access behind exhaustive
   Code/Markdown-aware root helpers. At this milestone only `Code` is
   constructible.
3. Generalize `ViewerMount` from installing/removing a code View root to an
   active presentation root.
4. Route render, disposal, DOM lookup, focus, scroll, layout, reveal, public
   read helpers, contribution guards, and test seams without changing the
   behavior of any existing model.
5. Keep headless `ModelData.browser=None` unchanged.

Focused evidence:

```sh
MOON_WORK=off moon test --target js viewer
just test-browser-component
```

Review: generated `viewer/pkg.generated.mbti` must be unchanged; every existing
code contribution must still use only the Code payload.

Commit: `refactor(viewer): introduce document presentation seam`

### Milestone 2 — Preserve Markdown source projections

1. Extend `MarkdownCodeBlock` with full info-string and source facts without
   exposing cmark types.
2. Parse with layout/locations and produce `MarkdownDocumentProjection` and
   per-line boundary maps from the same parsed document used for HTML.
3. Keep existing safe-render fallback, Diago, tokenized code, and Mermaid
   behavior unchanged for existing consumers.
4. Add semantic-fence classification as a pure DOM-free function over outer
   resource kind plus full fence info.
5. Update `internal/viewer/markdown/README.md` and regenerate/review its
   interface.

Focused evidence:

```sh
MOON_WORK=off moon test --target js internal/viewer/markdown
MOON_WORK=off moon test --target native internal/viewer/markdown
```

The suite must include every mapping case listed above. Tests traceable to the
pinned Experimental Editor behavior use
`*_reference_{test,wbtest}.mbt` and name the source/revision; local
`.mbt.md` projection extensions use ordinary focused tests.

Commit: `feat(markdown): retain fenced source projections`

### Milestone 3 — Add the editor-owned Markdown document view

1. Add a JS-only lower package under
   `internal/viewer/browser/markdown_document` (final basename may be refined
   only if it preserves this ownership).
2. Build one focusable root and native scroll container, render through
   `internal/viewer/browser/markdown`, retain the source projection, and expose
   a narrow concrete view API for root routing.
3. Add `BrowserPresentation::Markdown` selection in `Viewer::attach_model`.
4. Route model content, theme, layout, scroll, reveal/source anchors, focus,
   render publication, swap, and disposal.
5. Keep Code-only contributions dormant on the Markdown variant.
6. Add owner-adjacent
   `internal/viewer/browser/markdown_document/markdown_document.css` and list
   it in `scripts/build-web.mbtx::css_sources`. Reuse the existing component
   bundle; do not add a browser-test bundle or native static route.
7. Add or update package READMEs and review every changed `moon.pkg`.

Focused evidence:

- headless and mounted Viewer tests for selection, model truth, two Viewers,
  content flush, theme, swap, and idempotent disposal;
- a new direct scenario
  `tests/browser/moonbit/component/markdown_document_scenario.mbt`;
- `?markdownDocument=1` dispatch in
  `tests/browser/moonbit/component/main.mbt`;
- `tests/browser/component/markdown_document.spec.js`.

Commit: `feat(viewer): render Markdown document presentations`

### Milestone 4 — Close remote language revision freshness

1. Make `RemoteLanguageClient::provide_hover` retain the request model
   identity/version/URI/revision and accept only an exactly matching
   `HoverResultPayload`.
2. Revalidate the cached document after `RemoteServer::hover` awaits the
   provider. Reject a replaced or content-mismatched snapshot.
3. Add the native readonly disk guard around `moon ide hover`: normalized text
   and file signature must match the supplied model before the command and
   remain unchanged after it. Drop raced results instead of assigning them the
   request revision.
4. Make `MoonCheckDiagnostics` retain the producing revision with every
   published set. Capture and recheck revision/disk-signature maps, discard
   output from a dirty/incompatible run, rerun through the existing
   single-flight loop, and replay only an exact-revision set.
5. Gate diagnostics application on the registered model
   identity/version/URI/revision. Invalidate that generation and clear owner
   `moon` markers on content change or replacement before another push can
   apply.
6. Keep the remote protocol shape unchanged; add deterministic delayed-provider,
   delayed-check, disk-change, mismatched-response, revision-transition, and
   exact-replay tests.

Focused evidence:

```sh
MOON_WORK=off moon test --target js internal/shell/remote_protocol
MOON_WORK=off moon test --target js internal/shell/workbench
MOON_WORK=off moon test --target native internal/shell/server
MOON_WORK=off moon test --target native internal/shell/server_host_native
```

Review: no workbench code selects or renders Markdown; this milestone only
makes the existing original-document language boundary revision-safe.

Commit: `fix(language): enforce remote revision freshness`

### Milestone 5 — Bridge `.mbt.md` hover and diagnostics

1. Render source-bearing line elements for compiler-recognized semantic fences
   and retain their mapping beside the current projection.
2. Add narrow caret hit testing for a pointer event. Browser FFI may expose
   `caretPositionFromPoint`/`caretRangeFromPoint` and text-node offsets only;
   MoonBit owns block lookup, coordinate conversion, request state, and
   lifecycle.
3. Reuse `ContentHoverComputer` over the original model. Extract the safe
   hover-row renderer from the current content widget into a reusable
   browser-only lifetime; do not duplicate Markdown-to-DOM policy.
4. Add a DOM-anchored Markdown hover surface positioned from the code caret
   rectangle and clamped inside the active presentation viewport.
5. Project current original-model markers into matching code lines and reuse
   marker hover content. A diagnostic never creates a block-local marker store
   or synthetic model decoration.
6. Implement the complete freshness/cancellation contract and record request
   URI, revision, source position, and returned range in the component fixture.

Focused evidence:

```sh
MOON_WORK=off moon test --target js viewer/common/languages
MOON_WORK=off moon test --target js viewer/common/markers
MOON_WORK=off moon test --target js internal/viewer/contrib/hover
MOON_WORK=off moon test --target js internal/viewer/contrib/hover/browser
MOON_WORK=off moon test --target js viewer
just test-browser-component
```

The component must prove real pointer hit testing, original model identity,
the original 1-based model position and derived 0-based wire offset, language
plus marker hover, diagnostic projection, stale completion rejection,
replacement, and disposal.

Commit: `feat(viewer): bridge mbt markdown language hover`

### Milestone 6 — Prove the consumer boundary and close the plan

1. Add `tests/fixtures/workspace/README.md` and a valid
   `tests/fixtures/workspace/src/literate.mbt.md` containing a
   compiler-recognized `mbt check` fence.
2. Extend `tests/browser/smoke/viewer.spec.js` to open both files through the
   sidebar/remote protocol. Assert rendered Markdown and real MoonBit hover at
   the fence symbol.
3. Assert `internal/shell/workbench` has no Markdown presentation branch and
   the embedded example can render an in-memory/URI-based Markdown model through
   the public Viewer API.
4. Update current contracts in:
   - `docs/architecture.md`;
   - `docs/harness.md` and `tests/browser/README.md`;
   - `viewer/README.md`;
   - affected internal package READMEs;
   - generated interfaces.
5. Run full validation, record exact counts/results in this plan, then compress
   the completed outcome into `docs/exec-plans/HISTORY.md` and delete this
   detailed plan in the same final milestone.

Commit: `test(viewer): prove markdown document integration`

## Test Matrix

### DOM-free

- exact presentation selection and compiler-compatible fence classification;
- full info-string retention;
- source boundary round trips and non-semantic padding;
- source-to-projection diagnostic/range splitting;
- original model/URI/revision/position observed by a recording hover provider;
- request cancellation and stale stamp rejection.

### Remote language boundary

- hover response URI/revision mismatch and model version replacement are
  rejected;
- cached document and disk text/signature changes during hover are rejected;
- a dirty `moon check` run publishes nothing and triggers one follow-up run;
- diagnostics replay/apply only at an exact registered
  identity/version/URI/revision, and advancing content clears the old owner set;
- first-character, astral, and end-boundary coordinates survive
  Position-to-offset-to-Position and native CLI conversions without an
  off-by-one shift.

### Viewer white-box

- Code-only presentation seam is behavior-neutral;
- mounted `.md`, `.mbt.md`, and ordinary `.mbt` select the correct variant;
- headless Markdown keeps the source model and creates no DOM presentation;
- same-model flush reuses the owner but replaces projection lifetimes;
- model swap, model disposal, and repeated Viewer disposal release exactly
  once;
- two Viewers over one model retain independent DOM/request state;
- Code-only contributions do not act on Markdown presentation.

### Real browser component

- rendered prose, lists, safe links/images, tokenized code, Diago/Mermaid;
- original model text remains raw Markdown;
- actual DOM caret hit testing over ASCII, astral text, and nested fences;
- hover receives the mapped original 1-based `.mbt.md` model position and
  highlights the mapped source range;
- diagnostics render only in the owning semantic fence and participate in
  marker hover;
- theme, width/layout, native scroll, save/restore, reveal, focus, model flush,
  swap, stale async completion, and disposal;
- no raw HTML/script execution and no unsafe URI navigation.

### Real workbench smoke

- sidebar opens `.md` and `.mbt.md` through the existing host flow;
- `.md` renders without host parsing or presentation selection;
- `.mbt.md` keeps `data-source-uri` and MoonBit language identity;
- the native `moon ide hover` result appears from a symbol in `mbt check`;
- existing ordinary `.mbt` code presentation and hover remain green.

Performance browser tests are `N-A` unless implementation changes the shared
scroll-frame scheduler or perf harness.

## Explicit Exclusions and Deferrals

- **N-A: Notebook.** No notebook package, cell model, cell URI, cell editor,
  virtualized row, kernel, output renderer, or Notebook test is introduced.
- **N-A: editing.** No contenteditable/source mutation, checkbox toggle,
  composition/IME, undo/redo, dirty state, or hot-exit behavior.
- **N-A: virtual documents.** No fenced block becomes a provider-visible model
  or URI.
- **DEFERRED: persistent synchronized LSP transport.** The readonly first slice
  keeps the current native CLI provider behind exact disk/snapshot guards.
  Editable or unsaved source requires a new synchronized-document plan.
- **DEFERRED: definition/references/semantic tokens.** The current Viewer
  language registry/presentation does not expose them. Add them only through a
  separate plan that first establishes a product-wide Viewer contract.
- **DEFERRED: Markdown quick-diff gutter.** Existing Code quick diff remains
  unchanged.
- **DEFERRED: incremental AST/DOM patching and preserved interactive node
  state.** First implementation may replace the retained target on a content
  flush, provided freshness and disposal are exact.
- **DEFERRED: full prose source selection/caret editing and code actions.**
- **N-A: raw HTML/script extensions and webview security-level selector.** The
  local same-realm renderer keeps the stricter existing policy.
- **N-A: classic Preview manager/panel lock/serializer/BroadcastChannel.**
- **N-A: shell-owned Markdown parsing or adapter APIs.**

## Behavioral Deviations

- VS Code contributes the Experimental Markdown Editor with priority `option`
  and conditionally makes it the default in the Agents window. This Viewer has
  no editor resolver and the product requirement is editor-owned rendering, so
  a matching model automatically selects Markdown.
- VS Code's selected component can edit. The local product is readonly and
  deliberately implements only source-to-presentation updates.
- VS Code uses a script-enabled isolated webview and message bridge. The local
  Viewer uses the existing safe same-realm Markdown renderer and direct
  MoonBit-owned capability calls.
- The pinned Experimental Editor only bridges syntax highlighting. This product
  additionally bridges hover and diagnostics to exact original `.mbt.md`
  coordinates.
- The local first slice follows the compiler's ASCII-space token-prefix rule
  for `mbt check ...`/`moonbit check ...` and explicitly defers other MoonBit
  Markdown modes.

## Validation and Exit Gate

Focused commands are listed per milestone. Before declaring the
cross-package/browser-visible implementation complete, run:

```sh
moon info --target all
just check
just test
just build
just test-browser-smoke
git diff --check
```

Review generated interfaces and every changed `moon.pkg`; green repository
checks do not replace the focused evidence above.

- [ ] oracle revision and selected port modes recorded
- [ ] Gate A public-method routing and package-edge review recorded
- [ ] Code presentation behavior preserved through the new closed enum
- [ ] Markdown selection is automatic and shell-independent
- [ ] original model/URI/revision/UTF-16 coordinates proven end to end
- [ ] every projection/provider/wire/CLI coordinate uses the recorded base
- [ ] hover and diagnostics reject mismatched document/disk revisions
- [ ] all projection branches and async stale paths have focused evidence
- [ ] exclusions and deferrals remain explicit
- [ ] no public Viewer API change, or an unavoidable change is reviewed and the
      plan is updated before implementation continues
- [ ] current architecture/README/harness/generated contracts updated
- [ ] full required validation green
- [ ] completed plan compressed into `HISTORY.md` and removed from active plans

## Execution Log

- 2026-07-28: plan proposed from the current repository and pinned VS Code
  oracle. No implementation milestone has started.
- 2026-07-28: self-review replaced the global "1-based" claim with a boundary
  ledger, aligned semantic fences with the compiler's token-prefix grammar, and
  made the current hover/diagnostics revision gaps a blocking milestone.
- 2026-07-29, Gate A reviewed: the `vscode` gitlink, submodule HEAD, and
  inspected Experimental Markdown Editor sources are clean at
  `b18492a288de038fbc7643aae6de8247029d11bd`. The selected behavior and
  algorithm-fidelity modes, independent-presentation representation, and
  exclusions remain valid.
- 2026-07-29, Gate A compiler/toolchain: compiler commit
  `4ca4d3ef1213bcf038d88edadb79ae3a7ae8c23a` and
  `lib/xml/parsing/md_test_extraction.ml` were re-read from the local object
  database; the live parser file is identical (the compiler worktree has an
  unrelated dirty `core` submodule). Active tools are
  `moon 0.1.20260724 (5f1406a)` and
  `moonc v0.10.5+5e7afb0c0`. A temporary package-local `.mbt.md` probe proved
  `mbt check`, repeated ASCII spaces plus trailing tokens, and
  `moonbit check` with `moon ide hover --output-json`; the three symbols
  resolved at their original source ranges. The same file compiled while
  invalid differently-cased, tab-separated, plain, and `nocheck` bodies were
  ignored. `mbt test` was confirmed compiler-visible but remains intentionally
  outside this plan's semantic fence slice.
- 2026-07-29, Gate A fixture/coordinates: a temporary form of the planned
  `literate.mbt.md` fixture passed `moon check`; hover on
  `literate_answer` returned range `4:4-4:19` and
  `fn literate_answer() -> Int`. Every current conversion matches the ledger:
  local `Position`/`Range` is one-based, `OffsetRange` and the request wire
  offset are zero-based, and `TextSnapshot` owns conversion. The stale
  `HoverProvider` comment was corrected to the one-based contract.
- 2026-07-29, Gate A routing/dependencies: all 83 public `Viewer` methods are
  accounted for above. The root generated interface is expected to remain
  byte-for-byte unchanged. M1 defines only `Code(CodeBrowserData)`; M3 adds the
  real Markdown variant rather than a placeholder payload. DOM-free projection
  remains in `internal/viewer/markdown`, browser ownership remains under
  `internal/viewer/browser/**`, root `viewer` imports the implementation, and
  no reusable package imports `internal/shell`.
- 2026-07-29, Gate A backend refinement: the audited hover and diagnostics
  freshness gaps remain blocking M4 work. The native hover command will drop
  `--no-check`: pre/post disk guards alone cannot prove that cached compiler
  artifacts belong to the supplied snapshot, while ordinary
  `moon ide hover` checks the current disk document before answering. This
  preserves the selected readonly CLI strategy without adding synchronized
  virtual documents or shared shell presentation logic.
- 2026-07-29, Milestone 1: the Code-only presentation seam now owns the active
  root, focus, theme, layout, scroll, render/reveal state, and disposal
  dispatch. Code-only contributions use an explicit Code payload; overlay
  registrations still update Viewer-lifetime state while DOM work is gated on
  an active Code presentation. The generated Viewer interface retained SHA-256
  `0b1ef32ddc28847e96dc826455ac7bb7f26b22942279d6e616e3fa4f1cea7595`.
  `moon test --target js viewer` passed 244 tests and
  `just test-browser-component` passed 75 tests with one opt-in live-network
  case skipped.
