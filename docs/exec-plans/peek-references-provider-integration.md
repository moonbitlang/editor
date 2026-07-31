# Peek References Provider Integration

Status: active
Date: 2026-07-31
Oracle: VS Code gitlink `b18492a288de038fbc7643aae6de8247029d11bd`

## Goal

Complete the provider-backed Peek References path around the already-landed
precomputed References Peek UI:

- `Shift+F12` starts Peek References;
- `Peek References` is available in the editor context menu;
- the shared References shell displays query progress, grouped results,
  previews, and an accessible empty result;
- the reference workbench reaches
  `moon ide find-references --loc <path:line:column> --json`.

The existing public
`Viewer::show_references(Position, Array[Location])` entry remains a
presentation-only seam. Provider discovery and query ownership are added
beside it without changing its contract.

## Scope and Mode

### Upstream source

- `vscode/src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:644-727`
  for provider-backed References actions, availability, Shift+F12, context
  menu placement, no-result behavior, and Peek dispatch;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/goToSymbol.ts:23-91` for
  ordered provider aggregation, failure isolation, cancellation, and
  `includeDeclaration=true`;
- `vscode/src/vs/editor/contrib/gotoSymbol/browser/peek/referencesController.ts:
  77-187` for one request owner, replacement, and stale-result rejection;
- the References model/widget/tree source clusters already recorded in
  `docs/references/monaco.md` for the landed UI.

This is a behavior port. Request cancellation and freshness use the existing
generation-based root ownership and retain algorithm-fidelity for the
observable replacement/teardown ordering. It is not a full source audit.

### Adopted behavior

- register references providers with the same selector priority and
  newer-first tie ordering as definitions;
- query every matching live provider, isolate provider failures, retain
  registry order independently of completion order, and drop cancelled or
  disposed registrations;
- request locations with the repository's existing ReferencesProvider
  contract, whose result includes the declaration;
- make the action available only for a mounted outer Code or semantic-Markdown
  Viewer with a matching provider and a valid command anchor;
- use `Shift+F12` and a top-level `Peek References` context-menu row after
  Peek Definition;
- open the shared shell immediately in `Loading references...`, keep
  `No references found` visible for an authoritative empty result, and reuse
  the landed tree/preview/lifetime implementation for nonempty results;
- cancel and reject the query on another navigation intent, anchor movement,
  model/content replacement, Peek replacement, or disposal;
- register the remote browser client as a ReferencesProvider and map the
  existing protocol `ReferenceItem` payloads back to `Location`;
- invoke native Moon exactly as
  `moon ide find-references --loc <path:line:column> --json`, without
  `--no-check`, and normalize contained results through the same JSON-location
  parser used by `peek-def`.

### Intentional differences and exclusions

- VS Code gives Shift+F12 to `Go to References`; its configured
  `multipleReferences` preference normally determines whether multiple
  results use Peek. The readonly Viewer has no goto-location preference or
  editable navigation history, so Shift+F12 directly runs the Peek action.
- VS Code places Peek References in `EditorContextPeek`. The local HTML menu
  deliberately keeps navigation actions as adjacent top-level rows, matching
  the existing Definition menu contract.
- The local `ReferencesProvider` predates `ReferenceContext`; Moon
  `find-references --json` already returns the definition followed by
  references, so this slice does not add an unused include-declaration
  parameter.
- Go to References, alternative commands, Workbench References View,
  CodeLens, document highlights, result filtering/history/copy, protocol-level
  cancellation packets, and progress notifications are out of scope.

## Representation Decision

`Languages` gains a concrete References provider registry parallel to the
Definition registry, and `LanguageHandle` gains only the callbacks consumed by
the root Viewer. No new trait or service hierarchy is needed.

The existing per-Viewer `ReferencesContributionState` owns the provider query
source and generation in addition to the already-computed result session. A
typed request stamp covers model identity, attachment generation, content
version, session generation, and source identity before a result can enter the
shared Peek. Closing the session detaches the query source before cancellation
callbacks run.

The existing remote protocol already owns `References` and
`ReferencesResult`; the workbench adapter implements the existing
`ReferencesProvider` trait and does not expose wire DTOs to Viewer packages.
The native host remains the only owner of CLI execution and disk-to-remote URI
normalization.

## Gate A Record

- Working tree before this plan: clean on `codex/peek-references-ui` at
  `514d02c3`.
- Moon toolchain:
  `moon 0.1.20260730 (7611a39)`,
  `moonc v0.10.5+8d79ef683-nightly`.
- VS Code gitlink:
  `b18492a288de038fbc7643aae6de8247029d11bd`.
- Baseline `moon check --target all --warn-list +73`: green.
- Existing reusable pieces:
  `language.ReferencesProvider`, remote References request/result packets,
  server routing/enrichment, shared References controller, grouped ARIA tree,
  nested preview, model leases, and public precomputed display entry.
- Confirmed gaps:
  `viewer/common/languages` has no References registry/handle,
  the root References contribution has no provider action,
  the workbench does not register/implement its remote References provider,
  and the native provider still returns `[]` under an obsolete
  “no machine-readable query” comment.
- No new package dependency edge is required. Public generated-interface
  changes are limited to `viewer/common/languages`; the root Viewer public API
  remains unchanged.

Gate A review result: the current package graph supports the requested feature
without changing scope, public Viewer API, or host ownership.

## Evidence Map

| Behavior or invariant | Source | MoonBit disposition | Evidence |
| --- | --- | --- | --- |
| provider availability and ordered aggregation | `goToSymbol.ts:23-72` | References registry parallel to Definition | focused `viewer/common/languages` reference tests |
| declaration-inclusive provider query | `goToSymbol.ts:77-91` | existing provider result contract and Moon CLI output | registry test plus native command test |
| Shift+F12 and menu action | `goToCommands.ts:644-727` | direct Peek action, flat local menu | registry white-box and Playwright gestures |
| loading, empty, and populated Peek | `goToCommands.ts:105-167`; References controller/widget clusters | shared current References controller | mounted Viewer tests and component scenario |
| cancellation and stale-result rejection | `referencesController.ts:77-187` | query source + exact request stamp | controlled-provider mounted tests |
| remote request adaptation | local protocol contract | `ReferenceItem` to `Location` | workbench provider test |
| exact Moon invocation and URI filtering | Moon CLI help plus native host boundary | `find-references --loc ... --json` | native host probe and parser tests |
| landed grouped UI, preview, navigation, ARIA | References model/widget/tree clusters | unchanged existing implementation | existing reference and Playwright suites |

## Milestones

### 1. Language registry and root action

Status: complete

- add References registration, presence, query, handle callbacks, docs, and
  generated interfaces;
- add provider query ownership to the shared References contribution;
- register Shift+F12 and the context-menu action for Code;
- route the same action from semantic Markdown;
- cover provider ordering/cancellation and Viewer action lifecycle.

Focused gate:

```sh
moon test viewer/common/languages --target all
moon test viewer --target js
moon check --target all --warn-list +73
moon fmt --check
```

Commit the coherent green milestone.

Evidence:

- `viewer/common/languages` passed 43/43 tests independently on js, native,
  and wasm. Moon's `--target all` test invocation first ran the wasm cases
  green, then rejected the package for unsupported `wasm-gc`; the explicit
  declared targets are the authoritative focused gate.
- root `viewer` passed 289/289 js tests, including Shift+F12 registration,
  provider loading/results/empty states, cancellation on cursor movement, and
  precomputed-intent supersession.
- `moon check --target all --warn-list +73` and `moon fmt --check` passed.

### 2. Remote and native provider integration

- implement/register the workbench ReferencesProvider;
- adapt existing ReferencesResult payloads to locations;
- replace the native stub with the exact Moon command and shared parser;
- update provider/host/workbench contracts and focused tests.

Focused gate:

```sh
moon test internal/shell/workbench --target js
moon test server/host
moon test server/server
moon check --target all --warn-list +73
moon fmt --check
```

Commit the coherent green milestone.

### 3. Browser proof and final contracts

- add real Shift+F12 and right-click action coverage for Code and semantic
  Markdown while retaining native fallback on ordinary Markdown;
- update architecture, Monaco mapping, harness, Viewer/language/package docs,
  and generated interfaces;
- run required repository gates;
- compress this plan into `HISTORY.md` and remove the detailed file.

Final gate:

```sh
moon info --target all
moon check --target all --warn-list +73
moon fmt --check
just test
just build
just test-browser-smoke
git diff --check
```

## Test Matrix

- no provider, unmatched provider, and disposed provider;
- multiple providers finishing out of order, one failing, and cancellation;
- Code Shift+F12, context-menu click, repeated-anchor toggle, and empty result;
- semantic Markdown Shift+F12 and context-menu click at a valid projected
  anchor; ordinary Markdown remains native;
- cursor/anchor change, content/model replacement, newer Peek intent, and
  disposal while the query is pending;
- remote request URI/revision/offset, ordered result mapping, cancellation,
  protocol failure, and late-response tombstone;
- exact native argv, malformed JSON, contained relative/absolute paths,
  out-of-root filtering, and cancellation;
- existing grouped tree, preview, F4, Current/Side opening, ARIA, and teardown
  suites remain green.

## Exit Gate

- [x] scope, mode, oracle revision, representation, and exclusions recorded
- [x] current source/package gaps reviewed
- [ ] provider registry and query lifecycle have focused evidence
- [ ] Shift+F12 and context-menu action work in Code and semantic Markdown
- [ ] workbench reaches the existing References protocol
- [ ] native host invokes `moon ide find-references --loc ... --json`
- [ ] generated interfaces and dependency direction reviewed
- [ ] focused and required repository gates green
- [ ] final contracts updated and this plan compressed into history
