# Agent-feedback host API

This multi-target package owns the feedback DTOs, event values, and opaque
callback handle that may cross the public Viewer service boundary. It imports
only `base/common`; concrete storage, mutation policy, persistence, and browser
widgets remain in `internal/viewer/contrib/agent_feedback` and its browser
package.

`AgentFeedbackHandle(...)` requires the complete reviewed twelve-callback floor.
The handle forwards those operations without owning captured state or
lifecycle. External hosts can therefore inject a custom implementation through
`ViewerServices` without importing a contribution package, while the reference
workbench derives the same handle from its retained concrete service.

See `pkg.generated.mbti` for the exact value and callback contracts. Run
`moon test --target js viewer/common/agent_feedback_api` for focused coverage.
