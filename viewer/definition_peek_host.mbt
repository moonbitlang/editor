///|
priv struct DefinitionPeekRequestStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
}

///|
priv struct DefinitionPeekAnchor {
  model_identity : Int
  model_generation : Int
  model_version_id : Int
  position : @base_common.Position
} derive(Eq)

///|
priv struct DefinitionPeekState {
  mut generation : Int
  mut phase : @definition.DefinitionPeekPhase
  mut definition_source : @language.CancellationTokenSource?
  mut preview_generation : Int
  mut preview_source : @language.CancellationTokenSource?
  mut locations : Array[@language.Location]
  mut selected_index : Int
  mut anchor : DefinitionPeekAnchor?
  mut widget : @definition_browser.DefinitionPeekWidget?
  mut zone_id : String?
  mut markdown_projection_generation : Int?
  mut preview_viewer : Viewer?
  mut preview_reference : @navigation_api.TextModelReference?
  mut preview_layout_frame : @base_common.Disposable?
  mut preview_resize_observer : @base_common.Disposable?
  mut focus_frame : @base_common.Disposable?
}

///|
/// Preview resources detached atomically from `DefinitionPeekState` before any
/// cancellation or disposal callback can re-enter the Viewer.
priv struct DetachedDefinitionPeekPreview {
  viewer : Viewer?
  reference : @navigation_api.TextModelReference?
  layout_frame : @base_common.Disposable?
  resize_observer : @base_common.Disposable?
  restore_focus : Bool
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
    anchor: None,
    widget: None,
    zone_id: None,
    markdown_projection_generation: None,
    preview_viewer: None,
    preview_reference: None,
    preview_layout_frame: None,
    preview_resize_observer: None,
    focus_frame: None,
  }
}

