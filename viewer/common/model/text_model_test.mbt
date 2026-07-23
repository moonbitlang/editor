///|
test "text snapshot normalizes lf and crlf before deriving offsets" {
  let doc = @model.TextSnapshot("one\ntwo\r\nthree")
  assert_eq(doc.text, "one\ntwo\nthree")
  assert_eq(doc.line_count(), 3)
  assert_eq(doc.line_text(0), "one")
  assert_eq(doc.line_text(1), "two")
  assert_eq(doc.line_text(2), "three")
  assert_eq(doc.line_start_offset(2), 8)
}

///|
test "text snapshot handles lonely cr" {
  let doc = @model.TextSnapshot("one\rtwo\r\rthree\r")
  assert_eq(doc.line_count(), 5)
  assert_eq(doc.line_text(0), "one")
  assert_eq(doc.line_text(1), "two")
  assert_eq(doc.line_text(2), "")
  assert_eq(doc.line_text(3), "three")
  assert_eq(doc.line_text(4), "")
  // Offset↔position round trip across the CR break: offset 4 is the 't' of
  // "two" (line 2, column 1); the position converts back to the same offset.
  let pos = doc.get_position_at(4)
  assert_eq(pos.line_number, 2)
  assert_eq(pos.column, 1)
  assert_eq(doc.get_offset_at(2, 1), 4)
}

///|
test "offset and position use utf16 code units" {
  let doc = @model.TextSnapshot("a😊\n中")
  assert_eq(doc.get_length(), 5)
  let pos = doc.get_position_at(3)
  assert_eq(pos.line_number, 1)
  assert_eq(pos.column, 4)
  assert_eq(doc.get_offset_at(2, 2), 5)
}

///|
test "text model owns uri and version identity" {
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/main.mbt",
    ),
    "main.mbt",
    "moonbit",
    3,
    "rev-3",
    "pub fn main {}\n",
  )
  assert_eq(model.uri.to_string(), "inmemory://model/main.mbt")
  assert_eq(model.display_name, "main.mbt")
  assert_eq(model.language_id, "moonbit")
  assert_eq(model.version, 3)
  assert_eq(model.revision, "rev-3")
  assert_eq(model.snapshot().text, "pub fn main {}\n")
  assert_true(model.same(model))
  let same_document = @model.TextModel(
    model.uri,
    model.display_name,
    model.language_id,
    model.version,
    model.revision,
    model.get_value(),
  )
  assert_false(model.same(same_document))
}

///|
test "dispose fires on_will_dispose once and flips is_disposed" {
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/dispose.mbt",
    ),
    "dispose.mbt",
    "moonbit",
    1,
    "",
    "pub fn main {}\n",
  )
  let mut will_dispose_count = 0
  model.on_will_dispose(() => will_dispose_count += 1) |> ignore
  assert_false(model.is_disposed())
  model.dispose()
  assert_eq(will_dispose_count, 1)
  assert_true(model.is_disposed())
  // Reads survive dispose: the snapshot is immutable, `_assertNotDisposed`
  // guards are not ported.
  assert_eq(model.get_line_count(), 2)
  // A second dispose is inert — the emitter is already disposed.
  model.dispose()
  assert_eq(will_dispose_count, 1)
}
