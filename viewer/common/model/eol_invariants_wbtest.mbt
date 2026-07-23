///| Fixed-LF construction/read invariants for the approved EOL Option B.
/// These tests derive their expectations from the pinned builder, buffer, and
/// TextModel branches inventoried in `viewer-text-buffer-eol-parity.md`.

///|
fn eol_assert_offset_round_trips(snapshot : TextSnapshot) -> Unit raise {
  for offset in 0..<=snapshot.get_length() {
    let position = snapshot.get_position_at(offset)
    assert_eq(
      snapshot.get_offset_at(position.line_number, position.column),
      offset,
    )
  }
}

///|
fn eol_assert_model_offset_round_trips(model : TextModel) -> Unit raise {
  for offset in 0..<=model.get_value_length() {
    let position = model.get_position_at(offset)
    assert_eq(model.get_offset_at(position), offset)
  }
  let full = model.get_full_model_range()
  assert_eq(
    model.get_offset_at(full.get_end_position()),
    model.get_value_length(),
  )
}

///|
/// The approved readonly seam clamps invalid integer positions/ranges instead
/// of throwing. Exercise both extremes for every construction-corpus member,
/// after its raw EOL form has entered the normalized coordinate space.
fn eol_assert_invalid_clamps(
  snapshot : TextSnapshot,
  model : TextModel,
) -> Unit raise {
  let length = snapshot.get_length()
  let end_position = snapshot.get_position_at(length)
  let low_position = snapshot.get_position_at(-100)
  assert_eq(low_position.line_number, 1)
  assert_eq(low_position.column, 1)
  let high_position = snapshot.get_position_at(length + 100)
  assert_true(high_position == end_position)
  assert_eq(snapshot.get_offset_at(-100, -100), 0)
  assert_eq(snapshot.get_offset_at(100, 100), length)
  assert_eq(model.get_offset_at(Position(-100, -100)), 0)
  assert_eq(model.get_offset_at(Position(100, 100)), length)
  let oversized : @base_common.Range = Range(-100, -100, 100, 100)
  assert_true(model.validate_range(oversized) == model.get_full_model_range())
  assert_eq(snapshot.get_value_in_range(oversized), snapshot.get_value())
  assert_eq(model.get_value_in_range(oversized), model.get_value())
  assert_eq(
    model.get_value_length_in_range(oversized),
    model.get_value_length(),
  )
}

///|
fn eol_assert_lines(
  snapshot : TextSnapshot,
  expected : Array[String],
) -> Unit raise {
  assert_eq(snapshot.line_count(), expected.length())
  let mut start = 0
  for i, line in expected {
    assert_eq(snapshot.line_start_offset(i), start)
    assert_eq(snapshot.line_text(i), line)
    assert_eq(snapshot.get_line_content(i + 1), line)
    assert_eq(snapshot.get_line_length(i + 1), line.length())
    let max_column = line.length() + 1
    for column in 1..<=max_column {
      let offset = start + column - 1
      assert_eq(snapshot.get_offset_at(i + 1, column), offset)
      let position = snapshot.get_position_at(offset)
      assert_eq(position.line_number, i + 1)
      assert_eq(position.column, column)
    }
    start += line.length()
    if i + 1 < expected.length() {
      start += 1
    }
  }
}

///|
fn eol_assert_same_code_units(actual : String, expected : String) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i].to_int(), expected[i].to_int())
  }
}

///|
test "fixed-LF construction corpus keeps one coherent coordinate system" {
  let corpus : Array[(String, String, Array[String])] = [
    ("", "", [""]),
    ("one", "one", ["one"]),
    ("one\ntwo", "one\ntwo", ["one", "two"]),
    ("one\r\ntwo", "one\ntwo", ["one", "two"]),
    ("one\rtwo", "one\ntwo", ["one", "two"]),
    ("a\r\nb\nc\rd", "a\nb\nc\nd", ["a", "b", "c", "d"]),
    ("\r\na", "\na", ["", "a"]),
    ("a\r\n", "a\n", ["a", ""]),
    ("a\r\n\r\nb", "a\n\nb", ["a", "", "b"]),
    ("\r\n", "\n", ["", ""]),
    ("a\r", "a\n", ["a", ""]),
    ("\rX", "\nX", ["", "X"]),
    ("\r\r", "\n\n", ["", "", ""]),
    ("\n\r", "\n\n", ["", "", ""]),
    ("a\u{2028}b\u{2029}c", "a\u{2028}b\u{2029}c", ["a\u{2028}b\u{2029}c"]),
    ("\u{FEFF}a\r\nb", "\u{FEFF}a\nb", ["\u{FEFF}a", "b"]),
    ("a\u{FEFF}b\r\nc", "a\u{FEFF}b\nc", ["a\u{FEFF}b", "c"]),
  ]
  for item in corpus {
    let (raw, normalized, lines) = item
    let snapshot = TextSnapshot(raw)
    assert_eq(snapshot.text, normalized)
    assert_eq(snapshot.get_value(), normalized)
    assert_eq(snapshot.get_length(), normalized.length())
    assert_eq(snapshot.get_eol(), "\n")
    eol_assert_lines(snapshot, lines)
    eol_assert_offset_round_trips(snapshot)
    let model = wb_model(raw)
    assert_eq(model.snapshot.text, normalized)
    assert_eq(model.get_value(), normalized)
    assert_eq(model.get_value_length(), normalized.length())
    assert_eq(model.get_eol(), "\n")
    assert_true(model.get_lines_content() == lines)
    eol_assert_model_offset_round_trips(model)
    eol_assert_invalid_clamps(snapshot, model)
  }
}

