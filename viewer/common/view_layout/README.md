# viewer/common/view_layout

DOM-free scrolling, line/whitespace layout, view zones, and view-line rendering.

## Responsibilities

- `ScrollState` retains raw and validated positions; `Scrollable` owns current
  and future positions plus the cubic smooth-animation state machine.
  `EditorScrollable` normalizes editor content dimensions, while
  `ScrollbarState` contains pure slider geometry and provides a field-for-field
  clone for gesture snapshots. `ViewLayout` is the viewer's single scroll truth:
  it retains the maximum measured rendered-line width, derives content width,
  and feeds horizontal-scrollbar visibility back into the bottom content
  extent. It also computes visible/completely-visible windows and reveal
  positions. Vertical reveal math composes against the future viewport, while
  measured horizontal reveal uses the current viewport like `ViewLines`;
  both accept the source/minimal contract and omit their ordinary padding for
  minimal cursor reveals. Animation scheduling and the clock are injected so
  this package remains DOM/FFI-free.
- Geometry configuration is deliberately reduced to typed setters and fixed
  readonly-product arms: line padding is zero, horizontal scrollbar visibility
  is `Auto`, `scrollBeyondLastLine` and horizontal-scrollbar-height ignoring are
  false, and there is no minimap or overlay-widget minimum-width owner.
  `.view-line-content` measurement already contains the fixed 16px CSS right
  padding, replacing the unavailable `scrollBeyondLastColumn * halfwidth`
  option before `ViewLayout` adds the vertical-scrollbar and whitespace-minimum
  candidates. Wrapped width is the measured maximum because the only source
  threshold adjustment belongs to the absent right-side minimap.
- `set_max_line_width` publishes the width transition before recomputing the
  horizontal-scrollbar contribution to content height. Listeners observe those
  two source-ordered events; the method's local `ScrollChange?` compatibility
  return merges them into one complete old-to-new transition.
- `LinesLayout`, prefix-sum computers, and whitespace accessors map line/view-zone
  heights to vertical offsets. Whitespace height and minimum-width inputs stay
  `Double` until the accessor applies exact JavaScript `ToInt32`, including
  signed zero, non-finite values, and 32-bit wrap. Retained leaf heights remain
  `Int`, while prefix sums, total heights, line-height products, and public
  vertical offsets use `Double` like JavaScript Number; multiple valid Int32
  heights therefore never re-enter 32-bit arithmetic. Source-owned downstream
  `|0` coercion points in searches and viewport entry remain explicit. Pending
  operations commit in cleanup even when a raising callback exits the
  transaction. `ViewLayout`
  exposes that incremental transaction plus ID-bearing whitespace hit,
  viewport, all-data, explicit-scroll-top, and saved-scroll facades. The current
  viewer assumes one uniform view-line height; variable line heights are outside
  the readonly contract.
- `render_view_line*` converts `RenderLineInput` into escaped HTML plus
  `CharacterMapping`/`DomPosition`, preserving the source-to-DOM mapping used by
  hit testing and selections. The input retains Monaco's normalized
  render-space width/glyph identity rather than the raw middot candidates. This
  package also owns decoration normalization and current-line-highlight
  decisions. Renderer output retains Monaco's two foreign-element bits as the
  closed `None`/`Before`/`After`/`BeforeAndAfter` states so lines decorated on
  both sides preserve both geometry facts.
- `ViewportData`, `ViewLineRenderingData`, and ID-based
  `ViewWhitespaceViewportData` live here as dependency-bottom data. Their
  model-dependent factory is
  `view_model.viewport_data_from_view_model`, keeping the dependency one-way.
- ViewZones use only the incremental whitespace transaction and generated-ID
  APIs; the former reduced whole-array adapter and zone indexes are gone.
  Browser DOM mounting and the public mutable delegate live above this package.

The Monaco map is the pinned `src/vs/editor/common/viewLayout/{viewLayout,
linesLayout,viewLinesViewportData,viewLineRenderer}.ts`,
`src/vs/base/common/scrollable.ts`, and the base browser scrollbar state.

This package depends only on `base/common` and the value-only
`viewer/common/editor_api`, declares no FFI, and must not import view-model,
root viewer, browser, server, transport, workspace, or host packages. See
`pkg.generated.mbti`; run
`moon test --target js viewer/common/view_layout`.
