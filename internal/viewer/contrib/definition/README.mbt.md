# Definition Contribution Core

This DOM-free package owns definition-result normalization and the request and
gesture state used by the root Viewer contribution. Browser DOM, Viewer
composition, model opening, and target-model resolution stay in their owning
packages.

The overall implementation is a Monaco behavior port. The Ctrl/Command link
gesture and Peek cancellation/lifetime transitions use algorithm-fidelity
ports because their ordering is observable. `DefinitionTargetFingerprint`
captures model identity, attachment generation, content version, position, and
word range; `DefinitionLinkState` records resolving, armed, and pressed
transitions plus a gesture-scoped resolved-empty cache without owning browser
resources. `DefinitionPeekPhase` records definition and preview generations
while root `viewer` owns and tears down their cancellation sources,
decorations, ViewZone, nested Viewer, scheduled layout, and optional
model-reference lease.

Provider order is stable. Normalization removes only exact URI/range
duplicates, so ordinary goto and confirmed Peek select the first surviving
result without imposing workspace policy.

The JS-only browser sibling supplies the Peek/result-list and message widget
shells. Host-neutral opening and target-model resolution live in
`viewer/common/navigation_api`; no shell, filesystem, network, tab, or editor
group type crosses either boundary.