///|
/// Gate-D regression: raw UTF-16 slicing must not require Unicode-scalar
/// boundaries. This covers both lone high and lone low surrogates before and
/// after normalized EOLs, line-start/range boundaries, and either half of a
/// valid pair through the snapshot's offset slice.
test "lone surrogate code units survive EOL and range boundaries" {
  let d800 = Int::unsafe_to_char(0xD800).to_string()
  let dbff = Int::unsafe_to_char(0xDBFF).to_string()
  let dc00 = Int::unsafe_to_char(0xDC00).to_string()
  let dfff = Int::unsafe_to_char(0xDFFF).to_string()
  for held in [d800, dbff, dc00, dfff] {
    let leading = TextSnapshot("\r" + held)
    eol_assert_same_code_units(leading.get_value(), "\n" + held)
    eol_assert_same_code_units(leading.get_line_content(2), held)
    eol_assert_same_code_units(leading.slice(OffsetRange(1, 2)), held)
    eol_assert_same_code_units(
      leading.get_value_in_range(Range(2, 1, 2, 2)),
      held,
    )
    let trailing = TextSnapshot(held + "\r\n")
    eol_assert_same_code_units(trailing.get_value(), held + "\n")
    eol_assert_same_code_units(trailing.get_line_content(1), held)
    eol_assert_same_code_units(trailing.slice(OffsetRange(0, 1)), held)
    let model = wb_model("a\r\n" + held)
    eol_assert_same_code_units(model.get_value(), "a\n" + held)
    eol_assert_same_code_units(
      model.get_value_in_range(Range(2, 1, 2, 2)),
      held,
    )
  }
  let pair = "\u{1F60A}"
  let high = Int::unsafe_to_char(0xD83D).to_string()
  let low = Int::unsafe_to_char(0xDE0A).to_string()
  let pair_snapshot = TextSnapshot(pair)
  eol_assert_same_code_units(pair_snapshot.slice(OffsetRange(0, 1)), high)
  eol_assert_same_code_units(pair_snapshot.slice(OffsetRange(1, 2)), low)
}

///|
/// Exhaust every half-open range in small ASCII/EOL fixtures. Position and
/// offset bounds are all UTF-16 bounds, and returned value length must equal
/// both the slice length and the end-minus-start offset difference.
test "every small offset range agrees with value and length" {
  for value in ["", "a", "a\nb", "\na", "a\n", "a\n\nb"] {
    let snapshot = TextSnapshot(value)
    let model = wb_model(value)
    for start in 0..<=snapshot.get_length() {
      for end in start..<=snapshot.get_length() {
        let range = snapshot.range_of(OffsetRange(start, end))
        let actual = snapshot.get_value_in_range(range)
        let expected = value[start:end].to_owned()
        assert_eq(actual, expected)
        assert_eq(snapshot.get_value_length_in_range(range), expected.length())
        let offsets = snapshot.offset_range_of(range)
        assert_eq(offsets.start, start)
        assert_eq(offsets.end_exclusive, end)
        assert_eq(offsets.end_exclusive - offsets.start, actual.length())
        assert_eq(model.get_value_in_range(range), expected)
        assert_eq(model.get_value_length_in_range(range), expected.length())
      }
    }
  }
}

///|
/// `getPositionAt` is relaxed like Monaco: every UTF-16 offset, including the
/// boundary between a valid surrogate pair, round-trips exactly.
test "every surrogate-pair UTF-16 offset round-trips" {
  let snapshot = TextSnapshot("a\u{1F60A}\r\n中")
  eol_assert_offset_round_trips(snapshot)
  let model = wb_model("a\u{1F60A}\r\n中")
  eol_assert_model_offset_round_trips(model)
}

