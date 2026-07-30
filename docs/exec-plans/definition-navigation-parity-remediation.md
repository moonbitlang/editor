# Definition Navigation Parity Remediation

## Goal

Remove the source-level behavior and lifetime gaps that can make Goto
Definition, definition links, and Peek Definition return the wrong result,
ignore a valid gesture, remain stuck in a loading state, or release preview
resources in the wrong order.

The pinned behavioral oracle is the `vscode` gitlink at
`b18492a288de038fbc7643aae6de8247029d11bd`.

## Port mode

- Definition-provider collection, command dispatch, result choice, and
  user-visible feedback use a **behavior port**.
- Ctrl/Command-click input ordering and Peek request/resource replacement use
  an **algorithm-fidelity port** because key edges, request generations,
  focus, and dispose ordering are observable state machines.
- This is not a full source-unit audit. Workspace history, editor groups,
  mutable editing, and VS Code service topology remain outside the standalone
  Viewer contract.

## Confirmed gaps

| Area | Current local behavior | Required behavior/evidence |
| --- | --- | --- |
| Provider collection | Stops at the first non-empty provider | Invoke every matching provider concurrently, isolate failures, and concatenate live results in provider order (`goToSymbol.ts:getLocationLinks`) |
| F12 result dispatch | Always opens normalized result zero | One result opens directly; multiple results use Peek by the default `multipleDefinitions = "peek"` policy |
| Definition-link execution | Requires the preview request to finish and opens its cached result zero | Record the click independently of preview resolution and run a fresh Definition action at mouseup (`clickLinkGesture.ts`, `goToDefinitionAtPosition.ts`) |
| Definition-link identity | Exact pointer column is part of cache and down/up equality | Reuse preview work for the same word; execute when down/up remain on the same eligible line |
| Modifier lifetime | Successful mouseup can retain modifier and pointer state; unrelated Ctrl/Cmd chords remain armed | Reset the whole gesture after execution, cancel on trigger keyup and unrelated trigger-modified keydown, blur, drag, scroll, model/content change, and disposal |
| Empty link preview | Shows `No definition found` while merely hovering with Ctrl/Cmd | Remain silent and cache the empty answer for that word/gesture |
| Peek toggle/freshness | Same-anchor Alt+F12 closes then reopens; Markdown pointer movement can strand a loading shell | Same anchor toggles closed; captured model/projection state, not later hover position, owns request freshness |
| Peek replacement | Clears the installed child/reference before a replacement resolves | Keep the installed preview until a current replacement can commit, then dispose child before its reference and before the shell |
| Peek focus/order | Code shell focuses while its ViewZone is still hidden; F4 can destroy focused preview; shell is disposed before child | Focus after zone layout, preserve preview focus across selection, and tear down child/reference before widget/zone |
| Workbench preview leases | `DidDispose` can synchronously zero active lease counts before contribution teardown | Make outer Viewer teardown finish before the host retires the remaining cache entries |

## Milestones

### 1. Provider and action semantics

- Aggregate all matching definition providers with stable ordering, liveness,
  cancellation, and error isolation.
- Route both F12 and link execution through one resolved-result dispatcher.
- Open one result directly and multiple results in Peek when mounted; retain a
  deterministic first-result fallback only when Peek is unavailable.
- Keep ordinary F12 no-result feedback and make link-preview no-result silent.
- Add focused registry and Viewer white-box tests.

### 2. Gesture state machine

- Separate mouse down/up execution state from asynchronous link-preview state.
- Cache preview work by model/version/word rather than exact hover column.
- Pass key identity and key edge into the modifier handler.
- Add code scroll cancellation and full post-execution cleanup.
- Cover slow preview providers, fresh execution queries, same-token movement,
  lost keyup/root replacement, unrelated chords, and `detail <= 1`.

### 3. Peek state and ownership

- Add a model/version/position anchor and same-anchor toggle.
- Allow already-resolved multi-result actions to populate Peek without a
  duplicate provider request.
- Sort Peek display locations by URI/range and select the reference nearest the
  source position while preserving provider-first direct navigation.
- Stage replacement preview resources and atomically commit only current
  results, retaining the installed preview while a replacement resolves.
- Preserve focus across result movement and dispose nested Viewer/reference
  before the shell.
- Defer workbench preview-cache retirement until Viewer contribution teardown
  has synchronously released its leases.
- Add focused lifecycle, stale-result, focus, and browser behavior tests.

### 4. Contracts and validation

- Update the Viewer, language-registry, definition-core/browser, workbench, and
  Monaco-reference contracts so they describe the landed behavior rather than
  the former deviations.
- Review every changed `moon.pkg` edge and generated `pkg.generated.mbti`.
- Run focused MoonBit and browser tests, then the repository-required
  `moon info --target all`, formatting, check, test, build, and relevant
  browser suites. Record any environment limitation as a limitation, not a
  pass.

## Intentional exclusions

- `LocationLink.originSelectionRange` and `targetSelectionRange` require a
  broader public protocol change and remain deferred.
- Source-preview hover text on definition links remains deferred until the
  resolver/LocationLink boundary can represent it without leaking workspace
  policy into Viewer.
- Configurable `multiCursorModifier`, middle/side click, open-to-side,
  `definitionLinkOpensInPeek`, alternative commands, navigation history,
  stable Peek, editor-group migration, grouped-tree presentation, sash/layout
  persistence, and cross-editor Peek transfer remain N-A for this standalone
  readonly Viewer.
- The 350 ms `symbolHighlight` can be provided only for Viewer-local targets
  with the current opener contract. It is deferred rather than presenting
  inconsistent same-resource and cross-resource semantics.

## Completion rule

The work is complete only when each non-excluded row has focused evidence,
changed public interfaces and dependency edges have been reviewed, and this
plan is compressed into `docs/exec-plans/HISTORY.md` and removed from the
current tree.
