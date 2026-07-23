///|
test "QuickDiffHandle forwards lookup, subscription, and disposal" {
  let resource = try! @base_common.Uri::parse("memory://workspace/a.mbt")
  let calls : Array[String] = []
  let changed : Array[String] = []
  let handle = @quick_diff_api.QuickDiffHandle(
    get_original_content=uri => {
      calls.push("get:" + uri.to_string())
      Some("original")
    },
    on_did_change_original=listener => {
      calls.push("subscribe")
      listener(resource)
      @base_common.Disposable::from(() => calls.push("dispose"))
    },
  )
  let subscription = handle.on_did_change_original(uri => {
    changed.push(uri.to_string())
  })
  assert_eq(changed.join(","), resource.to_string())
  assert_true(handle.get_original_content(resource) is Some("original"))
  subscription.dispose()
  assert_eq(
    calls.join("|"),
    "subscribe|get:" + resource.to_string() + "|dispose",
  )
}
