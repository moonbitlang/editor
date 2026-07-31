# Definition Contribution Core

This DOM-free package owns definition-result normalization and the request and
gesture state used by the root Viewer contribution. Browser DOM, Viewer
composition, model opening, and target-model resolution stay in their owning
packages.

The overall implementation is a Monaco behavior port. The Ctrl/Command link
gesture and Peek cancellation/lifetime transitions use algorithm-fidelity
ports because their ordering is observable. `DefinitionTargetFingerprint`
captures model identity, attachment generation, content version, position, and
word range; same-word positions share preview work while mouse execution tracks
the pressed line independently. `DefinitionLinkState` records resolving and
armed transitions plus a gesture-scoped resolved-empty cache without owning
browser resources. The shared References contribution records Peek session and
preview generations plus the immutable grouped result model. Root `viewer`
owns and tears down the Definition provider source, Code decorations or
projected Markdown link spans, shared Code ViewZone or Markdown overlay, lazy
group and selected-preview cancellation/reference slots, nested Viewer,
preview decorations, and scheduled layout.

Provider order follows Monaco registry priority: selector score descending,
then newest registration first. Normalization removes only exact URI/range
duplicates. Ordinary goto opens one surviving result directly, delegates
multiple results to Peek when the outer Viewer can host it, and retains the
first result only as the deterministic headless/nested fallback. Peek display
sorting does not change provider-first direct-navigation policy.

The JS-only browser sibling supplies the Definition message widget; the shared
References browser package owns the Peek shell and result tree. Host-neutral
opening and target-model resolution live in `viewer/common/navigation_api`; no
shell, filesystem, network, tab, or editor group type crosses either boundary.
Definition's provider queries, zero-result text, and rejected-open feedback
remain here/root-owned and are not generalized into the precomputed References
entry.
