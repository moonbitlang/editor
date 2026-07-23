# Quality Gates

Current docs and package READMEs are product contracts. Keep architecture here
and in `docs/architecture.md`, package details in package READMEs, and completed
plan history in `docs/exec-plans/HISTORY.md`.

## Required Checks

```sh
just check
just test
just build
just test-browser
```

Run the subset relevant to each milestone; run all four before declaring a
cross-package or browser-visible implementation complete.

## Guardrails

- Product code never imports `vscode/`, `codemirror/`, or the reference shell.
- Shared packages remain FFI-free; js/native-only packages declare their target.
- Viewer packages use only Rabbita's DOM/JS bindings, not its TEA framework.
- The shell/backend remains optional to embedders.
- `just check` is read-only: it checks every target and verifies formatting.
- Review `moon.pkg` changes against `docs/architecture.md`, and review public API
  changes through `pkg.generated.mbti`.
- Do not add architecture lint for a one-time design decision. Automate a
  boundary only after the same concrete failure recurs, and keep the check
  generic rather than naming current methods or implementation types.

## Reference Tests

Use `*_reference_test.mbt` / `*_reference_wbtest.mbt` when a test is traceable
to a pinned Monaco, VS Code, or CodeMirror source test or behavior cluster.

- Name the source path and pinned revision in the file or test comment.
- Preserve source labels, inputs, outputs, ordering, and boundary values when
  they are part of the behavior under test.
- Within the selected source-test or behavior scope, keep unsupported cases
  visible as `SKIPPED` with a product-boundary reason instead of silently
  deleting them.
- Test observable behavior and algorithmic invariants. TypeScript interfaces,
  class hierarchies, and private field layout are not conformance contracts.
