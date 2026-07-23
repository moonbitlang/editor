///|
fn mapping(
  original_start : Int,
  original_end_exclusive : Int,
  modified_start : Int,
  modified_end_exclusive : Int,
) -> @diff.DetailedLineRangeMapping {
  DetailedLineRangeMapping(
    LineRange(original_start, original_end_exclusive),
    LineRange(modified_start, modified_end_exclusive),
    None,
  )
}

///|
fn change_str(change : @diff.Change) -> String {
  "(\{change.original_start_line_number},\{change.original_end_line_number})->(\{change.modified_start_line_number},\{change.modified_end_line_number})"
}

///|
test "to_line_changes re-encodes the three change shapes (diffEditorWidget.ts:759)" {
  // Modification: exclusive ends become inclusive.
  assert_eq(
    change_str(to_line_changes([mapping(2, 4, 2, 3)])[0]),
    "(2,3)->(2,2)",
  )
  // Insertion: empty original side → start-1 / 0.
  assert_eq(
    change_str(to_line_changes([mapping(2, 2, 2, 4)])[0]),
    "(1,0)->(2,3)",
  )
  // Deletion: empty modified side → start-1 / 0.
  assert_eq(
    change_str(to_line_changes([mapping(2, 4, 2, 2)])[0]),
    "(2,3)->(1,0)",
  )
}

///|
test "compute_changes runs the full pipeline over line arrays" {
  let changes = compute_changes(["a", "old", "b", "tail"], [
    "a", "new", "b", "inserted", "tail",
  ])
  assert_eq(changes.length(), 2)
  assert_eq(change_str(changes[0]), "(2,2)->(2,2)")
  assert_eq(@quick_diff.get_change_type(changes[0]), Modify)
  assert_eq(change_str(changes[1]), "(3,0)->(4,4)")
  assert_eq(@quick_diff.get_change_type(changes[1]), Add)
}

///|
test "compute_changes honors ignore_trim_whitespace" {
  let original = ["fn x {", "  y", "}"]
  let modified = ["fn x {", "      y", "}"]
  assert_eq(compute_changes(original, modified).length(), 1)
  assert_eq(
    compute_changes(original, modified, ignore_trim_whitespace=true).length(),
    0,
  )
}
