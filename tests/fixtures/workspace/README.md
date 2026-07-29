# Fixture workspace

This Markdown document is opened through the native workspace protocol and
rendered by the reusable public Viewer.

- The host supplies the original URI-backed model.
- The Viewer chooses the readonly Markdown presentation.

## Flow

```d2
direction: right

open: open README.md
viewer: public Viewer routing
surface: readonly Markdown document

open -> viewer
viewer -> surface: one presentation root
```

```mermaid
flowchart LR
  A[Markdown file] --> B[Shared renderer]
  B --> C[Reading surface]
```

```moonbit
fn readme_snippet() -> Unit {
}
```

Closing prose keeps the document honest.
