// Conformance port of Monaco/VS Code's CharacterClassifier suite.
//
// Ports: vscode/src/vs/editor/test/common/core/characterClassifier.test.ts
// From the checked-in vscode submodule.

///|
test "works" {
  // CharCode.a = 97, CharCode.b = 98, CharCode.z = 122
  let classifier = @common.CharacterClassifier(0)
  assert_eq(classifier.get(-1), 0)
  assert_eq(classifier.get(0), 0)
  assert_eq(classifier.get(97), 0)
  assert_eq(classifier.get(98), 0)
  assert_eq(classifier.get(122), 0)
  assert_eq(classifier.get(255), 0)
  assert_eq(classifier.get(1000), 0)
  assert_eq(classifier.get(2000), 0)
  classifier.set(97, 1)
  classifier.set(122, 2)
  classifier.set(1000, 3)
  assert_eq(classifier.get(-1), 0)
  assert_eq(classifier.get(0), 0)
  assert_eq(classifier.get(97), 1)
  assert_eq(classifier.get(98), 0)
  assert_eq(classifier.get(122), 2)
  assert_eq(classifier.get(255), 0)
  assert_eq(classifier.get(1000), 3)
  assert_eq(classifier.get(2000), 0)
}
