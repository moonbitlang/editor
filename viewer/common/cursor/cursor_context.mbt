///|
/// The conversion context a cursor needs, the readonly-viewer reduction of
/// Monaco's `cursorContext.ts` `CursorContext`. Monaco's holds the model, view
/// model, coordinates converter, and cursor config. The local context needs
/// only the converter to bridge model and view positions; the owning
/// `CursorsController` separately holds the mutable `TextModel` for validation
/// and content-version tracking. The port stores the three exact conversion
/// functions it consumes instead of turning Monaco's structural interface into
/// a runtime MoonBit trait object.
pub struct CursorContext {
  priv view_to_model_ : (@base_common.Position) -> @base_common.Position
  priv view_range_to_model_ : (@base_common.Range) -> @base_common.Range
  priv model_to_view_ : (@base_common.Position) -> @base_common.Position
}

///|
/// Builds a cursor context from the active view model's required conversions.
#alias(new, deprecated)
pub fn CursorContext::CursorContext(
  view_to_model~ : (@base_common.Position) -> @base_common.Position,
  view_range_to_model~ : (@base_common.Range) -> @base_common.Range,
  model_to_view~ : (@base_common.Position) -> @base_common.Position,
) -> CursorContext {
  {
    view_to_model_: view_to_model,
    view_range_to_model_: view_range_to_model,
    model_to_view_: model_to_view,
  }
}

///|
/// Converts a view position to its model position.
pub fn CursorContext::view_to_model(
  self : CursorContext,
  position : @base_common.Position,
) -> @base_common.Position {
  (self.view_to_model_)(position)
}

///|
/// Converts the complete view anchor range to model coordinates. The source's
/// missing-model cursor branch uses the converter's range member as one unit,
/// which can preserve boundary affinity differently from two unrelated point
/// conversions.
fn CursorContext::view_range_to_model(
  self : CursorContext,
  range : @base_common.Range,
) -> @base_common.Range {
  (self.view_range_to_model_)(range)
}

///|
/// Converts a model position to its view position.
pub fn CursorContext::model_to_view(
  self : CursorContext,
  position : @base_common.Position,
) -> @base_common.Position {
  (self.model_to_view_)(position)
}
