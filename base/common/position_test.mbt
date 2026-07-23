// Local tests for the ported `Position` methods.
//
// Unlike the `*_reference_test.mbt` suites, this is not a 1:1 port: in the
// checked-in vscode source
// there is no standalone `position.test.ts` — the editor `Position`
// (vs/editor/common/core/position.ts) is exercised indirectly (e.g. through
// range.test.ts, already ported in `monaco_range_reference_test.mbt`). These
// cases assert the method semantics transcribed from position.ts.

///|
test "Position is one-based on both axes" {
  let p = Position::Position(1, 1)
  assert_eq(p.line_number, 1)
  assert_eq(p.column, 1)
}

///|
test "with_ keeps unspecified axes" {
  let p = Position::Position(3, 5)
  assert_true(p.with_(line_number=7).equals(Position(7, 5)))
  assert_true(p.with_(column=2).equals(Position(3, 2)))
  assert_true(p.with_(line_number=7, column=2).equals(Position(7, 2)))
  assert_true(p.with_().equals(p))
}

///|
test "delta shifts and clamps to at least 1" {
  let p = Position::Position(3, 5)
  assert_true(p.delta(delta_line_number=1).equals(Position(4, 5)))
  assert_true(p.delta(delta_column=-2).equals(Position(3, 3)))
  // Both axes clamp at 1, matching Monaco's Math.max(1, ...).
  assert_true(
    p.delta(delta_line_number=-10, delta_column=-10).equals(Position(1, 1)),
  )
}

///|
test "equals compares both axes" {
  let p = Position::Position(2, 4)
  assert_true(p.equals(Position(2, 4)))
  assert_false(p.equals(Position(2, 5)))
  assert_false(p.equals(Position(3, 4)))
}

///|
test "is_before / is_before_or_equal order by line then column" {
  let a = Position::Position(2, 2)
  let b = Position::Position(2, 3)
  let c = Position::Position(3, 1)
  assert_true(a.is_before(b))
  assert_true(a.is_before(c))
  assert_false(b.is_before(a))
  assert_false(a.is_before(a))
  assert_true(a.is_before_or_equal(a))
  assert_true(a.is_before_or_equal(b))
  assert_false(b.is_before_or_equal(a))
}

///|
test "compare returns sign by line then column" {
  let a = Position::Position(2, 2)
  let b = Position::Position(2, 5)
  let c = Position::Position(4, 1)
  assert_true(Position::compare(a, b) < 0)
  assert_true(Position::compare(b, a) > 0)
  assert_true(Position::compare(a, a) == 0)
  assert_true(Position::compare(a, c) < 0)
}

///|
test "clone copies both axes" {
  let p = Position::Position(6, 9)
  assert_true(p.clone().equals(p))
}

///|
test "to_string is (line,column)" {
  assert_eq(Position::Position(3, 7).to_string(), "(3,7)")
}
