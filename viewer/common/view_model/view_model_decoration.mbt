///|
/// Faithful 1:1 port of Monaco's
/// `viewModel/viewModelDecoration.ts` declarations used by the viewer, from
/// checked-in vscode submodule.
///
/// A model decoration resolved into view coordinates (Monaco
/// `ViewModelDecoration`).
pub(all) struct ViewModelDecoration {
  range : @base_common.Range
  options : @model.ModelDecorationOptions
}

///|
/// Builds a view-model decoration.
fn ViewModelDecoration::ViewModelDecoration(
  range : @base_common.Range,
  options : @model.ModelDecorationOptions,
) -> ViewModelDecoration {
  { range, options }
}

///|
/// Whether a model decoration is visible. See the inline-decoration file
/// deviation: the comment/string-token hiding paths are not ported (no
/// tokenization seam, and unused by the suite), so this is always `true`.
fn is_model_decoration_visible(
  _model : @model.TextModel,
  _decoration : @model.ModelDecoration,
) -> Bool {
  true
}
