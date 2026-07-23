# internal/viewer/browser/view

The browser-side, per-model editor `View`. This module-private, JS-only MoonBit
package owns the editor DOM subtree, coordinated rendering, the shared row
recycler, and all implemented Monaco view parts. The root `Viewer` owns the
`View` lifetime: there is no `View` without an attached model, and a model swap
disposes and replaces the complete per-model instance. The package does not
import root `viewer`; Viewer-facing composition stays at the root so the
dependency remains one-way.

`View` is `pub`, not `pub(all)`: root code can read the reviewed DOM and
view-part fields recorded in `pkg.generated.mbti`, while construction remains
through the canonical `View(...)` constructor rather than an exposed struct
literal.

The implementation is pinned to the `vscode` submodule at
checked-in source. Files preserve Monaco source-unit
responsibilities inside one MoonBit compilation unit; filenames organize the
code but do not create child packages.

## Ownership and fixed DOM

`View` owns the root section, overflow guard, squiggle-theme style, and each
part's containers. Construction preserves this fixed relative order:

```text
section.monaco-editor
├── style[data-squiggly-theme]
├── div.overflow-guard
│   ├── div.margin
│   │   ├── div.margin-view-zones
│   │   └── div.margin-view-overlays
│   ├── div.monaco-scrollable-element.editor-scrollable
│   │   └── div.lines-content
│   │       ├── div.view-overlays
│   │       ├── div.view-zones
│   │       ├── div.view-lines
│   │       ├── div.contentWidgets
│   │       └── div.cursors-layer
│   └── div.overlayWidgets
├── div.overflowingContentWidgets
└── div.overflowingOverlayWidgets
```

Scrollbar slider nodes are additional children of the scrollbar wrapper. The
`.lines-content` node is the single shared 2^24-pixel scrolling rail retained
by both `EditorScrollbar` and `ViewLines`. Vertical and horizontal scroll
writes move only that rail, keeping text rows, content zones, content
overlays, content widgets, and cursors in one coordinate space. The margin has
its own vertically positioned rail and clipping container.

Caller-owned widget and zone nodes remain owned by their callers. A part may
mount, position, hide, and unmount such a node according to its contract.
ViewZones does not replace a supplied node's class, full style attribute, or
contents; it writes only the required layout properties and marker attributes.

## Event, render, and disposal lifecycle

The closed event-handler index contains eight source-ordered consumers over
the same concrete state:

1. `ViewLines`
2. `ViewZones`
3. content overlays
4. margin overlays
5. `ContentWidgets`
6. `ViewCursors`
7. `OverlayWidgets`
8. `EditorScrollbar`

The ordinary prepare/render index contains the latter seven in the same order.
`ViewLines` is intentionally excluded because Monaco drives it through the
dedicated `renderText` path.

`View::render(ViewContext, ViewRenderInput)` performs one coordinated frame:

1. Read the sticky dirty state accumulated by typed source events.
2. Run every currently dirty ordinary part's `on_before_render` writes against
   one prepared viewport.
3. Render dirty `ViewLines` first so later parts can measure fresh line DOM.
4. Recollect parts dirtied by synchronous width or scroll feedback, then build
   the post-text `RenderingContext` around the same viewport.
5. Run every recollected part's `prepare_render` read/measure phase.
6. Run the DOM-write phase in order and clear each successful part write.

Whole event batches are delivered FIFO through a nested collector. An event
emitted reentrantly becomes a later batch and cannot interleave the handler
pass in progress. Events are emitted at the mutation source, so an A -> B -> A
sequence before a frame is not collapsed into one final-state snapshot. The
closed local union contains only the nine events emitted by the current Viewer
and consumed by current view parts: configuration, cursor state, decorations,
flush, focus, line mapping, scroll, tokens, and zones. Composition and typed
theme events have no readonly producer; concrete theme application remains
direct root/CSS state.

`ViewContext` provides live measurement and conversion capabilities.
`ViewRenderInput` supplies the active `ViewModel`, layout, viewport,
configuration, selection, and zones. `RenderingContext` and
`RestrictedRenderingContext` separate the read/measure and write phases.
Selection geometry consumes live ViewLines ranges. Its package-private range
carriers retain only the rounded coordinates read by current selection and
widget consumers; Monaco's additional mutable/source-shape fields have no
current browser-view consumer.

