///| Faithful 1:1 port of vscode's `LineTokens` / `SliceLineTokens`.
///
/// Source: `src/vs/editor/common/tokens/lineTokens.ts` (pinned `vscode/`
/// submodule). The binary token store is a flat `Array[UInt]` mirroring
/// Monaco's `Uint32Array`: even slots hold a token's exclusive end offset,
/// odd slots its packed metadata word (see `encoded_token_attributes.mbt`).
/// The codec parameter is `@services.LanguageIdCodec`
/// (`services/languages_registry.mbt`), the `ILanguageIdCodec` role
/// `lineTokens.ts` takes.
///
/// Deviations from the source, none of which the conformance suite exercises:
///   - `ViewLineTokens` omits `equals`, the `languageIdCodec` field accessor,
///     and `getInlineStyle` stays via `color_map : Array[String]`.
///   - `LineTokens` omits `getTokensInRange` / `toString` (these pull in the
///     unported `TokenArray` family).
///   - The constructor skips Monaco's soft token-length/text-length mismatch
///     warning (`onUnexpectedError`); the readonly viewer has no such reporter.
///   - `with_inserted` guards the middle-insert metadata read against a
///     past-end token index (Monaco reads `undefined`); the read is unreachable
///     for valid in-bounds insert offsets.
///   - MoonBit's scalar-validating `StringView` cannot represent Monaco's raw
///     UTF-16 slices at lone-surrogate or pair-interior boundaries, so every
///     token-content slice uses `String::unsafe_substring`.

///|
/// A line's tokens, represented by the complete set of views this package
/// constructs. The closed enum preserves Monaco's concrete full/slice
/// distinction without erasing it behind a trait object.
pub enum ViewLineTokens {
  Full(LineTokens)
  Slice(SliceLineTokens)
}

///|
/// A token sequence backed by a flat metadata array. `tokens[i << 1]` is the
/// exclusive end offset of token `i`; `tokens[(i << 1) + 1]` its metadata.
pub struct LineTokens {
  tokens : Array[UInt]
  tokens_count : Int
  text : String
  language_id_codec : @services.LanguageIdCodec
}

///|
#alias(new, deprecated)
pub fn LineTokens::LineTokens(
  tokens : Array[UInt],
  text : String,
  decoder : @services.LanguageIdCodec,
) -> LineTokens {
  {
    tokens,
    tokens_count: tokens.length() >> 1,
    text,
    language_id_codec: decoder,
  }
}

///|
/// The default metadata word (no font style, default fg/bg colors).
pub fn LineTokens::default_token_metadata() -> UInt {
  ((FONT_STYLE_NONE << METADATA_FONT_STYLE_OFFSET) |
  (COLOR_ID_DEFAULT_FOREGROUND << METADATA_FOREGROUND_OFFSET) |
  (COLOR_ID_DEFAULT_BACKGROUND << METADATA_BACKGROUND_OFFSET)).reinterpret_as_uint()
}

///|
pub fn LineTokens::create_empty(
  line_content : String,
  decoder : @services.LanguageIdCodec,
) -> LineTokens {
  let tokens : Array[UInt] = [
    line_content.length().reinterpret_as_uint(),
    LineTokens::default_token_metadata(),
  ]
  LineTokens(tokens, line_content, decoder)
}

///|
pub fn LineTokens::create_from_text_and_metadata(
  data : Array[(String, UInt)],
  decoder : @services.LanguageIdCodec,
) -> LineTokens {
  let mut offset = 0
  let mut full_text = ""
  let tokens : Array[UInt] = []
  for item in data {
    let (text, metadata) = item
    offset = offset + text.length()
    tokens.push(offset.reinterpret_as_uint())
    tokens.push(metadata)
    full_text = full_text + text
  }
  LineTokens(tokens, full_text, decoder)
}

