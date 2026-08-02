///|
test "workbench opts MoonBit Markdown comments into documentation folding" {
  let languages = @languages.Languages()
  install_moonbit_markdown_comment_provider(languages)
  let log_service = @log.LogService()
  let handle = languages.language_handle(log_service.log_handle())
  let moonbit = @model.TextModel(
    try! @base_common.Uri::parse("inmemory://workbench/foldable-provider.mbt"),
    "foldable-provider.mbt",
    "moonbit",
    1,
    "moonbit-revision",
    (
      #|///|
      #|/// Registered docs
      #|pub fn registered() -> Unit {}
    ),
  )
  defer moonbit.dispose()
  guard handle.markdown_comment_provider_render_result(moonbit) is Some(result) else {
    fail("expected the workbench MoonBit provider")
  }
  assert_true(result.foldable)
}