Disposal is idempotent and source-ordered: dispose `ViewLines`, then the seven
ordinary parts, then the View-lifetime disposable store and dispatcher. The
root `Viewer` removes the root node separately. The scrollbar additionally
owns cancellable asynchronous hide work; controllers and root listeners enter
the View lifetime through `add_disposable`.

The root class builder preserves Monaco's independent platform suffixes:
Safari and native WebKit views use
`no-minimap-shadow enable-user-select`, other browsers use `no-user-select`,
and macOS additionally appends `mac`.

## Shared recycler and overlay rows

`view_layer.mbt` contains the shared `ViewLayerRenderer` used by text lines and
overlay rows. With no old/new window overlap it resets the collection. With an
overlap it preserves reusable rows and applies Monaco's before/after insertion
and removal order. Each update performs at most one batched HTML write for new
rows and one detached batch for invalid rows. Row-specific state remains on
the owning retained row type.

`view_overlays.mbt` owns one retained absolutely positioned row per visible
view line. It concatenates registered overlay HTML in registration order and
rewrites a row only when the concatenated content changes.

## Content widgets

`ContentWidgets` implements the generic content-widget layer; concrete hover
widgets remain in `internal/viewer/contrib/hover/browser`.

- `ContentWidgetHandle` retains live id, DOM-node, and position getters;
  `allowEditorOverflow` and `useDisplayNone`; and independently optional
  before/after-render callbacks. Safe callback helpers preserve exception
  fallbacks and argument order. Content-widget mouse suppression is absent
  because no current pointer-input consumer queries it.
- `add_widget` mounts a node once in `.contentWidgets` or
  `.overflowingContentWidgets`, where it remains for the owning View lifetime;
  disposing the View removes the complete subtree. `set_widget_position`
  retains model anchors, projects them through the live model-to-view
  converter, and invalidates cached dimensions. Line-mapping events
  synchronously reproject those anchors; flush and mapping invalidation mark
  the part dirty.
- A `LayoutInfo` change refreshes retained `contentLeft`, `contentWidth`, and
  `maxWidth` values. The pre-text phase completes the max-width writes; the
  later measured phase rounds dimensions and runs source-ordered two-pass
  placement. Rendering gates visibility writes, parks a focused off-viewport
  widget at `top:-1000px`, and reports the selected coordinate safely.
- Every outer phase snapshots insertion-ordered widget ids before live map
  lookup, matching `Object.keys(_widgets)`. Reentrant additions wait for the
  next phase and cannot change the traversal already in progress.
- Overflow width and explicit page-layout scroll subtraction use each node's
  `ownerDocument` and `defaultView`, with zero fallbacks for a detached
  document. The external page-position helper instead falls back to the main
  window when the owner is detached. Client-area lookup preserves the iOS
  `visualViewport` preference and returns a detached body's own client box.

Supplied widget nodes remain raw Rabbita elements, so style writes do not
claim Monaco `FastDomNode`'s per-property cache. Lifecycle equality and dirty
gates still preserve source write order and values. External overflow hosting,
fixed overflow widgets, and the editor-level `allowOverflow` option remain
explicit seams. The generic affinity handoff is complete; hover's
`shouldAppearBeforeContent` producer is a separate deferred seam.

## Content and margin overlays

The content overlays register in this paint order:

1. current-line highlight
2. selections
3. decorations

The content and margin current-line units apply Monaco's focus, selection,
wrapping, canonical `editor_api.RenderLineHighlight`, and
`RenderLineHighlightOnlyWhenFocus` predicates. `current_line_span` expands a
wrapped model line to its view-line span. The content highlight is below
selections and decorations; the margin highlight is first in the implemented
margin order.

Selections consume live ordered rectangles from
`RenderingContext.lines_visible_ranges_for_range(..., true)`, round the
per-line geometry, and preserve rounded and reverse-corner styling. The pure
measurement-driven entrypoint remains the focused-test oracle.

