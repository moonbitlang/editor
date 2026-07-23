///|
/// Subscribes to the ViewModel's outgoing cursor event alias.
pub fn ViewModel::on_cursor_state_changed(
  self : ViewModel,
  listener : (CursorStateChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.cursor_event_dispatcher.on_event(listener)
}

///|
/// Sends an accepted controller transition through the outgoing-only
/// dispatcher and reports whether the full model/view state changed. A
/// view-only change returns true but remains silent publicly.
fn ViewModel::emit_cursor_state_change(
  self : ViewModel,
  change : @cursor.CursorStateChange?,
) -> Bool {
  match change {
    None => false
    Some(change) => {
      if change.has_outgoing_event {
        self.cursor_event_dispatcher.emit_outgoing_event(
          CursorStateChangedEvent::from_change(change),
        )
      }
      true
    }
  }
}

///|
/// Validates a view-side cursor state with `PositionAffinity.None`, preserving
/// source leftover arithmetic by adding each column correction to its residue.
fn ViewModel::validate_view_cursor_state(
  self : ViewModel,
  state : @cursor.SingleCursorState,
) -> @cursor.SingleCursorState {
  let valid_position = self.normalize_position(state.position, None)
  let valid_start = if state.selection_start_start == state.position {
    valid_position
  } else {
    self.normalize_position(state.selection_start_start, None)
  }
  let valid_end = if state.selection_start_end == state.selection_start_start {
    valid_start
  } else {
    self.normalize_position(state.selection_start_end, None)
  }
  if valid_position == state.position &&
    valid_start == state.selection_start_start &&
    valid_end == state.selection_start_end {
    return state
  }
  SingleCursorState(
    valid_start,
    valid_end,
    state.selection_start_kind,
    valid_position,
    selection_start_leftover_visible_columns=state.selection_start_leftover_visible_columns +
      state.selection_start_start.column -
      valid_start.column,
    leftover_visible_columns=state.leftover_visible_columns +
      state.position.column -
      valid_position.column,
  )
}

///|
/// Applies one source-shaped partial state through the common controller and
/// outgoing-dispatcher spine. `None` preserves the source's both-null no-op.
pub fn ViewModel::set_cursor_state(
  self : ViewModel,
  state : @cursor.PartialCursorState?,
  source : String,
  reason : @editor_api.CursorChangeReason,
) -> Bool {
  self.emit_cursor_state_change(
    self.cursor.set_cursor_state(state, source~, reason~),
  )
}

///|
/// Applies a model-side state through the common transition/dispatcher spine.
pub fn ViewModel::set_model_cursor_state(
  self : ViewModel,
  state : @cursor.SingleCursorState,
  source : String,
  reason : @editor_api.CursorChangeReason,
) -> Bool {
  self.set_cursor_state(
    Some(@cursor.CursorState::from_model_state(state)),
    source,
    reason,
  )
}

///|
/// Applies a view-side state after source-shaped normalization, then emits the
/// resulting outgoing cursor fact when its model side changed.
pub fn ViewModel::set_view_cursor_state(
  self : ViewModel,
  state : @cursor.SingleCursorState,
  source : String,
  reason : @editor_api.CursorChangeReason,
) -> Bool {
  let state = self.validate_view_cursor_state(state)
  self.set_cursor_state(
    Some(@cursor.CursorState::from_view_state(state)),
    source,
    reason,
  )
}
