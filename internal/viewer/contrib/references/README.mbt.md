# References Contribution Core

This multi-target, DOM-free package owns the immutable result and session
values shared by Peek Definition and the public precomputed-references entry.
The root Viewer owns Definition provider requests, model-reference leases,
nested Viewers, decorations, presentation mounts, opening, and teardown. The
browser sibling owns the Peek shell and accessible result tree.

The public entry itself remains in the root facade:

```mbt nocheck
viewer.show_references(anchor, locations)
```

It consumes already-computed locations. This package does not register or call
a References provider and does not own declaration-inclusion policy.

`ReferencesModel` copies caller locations, sorts by canonical
`Uri::to_string()` and full 1-based `Range`, removes exact duplicates, and
builds both URI groups and one flat navigation sequence. URI fragments remain
part of identity; no filesystem case policy enters the Viewer.

`nearest_reference` is pinned to VS Code's longest-common-URI-prefix rule,
followed by `abs(line delta) * 100 + abs(column delta)` and stable sorted order.
Next and previous navigation use the flat sequence and wrap across resource
groups.

`ReferencesSessionKey` captures the exact source model identity, attachment
generation, content version, and validated anchor used for freshness and
same-session toggle decisions. `ReferencesPeekMode` labels the shared shell as
Definitions or References; phases describe controller lifecycle without owning
any browser or cancellation resource.

`reference_snippet` reads only through `TextModel` range operations. It begins
the prefix at the word containing the position eight UTF-16 columns before the
match, keeps the exact matched source as a separate string, extends the suffix
to the end of the match's final line, trims outer row whitespace, and replaces
embedded line breaks with display spaces. Invalid or empty ranges are not
clamped; `ReferenceItem::row_preview` retains the one-based
`basename:line:column` fallback.

The selected algorithms are traceable to the checked-in VS Code revision
`b18492a288de038fbc7643aae6de8247029d11bd`, primarily
`referencesModel.ts:66-145,147-297`. Local URI identity, snippet strings, line
break normalization, and invalid-range rejection are documented representation
choices.

The root Viewer registers the provider-backed `Peek References` action,
Shift+F12, and context-menu placement. This package's session phase identifies
Definition versus References query loading, while the root controller owns the
query cancellation source and freshness stamp. Provider registration and
aggregation remain in `viewer/common/languages`; native and remote adapters
remain host responsibilities.

Go to References, CodeLens, document highlights, the Workbench References View,
filtering, virtualization, history, and copy actions are outside this package.

Exact callable types are in `pkg.generated.mbti`. Focused coverage is:

```sh
moon test internal/viewer/contrib/references --target js
moon test internal/viewer/contrib/references --target native
```
