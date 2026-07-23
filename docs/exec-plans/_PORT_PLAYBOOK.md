# Reference Port Playbook

Use this when Monaco/VS Code or CodeMirror supplies reference behavior for a
MoonBit implementation. The reference tree is a behavioral oracle, not a
required local representation. Preserve observable semantics and relevant
algorithmic invariants; choose MoonBit-native types, ownership, packages, and
dispatch unless representation is itself an explicit compatibility contract.

Reference maps: `docs/references/{monaco,codemirror}.md`. Reference trees are
read-only research inputs.

## Select the Port Mode

State the mode before building an inventory. One task may assign different
modes to different slices.

### Behavior port (default)

Scope inputs, outputs, events, DOM effects, ordering, lifecycle transitions,
errors, and supported options. Account for intentional exclusions. Do not
inventory every TypeScript field, interface member, helper, or private method;
include source only when it contributes to the selected behavior.

### Algorithm-fidelity port

Use when branch order, early returns, constants, arithmetic, batching, geometry,
layout, timing, offsets, or state-machine transitions materially determine
behavior. Inventory the complete algorithm cluster and preserve those
invariants. Cite at the function or branch-cluster level, not line by line.

The local API and representation may still differ when the same invariants are
explicit and testable.

### Full source audit (explicit only)

Use only when the user explicitly requests a complete source-unit or literal
1:1 audit. Do not infer it merely from "port", "parity", or "conform with
Monaco". Read the complete named unit and account for all behavior-bearing
members, branches, constants, DOM/CSS ownership, and lifecycle transitions.
Group TypeScript-only representation details in a compact appendix instead of
manufacturing individual MoonBit counterparts.

## Scope and Representation

Every port records:

- pinned source revision and relevant file/function/class ranges;
- local product boundary and current consumers;
- adopted behaviors and invariants;
- unsupported or intentionally excluded behavior;
- selected mode for each slice.

A coherent behavior or algorithm cluster may be smaller than a source file if
excluded sibling clusters are named. A bug symptom is evidence, not by itself
the scope denominator.

Record a short representation decision. Upstream interfaces and inheritance do
not automatically become MoonBit traits. Prefer:

- closed family: enum plus exhaustive dispatch;
- one implementation: concrete type and inherent methods;
- open registration/extension: handle or callback record;
- required data plus optional operations: record with optional callbacks;
- small boundary capability: typed closure or narrow access record;
- registration lifetime: disposable handle with explicit ownership;
- freshness/identity: stable typed identity or generation.

A trait requires a real local open-polymorphism consumer whose implementation
set is intentionally open. An upstream interface, inheritance relationship, or
test fake is not sufficient justification.

Representation differences are not behavioral deviations. Put them in the
representation decision; reserve `Behavioral Deviations` for observable or
algorithmic differences.

## Evidence

Use the smallest table that lets a reviewer connect a claim to its proof:

| Behavior or invariant | Source | MoonBit disposition | Evidence |
|---|---|---|---|

Each row links focused test/oracle evidence or ends in `DEFERRED (reason)` or
`N-A (reason)`. One test may cover multiple inseparable transitions. Do not
duplicate prose to create a one-row-to-one-test appearance.

Full-source-audit mode may add:

| Source member/cluster | Behavioral role | Local disposition | Evidence |
|---|---|---|---|

Keep implementation and proof separate: `implemented` is not evidence, while
`tested` alone does not say what was adopted.

Derive evidence from risk and branches:

- give each behavior-changing branch and boundary an input that takes it;
- cover meaningful variable interactions; exhaust the Cartesian product only
  when it is small or the interaction risk warrants it;
- prefer applicable upstream tests with their source labels and boundary values;
- use the lowest harness layer that observes the behavior;
- keep unsupported cases within the selected scope visible as skips/deferrals.

Repository checks are merge gates. Focused tests establish the claimed port
behavior.

## Review and Exit

Review scope, mode, representation, and planned evidence before implementation.
For an execution request this is an internal checkpoint: record the result and
continue unless an unresolved choice changes scope, public API, or behavior.

A port is complete when:

1. Selected behavior and invariants are accounted for.
2. Exclusions, deferrals, and unsupported scoped cases are explicit.
3. Representation has a local capability/lifetime justification.
4. Algorithm-fidelity slices were reread for ordering, constants, and branches.
5. Each behavior claim has focused evidence at the appropriate layer.
6. Relevant repository checks pass.

Only full-source-audit mode may claim the entire named source unit was audited.
Ordinary ports claim exactly the behavior they cover, not "1:1" completeness.

## Plan Template

```markdown
# <Behavior/Algorithm> Reference Port

Status: proposed
Date: <YYYY-MM-DD>
Oracle: <revision>

## Scope and Mode
- Source: <paths/ranges>
- Local boundary/consumers: <packages/call sites>
- Mode: behavior | algorithm-fidelity | full source audit
- Adopted behavior/invariants: <list>
- Out of scope: <list>

## Representation Decision
<Why this concrete type/enum/handle/callback record/trait fits MoonBit here.>

## Evidence Map
| Behavior or invariant | Source | MoonBit disposition | Evidence |
|---|---|---|---|

## Behavioral Deviations
<Observable or algorithmic differences only, or None.>

## Test Matrix
- Branches/boundaries: <list>
- Meaningful interactions: <list>
- Harness layers: <list>

## Exit Gate
- [ ] scope, mode, and source revision recorded
- [ ] representation decision reviewed
- [ ] behaviors/invariants accounted for
- [ ] deferrals, exclusions, and skips explicit
- [ ] focused evidence green
- [ ] relevant repository checks green
```

Completed plans under an older protocol may be compressed into `HISTORY.md`;
their full text remains in Git history. Do not rewrite old work solely to make
it resemble this playbook.
