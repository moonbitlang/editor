# internal/viewer/contrib/folding/browser

The JS-target folding implementation. It owns folding ranges and regions,
indent-based range computation, folding decorations, hidden-range projection,
selection adjustment, and the per-Viewer folding controller state.

The root Viewer integrates these values with model events and cursor
selection. The package must remain independent of the root `viewer`, browser
view/controller, and shell packages. Its emitted stylesheet remains at
`viewer/contrib/folding/browser/folding.css`.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/folding/browser --target js
```
