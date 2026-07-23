// Behavior tests for the piediff-backed `DefaultLinesDiffComputer`.
//
// The engine deviates from Monaco's by design (see the impl file header), so
// unlike the `*_reference_test.mbt` suites these do NOT byte-compare against
// Monaco's outputs: hunk boundaries may legally differ by tie-breaking among
// equal adjacent lines. Instead every case asserts
// - the invariants Monaco's own assertion harness enforces on any valid
//   result (sorted, strictly separated hunks with equal line deltas), and
// - a reconstruction round-trip: applying `changes` to the original must
//   reproduce the modified document exactly;
// plus exact hunks on fixtures where the minimal diff is unambiguous.

///|
let default_options : @diff.LinesDiffComputerOptions = {
  ignore_trim_whitespace: false,
  max_computation_time_ms: 0,
  compute_moves: false,
}

///|
fn compute(
  original : Array[String],
  modified : Array[String],
  options? : @diff.LinesDiffComputerOptions = default_options,
) -> @diff.LinesDiff {
  @diff.get_default().compute_diff(original, modified, options)
}

///|
/// Renders a result's hunks as one comparable string (Array's `Show` is
/// deprecated toolchain-wide, so tests compare joined strings).
fn hunks(result : @diff.LinesDiff) -> String {
  result.changes.map(@diff.DetailedLineRangeMapping::to_string).join(", ")
}

///|
/// The `{[originalStart,originalEndExclusive)->[modifiedStart,
/// modifiedEndExclusive)}` rendering of one expected hunk.
fn hunk(
  original_start : Int,
  original_end_exclusive : Int,
  modified_start : Int,
  modified_end_exclusive : Int,
) -> String {
  "{[\{original_start},\{original_end_exclusive})->[\{modified_start},\{modified_end_exclusive})}"
}

///|
/// Applies `changes` to `original`: copy unchanged original lines, splice in
/// the modified side of each hunk.
fn apply_changes(
  original : Array[String],
  modified : Array[String],
  changes : Array[@diff.DetailedLineRangeMapping],
) -> Array[String] {
  let result : Array[String] = []
  let mut next_original_line = 1
  for change in changes {
    for line in next_original_line..<change.original.start_line_number {
      result.push(original[line - 1])
    }
    for
      line in change.modified.start_line_number..<change.modified.end_line_number_exclusive {
      result.push(modified[line - 1])
    }
    next_original_line = change.original.end_line_number_exclusive
  }
  for line in next_original_line..<(original.length() + 1) {
    result.push(original[line - 1])
  }
  result
}

///|
/// The invariants `lineRangeMappingFromRangeMappings`' assertion enforces
/// (`rangeMapping.ts:340-356`): hunks are sorted, strictly separated by at
/// least one unchanged line on both sides, and the gap between consecutive
/// hunks is the same number of lines on both sides.
fn assert_valid(
  original : Array[String],
  modified : Array[String],
  result : @diff.LinesDiff,
) -> Unit raise {
  for i in 1..<result.changes.length() {
    let m1 = result.changes[i - 1]
    let m2 = result.changes[i]
    assert_true(
      m1.original.end_line_number_exclusive < m2.original.start_line_number,
    )
    assert_true(
      m1.modified.end_line_number_exclusive < m2.modified.start_line_number,
    )
    assert_eq(
      m2.original.start_line_number - m1.original.end_line_number_exclusive,
      m2.modified.start_line_number - m1.modified.end_line_number_exclusive,
    )
  }
  assert_eq(
    apply_changes(original, modified, result.changes).join("\n"),
    modified.join("\n"),
  )
}

///|
test "identical documents produce no changes" {
  let result = compute(["a", "b", "c"], ["a", "b", "c"])
  assert_eq(hunks(result), "")
  assert_false(result.hit_timeout)
  // The `length <= 1` trivial branch.
  assert_eq(hunks(compute([""], [""])), "")
  assert_eq(hunks(compute(["x"], ["x"])), "")
}

///|
test "insertion only" {
  let original = ["a", "b"]
  let modified = ["a", "x", "y", "b"]
  let result = compute(original, modified)
  // Original side is empty and anchored after line 1; modified side spans
  // lines 2..3.
  assert_eq(hunks(result), hunk(2, 2, 2, 4))
  assert_valid(original, modified, result)
}

///|
test "deletion only" {
  let original = ["a", "x", "y", "b"]
  let modified = ["a", "b"]
  let result = compute(original, modified)
  assert_eq(hunks(result), hunk(2, 4, 2, 2))
  assert_valid(original, modified, result)
}

///|
test "modification maps to one hunk with both sides non-empty" {
  let original = ["a", "old", "b"]
  let modified = ["a", "new", "b"]
  let result = compute(original, modified)
  assert_eq(hunks(result), hunk(2, 3, 2, 3))
  assert_valid(original, modified, result)
}

