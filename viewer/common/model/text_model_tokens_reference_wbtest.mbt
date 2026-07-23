///| Conformance slice for the retained `RangePriorityQueueImpl` operations.
///
/// Source: `vscode/src/vs/editor/test/common/model/textModelTokens.test.ts` at
/// checked-in source. The applicable upstream test
/// keeps its original name; the incremental-resize case is explicitly skipped
/// below. Branch-derived cases cover the queue operations retained by current
/// tokenization state tracking.

///|
fn or_strings(ranges : Array[@base_common.OffsetRange]) -> Array[String] {
  ranges.map(fn(r) { r.to_string() })
}

///|
/// Element-wise string-array equality (avoids the deprecated `Show`-based
/// `assert_eq` on arrays while keeping per-element failure detail).
fn assert_str_array_eq(
  actual : Array[String],
  expected : Array[String],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i], expected[i])
  }
}

///|
test "addRange" {
  let ranges : Array[@base_common.OffsetRange] = []
  @base_common.OffsetRange::add_range(OffsetRange(0, 2), ranges)
  @base_common.OffsetRange::add_range(OffsetRange(10, 13), ranges)
  @base_common.OffsetRange::add_range(OffsetRange(20, 24), ranges)
  assert_str_array_eq(or_strings(ranges), ["[0, 2)", "[10, 13)", "[20, 24)"])
  @base_common.OffsetRange::add_range(OffsetRange(2, 10), ranges)
  assert_str_array_eq(or_strings(ranges), ["[0, 13)", "[20, 24)"])
  @base_common.OffsetRange::add_range(OffsetRange(14, 19), ranges)
  assert_str_array_eq(or_strings(ranges), ["[0, 13)", "[14, 19)", "[20, 24)"])
  @base_common.OffsetRange::add_range(OffsetRange(10, 22), ranges)
  assert_str_array_eq(or_strings(ranges), ["[0, 24)"])
  @base_common.OffsetRange::add_range(OffsetRange(-1, 29), ranges)
  assert_str_array_eq(or_strings(ranges), ["[-1, 29)"])
  @base_common.OffsetRange::add_range(OffsetRange(-10, -5), ranges)
  assert_str_array_eq(or_strings(ranges), ["[-10, -5)", "[-1, 29)"])
}

// SKIPPED: addRangeAndResize — readonly Viewer has no incremental edit producer,
// and the corresponding queue operation has no current production consumer.

///|
test "RangePriorityQueueImpl min delete and addRange" {
  let queue = RangePriorityQueueImpl()
  assert_true(queue.min() is None)
  queue.add_range(OffsetRange(1, 2))
  queue.add_range(OffsetRange(4, 8))
  assert_str_array_eq(or_strings(queue.ranges), ["[1, 2)", "[4, 8)"])
  assert_true(queue.min() == Some(1))
  queue.delete(1)
  assert_str_array_eq(or_strings(queue.ranges), ["[4, 8)"])
  queue.delete(4)
  assert_str_array_eq(or_strings(queue.ranges), ["[5, 8)"])
  queue.delete(7)
  assert_str_array_eq(or_strings(queue.ranges), ["[5, 7)"])
  queue.delete(6)
  assert_str_array_eq(or_strings(queue.ranges), ["[5, 6)"])
  queue.delete(5)
  assert_true(queue.ranges.is_empty())
  queue.delete(999)
  assert_true(queue.ranges.is_empty())
}

///|
test "RangePriorityQueueImpl delete splits interior and addRange covers boundaries" {
  let queue = RangePriorityQueueImpl()
  queue.add_range(OffsetRange(10, 20))
  queue.delete(15)
  assert_str_array_eq(or_strings(queue.ranges), ["[10, 15)", "[16, 20)"])
  queue.add_range(OffsetRange(15, 16))
  assert_str_array_eq(or_strings(queue.ranges), ["[10, 20)"])
  queue.add_range(OffsetRange(12, 14))
  assert_str_array_eq(or_strings(queue.ranges), ["[10, 20)"])
  queue.add_range(OffsetRange(0, 30))
  assert_str_array_eq(or_strings(queue.ranges), ["[0, 30)"])
}
