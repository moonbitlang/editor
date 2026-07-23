# syntax

Stateful lexical highlighting for readonly text. It keeps Monaco's line-tokenizer
architecture but replaces runtime Monarch grammars with MoonBit `lexmatch` code.

## Runtime contract

- `LineTokenizer::tokenize_line` receives one line plus `TokenizerState` and
  returns `LineToken[]` plus the state for the next line. Token offsets are UTF-16
  code units; gaps are rendered as plain text.
- `TokenizationRegistry` registers tokenizers by language id and emits
  `TokenizationChangedEvent { changed_languages, changed_color_map }`.
  Registration, replacement, explicit `handle_change`, and active removal emit
  exact language-id arrays with `changed_color_map=false`; disposing a stale
  registration is inert. `get` returns the current synchronous support and
  `is_resolved` is always true because this package has no lazy factory state.
- Monaco's registry `Color[] | null` / `Color | null` surface is deliberately
  reduced to `Array[String]?` / `String?`. Entries are retained, unparsed CSS
  color expressions. `set_color_map(Array[String])` emits every active language
  with `changed_color_map=true`; `get_color_map()` returns the retained option;
  `get_default_background()` returns literal index 2 only when the array length
  is greater than 2. No `Color` object behavior or identity is exposed.
- `tokenization_registry` is process-wide. `Languages::set_tokens_provider`
  forwards into it; `viewer/common/model` performs the state-threaded
  per-line encoding, passive storage reads, and explicit/visible/background
  demand scheduling.
- `PlainTokenizer` is an explicit stateless tokenizer, not an automatic fallback.
  A registry miss is encoded by the model tokenization part as one default token
  per line.

This maps to `ITokenizationSupport`, `IState`, and `TokenizationRegistry` in
`vs/editor/common/languages.ts` and `common/tokenizationRegistry.ts`.
The registry port is intentionally synchronous: Monaco's
`registerFactory`/`getOrCreate` Promise surface and lazy-factory carrier are not
part of the public `LineTokenizer` API and are not emulated here.

## Concrete lexers

`syntax/lang_moonbit`, `lang_json`, and `lang_javascript` each expose a tokenizer
implementing `LineTokenizer`. Concrete languages are selected by hosts, examples,
or tests; reusable viewer core packages must not import them. There is no runtime
grammar-loading or `setMonarchTokensProvider` equivalent.

When translating a Monarch or CodeMirror grammar:

- Use `lexmatch ... with longest`; equal-length matches choose the earliest arm.
  Longest-match arms do not support guards, so classify a bound identifier in the
  arm body and inspect the returned remainder for lookahead (for example
  `lang_json`'s `colon_follows`).
- Carry multiline modes in `TokenizerState`; use scoped `(?i:...)` for
  case-insensitive rules. Dynamic delimiters/backreferences require a small manual
  scan because a DFA cannot encode them.
- Regex literals use strict single-backslash escapes. Write literal braces as
  `[{]`/`[}]`; escape `-` and `]` inside classes. Single-character bindings are
  `Char`, longer bindings are `StringView`.
- Guarantee progress with a final `(".", rest)` arm and the mandatory catch-all;
  the catch-all must consume the remaining view. Never split a surrogate pair at
  an emitted token boundary.

## Boundaries and checks

`syntax` may depend only on `base/common`; each `syntax/lang_*` package may depend
only on `syntax`. It owns neither diagnostics nor semantic tokens; semantic-token
overlay is not implemented. The complete API is `pkg.generated.mbti`. Run
`moon test --target js syntax` plus the relevant `syntax/lang_*` package tests.
