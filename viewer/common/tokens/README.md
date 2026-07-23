# viewer/common/tokens

Binary token values and the contiguous syntactic store shared by model
tokenization and view-line rendering.

- `LineTokens` mirrors Monaco's flat `Uint32Array`: each pair is an exclusive end
  offset followed by a packed metadata word. It provides token lookup, text/class/
  style reads, zero-copy slicing for wrapped lines, and `with_inserted` for injected
  text. `ViewLineTokens` is the closed full-or-sliced view consumed by renderers.
- `encoded_token_attributes.mbt` defines the 32-bit language, standard-token-type,
  balanced-bracket, font-style, foreground, and background layout plus
  `TokenMetadata` decoders. Metadata is `UInt` because the background occupies the
  high byte.
- `ContiguousMultilineTokens` and its builder collect adjacent encoded line results
  without serialization or edit transforms. `ContiguousTokensStore` owns the
  per-model syntactic cache with distinct `Missing`, `Empty`, and encoded-word
  states. Reads are passive: a missing/empty line returns one default token and
  never invokes a lexer.
- Store batches accept only a top-level language id and a live line-length closure.
  This package never imports `viewer/common/model`; scheduling, carried tokenizer
  state, and acquisition remain with that higher package. Sparse semantic
  provider/application behavior is not implemented here.
- All token offsets and content slices are raw UTF-16 code-unit offsets. Slices may
  retain lone surrogates or either half of a valid pair, matching Monaco strings.

Upstream sources are `vs/editor/common/tokens/{lineTokens,
contiguousTokensStore,contiguousMultilineTokens,
contiguousMultilineTokensBuilder}.ts` and
`vs/editor/common/encodedTokenAttributes.ts`. The reduced `ViewLineTokens` omits
Monaco's concrete-type `equals`/codec accessor, and the unported `TokenArray` family
keeps `getTokensInRange` out of scope. Typed-array versus `ArrayBuffer` identity,
worker serialization, incremental token edits, and sparse semantic merging are
outside the readonly in-process boundary.

This package may depend only on `base/common` and `viewer/common/services`; it must
not import model, view-model, syntax, DOM, or host packages. See
`pkg.generated.mbti`; run `moon test --target js viewer/common/tokens`.
