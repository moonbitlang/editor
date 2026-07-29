///|
test "MoonBit Markdown comments prefix a core-shaped block with its item boundary" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n/// # Sample API\n///\n/// Uses **shell rendering**.\npub fn sample() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 5),
      markdown: "---\n\n# Sample API\n\nUses **shell rendering**.",
    },
  ])
}

///|
test "MoonBit Markdown comments retain inline text on a detached item boundary" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///| Port of `base/common/uri.ts`.\n///\n/// Reviewed deviations follow.\n\n///|\npub fn next() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 4),
      markdown: "---\n\nPort of `base/common/uri.ts`.\n\nReviewed deviations follow.",
    },
    { line_range: LineRange(5, 6), markdown: "---" },
  ])
}

///|
test "MoonBit Markdown comments render separators and ignore detached groups" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\nlet first = 1\n/// detached\n///|shadow\n///|\n\n/// separated\n///|\n/// Valid docs\npub fn valid() -> Unit {}\n///|\n/// Second docs\npub fn second() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    { line_range: LineRange(1, 2), markdown: "---" },
    { line_range: LineRange(5, 6), markdown: "---" },
    { line_range: LineRange(8, 10), markdown: "---\n\nValid docs" },
    { line_range: LineRange(11, 13), markdown: "---\n\nSecond docs" },
  ])
}

///|
test "MoonBit Markdown comments render consecutive undocumented item separators" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot("///|\nfn first {}\n///|\nfn second {}"),
  )
  assert_eq(blocks, [
    { line_range: LineRange(1, 2), markdown: "---" },
    { line_range: LineRange(3, 4), markdown: "---" },
  ])
}

///|
test "MoonBit Markdown comments retain a detached documented block" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n/// # Detached overview\n///\n/// This Markdown has no top-level body.\n\n///|\n/// # Attached function\nfn attached() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 5),
      markdown: "---\n\n# Detached overview\n\nThis Markdown has no top-level body.",
    },
    { line_range: LineRange(6, 8), markdown: "---\n\n# Attached function" },
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
      markdown: "---\n\n\n\n indented\n| literal pipe\n\tTabbed\nUnicode 中\n```mbt\nlet value = 1\n```",
    },
  ])
}

///|
test "MoonBit Markdown comments keep an EOF half-open range after CRLF normalization" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot("let before = 1\r\n///|\r\n/// EOF docs"),
  )
  assert_eq(blocks, [
    { line_range: LineRange(2, 4), markdown: "---\n\nEOF docs" },
  ])
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
    { line_range: LineRange(1, 3), markdown: "---\n\nRegistered docs" },
  ])
  assert_true(handle.markdown_comment_provider_result(plaintext) is None)
}
