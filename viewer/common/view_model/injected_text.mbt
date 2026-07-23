///|
/// Text inserted into a rendered line without existing in the source document.
pub struct InjectedText {
  position : @base_common.Position
  text : String
  class_name : String
  source_index : Int
} derive(Eq, Debug)

///|
/// Builds injected text at a model position.
pub fn InjectedText::InjectedText(
  position : @base_common.Position,
  text : String,
  class_name : String,
  source_index? : Int = -1,
) -> InjectedText {
  { position, text, class_name, source_index }
}

///|
/// Segment kind inside a projected line: source text or injected text.
pub enum ProjectedLinePartKind {
  SourceSegment(model_start~ : Int, model_end~ : Int)
  InjectedSegment(
    model_column~ : Int,
    injected_text_index~ : Int,
    class_name~ : String
  )
} derive(Eq, Debug)

///|
/// Half-open projected text segment with its source/injected identity.
pub struct ProjectedLinePart {
  start : Int
  end : Int
  kind : ProjectedLinePartKind
} derive(Eq, Debug)

///|
/// One model line after injected text has been projected into display text,
/// with column maps in both directions.
///
/// Monaco's `ModelLineProjectionData` maps columns with offset arithmetic and
/// binary search (`translateToOutputPosition` / `translateToInputOffset`);
/// this type precomputes per-column lookup tables
/// (`model_to_projected_columns`, `model_columns`) for O(1) `.get()`. The
/// tables are first-write-wins, so a boundary column resolves to the *left*
/// of the injections anchored there — exactly Monaco's non-`Right` affinity
/// behavior; `model_column_to_projected_column` surfaces the `Right` side and
/// `normalize_projected_column_around_injections` ports the normalization
/// branches.
pub struct ProjectedTextLine {
  text : String
  model_line_length : Int
  model_columns : Array[Int]
  injected_text_indices : Array[Int]
  model_to_projected_columns : Array[Int]
  parts : Array[ProjectedLinePart]
} derive(Eq, Debug)

///|
/// Projection for a line with no injected text.
pub fn ProjectedTextLine::identity(line_text : String) -> ProjectedTextLine {
  ProjectedTextLine::from_injected_text(line_text, [])
}

///|
/// Builds projected text and column maps for one model line plus injected text.
pub fn ProjectedTextLine::from_injected_text(
  line_text : String,
  injected_text : Array[InjectedText],
) -> ProjectedTextLine {
  let normalized = normalize_injected_text(line_text, injected_text[:])
  if normalized.length() == 0 {
    return identity_projected_text_line(line_text)
  }
  let builder = StringBuilder()
  let model_columns : Array[Int] = [0]
  let injected_text_indices : Array[Int] = []
  let model_to_projected_columns = initial_model_to_projected_columns(
    line_text.length(),
  )
  let parts : Array[ProjectedLinePart] = []
  let mut source_cursor = 0
  let mut view_cursor = 0
  for item in normalized {
    let column = @base_common.clamp_int(
      item.position.column,
      0,
      line_text.length(),
    )
    if column > source_cursor {
      append_source_text(
        builder, line_text, source_cursor, column, model_columns, injected_text_indices,
        model_to_projected_columns, parts, view_cursor,
      )
      view_cursor += column - source_cursor
      source_cursor = column
    }
    append_injected_text(
      builder, item, column, model_columns, injected_text_indices, parts, view_cursor,
    )
    view_cursor += item.text.length()
  }
  if source_cursor < line_text.length() {
    append_source_text(
      builder,
      line_text,
      source_cursor,
      line_text.length(),
      model_columns,
      injected_text_indices,
      model_to_projected_columns,
      parts,
      view_cursor,
    )
    view_cursor += line_text.length() - source_cursor
  }
  fill_unmapped_model_columns(model_to_projected_columns, view_cursor)
  {
    text: builder.to_string(),
    model_line_length: line_text.length(),
    model_columns,
    injected_text_indices,
    model_to_projected_columns,
    parts,
  }
}

