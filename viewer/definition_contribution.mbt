///|
let definition_contribution_id : String = "editor.contrib.definition"

///|
priv struct DefinitionActionStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
  position : @base_common.Position
}

///|
priv struct DefinitionContributionState {
  mut disposed : Bool
  mut action_generation : Int
  mut action_source : @language.CancellationTokenSource?
  mut link_generation : Int
  mut link_source : @language.CancellationTokenSource?
  mut link_state : @definition.DefinitionLinkState
  mut link_modifier_down : Bool
  mut last_pointer_target : @definition.DefinitionTargetFingerprint?
  mut last_message : String?
  mut message_widget : @definition_browser.DefinitionMessageWidget?
  mut message_overlay : @editor_browser.OverlayWidget?
  mut message_hide : @base_common.Disposable?
  peek : DefinitionPeekState
  link_decorations : EditorDecorationsCollection
  mut markdown_link_elements : Array[@rdom.Element]
  mut launch_async_task : (async () -> Unit noraise) -> Unit
}

///|
fn DefinitionContributionState::DefinitionContributionState(
  viewer : Viewer,
) -> DefinitionContributionState {
  {
    disposed: false,
    action_generation: 0,
    action_source: None,
    link_generation: 0,
    link_source: None,
    link_state: LinkIdle,
    link_modifier_down: false,
    last_pointer_target: None,
    last_message: None,
    message_widget: None,
    message_overlay: None,
    message_hide: None,
    peek: DefinitionPeekState(),
    link_decorations: viewer.create_decorations_collection(),
    markdown_link_elements: [],
    launch_async_task,
  }
}

///|
fn DefinitionContributionState::cancel_action(
  self : DefinitionContributionState,
) -> Unit {
  self.action_generation += 1
  match self.action_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  self.action_source = None
}

///|
/// Retires a completed or stale action only when it is still the exact request
/// owned by this state. A newer F12 request is therefore never cancelled by an
/// older continuation.
fn DefinitionContributionState::retire_action_source(
  self : DefinitionContributionState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.action_source {
    Some(current) if physical_equal(current, source) => {
      self.action_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn DefinitionContributionState::cancel_link(
  self : DefinitionContributionState,
) -> Unit {
  self.link_generation += 1
  match self.link_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  self.link_source = None
  self.link_state = LinkIdle
  self.link_decorations.clear()
  for element in self.markdown_link_elements {
    @base_browser.remove_element(element)
  }
  self.markdown_link_elements.clear()
}

///|
fn DefinitionContributionState::retire_link_source(
  self : DefinitionContributionState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.link_source {
    Some(current) if physical_equal(current, source) => {
      self.link_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn DefinitionContributionState::reset_link_gesture(
  self : DefinitionContributionState,
) -> Unit {
  self.cancel_link()
  self.link_modifier_down = false
  self.last_pointer_target = None
}

///|
fn DefinitionContributionState::dispose(
  self : DefinitionContributionState,
  viewer : Viewer,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel_action()
  self.reset_link_gesture()
  viewer.close_definition_peek(restore_focus=false)
  viewer.dispose_definition_message()
}

///|
fn register_definition_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    definition_contribution_id,
    BeforeFirstInteraction,
    viewer => Definition(DefinitionContributionState(viewer)),
    viewer => viewer.hook_definition_contribution(),
  )
  registry.register_editor_command(
    "editor.action.revealDefinition",
    viewer => viewer.definition_action_available(),
    viewer => viewer.start_goto_definition(),
    [
      ("F12", false, false),
      // VS Code's web fallback is the same Current-mode action.
      ("F12", false, true),
    ],
  )
  registry.register_editor_command(
    "editor.action.peekDefinition",
    viewer => viewer.definition_peek_available(),
    viewer => viewer.start_peek_definition(),
    [("F12", true, false)],
  )
}

///|
fn Viewer::definition_contribution(
  self : Viewer,
) -> DefinitionContributionState? {
  match self.contributions.lookup(definition_contribution_id) {
    Some(entry) =>
      match entry.instance {
        Definition(state) => Some(state)
        _ => None
      }
    None => None
  }
}

///|
fn Viewer::definition_action_available(self : Viewer) -> Bool {
  guard !self.disposed else { return false }
  match self.get_model() {
    Some(model) => self.services.languages.has_definition_provider(model)
    None => false
  }
}

///|
fn Viewer::handle_markdown_definition_key_down(
  self : Viewer,
  key : String,
  alt : Bool,
  ctrl_cmd : Bool,
  shift : Bool,
) -> Bool {
  guard key == "F12" && !shift else { return false }
  if alt && !ctrl_cmd && self.definition_peek_available() {
    self.start_peek_definition()
    return true
  }
  if !alt && self.definition_action_available() {
    self.start_goto_definition()
    return true
  }
  false
}

///|
fn Viewer::hook_definition_contribution(
  self : Viewer,
) -> Array[@base_common.Disposable] {
  [
    self.on_did_change_model(_ => self.reset_definition_requests()),
    self.on_did_change_model_content(_ => self.reset_definition_requests()),
    self.on_did_change_cursor_selection(_ => {
      self.on_definition_cursor_selection_changed()
    }),
    self.on_mouse_move(event => self.on_definition_mouse_move(event)),
    self.on_mouse_up(event => self.on_definition_mouse_up(event)),
    self.on_mouse_leave(_ => self.reset_definition_link()),
  ]
}

///|
/// Cursor movement invalidates an F12 action and a definition-link request.
/// A Peek that is still resolving its definitions is anchored to that same
/// source position and must close; once results are installed, ordinary
/// selection changes do not destroy the Viewer-owned Peek session.
fn Viewer::on_definition_cursor_selection_changed(self : Viewer) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.cancel_action()
  state.reset_link_gesture()
  match state.peek.phase {
    PeekLoadingDefinitions(_) => self.close_definition_peek(restore_focus=false)
    _ => ()
  }
  self.clear_definition_message()
}

///|
fn Viewer::cancel_definition_link(self : Viewer) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.link_modifier_down = false
      state.cancel_link()
    }
    None => ()
  }
}

