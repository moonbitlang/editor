// Ported from `vscode/src/vs/editor/common/config/editorOptions.ts:2457-2556`
// (checked-in vscode submodule): the
// `EditorLayoutInfo` shape, trimmed to the parts the viewer renders. Relocated
// here from the root package so the hit-test pipeline
// (`internal/viewer/browser/controller`) can read it; `Viewer::get_layout_info`
// (viewer/public_read_api.mbt) stays the producer.
//
// Omissions: `glyphMarginDecorationLaneCount` (no glyph-margin lanes),
// `minimap`/`overviewRuler` cluster, `viewportColumn`,
// `isWordWrapMinified`/`isViewportWrapping`/`wrappingColumn`, and the
// scrollbar width/height fields — none are rendered or consumed by the
// viewer. The viewer has no glyph margin, so `glyph_margin_left`/
// `glyph_margin_width` are always `0` and
// `content_left = line_numbers_width + decorations_width`.

///|
pub(all) struct EditorLayoutInfo {
  /// Full editor width.
  width : Double
  /// Full editor height.
  height : Double
  /// Left position for the glyph margin.
  glyph_margin_left : Double
  /// The width of the glyph margin.
  glyph_margin_width : Double
  /// Left position for the line numbers.
  line_numbers_left : Double
  /// The width of the line numbers.
  line_numbers_width : Double
  /// Left position for the line decorations.
  decorations_left : Double
  /// The width of the line decorations.
  decorations_width : Double
  /// Left position for the content (actual text).
  content_left : Double
  /// The width of the content (actual text).
  content_width : Double
  /// The height of the horizontal scrollbar.
  horizontal_scrollbar_height : Double
  /// The width of the vertical scrollbar.
  vertical_scrollbar_width : Double
} derive(Eq, Debug)
