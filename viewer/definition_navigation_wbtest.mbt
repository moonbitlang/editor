///|
priv struct DefinitionNavigationTestProvider {
  locations : Array[@language.Location]
}

///|
impl @language.DefinitionProvider for DefinitionNavigationTestProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  self.locations.copy()
}

///|
priv struct SequencedDefinitionProvider {
  responses : Array[Array[@language.Location]]
  calls : Ref[Int]
}

///|
impl @language.DefinitionProvider for SequencedDefinitionProvider with fn provide_definition(
  self,
  _model,
  _position,
  _token,
) {
  let index = self.calls.val
  self.calls.val += 1
  if index < self.responses.length() {
    self.responses[index].copy()
  } else {
    []
  }
}

///|
priv struct ManualDefinitionTasks {
  tasks : Array[async () -> Unit noraise]
}

///|
fn ManualDefinitionTasks::ManualDefinitionTasks() -> ManualDefinitionTasks {
  { tasks: [] }
}

///|
fn ManualDefinitionTasks::schedule(
  self : ManualDefinitionTasks,
  task : async () -> Unit noraise,
) -> Unit {
  self.tasks.push(task)
}

///|
async fn ManualDefinitionTasks::run_next(
  self : ManualDefinitionTasks,
) -> Unit noraise {
  guard !self.tasks.is_empty() else { return }
  let task = self.tasks.remove(0)
  task()
}

///|
fn definition_navigation_test_model(resource : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::parse(resource),
    "source.mbt",
    "moonbit",
    1,
    "revision-1",
    "let source = target\n",
  )
}

///|
fn definition_navigation_services(
  locations : Array[@language.Location],
  opener? : @navigation_api.LocationOpenerHandle,
  resolver? : @navigation_api.TextModelResolverHandle,
) -> ViewerServices {
  let languages = @languages.Languages()
  let provider = DefinitionNavigationTestProvider::{ locations, }
  languages.register_definition_provider(LanguageId("moonbit"), provider)
  |> ignore
  let log_service = @log.LogService()
  ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    location_opener?=opener,
    text_model_resolver?=resolver,
    log_service=log_service.log_handle(),
  )
}

///|
test "cancellation callbacks cannot clobber replacement request owners" {
  let services = definition_navigation_services([])
  let viewer = Viewer(services~)
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }

  let old_action = @language.CancellationTokenSource()
  let new_action = @language.CancellationTokenSource()
  old_action
  .token()
  .on_cancellation_requested(() => state.action_source = Some(new_action))
  |> ignore
  state.action_source = Some(old_action)
  state.cancel_action()
  guard state.action_source is Some(current_action) else {
    fail("action cancellation clobbered its replacement owner")
  }
  assert_true(physical_equal(current_action, new_action))

  let old_link = @language.CancellationTokenSource()
  let new_link = @language.CancellationTokenSource()
  old_link
  .token()
  .on_cancellation_requested(() => state.link_source = Some(new_link))
  |> ignore
  state.link_source = Some(old_link)
  state.cancel_link()
  guard state.link_source is Some(current_link) else {
    fail("link cancellation clobbered its replacement owner")
  }
  assert_true(physical_equal(current_link, new_link))

  let old_preview = @language.CancellationTokenSource()
  let new_preview = @language.CancellationTokenSource()
  old_preview
  .token()
  .on_cancellation_requested(() => state.peek.preview_source = Some(new_preview))
  |> ignore
  state.peek.preview_source = Some(old_preview)
  viewer.cancel_definition_peek_preview_request()
  guard state.peek.preview_source is Some(current_preview) else {
    fail("preview cancellation clobbered its replacement owner")
  }
  assert_true(physical_equal(current_preview, new_preview))

  let old_definitions = @language.CancellationTokenSource()
  let new_definitions = @language.CancellationTokenSource()
  old_definitions
  .token()
  .on_cancellation_requested(() => {
    state.peek.definition_source = Some(new_definitions)
  })
  |> ignore
  state.peek.definition_source = Some(old_definitions)
  viewer.close_definition_peek(restore_focus=false)
  guard state.peek.definition_source is Some(current_definitions) else {
    fail("Peek cancellation clobbered its replacement owner")
  }
  assert_true(physical_equal(current_definitions, new_definitions))

  new_action.dispose(cancel=true)
  new_link.dispose(cancel=true)
  new_preview.dispose(cancel=true)
  new_definitions.dispose(cancel=true)
  state.action_source = None
  state.link_source = None
  state.peek.preview_source = None
  state.peek.definition_source = None
  viewer.dispose()
  services.dispose()
}