Decorations filter and sort viewport decorations, emit whole-line pieces,
merge touching ranges with the same class, preserve `showIfCollapsed`, and
expand `shouldFillLineOnLineBreak`. Inline geometry comes from live line
measurement before each visible line is serialized.

The implemented margin overlay order is current-line margin, line decorations,
then line numbers. Line-decoration lane classes are deduplicated. Readonly
`lineNumbers: 'on'` renders a model line number only on that model line's first
view line. Glyph-margin rendering and relative, interval, and custom
line-number modes are not implemented.

## Scrollbar and overlay widgets

`EditorScrollbar` is the thin ViewPart wrapper around
`internal/viewer/ui/scrollbar.ScrollableElementDom`. It exposes the wrapper,
shared content node, and scrollable object needed by `View` and the root input
bridge. Scrollbar DOM, slider arithmetic, reveal/fade, wheel normalization, and
drag geometry remain owned by `internal/viewer/ui/scrollbar`; model scroll
state remains in `viewer/common/view_layout`.

`OverlayWidgets` owns fixed `.overlayWidgets` and
`.overflowingOverlayWidgets` containers plus the id-to-DOM registry.
Adding an id mounts or replaces a self-positioning node; removing the id
unmounts it. The root `Viewer` retains registrations across model swaps and
re-adds them to the replacement View. This is Monaco's null-position subset,
so prepare/render are no-ops; preference-based placement and
`layoutOverlayWidget` remain deferred.

## Cursors

`ViewCursors` implements the readonly single-cursor subset. It owns the
`.cursors-layer` and one cursor node. Placement and
`compute_screen_aware_size` preserve device-pixel-ratio-aware caret width, and
the last rendered box remains available to browser hit testing. The caret is
painted only while the editor is focused; selection state changes the layer
class. Multi-cursor rendering and Monaco's blink interval and cursor-style
machinery remain deferred.

## View lines and geometry

`ViewLines` retains one `ViewLine` for each member of the current half-open
`LineWindow` and reconciles them through `ViewLayerRenderer`. New rows share
one HTML batch, invalid rows share one detached batch, and equal render input
skips replacement. Every retained line keeps the common renderer's
`CharacterMapping` for DOM hit testing and live selection/decorations
measurement.

The retained slow `RenderedViewLine` strategy owns DOM-width and per-column
pixel caches, truncation guards, whitespace and foreign-element facts, and
`RangeUtil` visible-range reads. The normal factory selects this strategy;
the approved WebKit and fast-renderer branches remain deferred.

After reconciliation, ViewLines applies layer hinting, `contain: strict`, and
the sole scroll top/left writes to the shared `.lines-content` rail. Retained
row layout uses cached top, height, and line-height writes. A cancel/reschedule
200 ms job completes slow width sweeps when the fast pass encounters an
uncached row; the measured maximum feeds `ViewLayout` with Monaco's ceil and
monotonic rules.

`DomReadingContext` shares layout reads within a frame. `RangeUtil` reuses and
parks one DOM Range and creates ranges from the first measured start node's
`ownerDocument`, which keeps document-local fixtures independent of a global
Range binding. Installed geometry readers supply view-to-model line conversion
and model text direction for multi-line `includeNewLines` queries. The current
ViewModel supplies LTR rendering data, while the capability remains ready for
a real direction producer. Rendered rows retain the `data-line` attribute used
by browser conformance tests.

`View::render` invokes `render_text` directly before ordinary parts; the
ordinary ViewPart prepare/render path is unsupported for ViewLines. Optional
GPU range fallback, concatenation, and sorting remain deferred with a future
GPU renderer.

## View zones

`viewer/browser.ViewZone` is the mutable public descriptor retained by identity.
Its live fields are reread during layout. Its
opaque callback-backed `ViewZoneChangeAccessor` adds a descriptor and returns a
generated whitespace id, removes a registration, or requests a mapping/height
reread through `layout_zone`. This package converts once at that boundary and
keeps all registered/runtime state. `ViewZones`
computes hidden-area and height facts, mounts caller-owned content and margin
nodes without replacing their class/style/content, reports host callback
failures safely, and renders id-bearing viewport whitespace with Monaco's
visibility, offscreen, and width rules.

