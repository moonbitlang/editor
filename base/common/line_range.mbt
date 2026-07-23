// 1:1 port of Monaco/VS Code's LineRange / LineRangeSet.
//
// Source: vscode/src/vs/editor/common/core/ranges/lineRange.ts
//   with the monotonic binary-search helpers from
//   vscode/src/vs/base/common/arraysFind.ts
// (checked-in vscode submodule).
//
// Adaptation: upstream's constructor throws on `startLineNumber >
// endLineNumberExclusive`; this port stores the values without validating
// (callers pass valid ranges).

///|
/// A range of lines (1-based), `[start_line_number, end_line_number_exclusive)`.
pub(all) struct LineRange {
  start_line_number : Int
  end_line_number_exclusive : Int
} derive(Eq, Debug)

///|
pub fn LineRange::LineRange(
  start_line_number : Int,
  end_line_number_exclusive : Int,
) -> LineRange {
  { start_line_number, end_line_number_exclusive }
}

///|
pub fn LineRange::of_length(start_line_number : Int, length : Int) -> LineRange {
  LineRange(start_line_number, start_line_number + length)
}

///|
/// Indicates if this line range contains the given line number.
pub fn LineRange::contains(self : LineRange, line_number : Int) -> Bool {
  self.start_line_number <= line_number &&
  line_number < self.end_line_number_exclusive
}

///|
pub fn LineRange::contains_range(self : LineRange, other : LineRange) -> Bool {
  self.start_line_number <= other.start_line_number &&
  other.end_line_number_exclusive <= self.end_line_number_exclusive
}

///|
/// Indicates if this line range is empty.
pub fn LineRange::is_empty(self : LineRange) -> Bool {
  self.start_line_number == self.end_line_number_exclusive
}

///|
pub fn LineRange::delta(self : LineRange, offset : Int) -> LineRange {
  LineRange(
    self.start_line_number + offset,
    self.end_line_number_exclusive + offset,
  )
}

///|
/// The number of lines this line range spans.
pub fn LineRange::length(self : LineRange) -> Int {
  self.end_line_number_exclusive - self.start_line_number
}

///|
/// Combines this and the given line range into the smallest covering range.
pub fn LineRange::join(self : LineRange, other : LineRange) -> LineRange {
  LineRange(
    self.start_line_number.min(other.start_line_number),
    self.end_line_number_exclusive.max(other.end_line_number_exclusive),
  )
}

///|
/// Joins arrays of already sorted line ranges into one normalized array.
/// Mirrors Monaco's `LineRange.joinMany` (`lineRange.ts:51-60`), including the
/// empty-input early return and caller-array copies.
pub fn LineRange::join_many(
  line_ranges : Array[Array[LineRange]],
) -> Array[LineRange] {
  if line_ranges.length() == 0 {
    return []
  }
  let mut result = LineRangeSet(normalized_ranges=line_ranges[0].copy())
  for index in 1..<line_ranges.length() {
    result = result.get_union(
      LineRangeSet(normalized_ranges=line_ranges[index].copy()),
    )
  }
  result.ranges()
}

///|
pub fn LineRange::to_string(self : LineRange) -> String {
  "[\{self.start_line_number},\{self.end_line_number_exclusive})"
}

///|
/// Empty if the ranges touch but do not overlap; `None` if they don't touch.
pub fn LineRange::intersect(self : LineRange, other : LineRange) -> LineRange? {
  let start_line_number = self.start_line_number.max(other.start_line_number)
  let end_line_number_exclusive = self.end_line_number_exclusive.min(
    other.end_line_number_exclusive,
  )
  if start_line_number <= end_line_number_exclusive {
    Some(LineRange(start_line_number, end_line_number_exclusive))
  } else {
    None
  }
}

///|
pub fn LineRange::intersects_strict(
  self : LineRange,
  other : LineRange,
) -> Bool {
  self.start_line_number < other.end_line_number_exclusive &&
  other.start_line_number < self.end_line_number_exclusive
}

///|
pub fn LineRange::intersects_or_touches(
  self : LineRange,
  other : LineRange,
) -> Bool {
  self.start_line_number <= other.end_line_number_exclusive &&
  other.start_line_number <= self.end_line_number_exclusive
}

///|
pub fn LineRange::equals(self : LineRange, other : LineRange) -> Bool {
  self == other
}

///|
/// A normalized set of line ranges (sorted by start, none touching/overlapping).
pub struct LineRangeSet {
  normalized_ranges : Array[LineRange]
}

///|
#alias(new, deprecated)
pub fn LineRangeSet::LineRangeSet(
  normalized_ranges? : Array[LineRange] = [],
) -> LineRangeSet {
  { normalized_ranges, }
}

///|
pub fn LineRangeSet::ranges(self : LineRangeSet) -> Array[LineRange] {
  self.normalized_ranges
}

