///| Faithful port of vscode's `GuidesTextModelPart` indent-guide methods.
///
/// Source: `src/vs/editor/common/model/guidesTextModelPart.ts` (+ the
/// `computeIndentLevel` helper from `model/utils.ts`), pinned `vscode/`
/// submodule. This is `model.guides` — the readonly indent-guide queries on a
/// `TextModel`. Only the indent-guide subset is in scope:
/// `getActiveIndentGuide`, `getLinesIndentGuides`, and the private
/// `_getIndentLevelForWhitespaceLine`.
///
/// Deviations / omissions:
///   - `getLinesBracketGuides` / `getVisibleColumnFromPosition` are omitted:
///     they need the bracket-pair + language-configuration infrastructure the
///     readonly viewer does not implement (out of scope, like the bracket-pair
///     colorizer).
///   - `offSide` (from a language's folding rules) is supplied as a field
///     instead of resolved from `languageConfigurationService`; the viewer has
///     no language-configuration registry yet. Monaco's own test languages
///     register no folding rules, so `off_side` is `false` there.
///   - `tab_size` / `indent_size` are fields rather than read from
///     `model.getOptions()`; the viewer's `TextSnapshot` carries no editor
///     options.

///|
/// Active indent-guide span for a line. Mirrors Monaco's `IActiveIndentGuideInfo`.
pub struct ActiveIndentGuideInfo {
  start_line_number : Int
  end_line_number : Int
  indent : Int
} derive(Eq, Debug)

///|
/// `model.guides` — indent-guide queries over a text snapshot.
pub struct GuidesTextModelPart {
  text_model : TextSnapshot
  tab_size : Int
  indent_size : Int
  off_side : Bool
}

///|
#alias(new, deprecated)
pub fn GuidesTextModelPart::GuidesTextModelPart(
  text_model : TextSnapshot,
  tab_size? : Int = 4,
  indent_size? : Int = 4,
  off_side? : Bool = false,
) -> GuidesTextModelPart {
  { text_model, tab_size, indent_size, off_side }
}

///|
/// Whitespace-run width of a line (tabs expanded to `tab_size`), or `-1` if the
/// line is whitespace-only. Mirrors Monaco's `_computeIndentLevel`, delegating
/// to the `model/utils.ts` `computeIndentLevel` helper. The `line_index` is
/// zero-based, as in Monaco.
fn GuidesTextModelPart::compute_indent_level(
  self : GuidesTextModelPart,
  line_index : Int,
) -> Int {
  compute_indent_level(self.text_model.line_text(line_index), self.tab_size)
}

///|
fn GuidesTextModelPart::get_indent_level_for_whitespace_line(
  self : GuidesTextModelPart,
  off_side : Bool,
  above_content_line_indent : Int,
  below_content_line_indent : Int,
) -> Int {
  if above_content_line_indent == -1 || below_content_line_indent == -1 {
    // At the top or bottom of the file
    0
  } else if above_content_line_indent < below_content_line_indent {
    // we are inside the region above
    1 + floor_div(above_content_line_indent, self.indent_size)
  } else if above_content_line_indent == below_content_line_indent {
    // we are in between two regions
    ceil_div(below_content_line_indent, self.indent_size)
  } else if off_side {
    // same level as region below
    ceil_div(below_content_line_indent, self.indent_size)
  } else {
    // we are inside the region that ends below
    1 + floor_div(below_content_line_indent, self.indent_size)
  }
}

