///|
test "source-excluding hidden membership leaves dirty and cached unions intact" {
  let hidden = HiddenAreasModel::new()
  hidden.set_hidden_areas("markdown", [Range(2, 1, 3, 1)])
  hidden.set_hidden_areas("folding", [Range(3, 1, 4, 1)])
  let initial_cache = hidden.ranges
  assert_true(hidden.should_recompute)

  assert_false(
    hidden.position_is_hidden_except_source(Position(2, 99), "markdown"),
  )
  assert_true(
    hidden.position_is_hidden_except_source(Position(3, 1), "markdown"),
  )
  assert_true(
    hidden.position_is_hidden_except_source(Position(2, 1), "folding"),
  )
  assert_true(
    hidden.position_is_hidden_except_source(Position(4, 1), "markdown"),
  )
  assert_true(hidden.should_recompute)
  assert_true(physical_equal(hidden.ranges, initial_cache))

  let merged = hidden.get_merged_ranges()
  assert_false(hidden.should_recompute)
  assert_true(merged == [Range(2, 1, 4, 1)])
  let cached_union = hidden.ranges
  assert_false(
    hidden.position_is_hidden_except_source(Position(2, 1), "markdown"),
  )
  assert_false(hidden.should_recompute)
  assert_true(physical_equal(hidden.ranges, cached_union))
}
