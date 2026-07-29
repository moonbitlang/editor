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
async fn definition_navigation_next_microtask() -> Unit noraise {
  @js.suspend((resolve : (Unit) -> Unit, _reject : (Error) -> Unit) => {
    @base_browser.queue_microtask(() => resolve(()))
  }) catch {
    _ => ()
  }
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
    Some("No definition found"),
  )

  viewer.dispose()
  empty_viewer.dispose()
  services.dispose()
  empty_services.dispose()
  model.dispose()
  empty_model.dispose()
}

///|
async test "empty definition-link result is cached for one gesture and reports once" {
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
  assert_eq(viewer.definition_message_for_test(), Some("No definition found"))
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
  definition_navigation_next_microtask()
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
async fn run_cross_resource_definition_peek_test() -> Unit {
  let source = definition_navigation_test_model("file:///source.mbt")
  let first_uri = try! @base_common.Uri::parse("file:///first.mbt")
  let second_uri = try! @base_common.Uri::parse("file:///second.mbt")
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
  definition_navigation_next_microtask()
  guard viewer.definition_contribution() is Some(state) else {
    fail("missing definition contribution")
  }
  assert_eq(state.peek.selected_index, 0)
  assert_true(state.peek.preview_viewer is Some(_))
  assert_eq(first_releases.val, 0)

  viewer.move_definition_peek_result(1)
  assert_eq(first_releases.val, 1)
  assert_eq(state.peek.selected_index, 1)
  assert_eq(tasks.tasks.length(), 1)
  tasks.run_next()
  definition_navigation_next_microtask()
  assert_true(state.peek.preview_viewer is Some(_))
  assert_eq(second_releases.val, 0)
  viewer.move_definition_peek_result(1)
  assert_eq(second_releases.val, 1)
  assert_eq(state.peek.selected_index, 0)
  tasks.run_next()
  definition_navigation_next_microtask()
  viewer.close_definition_peek(restore_focus=false)
  assert_eq(first_releases.val, 2)
  assert_false(first_model.is_disposed())
  assert_false(second_model.is_disposed())

  viewer.dispose()
  services.dispose()
  source.dispose()
  first_model.dispose()
  second_model.dispose()
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
  run_cross_resource_definition_peek_test()
  run_stale_definition_peek_reference_test()
  run_stale_definition_peek_request_test()
}