///|
/// Indent-guide level for each line in `[start_line_number, end_line_number]`
/// (1-based, inclusive). Mirrors `getLinesIndentGuides`.
pub fn GuidesTextModelPart::get_lines_indent_guides(
  self : GuidesTextModelPart,
  start_line_number : Int,
  end_line_number : Int,
) -> Array[Int] {
  let line_count = self.text_model.line_count()
  guard start_line_number >= 1 && start_line_number <= line_count else {
    abort("Illegal value for startLineNumber")
  }
  guard end_line_number >= 1 && end_line_number <= line_count else {
    abort("Illegal value for endLineNumber")
  }
  let off_side = self.off_side
  let result = Array::make(end_line_number - start_line_number + 1, 0)
  let mut above_content_line_index = -2 // -2 is a marker for not yet computed
  let mut above_content_line_indent = -1
  let mut below_content_line_index = -2 // -2 is a marker for not yet computed
  let mut below_content_line_indent = -1
  for line_number = start_line_number
      line_number <= end_line_number
      line_number = line_number + 1 {
    let result_index = line_number - start_line_number
    let current_indent = self.compute_indent_level(line_number - 1)
    if current_indent >= 0 {
      // This line has content (besides whitespace) — use the line's indent
      above_content_line_index = line_number - 1
      above_content_line_indent = current_indent
      result[result_index] = ceil_div(current_indent, self.indent_size)
      continue
    }
    if above_content_line_index == -2 {
      above_content_line_index = -1
      above_content_line_indent = -1
      // must find previous line with content
      for line_index = line_number - 2
          line_index >= 0
          line_index = line_index - 1 {
        let indent = self.compute_indent_level(line_index)
        if indent >= 0 {
          above_content_line_index = line_index
          above_content_line_indent = indent
          break
        }
      }
    }
    if below_content_line_index != -1 &&
      (
        below_content_line_index == -2 ||
        below_content_line_index < line_number - 1
      ) {
      below_content_line_index = -1
      below_content_line_indent = -1
      // must find next line with content
      for line_index = line_number
          line_index < line_count
          line_index = line_index + 1 {
        let indent = self.compute_indent_level(line_index)
        if indent >= 0 {
          below_content_line_index = line_index
          below_content_line_indent = indent
          break
        }
      }
    }
    result[result_index] = self.get_indent_level_for_whitespace_line(
      off_side, above_content_line_indent, below_content_line_indent,
    )
  }
  result
}

