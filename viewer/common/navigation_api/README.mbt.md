# Navigation host API

This multi-target, DOM-free package owns the minimal capabilities shared by
goto-definition and the Definition/References Peek controller. It imports only
common URI/range, language-location/cancellation, and caller-owned `TextModel`
contracts. It does not own a workspace, filesystem, network transport, model
registry, active document, tab, editor group, or navigation history.

`LocationOpenerHandle` lets a host accept or reject an
`OpenLocationRequest`. The request contains only the initiating public Viewer
id, a language `Location`, and the host-neutral `Current`/`Side` intent. The
Viewer reveals Current same-resource locations locally; Side and
cross-resource Current requests require host action. Host acceptance cannot be
revoked after dispatch. Definition stamps the request and suppresses late
rejection feedback after newer intent, model/version replacement, or Viewer
disposal; the precomputed References entry dispatches the same request shape
without creating Definition feedback.

`TextModelResolverHandle` is the injected dependency-inversion boundary for
cross-resource Peek content. The root resolves an expanded resource group
lazily for row snippets and resolves the selected target independently for its
nested preview. Each successful request owns its own
`TextModelReference` lease. The model remains caller-owned:
`TextModelReference::dispose` invokes its release callback at most once and
never disposes the model. Same-resource snippets and selected previews reuse
the current Viewer model without acquiring a lease.

The root validates source model identity, attachment generation, content
version, session/request generation, cancellation, returned-model disposal,
and exact URI before committing. Group leases remain until session close;
selected leases remain until preview replacement or close. Stale and wrong-URI
returns are released exactly once. A missing resolver or `None` result keeps
group rows on their location fallback and makes a selected cross-resource
preview unavailable.

Both handles borrow their captured backings. `ViewerServices` stores them
optionally and never creates or disposes a navigation backing.

See `pkg.generated.mbti` for exact signatures. Run
`moon test --target js viewer/common/navigation_api` for focused coverage.
