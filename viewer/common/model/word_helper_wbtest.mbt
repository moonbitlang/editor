///| Ordinary local coverage for the Viewer word helper. The exact upstream
/// `Get word at position` conformance case lives in
/// `model_reference_wbtest.mbt`.

///|
test "word number alternative" {
  // (-?\d*\.\d\w*) takes alternation priority; '.' is a separator so a word run
  // splits around it (wordHelper.ts:39).
  let snapshot = wb_model("abc3.14def")
  assert_true(
    word_at(snapshot, 1) ==
    Some({ word: "abc3", start_column: 1, end_column: 5 }),
  )
  assert_true(
    word_at(snapshot, 6) ==
    Some({ word: ".14def", start_column: 5, end_column: 11 }),
  )
  let decimal = wb_model(".5")
  assert_true(
    word_at(decimal, 1) == Some({ word: ".5", start_column: 1, end_column: 3 }),
  )
}
