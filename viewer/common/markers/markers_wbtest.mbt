///|
/// Builds error marker input matching Monaco's `randomMarkerData` shape
/// (line/col all 1), with a deterministic message.
fn marker_data(severity : MarkerSeverity, message : String) -> MarkerData {
  MarkerData(
    severity~,
    message~,
    start_line_number=1,
    start_column=1,
    end_line_number=1,
    end_column=1,
  )
}

///|
test "marker decorations expose squiggles and marker hover lookup" {
  let markers = MarkerService()
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/decorations.mbt",
  )
  let model = @model.TextModel(
    uri, "", "moonbit", 1, "rev", "diagnostic text here",
  )
  markers.set_diagnostics("owner", uri, [
    {
      range: Range(1, 3, 1, 9),
      severity: Warning,
      message: "diagnostic",
      tags: None,
    },
  ])
  let decorations = MarkerDecorationsService(markers.marker_service_handle())
  decorations.on_model_added(model)
  // Squiggles now live in the model's decoration storage.
  let stored = model.get_all_decorations()
  assert_eq(stored.length(), 1)
  assert_true(stored[0].options.class_name == "squiggly-warning")
  assert_true(stored[0].range == Range(1, 3, 1, 9))
  // get_live_markers exposes the transformed range + marker for hover lookup.
  let live = decorations.get_live_markers(uri)
  assert_eq(live.length(), 1)
  let (range, marker) = live[0]
  assert_true(range == Range(1, 3, 1, 9))
  assert_true(marker.message == "diagnostic")
}

///|
test "marker service replaces owner resource and supports limits" {
  let service = MarkerService()
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/markers.mbt",
  )
  service.set_diagnostics("owner-a", uri, [
    {
      range: Range(1, 1, 1, 2),
      severity: Warning,
      message: "first",
      tags: None,
    },
    { range: Range(1, 3, 1, 4), severity: Error, message: "second", tags: None },
  ])
  service.set_diagnostics("owner-b", uri, [
    { range: Range(1, 5, 1, 6), severity: Info, message: "third", tags: None },
  ])
  assert_eq(service.markers_for_resource(uri).length(), 3)
  service.set_diagnostics("owner-a", uri, [
    {
      range: Range(1, 7, 1, 8),
      severity: Warning,
      message: "replacement",
      tags: None,
    },
  ])
  let markers = service.markers_for_resource(uri)
  assert_eq(markers.length(), 2)
  assert_eq(service.markers_for_resource(uri, limit=1).length(), 1)
}

///|
test "MarkerSeverity bit values and bridge" {
  // markers.ts:56 — load-bearing bit values.
  assert_eq(MarkerSeverity::Hint.value(), 1)
  assert_eq(MarkerSeverity::Info.value(), 2)
  assert_eq(MarkerSeverity::Warning.value(), 4)
  assert_eq(MarkerSeverity::Error.value(), 8)
  // compare = b - a (markers.ts:65)
  assert_eq(MarkerSeverity::compare(Error, Warning), 4 - 8)
  assert_true(MarkerSeverity::from_diagnostic_severity(Warning) == Warning)
  // Hint round-trips (no longer collapses to Info).
  assert_true(MarkerSeverity::from_diagnostic_severity(Hint) == Hint)
  assert_true(MarkerSeverity::Hint.to_diagnostic_severity() == Hint)
}

///|
test "Marker::from_diagnostic/to_diagnostic carry Hint severity and tags" {
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/hint.mbt",
  )
  let diagnostic : @language.Diagnostic = {
    range: Range(1, 1, 1, 2),
    severity: Hint,
    message: "unused import",
    tags: Some([Unnecessary]),
  }
  let marker = Marker::from_diagnostic("owner", uri, diagnostic)
  assert_true(marker.severity == Hint)
  assert_true(marker.tags == Some([Unnecessary]))
  let round_tripped = marker.to_diagnostic()
  assert_true(round_tripped.severity == Hint)
  assert_true(round_tripped.tags == Some([Unnecessary]))
}

///|
test "MarkerData sanitize clamps line/column and drops empty message" {
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/sanitize.mbt",
  )
  // empty message dropped (markerService.ts:238)
  assert_true(marker_data(Error, "").to_marker("o", uri) is None)
  // start/end clamping (markerService.ts:243-246)
  let raw = MarkerData(
    severity=Error,
    message="m",
    start_line_number=0,
    start_column=0,
    end_line_number=-3,
    end_column=0,
  )
  let marker = raw.to_marker("o", uri).unwrap()
  assert_eq(marker.start_line_number, 1)
  assert_eq(marker.start_column, 1)
  assert_eq(marker.end_line_number, 1)
  assert_eq(marker.end_column, 1)
}
