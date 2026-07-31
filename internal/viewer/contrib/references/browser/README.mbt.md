# References Browser Contribution

This JS-only package owns the detached Peek Definition/References shell and its
feature-local accessible result tree. The root Viewer owns presentation mounts,
model-resolution leases, nested preview Viewers, decorations, opening policy,
and stale-result checks.

`ReferencesPeekWidget` consumes the immutable normalized values from the
DOM-free sibling package. Its typed callbacks carry `ReferenceItem` and
`ReferenceGroup` identities; callers never recover model identity from DOM
attributes.

One-resource models render reference rows directly. Multi-resource models
render file rows and level-two reference rows, initially expanding the selected
resource. Expansion requests each group at most once so the root can lazily
resolve source snippets. `set_group_previews` replaces only that group's
reference DOM while preserving expansion, selection, and the current focus
domain.

The result surface is a native ARIA tree with one roving `tabindex="0"` among
visible rows. Arrow, Home, End, Left, and Right keys move or expand the tree;
Enter confirms the current reference and Ctrl+Enter or Meta+Enter requests a
side open. Escape and F4/Shift+F4 remain available from both the tree and a
nested preview, while Enter inside the preview keeps its native editor meaning.

The package uses direct Rabbita DOM primitives and imports neither the shell nor
Rabbita's TEA framework. Product behavior is a focused port of the pinned VS
Code References Peek tree/controller clusters recorded in
`docs/exec-plans/peek-references-ui.md`.