///|
async test "F12 reveals a same-resource definition without calling the opener" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let location : @language.Location = {
    uri: model.uri,
    range: Range(1, 14, 1, 20),
  }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 5))

  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=false, shift=false),
  )
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(viewer.get_position(), Some(Position(1, 14)))
  assert_eq(opener_calls.val, 0)
  assert_true(viewer.definition_message_for_test() is None)
  let highlights = viewer
    .get_line_decorations(1)
    .filter(decoration => decoration.options.class_name == "symbolHighlight")
  assert_eq(highlights.length(), 1)
  assert_eq(highlights[0].range, location.range)
  assert_eq(
    highlights[0].options.description,
    "symbol-navigate-action-highlight",
  )

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "headless multiple definitions retain provider-first fallback" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let provider_first = try! @base_common.Uri::parse(
    "file:///provider-first.mbt",
  )
  let requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    requests.push(request)
    true
  })
  let services = definition_navigation_services(
    [
      { uri: provider_first, range: Range(8, 2, 8, 6) },
      { uri: model.uri, range: Range(1, 14, 1, 20) },
    ],
    opener~,
  )
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 5))
  viewer.start_goto_definition()
  tasks.run_next()
  assert_eq(requests.length(), 1)
  assert_eq(requests[0].location.uri.to_string(), provider_first.to_string())

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "F12 sends a cross-resource request and preserves rejection feedback" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(4, 2, 4, 8) }
  let requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    requests.push(request)
    false
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 5))

  assert_true(
    viewer.handle_editor_key_down("F12", alt=false, ctrl_cmd=true, shift=false),
  )
  tasks.run_next()
  assert_eq(requests.length(), 1)
  assert_eq(requests[0].source_viewer_id, viewer.get_id())
  assert_eq(requests[0].location.uri.to_string(), target.to_string())
  assert_eq(requests[0].mode, Current)
  assert_eq(
    viewer.definition_message_for_test(),
    Some("Unable to open definition"),
  )

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "a superseded definition opener failure cannot overwrite a newer navigation" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(4, 2, 4, 8) }
  let calls = Ref(0)
  let first_started = @async.Semaphore(1, initial_value=0)
  let release_first = @async.Semaphore(1, initial_value=0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    let call = calls.val
    calls.val += 1
    if call == 0 {
      first_started.release()
      release_first.acquire() catch {
        _ => return false
      }
      false
    } else {
      true
    }
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 5))

  @async.with_task_group() <| group => {
    viewer.start_goto_definition()
    let first = group.spawn(() => tasks.run_next())
    first_started.acquire()

    viewer.start_goto_definition()
    // Merely starting B is enough to stale A's feedback; B's provider/opener
    // has not run yet.
    release_first.release()
    first.wait()
    assert_true(viewer.definition_message_for_test() is None)

    let second = group.spawn(() => tasks.run_next())
    second.wait()
    assert_eq(calls.val, 2)
  }
  assert_true(viewer.definition_message_for_test() is None)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "cursor movement suppresses late definition opener failure" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(4, 2, 4, 8) }
  let started = @async.Semaphore(1, initial_value=0)
  let release = @async.Semaphore(1, initial_value=0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    started.release()
    release.acquire() catch {
      _ => return false
    }
    false
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 5))

  @async.with_task_group() <| group => {
    viewer.start_goto_definition()
    let request = group.spawn(() => tasks.run_next())
    started.acquire()
    viewer.set_position(Position(1, 6))
    release.release()
    request.wait()
  }
  assert_true(viewer.definition_message_for_test() is None)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "empty and stale definition actions cannot navigate" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = { uri: target, range: Range(1, 1, 1, 2) }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  viewer.start_goto_definition()
  viewer.set_value("let source = changed\n")
  tasks.run_next()
  assert_eq(opener_calls.val, 0)
  assert_true(viewer.definition_message_for_test() is None)

  viewer.set_position(Position(1, 5))
  viewer.start_goto_definition()
  guard viewer.definition_contribution() is Some(action_state) else {
    fail("missing definition contribution")
  }
  guard action_state.action_source is Some(action_source) else {
    fail("F12 did not retain its cancellation source")
  }
  viewer.set_position(Position(1, 6))
  assert_true(action_source.token().is_cancellation_requested())
  assert_true(action_state.action_source is None)
  tasks.run_next()
  assert_eq(opener_calls.val, 0)

  let empty_services = definition_navigation_services([], opener~)
  let empty_viewer = Viewer(services=empty_services)
  let empty_tasks = ManualDefinitionTasks()
  empty_viewer.set_definition_host_for_test(task => empty_tasks.schedule(task))
  let empty_model = definition_navigation_test_model("file:///empty.mbt")
  empty_viewer.set_model(Some(empty_model))
  empty_viewer.start_goto_definition()
  empty_tasks.run_next()
  assert_eq(
    empty_viewer.definition_message_for_test(),
    Some("No definition found for 'let'"),
  )

  viewer.dispose()
  empty_viewer.dispose()
  services.dispose()
  empty_services.dispose()
  model.dispose()
  empty_model.dispose()
}

