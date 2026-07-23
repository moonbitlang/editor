///| Branch-derived conformance tests from
/// `vscode/src/vs/editor/test/common/model/pieceTreeTextBuffer/pieceTreeTextBuffer.test.ts`,
/// in the checked-in vscode source.

///|
fn assert_line1_line2_char_codes(snapshot : TextSnapshot) -> Unit raise {
  assert_eq(snapshot.get_line_char_code(1, 0), 'L')
  assert_eq(snapshot.get_line_char_code(1, 1), 'I')
  assert_eq(snapshot.get_line_char_code(1, 2), 'N')
  assert_eq(snapshot.get_line_char_code(1, 3), 'E')
  assert_eq(snapshot.get_line_char_code(1, 4), '1')
  assert_eq(snapshot.get_line_char_code(1, 5), '\n')
  assert_eq(snapshot.get_line_char_code(2, 0), 'l')
  assert_eq(snapshot.get_line_char_code(2, 1), 'i')
  assert_eq(snapshot.get_line_char_code(2, 2), 'n')
  assert_eq(snapshot.get_line_char_code(2, 3), 'e')
  assert_eq(snapshot.get_line_char_code(2, 4), '2')
}

///|
test "getLineCharCode - issue #45735" {
  assert_line1_line2_char_codes(TextSnapshot("LINE1\nline2"))
}

///|
/// The pinned source fixture uses chunks `['', 'LINE1\n', 'line2']`; the flat
/// Viewer seam has the same observable text and exact assertion sequence.
test "getLineCharCode - issue #47733" {
  assert_line1_line2_char_codes(TextSnapshot("LINE1\nline2"))
}

///|
/// Additional pinned-source branch oracle: LF is the head of a successor when
/// the preceding piece ends exactly after `LINE1`.
test "getLineCharCode piece-end successor returns LF" {
  assert_eq(TextSnapshot("LINE1\nline2").get_line_char_code(1, 5), '\n')
}

///|
/// Additional pinned-source branch oracle: an ordinary successor head is read
/// without confusing it for the later LF.
test "getLineCharCode piece-end successor returns ordinary content" {
  assert_eq(TextSnapshot("LINE1\nline2").get_line_char_code(1, 4), '1')
}

///|
test "panic getLineCharCode true-empty terminal EOF" {
  ignore(TextSnapshot("").get_line_char_code(1, 0))
}

///|
test "panic getLineCharCode nonempty terminal EOF" {
  ignore(TextSnapshot("LINE").get_line_char_code(1, 4))
}

///|
test "panic getLineCharCode trailing-empty terminal EOF" {
  ignore(TextSnapshot("LINE\n").get_line_char_code(2, 0))
}