///|
/// Maps a model column to a projected display column.
///
/// The injection branch of `translateToOutputPosition`
/// (`modelLineProjectionData.ts:111-128`): only `Right` resolves a boundary
/// column to the far side of every injection anchored there; every other
/// affinity (the `None` default included) stays left of them, which is what
/// the first-write-wins lookup table already encodes.
pub fn ProjectedTextLine::model_column_to_projected_column(
  self : ProjectedTextLine,
  model_column : Int,
  affinity? : @model.PositionAffinity,
) -> Int {
  let column = @base_common.clamp_int(model_column, 0, self.model_line_length)
  let projected = match self.model_to_projected_columns.get(column) {
    Some(projected_column) => projected_column
    None => self.text.length()
  }
  match affinity {
    Some(Right) => {
      let mut result = projected
      // Parts are in ascending projected order, so one pass walks every
      // injection anchored at this model column.
      for part in self.parts {
        if part.start == result &&
          part.kind is InjectedSegment(model_column=anchor, ..) &&
          anchor == column {
          result = part.end
        }
      }
      result
    }
    _ => projected
  }
}

///|
/// Snaps a projected column that touches injected text to one of its sides,
/// `normalizeOffsetInInputWithInjectionsAroundInjections`
/// (`modelLineProjectionData.ts:204-252`). Containment mirrors
/// `getInjectedTextAtOffset` (`:255-284`): inclusive on both ends, first
/// match wins. The viewer's injected text carries no `cursorStops`, so `None`
/// behaves as Monaco's default `InjectedTextCursorStops.Both`: only
/// strictly-inside columns snap (to the injection start); boundary columns
/// already are cursor stops.
pub fn ProjectedTextLine::normalize_projected_column_around_injections(
  self : ProjectedTextLine,
  projected_column : Int,
  affinity : @model.PositionAffinity,
) -> Int {
  let parts = self.parts
  let mut found = -1
  for index in 0..<parts.length() {
    let part = parts[index]
    guard part.kind is InjectedSegment(..) else { continue }
    if part.start > projected_column {
      // All later injections start even further right.
      break
    }
    if projected_column <= part.end {
      found = index
      break
    }
  }
  if found < 0 {
    return projected_column
  }
  let part = parts[found]
  match affinity {
    None =>
      // cursorStops = Both: the injection's end is a right cursor stop, its
      // start a left one.
      if projected_column == part.end {
        projected_column
      } else {
        part.start
      }
    Right | RightOfInjectedText => {
      // Past every injection anchored at the same model column.
      let anchor = injected_part_anchor(part)
      let mut result = part.end
      let mut index = found + 1
      while index < parts.length() &&
            parts[index].kind is InjectedSegment(model_column=next_anchor, ..) &&
            next_anchor == anchor {
        result = parts[index].end
        index += 1
      }
      result
    }
    Left | LeftOfInjectedText => {
      // Before every injection anchored at the same model column.
      let anchor = injected_part_anchor(part)
      let mut result = part.start
      let mut index = found - 1
      while index >= 0 &&
            parts[index].kind is InjectedSegment(model_column=prev_anchor, ..) &&
            prev_anchor == anchor {
        result = parts[index].start
        index -= 1
      }
      result
    }
  }
}

///|
fn injected_part_anchor(part : ProjectedLinePart) -> Int {
  match part.kind {
    InjectedSegment(model_column~, ..) => model_column
    SourceSegment(..) => -1
  }
}

///|
/// Maps a projected display column back to a model column.
pub fn ProjectedTextLine::projected_column_to_model_column(
  self : ProjectedTextLine,
  projected_column : Int,
) -> Int {
  let column = @base_common.clamp_int(projected_column, 0, self.text.length())
  match self.model_columns.get(column) {
    Some(model_column) => model_column
    None => self.model_line_length
  }
}

