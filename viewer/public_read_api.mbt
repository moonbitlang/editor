///|
/// Read-only state-query surface, Monaco's `CodeEditorWidget` getter cluster
/// (`vs/editor/browser/widget/codeEditor/codeEditorWidget.ts`). These answer
/// "where is the viewport / where does this model position land / what is
/// selected", complementing the write-heavy `reveal_*` / `scroll_*` / `set_model`
/// surface. Each getter delegates to the backing piece the viewer already owns
/// (`ViewModel` / `ViewLayout` / `View`) and copies Monaco's no-model sentinel
/// (`''` / `[]` / `null` / `-1` / raw-column) verbatim — callers branch on them.
///
/// Public API is *model*-coordinate in/out; every vertical-offset and
/// visible-range path converts at the boundary through the `CoordinatesConverter`
/// before touching `ViewLayout`, never reaching layout with a model line number.

///|
/// Monaco's `Number.MAX_SAFE_INTEGER` column for `getBottomForLineNumber`: a
/// column past any line end, clamped down to the line's max column by
/// `validate_position`.
let max_safe_column : Int = 2147483647

///|
/// Full document text, Monaco's `CodeEditorWidget.getValue` (`cew:472`). No
/// model → `''`. The `{preserveBOM, lineEnding}` option is dropped: the snapshot
/// stores fixed-LF text, retains U+FEFF as ordinary content, and exposes no
/// separate BOM metadata or EOL preference/preservation switch.
pub fn Viewer::get_value(self : Viewer) -> String {
  match self.get_model() {
    None => ""
    Some(model) => model.get_value()
  }
}

///|
/// Model ranges currently fully visible on screen, Monaco's
/// `CodeEditorWidget.getVisibleRanges` (`cew:563`) → `viewModel.getVisibleRanges`
/// (`vmi:646`): the completely-visible *view* range (from the layout) converted
/// to model ranges, split around any hidden region. No model → `[]`.
pub fn Viewer::get_visible_ranges(self : Viewer) -> Array[@base_common.Range] {
  guard self.get_view_model() is Some(view_model) else { return [] }
  let (start_view_line, end_view_line) = view_model.view_layout.completely_visible_line_range()
  view_model.to_model_visible_ranges({
    start_line_number: start_view_line,
    start_column: view_model.get_line_min_column(start_view_line),
    end_line_number: end_view_line,
    end_column: view_model.get_line_max_column(end_view_line),
  })
}

///|
/// Visible model ranges padded by a viewport's worth of lines above and below,
/// Monaco's `getVisibleRangesPlusViewportAboveBelow` (`cew:570`) →
/// `viewModel.getVisibleRangesPlusViewportAboveBelow` (`vmi:632`):
/// `linesAround = max(20, round(height / lineHeight))`, the completely-visible
/// view range grown by `linesAround` and clamped to `[1, lineCount]`, then split.
/// No model → `[]`.
fn Viewer::get_visible_ranges_plus_viewport_above_below(
  self : Viewer,
) -> Array[@base_common.Range] {
  guard self.get_view_model() is Some(view_model) else { return [] }
  let line_height = self.configuration.snapshot().font_info.line_height.to_double()
  let height = view_model.view_layout.dimensions().height
  // `Math.round` of a non-negative ratio is `floor(x + 0.5)`.
  let rounded = (height / line_height + 0.5).to_int()
  let lines_around = if rounded > 20 { rounded } else { 20 }
  let (completely_start, completely_end) = view_model.view_layout.completely_visible_line_range()
  let start_view_line = @base_common.clamp_int(
    completely_start - lines_around,
    1,
    view_model.line_count(),
  )
  let end_view_line = @base_common.clamp_int(
    completely_end + lines_around,
    start_view_line,
    view_model.line_count(),
  )
  view_model.to_model_visible_ranges({
    start_line_number: start_view_line,
    start_column: view_model.get_line_min_column(start_view_line),
    end_line_number: end_view_line,
    end_column: view_model.get_line_max_column(end_view_line),
  })
}

///|
/// Content-space top of a 1-based model line, Monaco's `getTopForLineNumber`
/// (`cew:593`). No model → `-1`.
pub fn Viewer::get_top_for_line_number(
  self : Viewer,
  line_number : Int,
  include_view_zones? : Bool = false,
) -> Double {
  self.get_vertical_offset_for_position(line_number, 1, include_view_zones~)
}