///|
/// Rewrites `tokens` start-offset slots in place to be end offsets.
pub fn LineTokens::convert_to_end_offset(
  tokens : Array[UInt],
  line_text_length : Int,
) -> Unit {
  let token_count = tokens.length() >> 1
  let last_token_index = token_count - 1
  for token_index in 0..<last_token_index {
    tokens[token_index << 1] = tokens[(token_index + 1) << 1]
  }
  tokens[last_token_index << 1] = line_text_length.reinterpret_as_uint()
}

///|
/// Binary-searches the token containing `desired_index`. Mirrors Monaco's
/// static `findIndexInTokensArray`.
pub fn LineTokens::find_index_in_tokens_array(
  tokens : Array[UInt],
  desired_index : Int,
) -> Int {
  if tokens.length() <= 2 {
    return 0
  }
  let mut low = 0
  let mut high = (tokens.length() >> 1) - 1
  while low < high {
    let mid = low + (high - low) / 2
    let end_offset = tokens[mid << 1].reinterpret_as_int()
    if end_offset == desired_index {
      return mid + 1
    } else if end_offset < desired_index {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low
}

///|
pub fn LineTokens::get_text_length(self : LineTokens) -> Int {
  self.text.length()
}

///|
pub fn LineTokens::get_start_offset(
  self : LineTokens,
  token_index : Int,
) -> Int {
  if token_index > 0 {
    self.tokens[(token_index - 1) << 1].reinterpret_as_int()
  } else {
    0
  }
}

///|
/// `inflate()` returns the tokens unchanged — already a view.
pub fn LineTokens::inflate(self : LineTokens) -> ViewLineTokens {
  Full(self)
}

///|
pub fn LineTokens::slice_and_inflate(
  self : LineTokens,
  start_offset : Int,
  end_offset : Int,
  delta_offset : Int,
) -> ViewLineTokens {
  Slice(SliceLineTokens::new(self, start_offset, end_offset, delta_offset))
}

///|
pub fn LineTokens::slice_zero_copy(
  self : LineTokens,
  range : @base_common.OffsetRange,
) -> ViewLineTokens {
  self.slice_and_inflate(range.start, range.end_exclusive, 0)
}

///|
/// A token to splice into the line. `insert_tokens` must be sorted by offset.
pub struct InsertedToken {
  offset : Int
  text : String
  token_metadata : UInt
}

///|
#alias(new, deprecated)
pub fn InsertedToken::InsertedToken(
  offset : Int,
  text : String,
  token_metadata : UInt,
) -> InsertedToken {
  { offset, text, token_metadata }
}

///|
/// Returns a new `LineTokens` with `insert_tokens` spliced into the text and
/// token boundaries. Pure; the receiver is unchanged.
pub fn LineTokens::with_inserted(
  self : LineTokens,
  insert_tokens : Array[InsertedToken],
) -> LineTokens {
  if insert_tokens.length() == 0 {
    return self
  }
  let mut next_original_token_idx = 0
  let mut next_insert_token_idx = 0
  let mut text = ""
  let new_tokens : Array[UInt] = []
  let mut original_end_offset = 0
  while true {
    let next_original_token_end_offset = if next_original_token_idx <
      self.tokens_count {
      self.tokens[next_original_token_idx << 1].reinterpret_as_int()
    } else {
      -1
    }
    let has_insert = next_insert_token_idx < insert_tokens.length()
    if next_original_token_end_offset != -1 &&
      (
        !has_insert ||
        next_original_token_end_offset <=
        insert_tokens[next_insert_token_idx].offset
      ) {
      // original token ends before the next insert token
      text = text +
        substr(self.text, original_end_offset, next_original_token_end_offset)
      let metadata = self.tokens[(next_original_token_idx << 1) + 1]
      new_tokens.push(text.length().reinterpret_as_uint())
      new_tokens.push(metadata)
      next_original_token_idx = next_original_token_idx + 1
      original_end_offset = next_original_token_end_offset
    } else if has_insert {
      let next_insert_token = insert_tokens[next_insert_token_idx]
      if next_insert_token.offset > original_end_offset {
        // insert token is in the middle of the next token
        text = text +
          substr(self.text, original_end_offset, next_insert_token.offset)
        let metadata = if next_original_token_idx < self.tokens_count {
          self.tokens[(next_original_token_idx << 1) + 1]
        } else {
          LineTokens::default_token_metadata()
        }
        new_tokens.push(text.length().reinterpret_as_uint())
        new_tokens.push(metadata)
        original_end_offset = next_insert_token.offset
      }
      text = text + next_insert_token.text
      new_tokens.push(text.length().reinterpret_as_uint())
      new_tokens.push(next_insert_token.token_metadata)
      next_insert_token_idx = next_insert_token_idx + 1
    } else {
      break
    }
  }
  LineTokens(new_tokens, text, self.language_id_codec)
}

///|
pub fn LineTokens::get_count(self : LineTokens) -> Int {
  self.tokens_count
}

///|
pub fn LineTokens::get_line_content(self : LineTokens) -> String {
  self.text
}

///|
pub fn LineTokens::get_end_offset(self : LineTokens, token_index : Int) -> Int {
  self.tokens[token_index << 1].reinterpret_as_int()
}

///|
pub fn LineTokens::get_metadata(self : LineTokens, token_index : Int) -> UInt {
  self.tokens[(token_index << 1) + 1]
}

///|
pub fn LineTokens::get_language_id(
  self : LineTokens,
  token_index : Int,
) -> String {
  let metadata = self.tokens[(token_index << 1) + 1]
  self.language_id_codec.decode_language_id(
    TokenMetadata::get_language_id(metadata),
  )
}

///|
pub fn LineTokens::get_standard_token_type(
  self : LineTokens,
  token_index : Int,
) -> Int {
  TokenMetadata::get_token_type(self.tokens[(token_index << 1) + 1])
}

///|
pub fn LineTokens::get_foreground(self : LineTokens, token_index : Int) -> Int {
  TokenMetadata::get_foreground(self.tokens[(token_index << 1) + 1])
}

///|
pub fn LineTokens::get_class_name(
  self : LineTokens,
  token_index : Int,
) -> String {
  TokenMetadata::get_class_name_from_metadata(
    self.tokens[(token_index << 1) + 1],
  )
}

///|
pub fn LineTokens::get_inline_style(
  self : LineTokens,
  token_index : Int,
  color_map : Array[String],
) -> String {
  TokenMetadata::get_inline_style_from_metadata(
    self.tokens[(token_index << 1) + 1],
    color_map,
  )
}

///|
pub fn LineTokens::get_presentation(
  self : LineTokens,
  token_index : Int,
) -> TokenPresentation {
  TokenMetadata::get_presentation_from_metadata(
    self.tokens[(token_index << 1) + 1],
  )
}

///|
pub fn LineTokens::find_token_index_at_offset(
  self : LineTokens,
  offset : Int,
) -> Int {
  LineTokens::find_index_in_tokens_array(self.tokens, offset)
}

///|
pub fn LineTokens::get_token_text(
  self : LineTokens,
  token_index : Int,
) -> String {
  substr(
    self.text,
    self.get_start_offset(token_index),
    self.get_end_offset(token_index),
  )
}

///|
pub fn LineTokens::for_each(
  self : LineTokens,
  callback : (Int) -> Unit,
) -> Unit {
  for token_index in 0..<self.get_count() {
    callback(token_index)
  }
}

///|
/// A read-only window onto a `LineTokens`, offset by `delta_offset`. Mirrors
/// Monaco's `SliceLineTokens`.
pub struct SliceLineTokens {
  priv source : LineTokens
  priv start_offset : Int
  priv end_offset : Int
  priv delta_offset : Int
  priv first_token_index : Int
  priv tokens_count : Int
}

///|
fn SliceLineTokens::new(
  source : LineTokens,
  start_offset : Int,
  end_offset : Int,
  delta_offset : Int,
) -> SliceLineTokens {
  let first_token_index = source.find_token_index_at_offset(start_offset)
  let mut tokens_count = 0
  for i = first_token_index; i < source.get_count(); i = i + 1 {
    let token_start_offset = source.get_start_offset(i)
    if token_start_offset >= end_offset {
      break
    }
    tokens_count = tokens_count + 1
  }
  {
    source,
    start_offset,
    end_offset,
    delta_offset,
    first_token_index,
    tokens_count,
  }
}

///|
fn SliceLineTokens::get_count(self : SliceLineTokens) -> Int {
  self.tokens_count
}

///|
fn SliceLineTokens::get_line_content(self : SliceLineTokens) -> String {
  substr(self.source.get_line_content(), self.start_offset, self.end_offset)
}

///|
fn SliceLineTokens::get_metadata(
  self : SliceLineTokens,
  token_index : Int,
) -> UInt {
  self.source.get_metadata(self.first_token_index + token_index)
}

///|
fn SliceLineTokens::get_language_id(
  self : SliceLineTokens,
  token_index : Int,
) -> String {
  self.source.get_language_id(self.first_token_index + token_index)
}

///|
fn SliceLineTokens::get_standard_token_type(
  self : SliceLineTokens,
  token_index : Int,
) -> Int {
  self.source.get_standard_token_type(self.first_token_index + token_index)
}

///|
fn SliceLineTokens::get_foreground(
  self : SliceLineTokens,
  token_index : Int,
) -> Int {
  self.source.get_foreground(self.first_token_index + token_index)
}

///|
fn SliceLineTokens::get_end_offset(
  self : SliceLineTokens,
  token_index : Int,
) -> Int {
  let token_end_offset = self.source.get_end_offset(
    self.first_token_index + token_index,
  )
  self.end_offset.min(token_end_offset) - self.start_offset + self.delta_offset
}

///|
fn SliceLineTokens::get_class_name(
  self : SliceLineTokens,
  token_index : Int,
) -> String {
  self.source.get_class_name(self.first_token_index + token_index)
}

///|
fn SliceLineTokens::get_inline_style(
  self : SliceLineTokens,
  token_index : Int,
  color_map : Array[String],
) -> String {
  self.source.get_inline_style(self.first_token_index + token_index, color_map)
}

///|
fn SliceLineTokens::get_presentation(
  self : SliceLineTokens,
  token_index : Int,
) -> TokenPresentation {
  self.source.get_presentation(self.first_token_index + token_index)
}

///|
fn SliceLineTokens::find_token_index_at_offset(
  self : SliceLineTokens,
  offset : Int,
) -> Int {
  self.source.find_token_index_at_offset(
    offset + self.start_offset - self.delta_offset,
  ) -
  self.first_token_index
}

///|
fn SliceLineTokens::get_token_text(
  self : SliceLineTokens,
  token_index : Int,
) -> String {
  let adjusted_token_index = self.first_token_index + token_index
  let token_start_offset = self.source.get_start_offset(adjusted_token_index)
  let token_end_offset = self.source.get_end_offset(adjusted_token_index)
  let mut text = self.source.get_token_text(adjusted_token_index)
  if token_start_offset < self.start_offset {
    text = substr(text, self.start_offset - token_start_offset, text.length())
  }
  if token_end_offset > self.end_offset {
    text = substr(text, 0, text.length() - (token_end_offset - self.end_offset))
  }
  text
}

///|
fn SliceLineTokens::for_each(
  self : SliceLineTokens,
  callback : (Int) -> Unit,
) -> Unit {
  for token_index in 0..<self.get_count() {
    callback(token_index)
  }
}

///|
pub fn ViewLineTokens::get_count(self : ViewLineTokens) -> Int {
  match self {
    Full(tokens) => tokens.get_count()
    Slice(tokens) => tokens.get_count()
  }
}

///|
pub fn ViewLineTokens::get_line_content(self : ViewLineTokens) -> String {
  match self {
    Full(tokens) => tokens.get_line_content()
    Slice(tokens) => tokens.get_line_content()
  }
}

///|
pub fn ViewLineTokens::get_metadata(
  self : ViewLineTokens,
  token_index : Int,
) -> UInt {
  match self {
    Full(tokens) => tokens.get_metadata(token_index)
    Slice(tokens) => tokens.get_metadata(token_index)
  }
}

///|
pub fn ViewLineTokens::get_language_id(
  self : ViewLineTokens,
  token_index : Int,
) -> String {
  match self {
    Full(tokens) => tokens.get_language_id(token_index)
    Slice(tokens) => tokens.get_language_id(token_index)
  }
}

///|
pub fn ViewLineTokens::get_standard_token_type(
  self : ViewLineTokens,
  token_index : Int,
) -> Int {
  match self {
    Full(tokens) => tokens.get_standard_token_type(token_index)
    Slice(tokens) => tokens.get_standard_token_type(token_index)
  }
}

///|
pub fn ViewLineTokens::get_foreground(
  self : ViewLineTokens,
  token_index : Int,
) -> Int {
  match self {
    Full(tokens) => tokens.get_foreground(token_index)
    Slice(tokens) => tokens.get_foreground(token_index)
  }
}

///|
pub fn ViewLineTokens::get_end_offset(
  self : ViewLineTokens,
  token_index : Int,
) -> Int {
  match self {
    Full(tokens) => tokens.get_end_offset(token_index)
    Slice(tokens) => tokens.get_end_offset(token_index)
  }
}

///|
pub fn ViewLineTokens::get_class_name(
  self : ViewLineTokens,
  token_index : Int,
) -> String {
  match self {
    Full(tokens) => tokens.get_class_name(token_index)
    Slice(tokens) => tokens.get_class_name(token_index)
  }
}

///|
pub fn ViewLineTokens::get_inline_style(
  self : ViewLineTokens,
  token_index : Int,
  color_map : Array[String],
) -> String {
  match self {
    Full(tokens) => tokens.get_inline_style(token_index, color_map)
    Slice(tokens) => tokens.get_inline_style(token_index, color_map)
  }
}

///|
pub fn ViewLineTokens::get_presentation(
  self : ViewLineTokens,
  token_index : Int,
) -> TokenPresentation {
  match self {
    Full(tokens) => tokens.get_presentation(token_index)
    Slice(tokens) => tokens.get_presentation(token_index)
  }
}

///|
pub fn ViewLineTokens::find_token_index_at_offset(
  self : ViewLineTokens,
  offset : Int,
) -> Int {
  match self {
    Full(tokens) => tokens.find_token_index_at_offset(offset)
    Slice(tokens) => tokens.find_token_index_at_offset(offset)
  }
}

///|
pub fn ViewLineTokens::get_token_text(
  self : ViewLineTokens,
  token_index : Int,
) -> String {
  match self {
    Full(tokens) => tokens.get_token_text(token_index)
    Slice(tokens) => tokens.get_token_text(token_index)
  }
}

///|
pub fn ViewLineTokens::for_each(
  self : ViewLineTokens,
  callback : (Int) -> Unit,
) -> Unit {
  match self {
    Full(tokens) => tokens.for_each(callback)
    Slice(tokens) => tokens.for_each(callback)
  }
}

///|
/// Raw UTF-16 code-unit substring `[start, end)`. Unlike `StringView`, this
/// preserves lone surrogates and either half of a valid pair.
fn substr(s : String, start : Int, end : Int) -> String {
  s.unsafe_substring(start~, end~)
}
