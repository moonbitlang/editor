# internal/viewer/contrib/agent_feedback

The DOM-free agent-feedback implementation. It owns the mutable feedback
service, editor-comment projection, deterministic sorting/grouping, navigation,
reply, acceptance, and submission state used by the root Viewer and workbench.

Public host DTOs and callback handles remain in
`viewer/common/agent_feedback_api`; this package is an internal implementation
owner and must not become a dependency of embedded clients. Browser widgets
live in `internal/viewer/contrib/agent_feedback/browser`.

Exact callable types are in `pkg.generated.mbti`. Run the focused suite on
both supported targets with:

```sh
moon test internal/viewer/contrib/agent_feedback --target js
moon test internal/viewer/contrib/agent_feedback --target native
```