///|
async test "empty definition-link result is cached silently for one gesture" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let word = model.get_word_at_position(position).unwrap()
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    word,
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  match state.link_state {
    LinkResolvedEmpty(stamp) => assert_eq(stamp.target, target)
    _ => fail("empty link result was not cached")
  }
  assert_true(viewer.definition_message_for_test() is None)
  viewer.start_definition_link_request(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 0)
  assert_eq(state.link_decorations.length(), 0)

  viewer.reset_definition_link()
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "definition-link trigger is the exact platform CtrlCmd modifier" {
  assert_false(definition_link_modifier_is_active(false, false, false, false))
  assert_false(definition_link_modifier_is_active(true, true, false, false))
  assert_false(
    definition_link_modifier_is_active(
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      true,
      false,
    ),
  )
  assert_false(
    definition_link_modifier_is_active(
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      true,
    ),
  )
  assert_true(
    definition_link_modifier_is_active(
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
}

///|
async test "definition-link arms only a fresh token and stale content clears it" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let location : @language.Location = {
    uri: try! @base_common.Uri::parse("file:///target.mbt"),
    range: Range(3, 2, 3, 8),
  }
  let services = definition_navigation_services([location])
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let word = model.get_word_at_position(position).unwrap()
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    word,
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  match state.link_state {
    LinkResolving(stamp) => assert_eq(stamp.target, target)
    _ => fail("link did not enter resolving state")
  }
  tasks.run_next()
  match state.link_state {
    LinkArmed(stamp, locations) => {
      assert_eq(stamp.target, target)
      assert_eq(locations.length(), 1)
      assert_eq(locations[0].uri.to_string(), "file:///target.mbt")
    }
    _ => fail("fresh resolved link was not armed")
  }
  assert_eq(state.link_decorations.length(), 1)
  assert_eq(state.link_decorations.get_range(0), Some(target.word_range))

  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  // The already-armed exact target is cached and does not issue a duplicate.
  assert_eq(tasks.tasks.length(), 0)
  state.cancel_link()
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  viewer.set_value("let source = changed\n")
  assert_eq(state.link_decorations.length(), 0)
  match state.link_state {
    LinkIdle => ()
    _ => fail("content change did not reset the link gesture")
  }
  tasks.run_next()
  match state.link_state {
    LinkIdle => ()
    _ => fail("late link result re-armed stale content")
  }

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "definition-link caches by word and executes a fresh Definition action" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let preview_uri = try! @base_common.Uri::parse("file:///preview-result.mbt")
  let action_uri = try! @base_common.Uri::parse("file:///action-result.mbt")
  let calls = Ref(0)
  let languages = @languages.Languages()
  languages.register_definition_provider(LanguageId("moonbit"), SequencedDefinitionProvider::{
    responses: [
      [{ uri: preview_uri, range: Range(2, 1, 2, 4) }],
      [{ uri: action_uri, range: Range(7, 3, 7, 9) }],
    ],
    calls,
  })
  |> ignore
  let requests : Array[@navigation_api.OpenLocationRequest] = []
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    requests.push(request)
    true
  })
  let log_service = @log.LogService()
  let services = ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    location_opener=opener,
    log_service=log_service.log_handle(),
  )
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let first_position = @base_common.Position(1, 14)
  let second_position = @base_common.Position(1, 18)
  let first_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    first_position,
    model.get_word_at_position(first_position).unwrap(),
  )
  let second_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    second_position,
    model.get_word_at_position(second_position).unwrap(),
  )
  assert_true(first_target.same_word(second_target))
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(first_target)
  viewer.start_definition_link_request(first_target)
  assert_eq(tasks.tasks.length(), 1)
  viewer.handle_definition_pointer_move(
    Some(second_target),
    !@base_common.is_macintosh,
    @base_common.is_macintosh,
    false,
    false,
    0,
  )
  // Moving within the same word reuses the in-flight preview request.
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(calls.val, 1)
  match state.link_state {
    LinkArmed(stamp, locations) => {
      assert_true(stamp.target.same_word(second_target))
      assert_eq(locations[0].uri.to_string(), preview_uri.to_string())
    }
    _ => fail("definition link was not armed")
  }

  assert_true(viewer.before_definition_target_mouse_down(Some(second_target)))
  assert_true(
    viewer.handle_definition_pointer_up(
      Some(second_target),
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
  assert_false(state.link_modifier_down)
  assert_true(state.last_pointer_target is None)
  assert_eq(state.definition_mouse_down_line, 0)
  match state.link_state {
    LinkIdle => ()
    _ => fail("successful mouseup retained link-preview state")
  }
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(calls.val, 2)
  assert_eq(requests.length(), 1)
  assert_eq(requests[0].location.uri.to_string(), action_uri.to_string())

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "definition-link click does not wait for preview resolution" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = {
    uri: target_uri,
    range: Range(3, 2, 3, 6),
  }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = None
  viewer.start_definition_link_request(target)
  assert_eq(tasks.tasks.length(), 1)
  // Preview is still LinkResolving, so selection is not suppressed; the
  // independent click gesture nevertheless records a valid mouse-down line.
  state.link_modifier_down = false
  assert_false(viewer.before_definition_target_mouse_down(Some(target)))
  viewer.on_definition_cursor_selection_changed(true)
  assert_true(state.link_modifier_down)
  assert_eq(state.definition_mouse_down_line, target.position.line_number)
  match state.link_state {
    LinkIdle => ()
    _ => fail("selection change did not cancel the pending link preview")
  }
  assert_true(
    viewer.handle_definition_pointer_up(
      Some(target),
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
  assert_eq(tasks.tasks.length(), 2)
  tasks.run_next()
  assert_eq(opener_calls.val, 0)
  tasks.run_next()
  assert_eq(opener_calls.val, 1)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "drag selection cancels an unresolved definition-link click" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let location : @language.Location = {
    uri: target_uri,
    range: Range(3, 2, 3, 6),
  }
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services([location], opener~)
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  viewer.start_definition_link_request(target)
  assert_false(viewer.before_definition_target_mouse_down(Some(target)))
  viewer.on_definition_cursor_selection_changed(false)
  assert_false(state.link_modifier_down)
  assert_eq(state.definition_mouse_down_line, 0)
  assert_false(
    viewer.handle_definition_pointer_up(
      Some(target),
      !@base_common.is_macintosh,
      @base_common.is_macintosh,
      false,
      false,
    ),
  )
  // Only the cancelled preview task remains; mouseup did not enqueue a fresh
  // Definition action.
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(opener_calls.val, 0)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "plain definition pointer-up preserves the keyboard command anchor" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let viewer = Viewer(services~)
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.last_pointer_target = None
  state.definition_mouse_down_line = target.position.line_number
  assert_false(
    viewer.handle_definition_pointer_up(
      Some(target),
      false,
      false,
      false,
      false,
    ),
  )
  assert_eq(state.last_pointer_target, Some(target))
  assert_false(state.link_modifier_down)
  assert_eq(state.definition_mouse_down_line, 0)
  match state.link_state {
    LinkIdle => ()
    _ => fail("plain pointer-up retained transient link state")
  }

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async test "plain definition click cancels the previous pointer-anchored action" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services(
    [{ uri: target_uri, range: Range(3, 2, 3, 6) }],
    opener~,
  )
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let first_position = @base_common.Position(1, 5)
  let second_position = @base_common.Position(1, 14)
  let second_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    second_position,
    model.get_word_at_position(second_position).unwrap(),
  )

  viewer.start_goto_definition_at(first_position, mute_message=false)
  guard viewer.definition_contribution() is Some(state) &&
    state.action_source is Some(first_source) else {
    fail("first definition action was not pending")
  }
  viewer.commit_plain_definition_pointer_target(Some(second_target))
  assert_true(first_source.token().is_cancellation_requested())
  assert_eq(state.last_pointer_target, Some(second_target))
  tasks.run_next()
  assert_eq(opener_calls.val, 0)
  assert_true(viewer.definition_message_for_test() is None)

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "non-left definition mouseup does not replace the command anchor" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let viewer = Viewer(services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(model))
  let first_position = @base_common.Position(1, 5)
  let second_position = @base_common.Position(1, 14)
  let first_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    first_position,
    model.get_word_at_position(first_position).unwrap(),
  )
  let second_target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    second_position,
    model.get_word_at_position(second_position).unwrap(),
  )
  viewer.start_goto_definition_at(first_position, mute_message=false)
  guard viewer.definition_contribution() is Some(state) &&
    state.action_source is Some(source) else {
    fail("definition action was not pending")
  }
  state.last_pointer_target = Some(first_target)

  assert_false(
    viewer.handle_definition_pointer_up(
      Some(second_target),
      false,
      false,
      false,
      false,
      left_button=false,
      detail=1,
    ),
  )
  assert_false(source.token().is_cancellation_requested())
  assert_eq(state.last_pointer_target, Some(first_target))

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
test "definition-link modifier edges cancel unrelated CtrlCmd chords" {
  let model = definition_navigation_test_model("file:///source.mbt")
  let services = definition_navigation_services([])
  let viewer = Viewer(services~)
  viewer.set_model(Some(model))
  let position = @base_common.Position(1, 14)
  let target = @definition.DefinitionTargetFingerprint::from_model(
    model,
    viewer.model_slot.generation,
    position,
    model.get_word_at_position(position).unwrap(),
  )
  guard viewer.definition_contribution() is Some(state) else {
    fail("definition contribution was not installed")
  }
  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  state.definition_mouse_down_line = 1
  viewer.handle_definition_modifier_key(
    "K",
    true,
    !@base_common.is_macintosh,
    @base_common.is_macintosh,
    false,
    false,
  )
  assert_false(state.link_modifier_down)
  assert_eq(state.last_pointer_target, Some(target))
  assert_eq(state.definition_mouse_down_line, 0)

  state.link_modifier_down = true
  state.last_pointer_target = Some(target)
  viewer.handle_definition_modifier_key(
    if @base_common.is_macintosh {
      "Meta"
    } else {
      "Control"
    },
    false,
    false,
    false,
    false,
    false,
  )
  assert_false(state.link_modifier_down)
  assert_eq(state.last_pointer_target, Some(target))

  viewer.dispose()
  services.dispose()
  model.dispose()
}

///|
async fn run_same_resource_definition_peek_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let location : @language.Location = {
    uri: source.uri,
    range: Range(1, 14, 1, 20),
  }
  let services = definition_navigation_services([location])
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))

  assert_true(
    viewer.handle_editor_key_down("F12", alt=true, ctrl_cmd=false, shift=false),
  )
  match viewer.definition_peek_phase_for_test() {
    PeekLoadingDefinitions(_) => ()
    _ => fail("Alt F12 did not open the loading Peek shell")
  }
  guard viewer.definition_contribution() is Some(state) else {
    fail("missing definition contribution")
  }
  assert_true(state.peek.zone_id is Some(_))
  assert_true(state.peek.widget is Some(_))
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  match viewer.definition_peek_phase_for_test() {
    PeekShown(_, _) => ()
    _ => fail("same-resource preview did not mount")
  }
  guard state.peek.preview_viewer is Some(preview) else {
    fail("nested preview Viewer was not created")
  }
  assert_true(preview.get_model().unwrap().same(source))
  assert_true(preview.role == PeekPreviewViewer)
  assert_false(preview.definition_peek_available())
  assert_false(
    preview.handle_editor_key_down("F12", alt=true, ctrl_cmd=false, shift=false),
  )
  assert_eq(preview.get_position(), Some(Position(1, 14)))
  assert_true(state.peek.preview_reference is None)

  viewer.close_definition_peek(restore_focus=false)
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_true(preview.disposed)
  assert_true(state.peek.preview_viewer is None)
  assert_true(state.peek.zone_id is None)
  assert_false(source.is_disposed())

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_empty_definition_peek_test() -> Unit {
  let source = definition_navigation_test_model("file:///empty-peek.mbt")
  let services = definition_navigation_services([])
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))

  viewer.start_peek_definition()
  match viewer.definition_peek_phase_for_test() {
    PeekLoadingDefinitions(_) => ()
    _ => fail("empty Definition request did not enter loading Peek")
  }
  tasks.run_next()
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  guard viewer.definition_contribution() is Some(state) else {
    fail("missing definition contribution")
  }
  assert_true(state.peek.widget is None)
  assert_true(state.peek.zone_id is None)
  assert_eq(
    viewer.definition_message_for_test(),
    Some("No definition found for 'source'"),
  )

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_multiple_definition_default_peek_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let remote_uri = try! @base_common.Uri::parse("file:///remote.mbt")
  let locations : Array[@language.Location] = [
    { uri: remote_uri, range: Range(6, 3, 6, 9) },
    { uri: source.uri, range: Range(1, 14, 1, 20) },
  ]
  let services = definition_navigation_services(locations)
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 14))

  // F12 has already resolved both locations. The default multiple-result
  // policy populates Peek directly instead of issuing another provider task.
  viewer.start_goto_definition()
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 0)
  guard viewer.definition_contribution() is Some(state) else {
    fail("missing definition contribution")
  }
  match viewer.definition_peek_phase_for_test() {
    PeekShown(_, _) => ()
    _ => fail("multiple definitions did not open Peek")
  }
  assert_eq(state.peek.locations.length(), 2)
  assert_eq(state.peek.locations[0].uri.to_string(), remote_uri.to_string())
  assert_eq(state.peek.locations[1].uri.to_string(), source.uri.to_string())
  assert_eq(state.peek.selected_index, 1)
  assert_true(state.peek.preview_viewer is Some(_))

  // Alt+F12 at the same model/version/position toggles the existing session
  // closed and does not launch a duplicate provider request.
  viewer.start_peek_definition()
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_eq(tasks.tasks.length(), 0)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_definition_action_replaces_loading_peek_test() -> Unit {
  let source = definition_navigation_test_model("file:///replace-peek.mbt")
  let first_uri = try! @base_common.Uri::parse("file:///first-target.mbt")
  let second_uri = try! @base_common.Uri::parse("file:///second-target.mbt")
  let calls = Ref(0)
  let languages = @languages.Languages()
  languages.register_definition_provider(LanguageId("moonbit"), SequencedDefinitionProvider::{
    responses: [
      [
        { uri: first_uri, range: Range(1, 5, 1, 11) },
        { uri: second_uri, range: Range(1, 14, 1, 20) },
      ],
    ],
    calls,
  })
  |> ignore
  let log_service = @log.LogService()
  let services = ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  let position = @base_common.Position(1, 14)
  viewer.set_position(position)

  viewer.start_peek_definition()
  match viewer.definition_peek_phase_for_test() {
    PeekLoadingDefinitions(_) => ()
    _ => fail("first request did not open a loading Peek")
  }
  guard viewer.definition_contribution() is Some(state) &&
    state.peek.definition_source is Some(first_source) else {
    fail("first Peek request did not retain its source")
  }
  viewer.start_goto_definition_at(position, mute_message=false)
  assert_true(first_source.token().is_cancellation_requested())
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_eq(tasks.tasks.length(), 2)

  // The cancelled first task may still finish, but it must not recreate the
  // shell or consume the replacement action's provider result.
  tasks.run_next()
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  tasks.run_next()
  assert_eq(state.peek.locations.length(), 2)
  match viewer.definition_peek_phase_for_test() {
    PeekUnavailable(_, _) => ()
    _ => fail("replacement action did not populate a fresh Peek")
  }

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_stale_definition_peek_confirm_test() -> Unit {
  let source = definition_navigation_test_model("file:///confirm-source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///confirm-target.mbt")
  let opener_calls = Ref(0)
  let opener = @navigation_api.LocationOpenerHandle(open=_request => {
    opener_calls.val += 1
    true
  })
  let services = definition_navigation_services(
    [{ uri: target_uri, range: Range(3, 2, 3, 8) }],
    opener~,
  )
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))
  viewer.start_peek_definition()
  tasks.run_next()
  guard viewer.definition_contribution() is Some(state) &&
    state.peek.locations.length() == 1 else {
    fail("Peek result was not installed")
  }

  viewer.confirm_definition_peek_result(0)
  assert_eq(tasks.tasks.length(), 1)
  viewer.set_position(Position(1, 6))
  tasks.run_next()
  assert_eq(opener_calls.val, 0)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async fn run_definition_peek_model_swap_focus_test() -> Unit {
  let source = definition_navigation_test_model("file:///focus-source.mbt")
  let replacement = definition_navigation_test_model(
    "file:///focus-replacement.mbt",
  )
  let services = definition_navigation_services([
    { uri: source.uri, range: Range(1, 14, 1, 20) },
  ])
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 14))
  viewer.start_peek_definition()
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  guard viewer.definition_contribution() is Some(state) &&
    state.peek.widget is Some(widget) else {
    fail("Peek widget was not installed")
  }
  widget.focus()
  assert_true(viewer.definition_peek_contains_focus())
  assert_false(viewer.has_text_focus())

  viewer.set_model(Some(replacement))
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_true(viewer.has_text_focus())

  viewer.dispose()
  services.dispose()
  source.dispose()
  replacement.dispose()
}

