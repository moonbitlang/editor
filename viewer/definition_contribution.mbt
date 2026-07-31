///|
let definition_contribution_id : String = "editor.contrib.definition"

///|
priv struct DefinitionActionStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
}

///|
priv struct DefinitionOpenStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
}

///|
priv struct DefinitionContributionState {
  mut disposed : Bool
  mut action_generation : Int
  mut action_source : @language.CancellationTokenSource?
  mut open_generation : Int
  mut link_generation : Int
  mut link_source : @language.CancellationTokenSource?
  mut link_state : @definition.DefinitionLinkState
  mut link_modifier_down : Bool
  mut last_pointer_target : @definition.DefinitionTargetFingerprint?
  mut definition_mouse_down_line : Int
  mut last_message : String?
  mut message_widget : @definition_browser.DefinitionMessageWidget?
  mut message_hide : @base_common.Disposable?
  mut peek_source : @language.CancellationTokenSource?
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
    open_generation: 0,
    link_generation: 0,
    link_source: None,
    link_state: LinkIdle,
    link_modifier_down: false,
    last_pointer_target: None,
    definition_mouse_down_line: 0,
    last_message: None,
    message_widget: None,
    message_hide: None,
    peek_source: None,
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
  let source = self.action_source
  self.action_source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
fn DefinitionContributionState::invalidate_open_feedback(
  self : DefinitionContributionState,
) -> Unit {
  self.open_generation += 1
}

///|
/// Retires a completed or stale Definition Peek provider request only when it
/// is still the exact source owned by this state.
fn DefinitionContributionState::retire_peek_source(
  self : DefinitionContributionState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.peek_source {
    Some(current) if physical_equal(current, source) => {
      self.peek_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
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
  let source = self.link_source
  self.link_source = None
  self.link_state = LinkIdle
  self.link_decorations.clear()
  for element in self.markdown_link_elements {
    @base_browser.remove_element(element)
  }
  self.markdown_link_elements.clear()
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
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
  self.cancel_link_gesture()
  self.last_pointer_target = None
}

///|
/// Retires the modifier/click transaction while retaining the live pointer
/// anchor used by semantic Markdown keyboard commands.
fn DefinitionContributionState::cancel_link_gesture(
  self : DefinitionContributionState,
) -> Unit {
  self.cancel_link()
  self.link_modifier_down = false
  self.definition_mouse_down_line = 0
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
  viewer.close_references_peek(restore_focus=false)
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
    title="Go to Definition",
    menu_keybinding_label=definition_menu_keybinding_label(
      alt=false,
      ctrl_cmd=false,
    ),
    menu_placements=[
      { menu_id: EditorContext, group: "navigation", order: 1.1 },
    ],
  )
  registry.register_editor_command(
    "editor.action.peekDefinition",
    viewer => viewer.definition_peek_available(),
    viewer => viewer.start_peek_definition(),
    [("F12", true, false)],
    title="Peek Definition",
    menu_keybinding_label=definition_menu_keybinding_label(
      alt=true,
      ctrl_cmd=false,
    ),
    menu_placements=[
      { menu_id: EditorContext, group: "navigation", order: 1.2 },
    ],
  )
}

///|
fn definition_menu_keybinding_label(alt~ : Bool, ctrl_cmd~ : Bool) -> String {
  if @base_common.is_macintosh {
    "\{(if alt { "\u{2325}" } else { "" })}\{(if ctrl_cmd { "\u{2318}" } else { "" })}F12"
  } else {
    "\{(if alt { "Alt+" } else { "" })}\{(if ctrl_cmd { "Ctrl+" } else { "" })}F12"
  }
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
  if !alt &&
    !ctrl_cmd &&
    ((key == "F10" && shift) || (key == "ContextMenu" && !shift)) {
    return self.show_markdown_context_menu_from_keyboard()
  }
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
    self.on_did_change_cursor_selection(event => {
      self.on_definition_cursor_selection_changed(event.selection.is_empty())
    }),
    self.on_mouse_move(event => self.on_definition_mouse_move(event)),
    self.on_mouse_up(event => self.on_definition_mouse_up(event)),
    self.on_mouse_leave(_ => self.reset_definition_link()),
    self.on_did_scroll_change(event => {
      if event.scroll_top_changed || event.scroll_left_changed {
        self.reset_definition_link()
      }
    }),
  ]
}

///|
/// Cursor movement invalidates an F12 action and a definition-link request.
/// A Peek that is still resolving its definitions is anchored to that same
/// source position and must close; once results are installed, ordinary
/// selection changes do not destroy the Viewer-owned Peek session. When an
/// unresolved definition link lets a collapsed mousedown perform the ordinary
/// cursor move, that event cancels only the preview request: the independent
/// mouse-down line must survive until mouseup launches the fresh action. A
/// non-empty drag selection resets the whole gesture and must never navigate.
fn Viewer::on_definition_cursor_selection_changed(
  self : Viewer,
  selection_is_empty : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.invalidate_open_feedback()
  state.cancel_action()
  if state.definition_mouse_down_line > 0 && selection_is_empty {
    state.cancel_link()
  } else {
    state.reset_link_gesture()
  }
  match self.references_contribution() {
    Some(references) =>
      match references.phase {
        PeekLoadingDefinitions(_) =>
          self.close_references_peek(restore_focus=false)
        _ => ()
      }
    None => ()
  }
  self.clear_definition_message()
}

///|
fn Viewer::cancel_definition_link(self : Viewer) -> Unit {
  match self.definition_contribution() {
    Some(state) => state.cancel_link_gesture()
    None => ()
  }
}

///|
fn Viewer::reset_definition_requests(self : Viewer) -> Unit {
  self.clear_markdown_context_menu_anchor()
  match self.definition_contribution() {
    Some(state) => {
      state.cancel_action()
      state.reset_link_gesture()
      self.close_references_peek(restore_focus=false)
      self.dispose_definition_message()
    }
    None => ()
  }
}

///|
fn Viewer::reset_definition_link(self : Viewer) -> Unit {
  self.clear_markdown_context_menu_anchor()
  match self.definition_contribution() {
    Some(state) => state.reset_link_gesture()
    None => ()
  }
}

///|
fn Viewer::start_goto_definition(self : Viewer) -> Unit {
  guard self.definition_command_position() is Some(position) else { return }
  self.start_goto_definition_at(position, mute_message=false)
}

///|
/// Starts the ordinary Definition action at an already validated source
/// position. Definition-link mouseup deliberately uses this entry instead of
/// consuming the preview request's cached locations.
fn Viewer::start_goto_definition_at(
  self : Viewer,
  position : @base_common.Position,
  mute_message~ : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  let position = model.validate_position(position)
  // An ordinary Definition action is a newer navigation intent than a Peek
  // request that is still resolving its definition list. Retire only that
  // loading shell: an already populated Peek remains independently usable.
  match self.references_contribution() {
    Some(references) =>
      match references.phase {
        PeekLoadingDefinitions(_) =>
          self.close_references_peek(restore_focus=false)
        _ => ()
      }
    None => ()
  }
  // A new navigation intent immediately supersedes feedback from any opener
  // that is still awaiting its host, even before this provider request
  // resolves far enough to call the next opener.
  state.invalidate_open_feedback()
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
  }
  let offset = model.get_offset_at(position)
  let task = state.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    if !self.definition_action_is_current(stamp, source) {
      state.retire_action_source(source, cancel=true)
      return
    }
    source.dispose()
    state.action_source = None
    let locations = @definition.normalize_definition_locations(locations)
    self.dispatch_definition_locations(position, locations, mute_message~)
  })
}

