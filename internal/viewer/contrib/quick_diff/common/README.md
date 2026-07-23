# internal/viewer/contrib/quick_diff/common

The DOM-free quick-diff implementation. It owns original-content state,
change notifications, the internal service handle, and change-kind
classification used by the root Viewer and browser scenarios.

Public host DTOs and callbacks remain in `viewer/common/quick_diff_api`. The
browser diff/decorations implementation lives in
`internal/viewer/contrib/quick_diff/browser`.

Exact callable types are in `pkg.generated.mbti`. Run the focused suite on
both supported targets with:

```sh
moon test internal/viewer/contrib/quick_diff/common --target js
moon test internal/viewer/contrib/quick_diff/common --target native
```