///|
async fn run_cross_resource_definition_peek_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let first_uri = try! @base_common.Uri::parse("file:///source-target.mbt")
  let second_uri = try! @base_common.Uri::parse("file:///z-target.mbt")
  let first_model = @model.TextModel(
    first_uri, "first.mbt", "moonbit", 1, "rev-first", "let first = 1\n",
  )
  let second_model = @model.TextModel(
    second_uri, "second.mbt", "moonbit", 1, "rev-second", "let second = 2\n",
  )
  let locations : Array[@language.Location] = [
    { uri: first_uri, range: Range(1, 5, 1, 10) },
    { uri: second_uri, range: Range(1, 5, 1, 11) },
  ]
  let first_releases = Ref(0)
  let second_releases = Ref(0)
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    if resource.to_string() == first_uri.to_string() {
      Some(
        TextModelReference(first_model, release=() => first_releases.val += 1),
      )
    } else if resource.to_string() == second_uri.to_string() {
      Some(
        TextModelReference(second_model, release=() => second_releases.val += 1),
      )
    } else {
      None
    }
  })
  let services = definition_navigation_services(locations, resolver~)
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))
  viewer.start_peek_definition()
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  guard viewer.definition_contribution() is Some(state) else {
    fail("missing definition contribution")
  }
  let initial_index = state.peek.selected_index
  assert_true(initial_index == 0 || initial_index == 1)
  guard state.peek.preview_viewer is Some(first_preview) else {
    fail("first preview was not installed")
  }
  assert_eq(first_releases.val + second_releases.val, 0)

  first_preview.focus()
  assert_true(first_preview.has_text_focus())
  viewer.move_definition_peek_result(1)
  // A pending replacement keeps the installed preview and lease alive.
  assert_eq(first_releases.val + second_releases.val, 0)
  assert_false(first_preview.disposed)
  assert_true(state.peek.selected_index != initial_index)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(first_releases.val + second_releases.val, 0)
  assert_false(first_preview.disposed)
  // Focus ownership is sampled at commit time. Moving to the result shell
  // while the resolver is pending must not let the old request steal it back.
  match first_preview.mount {
    Mounted(mounted) => mounted.set_editor_focus(false) |> ignore
    Headless => fail("Peek preview unexpectedly became headless")
  }
  viewer.focus()
  assert_false(first_preview.has_text_focus())
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(first_releases.val + second_releases.val, 1)
  assert_true(first_preview.disposed)
  guard state.peek.preview_viewer is Some(second_preview) else {
    fail("second preview was not installed")
  }
  assert_false(second_preview.has_text_focus())
  viewer.move_definition_peek_result(1)
  assert_eq(first_releases.val + second_releases.val, 1)
  assert_false(second_preview.disposed)
  assert_eq(state.peek.selected_index, initial_index)
  tasks.run_next()
  assert_eq(first_releases.val + second_releases.val, 1)
  assert_false(second_preview.disposed)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  assert_eq(first_releases.val + second_releases.val, 2)
  assert_true(second_preview.disposed)
  viewer.close_definition_peek(restore_focus=false)
  assert_eq(first_releases.val + second_releases.val, 3)
  assert_false(first_model.is_disposed())
  assert_false(second_model.is_disposed())

  viewer.dispose()
  services.dispose()
  source.dispose()
  first_model.dispose()
  second_model.dispose()
}

