// The viewer's `DefaultLinesDiffComputer` — the API of
// `vscode/src/vs/editor/common/diff/defaultLinesDiffComputer/
// defaultLinesDiffComputer.ts` (checked-in vscode submodule) over a different engine.
//
// DEVIATION (by decision, 2026-07-09): the computation is delegated to the
// `moonbit-community/piediff` library (a GNU-diffutils-style bidirectional
// Myers) instead of porting Monaco's Myers + refinement pipeline. Only the
// source method contract, the result types, and the two trivial-input branches
// are 1:1;
// everything the source computes beyond a minimal line-level edit script is
// not produced:
// - char-level inner changes (`refineDiff`, `optimizeSequenceDiffs`,
//   `extendDiffsToEntireWordIfAppropriate`, `removeShortMatches`,
//   `removeVeryShortMatching*`) — `inner_changes` is always `None`;
// - move detection (`computeMovedLines`) — `moves` is always empty and
//   `options.compute_moves` is ignored;
// - the timeout protocol — piediff's `cutoff` bounds the search *depth*, not
//   wall-clock time, and degrades silently to a correct-but-suboptimal
//   script, so `hit_timeout` is always `false`.
//   `options.max_computation_time_ms == 0` (Monaco's `InfiniteTimeout`) maps
//   to an effectively-unbounded cutoff; any other value keeps piediff's
//   default `~sqrt(n+m)` heuristic.
// Line-range boundaries may therefore differ from Monaco's output by
// tie-breaking among equal adjacent lines; tests assert diff *validity*
// (round-trip, ordering) and hand-checked fixtures, not byte parity.
//
// Parity ledger (source members): `computeDiff` trivial-equal branch (:28)
// and one-side-empty-document branch (:33) — PORTED; the remainder of
// `computeDiff` plus `refineDiff` and the assertion harness — N-A (replaced
// by the piediff engine per the deviation above).

///|
/// `DefaultLinesDiffComputer` (`defaultLinesDiffComputer.ts:26`), engine
/// swapped for piediff (see the file header).
pub struct DefaultLinesDiffComputer {} derive(Eq, Debug)

///|
#warnings("-unnecessary_annotation")
#alias(new)
pub fn DefaultLinesDiffComputer::DefaultLinesDiffComputer() -> DefaultLinesDiffComputer {
  // The qualifier is required because a bare `{}` is parsed as a `Map`.
  DefaultLinesDiffComputer::{  }
}

///|
pub fn DefaultLinesDiffComputer::compute_diff(
  self : DefaultLinesDiffComputer,
  original_lines : Array[String],
  modified_lines : Array[String],
  options : LinesDiffComputerOptions,
) -> LinesDiff {
  ignore(self)
  // `defaultLinesDiffComputer.ts:28`: a trivially-equal (empty or one-line)
  // input diffs to nothing.
  if original_lines.length() <= 1 && original_lines == modified_lines {
    return { changes: [], moves: [], hit_timeout: false }
  }

  // `defaultLinesDiffComputer.ts:33`: one side being the empty document maps
  // to a single whole-document change.
  if (original_lines.length() == 1 && original_lines[0].length() == 0) ||
    (modified_lines.length() == 1 && modified_lines[0].length() == 0) {
    return {
      changes: [
        DetailedLineRangeMapping(
          LineRange(1, original_lines.length() + 1),
          LineRange(1, modified_lines.length() + 1),
          Some([
            RangeMapping(
              Range(
                1,
                1,
                original_lines.length(),
                original_lines[original_lines.length() - 1].length() + 1,
              ),
              Range(
                1,
                1,
                modified_lines.length(),
                modified_lines[modified_lines.length() - 1].length() + 1,
              ),
            ),
          ]),
        ),
      ],
      moves: [],
      hit_timeout: false,
    }
  }

  // Engine: piediff over the (optionally trimmed) line arrays. Trimming
  // before hashing is how the source's `ignoreTrimWhitespace` line equality
  // behaves at line granularity (`defaultLinesDiffComputer.ts:60`).
  let old_input = if options.ignore_trim_whitespace {
    original_lines.map(l => l.trim().to_owned())
  } else {
    original_lines
  }
  let new_input = if options.ignore_trim_whitespace {
    modified_lines.map(l => l.trim().to_owned())
  } else {
    modified_lines
  }
  let cutoff : Int? = if options.max_computation_time_ms == 0 {
    Some(0x7FFFFFFF)
  } else {
    None
  }
  let d = @piediff.Diff::Diff(old=old_input[:], new=new_input[:], cutoff?)

  // Convert the flat edit script into hunks: each maximal run of
  // consecutive `Delete`/`Insert` edits (separated by `Equal` runs) is one
  // `DetailedLineRangeMapping`. piediff emits at most one `Delete` followed
  // by at most one `Insert` per hunk, but the converter tolerates any run.
  let edits = d.edits
  let changes : Array[DetailedLineRangeMapping] = []
  let mut i = 0
  while i < edits.length() {
    match edits[i] {
      Equal(..) => i += 1
      _ => {
        let mut old_start = 0x7FFFFFFF // 0-based, inclusive
        let mut old_end = -1 // 0-based, exclusive
        let mut new_start = 0x7FFFFFFF
        let mut new_end = -1
        // Where the hunk sits on the side that has no edits: an insert
        // carries the original position it lands after (`old_index`), a
        // delete carries the modified position the gap follows
        // (`new_index`).
        let mut anchor_old = 0
        let mut anchor_new = 0
        while i < edits.length() {
          match edits[i] {
            Equal(..) => break
            Delete(old_index~, new_index~, len~) => {
              old_start = old_start.min(old_index)
              old_end = old_end.max(old_index + len)
              anchor_new = new_index
            }
            Insert(old_index~, new_index~, len~) => {
              new_start = new_start.min(new_index)
              new_end = new_end.max(new_index + len)
              anchor_old = old_index
            }
          }
          i += 1
        }
        let original = if old_end >= 0 {
          @base_common.LineRange(old_start + 1, old_end + 1)
        } else {
          LineRange(anchor_old + 1, anchor_old + 1)
        }
        let modified = if new_end >= 0 {
          @base_common.LineRange(new_start + 1, new_end + 1)
        } else {
          LineRange(anchor_new + 1, anchor_new + 1)
        }
        changes.push(DetailedLineRangeMapping(original, modified, None))
      }
    }
  }
  { changes, moves: [], hit_timeout: false }
}
