///|
/// A position in the editor, a 1:1 port of Monaco/VS Code's `Position`
/// (`vs/editor/common/core/position.ts`). One-based on both axes:
/// `line_number` starts at 1 and `column` starts at 1 (the first character on a
/// line sits between column 1 and column 2). Field names use the repo's
/// snake_case convention (`line_number`), matching `Range::start_line_number`.
pub(all) struct Position {
  line_number : Int
  column : Int
} derive(Eq, Debug)

///|
/// A range of offsets (0-based), half-open `[start, end_exclusive)`. A 1:1 port
/// of Monaco's `OffsetRange` (`core/ranges/offsetRange.ts`); field names use the
/// repo's snake_case (`end_exclusive`). The name `Range` is reserved for
/// Monaco's line/column range (see `monaco_range.mbt`).
pub struct OffsetRange {
  start : Int
  end_exclusive : Int
} derive(Eq, Debug)

///|
/// Builds a position without normalization; callers decide the coordinate
/// space before conversion through a snapshot.
pub fn Position::Position(line_number : Int, column : Int) -> Position {
  { line_number, column }
}

///|
/// A new position derived from this one. `None` for either axis keeps this
/// position's value, mirroring Monaco's `with(newLineNumber, newColumn)`
/// defaults. (`with_` because `with` clashes with MoonBit's struct-update and
/// trait-impl syntax.)
pub fn Position::with_(
  self : Position,
  line_number? : Int,
  column? : Int,
) -> Position {
  let new_line_number = line_number.unwrap_or(self.line_number)
  let new_column = column.unwrap_or(self.column)
  if new_line_number == self.line_number && new_column == self.column {
    self
  } else {
    Position(new_line_number, new_column)
  }
}

///|
/// Derive a new position by shifting it, clamping both axes to at least 1.
/// Mirrors Monaco's `delta(deltaLineNumber, deltaColumn)`.
pub fn Position::delta(
  self : Position,
  delta_line_number? : Int = 0,
  delta_column? : Int = 0,
) -> Position {
  self.with_(
    line_number=clamp_int(self.line_number + delta_line_number, 1, 2147483647),
    column=clamp_int(self.column + delta_column, 1, 2147483647),
  )
}

///|
/// Whether this position equals `other`. Mirrors Monaco's `Position.equals`.
pub fn Position::equals(self : Position, other : Position) -> Bool {
  self.line_number == other.line_number && self.column == other.column
}

///|
/// Whether this position is strictly before `other` (equal positions return
/// false). Mirrors Monaco's `Position.isBefore`.
pub fn Position::is_before(self : Position, other : Position) -> Bool {
  if self.line_number < other.line_number {
    return true
  }
  if other.line_number < self.line_number {
    return false
  }
  self.column < other.column
}

///|
/// Whether this position is before or equal to `other`. Mirrors Monaco's
/// `Position.isBeforeOrEqual`.
pub fn Position::is_before_or_equal(self : Position, other : Position) -> Bool {
  if self.line_number < other.line_number {
    return true
  }
  if other.line_number < self.line_number {
    return false
  }
  self.column <= other.column
}

///|
/// Compares two positions for sorting (line, then column). Mirrors Monaco's
/// static `Position.compare`.
pub fn Position::compare(a : Position, b : Position) -> Int {
  if a.line_number == b.line_number {
    return a.column - b.column
  }
  a.line_number - b.line_number
}

///|
/// A copy of this position. Mirrors Monaco's `Position.clone` (a value copy
/// here, since `Position` is a value type).
pub fn Position::clone(self : Position) -> Position {
  Position(self.line_number, self.column)
}

///|
/// Human-readable `(line,column)` form. Mirrors Monaco's `Position.toString`.
pub fn Position::to_string(self : Position) -> String {
  "(\{self.line_number},\{self.column})"
}

