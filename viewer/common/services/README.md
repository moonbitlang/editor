# viewer/common/services

The common-layer language-id codec used by binary token metadata.

`LanguageIdCodec` assigns stable integer ids and decodes them back to strings.
Fresh codecs are seeded with `null`, `plaintext`, `moonbit`, `javascript`,
`typescript`, and `json`; `encode_language_id` returns `0` for an unregistered
language, while `register` allocates it. Invalid numeric ids decode as `null`.

`language_id_codec` is process-wide so every model interprets the low eight
language-id bits of Monaco's token metadata consistently. Isolated codecs remain
available for tests.

This is the `ILanguageIdCodec` slice of
`vs/editor/common/services/languagesRegistry.ts`. The package is a dependency leaf
with no model, token, syntax, DOM, or host imports. See `pkg.generated.mbti`; its
behavior is also covered by the token and model-token suites.
