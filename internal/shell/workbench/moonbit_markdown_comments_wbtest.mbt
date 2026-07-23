///|
test "MoonBit Markdown comments omit the item boundary from a core-shaped block" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n/// # Sample API\n///\n/// Uses **shell rendering**.\npub fn sample() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 5),
      markdown: "# Sample API\n\nUses **shell rendering**.",
    },
  ])
}

///|
test "MoonBit Markdown comments ignore unanchored false and detached groups" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\nlet first = 1\n/// detached\n///| shadow\n///|\n\n/// separated\n///|\n/// Valid docs\npub fn valid() -> Unit {}\n///|\n/// Second docs\npub fn second() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    { line_range: LineRange(8, 10), markdown: "Valid docs" },
    { line_range: LineRange(11, 13), markdown: "Second docs" },
  ])
}

///|
test "MoonBit Markdown comments preserve body whitespace Unicode and fences" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n///\n/// \n///  indented\n/// | literal pipe\n///\tTabbed\n/// Unicode 中\n/// ```mbt\n/// let value = 1\n/// ```\npub fn documented() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 11),
      markdown: "\n\n indented\n| literal pipe\n\tTabbed\nUnicode 中\n```mbt\nlet value = 1\n```",
    },
  ])
}

///|
test "MoonBit Markdown comments keep an EOF half-open range after CRLF normalization" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot("let before = 1\r\n///|\r\n/// EOF docs"),
  )
  assert_eq(blocks, [{ line_range: LineRange(2, 4), markdown: "EOF docs" }])
}

///|
test "workbench installs the provider only for MoonBit models" {
  let languages = @languages.Languages()
  install_moonbit_markdown_comment_provider(languages)
  let log_service = @log.LogService()
  let handle = languages.language_handle(log_service.log_handle())
  let moonbit = @model.TextModel(
    try! @base_common.Uri::parse("inmemory://workbench/provider.mbt"),
    "provider.mbt",
    "moonbit",
    1,
    "moonbit-revision",
    "///|\n/// Registered docs\npub fn registered() -> Unit {}",
  )
  let plaintext = @model.TextModel(
    try! @base_common.Uri::parse("inmemory://workbench/provider.txt"),
    "provider.txt",
    "plaintext",
    1,
    "plaintext-revision",
    "///|\n/// Not selected",
  )
  defer {
    moonbit.dispose()
    plaintext.dispose()
  }
  guard handle.markdown_comment_provider_result(moonbit) is Some(blocks) else {
    fail("expected the workbench MoonBit provider")
  }
  assert_eq(blocks, [
    { line_range: LineRange(1, 3), markdown: "Registered docs" },
  ])
  assert_true(handle.markdown_comment_provider_result(plaintext) is None)
}