///|
async fn run_reentrant_definition_peek_release_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let first_uri = try! @base_common.Uri::parse("file:///first-target.mbt")
  let second_uri = try! @base_common.Uri::parse("file:///second-target.mbt")
  let first_model = @model.TextModel(
    first_uri, "first.mbt", "moonbit", 1, "first-rev", "let first = 1\n",
  )
  let second_model = @model.TextModel(
    second_uri, "second.mbt", "moonbit", 1, "second-rev", "let second = 2\n",
  )
  let releases = Ref(0)
  let close_once = Ref(false)
  let release_hook : Ref[() -> Unit] = Ref(() => ())
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    let model = if resource.to_string() == first_uri.to_string() {
      first_model
    } else {
      second_model
    }
    Some(
      TextModelReference(model, release=() => {
        releases.val += 1
        if close_once.val {
          close_once.val = false
          (release_hook.val)()
        }
      }),
    )
  })
  let services = definition_navigation_services(
    [
      { uri: first_uri, range: Range(1, 5, 1, 10) },
      { uri: second_uri, range: Range(1, 5, 1, 11) },
    ],
    resolver~,
  )
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  release_hook.val = () => viewer.close_definition_peek(restore_focus=false)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))
  viewer.start_peek_definition()
  tasks.run_next()
  tasks.run_next()
  tasks.run_next()
  guard viewer.definition_contribution() is Some(state) &&
    state.peek.preview_reference is Some(_) else {
    fail("initial Peek preview reference was not installed")
  }

  viewer.move_definition_peek_result(1)
  tasks.run_next()
  assert_eq(tasks.tasks.length(), 1)
  close_once.val = true
  tasks.run_next()
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  assert_eq(releases.val, 2)
  assert_true(state.peek.preview_reference is None)
  assert_true(state.peek.preview_viewer is None)
  assert_true(state.peek.widget is None)

  viewer.dispose()
  services.dispose()
  source.dispose()
  first_model.dispose()
  second_model.dispose()
}