///|
/// Content-space top of a 1-based model position, Monaco's `getTopForPosition`
/// (`cew:600`) — always excludes the view zone directly above the line. No model
/// → `-1`.
pub fn Viewer::get_top_for_position(
  self : Viewer,
  line_number : Int,
  column : Int,
) -> Double {
  self.get_vertical_offset_for_position(
    line_number,
    column,
    include_view_zones=false,
  )
}

///|
/// Content-space bottom of a 1-based model line, Monaco's
/// `getBottomForLineNumber` (`cew:616`): the offset after the line, computed at
/// the line's max column (`Number.MAX_SAFE_INTEGER`, validated down). No model →
/// `-1`.
pub fn Viewer::get_bottom_for_line_number(
  self : Viewer,
  line_number : Int,
) -> Double {
  self.get_vertical_offset_after_position(
    line_number,
    max_safe_column,
    include_view_zones=false,
  )
}

///|
/// Pixel height of a 1-based model position's line, Monaco's
/// `getLineHeightForPosition` (`cew:623`). No model → `-1`; a position inside a
/// hidden region → `0`; otherwise the configured uniform line height.
/// Like Monaco the raw position is not validated before the visibility test.
pub fn Viewer::get_line_height_for_position(
  self : Viewer,
  position : @base_common.Position,
) -> Double {
  guard (self.get_model(), self.get_view_model()) is (Some(_), Some(view_model)) else {
    return -1.0
  }
  if view_model.model_position_is_visible(position) {
    let view_position = view_model
      .coordinates_converter()
      .model_position_to_view_position(position)
    view_model.view_layout
    .get_line_height_for_line_number(view_position.line_number)
    .to_double()
  } else {
    0.0
  }
}

///|
/// 1-based visible column of a model position (tabs expand to tab stops,
/// full-width/emoji count as two), Monaco's `getVisibleColumnFromPosition`
/// (`cew:641`): `visibleColumnFromColumn(...) + 1`. No model → the raw input
/// column (the load-bearing no-model sentinel, not `-1`).
pub fn Viewer::get_visible_column_from_position(
  self : Viewer,
  position : @base_common.Position,
) -> Int {
  guard self.get_model() is Some(model) else { return position.column }
  let position = model.validate_position(position)
  let tab_size = self.configuration.snapshot().options.tab_size
  @core.visible_column_from_column(
    model.get_line_content(position.line_number),
    position.column,
    tab_size,
  ) +
  1
}

///|
/// 1-based "Col" value for a status bar (tabs snap to tab stops, code points),
/// Monaco's `getStatusbarColumn` (`cew:652`). No model → the raw input column.
fn Viewer::get_statusbar_column(
  self : Viewer,
  position : @base_common.Position,
) -> Int {
  guard self.get_model() is Some(model) else { return position.column }
  let position = model.validate_position(position)
  let tab_size = self.configuration.snapshot().options.tab_size
  @core.to_statusbar_column(
    model.get_line_content(position.line_number),
    position.column,
    tab_size,
  )
}

///|
/// Package-private geometry helpers are exercised only by root white-box
/// tests; anchor them in the ordinary library build without reopening the
/// public facade.
let _public_read_geometry_test_seams_anchor : Unit = ignore(
  (
    Viewer::get_visible_ranges_plus_viewport_above_below,
    Viewer::get_statusbar_column,
  ),
)

///|
/// The primary cursor's model position, Monaco's `getPosition` (`cew:663`) →
/// `viewModel.getPosition`. No model → `null`; the view model's cursor always
/// exists, starting collapsed at `(1,1)` like Monaco's.
pub fn Viewer::get_position(self : Viewer) -> @base_common.Position? {
  guard self.get_view_model() is Some(view_model) else { return None }
  Some(view_model.cursor.model_state().position)
}

///|
/// The primary cursor's model selection, Monaco's `getSelection` (`cew:783`) →
/// `viewModel.getSelection`. No model → `null`.
pub fn Viewer::get_selection(self : Viewer) -> @core.Selection? {
  guard self.get_view_model() is Some(view_model) else { return None }
  Some(view_model.cursor.get_model_selection())
}

///|
/// All cursor model selections, Monaco's `getSelections` (`cew:790`). The viewer
/// is single-selection, so this is a 1-element array (a documented prior scope
/// cut). No model → `null`.
pub fn Viewer::get_selections(self : Viewer) -> Array[@core.Selection]? {
  match self.get_selection() {
    Some(selection) => Some([selection])
    None => None
  }
}

