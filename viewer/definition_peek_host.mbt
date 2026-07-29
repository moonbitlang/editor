///|
priv struct DefinitionPeekRequestStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
  position : @base_common.Position
}

///|
priv struct DefinitionPeekState {
  mut generation : Int
  mut phase : @definition.DefinitionPeekPhase
  mut definition_source : @language.CancellationTokenSource?
  mut preview_generation : Int
  mut preview_source : @language.CancellationTokenSource?
  mut locations : Array[@language.Location]
  mut selected_index : Int
  mut widget : @definition_browser.DefinitionPeekWidget?
  mut zone_id : String?
  mut markdown_projection_generation : Int?
  mut preview_viewer : Viewer?
  mut preview_reference : @navigation_api.TextModelReference?
  mut preview_layout_frame : @base_common.Disposable?
  mut preview_resize_observer : @base_common.Disposable?
}

///|
fn DefinitionPeekState::DefinitionPeekState() -> DefinitionPeekState {
  {
    generation: 0,
    phase: PeekClosed,
    definition_source: None,
    preview_generation: 0,
    preview_source: None,
    locations: [],
    selected_index: -1,
    widget: None,
    zone_id: None,
    markdown_projection_generation: None,
    preview_viewer: None,
    preview_reference: None,
    preview_layout_frame: None,
    preview_resize_observer: None,
  }
}