///|
async fn run_reentrant_definition_peek_close_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let target_model = @model.TextModel(
    target_uri, "target.mbt", "moonbit", 1, "target-rev", "let target = 1\n",
  )
  let releases = Ref(0)
  let reopen_once = Ref(false)
  let release_hook : Ref[() -> Unit] = Ref(() => ())
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => {
    Some(
      TextModelReference(target_model, release=() => {
        releases.val += 1
        if reopen_once.val {
          reopen_once.val = false
          (release_hook.val)()
        }
      }),
    )
  })
  let services = definition_navigation_services(
    [{ uri: target_uri, range: Range(1, 5, 1, 11) }],
    resolver~,
  )
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 640.0, 360.0)
  let viewer = Viewer::create(host, services~)
  release_hook.val = () => viewer.start_peek_definition()
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))
  viewer.start_peek_definition()
  tasks.run_next()
  tasks.run_next()
  tasks.run_next()
  guard viewer.definition_contribution() is Some(state) &&
    state.peek.preview_reference is Some(_) else {
    fail("initial Peek preview reference was not installed")
  }

  reopen_once.val = true
  viewer.close_definition_peek(restore_focus=false)
  match viewer.definition_peek_phase_for_test() {
    PeekLoadingDefinitions(_) => ()
    _ => fail("reentrant Peek request was clobbered by old-session teardown")
  }
  assert_true(state.peek.widget is Some(_))
  assert_true(state.peek.definition_source is Some(_))
  assert_eq(tasks.tasks.length(), 1)
  assert_eq(releases.val, 1)

  viewer.dispose()
  services.dispose()
  source.dispose()
  target_model.dispose()
}