///|
/// Applies Monaco's default definition result policy without asking providers
/// a second time: direct-open one result, or populate Peek for multiple
/// results when this outer mounted Viewer can host it.
async fn Viewer::dispatch_definition_locations(
  self : Viewer,
  source_position : @base_common.Position,
  locations : Array[@language.Location],
  mute_message~ : Bool,
) -> Unit noraise {
  if locations.is_empty() {
    if !mute_message {
      self.show_definition_message(
        self.definition_no_result_message(source_position),
        position=source_position,
      )
    }
    return
  }
  if locations.length() > 1 && self.definition_peek_available() {
    self.open_definition_peek_with_locations(source_position, locations)
    return
  }
  self.open_definition_location(
    locations[0],
    Current,
    message_position=source_position,
  )
  |> ignore
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
  Some(target.position())
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
/// Commits a plain-click command anchor. Pointer hover alone must not cancel a
/// Markdown request, but an actual click is the projection equivalent of a Code
/// cursor change and invalidates the old action/loading Peek immediately.
fn Viewer::commit_plain_definition_pointer_target(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.invalidate_open_feedback()
  state.cancel_action()
  match self.references_contribution() {
    Some(references) =>
      match references.phase {
        PeekLoadingDefinitions(_) =>
          self.close_references_peek(restore_focus=false)
        _ => ()
      }
    None => ()
  }
  state.last_pointer_target = match target {
    Some(target) if self.definition_link_target_is_current(target) =>
      Some(target)
    _ => None
  }
  state.cancel_link_gesture()
  self.clear_definition_message()
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
    LinkResolving(stamp) | LinkResolvedEmpty(stamp) | LinkArmed(stamp, _) if stamp.target.same_word(
        target,
      ) => return
    _ => ()
  }
  state.cancel_link()
  self.clear_definition_message()
  let sequence = state.link_generation
  let stamp : @definition.DefinitionRequestStamp = { sequence, target }
  let source = @language.CancellationTokenSource()
  state.link_source = Some(source)
  state.link_state = LinkResolving(stamp)
  let offset = model.get_offset_at(target.position())
  let task = state.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
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
      return
    }
    state.link_state = LinkArmed(stamp, locations)
    match self.current_markdown_document() {
      Some(markdown) => {
        let source_range = model.snapshot.offset_range_of(target.word_range())
        state.markdown_link_elements = markdown.append_projected_range_spans(
          source_range, "moonbit-viewer-markdown-definition-link",
        )
      }
      None =>
        state.link_decorations.set([
          {
            range: target.word_range(),
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
  guard state.last_pointer_target is Some(pointer_target) &&
    pointer_target.same_word(stamp.target) else {
    return false
  }
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
  if buttons != 0 {
    state.reset_link_gesture()
    return
  }
  if !active {
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
fn definition_link_key_is_trigger(key : String) -> Bool {
  if @base_common.is_macintosh {
    key == "Meta"
  } else {
    key == "Control"
  }
}

///|
fn Viewer::handle_definition_modifier_key(
  self : Viewer,
  key : String,
  key_down : Bool,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let active = definition_link_modifier_is_active(ctrl, meta, alt, shift)
  let trigger_key = definition_link_key_is_trigger(key)
  if !key_down {
    if trigger_key {
      state.cancel_link_gesture()
    }
    return
  }
  if !active {
    if trigger_key || state.link_modifier_down {
      state.cancel_link_gesture()
    }
    return
  }
  if !trigger_key {
    // A Ctrl/Cmd chord is not a link gesture. Clearing the whole click state
    // prevents its eventual mouseup from becoming an accidental navigation.
    state.cancel_link_gesture()
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
    left_button=event.event.left_button,
    detail=event.event.detail,
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
  left_button? : Bool = true,
  detail? : Int = 1,
) -> Bool {
  guard self.definition_contribution() is Some(state) else { return false }
  let modifier_active = definition_link_modifier_is_active(
    ctrl, meta, alt, shift,
  )
  let mouse_down_line = state.definition_mouse_down_line
  state.definition_mouse_down_line = 0
  guard modifier_active &&
    left_button &&
    detail <= 1 &&
    state.link_modifier_down &&
    mouse_down_line > 0 &&
    target is Some(target) &&
    target.position().line_number == mouse_down_line &&
    self.definition_link_target_is_current(target) else {
    if !modifier_active && left_button && detail <= 1 {
      self.commit_plain_definition_pointer_target(target)
    }
    return false
  }
  let position = target.position()
  state.reset_link_gesture()
  if self.current_markdown_document() is None {
    self.set_position(position, source="gotoDefinitionLink")
  }
  self.start_goto_definition_at(position, mute_message=true)
  true
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
  model.get_version_id() == stamp.model_version_id
}

///|
async fn Viewer::open_definition_location(
  self : Viewer,
  location : @language.Location,
  mode : @navigation_api.OpenLocationMode,
  message_position? : @base_common.Position,
) -> Bool noraise {
  guard !self.disposed else { return false }
  guard self.definition_contribution() is Some(state) else { return false }
  guard self.get_model() is Some(source_model) else { return false }
  state.invalidate_open_feedback()
  let stamp : DefinitionOpenStamp = {
    generation: state.open_generation,
    model_identity: source_model.identity(),
    model_generation: self.model_slot.generation,
    model_version_id: source_model.get_version_id(),
  }
  let accepted = self.open_peek_location(location, mode, "gotoDefinition")
  if !accepted && self.definition_open_is_current(stamp) {
    self.show_definition_message(
      "Unable to open definition",
      position?=message_position,
    )
  }
  accepted
}

///|
/// VS Code's `_openReference` target feedback shared by Definition and
/// References navigation: retain the full target range for 350ms, and clear it
/// only if the Viewer still owns the exact model that received the decoration.
fn Viewer::show_navigation_target_highlight(
  self : Viewer,
  target_model : @model.TextModel,
  range : @base_common.Range,
) -> Unit {
  let decorations = self.create_decorations_collection(decorations=[
    {
      range,
      options: ModelDecorationOptions(
        "symbolHighlight",
        description="symbol-navigate-action-highlight",
      ),
    },
  ])
  @base_browser.schedule_timeout(
    () => {
      match self.get_model() {
        Some(current) if current.same(target_model) => decorations.clear()
        _ => ()
      }
    },
    350,
  )
  |> ignore
}

///|
fn Viewer::definition_open_is_current(
  self : Viewer,
  stamp : DefinitionOpenStamp,
) -> Bool {
  guard !self.disposed else { return false }
  guard self.definition_contribution() is Some(state) &&
    !state.disposed &&
    state.open_generation == stamp.generation else {
    return false
  }
  guard self.get_model() is Some(model) else { return false }
  model.identity() == stamp.model_identity &&
  self.model_slot.generation == stamp.model_generation &&
  model.get_version_id() == stamp.model_version_id
}

///|
fn Viewer::definition_no_result_message(
  self : Viewer,
  position : @base_common.Position,
) -> String {
  match self.get_model() {
    Some(model) =>
      match model.get_word_at_position(model.validate_position(position)) {
        Some(word) if !word.word.is_empty() =>
          "No definition found for '\{word.word}'"
        _ => "No definition found"
      }
    None => "No definition found"
  }
}

///|
fn Viewer::show_definition_message(
  self : Viewer,
  message : String,
  position? : @base_common.Position,
) -> Unit {
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
      guard self.get_model() is Some(model) else { return }
      let position = model.validate_position(
        match position {
          Some(position) => position
          None =>
            match self.get_position() {
              Some(position) => position
              None => Position(1, 1)
            }
        },
      )
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
          markdown.overlay_mount().append_child(widget.get_dom_node().as_node())
          @base_browser.set_style_property(
            widget.get_dom_node(),
            "position",
            "absolute",
          )
          @base_browser.set_style_property(widget.get_dom_node(), "top", "12px")
          @base_browser.set_style_property(
            widget.get_dom_node(),
            "right",
            "12px",
          )
        }
        None => {
          guard self.current_code_view() is Some(view) else { return }
          if widget.get_dom_node().get_attribute("data-content-widget") is None {
            view.content_widgets.add_widget(widget.content_widget_handle())
          }
          @base_browser.remove_style_property(widget.get_dom_node(), "top")
          @base_browser.remove_style_property(widget.get_dom_node(), "right")
          self.reveal_position_in_center_if_outside_viewport(position)
        }
      }
      widget.set_message(message)
      widget.show_at(position)
      match self.current_code_view() {
        Some(view) => {
          view.content_widgets.set_widget_position(
            widget.content_widget_handle(),
          )
          self.schedule_render()
        }
        None => ()
      }
      state.message_hide = Some(
        @base_browser.schedule_timeout(
          () => {
            if !state.disposed {
              widget.hide()
              match self.current_code_view() {
                Some(view) => {
                  view.content_widgets.set_widget_position(
                    widget.content_widget_handle(),
                  )
                  self.schedule_render()
                }
                None => ()
              }
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
        Some(widget) => {
          widget.hide()
          match self.current_code_view() {
            Some(view) => {
              view.content_widgets.set_widget_position(
                widget.content_widget_handle(),
              )
              self.schedule_render()
            }
            None => ()
          }
        }
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
  match self.references_contribution() {
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
