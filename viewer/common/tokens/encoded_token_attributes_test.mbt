///|
test "TokenMetadata owns semantic decoding while preserving the raw word" {
  let raw = (7U << @tokens.METADATA_LANGUAGEID_OFFSET) |
    (
      @tokens.STANDARD_TOKEN_TYPE_STRING.reinterpret_as_uint() <<
      @tokens.METADATA_TOKEN_TYPE_OFFSET
    ) |
    (
      @tokens.FONT_STYLE_BOLD.reinterpret_as_uint() <<
      @tokens.METADATA_FONT_STYLE_OFFSET
    ) |
    (11U << @tokens.METADATA_FOREGROUND_OFFSET) |
    (200U << @tokens.METADATA_BACKGROUND_OFFSET)
  let metadata = @tokens.TokenMetadata::from_uint(raw)
  assert_eq(metadata.to_uint(), raw)
  assert_eq(metadata.get_language_id(), 7)
  assert_eq(metadata.get_token_type(), @tokens.STANDARD_TOKEN_TYPE_STRING)
  assert_eq(metadata.get_font_style(), @tokens.FONT_STYLE_BOLD)
  assert_eq(metadata.get_foreground(), 11)
  assert_eq(metadata.get_background(), 200)
  assert_false(metadata.contains_balanced_brackets())
}
