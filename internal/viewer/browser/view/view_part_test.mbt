///|
/// The `data-mprt` numeric slots are load-bearing (`ElementPath` compares
/// fixed indices against fixed values), so the enum order is pinned by test.
test "part fingerprint numeric slots round-trip" {
  let all : Array[@view.PartFingerprint] = [
    None,
    ContentWidgets,
    OverflowingContentWidgets,
    OverflowGuard,
    OverlayWidgets,
    OverflowingOverlayWidgets,
    ScrollableElement,
    TextArea,
    ViewLines,
    Minimap,
    ViewLinesGpu,
  ]
  for expected_int, fingerprint in all {
    assert_eq(fingerprint.to_int(), expected_int)
    assert_true(@view.PartFingerprint::from_int(expected_int) == fingerprint)
  }
  // Unknown values collapse to `None`, Monaco's missing-attribute default.
  assert_true(@view.PartFingerprint::from_int(99) == None)
  assert_true(@view.PartFingerprint::from_int(-1) == None)
}
