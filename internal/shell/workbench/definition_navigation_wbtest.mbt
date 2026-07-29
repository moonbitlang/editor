///|
fn definition_navigation_test_uri(name : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/" + name + ".mbt",
  )
}

///|
extend RemoteLanguageClient with @language.DefinitionProvider::{
  provide_definition,
}

///|
test "preview references share one host model and retire it after the final lease" {
  let uri = definition_navigation_test_uri("lease-target")
  let model = TextModel(
    uri, "lease-target.mbt", "moonbit", 1, "rev-lease", "let target = 1",
  )
  let state : PreviewResourceState = {
    uri,
    model: Some(model),
    in_flight: 0,
    leases: 0,
    disposed: false,
  }
  preview_resources[uri.to_string()] = state

  let first = acquire_preview_reference(state, model)
  let second = acquire_preview_reference(state, model)
  assert_eq(state.leases, 2)
  assert_true(preview_resource_retains_remote_document(uri))
  assert_true(first.model().same(second.model()))

  first.dispose()
  first.dispose()
  assert_eq(state.leases, 1)
  assert_false(model.is_disposed())
  assert_true(preview_resources.contains(uri.to_string()))

  second.dispose()
  assert_eq(state.leases, 0)
  assert_true(model.is_disposed())
  assert_false(preview_resources.contains(uri.to_string()))
  assert_false(preview_resource_retains_remote_document(uri))
}

///|
async test "remote definition provider preserves ordered locations and cancellation" {
  let previous_send = protocol_send.val
  let previous_dispatch = workbench_dispatch.val
  let source_uri = definition_navigation_test_uri("definition-source")
  let first_uri = definition_navigation_test_uri("definition-first")
  let second_uri = definition_navigation_test_uri("definition-second")
  let source_model = TextModel(
    source_uri, "definition-source.mbt", "moonbit", 2, "rev-source", "let answer = target",
  )
  let markers = @markers.MarkerService()
  let freshness = RemoteLanguageFreshness(markers)
  freshness.note_document(source_model)
  let client = RemoteLanguageClient::{
    log_service: LogService(logger=NullLogger()),
    freshness,
  }
  let observed_uri = Ref("")
  let observed_revision = Ref("")
  let observed_offset = Ref(-1)
  let unexpected_packet = Ref(false)
  protocol_send.val = Some(packet => {
    match packet {
      Definition(request) => {
        observed_uri.val = request.uri.to_string()
        observed_revision.val = request.document_revision
        observed_offset.val = request.offset
        resolve_pending_response(
          DefinitionResult({
            id: request.id,
            uri: request.uri,
            revision: request.document_revision,
            locations: [
              { uri: first_uri, range: Range(3, 2, 3, 8) },
              { uri: second_uri, range: Range(9, 1, 9, 5) },
            ],
          }),
        )
        |> ignore
      }
      _ => unexpected_packet.val = true
    }
  })
  let locations = client.provide_definition(
    source_model,
    Position(1, 14),
    @language.CancellationToken::none(),
  )
  assert_false(unexpected_packet.val)
  assert_eq(observed_uri.val, source_uri.to_string())
  assert_eq(observed_revision.val, "rev-source")
  assert_eq(observed_offset.val, source_model.get_offset_at(Position(1, 14)))
  assert_eq(locations.length(), 2)
  assert_eq(locations[0].uri.to_string(), first_uri.to_string())
  assert_eq(locations[0].range, Range(3, 2, 3, 8))
  assert_eq(locations[1].uri.to_string(), second_uri.to_string())
  assert_eq(locations[1].range, Range(9, 1, 9, 5))

  let cancelled = @language.CancellationTokenSource()
  let late_response_consumed = Ref(false)
  let cancelled_request_id = Ref("")
  protocol_send.val = Some(packet => {
    match packet {
      Definition(request) => {
        cancelled_request_id.val = request.id
        cancelled.cancel()
      }
      _ => unexpected_packet.val = true
    }
  })
  let cancelled_locations = client.provide_definition(
    source_model,
    Position(1, 14),
    cancelled.token(),
  )
  assert_true(cancelled_locations.is_empty())
  // The local cancellation has resumed the provider. A later server response
  // is consumed through the retained request-id tombstone.
  late_response_consumed.val = resolve_pending_response(
    DefinitionResult({
      id: cancelled_request_id.val,
      uri: source_uri,
      revision: "rev-source",
      locations: [{ uri: first_uri, range: Range(1, 1, 1, 2) }],
    }),
  )
  assert_true(late_response_consumed.val)
  assert_false(unexpected_packet.val)
  freshness.invalidate()
  markers.dispose()

  let preview_uri = definition_navigation_test_uri("definition-preview")
  let preview_open_count = Ref(0)
  let preview_close_count = Ref(0)
  protocol_send.val = Some(packet => {
    match packet {
      OpenDocument(request) => {
        preview_open_count.val = preview_open_count.val + 1
        resolve_pending_response(
          DocumentLoaded({
            id: request.id,
            document: DocumentSnapshot(
              request.uri,
              "definition-preview.mbt",
              "moonbit",
              "rev-preview",
              "let preview = 1",
            ),
          }),
        )
        |> ignore
      }
      CloseDocument(_) => preview_close_count.val = preview_close_count.val + 1
      _ => unexpected_packet.val = true
    }
  })
  guard resolve_preview_model(preview_uri, @language.CancellationToken::none())
    is Some(first_preview) else {
    fail("first preview resolution returned no model")
  }
  guard resolve_preview_model(preview_uri, @language.CancellationToken::none())
    is Some(second_preview) else {
    fail("cached preview resolution returned no model")
  }
  assert_eq(preview_open_count.val, 1)
  assert_true(first_preview.model().same(second_preview.model()))
  let preview_model = first_preview.model()
  first_preview.dispose()
  assert_false(preview_model.is_disposed())
  assert_eq(preview_close_count.val, 0)
  second_preview.dispose()
  assert_true(preview_model.is_disposed())
  assert_eq(preview_close_count.val, 1)
  assert_false(preview_resources.contains(preview_uri.to_string()))

  let opened_uri = Ref("")
  workbench_dispatch.val = Some(msg => {
    match msg {
      OpenDefinitionLocation(location) =>
        opened_uri.val = location.uri.to_string()
      _ => unexpected_packet.val = true
    }
  })
  let opener = workbench_location_opener()
  let open_request : @navigation_api.OpenLocationRequest = {
    source_viewer_id: "definition-test-viewer",
    location: { uri: first_uri, range: Range(3, 2, 3, 8) },
    mode: Current,
  }
  assert_true(opener.open(open_request))
  assert_eq(opened_uri.val, first_uri.to_string())
  assert_false(opener.open({ ..open_request, mode: Side }))
  assert_false(unexpected_packet.val)

  protocol_send.val = previous_send
  workbench_dispatch.val = previous_dispatch
  cancelled.dispose()
  source_model.dispose()
}
