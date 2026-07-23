///| Source-shaped in-process builder for contiguous token batches.
///
/// Source:
/// `vscode/src/vs/editor/common/tokens/contiguousMultilineTokensBuilder.ts`
/// at checked-in oracle, consumed
/// closure lines 9 and 21-41. Worker serialization remains outside the
/// readonly Viewer boundary.

///|
/// Collects adjacent one-based lines into ordered contiguous batches.
/// Source: `contiguousMultilineTokensBuilder.ts:9,21`.
pub struct ContiguousMultilineTokensBuilder {
  tokens : Array[ContiguousMultilineTokens]
}

///|
/// Creates an empty collector.
/// Source: `contiguousMultilineTokensBuilder.ts:23-25`.
#alias(new, deprecated)
pub fn ContiguousMultilineTokensBuilder::ContiguousMultilineTokensBuilder() -> ContiguousMultilineTokensBuilder {
  { tokens: [] }
}

///|
/// Appends to the final batch only when `line_number` is its exact successor;
/// gaps and out-of-order lines begin a new batch.
/// Source: `contiguousMultilineTokensBuilder.ts:27-37`.
pub fn ContiguousMultilineTokensBuilder::add(
  self : ContiguousMultilineTokensBuilder,
  line_number : Int,
  line_tokens : Array[UInt],
) -> Unit {
  if self.tokens.length() > 0 {
    let last = self.tokens[self.tokens.length() - 1]
    if last.end_line_number() + 1 == line_number {
      last.append_line_tokens(line_tokens)
      return
    }
  }
  self.tokens.push(ContiguousMultilineTokens(line_number, [line_tokens]))
}

///|
/// Returns the accumulated batches in insertion order without copying them.
/// Source: `contiguousMultilineTokensBuilder.ts:39-41`.
pub fn ContiguousMultilineTokensBuilder::finalize(
  self : ContiguousMultilineTokensBuilder,
) -> Array[ContiguousMultilineTokens] {
  self.tokens
}
