///|
/// A single cursor, a faithful port of Monaco's `oneCursor.ts` `Cursor`. It
/// keeps both a model-coordinate and a view-coordinate `SingleCursorState` in
/// sync through the `CursorContext`'s coordinates converter. Setting one side
/// derives the other (`set_state`), exactly as Monaco's `_setState` does.
///
/// Model validation and internal-version snapshots belong to
/// `CursorsController`; this lower owner only derives the missing coordinate
/// side. Editable marker-tracked ranges remain outside the readonly contract.
pub struct Cursor {
  mut model_state : SingleCursorState
  mut view_state : SingleCursorState
}

///|
/// A fresh cursor collapsed at the document origin.
#alias(new, deprecated)
pub fn Cursor::Cursor() -> Cursor {
  let origin = @base_common.Position::Position(1, 1)
  {
    model_state: SingleCursorState::collapsed(origin),
    view_state: SingleCursorState::collapsed(origin),
  }
}

///|
/// Captures the model and view sides together.
fn Cursor::as_cursor_state(self : Cursor) -> CursorState {
  CursorState(self.model_state, self.view_state)
}

///|
/// Source-shaped nullable state entry. Exactly one side is normally supplied;
/// when both are present the model side remains authoritative and is
/// reprojected through the live converter. The source's simultaneous
/// model/view cross-validation surface is intentionally owned by the
/// controller's documented reduced seam. A double-null input is a no-op.
fn Cursor::set_state(
  self : Cursor,
  context : CursorContext,
  model_state : SingleCursorState?,
  view_state : SingleCursorState?,
) -> Bool {
  match (model_state, view_state) {
    (None, None) => false
    (Some(model_state), _) => {
      self.set_model_state(context, model_state)
      true
    }
    (None, Some(view_state)) => {
      self.set_view_state(context, view_state)
      true
    }
  }
}

///|
/// Sets the cursor from a view-coordinate state, deriving the model state by
/// converting every endpoint through the coordinates converter. Mirrors the
/// "we only have the view state => compute the model state" branch of
/// Monaco's `_setState`.
fn Cursor::set_view_state(
  self : Cursor,
  context : CursorContext,
  view_state : SingleCursorState,
) -> Unit {
  self.view_state = view_state
  let model_selection_start = context.view_range_to_model(
    Range(
      view_state.selection_start_start.line_number,
      view_state.selection_start_start.column,
      view_state.selection_start_end.line_number,
      view_state.selection_start_end.column,
    ),
  )
  self.model_state = SingleCursorState(
    Position(
      model_selection_start.start_line_number,
      model_selection_start.start_column,
    ),
    Position(
      model_selection_start.end_line_number,
      model_selection_start.end_column,
    ),
    view_state.selection_start_kind,
    context.view_to_model(view_state.position),
    selection_start_leftover_visible_columns=view_state.selection_start_leftover_visible_columns,
    leftover_visible_columns=view_state.leftover_visible_columns,
  )
}

///|
/// Sets the cursor from a model-coordinate state, deriving the view state by
/// converting every endpoint through the coordinates converter. Mirrors the
/// "we only have the model state => compute the view state" branch of
/// Monaco's `_setState`; used to re-project an existing selection after the
/// view model reflows (wrapping and injected text).
pub fn Cursor::set_model_state(
  self : Cursor,
  context : CursorContext,
  model_state : SingleCursorState,
) -> Unit {
  self.model_state = model_state
  self.view_state = SingleCursorState(
    context.model_to_view(model_state.selection_start_start),
    context.model_to_view(model_state.selection_start_end),
    model_state.selection_start_kind,
    context.model_to_view(model_state.position),
    selection_start_leftover_visible_columns=model_state.selection_start_leftover_visible_columns,
    leftover_visible_columns=model_state.leftover_visible_columns,
  )
}

///|
/// Re-derives the view state from the current model state through `context`.
/// Used when the view model is rebuilt so an existing selection stays anchored
/// to the same model positions after the reflow.
fn Cursor::reproject(self : Cursor, context : CursorContext) -> Unit {
  self.set_model_state(context, self.model_state)
}
