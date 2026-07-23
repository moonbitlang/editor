// Port of `vscode/src/vs/editor/common/diff/linesDiffComputer.ts` (vscode
// checked-in submodule): the computer
// options and result shape. The sole local engine is exposed concretely from
// `default_lines_diff_computer.mbt` instead of retaining the source interface
// as an unused runtime abstraction.
//
// Parity ledger (source members):
// - `ILinesDiffComputer.computeDiff` — PORTED as
//   `DefaultLinesDiffComputer::compute_diff`.
// - `ILinesDiffComputerOptions` — PORTED; `extendToSubwords?` — DEFERRED
//   (consumed only by the char-level refinement, which is not ported).
// - `LinesDiff` changes/moves/hitTimeout — PORTED.
// - `MovedText` lineRangeMapping/changes/flip — PORTED (the viewer's
//   computer never emits moves yet, see `default_lines_diff_computer.mbt`).

///|
/// `ILinesDiffComputerOptions` (`linesDiffComputer.ts:12`).
pub(all) struct LinesDiffComputerOptions {
  ignore_trim_whitespace : Bool
  /// `0` disables the computation budget entirely (Monaco's
  /// `InfiniteTimeout`).
  max_computation_time_ms : Int
  compute_moves : Bool
} derive(Eq, Debug)

///|
/// `LinesDiff` (`linesDiffComputer.ts:19`).
pub struct LinesDiff {
  changes : Array[DetailedLineRangeMapping]
  /// Sorted by original line ranges. The original line ranges and the
  /// modified line ranges must be disjoint (but can be touching).
  moves : Array[MovedText]
  /// Indicates if the time out was reached. In that case, the diffs might be
  /// an approximation and the user should be asked to rerun the diff with
  /// more time.
  hit_timeout : Bool
} derive(Eq, Debug)

///|
/// `MovedText` (`linesDiffComputer.ts:38`).
pub struct MovedText {
  line_range_mapping : LineRangeMapping
  /// The diff from the original text to the moved text. Must be contained in
  /// the original/modified line range. Can be empty if the text didn't
  /// change (only moved).
  changes : Array[DetailedLineRangeMapping]
} derive(Eq, Debug)

///|
pub fn MovedText::MovedText(
  line_range_mapping : LineRangeMapping,
  changes : Array[DetailedLineRangeMapping],
) -> MovedText {
  { line_range_mapping, changes }
}

///|
pub fn MovedText::flip(self : MovedText) -> MovedText {
  MovedText(
    self.line_range_mapping.flip(),
    self.changes.map(DetailedLineRangeMapping::flip),
  )
}