///|
fn Viewer::reset_definition_requests(self : Viewer) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.cancel_action()
      state.reset_link_gesture()
      self.close_definition_peek(restore_focus=false)
      self.dispose_definition_message()
    }
    None => ()
  }
}

///|
fn Viewer::reset_definition_link(self : Viewer) -> Unit {
  match self.definition_contribution() {
    Some(state) => state.reset_link_gesture()
    None => ()
  }
}

///|
fn Viewer::start_goto_definition(self : Viewer) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.definition_command_position() is Some(position) else { return }
  state.cancel_action()
  self.clear_definition_message()
  state.action_generation += 1
  let generation = state.action_generation
  let source = @language.CancellationTokenSource()
  state.action_source = Some(source)
  let stamp : DefinitionActionStamp = {
    generation,
    model_identity: model.identity(),
    model_generation: self.model_slot.generation,
    model_version_id: model.get_version_id(),
    position,
  }
  let offset = model.get_offset_at(position)
  let task = state.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
    )
    if !self.definition_action_is_current(stamp, source) {
      state.retire_action_source(source, cancel=true)
      return
    }
    source.dispose()
    state.action_source = None
    let locations = @definition.normalize_definition_locations(locations)
    if locations.is_empty() {
      self.show_definition_message("No definition found")
      return
    }
    self.open_definition_location(locations[0], Current) |> ignore
  })
}

///|
fn definition_link_modifier_is_active(
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
) -> Bool {
  guard !alt && !shift else { return false }
  if @base_common.is_macintosh {
    meta && !ctrl
  } else {
    ctrl && !meta
  }
}

///|
fn Viewer::definition_target_from_mouse_target(
  self : Viewer,
  target : @editor_browser.MouseTarget,
) -> @definition.DefinitionTargetFingerprint? {
  guard self.get_model() is Some(model) else { return None }
  guard !model.is_disposed() else { return None }
  match target {
    MouseTargetContentText(position~, detail~, ..) => {
      guard !detail.might_be_foreign_element else { return None }
      guard detail.injected_text is None else { return None }
      let position = model.validate_position(position)
      guard model.get_word_at_position(position) is Some(word) else {
        return None
      }
      Some(
        @definition.DefinitionTargetFingerprint::from_model(
          model,
          self.model_slot.generation,
          position,
          word,
        ),
      )
    }
    _ => None
  }
}

///|
fn Viewer::definition_target_from_source_offset(
  self : Viewer,
  source_offset : Int,
) -> @definition.DefinitionTargetFingerprint? {
  guard self.get_model() is Some(model) && !model.is_disposed() else {
    return None
  }
  let position = model.get_position_at(source_offset)
  guard model.get_word_at_position(position) is Some(word) else { return None }
  Some(
    @definition.DefinitionTargetFingerprint::from_model(
      model,
      self.model_slot.generation,
      position,
      word,
    ),
  )
}

///|
fn Viewer::definition_command_position(self : Viewer) -> @base_common.Position? {
  if self.current_markdown_document() is None {
    return self.get_position()
  }
  guard self.current_markdown_document() is Some(_) &&
    self.definition_contribution() is Some(state) &&
    state.last_pointer_target is Some(target) &&
    self.definition_link_target_is_current(target) else {
    return None
  }
  Some(target.position)
}

