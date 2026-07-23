// Port of `vscode/src/vs/editor/common/diff/rangeMapping.ts` (vscode
// checked-in submodule): the mapping
// types a lines-diff result is expressed in.
//
// Parity ledger (source members):
// - `LineRangeMapping` original/modified/ctor/toString/flip/join/
//   changedLineCount/inverse — PORTED. `clip`, `toRangeMapping`,
//   `toRangeMapping2` — DEFERRED (consumers are the diff editor's inner-change
//   plumbing; `toRangeMapping*` additionally need `LineRange.toInclusiveRange`
//   / an `AbstractText`, neither of which exists yet).
// - `DetailedLineRangeMapping` — PORTED as a flat struct (MoonBit has no
//   class inheritance; it repeats `original`/`modified` beside
//   `inner_changes`). `toTextEdit`/`fromRangeMappings`/
//   `withInnerChangesFromLineRanges` — DEFERRED (need TextEdit /
//   `LineRange.fromRangeInclusive` / `toRangeMapping`).
// - `RangeMapping` originalRange/modifiedRange/ctor/toString/flip/join —
//   PORTED. Statics `fromEdit`/`fromEditJoin`/`toTextEdit` — DEFERRED (no
//   TextEdit type); `join(list)`/`assertSorted` — DEFERRED (no consumer).
// - `lineRangeMappingFromRangeMappings`/`getLineRangeMapping` — DEFERRED
//   (only the char-level refinement pipeline builds line mappings from range
//   mappings; the viewer's computer emits line mappings directly).
// - `lineRangeMappingFromChange` — DEFERRED (no consumer; the viewer converts
//   the other direction, see `to_line_changes` in the quick-diff contrib).

///|
/// Maps a line range in the original text model to a line range in the
/// modified text model — `LineRangeMapping` (`rangeMapping.ts:19`).
pub struct LineRangeMapping {
  /// The line range in the original text model.
  original : @base_common.LineRange
  /// The line range in the modified text model.
  modified : @base_common.LineRange
} derive(Eq, Debug)

///|
pub fn LineRangeMapping::LineRangeMapping(
  original_range : @base_common.LineRange,
  modified_range : @base_common.LineRange,
) -> LineRangeMapping {
  { original: original_range, modified: modified_range }
}

///|
/// `LineRangeMapping.inverse` (`rangeMapping.ts:20`): the unchanged regions
/// between the given (sorted) mappings.
pub fn LineRangeMapping::inverse(
  mapping : Array[LineRangeMapping],
  original_line_count : Int,
  modified_line_count : Int,
) -> Array[LineRangeMapping] {
  let result : Array[LineRangeMapping] = []
  let mut last_original_end_line_number = 1
  let mut last_modified_end_line_number = 1
  for m in mapping {
    let r = LineRangeMapping(
      LineRange(last_original_end_line_number, m.original.start_line_number),
      LineRange(last_modified_end_line_number, m.modified.start_line_number),
    )
    if !r.modified.is_empty() {
      result.push(r)
    }
    last_original_end_line_number = m.original.end_line_number_exclusive
    last_modified_end_line_number = m.modified.end_line_number_exclusive
  }
  let r = LineRangeMapping(
    LineRange(last_original_end_line_number, original_line_count + 1),
    LineRange(last_modified_end_line_number, modified_line_count + 1),
  )
  if !r.modified.is_empty() {
    result.push(r)
  }
  result
}

///|
pub fn LineRangeMapping::to_string(self : LineRangeMapping) -> String {
  "{" + self.original.to_string() + "->" + self.modified.to_string() + "}"
}

///|
pub impl Show for LineRangeMapping with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn LineRangeMapping::flip(self : LineRangeMapping) -> LineRangeMapping {
  LineRangeMapping(self.modified, self.original)
}

///|
pub fn LineRangeMapping::join(
  self : LineRangeMapping,
  other : LineRangeMapping,
) -> LineRangeMapping {
  LineRangeMapping(
    self.original.join(other.original),
    self.modified.join(other.modified),
  )
}

///|
pub fn LineRangeMapping::changed_line_count(self : LineRangeMapping) -> Int {
  self.original.length().max(self.modified.length())
}

///|
/// Maps a line range in the original text model to a line range in the
/// modified text model, together with the character-level inner range
/// mappings — `DetailedLineRangeMapping` (`rangeMapping.ts:196`). The source
/// class extends `LineRangeMapping`; MoonBit has no inheritance, so the
/// struct is flat and repeats the two line ranges.
pub struct DetailedLineRangeMapping {
  original : @base_common.LineRange
  modified : @base_common.LineRange
  /// If inner changes have not been computed, this is `None`. Otherwise it
  /// represents the character-level diff in this line range.
  inner_changes : Array[RangeMapping]?
} derive(Eq, Debug)

///|
pub fn DetailedLineRangeMapping::DetailedLineRangeMapping(
  original_range : @base_common.LineRange,
  modified_range : @base_common.LineRange,
  inner_changes : Array[RangeMapping]?,
) -> DetailedLineRangeMapping {
  { original: original_range, modified: modified_range, inner_changes }
}

///|
pub fn DetailedLineRangeMapping::to_string(
  self : DetailedLineRangeMapping,
) -> String {
  "{" + self.original.to_string() + "->" + self.modified.to_string() + "}"
}

///|
pub impl Show for DetailedLineRangeMapping with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn DetailedLineRangeMapping::flip(
  self : DetailedLineRangeMapping,
) -> DetailedLineRangeMapping {
  DetailedLineRangeMapping(
    self.modified,
    self.original,
    self.inner_changes.map(changes => changes.map(RangeMapping::flip)),
  )
}

///|
/// Maps a range in the original text model to a range in the modified text
/// model — `RangeMapping` (`rangeMapping.ts:243`).
pub struct RangeMapping {
  /// The original range.
  original_range : @base_common.Range
  /// The modified range.
  modified_range : @base_common.Range
} derive(Eq, Debug)

///|
pub fn RangeMapping::RangeMapping(
  original_range : @base_common.Range,
  modified_range : @base_common.Range,
) -> RangeMapping {
  { original_range, modified_range }
}

///|
pub fn RangeMapping::to_string(self : RangeMapping) -> String {
  "{" +
  self.original_range.to_string() +
  "->" +
  self.modified_range.to_string() +
  "}"
}

///|
pub impl Show for RangeMapping with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn RangeMapping::flip(self : RangeMapping) -> RangeMapping {
  RangeMapping(self.modified_range, self.original_range)
}