///|
fn DefinitionPeekState::retire_definition_source(
  self : DefinitionPeekState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.definition_source {
    Some(current) if physical_equal(current, source) => {
      self.definition_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn DefinitionPeekState::retire_preview_source(
  self : DefinitionPeekState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.preview_source {
    Some(current) if physical_equal(current, source) => {
      self.preview_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn Viewer::definition_peek_available(self : Viewer) -> Bool {
  self.role == OuterViewer &&
  self.definition_action_available() &&
  (
    self.current_code_browser_data() is Some(_) ||
    self.current_markdown_document() is Some(_)
  )
}

///|
fn Viewer::start_peek_definition(self : Viewer) -> Unit {
  guard self.definition_peek_available() else { return }
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.definition_command_position() is Some(position) else { return }
  self.close_definition_peek(restore_focus=false)
  self.clear_definition_message()
  state.cancel_action()
  if self.current_markdown_document() is Some(_) {
    // The pointer-derived source position is the Markdown equivalent of the
    // Code cursor anchor and must survive focus transfer into the Peek shell.
    state.link_modifier_down = false
    state.cancel_link()
  } else {
    state.reset_link_gesture()
  }
  state.peek.generation += 1
  let generation = state.peek.generation
  guard self.open_definition_peek_shell(position, generation) else {
    self.show_definition_message("No preview available")
    return
  }
  let source = @language.CancellationTokenSource()
  state.peek.definition_source = Some(source)
  state.peek.phase = PeekLoadingDefinitions(generation)
  let stamp : DefinitionPeekRequestStamp = {
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
    if !self.definition_peek_request_is_current(stamp, source) {
      state.peek.retire_definition_source(source, cancel=true)
      return
    }
    source.dispose()
    state.peek.definition_source = None
    let locations = @definition.normalize_definition_locations(locations)
    state.peek.locations = locations
    if locations.is_empty() {
      state.peek.selected_index = -1
      state.peek.phase = PeekEmpty(generation)
      match state.peek.widget {
        Some(widget) => widget.set_locations([], 0)
        None => ()
      }
      self.show_definition_message("No definition found")
      return
    }
    state.peek.selected_index = 0
    match state.peek.widget {
      Some(widget) => {
        widget.set_locations(locations, 0)
        widget.show_preview_loading()
      }
      None => return
    }
    self.load_definition_peek_preview(generation, 0)
  })
}

///|
fn Viewer::open_definition_peek_shell(
  self : Viewer,
  position : @base_common.Position,
  generation : Int,
) -> Bool {
  guard self.definition_contribution() is Some(state) else { return false }
  let widget = @definition_browser.DefinitionPeekWidget({
    on_close: () => self.close_definition_peek(restore_focus=true),
    on_select: index => self.select_definition_peek_result(index),
    on_confirm: index => self.confirm_definition_peek_result(index),
    on_next: () => self.move_definition_peek_result(1),
    on_previous: () => self.move_definition_peek_result(-1),
  })
  match self.current_code_browser_data() {
    Some(_) => {
      let zone = @editor_browser.ViewZone(
        position.line_number,
        widget.get_dom_node(),
        suppress_mouse_down=true,
        height_in_lines=@definition_browser.definition_peek_height_in_lines.to_double(),
      )
      let added_id = Ref("")
      self.change_view_zones(accessor => added_id.val = accessor.add_zone(zone))
      if added_id.val == "" {
        widget.dispose()
        return false
      }
      state.peek.zone_id = Some(added_id.val)
    }
    None =>
      match self.current_markdown_document() {
        Some(markdown) => {
          widget
          .get_dom_node()
          .set_attribute(
            "class", "moonbit-viewer-definition-peek moonbit-viewer-definition-peek-overlay",
          )
          markdown.overlay_mount().append_child(widget.get_dom_node().as_node())
          state.peek.markdown_projection_generation = Some(
            markdown.projection_generation(),
          )
        }
        None => {
          widget.dispose()
          return false
        }
      }
  }
  state.peek.widget = Some(widget)
  @base_browser.queue_microtask(() => {
    if self.definition_peek_session_is_current(generation) {
      widget.focus()
    }
  })
  true
}

///|
fn Viewer::definition_peek_request_is_current(
  self : Viewer,
  stamp : DefinitionPeekRequestStamp,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard !self.disposed && !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.peek.generation == stamp.generation else { return false }
  guard state.peek.definition_source is Some(current_source) else {
    return false
  }
  guard physical_equal(current_source, source) else { return false }
  guard self.get_model() is Some(model) else { return false }
  model.identity() == stamp.model_identity &&
  self.model_slot.generation == stamp.model_generation &&
  model.get_version_id() == stamp.model_version_id &&
  self.definition_command_position() == Some(stamp.position)
}

///|
fn Viewer::definition_peek_session_is_current(
  self : Viewer,
  generation : Int,
) -> Bool {
  guard !self.disposed else { return false }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.peek.generation == generation && state.peek.widget is Some(_) else {
    return false
  }
  match (state.peek.zone_id, state.peek.markdown_projection_generation) {
    (Some(_), None) => self.current_code_browser_data() is Some(_)
    (None, Some(projection_generation)) =>
      match self.current_markdown_document() {
        Some(markdown) =>
          markdown.projection_generation() == projection_generation
        None => false
      }
    _ => false
  }
}

///|
fn Viewer::clear_definition_peek_preview(self : Viewer) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.peek.preview_generation += 1
  match state.peek.preview_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  state.peek.preview_source = None
  match state.peek.preview_resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  state.peek.preview_resize_observer = None
  match state.peek.preview_layout_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  state.peek.preview_layout_frame = None
  match state.peek.preview_viewer {
    Some(viewer) => {
      state.peek.preview_viewer = None
      viewer.set_model(None)
      viewer.dispose()
    }
    None => ()
  }
  match state.peek.preview_reference {
    Some(reference) => {
      state.peek.preview_reference = None
      reference.dispose()
    }
    None => ()
  }
}

///|
fn Viewer::load_definition_peek_preview(
  self : Viewer,
  generation : Int,
  index : Int,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard self.definition_peek_session_is_current(generation) else { return }
  guard index >= 0 && index < state.peek.locations.length() else { return }
  self.clear_definition_peek_preview()
  state.peek.selected_index = index
  match state.peek.widget {
    Some(widget) => {
      widget.set_selected_index(index)
      widget.show_preview_loading()
    }
    None => return
  }
  let location = state.peek.locations[index]
  state.peek.preview_generation += 1
  let preview_generation = state.peek.preview_generation
  state.peek.phase = PeekLoadingPreview(generation, preview_generation)
  match self.get_model() {
    Some(model) if model.uri.to_string() == location.uri.to_string() => {
      self.schedule_definition_peek_preview(
        generation, preview_generation, location, model,
      )
      return
    }
    _ => ()
  }
  guard self.services.text_model_resolver is Some(resolver) else {
    self.show_definition_peek_preview_unavailable(
      generation, preview_generation, "No preview available",
    )
    return
  }
  let source = @language.CancellationTokenSource()
  state.peek.preview_source = Some(source)
  let task = state.launch_async_task
  task(async fn() noraise {
    let reference = resolver.resolve(location.uri, source.token())
    if !self.definition_peek_preview_request_is_current(
        generation, preview_generation, source,
      ) {
      state.peek.retire_preview_source(source, cancel=true)
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    source.dispose()
    state.peek.preview_source = None
    match reference {
      None =>
        self.show_definition_peek_preview_unavailable(
          generation, preview_generation, "No preview available",
        )
      Some(reference) => {
        let model = reference.model()
        if model.is_disposed() ||
          model.uri.to_string() != location.uri.to_string() {
          reference.dispose()
          self.show_definition_peek_preview_unavailable(
            generation, preview_generation, "No preview available",
          )
          return
        }
        self.schedule_definition_peek_preview(
          generation,
          preview_generation,
          location,
          model,
          reference~,
        )
      }
    }
  })
}

///|
fn Viewer::definition_peek_preview_request_is_current(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard self.definition_peek_session_is_current(generation) else {
    return false
  }
  guard !source.token().is_cancellation_requested() else { return false }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.peek.preview_generation == preview_generation else {
    return false
  }
  match state.peek.preview_source {
    Some(current_source) => physical_equal(current_source, source)
    None => false
  }
}

///|
fn Viewer::schedule_definition_peek_preview(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  location : @language.Location,
  model : @model.TextModel,
  reference? : @navigation_api.TextModelReference,
) -> Unit {
  guard self.definition_contribution() is Some(state) else {
    match reference {
      Some(reference) => reference.dispose()
      None => ()
    }
    return
  }
  state.peek.preview_reference = reference
  @base_browser.queue_microtask(() => {
    if !self.definition_peek_preview_is_current(
        generation, preview_generation, model,
      ) {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    guard state.peek.widget is Some(widget) else { return }
    let preview_host = widget.get_preview_host()
    let preview = Viewer(
      services=self.services,
      options=self.get_options(),
      initial_container=preview_host,
      role=PeekPreviewViewer,
    )
    preview.attach(preview_host)
    state.peek.preview_viewer = Some(preview)
    preview.set_model(Some(model))
    let range = model.validate_range(location.range)
    preview.set_position(range.get_start_position(), source="peekDefinition")
    preview.reveal_range_in_center_if_outside_viewport(range)
    preview.handle_initialized()
    state.peek.preview_resize_observer = @base_browser.observe_element_resize(
      preview_host,
      () => {
        if self.definition_peek_preview_is_current(
            generation, preview_generation, model,
          ) {
          preview.layout()
        }
      },
    )
    state.peek.preview_layout_frame = Some(
      @base_browser.schedule_at_next_animation_frame(() => {
        if self.definition_peek_preview_is_current(
            generation, preview_generation, model,
          ) {
          preview.layout()
        }
      }),
    )
    widget.show_preview_ready()
    state.peek.phase = PeekShown(generation, preview_generation)
  })
}

///|
fn Viewer::definition_peek_preview_is_current(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  model : @model.TextModel,
) -> Bool {
  guard self.definition_peek_session_is_current(generation) else {
    return false
  }
  guard !model.is_disposed() else { return false }
  guard self.definition_contribution() is Some(state) else { return false }
  state.peek.preview_generation == preview_generation
}

///|
fn Viewer::show_definition_peek_preview_unavailable(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  message : String,
) -> Unit {
  guard self.definition_peek_session_is_current(generation) else { return }
  guard self.definition_contribution() is Some(state) else { return }
  guard state.peek.preview_generation == preview_generation else { return }
  state.peek.phase = PeekUnavailable(generation, preview_generation)
  match state.peek.widget {
    Some(widget) => widget.show_preview_unavailable(message)
    None => ()
  }
}

///|
fn Viewer::select_definition_peek_result(self : Viewer, index : Int) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let generation = state.peek.generation
  guard index >= 0 && index < state.peek.locations.length() else { return }
  if index == state.peek.selected_index &&
    (
      state.peek.preview_viewer is Some(_) ||
      state.peek.preview_source is Some(_)
    ) {
    return
  }
  self.load_definition_peek_preview(generation, index)
}

///|
fn Viewer::move_definition_peek_result(self : Viewer, delta : Int) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let length = state.peek.locations.length()
  guard length > 0 else { return }
  let current = if state.peek.selected_index >= 0 &&
    state.peek.selected_index < length {
    state.peek.selected_index
  } else {
    0
  }
  let next = if delta < 0 {
    if current == 0 {
      length - 1
    } else {
      current - 1
    }
  } else if current + 1 >= length {
    0
  } else {
    current + 1
  }
  self.select_definition_peek_result(next)
}

///|
fn Viewer::confirm_definition_peek_result(self : Viewer, index : Int) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard index >= 0 && index < state.peek.locations.length() else { return }
  let location = state.peek.locations[index]
  let task = state.launch_async_task
  self.close_definition_peek(restore_focus=true)
  task(async fn() noraise {
    self.open_definition_location(location, Current) |> ignore
  })
}

///|
fn Viewer::close_definition_peek(self : Viewer, restore_focus~ : Bool) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let peek = state.peek
  peek.generation += 1
  peek.phase = PeekClosed
  match peek.definition_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  peek.definition_source = None
  let widget = peek.widget
  match widget {
    Some(widget) => widget.dispose()
    None => ()
  }
  self.clear_definition_peek_preview()
  peek.widget = None
  let zone_id = peek.zone_id
  peek.zone_id = None
  let markdown_projection_generation = peek.markdown_projection_generation
  peek.markdown_projection_generation = None
  peek.locations = []
  peek.selected_index = -1
  match zone_id {
    Some(zone_id) =>
      if self.disposed {
        // Public `change_view_zones` intentionally rejects disposed Viewers.
        // Disposal still tears the current View down synchronously, so use the
        // lower owner only in this terminal path.
        match self.current_code_browser_data() {
          Some(browser) =>
            browser.view.change_view_zones(accessor => {
              accessor.remove_zone(zone_id)
            })
          None => ()
        }
      } else {
        // The live root transaction also schedules the render that removes the
        // zone's layout gap; focus restoration must not be that render's
        // accidental trigger.
        self.change_view_zones(accessor => accessor.remove_zone(zone_id))
      }
    None => ()
  }
  match markdown_projection_generation {
    Some(_) =>
      match widget {
        Some(widget) => @base_browser.remove_element(widget.get_dom_node())
        None => ()
      }
    None => ()
  }
  if restore_focus && !self.disposed {
    self.focus()
  }
}

///|
fn Viewer::definition_peek_phase_for_test(
  self : Viewer,
) -> @definition.DefinitionPeekPhase {
  match self.definition_contribution() {
    Some(state) => state.peek.phase
    None => PeekClosed
  }
}

///|
let _definition_peek_test_seam_anchor : Unit = ignore(
  Viewer::definition_peek_phase_for_test,
)
