///|
priv struct DefinitionPeekRequestStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
}

///|
/// Preview resources detached atomically from the shared References state before any
/// cancellation or disposal callback can re-enter the Viewer.
priv struct DetachedReferencesPeekPreview {
  viewer : Viewer?
  reference : @navigation_api.TextModelReference?
  layout_frame : @base_common.Disposable?
  resize_observer : @base_common.Disposable?
  restore_focus : Bool
}

///|
fn DetachedReferencesPeekPreview::dispose(
  self : DetachedReferencesPeekPreview,
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
fn ReferencesContributionState::retire_preview_source(
  self : ReferencesContributionState,
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
  match self.references_contribution() {
    Some(state) =>
      match state.widget {
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
  guard self.definition_contribution() is Some(definition) else { return }
  guard self.references_contribution() is Some(references) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.definition_command_position() is Some(position) else { return }
  let position = model.validate_position(position)
  let session_key = @references.ReferencesSessionKey::from_model(
    model,
    self.model_slot.generation,
    position,
  )
  if self.references_peek_session_is_open(session_key, Definitions) {
    self.close_references_peek(restore_focus=true)
    return
  }
  guard self.begin_definition_peek(position, session_key) is Some(generation) else {
    return
  }
  let source = @language.CancellationTokenSource()
  definition.peek_source = Some(source)
  references.phase = PeekLoadingDefinitions(generation)
  let stamp : DefinitionPeekRequestStamp = {
    generation,
    model_identity: model.identity(),
    model_generation: self.model_slot.generation,
    model_version_id: model.get_version_id(),
  }
  let offset = model.get_offset_at(position)
  let task = definition.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    if !self.definition_peek_request_is_current(stamp, source) {
      definition.retire_peek_source(source, cancel=true)
      return
    }
    source.dispose()
    definition.peek_source = None
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
  let session_key = @references.ReferencesSessionKey::from_model(
    model,
    self.model_slot.generation,
    position,
  )
  if self.references_peek_session_is_open(session_key, Definitions) {
    self.close_references_peek(restore_focus=true)
    return
  }
  guard self.begin_definition_peek(position, session_key) is Some(generation) else {
    return
  }
  self.install_definition_peek_locations(generation, position, locations)
}

///|
fn Viewer::references_peek_session_is_open(
  self : Viewer,
  session_key : @references.ReferencesSessionKey,
  mode : @references.ReferencesPeekMode,
) -> Bool {
  match self.references_contribution() {
    Some(state) =>
      state.session_key == Some(session_key) &&
      state.mode == Some(mode) &&
      state.widget is Some(_)
    None => false
  }
}

///|
fn Viewer::begin_definition_peek(
  self : Viewer,
  position : @base_common.Position,
  session_key : @references.ReferencesSessionKey,
) -> Int? {
  guard self.definition_contribution() is Some(definition) else { return None }
  guard self.references_contribution() is Some(references) else { return None }
  self.close_references_peek(restore_focus=false)
  self.clear_definition_message()
  definition.invalidate_open_feedback()
  definition.cancel_action()
  if self.current_markdown_document() is Some(_) {
    // The pointer-derived source position is the Markdown equivalent of the
    // Code cursor anchor and must survive focus transfer into the Peek shell.
    definition.cancel_link_gesture()
  } else {
    definition.reset_link_gesture()
  }
  references.generation += 1
  let generation = references.generation
  references.mode = Some(Definitions)
  references.session_key = Some(session_key)
  guard self.open_definition_peek_shell(position, generation) else {
    references.mode = None
    references.session_key = None
    self.show_definition_message("No preview available", position~)
    return None
  }
  Some(generation)
}

///|
fn Viewer::install_definition_peek_locations(
  self : Viewer,
  generation : Int,
  source_position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.definition_peek_session_is_current(generation) else { return }
  guard self.references_contribution() is Some(state) else { return }
  guard self.get_model() is Some(source_model) else { return }
  let result_model = @references.ReferencesModel(locations)
  state.model = Some(result_model)
  if result_model.is_empty() {
    // Upstream stops before opening Peek when there are no references. The
    // local shell already exists while the async request runs, so retire it
    // before presenting the same non-destructive action feedback.
    self.close_references_peek(restore_focus=true)
    self.show_definition_message(
      self.definition_no_result_message(source_position),
      position=source_position,
    )
    return
  }
  guard result_model.nearest_reference(source_model.uri, source_position)
    is Some(selected) else {
    return
  }
  let selected_index = selected.flat_index
  state.selected_index = selected_index
  match state.widget {
    Some(widget) => {
      widget.set_results(result_model, Some(selected))
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
  guard self.references_contribution() is Some(state) else { return false }
  let widget = @references_browser.ReferencesPeekWidget(Definitions, {
    on_close: () => self.close_references_peek(restore_focus=true),
    on_select: item => self.select_definition_peek_item(item),
    on_confirm: item => {
      if self.references_peek_item_is_current(item) {
        self.confirm_definition_peek_result(item.flat_index)
      }
    },
    on_open_side: item => self.confirm_definition_peek_item(item, Side),
    on_next: () => self.move_definition_peek_result(1),
    on_previous: () => self.move_definition_peek_result(-1),
    on_expand_group: _group => (),
  })
  match self.current_code_browser_data() {
    Some(_) => {
      let zone_dom_node = @rdom.document().create_element("div")
      zone_dom_node.set_attribute(
        "class", "moonbit-viewer-references-peek-zone",
      )
      let widget_dom_node = widget.get_dom_node()
      let layout = self.get_layout_info()
      @base_browser.set_style_property(widget_dom_node, "position", "absolute")
      @base_browser.set_style_property(widget_dom_node, "top", "-1000000px")
      @base_browser.set_style_property(widget_dom_node, "left", "0")
      @base_browser.set_style_property(
        widget_dom_node,
        "right",
        "\{layout.vertical_scrollbar_width.to_string()}px",
      )
      @base_browser.set_style_property(widget_dom_node, "width", "auto")
      let zone = @editor_browser.ViewZone(
        position.line_number,
        zone_dom_node,
        after_column=position.column,
        suppress_mouse_down=true,
        height_in_lines=self.references_peek_height_in_lines(),
        on_dom_node_top=top => {
          @base_browser.set_style_property(
            widget_dom_node,
            "top",
            "\{top.to_string()}px",
          )
        },
        on_computed_height=height => {
          @base_browser.set_style_property(
            widget_dom_node,
            "height",
            "\{height.to_string()}px",
          )
        },
      )
      let added_id = Ref("")
      self.change_view_zones(accessor => added_id.val = accessor.add_zone(zone))
      if added_id.val == "" {
        widget.dispose()
        return false
      }
      state.zone_id = Some(added_id.val)
      let overlay = overlay_widget(
        "moonbit.viewer.referencesPeek.\{self.get_id()}",
        widget_dom_node,
      )
      self.add_overlay_widget(overlay)
      state.overlay_widget = Some(overlay)
      self.reveal_definition_peek_zone(position)
    }
    None =>
      match self.current_markdown_document() {
        Some(markdown) => {
          widget
          .get_dom_node()
          .set_attribute(
            "class", "moonbit-viewer-references-peek moonbit-viewer-references-peek-overlay",
          )
          markdown.overlay_mount().append_child(widget.get_dom_node().as_node())
          state.markdown_projection_generation = Some(
            markdown.projection_generation(),
          )
        }
        None => {
          widget.dispose()
          return false
        }
      }
  }
  state.widget = Some(widget)
  state.focus_frame = Some(
    @base_browser.schedule_at_next_animation_frame(
      () => {
        state.focus_frame = None
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
/// Mirrors `ZoneWidget.show`: reveal the anchor through the following model
/// line after installing the whitespace. The range crosses the Peek ViewZone,
/// so the scroll computation brings the whole widget into the viewport instead
/// of leaving a newly opened shell clipped below the editor.
fn Viewer::reveal_definition_peek_zone(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  guard self.get_model() is Some(model) else { return }
  let line_number = position.line_number
  let end_line_number = (line_number + 1).min(model.get_line_count())
  if end_line_number == line_number {
    self.reveal_line_near_top(line_number)
  } else {
    self.reveal_lines(line_number, end_line_number)
  }
}

///|
fn Viewer::references_peek_height_in_lines(self : Viewer) -> Double {
  let snapshot = self.configuration.snapshot()
  let requested = @references_browser.references_peek_height_in_lines.to_double()
  let line_height = snapshot.font_info.line_height.to_double()
  if snapshot.height <= 0.0 || line_height <= 0.0 {
    return requested
  }
  requested.min((snapshot.height / line_height * 0.8).max(12.0))
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
  guard self.definition_contribution() is Some(definition) else { return false }
  guard self.references_contribution() is Some(references) else { return false }
  guard references.generation == stamp.generation else { return false }
  guard definition.peek_source is Some(current_source) else { return false }
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
  guard self.references_contribution() is Some(state) else { return false }
  guard state.generation == generation && state.widget is Some(_) else {
    return false
  }
  guard state.session_key is Some(session_key) &&
    self.get_model() is Some(source_model) &&
    session_key.is_current(source_model, self.model_slot.generation) else {
    return false
  }
  match
    (state.zone_id, state.overlay_widget, state.markdown_projection_generation) {
    (Some(_), Some(_), None) => self.current_code_browser_data() is Some(_)
    (None, None, Some(projection_generation)) =>
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
  guard self.references_contribution() is Some(state) else { return }
  let source = state.preview_source
  state.preview_source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
/// Removes every installed preview owner slot without running callbacks.
fn Viewer::detach_installed_definition_peek_preview(
  self : Viewer,
) -> DetachedReferencesPeekPreview? {
  guard self.references_contribution() is Some(state) else { return None }
  let restore_focus = match state.preview_viewer {
    Some(viewer) => viewer.has_text_focus()
    None => false
  }
  let detached : DetachedReferencesPeekPreview = {
    viewer: state.preview_viewer,
    reference: state.preview_reference,
    layout_frame: state.preview_layout_frame,
    resize_observer: state.preview_resize_observer,
    restore_focus,
  }
  state.preview_resize_observer = None
  state.preview_layout_frame = None
  state.preview_viewer = None
  state.preview_reference = None
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
  guard self.references_contribution() is Some(state) else { return }
  guard self.definition_peek_session_is_current(generation) else { return }
  guard state.model is Some(result_model) else { return }
  guard index >= 0 && index < result_model.references.length() else { return }
  self.cancel_definition_peek_preview_request()
  state.selected_index = index
  match state.widget {
    Some(widget) => {
      widget.set_selected(result_model.references[index])
      widget.show_preview_loading()
    }
    None => return
  }
  let location = result_model.references[index].location()
  state.preview_generation += 1
  let preview_generation = state.preview_generation
  state.phase = PeekLoadingPreview(generation, preview_generation)
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
  state.preview_source = Some(source)
  let task = state.launch_async_task
  task(async fn() noraise {
    let reference = resolver.resolve(location.uri, source.token())
    if !self.definition_peek_preview_request_is_current(
        generation, preview_generation, source,
      ) {
      state.retire_preview_source(source, cancel=true)
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    source.dispose()
    state.preview_source = None
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
  guard self.references_contribution() is Some(state) else { return false }
  guard state.preview_generation == preview_generation else { return false }
  match state.preview_source {
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
  guard self.references_contribution() is Some(state) else {
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
    guard state.widget is Some(widget) else {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    let restore_preview_focus = self.clear_installed_definition_peek_preview()
    let widget_changed = match state.widget {
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
    state.preview_reference = reference
    let preview_host = widget.get_preview_host()
    let preview = Viewer(
      services=self.services,
      options=self.get_options(),
      initial_container=preview_host,
      role=PeekPreviewViewer,
    )
    preview.attach(preview_host)
    state.preview_viewer = Some(preview)
    preview.set_model(Some(model))
    let range = model.validate_range(location.range)
    preview.create_decorations_collection(decorations=[
      {
        range,
        options: ModelDecorationOptions(
          "moonbit-viewer-references-peek-reference-match-selected",
          description="peek-definition-match",
        ),
      },
    ])
    |> ignore
    let start = range.get_start_position()
    preview.set_position(start, source="peekDefinition")
    preview.reveal_range_in_center_if_outside_viewport(
      Range(start.line_number, start.column, start.line_number, start.column),
    )
    preview.handle_initialized()
    state.preview_resize_observer = @base_browser.observe_element_resize(
      preview_host,
      () => {
        if self.definition_peek_preview_is_current(
            generation, preview_generation, model,
          ) {
          preview.layout()
        }
      },
    )
    state.preview_layout_frame = Some(
      @base_browser.schedule_at_next_animation_frame(() => {
        if self.definition_peek_preview_is_current(
            generation, preview_generation, model,
          ) {
          preview.layout()
        }
      }),
    )
    widget.show_preview_ready()
    state.phase = PeekShown(generation, preview_generation)
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
  guard self.references_contribution() is Some(state) else { return false }
  state.preview_generation == preview_generation
}

///|
fn Viewer::show_definition_peek_preview_unavailable(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  message : String,
) -> Unit {
  guard self.definition_peek_session_is_current(generation) else { return }
  guard self.references_contribution() is Some(state) else { return }
  guard state.preview_generation == preview_generation else { return }
  guard state.widget is Some(widget) else { return }
  let had_preview_focus = self.clear_installed_definition_peek_preview()
  guard self.definition_peek_session_is_current(generation) &&
    state.preview_generation == preview_generation &&
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return
  }
  state.phase = PeekUnavailable(generation, preview_generation)
  widget.show_preview_unavailable(message)
  if had_preview_focus {
    widget.focus()
  }
}

///|
fn Viewer::references_peek_item_is_current(
  self : Viewer,
  item : @references.ReferenceItem,
) -> Bool {
  match self.references_contribution() {
    Some(state) =>
      match state.model {
        Some(model) =>
          item.flat_index >= 0 &&
          item.flat_index < model.references.length() &&
          model.references[item.flat_index] == item
        None => false
      }
    None => false
  }
}

///|
fn Viewer::select_definition_peek_item(
  self : Viewer,
  item : @references.ReferenceItem,
) -> Unit {
  if self.references_peek_item_is_current(item) {
    self.select_definition_peek_result(item.flat_index)
  }
}

///|
fn Viewer::select_definition_peek_result(self : Viewer, index : Int) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  guard state.model is Some(result_model) else { return }
  let generation = state.generation
  guard index >= 0 && index < result_model.references.length() else { return }
  if index == state.selected_index &&
    (state.preview_viewer is Some(_) || state.preview_source is Some(_)) {
    return
  }
  self.load_definition_peek_preview(generation, index)
}

///|
fn Viewer::move_definition_peek_result(self : Viewer, delta : Int) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  guard state.model is Some(result_model) else { return }
  guard result_model.references.length() > 0 else { return }
  let current = if state.selected_index >= 0 &&
    state.selected_index < result_model.references.length() {
    result_model.references[state.selected_index]
  } else {
    result_model.references[0]
  }
  let next = if delta < 0 {
    result_model.previous_reference(current)
  } else {
    result_model.next_reference(current)
  }
  match next {
    Some(item) => self.select_definition_peek_item(item)
    None => ()
  }
}

///|
fn Viewer::confirm_definition_peek_result(self : Viewer, index : Int) -> Unit {
  guard self.references_contribution() is Some(references) else { return }
  guard references.model is Some(result_model) else { return }
  guard index >= 0 && index < result_model.references.length() else { return }
  self.confirm_definition_peek_item(result_model.references[index], Current)
}

///|
fn Viewer::confirm_definition_peek_item(
  self : Viewer,
  item : @references.ReferenceItem,
  mode : @navigation_api.OpenLocationMode,
) -> Unit {
  guard self.references_peek_item_is_current(item) else { return }
  guard self.definition_contribution() is Some(definition) else { return }
  guard self.get_model() is Some(model) else { return }
  let location = item.location()
  let model_identity = model.identity()
  let model_generation = self.model_slot.generation
  let model_version_id = model.get_version_id()
  let task = definition.launch_async_task
  definition.invalidate_open_feedback()
  let open_generation = definition.open_generation
  self.close_references_peek(restore_focus=true)
  task(async fn() noraise {
    guard !self.disposed &&
      definition.open_generation == open_generation &&
      self.get_model() is Some(current_model) &&
      current_model.identity() == model_identity &&
      self.model_slot.generation == model_generation &&
      current_model.get_version_id() == model_version_id else {
      return
    }
    self.open_definition_location(location, mode) |> ignore
  })
}

///|
fn Viewer::close_references_peek(self : Viewer, restore_focus~ : Bool) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  state.generation += 1
  let closing_generation = state.generation
  state.preview_generation += 1
  state.phase = PeekClosed

  // Detach the complete old session before the first cancellation/disposal
  // callback. Any callback may synchronously open a new Peek; teardown below
  // must then touch only these captured old resources.
  let definition_source = match self.definition_contribution() {
    Some(definition) => {
      let source = definition.peek_source
      definition.peek_source = None
      source
    }
    None => None
  }
  let preview_source = state.preview_source
  state.preview_source = None
  let focus_frame = state.focus_frame
  state.focus_frame = None
  let widget = state.widget
  state.widget = None
  let zone_id = state.zone_id
  state.zone_id = None
  let overlay_widget = state.overlay_widget
  state.overlay_widget = None
  let markdown_projection_generation = state.markdown_projection_generation
  state.markdown_projection_generation = None
  let detached_preview = self.detach_installed_definition_peek_preview()
  state.model = None
  state.selected_index = -1
  state.mode = None
  state.session_key = None

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
  match overlay_widget {
    Some(overlay_widget) => self.remove_overlay_widget(overlay_widget)
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
  if restore_focus &&
    !self.disposed &&
    state.generation == closing_generation &&
    state.phase == PeekClosed &&
    state.widget is None {
    self.focus()
  }
}

///|
fn Viewer::close_definition_peek(self : Viewer, restore_focus~ : Bool) -> Unit {
  self.close_references_peek(restore_focus~)
}

///|
fn Viewer::definition_peek_phase_for_test(
  self : Viewer,
) -> @references.ReferencesPeekPhase {
  match self.references_contribution() {
    Some(state) => state.phase
    None => PeekClosed
  }
}

///|
let _definition_peek_test_seam_anchor : Unit = ignore(
  Viewer::definition_peek_phase_for_test,
)