///|
fn DetachedDefinitionPeekPreview::dispose(
  self : DetachedDefinitionPeekPreview,
) -> Unit {
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  match self.layout_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  match self.viewer {
    Some(viewer) => {
      viewer.set_model(None)
      viewer.dispose()
    }
    None => ()
  }
  match self.reference {
    Some(reference) => reference.dispose()
    None => ()
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
fn Viewer::definition_peek_contains_focus(self : Viewer) -> Bool {
  match self.definition_contribution() {
    Some(state) =>
      match state.peek.widget {
        Some(widget) =>
          @base_browser.element_contains_active_element(widget.get_dom_node())
        None => false
      }
    None => false
  }
}

///|
fn Viewer::start_peek_definition(self : Viewer) -> Unit {
  guard self.definition_peek_available() else { return }
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.definition_command_position() is Some(position) else { return }
  let position = model.validate_position(position)
  let anchor = self.definition_peek_anchor(model, position)
  if self.definition_peek_anchor_is_open(anchor) {
    self.close_definition_peek(restore_focus=true)
    return
  }
  guard self.begin_definition_peek(position, anchor) is Some(generation) else {
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
    if !self.definition_peek_request_is_current(stamp, source) {
      state.peek.retire_definition_source(source, cancel=true)
      return
    }
    source.dispose()
    state.peek.definition_source = None
    self.install_definition_peek_locations(
      generation,
      position,
      @definition.normalize_definition_locations(locations),
    )
  })
}

///|
/// Populates Peek from locations already resolved by the ordinary Definition
/// action. This preserves the one-provider-query contract for the default
/// multiple-definition Peek policy.
fn Viewer::open_definition_peek_with_locations(
  self : Viewer,
  position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.definition_peek_available() else { return }
  guard self.get_model() is Some(model) else { return }
  let position = model.validate_position(position)
  let anchor = self.definition_peek_anchor(model, position)
  if self.definition_peek_anchor_is_open(anchor) {
    self.close_definition_peek(restore_focus=true)
    return
  }
  guard self.begin_definition_peek(position, anchor) is Some(generation) else {
    return
  }
  self.install_definition_peek_locations(generation, position, locations)
}

///|
fn Viewer::definition_peek_anchor(
  self : Viewer,
  model : @model.TextModel,
  position : @base_common.Position,
) -> DefinitionPeekAnchor {
  {
    model_identity: model.identity(),
    model_generation: self.model_slot.generation,
    model_version_id: model.get_version_id(),
    position,
  }
}

///|
fn Viewer::definition_peek_anchor_is_open(
  self : Viewer,
  anchor : DefinitionPeekAnchor,
) -> Bool {
  match self.definition_contribution() {
    Some(state) =>
      state.peek.anchor == Some(anchor) && state.peek.widget is Some(_)
    None => false
  }
}

///|
fn Viewer::begin_definition_peek(
  self : Viewer,
  position : @base_common.Position,
  anchor : DefinitionPeekAnchor,
) -> Int? {
  guard self.definition_contribution() is Some(state) else { return None }
  self.close_definition_peek(restore_focus=false)
  self.clear_definition_message()
  state.invalidate_open_feedback()
  state.cancel_action()
  if self.current_markdown_document() is Some(_) {
    // The pointer-derived source position is the Markdown equivalent of the
    // Code cursor anchor and must survive focus transfer into the Peek shell.
    state.cancel_link_gesture()
  } else {
    state.reset_link_gesture()
  }
  state.peek.generation += 1
  let generation = state.peek.generation
  state.peek.anchor = Some(anchor)
  guard self.open_definition_peek_shell(position, generation) else {
    state.peek.anchor = None
    self.show_definition_message("No preview available")
    return None
  }
  Some(generation)
}

///|
fn compare_definition_location_for_peek(
  left : @language.Location,
  right : @language.Location,
) -> Int {
  let uri_order = left.uri.to_string().compare(right.uri.to_string())
  if uri_order != 0 {
    return uri_order
  }
  let left_range = left.range
  let right_range = right.range
  if left_range.start_line_number != right_range.start_line_number {
    return left_range.start_line_number - right_range.start_line_number
  }
  if left_range.start_column != right_range.start_column {
    return left_range.start_column - right_range.start_column
  }
  if left_range.end_line_number != right_range.end_line_number {
    return left_range.end_line_number - right_range.end_line_number
  }
  left_range.end_column - right_range.end_column
}

///|
fn definition_uri_common_prefix_length(left : String, right : String) -> Int {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  let limit = left_chars.length().min(right_chars.length())
  let mut length = 0
  while length < limit && left_chars[length] == right_chars[length] {
    length += 1
  }
  length
}

///|
fn definition_position_distance(
  left : @base_common.Position,
  right : @base_common.Position,
) -> Int {
  (left.line_number - right.line_number).abs() * 100 +
  (left.column - right.column).abs()
}

///|
fn nearest_definition_peek_index(
  locations : Array[@language.Location],
  source_uri : @base_common.Uri,
  source_position : @base_common.Position,
) -> Int {
  guard !locations.is_empty() else { return -1 }
  let source = source_uri.to_string()
  let mut best_index = 0
  let mut best_prefix = -1
  let mut best_distance = 0
  for index, location in locations {
    let prefix = definition_uri_common_prefix_length(
      location.uri.to_string(),
      source,
    )
    let distance = definition_position_distance(
      location.range.get_start_position(),
      source_position,
    )
    if prefix > best_prefix ||
      (prefix == best_prefix && distance < best_distance) {
      best_index = index
      best_prefix = prefix
      best_distance = distance
    }
  }
  best_index
}

///|
fn Viewer::install_definition_peek_locations(
  self : Viewer,
  generation : Int,
  source_position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.definition_peek_session_is_current(generation) else { return }
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(source_model) else { return }
  let locations = @definition.normalize_definition_locations(locations)
  locations.sort_by(compare_definition_location_for_peek)
  state.peek.locations = locations
  if locations.is_empty() {
    // Upstream stops before opening Peek when there are no references. The
    // local shell already exists while the async request runs, so retire it
    // before presenting the same non-destructive action feedback.
    self.close_definition_peek(restore_focus=true)
    self.show_definition_message("No definition found")
    return
  }
  let selected_index = nearest_definition_peek_index(
    locations,
    source_model.uri,
    source_position,
  )
  state.peek.selected_index = selected_index
  match state.peek.widget {
    Some(widget) => {
      widget.set_locations(locations, selected_index)
      widget.show_preview_loading()
    }
    None => return
  }
  self.load_definition_peek_preview(generation, selected_index)
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
      // ViewZones hide caller nodes from the accessibility tree while they
      // are generic layout whitespace. Peek is an interactive dialog, so its
      // owner explicitly opts the mounted node back in.
      widget.get_dom_node().remove_attribute("aria-hidden")
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
  state.peek.focus_frame = Some(
    @base_browser.schedule_at_next_animation_frame(
      () => {
        state.peek.focus_frame = None
        if self.definition_peek_session_is_current(generation) {
          widget.focus()
        }
      },
      // Viewer render runs at 100; focus runs later in the same native frame,
      // after a Code ViewZone has changed from display:none to display:block.
      priority=0,
    ),
  )
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
  model.get_version_id() == stamp.model_version_id
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
fn Viewer::cancel_definition_peek_preview_request(self : Viewer) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let source = state.peek.preview_source
  state.peek.preview_source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
/// Removes every installed preview owner slot without running callbacks.
fn Viewer::detach_installed_definition_peek_preview(
  self : Viewer,
) -> DetachedDefinitionPeekPreview? {
  guard self.definition_contribution() is Some(state) else { return None }
  let restore_focus = match state.peek.preview_viewer {
    Some(viewer) => viewer.has_text_focus()
    None => false
  }
  let detached : DetachedDefinitionPeekPreview = {
    viewer: state.peek.preview_viewer,
    reference: state.peek.preview_reference,
    layout_frame: state.peek.preview_layout_frame,
    resize_observer: state.peek.preview_resize_observer,
    restore_focus,
  }
  state.peek.preview_resize_observer = None
  state.peek.preview_layout_frame = None
  state.peek.preview_viewer = None
  state.peek.preview_reference = None
  Some(detached)
}

///|
/// Releases only the installed child and lease. A replacement request keeps
/// these alive until its own result is current and ready to commit.
fn Viewer::clear_installed_definition_peek_preview(self : Viewer) -> Bool {
  guard self.detach_installed_definition_peek_preview() is Some(detached) else {
    return false
  }
  let restore_focus = detached.restore_focus
  detached.dispose()
  restore_focus
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
  self.cancel_definition_peek_preview_request()
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
/// Defers the final child swap through the same Viewer-owned task host as
/// provider and resolver work. That keeps stale reference disposal ordered
/// with cancellation and prevents an unowned browser microtask from outliving
/// the Viewer's DOM realm.
#warnings("-unused_async")
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
  let task = state.launch_async_task
  task(async fn() noraise {
    if !self.definition_peek_preview_is_current(
        generation, preview_generation, model,
      ) {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    guard state.peek.widget is Some(widget) else {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    let restore_preview_focus = self.clear_installed_definition_peek_preview()
    let widget_changed = match state.peek.widget {
      Some(current_widget) => !physical_equal(current_widget, widget)
      None => true
    }
    if !self.definition_peek_preview_is_current(
        generation, preview_generation, model,
      ) ||
      widget_changed {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    state.peek.preview_reference = reference
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
    let start = range.get_start_position()
    preview.set_position(start, source="peekDefinition")
    preview.reveal_range_in_center_if_outside_viewport(
      Range(start.line_number, start.column, start.line_number, start.column),
    )
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
    if restore_preview_focus {
      preview.focus()
    }
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
  guard state.peek.widget is Some(widget) else { return }
  let had_preview_focus = self.clear_installed_definition_peek_preview()
  guard self.definition_peek_session_is_current(generation) &&
    state.peek.preview_generation == preview_generation &&
    state.peek.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return
  }
  state.peek.phase = PeekUnavailable(generation, preview_generation)
  widget.show_preview_unavailable(message)
  if had_preview_focus {
    widget.focus()
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
  guard self.get_model() is Some(model) else { return }
  let location = state.peek.locations[index]
  let model_identity = model.identity()
  let model_generation = self.model_slot.generation
  let model_version_id = model.get_version_id()
  let task = state.launch_async_task
  state.invalidate_open_feedback()
  let open_generation = state.open_generation
  self.close_definition_peek(restore_focus=true)
  task(async fn() noraise {
    guard !self.disposed &&
      state.open_generation == open_generation &&
      self.get_model() is Some(current_model) &&
      current_model.identity() == model_identity &&
      self.model_slot.generation == model_generation &&
      current_model.get_version_id() == model_version_id else {
      return
    }
    self.open_definition_location(location, Current) |> ignore
  })
}

///|
fn Viewer::close_definition_peek(self : Viewer, restore_focus~ : Bool) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let peek = state.peek
  peek.generation += 1
  let closing_generation = peek.generation
  peek.preview_generation += 1
  peek.phase = PeekClosed

  // Detach the complete old session before the first cancellation/disposal
  // callback. Any callback may synchronously open a new Peek; teardown below
  // must then touch only these captured old resources.
  let definition_source = peek.definition_source
  peek.definition_source = None
  let preview_source = peek.preview_source
  peek.preview_source = None
  let focus_frame = peek.focus_frame
  peek.focus_frame = None
  let widget = peek.widget
  peek.widget = None
  let zone_id = peek.zone_id
  peek.zone_id = None
  let markdown_projection_generation = peek.markdown_projection_generation
  peek.markdown_projection_generation = None
  let detached_preview = self.detach_installed_definition_peek_preview()
  peek.locations = []
  peek.selected_index = -1
  peek.anchor = None

  match definition_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  match preview_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  match focus_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  // The nested Viewer and its model lease are children of the shell. Release
  // them while the shell listeners and host node are still alive.
  match detached_preview {
    Some(detached) => detached.dispose()
    None => ()
  }
  match widget {
    Some(widget) => widget.dispose()
    None => ()
  }
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
  if restore_focus &&
    !self.disposed &&
    peek.generation == closing_generation &&
    peek.phase == PeekClosed &&
    peek.widget is None {
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
