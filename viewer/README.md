# viewer

The reusable readonly editor facade. It plays Monaco's
`CodeEditorWidget`/`ICodeEditor` role over the packages below it; the reference
workbench, transport, files, and reload policy live under `internal/shell/`.
`pkg.generated.mbti` is the authoritative public API. This README records the
ownership and lifecycle rules that are not obvious from signatures.

## Construction and ownership

- Browser embedders call `Viewer::create(host, services~, options~)`. The host
  element must stay mounted and must not receive host-rendered children.
  This is the only public construction path. The package keeps a private
  headless constructor for white-box tests; there is no public two-step mounting
  API. Construction synchronously reads the host's `clientWidth`/
  `clientHeight` (clamped to Monaco's 5px minimum), so options, model attachment,
  and model-line projection use the measured viewport. The internal ViewLayout
  is seeded synchronously before it becomes observable or publishes stable
  visible-token demand. Later `layout()` calls use the same client-box
  semantics, including while the no-model placeholder is showing. Headless
  means no host, placeholder, browser `View`, DOM focus state, measurement, or
  root animation frame, although a model and `ViewModel` may still be installed
  with `ModelData.browser=None`; a model installed through the public mounted
  path always has `Some(ModelBrowserData)`.
- Mounting is a one-way private transition. A mounted Viewer with no model owns
  one atomic placeholder root/text pair; attaching a model replaces that DOM
  with its `View`, and ordinary detach restores the same pair. Disposal removes
  Viewer-owned DOM and clears placeholder/frame/focus state without returning
  to headless or releasing the caller's host. `get_container_dom_node` returns
  that original host before and after disposal, while `get_dom_node` is nullable
  when no model/browser View exists.
- Omitting `services` makes the Viewer create and own an internal bundle.
  Passing `services` explicitly always borrows that bundle, including a bundle
  returned by `ViewerServices(...)`; this is the form for sharing languages,
  diagnostics, feedback, and quick-diff state between Viewers.
- `set_model(TextModel?)` installs a caller-owned readonly model in the one
  `ViewerModelSlot.current` bundle. The same object is a no-op; replacement or
  clearing invalidates the generation before cleanup, then disposes the old
  model-scoped listeners, exact model-owned attached-view handle, optional DOM
  `View`, and `ViewModel` in order. Attachment acquires the handle before
  `ViewModel` construction and, when mounted, creates one `ModelBrowserData`
  that cannot hold a `View` without its retained mouse handler and render/reveal
  facts. The `View` remains the handler's sole disposal owner. Model swaps reset
  scroll and feature model state; use `save_view_state`/`restore_view_state`
  when the host wants persistence.
- Contributions are created once per `Viewer` and disposed with it.
  `Viewer.contributions` is the `EditorContributions` owner, and its `instances`
  map is the only per-Viewer instance store. Each central entry owns one
  concrete hover, folding, feedback-input, feedback-widget, quick-diff, or
  Markdown-comment state value plus its root listeners; feature packages keep
  no editor-id-keyed instance table. The content-hover payload additionally
  owns its controller, lazy widget and logical widget view, and timeout/async
  launch policy across model swaps. The Markdown-comment payload owns its
  model/content subscriptions and the current model's stable-key rendered-zone
  map. Construction rejects duplicate ids before side effects, inserts the bare
  typed entry before synchronous initialization, and then installs listeners.
  All modes currently instantiate eagerly.
- `dispose` is idempotent. The complete contribution map remains installed for
  ordered behavior teardown, then becomes non-lookuppable; retained hover
  browser resources are released at the later root cleanup slot before the map
  is cleared. `on_did_dispose` fires after model detach and owner-decoration
  cleanup but before those contribution and Viewer-lifetime phases, while every
  central entry is still reachable. Disposal cancels pending render work and
  pending per-model smooth-scroll registrations, removes Viewer/View listeners
  and owned DOM, and never disposes the caller's model, host, or explicitly
  supplied services. An internally created service bundle is released
  afterward in marker-decoration, marker, then feedback order.
- Each attached model stores one marker-decoration acquisition lease and one
  exact attached-view handle in its `ModelData`. Multiple Viewers sharing a
  service and model share the identity owner until the final lease and maintain
  an aggregate attached count; `set_value` refreshes that owner without
  acquiring again. Model-scoped listeners dispose before model detachment, the
  View disposes next, and the ViewModel disposes last.
- Overlay-widget registrations belong to the Viewer and are re-added to each
  per-model View. Content widgets are an internal view-part seam; hover owns
  the current implementation.

## Public surface

The API is a readonly subset of Monaco's editor API:

- lifecycle/model/options: `create`, `set_model`, `handle_initialized`,
  `update_options`, `layout`, `focus`, `dispose`;
- position, selection, scroll, reveal, geometry, and read queries;
- model decorations and `EditorDecorationsCollection`;
- view zones and null-position overlay widgets;
- model, cursor, scroll, ViewZone, hidden-area, mouse, and disposal events.

Canonical public event values and editor-option enums are owned by
`viewer/common/editor_api`; the root facade consumes those types directly and
does not provide compatibility aliases.

`update_options` accepts and replaces one complete typed `ViewerOptions`
snapshot. It is intentionally not Monaco's JavaScript partial-object merge:
the representation is opaque, and callers changing one field derive a new
snapshot with a reviewed builder such as
`viewer.get_options().with_render_whitespace(All)`. The public read floor is
limited to `soft_wrap()` and `line_height()`; internal packages derive the rest.
An equal complete snapshot is a strict no-op. A changed snapshot computes
option-specific facts once and delivers the resulting mapping, decoration, and
configuration view events as one ordered batch before scheduling the frame.
The readonly product keeps its approved
`render_validation_decorations=On` default; `Editable` still filters validation
decorations because readonly is a fixed product fact.

The viewer is single-cursor: secondary cursor/selection arrays are empty and
`set_selections` uses the first selection. The primary Left/Right/Up/Down,
PageUp/PageDown, Home, and End bindings (with Shift variants) move the cursor;
a winning binding remains handled at a document boundary. Pointer click/drag,
word, line, gutter, and select-all gestures use source-shaped command objects
registered under their source IDs and the same transition path. Their
runtime-partial argument shapes return before mutation when required
position/selection data is absent; the readonly model has no undo stack, so
Monaco's cursor-command `pushStackElement` calls have no local state to update.
Alternate platform bindings, editable commands, multi-cursor, and column
selection are outside the readonly surface. Build/render/hover telemetry and
the disabled-by-default scroll state/render-phase trace are not part of the
public Viewer API; the internal workbench and browser scenarios use the
Viewer-id-keyed `internal/viewer/browser/testing` seam.

Cursor payload versions are `TextModel.get_version_id()`, never the caller's
host metadata version. `set_position`/`set_selection` accept an optional
source, while `set_selections` accepts optional source and reason; their
defaults are `api`/`NotSet`. Keyboard and ordinary pointer gestures emit
`keyboard` or `mouse` with `Explicit`;
four-click SelectAll deliberately keeps source `keyboard`. `set_value` resets
the cursor to `(1,1)` and emits source `model`/reason `ContentFlush`, old version
`0`, and `old_selections=None`, even when the visible cursor was already at the
origin. State is committed and rendering is scheduled before public cursor
callbacks. Delivery is FIFO and reentrancy-safe: ordinary transitions fire
position then selection as an adjacent pair, while flush delivery is model
content, position, then selection. The private `CursorEventDelivery` owns the
queue, active drain gate, exact content-barrier depth, and completed versions.
A model reset clears queued model facts and versions but never clears an active
outer drain gate; active-model checks and public event effects remain at the
root Viewer boundary.

`on_did_change_hidden_areas` is the public, payload-free notification for the
current model's changed view-line mapping. The root subscribes to the
ViewModel's heterogeneous outgoing dispatcher through the model-scoped
generation gate, so a detached model, a missing model, and callbacks retired by
replacement or disposal cannot reach the Viewer emitter. The event fires once
after the hidden-area transaction has delivered its internal mapping,
cursor/decorations, layout, and stable-viewport recovery facts. Equal ranges
and a forced update that leaves the mapping equal do not fire. Applying hidden
areas remains package-private root/contribution behavior rather than a public
Viewer mutation API.

On a mounted Viewer, the Markdown-comment contribution resolves whole-line
blocks from the first matching provider or the language's comment
configuration, then replaces those lines only in the view projection with
measured ViewZones. The model value, coordinates, tokens, selection, and code
copy remain source truth. Each stable range key retains one DOM target while a
body-only change replaces its shared safe-renderer lifetime; same-model content
flushes force the hidden-source projection refresh even when the normalized
ranges stay equal. Model detach disposes renderers and size observers, removes
zones, and clears the feature's one hidden source before the outgoing browser
`View` is destroyed. A headless Viewer never hides these source lines because
it has no replacement DOM. Offscreen zones measure invisibly at the editor
content width, so scroll geometry converges before first reveal and responds to
width/image changes without exposing hidden content. The feature enables only
sanitized HTTP(S) images and routes sanitized links through its external action
handler; raw HTML and unsafe schemes stay inert under the shared renderer
policy.

Cursor-command reveals keep the committed view coordinate. Keyboard commands
request non-minimal Smooth reveal; pointer MoveTo/Word/Line commands use the
same Smooth request with `minimalReveal=true` after their `None` gate, so a
target already at the viewport edge gains no extra vertical or horizontal
padding. Smooth requests of at most one line downgrade to immediate, and the
`smooth_scrolling=false` default also commits them immediately.

`ViewerServices` is an opaque capability aggregate. Its constructor accepts a
`LanguageHandle`, one closed marker source (`MarkerStore` or `Decorations`), an
`AgentFeedbackHandle`, a `QuickDiffHandle`, and a `LogHandle`; concrete service
fields cannot be recovered through the facade. Hosts retain concrete language,
marker, feedback, quick-diff, and logging backings when they need to register
providers, publish diagnostics, mutate feature state, or inspect telemetry.
Omitted capabilities create bundle-owned defaults. `ViewerServices::dispose`
is idempotent and releases only those defaults, in marker-decoration,
marker-store, then feedback order; supplied handles and captured backings remain
caller-owned. A Viewer disposes only a bundle it created implicitly. There is
no current viewer UI for definition or references.

## Runtime pipeline

```text
TextModel (caller-owned)
  -> TokenizationTextModelPart
  -> ViewModel + ViewLayout + cursor outgoing dispatcher (per model)
  -> typed ViewEvent FIFO -> View + ViewParts (per model, browser only)
  -> shared animation-frame queue -> read/measure then DOM write
```

`base/browser` owns the one realm-global frame coordinator. ViewModel smooth
scroll and controller touch inertia use its strict-next queue; a mounted Viewer
uses current-or-next priority `100` for its coalesced render. Therefore an
animation tick can commit state and append that Viewer render to the same
native frame, while strict-next animation state still advances only once per
frame. Multiple Viewers share the native request and priority queue but retain
independent dirty flags, callbacks, trace ids, and cancellation lifetimes. This
is private composition and leaves `viewer/pkg.generated.mbti` unchanged; it is
not Monaco's cross-editor phased `EditorRenderingCoordinator` port.

The root package owns every `Viewer::` method and the cross-package glue for
input, reveal, widgets, folding, hover, Markdown comments, quick diff,
feedback, and decorations. Public values remain in `viewer/common/**` and
`viewer/browser`;
concrete browser and contribution mechanisms live in
`internal/viewer/browser/**` and `internal/viewer/contrib/**`. Those
lower-level packages do not import the root facade, so Viewer-facing
composition stays here without reversing dependencies. Each hover request
captures the physical `TextModel`, its internal content version, a
Viewer-lifetime monotonic generation, and a caller-owned cancellation token.
Replacement, content invalidation, detach, model disposal, and Viewer disposal
cancel before retiring the request; only a stamp that is still fully current
may mutate decorations, hover state, rendering, or resolution events. Hover
mouse/async/sync/loading delays are clearable owned handles with a generation
guard retained for dispatch races.

Grammar tokenization is demand-driven. Model attach/build telemetry and token
change telemetry read the passive store only; `_attachModel` does not own
Monaco's separate `handleInitialized` transition. ViewModel scroll/content
changes publish unstable visible ranges. After `set_model` and any synchronous
view-state restore or option update, the host calls `handle_initialized`; that
separate boundary publishes the current model's stabilized visible demand
without waiting for a render frame. Repeated calls re-stabilize that demand and
can immediately supersede a pending unstable-range debounce.
`restore_view_state(Some(...))` also publishes a stabilized range after the
restored scroll is committed. Model attachment alone, including headless
attachment, publishes no synthetic zero-viewport stable range. This behavior
port does not claim full constructor
arithmetic parity: real DOM `FontInfo` replaces the initial estimate in the
first mounted read phase, and wrap-column computation retains the documented
local reduced formula. The browser scheduler selects one native-idle or 15 ms
timeout fallback implementation, exposes cancellable idle/zero/delay handles,
and lets the model backend bound and cancel background work. The root consumes
the ViewModel's typed outgoing token event only after the browser ViewEvent has
been delivered; it does not subscribe directly to TextModel token events.

## Boundaries and checks

- JS-only: DOM access is through `rabbita/dom`/`rabbita/js`; no Rabbita
  TEA/vdom/command layer, `internal/shell/**`, backend transport, or concrete
  `syntax/lang_*` import belongs here.
- DOM-free logic belongs in `viewer/common/**` or a multi-target contribution.
  The browser renders typed state directly; do not pass render-frame JSON to
  JavaScript.
- Owner-adjacent CSS is assembled by `scripts/build-web.mbtx`.
- Use `just test` for headless/model behavior, `just test-browser` for real DOM
  input and geometry, and `just check` for architecture boundaries.
