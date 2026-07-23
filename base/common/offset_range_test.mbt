// Local tests for the ported `OffsetRange` methods.
//
// Like `position_test.mbt`, this is not a 1:1 reference port: the checked-in
// vscode source has no
// `offsetRange.test.ts`. These cases assert the method semantics transcribed
// from `core/ranges/offsetRange.ts`.

///|
/// Constructor shorthand: a bare `OffsetRange(...)` only resolves when the
/// expected type is known, so build through a helper whose return type supplies
/// it.
fn or_(start : Int, end_exclusive : Int) -> OffsetRange {
  OffsetRange(start, end_exclusive)
}

///|
test "constructors and fields" {
  let r = or_(3, 8)
  assert_eq(r.start, 3)
  assert_eq(r.end_exclusive, 8)
  assert_eq(r.length(), 5)
  // Deviation from Monaco: invalid input normalizes instead of throwing.
  let swapped = or_(8, 3)
  assert_eq(swapped.start, 3)
  assert_eq(swapped.end_exclusive, 8)
  assert_true(OffsetRange::from_to(3, 8).equals(r))
  assert_true(OffsetRange::of_length(5).equals(or_(0, 5)))
  assert_true(OffsetRange::of_start_and_length(3, 5).equals(r))
  assert_true(OffsetRange::empty_at(4).equals(or_(4, 4)))
}

///|
test "try_create returns None for inverted ranges" {
  assert_true(OffsetRange::try_create(3, 8) is Some(_))
  assert_true(OffsetRange::try_create(8, 3) is None)
  assert_true(OffsetRange::try_create(5, 5) is Some(_))
}

///|
test "is_empty and length" {
  assert_true(or_(4, 4).is_empty())
  assert_false(or_(4, 5).is_empty())
  assert_eq(or_(4, 4).length(), 0)
  assert_eq(or_(2, 9).length(), 7)
}

///|
test "delta / delta_start / delta_end" {
  let r = or_(3, 8)
  assert_true(r.delta(2).equals(or_(5, 10)))
  assert_true(r.delta_start(1).equals(or_(4, 8)))
  assert_true(r.delta_end(2).equals(or_(3, 10)))
}

///|
test "contains and contains_range" {
  let r = or_(3, 8)
  assert_true(r.contains(3))
  assert_true(r.contains(7))
  assert_false(r.contains(8))
  assert_false(r.contains(2))
  assert_true(r.contains_range(or_(4, 7)))
  assert_true(r.contains_range(or_(3, 8)))
  assert_false(r.contains_range(or_(3, 9)))
  assert_false(r.contains_range(or_(2, 4)))
}

///|
test "join" {
  assert_true(or_(3, 5).join(or_(8, 10)).equals(or_(3, 10)))
  assert_true(or_(3, 8).join(or_(4, 6)).equals(or_(3, 8)))
}

///|
test "intersect / intersection_length" {
  // Overlapping.
  guard or_(3, 8).intersect(or_(5, 10)) is Some(i)
  assert_true(i.equals(or_(5, 8)))
  assert_eq(or_(3, 8).intersection_length(or_(5, 10)), 3)
  // Touching: empty intersection, length 0.
  guard or_(3, 5).intersect(or_(5, 9)) is Some(touch)
  assert_true(touch.is_empty())
  assert_eq(or_(3, 5).intersection_length(or_(5, 9)), 0)
  // Disjoint: None.
  assert_true(or_(3, 4).intersect(or_(6, 9)) is None)
  assert_eq(or_(3, 4).intersection_length(or_(6, 9)), 0)
}

///|
test "intersects vs intersects_or_touches" {
  assert_true(or_(3, 8).intersects(or_(5, 10)))
  // Touching ranges: intersects is false, intersects_or_touches is true.
  assert_false(or_(3, 5).intersects(or_(5, 9)))
  assert_true(or_(3, 5).intersects_or_touches(or_(5, 9)))
  // Empty range never intersects.
  assert_false(or_(5, 5).intersects(or_(3, 8)))
}

///|
test "is_before / is_after" {
  assert_true(or_(3, 5).is_before(or_(5, 9)))
  assert_true(or_(3, 5).is_before(or_(6, 9)))
  assert_false(or_(3, 6).is_before(or_(5, 9)))
  assert_true(or_(6, 9).is_after(or_(3, 6)))
  assert_false(or_(5, 9).is_after(or_(3, 6)))
}

///|
test "to_string" {
  assert_eq(or_(3, 8).to_string(), "[3, 8)")
}
