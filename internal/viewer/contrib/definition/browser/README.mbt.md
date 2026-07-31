# Definition Peek Browser Shell

This JS-only package owns the DOM shell for Peek Definition. It renders the
loading and unavailable states, the definition result list, and the empty
preview host where the root `viewer` package mounts a nested readonly Viewer.
The package deliberately does not import or construct that Viewer.

The shell follows the selected Monaco Peek presentation contract: an
18-line requested height, filename/directory/result-count title, preview on the
left, results on the right, and a selected-target match decoration supplied by
the root Viewer. Code mounts the shell as an overlay aligned to a separate
blank ViewZone spacer; passing the interactive shell itself to ViewZones would
overwrite its flex layout with ViewZone's absolute block styles. Semantic
Markdown mounts the same shell in its projection overlay.

`DefinitionPeekWidget` owns every DOM listener it installs. Replacing the
location list releases the old row listeners before removing those rows, and
`dispose` releases both row and persistent listeners exactly once. The caller
owns the Code ViewZone spacer and overlay registration or Markdown overlay
mount, the nested Viewer, and any target-model reference; it must dispose and
detach those resources before disposing the shell.

Keyboard events from the result list or nested preview stop at the shell.
Escape closes, F4 selects the next result, and Shift+F4 selects the previous
result from either focus domain. Enter confirms the selected result only while
the shell root or result list owns focus; Enter from the nested preview retains
its native meaning and does not confirm. The host callback remains responsible
for applying a requested selection with `set_selected_index`.
Per-result `show_preview_loading` and `show_preview_unavailable` transitions
preserve the list and selected index, allowing a failed cross-file resolution
to switch to another result; `show_preview_ready` clears that status after the
nested Viewer mounts.

`DefinitionMessageWidget` is a separate detached ARIA status node for
non-destructive action feedback such as “No definition found” or “Unable to
open definition”. For Code it exposes Monaco's overflowing content-widget
contract, retains the exact request position, prefers above then below with
right affinity, and renders the matching arrow/message DOM. The root Viewer
chooses the presentation-specific mount, drives layout after show/hide, and
controls message visibility.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/definition/browser --target js
```
