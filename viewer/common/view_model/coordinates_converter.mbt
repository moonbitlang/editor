///|
/// The closed coordinate-converter set owned by the view model. It is the
/// concrete representation of Monaco's `ICoordinatesConverter`
/// (`coordinatesConverter.ts:9-30`) and projected `CoordinatesConverter`
/// (`viewModelLines.ts:1073-1119`) over the line collections this viewer
/// currently ships. A future large-file as-is collection extends this enum
/// with an identity arm without changing converter consumers.
pub enum CoordinatesConverter {
  Projected(ViewModelLinesFromProjectedModel)
}

///|
/// Narrows the converter to the three operations retained by cursor state.
/// Cursor owns typed closures instead of importing or retaining a converter.
fn CoordinatesConverter::cursor_context(
  self : CoordinatesConverter,
) -> @cursor.CursorContext {
  CursorContext(
    view_to_model=position => self.view_position_to_model_position(position),
    view_range_to_model=range => self.view_range_to_model_range(range),
    model_to_view=position => self.model_position_to_view_position(position),
  )
}

///|
/// Converts a model position through the projected line collection —
/// `CoordinatesConverter.convertModelPositionToViewPosition`
/// (`viewModelLines.ts:1098-1102`). The collection retains the additional
/// zero-line and below-hidden-range switches; this current converter surface
/// exposes the already-shipped affinity switch only.
pub fn CoordinatesConverter::model_position_to_view_position(
  self : CoordinatesConverter,
  position : @base_common.Position,
  affinity? : @model.PositionAffinity,
) -> @base_common.Position {
  match self {
    Projected(lines) =>
      lines.convert_model_position_to_view_position(
        position.line_number,
        position.column,
        affinity?,
      )
  }
}

///|
/// Converts a view position through the projected line collection —
/// `CoordinatesConverter.convertViewPositionToModelPosition`
/// (`viewModelLines.ts:1082-1084`).
pub fn CoordinatesConverter::view_position_to_model_position(
  self : CoordinatesConverter,
  position : @base_common.Position,
) -> @base_common.Position {
  match self {
    Projected(lines) =>
      lines.convert_view_position_to_model_position(
        position.line_number,
        position.column,
      )
  }
}

///|
/// Converts a model range through the projected line collection —
/// `CoordinatesConverter.convertModelRangeToViewRange`
/// (`viewModelLines.ts:1104-1106`).
pub fn CoordinatesConverter::model_range_to_view_range(
  self : CoordinatesConverter,
  range : @base_common.Range,
  affinity? : @model.PositionAffinity,
) -> @base_common.Range {
  match self {
    Projected(lines) =>
      lines.convert_model_range_to_view_range(range, affinity?)
  }
}

///|
/// Reports projected model-position visibility through the line collection —
/// `CoordinatesConverter.modelPositionIsVisible`
/// (`viewModelLines.ts:1108-1110`). The current collection visibility surface
/// is line-based, so the column remains deliberately unobserved.
pub fn CoordinatesConverter::model_position_is_visible(
  self : CoordinatesConverter,
  position : @base_common.Position,
) -> Bool {
  match self {
    Projected(lines) => lines.model_position_is_visible(position.line_number)
  }
}

///|
/// Converts a view range through the projected line collection —
/// `CoordinatesConverter.convertViewRangeToModelRange`
/// (`viewModelLines.ts:1086-1088`).
pub fn CoordinatesConverter::view_range_to_model_range(
  self : CoordinatesConverter,
  range : @base_common.Range,
) -> @base_common.Range {
  match self {
    Projected(lines) => lines.convert_view_range_to_model_range(range)
  }
}
