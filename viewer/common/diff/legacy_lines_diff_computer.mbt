// The `IChange` result contract from `vscode/src/vs/editor/common/diff/
// legacyLinesDiffComputer.ts` (checked-in vscode submodule). Only the contract is ported:
// the quick-diff contrib consumes changes in this shape (as VS Code's
// `quickDiffModel.ts` does after `toLineChanges`).
//
// Parity ledger (source members): `IChange` — PORTED (`Change`; the
// I-prefix is dropped tree-wide). `ICharChange`, `ILineChange`,
// `IDiffComputationResult`, `ILinesDiff`, the `LegacyLinesDiffComputer` /
// `DiffComputer` machinery and its helpers — N-A (the legacy Myers engine is
// superseded; the viewer's default computer is piediff-backed, see
// `default_lines_diff_computer.mbt`).

///|
/// A line-level change with the legacy 1-based inclusive encoding —
/// `IChange` (`legacyLinesDiffComputer.ts:102`). `original_end_line_number
/// == 0` encodes an insertion (nothing on the original side);
/// `modified_end_line_number == 0` encodes a deletion, with the respective
/// start line number naming the line *before* the gap.
pub(all) struct Change {
  original_start_line_number : Int
  original_end_line_number : Int
  modified_start_line_number : Int
  modified_end_line_number : Int
} derive(Eq, Debug)