///|
test "metadata is derived from complete normalized text" {
  let basic = TextSnapshot("ASCII\t0126 ~\r\n")
  assert_eq(basic.might_contain_non_basic_ascii(), false)
  assert_eq(basic.might_contain_rtl(), false)
  assert_eq(TextSnapshot("\u{0001}").might_contain_non_basic_ascii(), true)
  assert_eq(TextSnapshot("Zürich").might_contain_non_basic_ascii(), true)
  assert_eq(TextSnapshot("e\u{0301}").might_contain_non_basic_ascii(), true)
  assert_eq(TextSnapshot("זוהי").might_contain_non_basic_ascii(), true)
  assert_eq(TextSnapshot("זוהי").might_contain_rtl(), true)
  assert_eq(TextSnapshot("\u{1F60A}").might_contain_non_basic_ascii(), true)
  let separators = TextSnapshot("a\u{2028}b\u{2029}c")
  assert_eq(separators.line_count(), 1)
  assert_eq(separators.might_contain_non_basic_ascii(), true)
  assert_eq(TextSnapshot("\u{FEFF}").might_contain_non_basic_ascii(), true)
  let model = wb_model("ASCII\t\r\nזוהי")
  assert_eq(model.might_contain_non_basic_ascii(), true)
  assert_eq(model.might_contain_rtl(), true)
}

///|
/// ORACLE-001 local side: pinned builder/factory duplicates a singleton held
/// CR/D800/DBFF (also after source-only BOM stripping), and leaves the
/// basic-prefix trailing-high-surrogate metadata stale. Gate A instead keeps
/// exactly one input code unit, retains U+FEFF as content, and computes the
/// metadata from the complete stored value.
test "held-unit ORACLE local adaptation preserves one unit and fresh metadata" {
  let bom = "\u{FEFF}"
  let d800 = Int::unsafe_to_char(0xD800).to_string()
  let dbff = Int::unsafe_to_char(0xDBFF).to_string()
  let bare_cr = TextSnapshot("\r")
  assert_eq(bare_cr.text, "\n")
  assert_eq(bare_cr.get_length(), 1)
  assert_eq(bare_cr.line_count(), 2)
  let bom_cr = TextSnapshot(bom + "\r")
  assert_eq(bom_cr.text, bom + "\n")
  assert_eq(bom_cr.get_length(), 2)
  for held in [d800, dbff] {
    let bare = TextSnapshot(held)
    assert_eq(bare.get_length(), 1)
    assert_eq(bare.text[0].to_int(), held[0].to_int())
    assert_eq(bare.might_contain_non_basic_ascii(), true)
    eol_assert_offset_round_trips(bare)
    let prefixed_bom = TextSnapshot(bom + held)
    assert_eq(prefixed_bom.get_length(), 2)
    assert_eq(prefixed_bom.text[0].to_int(), 0xFEFF)
    assert_eq(prefixed_bom.text[1].to_int(), held[0].to_int())
    assert_eq(prefixed_bom.might_contain_non_basic_ascii(), true)
    let accepted_prefix = TextSnapshot("a" + held)
    assert_eq(accepted_prefix.get_length(), 2)
    assert_eq(accepted_prefix.text[0].to_int(), 'a')
    assert_eq(accepted_prefix.text[1].to_int(), held[0].to_int())
    assert_eq(accepted_prefix.might_contain_non_basic_ascii(), true)
    let model = wb_model("a" + held)
    assert_eq(model.get_value_length(), 2)
    assert_eq(model.get_value().length(), 2)
    assert_eq(model.snapshot.text[1].to_int(), held[0].to_int())
    assert_eq(model.get_value()[1].to_int(), held[0].to_int())
    assert_eq(model.might_contain_non_basic_ascii(), true)
    let before_cr = TextSnapshot(held + "\r")
    assert_eq(before_cr.get_length(), 2)
    assert_eq(before_cr.text[0].to_int(), held[0].to_int())
    assert_eq(before_cr.text[1].to_int(), 10)
    let after_cr = TextSnapshot("\r" + held)
    assert_eq(after_cr.get_length(), 2)
    assert_eq(after_cr.text[0].to_int(), 10)
    assert_eq(after_cr.text[1].to_int(), held[0].to_int())
  }
  let trailing_cr = TextSnapshot("a\r")
  assert_eq(trailing_cr.text, "a\n")
  assert_eq(trailing_cr.get_length(), 2)
}

///|
/// PieceTreeBase.equal's four source exits: length mismatch, equal length but
/// line-count mismatch, equal length/count but content mismatch, and equality.
test "normalized equality covers all four source exits" {
  assert_eq(TextSnapshot("a").equals(TextSnapshot("aa")), false)
  assert_eq(TextSnapshot("ab").equals(TextSnapshot("a\n")), false)
  assert_eq(TextSnapshot("ab").equals(TextSnapshot("ac")), false)
  assert_eq(TextSnapshot("a\r\nb").equals(TextSnapshot("a\nb")), true)
  assert_eq(TextSnapshot("\u{FEFF}a").equals(TextSnapshot("a")), false)
}
