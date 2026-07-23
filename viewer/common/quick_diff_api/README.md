# Quick-diff host API

This multi-target package owns the opaque baseline-content capability accepted
by `ViewerServices`. `QuickDiffHandle(...)` requires exactly a resource lookup
and a change subscription. The handle borrows its captured backing and has no
disposal authority.

Concrete baseline state and diff adapters remain under
`internal/viewer/contrib/quick_diff/**`. Keeping the callback contract here
lets an external host supply quick diff through an allowed
`viewer/common/**` import without exposing contribution implementation types
through the root facade.

See `pkg.generated.mbti` for the exact signatures. Run
`moon test --target js viewer/common/quick_diff_api` for focused coverage.