///|
/// Widest content width (horizontal scroll extent before viewport clamping),
/// Monaco's `getContentWidth` (`cew:963`). No model → `-1`.
pub fn Viewer::get_content_width(self : Viewer) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  view_model.view_layout.get_content_width()
}

///|
/// Scrollable content width = `max(viewport width, content width)`, Monaco's
/// `getScrollWidth` (`cew:970`). No model → `-1`.
pub fn Viewer::get_scroll_width(self : Viewer) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  view_model.view_layout.get_scroll_width()
}

///|
/// Current horizontal scroll offset, Monaco's `getScrollLeft` (`cew:976`). No
/// model → `-1`.
pub fn Viewer::get_scroll_left(self : Viewer) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  view_model.view_layout.get_current_scroll_left()
}

///|
/// Total content height including view zones, Monaco's `getContentHeight`
/// (`cew:983`). No model → `-1`.
pub fn Viewer::get_content_height(self : Viewer) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  view_model.view_layout.get_content_height()
}

///|
/// Scrollable content height = `max(viewport height, content height)`, Monaco's
/// `getScrollHeight` (`cew:990`). No model → `-1`.
pub fn Viewer::get_scroll_height(self : Viewer) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  view_model.view_layout.get_scroll_height()
}

///|
/// Current vertical scroll offset, Monaco's `getScrollTop` (`cew:996`). No model
/// → `-1`.
pub fn Viewer::get_scroll_top(self : Viewer) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  view_model.view_layout.get_current_scroll_top()
}

///|
/// Validates a model position and converts it to a view position, the shared
/// front half of Monaco's `_getVerticalOffsetForPosition` /
/// `_getVerticalOffsetAfterPosition` (`cew:607` / `cew:584`). `None` when there
/// is no model (the no-model sentinel boundary).
fn Viewer::model_to_view_position(
  self : Viewer,
  line_number : Int,
  column : Int,
) -> @base_common.Position? {
  guard (self.get_model(), self.get_view_model())
    is (Some(model), Some(view_model)) else {
    return None
  }
  let model_position = model.validate_position(Position(line_number, column))
  Some(
    view_model
    .coordinates_converter()
    .model_position_to_view_position(model_position),
  )
}

///|
/// Monaco's `CodeEditorWidget._getVerticalOffsetForPosition` (`cew:607`):
/// validate → convert to view position → `viewLayout.getVerticalOffsetForLineNumber`.
/// No model → `-1`.
fn Viewer::get_vertical_offset_for_position(
  self : Viewer,
  line_number : Int,
  column : Int,
  include_view_zones~ : Bool,
) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  match self.model_to_view_position(line_number, column) {
    Some(view_position) =>
      view_model.view_layout.get_vertical_offset_for_line_number(
        view_position.line_number,
        include_view_zones~,
      )
    None => -1.0
  }
}

///|
/// Monaco's `CodeEditorWidget._getVerticalOffsetAfterPosition` (`cew:584`):
/// validate → convert → `viewLayout.getVerticalOffsetAfterLineNumber`. No model
/// → `-1`.
fn Viewer::get_vertical_offset_after_position(
  self : Viewer,
  line_number : Int,
  column : Int,
  include_view_zones~ : Bool,
) -> Double {
  guard self.get_view_model() is Some(view_model) else { return -1.0 }
  match self.model_to_view_position(line_number, column) {
    Some(view_position) =>
      view_model.view_layout.get_vertical_offset_after_line_number(
        view_position.line_number,
        include_view_zones~,
      )
    None => -1.0
  }
}

// --- DOM-measured read API (Monaco's `hasRealView`-gated getters) ------------
//
// These read real client rects, so they need the target line rendered. The
// `hasRealView` gate collapses to "model + view attached"; an off-screen line
// (not in the rendered window) measures to `-1`/`null`, mirroring Monaco's
// `visibleRangeForPosition` → `null`. They flush any pending render first, the
// analog of Monaco's `_flushAccumulatedAndRenderNow`.

