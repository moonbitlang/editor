# Navigation host API

This multi-target, DOM-free package owns the minimal capabilities shared by
goto-definition and Peek Definition. It imports only common URI/range,
language-location/cancellation, and caller-owned `TextModel` contracts. It does
not own a workspace, filesystem, network transport, model registry, active
document, tab, editor group, or navigation history.

`LocationOpenerHandle` lets a host accept or reject an
`OpenLocationRequest`. The request contains only the initiating public Viewer
id, a language `Location`, and the host-neutral `Current`/`Side` intent. The
Viewer reveals same-resource locations locally; the opener is for locations
that require host action.

`TextModelResolverHandle` is an injected dependency-inversion boundary for
cross-resource Peek previews. The host decides where a model comes from and
returns a `TextModelReference` lease when preview is possible. The model remains
caller-owned: `TextModelReference::dispose` invokes its release callback at
most once and never disposes the model. Same-resource Peek reuses the current
Viewer model without resolving a reference. A missing resolver or `None`
result means that no cross-resource preview is available.

Both handles borrow their captured backings. `ViewerServices` stores them
optionally and never creates or disposes a navigation backing.

See `pkg.generated.mbti` for exact signatures. Run
`moon test --target js viewer/common/navigation_api` for focused coverage.
