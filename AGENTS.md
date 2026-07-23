# Agent Notes

## Start Here

- Architecture and dependency rules: `docs/architecture.md`
- Package contracts: the owning package's `README.md` and
  `pkg.generated.mbti`
- Commands and test-layer selection: `docs/harness.md`
- Required checks and conformance-test rules: `docs/quality.md`
- Style: `docs/styles.md`
- Active cross-package plans and compressed history:
  `docs/exec-plans/{README,HISTORY}.md`
- Monaco/CodeMirror source maps: `docs/references/{monaco,codemirror}.md`

Completed execution plans are compressed history, not current contracts.

## Architecture Changes

Follow `docs/architecture.md` and review dependency changes in `moon.pkg`.
Review public API changes through the owning `pkg.generated.mbti`. Do not add
architecture-lint scripts for one-time design decisions; automate only a
repeated concrete failure mode, and keep the check generic rather than naming
current methods or implementation types.

## Reference Ports

Follow `docs/exec-plans/_PORT_PLAYBOOK.md` for Monaco/VS Code or CodeMirror
ports. Monaco is the behavioral oracle, not a required MoonBit representation.
The non-negotiables are:

1. Choose and state the port mode: behavior port by default, algorithm-fidelity
   port for sensitive arithmetic/state machines, or full source audit only when
   explicitly requested.
2. Account for observable behavior, boundary cases, algorithmic invariants, and
   intentional exclusions. Do not create one ledger row per TypeScript member
   unless the selected full-audit mode needs it.
3. Preserve exact control flow and constants only where they affect the selected
   algorithm-fidelity contract. Otherwise prefer MoonBit-native concrete types,
   enums, handles, callback records, and ownership.
4. Link each claimed behavior to focused evidence or mark it `DEFERRED (reason)`
   / `N-A (reason)`. Green repository checks alone do not prove parity.

## Execution Plan Continuation

When the user asks to execute a checked-in plan, carry it through inventory,
review, implementation, validation, and milestone commits without pausing for
user approval. `Gate A`, `review gate`, and `STOP FOR REVIEW` are internal
quality checkpoints: produce the required artifact, review it against the plan
and current source, record the result, and continue.

Pause only when the user explicitly requests a review stop or when the gate
reveals a material choice that the plan and current repository evidence cannot
resolve without changing scope, public API, or behavior.

## Version Control

- Commit each coherent, validated milestone without waiting to be asked.
- Do not rewrite, squash, amend, reset, or revert history without approval.
