// Conformance port of
// vscode/src/vs/platform/markers/test/common/markerService.test.ts

///|
fn uri(value : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(value)
}

///|
fn resource_marker(
  resource : @base_common.Uri,
  severity : MarkerSeverity,
) -> ResourceMarker {
  { resource, marker: marker_data(severity, "msg") }
}

///|
test "query" {
  let service = MarkerService()
  let file = uri("file:///c/test/file.cs")
  service.change_all("far", [resource_marker(file, Error)])
  assert_eq(service.read(MarkerReadOptions()).length(), 1)
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 1)
  assert_eq(service.read(MarkerReadOptions(resource=file)).length(), 1)
  assert_eq(
    service.read(MarkerReadOptions(owner="far", resource=file)).length(),
    1,
  )
  service.change_all("boo", [resource_marker(file, Warning)])
  assert_eq(service.read(MarkerReadOptions()).length(), 2)
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 1)
  assert_eq(service.read(MarkerReadOptions(owner="boo")).length(), 1)
  // severities bitmask (_accept)
  assert_eq(
    service
    .read(MarkerReadOptions(severities=MarkerSeverity::Error.value()))
    .length(),
    1,
  )
  assert_eq(
    service
    .read(MarkerReadOptions(severities=MarkerSeverity::Warning.value()))
    .length(),
    1,
  )
  assert_eq(
    service
    .read(MarkerReadOptions(severities=MarkerSeverity::Hint.value()))
    .length(),
    0,
  )
  assert_eq(
    service
    .read(
      MarkerReadOptions(
        severities=MarkerSeverity::Error.value() |
          MarkerSeverity::Warning.value(),
      ),
    )
    .length(),
    2,
  )
}

///|
test "changeOne override" {
  let service = MarkerService()
  let only = uri("file:///path/only.cs")
  service.change_one("far", only, [marker_data(Error, "a")])
  assert_eq(service.read(MarkerReadOptions()).length(), 1)
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 1)
  service.change_one("boo", only, [marker_data(Error, "b")])
  assert_eq(service.read(MarkerReadOptions()).length(), 2)
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 1)
  assert_eq(service.read(MarkerReadOptions(owner="boo")).length(), 1)
  service.change_one("far", only, [
    marker_data(Error, "c"),
    marker_data(Error, "d"),
  ])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 2)
  assert_eq(service.read(MarkerReadOptions(owner="boo")).length(), 1)
}

///|
test "changeOne/All clears" {
  let service = MarkerService()
  let only = uri("file:///path/only.cs")
  service.change_one("far", only, [marker_data(Error, "a")])
  service.change_one("boo", only, [marker_data(Error, "b")])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 1)
  assert_eq(service.read(MarkerReadOptions(owner="boo")).length(), 1)
  assert_eq(service.read(MarkerReadOptions()).length(), 2)
  service.change_one("far", only, [])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 0)
  assert_eq(service.read(MarkerReadOptions(owner="boo")).length(), 1)
  assert_eq(service.read(MarkerReadOptions()).length(), 1)
  service.change_all("boo", [])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 0)
  assert_eq(service.read(MarkerReadOptions(owner="boo")).length(), 0)
  assert_eq(service.read(MarkerReadOptions()).length(), 0)
}

///|
test "changeAll sends event for cleared" {
  let service = MarkerService()
  let path = uri("file:///d/path")
  service.change_all("far", [
    resource_marker(path, Error),
    resource_marker(path, Error),
  ])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 2)
  let fired : Array[@base_common.Uri] = []
  let d = service.on_did_change_markers(changed => {
    for u in changed {
      fired.push(u)
    }
  })
  service.change_all("far", [])
  assert_eq(fired.length(), 1)
  assert_eq(fired[0].to_string(), "file:///d/path")
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 0)
  d.dispose()
}

///|
test "changeAll merges" {
  let service = MarkerService()
  let file = uri("file:///c/test/file.cs")
  service.change_all("far", [
    resource_marker(file, Error),
    resource_marker(file, Error),
  ])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 2)
}

///|
test "changeAll must not break integrity, issue #12635" {
  let service = MarkerService()
  let p1 = uri("scheme://path1")
  let p2 = uri("scheme://path2")
  service.change_all("far", [
    resource_marker(p1, Error),
    resource_marker(p2, Error),
  ])
  service.change_all("boo", [resource_marker(p1, Error)])
  service.change_all("far", [
    resource_marker(p1, Error),
    resource_marker(p2, Error),
  ])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 2)
  assert_eq(service.read(MarkerReadOptions(resource=p1)).length(), 2)
}

///|
test "invalid marker data" {
  let service = MarkerService()
  let path = uri("some://uri/path")
  service.change_one("far", path, [marker_data(Error, "")])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 0)
  service.change_one("far", path, [marker_data(Error, "null")])
  assert_eq(service.read(MarkerReadOptions(owner="far")).length(), 1)
}

///|
test "MapMap#remove returns bad values, issue #13548" {
  let service = MarkerService()
  service.change_one("o", uri("some://uri/1"), [marker_data(Error, "a")])
  service.change_one("o", uri("some://uri/2"), [])
}

///|
test "Error code of zero in markers get removed, #31275" {
  let service = MarkerService()
  let thing = uri("some://thing")
  let data = MarkerData(
    severity=Error,
    message="test",
    start_line_number=1,
    start_column=2,
    end_line_number=1,
    end_column=5,
    code="0",
    source="me",
  )
  service.change_one("far", thing, [data])
  let marker = service.read(MarkerReadOptions(resource=thing))
  assert_eq(marker.length(), 1)
  assert_true(marker[0].code == Some("0"))
}

