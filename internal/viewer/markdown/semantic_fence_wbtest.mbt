///|
fn semantic_test_block(info_string : String?) -> MarkdownCodeBlock {
  let source = match info_string {
    Some(info_string) => "```" + info_string + "\nx\n```"
    None => "```\nx\n```"
  }
  render_markdown(source).projection.code_blocks[0]
}

///|
test "MoonBit check classifier accepts compiler ASCII-space prefixes" {
  for
    info_string in [
      "mbt check", "moonbit check", "mbt  check", "moonbit   check trailing tokens",
    ] {
    assert_true(
      semantic_test_block(Some(info_string)).is_moonbit_check_fence(
        MoonBitMarkdown,
      ),
    )
  }
}

///|
test "MoonBit check classifier rejects non-prefix case and tab variants" {
  for
    info_string in [
      "plain", "mbt", "mbt test", "mbt nocheck", "Mbt check", "MoonBit check", "mbt\tcheck",
      "mbt \t check",
    ] {
    assert_false(
      semantic_test_block(Some(info_string)).is_moonbit_check_fence(
        MoonBitMarkdown,
      ),
    )
  }
  assert_false(
    semantic_test_block(None).is_moonbit_check_fence(MoonBitMarkdown),
  )
}

///|
test "ordinary Markdown never opts into MoonBit fence semantics" {
  let block = semantic_test_block(Some("mbt check trailing"))
  assert_false(block.is_moonbit_check_fence(OrdinaryMarkdown))
  assert_true(block.is_moonbit_check_fence(MoonBitMarkdown))
}
