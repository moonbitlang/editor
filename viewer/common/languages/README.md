# viewer/common/languages

The viewer's DOM-free language registry and token-to-HTML helpers.

## Registered features

- Ordered, disposable registries exist for hover, document symbols, and
  whole-line Markdown comments. Hover requests snapshot matching registrations
  before their first await, forward the caller's exact cancellation token,
  reject a result from a registration disposed during the await, and keep
  cancellation silent; ordinary provider failures are logged and contained.
  `hover_at` returns the first non-empty live result.
- Markdown-comment lookup returns the first matching provider's raw synchronous
  result. `None` means no provider matched; `Some([])` is authoritative. A
  provider failure is logged and remains authoritative as `Some([])` so a later
  provider or configuration fallback cannot silently replace it.
- `set_language_configuration` stores the normalized comments and folding-rules
  slices of Monaco's `LanguageConfiguration`. Empty present comment delimiters
  are rejected; region markers remain whole-line predicates rather than regular
  expressions.
- `set_tokens_provider` forwards to the process-wide
  `syntax.tokenization_registry`. Therefore tokenizer registrations remain global
  even when tests or embedders use an isolated `Languages()` instance.
- `tokenize_line_to_html` and `tokenize_to_string` port
  `vs/editor/common/languages/textToHtmlTokenizer.ts`.

There are currently no diagnostics, semantic-token, definition, or references
registries. Diagnostics use `viewer/common/markers`; definition/reference traits
remain host/protocol contracts in `language`.

`languages` is the process-wide instance used by default Viewer services;
`default_languages()` returns that same instance. The package has no viewer-root,
contribution, DOM, or host dependency. See `pkg.generated.mbti` for the complete
surface and run `moon test --target js viewer/common/languages`.

`Languages::language_handle(log_handle)` returns the opaque capability consumed
by `ViewerServices`. It exposes configuration lookup, raw Markdown-comment
provider selection, and contained hover resolution; registrations, tokenizer
mutation, document-symbol queries, and the concrete registry lifecycle stay on
the caller-retained `Languages` value. The handle borrows its backing and never
disposes it.
