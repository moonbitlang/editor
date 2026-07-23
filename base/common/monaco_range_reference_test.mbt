// Conformance port of Monaco/VS Code's Range suite.
//
// Ports: vscode/src/vs/editor/test/common/core/range.test.ts
// From the checked-in vscode submodule.

///|
test "empty range" {
  let s = Range::Range(1, 1, 1, 1)
  assert_eq(s.start_line_number, 1)
  assert_eq(s.start_column, 1)
  assert_eq(s.end_line_number, 1)
  assert_eq(s.end_column, 1)
  assert_eq(s.is_empty(), true)
}

///|
test "swap start and stop same line" {
  let s = Range::Range(1, 2, 1, 1)
  assert_eq(s.start_line_number, 1)
  assert_eq(s.start_column, 1)
  assert_eq(s.end_line_number, 1)
  assert_eq(s.end_column, 2)
  assert_eq(s.is_empty(), false)
}

///|
test "swap start and stop" {
  let s = Range::Range(2, 1, 1, 2)
  assert_eq(s.start_line_number, 1)
  assert_eq(s.start_column, 2)
  assert_eq(s.end_line_number, 2)
  assert_eq(s.end_column, 1)
  assert_eq(s.is_empty(), false)
}

///|
test "no swap same line" {
  let s = Range::Range(1, 1, 1, 2)
  assert_eq(s.start_line_number, 1)
  assert_eq(s.start_column, 1)
  assert_eq(s.end_line_number, 1)
  assert_eq(s.end_column, 2)
  assert_eq(s.is_empty(), false)
}

///|
test "no swap" {
  let s = Range::Range(1, 1, 2, 1)
  assert_eq(s.start_line_number, 1)
  assert_eq(s.start_column, 1)
  assert_eq(s.end_line_number, 2)
  assert_eq(s.end_column, 1)
  assert_eq(s.is_empty(), false)
}

///|
test "compareRangesUsingEnds" {
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 1, 1, 3), Range(1, 2, 1, 4)) < 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 1, 1, 3), Range(1, 1, 1, 4)) < 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 2, 1, 3), Range(1, 1, 1, 4)) < 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 1, 1, 4), Range(1, 2, 1, 4)) < 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 1, 1, 4), Range(1, 1, 1, 4)) == 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 2, 1, 4), Range(1, 1, 1, 4)) > 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 1, 1, 5), Range(1, 2, 1, 4)) > 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 1, 2, 4), Range(1, 1, 1, 4)) > 0,
  )
  assert_true(
    Range::compare_ranges_using_ends(Range(1, 2, 5, 1), Range(1, 1, 1, 4)) > 0,
  )
}

///|
test "containsPosition" {
  let r = Range::Range(2, 2, 5, 10)
  assert_eq(r.contains_position(Position(1, 3)), false)
  assert_eq(r.contains_position(Position(2, 1)), false)
  assert_eq(r.contains_position(Position(2, 2)), true)
  assert_eq(r.contains_position(Position(2, 3)), true)
  assert_eq(r.contains_position(Position(3, 1)), true)
  assert_eq(r.contains_position(Position(5, 9)), true)
  assert_eq(r.contains_position(Position(5, 10)), true)
  assert_eq(r.contains_position(Position(5, 11)), false)
  assert_eq(r.contains_position(Position(6, 1)), false)
}

///|
test "containsRange" {
  let r = Range::Range(2, 2, 5, 10)
  assert_eq(r.contains_range(Range(1, 3, 2, 2)), false)
  assert_eq(r.contains_range(Range(2, 1, 2, 2)), false)
  assert_eq(r.contains_range(Range(2, 2, 5, 11)), false)
  assert_eq(r.contains_range(Range(2, 2, 6, 1)), false)
  assert_eq(r.contains_range(Range(5, 9, 6, 1)), false)
  assert_eq(r.contains_range(Range(5, 10, 6, 1)), false)
  assert_eq(r.contains_range(Range(2, 2, 5, 10)), true)
  assert_eq(r.contains_range(Range(2, 3, 5, 9)), true)
  assert_eq(r.contains_range(Range(3, 100, 4, 100)), true)
}

///|
test "areIntersecting" {
  assert_eq(
    Range::are_intersecting(Range(2, 2, 3, 2), Range(4, 2, 5, 2)),
    false,
  )
  assert_eq(
    Range::are_intersecting(Range(4, 2, 5, 2), Range(2, 2, 3, 2)),
    false,
  )
  assert_eq(
    Range::are_intersecting(Range(4, 2, 5, 2), Range(5, 2, 6, 2)),
    false,
  )
  assert_eq(
    Range::are_intersecting(Range(5, 2, 6, 2), Range(4, 2, 5, 2)),
    false,
  )
  assert_eq(Range::are_intersecting(Range(2, 2, 2, 7), Range(2, 4, 2, 6)), true)
  assert_eq(Range::are_intersecting(Range(2, 2, 2, 7), Range(2, 4, 2, 9)), true)
  assert_eq(Range::are_intersecting(Range(2, 4, 2, 9), Range(2, 2, 2, 7)), true)
}
