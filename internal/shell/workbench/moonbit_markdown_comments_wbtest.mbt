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
      render_after_line_number: Some(5),
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
    {
      line_range: LineRange(8, 10),
      markdown: "Valid docs",
      render_after_line_number: Some(10),
    },
    {
      line_range: LineRange(11, 13),
      markdown: "Second docs",
      render_after_line_number: Some(13),
    },
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
      render_after_line_number: Some(11),
    },
  ])
}

///|
test "MoonBit Markdown comments keep an EOF half-open range after CRLF normalization" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot("let before = 1\r\n///|\r\n/// EOF docs"),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(2, 4),
      markdown: "EOF docs",
      render_after_line_number: None,
    },
  ])
}

///|
test "MoonBit Markdown comments render after multiline signatures and attributes" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n/// Multiline docs\n#alias(old_name, deprecated)\npub fn sample(\n  callback : (String) -> Unit,\n  label : String,\n) -> Unit {\n  callback(label)\n}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 3),
      markdown: "Multiline docs",
      render_after_line_number: Some(7),
    },
  ])
}

///|
test "MoonBit Markdown comments cross multiline attributes and implementation notes" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n/// Attribute docs\n#alias(\n  old_sample,\n  deprecated,\n)\n// Kept next to the declaration.\npub fn sample(\n  value : Int,\n) -> Int {\n  value\n}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 3),
      markdown: "Attribute docs",
      render_after_line_number: Some(10),
    },
  ])
}

///|
test "MoonBit Markdown comments do not cross another exact item boundary" {
  let blocks = moonbit_markdown_comments_in_snapshot(
    TextSnapshot(
      "///|\n/// First docs\n///|\n/// Second docs\npub fn second() -> Unit {}",
    ),
  )
  assert_eq(blocks, [
    {
      line_range: LineRange(1, 3),
      markdown: "First docs",
      render_after_line_number: None,
    },
    {
      line_range: LineRange(3, 5),
      markdown: "Second docs",
      render_after_line_number: Some(5),
    },
  ])
}

///|
test "MoonBit signature placement ignores braces in strings and comments" {
  assert_eq(
    moonbit_signature_end_line_number(
      TextSnapshot(
        "pub fn sample(\n  label : String, // { is not a body\n) -> String {\n  \"{\"\n}",
      ),
      1,
    ),
    Some(3),
  )
}

///|
test "MoonBit signature placement ignores nested defaults and open-list blanks" {
  assert_eq(
    moonbit_signature_end_line_number(
      TextSnapshot(
        "pub fn sample(\n  callback? : () -> Unit = fn() { println(\"work\") },\n\n  value? : Int = 1,\n) -> Unit {\n  callback()\n}",
      ),
      1,
    ),
    Some(5),
  )
  assert_eq(
    moonbit_signature_end_line_number(
      TextSnapshot(
        "#alias(\n  old_sample,\n\n  deprecated,\n)\npub fn sample() -> Unit {}",
      ),
      1,
    ),
    Some(6),
  )
}

///|
test "MoonBit signature placement expands coalesced delimiter tokens" {
  assert_eq(
    moonbit_signature_end_line_number(
      TextSnapshot(
        "pub fn sample(\n  values : Array[Int],\n  pair : (Int, Int),\n) -> Unit {\n  println(values.length() + pair.0)\n}",
      ),
      1,
    ),
    Some(4),
  )
  assert_eq(
    moonbit_signature_end_line_number(
      TextSnapshot("#attribute((nested),)\npub fn sample() -> Unit {}"),
      1,
    ),
    Some(2),
  )
}

///|
test "MoonBit Markdown comments do not cross a blank line to find an item" {
  assert_eq(
    moonbit_markdown_comments_in_snapshot(
      TextSnapshot("///|\n/// Detached docs\n\npub fn later() -> Unit {}"),
    ),
    [
      {
        line_range: LineRange(1, 3),
        markdown: "Detached docs",
        render_after_line_number: None,
      },
    ],
  )
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
    {
      line_range: LineRange(1, 3),
      markdown: "Registered docs",
      render_after_line_number: Some(3),
    },
  ])
  assert_true(handle.markdown_comment_provider_result(plaintext) is None)
}