///|
/// Reduced editor layout info, Monaco's `CodeEditorWidget.getLayoutInfo`
/// (`cew:1472`); the shape lives in `viewer/common/config/editor_options.mbt`.
/// Backed by the viewer's measured gutter width and content box;
/// `content_left` is the full margin (line numbers plus the line-decorations
/// lane; the glyph-margin terms are `0`). Like Monaco this does not gate on a
/// model.
pub fn Viewer::get_layout_info(self : Viewer) -> @config.EditorLayoutInfo {
  let model_line_count = match self.get_model() {
    Some(model) => model.snapshot.line_count()
    // EditorConfiguration retains its one-digit model environment before any
    // model is attached; `digit_count(0)` supplies the same minimum band.
    None => 0
  }
  self.configuration.snapshot().layout_info(model_line_count)
}

///|
/// Horizontal pixel offset of a model position on its rendered line, Monaco's
/// `getOffsetForColumn` (`cew:1687`) → `view.getOffsetForColumn`. No real view →
/// `-1`; line not in the rendered window → `-1`.
pub fn Viewer::get_offset_for_column(
  self : Viewer,
  line_number : Int,
  column : Int,
) -> Double {
  guard (self.get_model(), self.get_view_model(), self.get_view())
    is (Some(model), Some(view_model), Some(view)) else {
    return -1.0
  }
  let model_position = model.validate_position(Position(line_number, column))
  let view_position = view_model
    .coordinates_converter()
    .model_position_to_view_position(model_position)
  self.flush_accumulated_and_render_now()
  view.offset_for_column(view_position.line_number, view_position.column)
}

///|
/// Rendered width of a model line, Monaco's `getWidthOfLine` (`cew:1694`) →
/// `view.getLineWidth`: convert the line's max-column model position to its view
/// line (the last wrapped segment), then measure that view line's width. No real
/// view → `-1`; line not in the rendered window → `-1`.
pub fn Viewer::get_width_of_line(self : Viewer, line_number : Int) -> Double {
  guard (self.get_model(), self.get_view_model(), self.get_view())
    is (Some(model), Some(view_model), Some(view)) else {
    return -1.0
  }
  let line_count = model.get_line_count()
  let clamped_line = @base_common.clamp_int(line_number, 1, line_count)
  let max_column = model.get_line_max_column(clamped_line)
  let view_position = view_model
    .coordinates_converter()
    .model_position_to_view_position(Position(clamped_line, max_column))
  self.flush_accumulated_and_render_now()
  view.line_width(
    view_position.line_number,
    view_model.get_line_max_column(view_position.line_number),
  )
}

///|
/// A model position projected to scrolled viewport pixels, Monaco's
/// `getScrolledVisiblePosition` (`cew:1668`): `top` is the vertical offset minus
/// scrollTop, `left` is the column offset plus the content-left gutter minus
/// scrollLeft, `height` is the line height. No real view → `null`.
pub fn Viewer::get_scrolled_visible_position(
  self : Viewer,
  position : @base_common.Position,
) -> @editor_api.ScrolledVisiblePosition? {
  guard (self.get_model(), self.get_view_model(), self.get_view())
    is (Some(model), Some(view_model), Some(view)) else {
    return None
  }
  let position = model.validate_position(position)
  let content_left = self.read_api_content_left()
  let top = self.get_vertical_offset_for_position(
      position.line_number,
      position.column,
      include_view_zones=false,
    ) -
    view_model.view_layout.get_current_scroll_top()
  let view_position = view_model
    .coordinates_converter()
    .model_position_to_view_position(position)
  self.flush_accumulated_and_render_now()
  let offset = view.offset_for_column(
    view_position.line_number,
    view_position.column,
  )
  let left = offset +
    content_left -
    view_model.view_layout.get_current_scroll_left()
  let height = self.get_line_height_for_position(position)
  Some({ top, left, height })
}

///|
/// The content-left gutter width (Monaco's `glyphMarginWidth + lineNumbersWidth +
/// decorationsWidth`), the offset DOM-measured line x's are relative to. Backed
/// by the view model's measured `gutter_width`; `0` with no model.
fn Viewer::read_api_content_left(self : Viewer) -> Double {
  match self.get_model() {
    Some(model) =>
      self.configuration.snapshot().gutter_width(model.snapshot.line_count())
    None => 0.0
  }
}

///|
/// Flushes a pending render so DOM-measured getters read current client rects,
/// Monaco's `_flushAccumulatedAndRenderNow`. A no-op when nothing is pending (the
/// DOM already reflects the latest content) or when there is no view.
fn Viewer::flush_accumulated_and_render_now(self : Viewer) -> Unit {
  if self.mount.has_pending_render() && !self.disposed {
    self.cancel_render_frame()
    self.flush_render()
  }
}