///|
/// Returns the injected-text source index at a projected display column, or
/// `-1` for source text.
pub fn ProjectedTextLine::injected_text_index_at_projected_column(
  self : ProjectedTextLine,
  projected_column : Int,
) -> Int {
  let column = @base_common.clamp_int(projected_column, 0, self.text.length())
  match self.injected_text_indices.get(column) {
    Some(index) => index
    None => -1
  }
}

///|
fn identity_projected_text_line(line_text : String) -> ProjectedTextLine {
  let model_columns : Array[Int] = []
  let injected_text_indices : Array[Int] = []
  let model_to_projected_columns : Array[Int] = []
  for column in 0..<=line_text.length() {
    model_columns.push(column)
    model_to_projected_columns.push(column)
    if column < line_text.length() {
      injected_text_indices.push(-1)
    }
  }
  let parts : Array[ProjectedLinePart] = []
  if line_text.length() > 0 {
    parts.push({
      start: 0,
      end: line_text.length(),
      kind: SourceSegment(model_start=0, model_end=line_text.length()),
    })
  }
  {
    text: line_text,
    model_line_length: line_text.length(),
    model_columns,
    injected_text_indices,
    model_to_projected_columns,
    parts,
  }
}

///|
fn normalize_injected_text(
  line_text : String,
  injected_text : ArrayView[InjectedText],
) -> Array[InjectedText] {
  let normalized : Array[InjectedText] = []
  for item in injected_text {
    if item.text.length() > 0 {
      let column = @base_common.clamp_int(
        item.position.column,
        0,
        line_text.length(),
      )
      normalized.push({ ..item, position: { ..item.position, column, } })
    }
  }
  normalized.sort_by((left, right) => {
    if left.position.column != right.position.column {
      left.position.column - right.position.column
    } else {
      left.source_index - right.source_index
    }
  })
  normalized
}

///|
fn initial_model_to_projected_columns(line_length : Int) -> Array[Int] {
  let columns : Array[Int] = []
  for _ in 0..<=line_length {
    columns.push(-1)
  }
  columns[0] = 0
  columns
}

///|
fn append_source_text(
  builder : StringBuilder,
  line_text : String,
  start_column : Int,
  end_column : Int,
  model_columns : Array[Int],
  injected_text_indices : Array[Int],
  model_to_projected_columns : Array[Int],
  parts : Array[ProjectedLinePart],
  view_cursor : Int,
) -> Unit {
  builder.write_string(line_text[start_column:end_column].to_owned())
  let mut view = view_cursor
  for column in start_column..<end_column {
    injected_text_indices.push(-1)
    view += 1
    model_columns.push(column + 1)
    if model_to_projected_columns[column + 1] < 0 {
      model_to_projected_columns[column + 1] = view
    }
  }
  parts.push({
    start: view_cursor,
    end: view,
    kind: SourceSegment(model_start=start_column, model_end=end_column),
  })
}

///|
fn append_injected_text(
  builder : StringBuilder,
  item : InjectedText,
  model_column : Int,
  model_columns : Array[Int],
  injected_text_indices : Array[Int],
  parts : Array[ProjectedLinePart],
  view_cursor : Int,
) -> Unit {
  builder.write_string(item.text)
  let mut view = view_cursor
  for _ in 0..<item.text.length() {
    injected_text_indices.push(item.source_index)
    view += 1
    model_columns.push(model_column)
  }
  parts.push({
    start: view_cursor,
    end: view,
    kind: InjectedSegment(
      model_column~,
      injected_text_index=item.source_index,
      class_name=item.class_name,
    ),
  })
}

///|
fn fill_unmapped_model_columns(
  model_to_projected_columns : Array[Int],
  fallback : Int,
) -> Unit {
  let mut last = fallback
  for index in 0..<model_to_projected_columns.length() {
    if model_to_projected_columns[index] >= 0 {
      last = model_to_projected_columns[index]
    } else {
      model_to_projected_columns[index] = last
    }
  }
}