Hidden-area precedence is explicit: `show_in_hidden_areas=true` always wins;
otherwise `ignore_hidden_area_source=Some(source)` tests the declared anchor
against every other source; omission keeps the Monaco-compatible merged
position-after-zone test. The source-excluding read never mutates the merged
hidden-area projection.

The `.margin-view-zones` child sits below the retained `.margin` clipping
container and receives the `bigNumbersDelta - scrollTop` parent offset.
Individual margin-zone nodes receive the same top, height, and display writes
as their content peers.

The public host seam is `Viewer::change_view_zones`. The root handles the
constructor/model guard, completes changed-only internal delivery before the
outgoing event, and schedules a render unconditionally; per-model zone
registration and teardown stay with `ViewZones`.

## Source-unit map

| Local source units | Pinned Monaco ownership |
|---|---|
| `view.mbt`, `view_context.mbt`, `view_events.mbt`, `view_event_dispatcher.mbt`, `view_lifecycle_handles.mbt`, `view_lines_zones_lifecycle.mbt`, `view_overlays_lifecycle.mbt`, `view_widgets_cursors_lifecycle.mbt` | `editor/browser/view.ts` and its View event/lifecycle collaborators |
| `rendering_context.mbt` | `editor/browser/view/renderingContext.ts` |
| `view_part.mbt` | `editor/browser/view/viewPart.ts` |
| `view_user_input_events.mbt` | `editor/browser/view/viewUserInputEvents.ts` |
| `view_layer.mbt` | `editor/browser/view/viewLayer.ts` |
| `view_overlays.mbt`, `margin.mbt` | `editor/browser/view/{dynamicViewOverlay,viewOverlays}.ts` and `viewParts/margin/margin.ts` |
| `selection_measure.mbt` | `View.getOffsetForColumn` and ViewLines visible-range geometry |
| `squiggly_theme.mbt` | the local DOM bridge for Monaco's marker theming participant |
| `content_widgets.mbt` | `viewParts/contentWidgets/contentWidgets.ts` plus `IContentWidget` contracts in `editorBrowser.ts` |
| `current_line_highlight.mbt`, `current_line_margin_highlight.mbt` | `viewParts/currentLineHighlight/currentLineHighlight.ts` |
| `decorations.mbt` | `viewParts/decorations/decorations.ts` |
| `editor_scrollbar.mbt` | `viewParts/editorScrollbar/editorScrollbar.ts` |
| `line_numbers.mbt`, `lines_decorations.mbt` | `viewParts/lineNumbers/lineNumbers.ts` and `viewParts/linesDecorations/linesDecorations.ts` |
| `overlay_widgets.mbt` | `viewParts/overlayWidgets/overlayWidgets.ts` |
| `selections.mbt` | `viewParts/selections/selections.ts` |
| `view_cursors.mbt` | `viewParts/viewCursors/viewCursors.ts` |
| `view_lines.mbt`, `view_line.mbt`, `dom_reading_context.mbt`, `range_util.mbt` | `viewParts/viewLines/{viewLines,viewLine,domReadingContext,rangeUtil}.ts` |
| `view_zones.mbt` | `viewParts/viewZones/viewZones.ts` |

CSS stays at its established asset paths so the assembly order and emitted
provenance remain byte-for-byte stable. The
`viewer/browser/view_parts/*` directories and `viewer/browser/view` are asset
locations, not MoonBit packages. Root editor CSS and the codicon font remain
under the stable `viewer/browser/view` asset directory.

## Tests

Focused package tests cover:

- event dispatch, user-input mapping, root classes, and lifecycle ordering;
- recycler retention, line DOM, mappings, reusable Range geometry, and width
  scheduling;
- content widgets, rendering contexts, decorations, whitespace, and selection
  overlays;
- cursor rendering and both ViewZones geometry and branch matrices;
- part fingerprints and DOM hit-test contracts.

Run the complete package suite with:

```sh
moon test internal/viewer/browser/view --target js -v
```

The structural validation set is:

```sh
moon check --target all
just check
just test
just build
just test-browser
```

Exact public API and dependency summaries are generated in
`pkg.generated.mbti` and declared in `moon.pkg`.
