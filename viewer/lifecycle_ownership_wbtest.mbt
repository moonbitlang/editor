///|
/// Pushes one stable diagnostic before attachment so lifecycle tests can
/// distinguish MarkerService data from the derived per-model decorations.
fn seed_lifecycle_marker(
  markers : @markers.MarkerService,
  model : @model.TextModel,
) -> Unit {
  markers.change_one("lifecycle-owner", model.uri, [
    MarkerData(
      severity=Error,
      message="preloaded",
      start_line_number=1,
      start_column=1,
      end_line_number=1,
      end_column=2,
    ),
  ])
}

///|
/// Caller-retained concrete backings for root white-box tests. Production
/// receives only the narrowed handles captured by `services`.
struct RootTestServiceBackings {
  services : ViewerServices
  languages : @languages.Languages
  markers : @markers.MarkerService
  marker_decorations : @markers.MarkerDecorationsService
  agent_feedback : @agent_feedback.AgentFeedbackService
  quick_diff : @quick_diff.QuickDiffService
  log_service : @log.LogService
  log_output : @log.MemoryLogger
}

///|
fn RootTestServiceBackings::new() -> RootTestServiceBackings {
  let log_output = @log.MemoryLogger()
  let log_service = @log.LogService(level=Trace, logger=log_output)
  let languages = @languages.Languages()
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  let agent_feedback = @agent_feedback.AgentFeedbackService()
  let quick_diff = @quick_diff.QuickDiffService()
  let services = ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    markers=Decorations(marker_decorations.marker_decorations_handle()),
    agent_feedback=agent_feedback.agent_feedback_handle(),
    quick_diff=quick_diff.quick_diff_handle(),
    log_service=log_service.log_handle(),
  )
  {
    services,
    languages,
    markers,
    marker_decorations,
    agent_feedback,
    quick_diff,
    log_service,
    log_output,
  }
}

///|
fn RootTestServiceBackings::dispose(self : RootTestServiceBackings) -> Unit {
  // The explicit bundle owns none of these injected backings.
  self.services.dispose()
  self.marker_decorations.dispose()
  self.markers.dispose()
  self.agent_feedback.dispose()
}

///|
test "model slot generation and browser shape follow headless lifecycle" {
  let viewer = Viewer::Viewer()
  let model = test_model("alpha")
  assert_eq(viewer.model_slot.generation, 0)
  assert_true(viewer.model_slot.current is None)

  viewer.set_model(Some(model))
  assert_eq(viewer.model_slot.generation, 1)
  guard viewer.model_slot.current is Some(first) else {
    fail("headless model slot was not installed")
  }
  assert_true(first.browser is None)

  viewer.set_value("beta")
  viewer.set_model(Some(model))
  assert_eq(viewer.model_slot.generation, 1)

  viewer.set_model(None)
  assert_eq(viewer.model_slot.generation, 2)
  assert_true(viewer.model_slot.current is None)

  viewer.set_model(Some(model))
  assert_eq(viewer.model_slot.generation, 3)
  guard viewer.model_slot.current is Some(second) else {
    fail("headless model slot was not reinstalled")
  }
  assert_true(second.browser is None)

  viewer.dispose()
  assert_eq(viewer.model_slot.generation, 4)
  assert_true(viewer.model_slot.current is None)
  model.dispose()
}

///|
test "preloaded markers survive detach and seed again on reattach" {
  let backings = RootTestServiceBackings::new()
  let viewer = Viewer::Viewer(services=backings.services)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  viewer.set_model(Some(model))
  assert_eq(model.get_all_decorations().length(), 1)
  viewer.set_model(None)
  assert_eq(model.get_all_decorations().length(), 0)
  assert_eq(backings.markers.diagnostics_for_resource(model.uri).length(), 1)
  viewer.set_model(Some(model))
  assert_eq(model.get_all_decorations().length(), 1)
  viewer.dispose()
  assert_false(model.is_disposed())
  model.dispose()
  backings.dispose()
}

///|
test "set_value refresh does not acquire another shared-model lease" {
  let backings = RootTestServiceBackings::new()
  let first = Viewer::Viewer(services=backings.services)
  let second = Viewer::Viewer(services=backings.services)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  first.set_model(Some(model))
  second.set_model(Some(model))
  assert_eq(model.get_all_decorations().length(), 1)
  first.set_value("beta")
  assert_eq(model.get_all_decorations().length(), 1)
  first.dispose()
  assert_eq(model.get_all_decorations().length(), 1)
  second.dispose()
  assert_eq(model.get_all_decorations().length(), 0)
  assert_false(backings.services.disposed)
  assert_eq(backings.markers.diagnostics_for_resource(model.uri).length(), 1)
  model.dispose()
  backings.dispose()
  assert_true(backings.services.disposed)
}

