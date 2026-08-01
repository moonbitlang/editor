# viewer/common/tokens

Binary token values and the contiguous syntactic store shared by model
tokenization and view-line rendering.

A rendered line can carry hundreds of tokens, and a document can carry hundreds
of thousands of lines. The storage representation remains two `UInt` words per
token in a flat array, and every read is an index computation. The opaque
`TokenMetadata` newtype marks semantic API boundaries without changing that raw
interleaved layout.

## The packed metadata word

```mermaid
flowchart LR
  subgraph W["one 32-bit metadata UInt"]
    direction LR
    B["background<br>bits 24-31"]
    F["foreground<br>bits 15-23"]
    S["font style<br>bits 11-14"]
    K["balanced brackets<br>bit 10"]
    T["token type<br>bits 8-9"]
    L["language id<br>bits 0-7"]
  end
```

`encoded_token_attributes.mbt` defines the 32-bit language, standard-token-type,
balanced-bracket, font-style, foreground, and background layout plus
`TokenMetadata` decoders. Its backing word is `UInt` because the background
occupies the high byte — a signed `Int` would make a fully saturated background
negative.

The offsets are public, so a caller can compose a raw word, wrap it as
`TokenMetadata`, and read it back with the same constants the renderer uses.

```mbt check
///|
test "a metadata word round-trips through the published offsets" {
  let metadata = @tokens.TokenMetadata::from_uint(
    (2U << @tokens.METADATA_LANGUAGEID_OFFSET) |
    (
      @tokens.STANDARD_TOKEN_TYPE_COMMENT.reinterpret_as_uint() <<
      @tokens.METADATA_TOKEN_TYPE_OFFSET
    ) |
    (
      (@tokens.FONT_STYLE_ITALIC | @tokens.FONT_STYLE_BOLD).reinterpret_as_uint() <<
      @tokens.METADATA_FONT_STYLE_OFFSET
    ) |
    (7U << @tokens.METADATA_FOREGROUND_OFFSET) |
    (200U << @tokens.METADATA_BACKGROUND_OFFSET),
  )
  debug_inspect(
    (
      metadata.get_language_id(),
      metadata.get_token_type(),
      metadata.get_font_style(),
      metadata.get_foreground(),
      metadata.get_background(),
      metadata.contains_balanced_brackets(),
    ),
    content=(
      #|(2, 1, 3, 7, 200, false)
    ),
  )
}
```

`get_presentation_from_metadata` is the decoded form the renderer actually
consumes; the font-style bits become named booleans.

```mbt check
///|
test "presentation decodes the font-style bits into booleans" {
  let styled = @tokens.TokenMetadata::from_uint(
    (
      (@tokens.FONT_STYLE_ITALIC | @tokens.FONT_STYLE_UNDERLINE).reinterpret_as_uint() <<
      @tokens.METADATA_FONT_STYLE_OFFSET
    ) |
    (5U << @tokens.METADATA_FOREGROUND_OFFSET),
  )
  let presentation = styled.get_presentation_from_metadata()
  debug_inspect(
    (
      presentation.foreground,
      presentation.italic,
      presentation.bold,
      presentation.underline,
      presentation.strikethrough,
      styled.get_class_name_from_metadata(),
    ),
    content=(
      #|(5, true, false, true, false, "mtk5 mtki mtku")
    ),
  )
}
```

## LineTokens

`LineTokens` mirrors Monaco's flat `Uint32Array`: each pair is an exclusive end
offset followed by a packed metadata word. It provides token lookup, text/class/
style reads, zero-copy slicing for wrapped lines, and `with_inserted` for injected
text.

`create_from_text_and_metadata` is the readable constructor — it derives the end
offsets from the token texts.

