# Definition Peek Browser Shell

This JS-only package owns the DOM shell for Peek Definition. It renders the
loading and unavailable states, the definition result list, and the empty
preview host where the root `viewer` package mounts a nested readonly Viewer.
The package deliberately does not import or construct that Viewer.

`DefinitionPeekWidget` owns every DOM listener it installs. Replacing the
location list releases the old row listeners before removing those rows, and
`dispose` releases both row and persistent listeners exactly once. The caller
owns the Code ViewZone or Markdown overlay mount, the nested Viewer, and any
target-model reference; it must dispose and detach those resources before
disposing the shell.

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
open definition”. The root Viewer chooses its mounting mechanism and controls
message visibility.

Exact callable types are in `pkg.generated.mbti`. Run focused tests with:

```sh
moon test internal/viewer/contrib/definition/browser --target js
```