///|
test "distinct same-URI models retain independent decoration owners" {
  let backings = RootTestServiceBackings::new()
  let first_viewer = Viewer::Viewer(services=backings.services)
  let second_viewer = Viewer::Viewer(services=backings.services)
  let first_model = test_model("first")
  let second_model = test_model("second")
  assert_true(first_model.uri.to_string() == second_model.uri.to_string())
  assert_false(first_model.same(second_model))
  seed_lifecycle_marker(backings.markers, first_model)
  first_viewer.set_model(Some(first_model))
  second_viewer.set_model(Some(second_model))
  assert_eq(first_model.get_all_decorations().length(), 1)
  assert_eq(second_model.get_all_decorations().length(), 1)
  first_viewer.dispose()
  assert_eq(first_model.get_all_decorations().length(), 0)
  assert_eq(second_model.get_all_decorations().length(), 1)
  second_viewer.dispose()
  assert_eq(second_model.get_all_decorations().length(), 0)
  first_model.dispose()
  second_model.dispose()
  backings.dispose()
}

///|
test "model disposal detaches two Viewers sharing one registration" {
  let backings = RootTestServiceBackings::new()
  let first = Viewer::Viewer(services=backings.services)
  let second = Viewer::Viewer(services=backings.services)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  first.set_model(Some(model))
  second.set_model(Some(model))
  model.dispose()
  assert_true(first.get_model() is None)
  assert_true(second.get_model() is None)
  assert_eq(model.get_all_decorations().length(), 0)
  first.dispose()
  second.dispose()
  backings.dispose()
}

///|
test "explicit services stay borrowed after Viewer disposal" {
  let backings = RootTestServiceBackings::new()
  let viewer = Viewer::Viewer(services=backings.services)
  assert_false(viewer.owns_services)
  viewer.dispose()
  assert_false(backings.services.disposed)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  let lease = backings.marker_decorations.acquire_model(model)
  assert_eq(model.get_all_decorations().length(), 1)
  lease.dispose()
  model.dispose()
  backings.dispose()
}

///|
test "MarkerStore makes only its generated decorations bundle-owned" {
  let backings = RootTestServiceBackings::new()
  let services = ViewerServices(
    languages=backings.languages.language_handle(
      backings.log_service.log_handle(),
    ),
    markers=MarkerStore(backings.markers.marker_service_handle()),
    agent_feedback=backings.agent_feedback.agent_feedback_handle(),
    quick_diff=backings.quick_diff.quick_diff_handle(),
    log_service=backings.log_service.log_handle(),
  )
  let generated_decorations = services.owned_marker_decorations.unwrap()
  assert_true(services.owned_markers is None)
  assert_true(services.owned_agent_feedback is None)
  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  let lease = generated_decorations.acquire_model(model)
  assert_eq(model.get_all_decorations().length(), 1)
  let marker_deliveries = Ref(0)
  let subscription = backings.markers.on_did_change_markers(_ => {
    marker_deliveries.val += 1
  })

  services.dispose()
  services.dispose()

  assert_true(services.disposed)
  assert_eq(model.get_all_decorations().length(), 0)
  seed_lifecycle_marker(backings.markers, model)
  assert_eq(marker_deliveries.val, 1)
  subscription.dispose()
  lease.dispose()
  model.dispose()
  backings.dispose()
}

///|
test "Decorations leaves every caller handle live after bundle disposal" {
  let backings = RootTestServiceBackings::new()
  let log_handle = backings.log_service.log_handle()
  let language_handle = backings.languages.language_handle(log_handle)
  let marker_handle = backings.marker_decorations.marker_decorations_handle()
  let feedback_handle = backings.agent_feedback.agent_feedback_handle()
  let quick_diff_handle = backings.quick_diff.quick_diff_handle()
  let services = ViewerServices(
    languages=language_handle,
    markers=Decorations(marker_handle),
    agent_feedback=feedback_handle,
    quick_diff=quick_diff_handle,
    log_service=log_handle,
  )
  assert_true(services.owned_marker_decorations is None)
  assert_true(services.owned_markers is None)
  assert_true(services.owned_agent_feedback is None)

  services.dispose()
  services.dispose()

  let model = test_model("alpha")
  seed_lifecycle_marker(backings.markers, model)
  let lease = backings.marker_decorations.acquire_model(model)
  assert_eq(model.get_all_decorations().length(), 1)
  backings.agent_feedback.set_feedback_enabled(model.uri, true)
  assert_true(feedback_handle.is_feedback_enabled(model.uri))
  backings.quick_diff.set_original_content(model.uri, Some("baseline"))
  assert_true(
    quick_diff_handle.get_original_content(model.uri) == Some("baseline"),
  )
  backings.languages.set_language_configuration("root-test", {
    comments: None,
    folding_rules: Some({ off_side: true, markers: None }),
  })
  guard language_handle.get_language_configuration("root-test").folding_rules
    is Some(folding_rules) else {
    fail("caller language handle lost its registered configuration")
  }
  assert_true(folding_rules.off_side)
  log_handle.warn("viewer.lifecycle", "still live")
  assert_eq(backings.log_output.entries().length(), 1)

  lease.dispose()
  model.dispose()
  backings.dispose()
}

