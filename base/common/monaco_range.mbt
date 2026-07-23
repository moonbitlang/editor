// 1:1 port of Monaco/VS Code's line/column `Range`.
//
// Source: vscode/src/vs/editor/common/core/range.ts
// (checked-in vscode submodule).
//
// `(startLineNumber, startColumn)` is normalized to be <= `(endLineNumber,
// endColumn)`. Endpoints are held as `Position` (1-based `line_number`/`column`,
// matching Monaco); the methods here are pure coordinate comparisons.

///|
/// A range in the editor. `(start_line_number, start_column)` is <=
/// `(end_line_number, end_column)`.
pub(all) struct Range {
  start_line_number : Int
  start_column : Int
  end_line_number : Int
  end_column : Int
} derive(Eq, Debug)

///|
pub fn Range::Range(
  start_line_number : Int,
  start_column : Int,
  end_line_number : Int,
  end_column : Int,
) -> Range {
  if start_line_number > end_line_number ||
    (start_line_number == end_line_number && start_column > end_column) {
    {
      start_line_number: end_line_number,
      start_column: end_column,
      end_line_number: start_line_number,
      end_column: start_column,
    }
  } else {
    { start_line_number, start_column, end_line_number, end_column }
  }
}

///|
/// Test if this range is empty.
pub fn Range::is_empty(self : Range) -> Bool {
  Range::is_empty_range(self)
}

///|
/// Test if `range` is empty.
pub fn Range::is_empty_range(range : Range) -> Bool {
  range.start_line_number == range.end_line_number &&
  range.start_column == range.end_column
}

///|
/// Test if position is in this range. If the position is at the edges, returns true.
pub fn Range::contains_position(self : Range, position : Position) -> Bool {
  Range::contains_position_in(self, position)
}

///|
pub fn Range::contains_position_in(range : Range, position : Position) -> Bool {
  if position.line_number < range.start_line_number ||
    position.line_number > range.end_line_number {
    return false
  }
  if position.line_number == range.start_line_number &&
    position.column < range.start_column {
    return false
  }
  if position.line_number == range.end_line_number &&
    position.column > range.end_column {
    return false
  }
  true
}

///|
/// Test if position is strictly in this range (edges excluded).
pub fn Range::strict_contains_position(
  range : Range,
  position : Position,
) -> Bool {
  if position.line_number < range.start_line_number ||
    position.line_number > range.end_line_number {
    return false
  }
  if position.line_number == range.start_line_number &&
    position.column <= range.start_column {
    return false
  }
  if position.line_number == range.end_line_number &&
    position.column >= range.end_column {
    return false
  }
  true
}

///|
/// Test if `other` is in this range. If equal, returns true.
pub fn Range::contains_range(self : Range, other : Range) -> Bool {
  Range::contains_range_in(self, other)
}

///|
pub fn Range::contains_range_in(range : Range, other_range : Range) -> Bool {
  if other_range.start_line_number < range.start_line_number ||
    other_range.end_line_number < range.start_line_number {
    return false
  }
  if other_range.start_line_number > range.end_line_number ||
    other_range.end_line_number > range.end_line_number {
    return false
  }
  if other_range.start_line_number == range.start_line_number &&
    other_range.start_column < range.start_column {
    return false
  }
  if other_range.end_line_number == range.end_line_number &&
    other_range.end_column > range.end_column {
    return false
  }
  true
}

///|
/// Test if `other` is strictly in this range (must start after and end before).
pub fn Range::strict_contains_range(self : Range, other : Range) -> Bool {
  Range::strict_contains_range_in(self, other)
}

///|
pub fn Range::strict_contains_range_in(
  range : Range,
  other_range : Range,
) -> Bool {
  if other_range.start_line_number < range.start_line_number ||
    other_range.end_line_number < range.start_line_number {
    return false
  }
  if other_range.start_line_number > range.end_line_number ||
    other_range.end_line_number > range.end_line_number {
    return false
  }
  if other_range.start_line_number == range.start_line_number &&
    other_range.start_column <= range.start_column {
    return false
  }
  if other_range.end_line_number == range.end_line_number &&
    other_range.end_column >= range.end_column {
    return false
  }
  true
}

///|
/// A reunion of the two ranges (smallest start, largest end).
pub fn Range::plus_range(self : Range, other : Range) -> Range {
  Range::plus_range_of(self, other)
}

///|
pub fn Range::plus_range_of(a : Range, b : Range) -> Range {
  let mut start_line_number = 0
  let mut start_column = 0
  let mut end_line_number = 0
  let mut end_column = 0
  if b.start_line_number < a.start_line_number {
    start_line_number = b.start_line_number
    start_column = b.start_column
  } else if b.start_line_number == a.start_line_number {
    start_line_number = b.start_line_number
    start_column = b.start_column.min(a.start_column)
  } else {
    start_line_number = a.start_line_number
    start_column = a.start_column
  }
  if b.end_line_number > a.end_line_number {
    end_line_number = b.end_line_number
    end_column = b.end_column
  } else if b.end_line_number == a.end_line_number {
    end_line_number = b.end_line_number
    end_column = b.end_column.max(a.end_column)
  } else {
    end_line_number = a.end_line_number
    end_column = a.end_column
  }
  Range(start_line_number, start_column, end_line_number, end_column)
}

///|
/// An intersection of the two ranges, or `None` if they do not intersect.
pub fn Range::intersect_ranges(self : Range, other : Range) -> Range? {
  Range::intersect_ranges_of(self, other)
}