///|
async fn run_stale_definition_peek_reference_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let target_uri = try! @base_common.Uri::parse("file:///target.mbt")
  let wrong_uri = try! @base_common.Uri::parse("file:///wrong.mbt")
  let wrong_model = @model.TextModel(
    wrong_uri, "wrong.mbt", "moonbit", 1, "wrong-rev", "let wrong = 1",
  )
  let releases = Ref(0)
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    _resource,
    _token,
  ) => Some(TextModelReference(wrong_model, release=() => releases.val += 1)))
  let services = definition_navigation_services(
    [{ uri: target_uri, range: Range(1, 1, 1, 2) }],
    resolver~,
  )
  let host = @rdom.document().create_element("div")
  let viewer = Viewer::create(host, services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.start_peek_definition()
  tasks.run_next()
  // The resolver task has not run. Closing cancels it; a non-cooperative late
  // resolver result must still release the returned lease.
  viewer.close_definition_peek(restore_focus=false)
  tasks.run_next()
  assert_eq(releases.val, 1)
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)

  viewer.start_peek_definition()
  tasks.run_next()
  tasks.run_next()
  assert_eq(releases.val, 2)
  match viewer.definition_peek_phase_for_test() {
    PeekUnavailable(_, _) => ()
    _ => fail("wrong-URI resolver result did not become unavailable")
  }

  viewer.dispose()
  services.dispose()
  source.dispose()
  wrong_model.dispose()
}

