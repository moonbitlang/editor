///|
/// Narrow pre-selection seam used by the browser mouse controller. A press
/// suppresses the ordinary cursor/selection dispatch only after the exact
/// token has resolved to a live definition while Ctrl/Cmd was already held.
fn Viewer::before_definition_mouse_down_selection(
  self : Viewer,
  event : @editor_browser.EditorDomMouseEvent,
  target : @editor_browser.MouseTarget,
) -> Bool {
  guard event.left_button && event.detail <= 1 else { return false }
  let target = self.definition_target_from_mouse_target(
    self.convert_mouse_target(target),
  )
  guard definition_link_modifier_is_active(
    event.ctrl_key,
    event.meta_key,
    event.alt_key,
    event.shift_key,
  ) else {
    self.commit_plain_definition_pointer_target(target)
    return false
  }
  guard self.definition_contribution() is Some(state) else { return false }
  state.link_modifier_down = true
  self.before_definition_target_mouse_down(target)
}

///|
fn Viewer::before_definition_target_mouse_down(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
) -> Bool {
  guard self.definition_contribution() is Some(state) else { return false }
  // Callers have already validated the current mousedown event's modifier;
  // do not depend on an earlier root keydown/mousemove having been observed.
  state.link_modifier_down = true
  state.definition_mouse_down_line = match target {
    Some(target) if self.definition_link_target_is_current(target) =>
      target.position.line_number
    _ => 0
  }
  match state.link_state {
    LinkArmed(stamp, _) if target is Some(target) &&
      target.same_word(stamp.target) &&
      self.definition_link_target_is_current(stamp.target) => true
    _ => false
  }
}
