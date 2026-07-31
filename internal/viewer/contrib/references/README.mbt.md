# References Contribution Core

This multi-target, DOM-free package owns the immutable result and session
values shared by Peek Definition and the public precomputed-references entry.
The root Viewer owns provider requests, model-reference leases, nested Viewers,
decorations, presentation mounts, opening, and teardown. The browser sibling
owns the Peek shell and accessible result tree.

`ReferencesModel` copies caller locations, sorts by canonical
`Uri::to_string()` and full 1-based `Range`, removes exact duplicates, and
builds both URI groups and one flat navigation sequence. URI fragments remain
part of identity; no filesystem case policy enters the Viewer.

`nearest_reference` is pinned to VS Code's longest-common-URI-prefix rule,
followed by `abs(line delta) * 100 + abs(column delta)` and stable sorted order.
Next and previous navigation use the flat sequence and wrap across resource
groups.

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
