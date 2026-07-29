///|
/// Narrow pre-selection seam used by the browser mouse controller. A press
/// suppresses the ordinary cursor/selection dispatch only after the exact
/// token has resolved to a live definition while Ctrl/Cmd was already held.
fn Viewer::before_definition_mouse_down_selection(
  self : Viewer,
  event : @editor_browser.EditorDomMouseEvent,
  target : @editor_browser.MouseTarget,
) -> Bool {
  guard event.left_button && event.detail == 1 else { return false }
  guard definition_link_modifier_is_active(
    event.ctrl_key,
    event.meta_key,
    event.alt_key,
    event.shift_key,
  ) else {
    return false
  }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.link_modifier_down else { return false }
  let target = self.definition_target_from_mouse_target(
    self.convert_mouse_target(target),
  )
  self.before_definition_target_mouse_down(target)
}

///|
fn Viewer::before_definition_target_mouse_down(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
) -> Bool {
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.link_modifier_down else { return false }
  match state.link_state {
    LinkArmed(stamp, locations) if target == Some(stamp.target) &&
      self.definition_link_target_is_current(stamp.target) => {
      state.link_state = LinkPressed(stamp, locations)
      true
    }
    _ => false
  }
}
