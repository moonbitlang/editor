# Definition Message Browser Widget

This JS-only package owns Definition's detached ARIA status node for
non-destructive action feedback such as “No definition found” or “Unable to
open definition”. The shared Definition and References Peek shell belongs to
the sibling References browser package.

For Code, `DefinitionMessageWidget` exposes Monaco's overflowing
content-widget contract, retains the exact request position, prefers above
then below with right affinity, and renders the matching arrow/message DOM.
The root Viewer chooses the presentation-specific mount, drives layout after
show/hide, and controls message visibility and lifetime.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/definition/browser --target js
```