///|
fn Viewer::definition_link_target_is_current(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint,
) -> Bool {
  match self.get_model() {
    Some(model) => {
      guard target.is_current(model, self.model_slot.generation) else {
        return false
      }
      match self.current_markdown_document() {
        Some(markdown) =>
          markdown.source_model_version() == model.get_version_id()
        None => true
      }
    }
    None => false
  }
}

///|
fn Viewer::start_definition_link_request(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.services.languages.has_definition_provider(model) else {
    state.cancel_link()
    return
  }
  match state.link_state {
    LinkResolving(stamp)
    | LinkResolvedEmpty(stamp)
    | LinkArmed(stamp, _)
    | LinkPressed(stamp, _) if stamp.target == target => return
    _ => ()
  }
  state.cancel_link()
  self.clear_definition_message()
  let sequence = state.link_generation
  let stamp : @definition.DefinitionRequestStamp = { sequence, target }
  let source = @language.CancellationTokenSource()
  state.link_source = Some(source)
  state.link_state = LinkResolving(stamp)
  let offset = model.get_offset_at(target.position)
  let task = state.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
    )
    if !self.definition_link_request_is_current(stamp, source) {
      state.retire_link_source(source, cancel=true)
      return
    }
    source.dispose()
    state.link_source = None
    let locations = @definition.normalize_definition_locations(locations)
    if locations.is_empty() {
      state.link_state = LinkResolvedEmpty(stamp)
      state.link_decorations.clear()
      self.show_definition_message("No definition found")
      return
    }
    state.link_state = LinkArmed(stamp, locations)
    match self.current_markdown_document() {
      Some(markdown) => {
        let source_range = model.snapshot.offset_range_of(target.word_range)
        state.markdown_link_elements = markdown.append_projected_range_spans(
          source_range, "moonbit-viewer-markdown-definition-link",
        )
      }
      None =>
        state.link_decorations.set([
          {
            range: target.word_range,
            options: ModelDecorationOptions(
              "",
              inline_class_name="moonbit-viewer-definition-link",
              description="definition-link",
            ),
          },
        ])
        |> ignore
    }
  })
}

///|
fn Viewer::definition_link_request_is_current(
  self : Viewer,
  stamp : @definition.DefinitionRequestStamp,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard !self.disposed && !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.link_generation == stamp.sequence else { return false }
  guard state.link_modifier_down else { return false }
  guard state.last_pointer_target == Some(stamp.target) else { return false }
  guard self.definition_link_target_is_current(stamp.target) else {
    return false
  }
  match state.link_state {
    LinkResolving(current) => current == stamp
    _ => false
  }
}

///|
fn Viewer::on_definition_mouse_move(
  self : Viewer,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  let target = self.definition_target_from_mouse_target(event.target)
  self.handle_definition_pointer_move(
    target,
    event.event.ctrl_key,
    event.event.meta_key,
    event.event.alt_key,
    event.event.shift_key,
    event.event.buttons,
  )
}

///|
fn Viewer::handle_definition_pointer_move(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
  buttons : Int,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.last_pointer_target = target
  let active = definition_link_modifier_is_active(ctrl, meta, alt, shift)
  if !active || buttons != 0 {
    state.link_modifier_down = false
    state.cancel_link()
    return
  }
  state.link_modifier_down = true
  match target {
    Some(target) => self.start_definition_link_request(target)
    None => state.cancel_link()
  }
}

///|
fn Viewer::handle_definition_modifier_change(
  self : Viewer,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let active = definition_link_modifier_is_active(ctrl, meta, alt, shift)
  if !active {
    state.link_modifier_down = false
    state.cancel_link()
    return
  }
  let became_active = !state.link_modifier_down
  state.link_modifier_down = true
  if became_active {
    match state.last_pointer_target {
      Some(target) if self.definition_link_target_is_current(target) =>
        self.start_definition_link_request(target)
      _ => ()
    }
  }
}

///|
fn Viewer::on_definition_mouse_up(
  self : Viewer,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  let target = self.definition_target_from_mouse_target(event.target)
  self.handle_definition_pointer_up(
    target,
    event.event.ctrl_key,
    event.event.meta_key,
    event.event.alt_key,
    event.event.shift_key,
  )
  |> ignore
}

