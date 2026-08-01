///| Unit tests for the `HighlightTag` -> metadata word theme bridge
/// (`token_theme.mbt`): packing round-trips through the `TokenMetadata`
/// decoders, and each tag yields the expected `mtk<colorId>` class.

///|
fn decoded_metadata(raw : UInt) -> @common_tokens.TokenMetadata {
  @common_tokens.TokenMetadata::from_uint(raw)
}

///|
test "tag_to_metadata round-trips through the TokenMetadata decoders" {
  // Foreground color id survives the pack/unpack.
  let keyword = decoded_metadata(tag_to_metadata(Keyword))
  assert_eq(keyword.get_foreground(), 3)
  assert_eq(keyword.get_font_style(), @common_tokens.FONT_STYLE_NONE)
  assert_eq(keyword.get_token_type(), @common_tokens.STANDARD_TOKEN_TYPE_OTHER)

  // Comments / strings / regexps additionally carry a StandardTokenType.
  let comment = decoded_metadata(tag_to_metadata(Comment))
  assert_eq(
    comment.get_token_type(),
    @common_tokens.STANDARD_TOKEN_TYPE_COMMENT,
  )
  let string = decoded_metadata(tag_to_metadata(String))
  assert_eq(string.get_token_type(), @common_tokens.STANDARD_TOKEN_TYPE_STRING)
  let regexp = decoded_metadata(tag_to_metadata(Regexp))
  assert_eq(regexp.get_token_type(), @common_tokens.STANDARD_TOKEN_TYPE_REGEX)

  // Optional font style is packed into the font-style field.
  let bold_kw = decoded_metadata(
    tag_to_metadata(Keyword, font_style=@common_tokens.FONT_STYLE_BOLD),
  )
  assert_eq(bold_kw.get_font_style(), @common_tokens.FONT_STYLE_BOLD)
  assert_eq(bold_kw.get_foreground(), 3)

  // Optional language id is packed into the language field.
  let lang_kw = decoded_metadata(tag_to_metadata(Keyword, language_id=7))
  assert_eq(lang_kw.get_language_id(), 7)
}

///|
test "tag_to_metadata yields the expected mtk class per tag" {
  let cases : Array[(@syntax.HighlightTag, String)] = [
    (Keyword, "mtk3"),
    (Identifier, "mtk4"),
    (String, "mtk5"),
    (Number, "mtk6"),
    (Comment, "mtk7"),
    (Punctuation, "mtk8"),
    (Plain, "mtk1"),
    (Operator, "mtk8"),
    (Delimiter, "mtk8"),
    (Type, "mtk9"),
    (Function, "mtk10"),
    (Variable, "mtk4"),
    (Constant, "mtk3"),
    (StringEscape, "mtk11"),
    (CommentDoc, "mtk7"),
    (Regexp, "mtk12"),
    (Tag, "mtk3"),
    (Attribute, "mtk4"),
    (Invalid, "mtk13"),
  ]
  for case in cases {
    let (tag, expected) = case
    let metadata = decoded_metadata(tag_to_metadata(tag))
    assert_eq(metadata.get_class_name_from_metadata(), expected)
  }
}

///|
test "bold/italic font style augments the mtk class" {
  let metadata = decoded_metadata(
    tag_to_metadata(
      Comment,
      font_style=@common_tokens.FONT_STYLE_ITALIC |
        @common_tokens.FONT_STYLE_BOLD,
    ),
  )
  assert_eq(metadata.get_class_name_from_metadata(), "mtk7 mtki mtkb")
}

///|
test "default color map resolves mtk classes to the workbench token vars" {
  let color_map = default_token_color_map()
  // Foreground color ids index straight into the map.
  assert_eq(color_map[1], "var(--vscode-editor-foreground)")
  assert_eq(color_map[3], "var(--vscode-token-keyword)")
  assert_eq(color_map[7], "var(--vscode-token-comment)")
  // Inline style for a keyword token resolves through the map.
  let keyword = decoded_metadata(tag_to_metadata(Keyword))
  assert_eq(
    keyword.get_inline_style_from_metadata(color_map),
    "color: var(--vscode-token-keyword);",
  )
}
