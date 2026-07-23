///|
fn eol_boundary_uri() -> @base_common.Uri {
  try! @base_common.Uri::parse(
    "readonly-remote://workspace/src/eol-boundary.mbt",
  )
}

///|
/// Remote DocumentSnapshot is the raw provider boundary. Conversion into the
/// viewer model starts normalized LF storage, and the browser harness exports
/// that same normalized value.
test "workbench keeps documents raw and exposes normalized model text" {
  let cases : Array[(String, String)] = [
    ("a\r\nb", "a\nb"),
    ("a\rb", "a\nb"),
    ("a\r\nb\rc\nd", "a\nb\nc\nd"),
    ("tail\r\n", "tail\n"),
    ("🙂\r\nβ\r中\n", "🙂\nβ\n中\n"),
    ("\u{FEFF}head\r\ntail", "\u{FEFF}head\ntail"),
  ]
  for index, sample in cases {
    let raw = sample.0
    let normalized = sample.1
    let document = @workspace.DocumentSnapshot(
      eol_boundary_uri(),
      "eol-boundary.mbt",
      "moonbit",
      "revision-" + index.to_string(),
      raw,
    )
    assert_eq(document.text, raw)
    assert_eq(document.length(), raw.length())
    let model = document_to_text_model(document)
    assert_eq(model.get_value(), normalized)
    assert_eq(model.get_value_length(), normalized.length())
    assert_eq(model.snapshot.text, normalized)
    let parsed = try! @json.parse(text_model_harness_json(model))
    guard parsed is { "text": String(harness_text), .. } else {
      fail("expected harness text field")
    }
    assert_eq(harness_text, normalized)
    model.dispose()
  }
}
