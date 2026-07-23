///|
fn test_uri() -> @base_common.Uri {
  try! @base_common.Uri::parse("readonly-remote://workspace/src/main.mbt")
}

///|
test "crossing in-flight responses resolve their own requests" {
  let first = next_request_id("hover")
  let second = next_request_id("hover")
  let resolved : Array[String] = []
  pending_requests[first] = packet => {
    resolved.push("first<-" + server_packet_request_id(packet))
  }
  pending_requests[second] = packet => {
    resolved.push("second<-" + server_packet_request_id(packet))
  }
  // The second request answers before the first: ids keep them apart.
  assert_true(
    resolve_pending_response(
      HoverResult({
        id: second,
        uri: test_uri(),
        revision: "rev-2",
        hover: None,
      }),
    ),
  )
  assert_true(
    resolve_pending_response(
      HoverResult({ id: first, uri: test_uri(), revision: "rev-1", hover: None }),
    ),
  )
  debug_inspect(
    resolved,
    content=(
      #|["second<-hover-2", "first<-hover-1"]
    ),
  )
  // Each entry resolves exactly once.
  assert_false(
    resolve_pending_response(
      HoverResult({ id: first, uri: test_uri(), revision: "rev-1", hover: None }),
    ),
  )
  assert_eq(pending_requests.length(), 0)
}

///|
test "push packets without a pending id fall through" {
  assert_false(
    resolve_pending_response(
      DocumentChanged({
        id: "watch:readonly-remote://workspace/src/main.mbt",
        document: DocumentSnapshot(
          test_uri(),
          "main.mbt",
          "moonbit",
          "rev",
          "fn main {}",
        ),
      }),
    ),
  )
  assert_false(
    resolve_pending_response(
      RemoteError(ProtocolError(ProtocolProviderError, "boom")),
    ),
  )
}