///|
async fn run_stale_definition_peek_request_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let location : @language.Location = {
    uri: source.uri,
    range: Range(1, 14, 1, 20),
  }
  let services = definition_navigation_services([location])
  let viewer = Viewer::create(@rdom.document().create_element("div"), services~)
  let tasks = ManualDefinitionTasks()
  viewer.set_definition_host_for_test(task => tasks.schedule(task))
  viewer.set_model(Some(source))
  viewer.set_position(Position(1, 5))
  viewer.start_peek_definition()
  guard viewer.definition_contribution() is Some(state) else {
    fail("missing definition contribution")
  }
  guard state.peek.definition_source is Some(definition_source) else {
    fail("Peek did not retain its definition cancellation source")
  }
  viewer.set_position(Position(1, 6))
  assert_true(definition_source.token().is_cancellation_requested())
  assert_true(state.peek.definition_source is None)
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  tasks.run_next()
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)

  viewer.start_peek_definition()
  viewer.set_value("let source = changed\n")
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)
  tasks.run_next()
  assert_eq(viewer.definition_peek_phase_for_test(), PeekClosed)

  viewer.dispose()
  services.dispose()
  source.dispose()
}

///|
async test "Peek Definition owns nested preview, switching, cancellation, and freshness" {
  // The mounted browser fixture replaces process globals, so all async Peek
  // cases deliberately run inside one test lifetime instead of racing through
  // independently installed fake DOM realms.
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  run_same_resource_definition_peek_test()
  run_empty_definition_peek_test()
  run_multiple_definition_default_peek_test()
  run_definition_action_replaces_loading_peek_test()
  run_stale_definition_peek_confirm_test()
  run_definition_peek_model_swap_focus_test()
  run_cross_resource_definition_peek_test()
  run_reentrant_definition_peek_release_test()
  run_reentrant_definition_peek_close_test()
  run_stale_definition_peek_reference_test()
  run_stale_definition_peek_request_test()
}