///|
/// Builds a half-open offset range. Monaco's constructor throws a
/// `BugIndicatingError` when `start > end_exclusive`; the readonly viewer avoids
/// panics, so this normalizes by swapping instead. For valid inputs
/// (`start <= end_exclusive`) the swap is a no-op, so every other method keeps
/// Monaco's behavior.
pub fn OffsetRange::OffsetRange(
  start : Int,
  end_exclusive : Int,
) -> OffsetRange {
  if start <= end_exclusive {
    { start, end_exclusive }
  } else {
    { start: end_exclusive, end_exclusive: start }
  }
}

///|
/// `[start, end_exclusive)`. Mirrors Monaco's static `OffsetRange.fromTo`.
pub fn OffsetRange::from_to(start : Int, end_exclusive : Int) -> OffsetRange {
  OffsetRange(start, end_exclusive)
}

///|
/// `[0, length)`. Mirrors Monaco's static `OffsetRange.ofLength`.
pub fn OffsetRange::of_length(length : Int) -> OffsetRange {
  OffsetRange(0, length)
}

///|
/// `[start, start + length)`. Mirrors Monaco's `OffsetRange.ofStartAndLength`.
pub fn OffsetRange::of_start_and_length(
  start : Int,
  length : Int,
) -> OffsetRange {
  OffsetRange(start, start + length)
}

///|
/// The empty range `[offset, offset)`. Mirrors Monaco's `OffsetRange.emptyAt`.
pub fn OffsetRange::empty_at(offset : Int) -> OffsetRange {
  OffsetRange(offset, offset)
}

///|
/// `[start, end_exclusive)`, or `None` when `start > end_exclusive`. Mirrors
/// Monaco's static `OffsetRange.tryCreate`.
pub fn OffsetRange::try_create(
  start : Int,
  end_exclusive : Int,
) -> OffsetRange? {
  if start > end_exclusive {
    None
  } else {
    Some({ start, end_exclusive })
  }
}

///|
/// Whether the range contains no offsets. Mirrors Monaco's `isEmpty` getter.
pub fn OffsetRange::is_empty(self : OffsetRange) -> Bool {
  self.start == self.end_exclusive
}

///|
/// The number of offsets in the range. Mirrors Monaco's `length` getter.
pub fn OffsetRange::length(self : OffsetRange) -> Int {
  self.end_exclusive - self.start
}

///|
/// Shifts both endpoints by `offset`. Mirrors Monaco's `delta`.
pub fn OffsetRange::delta(self : OffsetRange, offset : Int) -> OffsetRange {
  OffsetRange(self.start + offset, self.end_exclusive + offset)
}

///|
/// Shifts the start by `offset`. Mirrors Monaco's `deltaStart`.
pub fn OffsetRange::delta_start(
  self : OffsetRange,
  offset : Int,
) -> OffsetRange {
  OffsetRange(self.start + offset, self.end_exclusive)
}

///|
/// Shifts the end by `offset`. Mirrors Monaco's `deltaEnd`.
pub fn OffsetRange::delta_end(self : OffsetRange, offset : Int) -> OffsetRange {
  OffsetRange(self.start, self.end_exclusive + offset)
}

///|
/// Whether this range equals `other`. Mirrors Monaco's `equals`.
pub fn OffsetRange::equals(self : OffsetRange, other : OffsetRange) -> Bool {
  self.start == other.start && self.end_exclusive == other.end_exclusive
}

///|
/// Whether `other` is fully contained in this range. Mirrors `containsRange`.
pub fn OffsetRange::contains_range(
  self : OffsetRange,
  other : OffsetRange,
) -> Bool {
  self.start <= other.start && other.end_exclusive <= self.end_exclusive
}

///|
/// Whether `offset` falls inside the half-open range. Mirrors Monaco's
/// `contains`.
pub fn OffsetRange::contains(self : OffsetRange, offset : Int) -> Bool {
  self.start <= offset && offset < self.end_exclusive
}

///|
/// The smallest range containing both ranges. Mirrors Monaco's `join`.
pub fn OffsetRange::join(
  self : OffsetRange,
  other : OffsetRange,
) -> OffsetRange {
  OffsetRange(
    self.start.min(other.start),
    self.end_exclusive.max(other.end_exclusive),
  )
}