///|
test "modelVersionId is preserved on IMarker when present in IMarkerData" {
  let service = MarkerService()
  let resource = uri("file:///path/file.ts")
  let with_version = MarkerData(
    severity=Error,
    message="m",
    start_line_number=1,
    start_column=1,
    end_line_number=1,
    end_column=1,
    model_version_id=42,
  )
  service.change_one("owner", resource, [with_version])
  let markers_with = service.read(MarkerReadOptions(resource~))
  assert_eq(markers_with.length(), 1)
  assert_true(markers_with[0].model_version_id == Some(42))
  service.change_one("owner", resource, [marker_data(Error, "m")])
  let markers_without = service.read(MarkerReadOptions(resource~))
  assert_eq(markers_without.length(), 1)
  assert_true(markers_without[0].model_version_id is None)
}

///|
test "resource filter hides markers and shows info marker" {
  let service = MarkerService()
  let r1 = uri("file:///path/file1.cs")
  let r2 = uri("file:///path/file2.cs")
  service.change_one("owner1", r1, [marker_data(Error, "a")])
  service.change_one("owner1", r2, [marker_data(Error, "b")])
  assert_eq(service.read(MarkerReadOptions()).length(), 2)
  let filter = service.install_resource_filter(r1, "Test filter")
  // r1's real markers replaced by 1 info marker; total still 2
  assert_eq(service.read(MarkerReadOptions()).length(), 2)
  let r1_markers = service.read(MarkerReadOptions(resource=r1))
  assert_eq(r1_markers.length(), 1)
  assert_true(r1_markers[0].severity == Info)
  assert_true(r1_markers[0].message.contains("Test filter"))
  assert_eq(service.read(MarkerReadOptions(resource=r2)).length(), 1)
  // ignoreResourceFilters bypasses
  assert_eq(
    service
    .read(MarkerReadOptions(resource=r1, ignore_resource_filters=true))
    .length(),
    1,
  )
  assert_true(
    service.read(MarkerReadOptions(resource=r1, ignore_resource_filters=true))[0].severity ==
    Error,
  )
  filter.dispose()
  assert_eq(service.read(MarkerReadOptions(resource=r1)).length(), 1)
  assert_true(service.read(MarkerReadOptions(resource=r1))[0].severity == Error)
}

///|
test "multiple filters for same resource are handled correctly" {
  let service = MarkerService()
  let resource = uri("file:///path/file.cs")
  service.change_one("owner1", resource, [marker_data(Error, "a")])
  let filter1 = service.install_resource_filter(resource, "First filter")
  let filter2 = service.install_resource_filter(resource, "Second filter")
  assert_eq(service.read(MarkerReadOptions(resource~)).length(), 1)
  assert_true(service.read(MarkerReadOptions(resource~))[0].severity == Info)
  filter1.dispose()
  // still filtered (one reason remains)
  assert_true(service.read(MarkerReadOptions(resource~))[0].severity == Info)
  filter2.dispose()
  assert_true(service.read(MarkerReadOptions(resource~))[0].severity == Error)
}

///|
test "marker events merge: N changes in one tick fire one event with the URI union" {
  // Manual scheduler standing in for the hardcoded `queueMicrotask`
  // (`event.ts:1610`); flushing by hand keeps the test deterministic on
  // every target.
  let scheduled : Array[() -> Unit] = []
  let service = MarkerService(schedule=run => scheduled.push(run))
  let a = uri("file:///a.cs")
  let b = uri("file:///b.cs")
  let fired : Array[Array[@base_common.Uri]] = []
  service.on_did_change_markers(changed => fired.push(changed)) |> ignore
  service.change_one("far", a, [marker_data(Error, "a1")])
  service.change_one("far", b, [marker_data(Error, "b1")])
  service.change_one("boo", a, [marker_data(Warning, "a2")])
  // Nothing delivered until the flush; one flush covers the whole tick.
  assert_eq(fired.length(), 0)
  assert_eq(scheduled.length(), 1)
  scheduled[0]()
  assert_eq(fired.length(), 1)
  inspect(
    fired[0].map(u => u.to_string()).join(","),
    content="file:///a.cs,file:///b.cs",
  )
  // The flush resets the queue for the next tick.
  service.change_one("far", b, [])
  assert_eq(scheduled.length(), 2)
  scheduled[1]()
  assert_eq(fired.length(), 2)
  inspect(fired[1].map(u => u.to_string()).join(","), content="file:///b.cs")
}

///|
test "statistics buckets severities and excludes unsupported schemes" {
  let service = MarkerService()
  let file = uri("file:///stats.cs")
  service.change_one("owner", file, [
    marker_data(Error, "e1"),
    marker_data(Error, "e2"),
    marker_data(Warning, "w1"),
    marker_data(Info, "i1"),
  ])
  let stats = service.statistics()
  assert_eq(stats.errors, 2)
  assert_eq(stats.warnings, 1)
  assert_eq(stats.infos, 1)
  // unsupported scheme (inmemory) is excluded from stats
  let scratch = uri("inmemory://scratch")
  service.change_one("owner", scratch, [marker_data(Error, "e")])
  let stats2 = service.statistics()
  assert_eq(stats2.errors, 2)
  // removing markers decrements
  service.change_one("owner", file, [])
  let stats3 = service.statistics()
  assert_eq(stats3.errors, 0)
  assert_eq(stats3.warnings, 0)
  assert_eq(stats3.infos, 0)
}
