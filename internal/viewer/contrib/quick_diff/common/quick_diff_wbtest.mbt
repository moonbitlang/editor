///|
fn test_change(
  original_start : Int,
  original_end : Int,
  modified_start : Int,
  modified_end : Int,
) -> @diff.Change {
  {
    original_start_line_number: original_start,
    original_end_line_number: original_end,
    modified_start_line_number: modified_start,
    modified_end_line_number: modified_end,
  }
}

///|
test "get_change_type mirrors quickDiff.ts:121" {
  // originalEndLineNumber === 0 → Add
  assert_eq(get_change_type(test_change(1, 0, 2, 3)), Add)
  // modifiedEndLineNumber === 0 → Delete
  assert_eq(get_change_type(test_change(2, 4, 1, 0)), Delete)
  assert_eq(get_change_type(test_change(2, 2, 2, 2)), Modify)
}

///|
test "quick diff service stores, clears, and reports originals per resource" {
  let service = QuickDiffService()
  let a = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/a.txt",
  )
  let b = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/b.txt",
  )
  let fired : Array[String] = []
  let listener = service.on_did_change_original(resource => {
    fired.push(resource.to_string())
  })
  assert_true(service.get_original_content(a) is None)
  service.set_original_content(a, Some("one\ntwo"))
  assert_eq(service.get_original_content(a).unwrap(), "one\ntwo")
  assert_true(service.get_original_content(b) is None)
  service.set_original_content(a, Some("three"))
  assert_eq(service.get_original_content(a).unwrap(), "three")
  service.set_original_content(a, None)
  assert_true(service.get_original_content(a) is None)
  assert_eq(fired.length(), 3)
  assert_eq(fired[0], a.to_string())
  listener.dispose()
  service.set_original_content(b, Some("x"))
  assert_eq(fired.length(), 3)
}

///|
test "quick_diff_handle adapts the concrete baseline store" {
  let service = QuickDiffService()
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/handle.txt",
  )
  let handle = service.quick_diff_handle()
  let mut change_count = 0
  let changed_resources : Array[String] = []
  let subscription = handle.on_did_change_original(changed => {
    changed_resources.push(changed.to_string())
    change_count += 1
  })
  assert_true(handle.get_original_content(resource) is None)
  service.set_original_content(resource, Some("baseline"))
  assert_true(handle.get_original_content(resource) is Some("baseline"))
  assert_eq(change_count, 1)
  assert_eq(changed_resources.join(","), resource.to_string())
  subscription.dispose()
}
