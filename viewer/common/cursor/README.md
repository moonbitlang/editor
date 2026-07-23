# viewer/common/cursor

Backend-neutral single-cursor state for the readonly viewer.

## Flow and API

- `SingleCursorState` holds an anchor range, `SelectionStartKind`, and active
  1-based UTF-16 position plus anchor/active leftover-visible-column residues;
  `selection`, `has_selection`, and `moved` derive the oriented
  `viewer/common/core.Selection` without losing Word/Line anchor shape.
- `CursorContext` stores only the three typed model/view conversion closures the
  cursor consumes; it does not retain a runtime converter trait object.
- `CursorState` retains a full model/view pair. `PartialCursorState` has exact
  full, model-only, and view-only shapes; the two partial constructors retain
  `None` on the absent side, and selection constructors build a collapsed
  `Simple` anchor in source order. `Cursor` consumes nullable model/view sides
  through one `set_state` entry: both absent is a no-op, model derives view,
  and view derives model while retaining the authoritative projected position.
- `CursorsController` owns the model, conversion context, one cursor, the known
  internal model version, validation, and the shared `set_cursor_state`
  transition snapshot used by API, pointer, keyboard, and content-flush
  callers. A changed transition returns `CursorStateChange?`; an exact paired-
  state/version no-op returns `None`. A content flush always resets to `(1,1)`
  with source `model`, reason `ContentFlush`, old version `0`, and no old
  selections.
- `viewer/common/editor_api.CursorChangeReason` is the canonical public reason;
  paired `CursorState` and `CursorStateChange` retain cursor-owned transition
  state consumed by `viewer/common/view_model`. Free
  `move_to`/`move_to_select` remain the low-level pointer command subset;
  source-shaped Left/Right/Up/Down/Page/Home/End and Word/Line continuation live
  in the view-model package where projected-line facts are available.

Upstream sources are `cursorCommon.ts`, `cursorContext.ts`, `oneCursor.ts`,
`cursor.ts`/`cursorCollection.ts`, and the selection part of `coreCommands.ts`.

## Deliberate reductions

There is one selection only. Editable marker recovery, edit-operation tracking,
multi-cursor limits, and simultaneous supplied model+view cross-validation are
deferred. Mapping changes reproject from the model side; live view-driven moves
are normalized by `viewer/common/view_model` before this package validates the
derived model side. The one-cursor `normalize` member therefore takes the
source's primary-only early return before allocating or sorting. Atomic
soft-tab movement, full grapheme-cluster stepping/visible-column arithmetic,
and visual RTL arrow swapping are outside this package's current cursor
contract; current horizontal stepping is surrogate-pair safe and otherwise
code-point based.

The package depends on `base/common`, `viewer/common/editor_api`,
`viewer/common/core`, and `viewer/common/model`; it has no view-model, DOM, or
FFI dependency. See
`pkg.generated.mbti` for the complete API and run
`moon test --target all viewer/common/cursor`.