```mbt check
///|
test "tokens are addressed by index, and offsets are exclusive ends" {
  let codec = @services.LanguageIdCodec()
  let line = @tokens.LineTokens::create_from_text_and_metadata(
    [
      ("let", @tokens.TokenMetadata::from_uint(1U)),
      (" ", @tokens.TokenMetadata::from_uint(0U)),
      ("x", @tokens.TokenMetadata::from_uint(2U)),
    ],
    codec,
  )
  debug_inspect(
    (
      line.get_count(),
      line.get_line_content(),
      line.get_text_length(),
      (0)
      .until(line.get_count())
      .map(i => {
        (
          line.get_token_text(i),
          line.get_start_offset(i),
          line.get_end_offset(i),
        )
      })
      .collect(),
    ),
    content=(
      #|(3, "let x", 5, [("let", 0, 3), (" ", 3, 4), ("x", 4, 5)])
    ),
  )
}
```

`find_token_index_at_offset` is the hot lookup: it is a binary search over the
flat array, not a scan.

```mbt check
///|
test "offset lookup maps a column into a token index" {
  let codec = @services.LanguageIdCodec()
  let line = @tokens.LineTokens::create_from_text_and_metadata(
    [
      ("let", @tokens.TokenMetadata::from_uint(1U)),
      (" ", @tokens.TokenMetadata::from_uint(0U)),
      ("x", @tokens.TokenMetadata::from_uint(2U)),
    ],
    codec,
  )
  debug_inspect(
    [0, 2, 3, 4, 99].map(offset => line.find_token_index_at_offset(offset)),
    content=(
      #|[0, 0, 1, 2, 2]
    ),
  )
}
```

Slicing is what wrapped lines need: one model line becomes several view lines,
and each view line must present its own sub-range of the same token array
without copying it.

```mbt check
///|
test "slicing produces a view over the same underlying tokens" {
  let codec = @services.LanguageIdCodec()
  let line = @tokens.LineTokens::create_from_text_and_metadata(
    [
      ("hello", @tokens.TokenMetadata::from_uint(1U)),
      (" ", @tokens.TokenMetadata::from_uint(0U)),
      ("world", @tokens.TokenMetadata::from_uint(2U)),
    ],
    codec,
  )
  let sliced = line.slice_zero_copy(OffsetRange(6, 11))
  debug_inspect(
    (
      sliced.get_count(),
      sliced.get_line_content(),
      (0).until(sliced.get_count()).map(i => sliced.get_token_text(i)).collect(),
    ),
    content=(
      #|(1, "world", ["world"])
    ),
  )
}
```

