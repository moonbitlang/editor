# internal/viewer/markdown

Multi-target safe Markdown-to-HTML conversion shared by browser features.

The package owns the cmark boundary. `MarkdownCodeBlock` is a MoonBit value,
so callers can synchronously replace fenced-code rendering without importing
cmark types. Every conversion uses the safe HTML renderer; a conversion error
falls back to one escaped plaintext paragraph. `MarkdownRenderFact` reports
whether the input contained a code block independently of whether a caller
overrode its HTML.

The exact lowercase `diago` fence is a built-in synchronous diagram adapter.
It compiles source directly to wrapped SVG before a caller-supplied code-block
renderer runs. Parse or render failures fall through to that caller override,
or to cmark's ordinary `<pre><code>` output when no override exists. Unknown,
differently cased, unlabelled, and indented code blocks are never diagrams.

`render_tokenized_code_block` is the shared editor override: it selects a fenced
or active model language, threads tokenizer state across lines, and emits the
existing `monaco-tokenized-source`/`mtk*` classes. Hover and whole-line Markdown
comments both use that owner.

Browser DOM policy, URI rewriting, listeners, target reuse, and disposal live
in `internal/viewer/browser/markdown`.

Run the focused suite on both supported targets:

```sh
moon test internal/viewer/markdown --target js
moon test internal/viewer/markdown --target native
```