///|
fn Viewer::handle_definition_pointer_up(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
) -> Bool {
  guard self.definition_contribution() is Some(state) else { return false }
  let modifier_active = definition_link_modifier_is_active(
    ctrl, meta, alt, shift,
  )
  match state.link_state {
    LinkPressed(stamp, locations) if modifier_active &&
      state.link_modifier_down &&
      target == Some(stamp.target) &&
      self.definition_link_target_is_current(stamp.target) => {
      let location = locations[0]
      state.cancel_link()
      let task = state.launch_async_task
      task(async fn() noraise {
        self.open_definition_location(location, Current) |> ignore
      })
      return true
    }
    LinkPressed(_, _) => state.cancel_link()
    _ => ()
  }
  false
}

///|
fn Viewer::definition_action_is_current(
  self : Viewer,
  stamp : DefinitionActionStamp,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard !self.disposed && !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.action_generation == stamp.generation else { return false }
  guard self.get_model() is Some(model) else { return false }
  model.identity() == stamp.model_identity &&
  self.model_slot.generation == stamp.model_generation &&
  model.get_version_id() == stamp.model_version_id &&
  self.definition_command_position() == Some(stamp.position)
}

///|
async fn Viewer::open_definition_location(
  self : Viewer,
  location : @language.Location,
  mode : @navigation_api.OpenLocationMode,
) -> Bool noraise {
  if mode == Current {
    match self.get_model() {
      Some(model) if model.uri.to_string() == location.uri.to_string() => {
        let range = model.validate_range(location.range)
        self.set_position(range.get_start_position(), source="gotoDefinition")
        self.reveal_range_in_center_if_outside_viewport(range)
        self.focus()
        return true
      }
      _ => ()
    }
  }
  let accepted = match self.services.location_opener {
    Some(opener) =>
      opener.open({ source_viewer_id: self.get_id(), location, mode })
    None => false
  }
  if !accepted {
    self.show_definition_message("Unable to open definition")
  }
  accepted
}

///|
fn Viewer::show_definition_message(self : Viewer, message : String) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.last_message = Some(message)
      match state.message_hide {
        Some(handle) => handle.dispose()
        None => ()
      }
      state.message_hide = None
      guard self.current_markdown_document() is Some(_) ||
        self.current_code_browser_data() is Some(_) else {
        return
      }
      let widget = match state.message_widget {
        Some(widget) => widget
        None => {
          let widget = @definition_browser.DefinitionMessageWidget()
          state.message_widget = Some(widget)
          widget
        }
      }
      match self.current_markdown_document() {
        Some(markdown) => {
          match state.message_overlay {
            Some(overlay) => self.remove_overlay_widget(overlay)
            None => ()
          }
          state.message_overlay = None
          markdown.overlay_mount().append_child(widget.get_dom_node().as_node())
        }
        None => {
          guard self.current_code_browser_data() is Some(_) else { return }
          if state.message_overlay is None {
            let overlay = overlay_widget(
              "editor.contrib.definition.message",
              widget.get_dom_node(),
            )
            state.message_overlay = Some(overlay)
            self.add_overlay_widget(overlay)
          }
        }
      }
      widget.set_message(message)
      widget.show()
      state.message_hide = Some(
        @base_browser.schedule_timeout(
          () => {
            if !state.disposed {
              widget.hide()
              state.message_hide = None
            }
          },
          2500,
        ),
      )
    }
    None => ()
  }
}

///|
fn Viewer::clear_definition_message(self : Viewer) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.last_message = None
      match state.message_hide {
        Some(handle) => handle.dispose()
        None => ()
      }
      state.message_hide = None
      match state.message_widget {
        Some(widget) => widget.hide()
        None => ()
      }
    }
    None => ()
  }
}

///|
fn Viewer::dispose_definition_message(self : Viewer) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      match state.message_hide {
        Some(handle) => handle.dispose()
        None => ()
      }
      state.message_hide = None
      match state.message_overlay {
        Some(overlay) => self.remove_overlay_widget(overlay)
        None => ()
      }
      state.message_overlay = None
      match state.message_widget {
        Some(widget) => {
          @base_browser.remove_element(widget.get_dom_node())
          widget.dispose()
        }
        None => ()
      }
      state.message_widget = None
      state.last_message = None
    }
    None => ()
  }
}

///|
fn Viewer::definition_message_for_test(self : Viewer) -> String? {
  match self.definition_contribution() {
    Some(state) => state.last_message
    None => None
  }
}

///|
fn Viewer::set_definition_host_for_test(
  self : Viewer,
  launch : (async () -> Unit noraise) -> Unit,
) -> Unit {
  match self.definition_contribution() {
    Some(state) => state.launch_async_task = launch
    None => ()
  }
}

///|
let _definition_test_seam_anchor : Unit = ignore(
  (
    Viewer::definition_message_for_test,
    Viewer::set_definition_host_for_test,
    Viewer::cancel_definition_link,
  ),
)
