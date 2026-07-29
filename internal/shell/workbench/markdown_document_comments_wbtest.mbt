///|
fn markdown_document_test_model(
  name : String,
  language_id : String,
  text : String,
) -> @model.TextModel raise {
  @model.TextModel(
    @base_common.Uri::parse("inmemory://workbench/\{name}"),
    name,
    language_id,
    1,
    "markdown-document-revision",
    text,
  )
}

///|
test "workbench renders whole Markdown documents as one rendered block" {
  let languages = @languages.Languages()
  install_markdown_document_comment_provider(languages)
  let log_service = @log.LogService()
  let handle = languages.language_handle(log_service.log_handle())
  let document = markdown_document_test_model(
    "README.md", "markdown", "# Title\n\nBody with a **detail**.\n",
  )
  defer document.dispose()
  guard handle.markdown_comment_provider_render_result(document) is Some(result) else {
    fail("expected the workbench Markdown document provider")
  }
  assert_false(result.foldable)
  guard result.blocks is [block] else {
    fail("expected one whole-document block")
  }
  assert_eq(block.line_range, LineRange(1, 4))
  assert_eq(block.markdown, "# Title\n\nBody with a **detail**.")
}

///|
test "one-line and blank Markdown documents keep their plain source view" {
  let languages = @languages.Languages()
  install_markdown_document_comment_provider(languages)
  let log_service = @log.LogService()
  let handle = languages.language_handle(log_service.log_handle())
  let one_line = markdown_document_test_model("one.md", "markdown", "# only")
  defer one_line.dispose()
  guard handle.markdown_comment_provider_render_result(one_line)
    is Some(one_line_result) else {
    fail("expected the provider to stay authoritative for one-line files")
  }
  assert_eq(one_line_result.blocks, [])
  let blank = markdown_document_test_model("blank.md", "markdown", "\n\n\n")
  defer blank.dispose()
  guard handle.markdown_comment_provider_render_result(blank)
    is Some(blank_result) else {
    fail("expected the provider to stay authoritative for blank files")
  }
  assert_eq(blank_result.blocks, [])
}

///|
test "MoonBit literate documents keep the anchored MoonBit provider" {
  let languages = @languages.Languages()
  install_moonbit_markdown_comment_provider(languages)
  install_markdown_document_comment_provider(languages)
  let log_service = @log.LogService()
  let handle = languages.language_handle(log_service.log_handle())
  // `.mbt.md` infers the moonbit language, so the whole-document Markdown
  // provider must not claim it.
  let literate = markdown_document_test_model(
    "README.mbt.md", "moonbit", "///|\n/// Registered docs\npub fn registered() -> Unit {}",
  )
  defer literate.dispose()
  guard handle.markdown_comment_provider_render_result(literate) is Some(result) else {
    fail("expected the MoonBit provider to keep literate documents")
  }
  assert_true(result.foldable)
  guard result.blocks is [block] else {
    fail("expected the anchored MoonBit block")
  }
  assert_eq(block.line_range, LineRange(1, 3))
}