///|
/// The intersection of the two ranges, or `None` if they do not even touch.
/// Mirrors Monaco's `intersect` (an empty range if they touch but not overlap).
pub fn OffsetRange::intersect(
  self : OffsetRange,
  other : OffsetRange,
) -> OffsetRange? {
  let start = self.start.max(other.start)
  let end = self.end_exclusive.min(other.end_exclusive)
  if start <= end {
    Some(OffsetRange(start, end))
  } else {
    None
  }
}

///|
/// The number of overlapping offsets (0 if disjoint). Mirrors Monaco's
/// `intersectionLength`.
pub fn OffsetRange::intersection_length(
  self : OffsetRange,
  other : OffsetRange,
) -> Int {
  let start = self.start.max(other.start)
  let end = self.end_exclusive.min(other.end_exclusive)
  (0).max(end - start)
}

///|
/// Whether the two ranges overlap. Mirrors Monaco's `intersects` (always false
/// when either range is empty).
pub fn OffsetRange::intersects(self : OffsetRange, other : OffsetRange) -> Bool {
  let start = self.start.max(other.start)
  let end = self.end_exclusive.min(other.end_exclusive)
  start < end
}

///|
/// Whether the two ranges overlap or touch. Mirrors `intersectsOrTouches`.
pub fn OffsetRange::intersects_or_touches(
  self : OffsetRange,
  other : OffsetRange,
) -> Bool {
  let start = self.start.max(other.start)
  let end = self.end_exclusive.min(other.end_exclusive)
  start <= end
}

///|
/// Whether this range ends at or before `other` starts. Mirrors `isBefore`.
pub fn OffsetRange::is_before(self : OffsetRange, other : OffsetRange) -> Bool {
  self.end_exclusive <= other.start
}

///|
/// Whether this range starts at or after `other` ends. Mirrors `isAfter`.
pub fn OffsetRange::is_after(self : OffsetRange, other : OffsetRange) -> Bool {
  self.start >= other.end_exclusive
}

///|
/// `[start, end_exclusive)`. Mirrors Monaco's `toString`.
pub fn OffsetRange::to_string(self : OffsetRange) -> String {
  "[\{self.start}, \{self.end_exclusive})"
}

///|
/// Inserts `range` into `sorted_ranges`, merging it with any ranges it touches
/// or overlaps so the array stays sorted and non-overlapping. Mirrors Monaco's
/// static `OffsetRange.addRange`.
pub fn OffsetRange::add_range(
  range : OffsetRange,
  sorted_ranges : Array[OffsetRange],
) -> Unit {
  let mut i = 0
  while i < sorted_ranges.length() &&
        sorted_ranges[i].end_exclusive < range.start {
    i = i + 1
  }
  let mut j = i
  while j < sorted_ranges.length() &&
        sorted_ranges[j].start <= range.end_exclusive {
    j = j + 1
  }
  if i == j {
    sorted_ranges.insert(i, range)
  } else {
    let start = if range.start < sorted_ranges[i].start {
      range.start
    } else {
      sorted_ranges[i].start
    }
    let end = if range.end_exclusive > sorted_ranges[j - 1].end_exclusive {
      range.end_exclusive
    } else {
      sorted_ranges[j - 1].end_exclusive
    }
    for _ in 0..<(j - i) {
      sorted_ranges.remove(i) |> ignore
    }
    sorted_ranges.insert(i, OffsetRange(start, end))
  }
}

///|
/// Clamps an integer to an inclusive range.
///
/// Deliberately retained instead of std `Int::clamp(min~, max~)`: many callers
/// pass bounds like `(x, 0, line_count - 1)` where the high bound can fall
/// below the low bound for an empty model, and this helper tolerates that
/// (returning a bound) where std `Int::clamp` would `guard min <= max` and
/// panic. See std-dedup-and-divergence-review.md Step 2.
pub fn clamp_int(value : Int, low : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}