///|
/// The active indent guide that contains `line_number`, bounded by
/// `[min_line_number, max_line_number]`. Mirrors `getActiveIndentGuide`.
pub fn GuidesTextModelPart::get_active_indent_guide(
  self : GuidesTextModelPart,
  line_number : Int,
  min_line_number : Int,
  max_line_number : Int,
) -> ActiveIndentGuideInfo {
  let line_count = self.text_model.line_count()
  guard line_number >= 1 && line_number <= line_count else {
    abort("Illegal value for lineNumber")
  }
  let off_side = self.off_side

  // -2 is a marker for "not yet computed" throughout.
  let mut up_above_content_line_index = -2
  let mut up_above_content_line_indent = -1
  let mut up_below_content_line_index = -2
  let mut up_below_content_line_indent = -1
  let up_resolve_indents = fn(line_number : Int) -> Unit {
    if up_above_content_line_index != -1 &&
      (
        up_above_content_line_index == -2 ||
        up_above_content_line_index > line_number - 1
      ) {
      up_above_content_line_index = -1
      up_above_content_line_indent = -1
      // must find previous line with content
      for line_index = line_number - 2
          line_index >= 0
          line_index = line_index - 1 {
        let indent = self.compute_indent_level(line_index)
        if indent >= 0 {
          up_above_content_line_index = line_index
          up_above_content_line_indent = indent
          break
        }
      }
    }
    if up_below_content_line_index == -2 {
      up_below_content_line_index = -1
      up_below_content_line_indent = -1
      // must find next line with content
      for line_index = line_number
          line_index < line_count
          line_index = line_index + 1 {
        let indent = self.compute_indent_level(line_index)
        if indent >= 0 {
          up_below_content_line_index = line_index
          up_below_content_line_indent = indent
          break
        }
      }
    }
  }
  let mut down_above_content_line_index = -2
  let mut down_above_content_line_indent = -1
  let mut down_below_content_line_index = -2
  let mut down_below_content_line_indent = -1
  let down_resolve_indents = fn(line_number : Int) -> Unit {
    if down_above_content_line_index == -2 {
      down_above_content_line_index = -1
      down_above_content_line_indent = -1
      // must find previous line with content
      for line_index = line_number - 2
          line_index >= 0
          line_index = line_index - 1 {
        let indent = self.compute_indent_level(line_index)
        if indent >= 0 {
          down_above_content_line_index = line_index
          down_above_content_line_indent = indent
          break
        }
      }
    }
    if down_below_content_line_index != -1 &&
      (
        down_below_content_line_index == -2 ||
        down_below_content_line_index < line_number - 1
      ) {
      down_below_content_line_index = -1
      down_below_content_line_indent = -1
      // must find next line with content
      for line_index = line_number
          line_index < line_count
          line_index = line_index + 1 {
        let indent = self.compute_indent_level(line_index)
        if indent >= 0 {
          down_below_content_line_index = line_index
          down_below_content_line_indent = indent
          break
        }
      }
    }
  }
  let mut start_line_number = 0
  let mut go_up = true
  let mut end_line_number = 0
  let mut go_down = true
  let mut indent = 0
  let mut initial_indent = 0
  for distance = 0; go_up || go_down; distance = distance + 1 {
    let up_line_number = line_number - distance
    let down_line_number = line_number + distance
    if distance > 1 && (up_line_number < 1 || up_line_number < min_line_number) {
      go_up = false
    }
    if distance > 1 &&
      (down_line_number > line_count || down_line_number > max_line_number) {
      go_down = false
    }
    if distance > 50000 {
      // stop processing
      go_up = false
      go_down = false
    }
    let mut up_line_indent_level = -1
    if go_up && up_line_number >= 1 {
      // compute indent level going up
      let current_indent = self.compute_indent_level(up_line_number - 1)
      if current_indent >= 0 {
        // This line has content (besides whitespace) — use the line's indent
        up_below_content_line_index = up_line_number - 1
        up_below_content_line_indent = current_indent
        up_line_indent_level = ceil_div(current_indent, self.indent_size)
      } else {
        up_resolve_indents(up_line_number)
        up_line_indent_level = self.get_indent_level_for_whitespace_line(
          off_side, up_above_content_line_indent, up_below_content_line_indent,
        )
      }
    }
    let mut down_line_indent_level = -1
    if go_down && down_line_number <= line_count {
      // compute indent level going down
      let current_indent = self.compute_indent_level(down_line_number - 1)
      if current_indent >= 0 {
        // This line has content (besides whitespace) — use the line's indent
        down_above_content_line_index = down_line_number - 1
        down_above_content_line_indent = current_indent
        down_line_indent_level = ceil_div(current_indent, self.indent_size)
      } else {
        down_resolve_indents(down_line_number)
        down_line_indent_level = self.get_indent_level_for_whitespace_line(
          off_side, down_above_content_line_indent, down_below_content_line_indent,
        )
      }
    }
    if distance == 0 {
      initial_indent = up_line_indent_level
      continue
    }
    if distance == 1 {
      if down_line_number <= line_count &&
        down_line_indent_level >= 0 &&
        initial_indent + 1 == down_line_indent_level {
        // This is the beginning of a scope: we want the child scope indent to
        // be active, not the parent scope.
        go_up = false
        start_line_number = down_line_number
        end_line_number = down_line_number
        indent = down_line_indent_level
        continue
      }
      if up_line_number >= 1 &&
        up_line_indent_level >= 0 &&
        up_line_indent_level - 1 == initial_indent {
        // This is the end of a scope, just like above.
        go_down = false
        start_line_number = up_line_number
        end_line_number = up_line_number
        indent = up_line_indent_level
        continue
      }
      start_line_number = line_number
      end_line_number = line_number
      indent = initial_indent
      if indent == 0 {
        // No need to continue
        return { start_line_number, end_line_number, indent }
      }
    }
    if go_up {
      if up_line_indent_level >= indent {
        start_line_number = up_line_number
      } else {
        go_up = false
      }
    }
    if go_down {
      if down_line_indent_level >= indent {
        end_line_number = down_line_number
      } else {
        go_down = false
      }
    }
  }
  { start_line_number, end_line_number, indent }
}

///|
/// `ceil(a / b)` for `a >= 0`, `b > 0` (Monaco's `Math.ceil` over number
/// division).
fn ceil_div(a : Int, b : Int) -> Int {
  (a + b - 1) / b
}

///|
/// `floor(a / b)` for `a >= 0`, `b > 0` (Monaco's `Math.floor` over number
/// division).
fn floor_div(a : Int, b : Int) -> Int {
  a / b
}
