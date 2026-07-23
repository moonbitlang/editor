// The diff-computation half of `vscode/src/vs/workbench/contrib/scm/browser/
// quickDiffModel.ts` (checked-in vscode submodule), reduced to a pure function: the
// viewer's text models are immutable and the service stores one original per
// resource, so the source's reference-counted per-resource model (throttled
// recompute, provider merge, `compareChanges` sort) collapses to
// `compute_changes` — the `_diff` method's pipeline (`quickDiffModel.ts:348`:
// `editorWorkerService.computeDiff` → `toLineChanges(DiffState.
// fromDiffResult(result))`) over the piediff-backed default computer.
//
// Parity ledger: `QuickDiffModel._diff` + the `toLineChanges` conversion it
// applies (`diffEditorWidget.ts:759`) — PORTED (`charChanges` — DEFERRED,
// the computer produces no inner changes). Everything else in
// `quickDiffModel.ts` (service/reference plumbing, editor-model sync,
// multi-provider merge) — N-A under the single-provider reduction (see
// `../common/quick_diff.mbt`).

///|
/// `toLineChanges` (`diffEditorWidget.ts:759`) without `charChanges`:
/// re-encodes exclusive line-range mappings in the legacy 1-based inclusive
/// `Change` shape, `0` marking the empty side.
pub fn to_line_changes(
  changes : Array[@diff.DetailedLineRangeMapping],
) -> Array[@diff.Change] {
  changes.map(m => {
    let (original_start_line_number, original_end_line_number) = if m.original.is_empty() {
      // Insertion
      (m.original.start_line_number - 1, 0)
    } else {
      (m.original.start_line_number, m.original.end_line_number_exclusive - 1)
    }
    let (modified_start_line_number, modified_end_line_number) = if m.modified.is_empty() {
      // Deletion
      (m.modified.start_line_number - 1, 0)
    } else {
      (m.modified.start_line_number, m.modified.end_line_number_exclusive - 1)
    }
    {
      original_start_line_number,
      original_end_line_number,
      modified_start_line_number,
      modified_end_line_number,
    }
  })
}

///|
/// `QuickDiffModel._diff` (`quickDiffModel.ts:348`) reduced: computes the
/// line-level changes between the original document and the modified one.
/// Defaults mirror the source's effective configuration: a 1000ms budget
/// (`quickDiffModel.ts:43`) and `scm.diffDecorationsIgnoreTrimWhitespace`'s
/// `'false'` default (`scm.contribution.ts:239`).
pub fn compute_changes(
  original_lines : Array[String],
  modified_lines : Array[String],
  ignore_trim_whitespace? : Bool = false,
  max_computation_time_ms? : Int = 1000,
) -> Array[@diff.Change] {
  let result = @diff.get_default().compute_diff(
    original_lines,
    modified_lines,
    { ignore_trim_whitespace, max_computation_time_ms, compute_moves: false },
  )
  to_line_changes(result.changes)
}
