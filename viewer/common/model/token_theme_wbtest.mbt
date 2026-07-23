///| Unit tests for the `HighlightTag` -> metadata word theme bridge
/// (`token_theme.mbt`): packing round-trips through the `TokenMetadata`
/// decoders, and each tag yields the expected `mtk<colorId>` class.

///|
test "tag_to_metadata round-trips through the TokenMetadata decoders" {
  // Foreground color id survives the pack/unpack.
  let keyword = tag_to_metadata(Keyword)
  assert_eq(@common_tokens.TokenMetadata::get_foreground(keyword), 3)
  assert_eq(
    @common_tokens.TokenMetadata::get_font_style(keyword),
    @common_tokens.FONT_STYLE_NONE,
  )
  assert_eq(
    @common_tokens.TokenMetadata::get_token_type(keyword),
    @common_tokens.STANDARD_TOKEN_TYPE_OTHER,
  )

  // Comments / strings / regexps additionally carry a StandardTokenType.
  let comment = tag_to_metadata(Comment)
  assert_eq(
    @common_tokens.TokenMetadata::get_token_type(comment),
    @common_tokens.STANDARD_TOKEN_TYPE_COMMENT,
  )
  let string = tag_to_metadata(String)
  assert_eq(
    @common_tokens.TokenMetadata::get_token_type(string),
    @common_tokens.STANDARD_TOKEN_TYPE_STRING,
  )
  let regexp = tag_to_metadata(Regexp)
  assert_eq(
    @common_tokens.TokenMetadata::get_token_type(regexp),
    @common_tokens.STANDARD_TOKEN_TYPE_REGEX,
  )

  // Optional font style is packed into the font-style field.
  let bold_kw = tag_to_metadata(
    Keyword,
    font_style=@common_tokens.FONT_STYLE_BOLD,
  )
  assert_eq(
    @common_tokens.TokenMetadata::get_font_style(bold_kw),
    @common_tokens.FONT_STYLE_BOLD,
  )
  assert_eq(@common_tokens.TokenMetadata::get_foreground(bold_kw), 3)

  // Optional language id is packed into the language field.
  let lang_kw = tag_to_metadata(Keyword, language_id=7)
  assert_eq(@common_tokens.TokenMetadata::get_language_id(lang_kw), 7)
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
    let metadata = tag_to_metadata(tag)
    assert_eq(
      @common_tokens.TokenMetadata::get_class_name_from_metadata(metadata),
      expected,
    )
  }
}

///|
test "bold/italic font style augments the mtk class" {
  let metadata = tag_to_metadata(
    Comment,
    font_style=@common_tokens.FONT_STYLE_ITALIC | @common_tokens.FONT_STYLE_BOLD,
  )
  assert_eq(
    @common_tokens.TokenMetadata::get_class_name_from_metadata(metadata),
    "mtk7 mtki mtkb",
  )
}

///|
test "default color map resolves mtk classes to the workbench token vars" {
  let color_map = default_token_color_map()
  // Foreground color ids index straight into the map.
  assert_eq(color_map[1], "var(--vscode-editor-foreground)")
  assert_eq(color_map[3], "var(--vscode-token-keyword)")
  assert_eq(color_map[7], "var(--vscode-token-comment)")
  // Inline style for a keyword token resolves through the map.
  let keyword = tag_to_metadata(Keyword)
  assert_eq(
    @common_tokens.TokenMetadata::get_inline_style_from_metadata(
      keyword, color_map,
    ),
    "color: var(--vscode-token-keyword);",
  )
}
