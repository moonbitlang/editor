# Execution Plans

This directory contains active plans only, plus the planning rules and a
compressed historical index.

Create a plan here for future work spanning packages or changing harness
behavior. It must let another engineer execute the work without rediscovery and
must be checked against the current source and package contracts.

For Monaco/VS Code or CodeMirror ports, follow `_PORT_PLAYBOOK.md`. Use its
behavior-port mode by default. Require source-shaped algorithm review only for
sensitive arithmetic, ordering, timing, or state machines; require a complete
source-unit ledger only when the user explicitly asks for a full audit.

When the user asks to execute a plan, review gates are internal validation
checkpoints, not user-approval pauses. Complete and record each review, then
continue through implementation and validation. Pause only if the user asks for
it or the review exposes a material unresolved choice that changes scope,
public API, or behavior.

After implementation:

1. Move landed ownership and behavior into `docs/architecture.md`, package
   READMEs, tests, generated interfaces, and harness docs.
2. Fold the completed plan and any Gate companions into `HISTORY.md`.
3. Delete the detailed files from the current tree; Git retains the full
   artifacts.

Delete superseded or abandoned incomplete plans once `HISTORY.md` records why
they are obsolete. Do not leave a stale proposed plan that no longer matches the
current package graph.
