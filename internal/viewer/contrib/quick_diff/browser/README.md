# internal/viewer/contrib/quick_diff/browser

The JS-target quick-diff calculation and decoration implementation. It
converts detailed line mappings into model changes, computes line diffs, and
maps changes to editor decorations consumed by the root Viewer.

Service state and public-host adaptation remain in
`internal/viewer/contrib/quick_diff/common` and
`viewer/common/quick_diff_api`, respectively. The emitted stylesheet remains
at `viewer/contrib/quick_diff/browser/quick_diff.css`.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/quick_diff/browser --target js
```
