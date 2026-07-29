# internal/viewer/contrib/folding/browser

The JS-target folding implementation. It owns folding ranges and regions,
indent-based range computation, folding decorations, hidden-range projection,
selection adjustment, and the per-Viewer folding controller state.

The root Viewer integrates these values with model events and cursor
selection. The package must remain independent of the root `viewer`, browser
view/controller, and shell packages. Its emitted stylesheet remains at
`viewer/contrib/folding/browser/folding.css`.

The root may compose a host-computed range with
`OUTLINE_BODY_FOLDING_RANGE_TYPE` before an explicit outline action. The range
uses its complete declaration header's final line as the ordinary fold header,
so the standard hidden-range model needs no partial-line projection. Its
collapsed decoration keeps the chevron/highlight but omits `inline-folded`'s
trailing ellipsis. Provider and user folds retain the Monaco presentation.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/folding/browser --target js
```