`with_inserted` is how injected text (the view-model's inline insertions) joins a
line's token stream without the model ever containing that text.

```mbt check
///|
test "injected text splices new tokens into a copy" {
  let codec = @services.LanguageIdCodec()
  let line = @tokens.LineTokens::create_from_text_and_metadata(
    [("value", @tokens.TokenMetadata::from_uint(1U))],
    codec,
  )
  let with_hint = line.with_inserted([
    InsertedToken(5, " : Int", @tokens.TokenMetadata::from_uint(3U)),
  ])
  debug_inspect(
    (
      line.get_line_content(),
      with_hint.get_line_content(),
      (0)
      .until(with_hint.get_count())
      .map(i => with_hint.get_token_text(i))
      .collect(),
    ),
    content=(
      #|("value", "value : Int", ["value", " : Int"])
    ),
  )
}
```

`ViewLineTokens` is the closed full-or-sliced view consumed by renderers, so a
renderer never needs to know whether it was handed a whole line or a fragment.

## The per-model store

`ContiguousMultilineTokens` and its builder collect adjacent encoded line results
without serialization or edit transforms. `ContiguousTokensStore` owns the
per-model syntactic cache with distinct `Missing`, `Empty`, and encoded-word
states.

```mermaid
stateDiagram-v2
  [*] --> Missing: line never tokenized
  Missing --> Words: set_tokens with real words
  Missing --> Empty: set_tokens(None) or an empty/default array
  Words --> Missing: flush()
  Empty --> Missing: flush()
  Words --> Words: set_tokens replaces
```

Reads are passive: a missing/empty line returns one default token and
never invokes a lexer. That is the property that keeps rendering off the
tokenizer's critical path.

```mbt check
///|
test "an untokenized line reads back as one default token" {
  let store = @tokens.ContiguousTokensStore(LanguageIdCodec())
  let missing = store.get_tokens("moonbit", 0, "let x = 1")
  debug_inspect(
    (
      store.has_tokens(),
      missing.get_count(),
      missing.get_token_text(0),
      missing.get_end_offset(0),
    ),
    content=(
      #|(false, 1, "let x = 1", 9)
    ),
  )
}
```

`set_tokens` returns whether the line actually changed, but only when the caller
asks for the equality check — the unchecked lane always reports `false`.

```mbt check
///|
test "set_tokens reports change only when equality is checked" {
  let store = @tokens.ContiguousTokensStore(LanguageIdCodec())
  let words = [3U, 1U, 4U, 0U]
  debug_inspect(
    (
      store.set_tokens("moonbit", 0, 4, Some(words), true),
      // same words again: no change
      store.set_tokens("moonbit", 0, 4, Some(words), true),
      // unchecked lane never reports a change
      store.set_tokens("moonbit", 0, 4, Some([3U, 2U, 4U, 0U]), false),
      store.has_tokens(),
    ),
    content=(
      #|(true, false, false, true)
    ),
  )
}
```

`flush` returns every line to `Missing`, which is what a whole-document reset
does.

```mbt check
///|
test "flush returns the store to its untokenized state" {
  let store = @tokens.ContiguousTokensStore(LanguageIdCodec())
  store.set_tokens("moonbit", 0, 4, Some([4U, 1U]), true) |> ignore
  let before = store.get_tokens("moonbit", 0, "abcd").get_metadata(0)
  store.flush()
  let after = store.get_tokens("moonbit", 0, "abcd").get_metadata(0)
  debug_inspect(
    (store.has_tokens(), before == after),
    content=(
      #|(false, false)
    ),
  )
}
```

The builder accumulates adjacent line results and coalesces them into runs, so a
sweep over a viewport produces a few `ContiguousMultilineTokens` rather than one
per line.

```mbt check
///|
test "the builder coalesces adjacent lines and splits at gaps" {
  let builder = @tokens.ContiguousMultilineTokensBuilder()
  builder.add(1, [4U, 1U])
  builder.add(2, [4U, 1U])
  // a gap at line 3 starts a new run
  builder.add(7, [4U, 1U])
  debug_inspect(
    builder
    .finalize()
    .map(run => (run.start_line_number(), run.end_line_number())),
    content=(
      #|[(1, 2), (7, 7)]
    ),
  )
}
```

Store batches accept only a top-level language id and a live line-length closure.
This package never imports `viewer/common/model`; scheduling, carried tokenizer
state, and acquisition remain with that higher package. Sparse semantic
provider/application behavior is not implemented here.

## UTF-16 boundaries

All token offsets and content slices are raw UTF-16 code-unit offsets. Slices may
retain lone surrogates or either half of a valid pair, matching Monaco strings.

```mbt check
///|
test "a slice may split a surrogate pair, matching Monaco strings" {
  let codec = @services.LanguageIdCodec()
  let line = @tokens.LineTokens::create_from_text_and_metadata(
    [
      ("😀", @tokens.TokenMetadata::from_uint(1U)),
      ("x", @tokens.TokenMetadata::from_uint(2U)),
    ],
    codec,
  )
  // The emoji is two UTF-16 units, so offset 1 is inside it.
  let split = line.slice_zero_copy(OffsetRange(1, 3))
  debug_inspect(
    (line.get_text_length(), split.get_line_content().length()),
    content=(
      #|(3, 2)
    ),
  )
}
```

## Boundaries and checks

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
`pkg.generated.mbti`.

```sh
moon test --target js viewer/common/tokens
```