///|
pub fn LineRangeSet::add_range(self : LineRangeSet, range : LineRange) -> Unit {
  if range.length() == 0 {
    return
  }
  let ranges = self.normalized_ranges
  let join_range_start_idx = find_first_idx_monotonous_or_arr_len(ranges[:], r => {
    r.end_line_number_exclusive >= range.start_line_number
  })
  let join_range_end_idx_exclusive = find_last_idx_monotonous(ranges[:], r => {
      r.start_line_number <= range.end_line_number_exclusive
    }) +
    1
  if join_range_start_idx == join_range_end_idx_exclusive {
    array_splice_insert(ranges, join_range_start_idx, range)
  } else if join_range_start_idx == join_range_end_idx_exclusive - 1 {
    let join_range = ranges[join_range_start_idx]
    ranges[join_range_start_idx] = join_range.join(range)
  } else {
    let join_range = ranges[join_range_start_idx]
      .join(ranges[join_range_end_idx_exclusive - 1])
      .join(range)
    array_splice_replace(
      ranges,
      join_range_start_idx,
      join_range_end_idx_exclusive - join_range_start_idx,
      join_range,
    )
  }
}

///|
pub fn LineRangeSet::contains(self : LineRangeSet, line_number : Int) -> Bool {
  match
    find_last_monotonous(self.normalized_ranges[:], r => {
      r.start_line_number <= line_number
    }) {
    Some(r) => r.end_line_number_exclusive > line_number
    None => false
  }
}

///|
pub fn LineRangeSet::intersects(self : LineRangeSet, range : LineRange) -> Bool {
  match
    find_last_monotonous(self.normalized_ranges[:], r => {
      r.start_line_number < range.end_line_number_exclusive
    }) {
    Some(r) => r.end_line_number_exclusive > range.start_line_number
    None => false
  }
}

///|
pub fn LineRangeSet::get_union(
  self : LineRangeSet,
  other : LineRangeSet,
) -> LineRangeSet {
  if self.normalized_ranges.length() == 0 {
    return other
  }
  if other.normalized_ranges.length() == 0 {
    return self
  }
  let result : Array[LineRange] = []
  let mut i1 = 0
  let mut i2 = 0
  let mut current : LineRange? = None
  while i1 < self.normalized_ranges.length() ||
        i2 < other.normalized_ranges.length() {
    let next = if i1 < self.normalized_ranges.length() &&
      i2 < other.normalized_ranges.length() {
      let line_range1 = self.normalized_ranges[i1]
      let line_range2 = other.normalized_ranges[i2]
      if line_range1.start_line_number < line_range2.start_line_number {
        i1 += 1
        line_range1
      } else {
        i2 += 1
        line_range2
      }
    } else if i1 < self.normalized_ranges.length() {
      let r = self.normalized_ranges[i1]
      i1 += 1
      r
    } else {
      let r = other.normalized_ranges[i2]
      i2 += 1
      r
    }
    match current {
      None => current = Some(next)
      Some(cur) =>
        if cur.end_line_number_exclusive >= next.start_line_number {
          current = Some(
            LineRange(
              cur.start_line_number,
              cur.end_line_number_exclusive.max(next.end_line_number_exclusive),
            ),
          )
        } else {
          result.push(cur)
          current = Some(next)
        }
    }
  }
  match current {
    Some(cur) => result.push(cur)
    None => ()
  }
  LineRangeSet(normalized_ranges=result)
}

///|
pub fn LineRangeSet::to_string(self : LineRangeSet) -> String {
  let parts = []
  for r in self.normalized_ranges {
    parts.push(r.to_string())
  }
  parts.join(", ")
}

// --- monotonic binary-search helpers (arraysFind.ts) ---

///|
fn find_first_idx_monotonous_or_arr_len(
  array : ArrayView[LineRange],
  predicate : (LineRange) -> Bool,
) -> Int {
  let mut i = 0
  let mut j = array.length()
  while i < j {
    let k = (i + j) / 2
    if predicate(array[k]) {
      j = k
    } else {
      i = k + 1
    }
  }
  i
}

///|
fn find_last_idx_monotonous(
  array : ArrayView[LineRange],
  predicate : (LineRange) -> Bool,
) -> Int {
  let mut i = 0
  let mut j = array.length()
  while i < j {
    let k = (i + j) / 2
    if predicate(array[k]) {
      i = k + 1
    } else {
      j = k
    }
  }
  i - 1
}

///|
fn find_last_monotonous(
  array : ArrayView[LineRange],
  predicate : (LineRange) -> Bool,
) -> LineRange? {
  let idx = find_last_idx_monotonous(array, predicate)
  if idx == -1 {
    None
  } else {
    Some(array[idx])
  }
}

///|
fn array_splice_insert(
  array : Array[LineRange],
  index : Int,
  item : LineRange,
) -> Unit {
  array.push(item)
  let mut i = array.length() - 1
  while i > index {
    array[i] = array[i - 1]
    i -= 1
  }
  array[index] = item
}

///|
fn array_splice_replace(
  array : Array[LineRange],
  start : Int,
  delete_count : Int,
  item : LineRange,
) -> Unit {
  let rest : Array[LineRange] = []
  for i in (start + delete_count)..<array.length() {
    rest.push(array[i])
  }
  while array.length() > start {
    array.pop() |> ignore
  }
  array.push(item)
  for r in rest {
    array.push(r)
  }
}
