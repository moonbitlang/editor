///|
test "range normalizes endpoints and tests offsets" {
  let range : OffsetRange = OffsetRange(8, 3)
  assert_eq(range.start, 3)
  assert_eq(range.end_exclusive, 8)
  assert_true(range.contains(3))
  assert_true(!range.contains(8))
  assert_true(range.intersects(OffsetRange(7, 10)))
  assert_true(!range.intersects(OffsetRange(8, 10)))
}

///|
test "clamps ints" {
  assert_eq(clamp_int(-1, 0, 10), 0)
  assert_eq(clamp_int(4, 0, 10), 4)
  assert_eq(clamp_int(99, 0, 10), 10)
}