///|
pub fn Range::intersect_ranges_of(a : Range, b : Range) -> Range? {
  let mut result_start_line_number = a.start_line_number
  let mut result_start_column = a.start_column
  let mut result_end_line_number = a.end_line_number
  let mut result_end_column = a.end_column
  let other_start_line_number = b.start_line_number
  let other_start_column = b.start_column
  let other_end_line_number = b.end_line_number
  let other_end_column = b.end_column
  if result_start_line_number < other_start_line_number {
    result_start_line_number = other_start_line_number
    result_start_column = other_start_column
  } else if result_start_line_number == other_start_line_number {
    result_start_column = result_start_column.max(other_start_column)
  }
  if result_end_line_number > other_end_line_number {
    result_end_line_number = other_end_line_number
    result_end_column = other_end_column
  } else if result_end_line_number == other_end_line_number {
    result_end_column = result_end_column.min(other_end_column)
  }
  if result_start_line_number > result_end_line_number {
    return None
  }
  if result_start_line_number == result_end_line_number &&
    result_start_column > result_end_column {
    return None
  }
  Some(
    Range(
      result_start_line_number, result_start_column, result_end_line_number, result_end_column,
    ),
  )
}

///|
/// Test if this range equals `other`.
pub fn Range::equals_range(self : Range, other : Range) -> Bool {
  self == other
}

///|
/// The end position (after or equal to the start position).
pub fn Range::get_end_position(self : Range) -> Position {
  Position(self.end_line_number, self.end_column)
}

///|
/// The start position (before or equal to the end position).
pub fn Range::get_start_position(self : Range) -> Position {
  Position(self.start_line_number, self.start_column)
}

///|
/// New range with this range's start and the given end position.
pub fn Range::set_end_position(
  self : Range,
  end_line_number : Int,
  end_column : Int,
) -> Range {
  Range(self.start_line_number, self.start_column, end_line_number, end_column)
}

///|
/// New range with this range's end and the given start position.
pub fn Range::set_start_position(
  self : Range,
  start_line_number : Int,
  start_column : Int,
) -> Range {
  Range(start_line_number, start_column, self.end_line_number, self.end_column)
}

///|
/// New empty range at this range's start.
pub fn Range::collapse_to_start(self : Range) -> Range {
  Range(
    self.start_line_number,
    self.start_column,
    self.start_line_number,
    self.start_column,
  )
}

///|
/// New empty range at this range's end.
pub fn Range::collapse_to_end(self : Range) -> Range {
  Range(
    self.end_line_number,
    self.end_column,
    self.end_line_number,
    self.end_column,
  )
}

///|
/// Moves the range by the given number of lines.
pub fn Range::delta(self : Range, line_count : Int) -> Range {
  Range(
    self.start_line_number + line_count,
    self.start_column,
    self.end_line_number + line_count,
    self.end_column,
  )
}

///|
/// Test if this range starts and ends on the same line.
pub fn Range::is_single_line(self : Range) -> Bool {
  self.start_line_number == self.end_line_number
}

///|
/// Build a range from two positions.
pub fn Range::from_positions(start : Position, end : Position) -> Range {
  Range(start.line_number, start.column, end.line_number, end.column)
}

///|
/// Test if the two ranges are touching in any way.
pub fn Range::are_intersecting_or_touching(a : Range, b : Range) -> Bool {
  if a.end_line_number < b.start_line_number ||
    (a.end_line_number == b.start_line_number && a.end_column < b.start_column) {
    return false
  }
  if b.end_line_number < a.start_line_number ||
    (b.end_line_number == a.start_line_number && b.end_column < a.start_column) {
    return false
  }
  true
}

///|
/// Test if the two ranges are intersecting. Touching ranges are not intersecting.
pub fn Range::are_intersecting(a : Range, b : Range) -> Bool {
  if a.end_line_number < b.start_line_number ||
    (a.end_line_number == b.start_line_number && a.end_column <= b.start_column) {
    return false
  }
  if b.end_line_number < a.start_line_number ||
    (b.end_line_number == a.start_line_number && b.end_column <= a.start_column) {
    return false
  }
  true
}

///|
/// Compare ranges by start position, then end position.
pub fn Range::compare_ranges_using_starts(a : Range, b : Range) -> Int {
  if a.start_line_number == b.start_line_number {
    if a.start_column == b.start_column {
      if a.end_line_number == b.end_line_number {
        return a.end_column - b.end_column
      }
      return a.end_line_number - b.end_line_number
    }
    return a.start_column - b.start_column
  }
  a.start_line_number - b.start_line_number
}

///|
/// Compare ranges by end position, then start position.
pub fn Range::compare_ranges_using_ends(a : Range, b : Range) -> Int {
  if a.end_line_number == b.end_line_number {
    if a.end_column == b.end_column {
      if a.start_line_number == b.start_line_number {
        return a.start_column - b.start_column
      }
      return a.start_line_number - b.start_line_number
    }
    return a.end_column - b.end_column
  }
  a.end_line_number - b.end_line_number
}

///|
/// Test if the range spans multiple lines.
pub fn Range::spans_multiple_lines(range : Range) -> Bool {
  range.end_line_number > range.start_line_number
}

///|
/// Transform to a user-presentable string representation.
pub fn Range::to_string(self : Range) -> String {
  "[\{self.start_line_number},\{self.start_column} -> \{self.end_line_number},\{self.end_column}]"
}