///|
test "omitted services are owned and Viewer disposal is idempotent" {
  let viewer = Viewer::Viewer()
  let services = viewer.services
  let owned_markers = services.owned_markers.unwrap()
  let owned_marker_decorations = services.owned_marker_decorations.unwrap()
  let owned_agent_feedback = services.owned_agent_feedback.unwrap()
  assert_false(services.disposed)
  let model = test_model("alpha")
  seed_lifecycle_marker(owned_markers, model)
  viewer.set_model(Some(model))
  let marker_deliveries = Ref(0)
  let feedback_deliveries = Ref(0)
  let marker_subscription = owned_markers.on_did_change_markers(_ => {
    marker_deliveries.val += 1
  })
  let feedback_subscription = owned_agent_feedback.on_did_change_feedback(_ => {
    feedback_deliveries.val += 1
  })
  let mut dispose_events = 0
  let contribution_alive_in_event = Ref(false)
  let lifetime_store_alive_in_event = Ref(false)
  let model_detached_in_event = Ref(false)
  viewer.on_did_dispose(() => {
    dispose_events += 1
    contribution_alive_in_event.val = viewer.contributions.lookup(
        "editor.contrib.contentHover",
      )
      is Some(_)
    lifetime_store_alive_in_event.val = !viewer.lifetime_disposables.is_empty()
    model_detached_in_event.val = viewer.get_model() is None
  })
  |> ignore
  viewer.dispose()
  viewer.dispose()
  assert_true(viewer.owns_services)
  assert_true(viewer.disposed)
  assert_true(services.disposed)
  assert_eq(dispose_events, 1)
  assert_true(contribution_alive_in_event.val)
  assert_true(lifetime_store_alive_in_event.val)
  assert_true(model_detached_in_event.val)
  assert_eq(viewer.lifetime_disposables.length(), 0)
  // A never-attached Viewer remains semantically headless through disposal:
  // it has no browser frame, focus, host, or placeholder capability to tear
  // down.
  assert_true(viewer.mount is Headless)
  assert_false(viewer.mount.has_pending_render())
  assert_false(viewer.has_text_focus())
  assert_false(model.is_disposed())
  // The owning Viewer released all three bundle-owned default backings. Their
  // captured concrete references remain safe but have no live ingress.
  seed_lifecycle_marker(owned_markers, model)
  owned_agent_feedback.set_feedback_enabled(model.uri, true)
  owned_agent_feedback.add_feedback(
    model.uri,
    Range(1, 1, 1, 2),
    "after default disposal",
  )
  |> ignore
  assert_eq(marker_deliveries.val, 0)
  assert_eq(feedback_deliveries.val, 0)
  let later_model = test_model("later")
  let late_lease = owned_marker_decorations.acquire_model(later_model)
  assert_eq(later_model.get_all_decorations().length(), 0)
  late_lease.dispose()
  marker_subscription.dispose()
  feedback_subscription.dispose()
  model.dispose()
  later_model.dispose()
}

///|
test "disposed headless Viewer ignores later model and callback work" {
  let backings = RootTestServiceBackings::new()
  let viewer = Viewer::Viewer(services=backings.services)
  let model = test_model("alpha")
  viewer.set_model(Some(model))
  let mut content_events = 0
  viewer.on_did_change_model_content(_ => content_events += 1) |> ignore
  viewer.dispose()
  model.set_value("beta")
  // The Viewer-level font subscription is both released and guarded. A
  // source emission after disposal must not mark layout work pending.
  @browser_config.font_measurements().clear_all_font_infos()
  viewer.set_model(Some(model))
  viewer.schedule_render()
  assert_eq(content_events, 0)
  assert_false(viewer.configuration.consume_measure_request())
  assert_true(viewer.get_model() is None)
  assert_true(viewer.mount is Headless)
  assert_false(viewer.mount.has_pending_render())
  model.dispose()
  backings.dispose()
}

///|
test "testing registration follows headless Viewer lifecycle" {
  let viewer = Viewer::Viewer()
  let viewer_id = viewer.get_id()
  assert_false(@viewer_testing.has_model(viewer_id))
  let model = test_model("testing-registration")
  viewer.set_model(Some(model))
  assert_true(@viewer_testing.has_model(viewer_id))

  viewer.dispose()

  assert_false(@viewer_testing.has_model(viewer_id))
  assert_false(
    @viewer_testing.set_hidden_areas(
      viewer_id,
      [Range(1, 1, 1, 1)],
      source="disposed-viewer",
    ),
  )
  model.dispose()
}
