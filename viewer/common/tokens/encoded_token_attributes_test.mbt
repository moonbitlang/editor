///|
test "TokenMetadata owns semantic decoding while preserving the raw word" {
  let font_style_bold = 2
  let raw = (7U << @tokens.METADATA_LANGUAGEID_OFFSET) |
    (
      @tokens.STANDARD_TOKEN_TYPE_STRING.reinterpret_as_uint() <<
      @tokens.METADATA_TOKEN_TYPE_OFFSET
    ) |
    (
      font_style_bold.reinterpret_as_uint() <<
      @tokens.METADATA_FONT_STYLE_OFFSET
    ) |
    (11U << @tokens.METADATA_FOREGROUND_OFFSET) |
    (200U << @tokens.METADATA_BACKGROUND_OFFSET)
  let metadata = @tokens.TokenMetadata(raw)
  assert_eq(metadata.to_uint(), raw)
  assert_eq(
    ((raw >> @tokens.METADATA_LANGUAGEID_OFFSET) & 0xffU).reinterpret_as_int(),
    7,
  )
  assert_eq(
    ((raw >> @tokens.METADATA_TOKEN_TYPE_OFFSET) & 0x3U).reinterpret_as_int(),
    @tokens.STANDARD_TOKEN_TYPE_STRING,
  )
  assert_eq(
    ((raw >> @tokens.METADATA_FONT_STYLE_OFFSET) & 0xfU).reinterpret_as_int(),
    font_style_bold,
  )
  assert_eq(
    ((raw >> @tokens.METADATA_FOREGROUND_OFFSET) & 0x1ffU).reinterpret_as_int(),
    11,
  )
  assert_eq(
    ((raw >> @tokens.METADATA_BACKGROUND_OFFSET) & 0xffU).reinterpret_as_int(),
    200,
  )
  assert_eq(metadata.get_class_name(), "mtk11 mtkb")
}
