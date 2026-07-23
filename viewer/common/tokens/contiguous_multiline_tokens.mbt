///| A source-shaped in-process port of Monaco's `ContiguousMultilineTokens`.
///
/// Source: `vscode/src/vs/editor/common/tokens/contiguousMultilineTokens.ts`
/// at checked-in oracle, consumed
/// closure lines 17 and 35-80. Serialization and incremental editing are not
/// part of the readonly Viewer boundary.

///|
/// Encoded tokens for one contiguous inclusive interval of one-based lines.
/// Each inner array contains `[endOffset, metadata]` pairs for one line.
/// Source: `contiguousMultilineTokens.ts:17,35-46`.
pub struct ContiguousMultilineTokens {
  start_line_number_ : Int
  tokens : Array[Array[UInt]]
}

///|
/// Retains the caller's line order and encoded token arrays.
/// Source: `contiguousMultilineTokens.ts:62-65`.
#alias(new, deprecated)
pub fn ContiguousMultilineTokens::ContiguousMultilineTokens(
  start_line_number : Int,
  tokens : Array[Array[UInt]],
) -> ContiguousMultilineTokens {
  { start_line_number_: start_line_number, tokens }
}

///|
/// Inclusive first line of this batch.
/// Source: `contiguousMultilineTokens.ts:51-53`.
pub fn ContiguousMultilineTokens::start_line_number(
  self : ContiguousMultilineTokens,
) -> Int {
  self.start_line_number_
}

///|
/// Inclusive final line of this batch.
/// Source: `contiguousMultilineTokens.ts:58-60`.
pub fn ContiguousMultilineTokens::end_line_number(
  self : ContiguousMultilineTokens,
) -> Int {
  self.start_line_number_ + self.tokens.length() - 1
}

///|
/// Half-open line range covered by this batch.
/// Source: `contiguousMultilineTokens.ts:67-69`.
pub fn ContiguousMultilineTokens::get_line_range(
  self : ContiguousMultilineTokens,
) -> @base_common.LineRange {
  let range : @base_common.LineRange = {
    start_line_number: self.start_line_number_,
    end_line_number_exclusive: self.start_line_number_ + self.tokens.length(),
  }
  range
}

///|
/// Returns the encoded words for an included one-based line.
/// Source: `contiguousMultilineTokens.ts:74-76`.
pub fn ContiguousMultilineTokens::get_line_tokens(
  self : ContiguousMultilineTokens,
  line_number : Int,
) -> Array[UInt] {
  self.tokens[line_number - self.start_line_number_]
}

///|
/// Extends the batch by exactly one final line.
/// Source: `contiguousMultilineTokens.ts:78-80`.
pub fn ContiguousMultilineTokens::append_line_tokens(
  self : ContiguousMultilineTokens,
  line_tokens : Array[UInt],
) -> Unit {
  self.tokens.push(line_tokens)
}