///|
test "unbalanced modification keeps one hunk" {
  let original = ["a", "old", "b"]
  let modified = ["a", "new1", "new2", "new3", "b"]
  let result = compute(original, modified)
  assert_eq(hunks(result), hunk(2, 3, 2, 5))
  assert_valid(original, modified, result)
}

///|
test "multiple separated hunks stay separated" {
  let original = ["a", "one", "b", "c", "two", "d"]
  let modified = ["a", "ONE", "b", "c", "d", "e"]
  let result = compute(original, modified)
  assert_eq(
    hunks(result),
    [hunk(2, 3, 2, 3), hunk(5, 6, 5, 5), hunk(7, 7, 6, 7)].join(", "),
  )
  assert_valid(original, modified, result)
}

///|
test "insertion at document start and end" {
  let original = ["m"]
  let modified = ["start", "m", "end"]
  let result = compute(original, modified)
  assert_eq(hunks(result), [hunk(1, 1, 1, 2), hunk(2, 2, 3, 4)].join(", "))
  assert_valid(original, modified, result)
}

///|
test "empty original document maps to one whole-document change" {
  let original = [""]
  let modified = ["a", "b"]
  let result = compute(original, modified)
  assert_eq(hunks(result), hunk(1, 2, 1, 3))
  // This trivial branch is the one place inner changes are populated
  // (`defaultLinesDiffComputer.ts:33`).
  guard result.changes[0].inner_changes is Some(inner)
  assert_eq(
    inner.map(@diff.RangeMapping::to_string).join(", "),
    "{[1,1 -> 1,1]->[1,1 -> 2,2]}",
  )
}

///|
test "empty modified document maps to one whole-document change" {
  let result = compute(["a", "b"], [""])
  assert_eq(hunks(result), hunk(1, 3, 1, 2))
}

///|
test "ignore trim whitespace treats reindented lines as unchanged" {
  let original = ["fn main {", "  body", "}"]
  let modified = ["fn main {", "      body", "}"]
  assert_eq(
    hunks(
      compute(original, modified, options={
        ignore_trim_whitespace: true,
        max_computation_time_ms: 0,
        compute_moves: false,
      }),
    ),
    "",
  )
  // ...while the default options see a modification.
  assert_eq(hunks(compute(original, modified)), hunk(2, 3, 2, 3))
}

///|
test "interleaved edits round-trip" {
  let original = [
    "package demo", "", "fn alpha() {", "  return 1", "}", "", "fn beta() {", "  return 2",
    "}", "", "fn gamma() {", "  return 3", "}",
  ]
  let modified = [
    "package demo", "", "// docs", "fn alpha() {", "  return 10", "}", "", "fn beta() {",
    "  return 2", "}", "", "fn delta() {", "  return 4", "}", "", "fn gamma() {",
    "  return 3", "}",
  ]
  let result = compute(original, modified)
  assert_valid(original, modified, result)
  assert_true(result.changes.length() >= 2)
}

///|
test "completely disjoint documents round-trip" {
  let original = ["a", "b", "c"]
  let modified = ["x", "y"]
  let result = compute(original, modified)
  assert_eq(hunks(result), hunk(1, 4, 1, 3))
  assert_valid(original, modified, result)
}

///|
test "repeated equal lines still yield a valid separated script" {
  // Repetition is where Myers tie-breaking has latitude; the exact hunk
  // placement is unspecified, validity is not.
  let original = ["x", "x", "x", "x", "x"]
  let modified = ["x", "x", "y", "x", "x", "x"]
  let result = compute(original, modified)
  assert_valid(original, modified, result)
}

///|
test "default computation budget still yields a correct script" {
  // A non-zero budget takes piediff's default cutoff path
  // (suboptimal-but-correct); correctness must hold regardless.
  let original : Array[String] = []
  let modified : Array[String] = []
  for i in 0..<200 {
    original.push("line \{i}")
    modified.push(if i % 7 == 0 { "line \{i} changed" } else { "line \{i}" })
  }
  let result = compute(original, modified, options={
    ignore_trim_whitespace: false,
    max_computation_time_ms: 1000,
    compute_moves: false,
  })
  assert_false(result.hit_timeout)
  assert_valid(original, modified, result)
}

///|
test "moves are never produced" {
  let original = ["block", "a", "b", "c", "tail"]
  let modified = ["a", "b", "c", "tail", "block"]
  let result = compute(original, modified, options={
    ignore_trim_whitespace: false,
    max_computation_time_ms: 0,
    compute_moves: true,
  })
  assert_eq(result.moves.length(), 0)
  assert_valid(original, modified, result)
}
