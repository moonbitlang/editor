///|
/// A brace-delimited top-level MoonBit function body. The declaration prefix
/// through `body_start_line_number` remains visible when its outline is
/// collapsed; the fold hides the following body lines and closing brace.
priv struct MoonbitFunctionBodyFold {
  declaration_start_line_number : Int
  body_start_line_number : Int
  body_end_line_number : Int
}

///|
/// A run of two or more consecutive top-level plain `//` comment lines —
/// typically a copyright or file-header block. The first line stays visible
/// when the run is collapsed; the fold hides the continuation lines.
priv struct MoonbitCommentRunFold {
  start_line_number : Int
  end_line_number : Int
}

///|
/// The lexical scan's combined result over one snapshot: brace-bodied
/// top-level function bodies and top-level plain-comment runs, each array in
/// document order and every construct mutually disjoint.
priv struct MoonbitSourceFolds {
  function_bodies : Array[MoonbitFunctionBodyFold]
  comment_runs : Array[MoonbitCommentRunFold]
}

///|
/// Marks a host-computed fold over a run of plain `//` comment lines. Unlike
/// `OUTLINE_BODY_FOLDING_RANGE_TYPE`, a collapsed comment run keeps the
/// ordinary trailing ellipsis after its first line.
const COMMENT_RUN_FOLDING_RANGE_TYPE : String = "editor.commentRun"

///|
fn is_moonbit_outline_identifier_start(code : Int) -> Bool {
  (code >= 'a' && code <= 'z') ||
  (code >= 'A' && code <= 'Z') ||
  code == '_' ||
  code >= 0x80
}

///|
fn is_moonbit_outline_identifier_continue(code : Int) -> Bool {
  is_moonbit_outline_identifier_start(code) || (code >= '0' && code <= '9')
}

///|
/// Whether a line's first token is a plain `//` line comment. Doc comments
/// (`///`, including the `///|` block delimiter) document the adjacent
/// declaration and never join a comment run.
fn is_moonbit_plain_comment_line(line : String) -> Bool {
  for index in 0..<line.length() {
    let code = line[index].to_int()
    if code == ' ' || code == '\t' {
      continue
    }
    return code == '/' &&
      index + 1 < line.length() &&
      line[index + 1].to_int() == '/' &&
      !(index + 2 < line.length() && line[index + 2].to_int() == '/')
  }
  false
}

///|
/// Finds brace-bodied top-level MoonBit functions and top-level plain-comment
/// runs without treating braces in comments, strings, interpolations, or raw
/// lines as source delimiters. The function scan is intentionally
/// declaration-specific: `declare` and `=`-backed functions have no MoonBit
/// body, while qualified methods and formatted `impl ... with fn ...`
/// declarations are included. Comment runs require the line-start lexical
/// state to be top level, so lines inside block comments or brace-delimited
/// constructs never join a run.
fn moonbit_source_folds(snapshot : @model.TextSnapshot) -> MoonbitSourceFolds {
  let folds : Array[MoonbitFunctionBodyFold] = []
  let comment_runs : Array[MoonbitCommentRunFold] = []
  let mut comment_run_start_line = 0
  let mut block_comment_depth = 0
  let mut brace_depth = 0
  let mut function_keyword_line = 0
  let mut function_keyword_bracket_depth = 0
  let mut pending_function_prefix_line = 0
  let mut pending_function_prefix_paren_depth = 0
  let mut pending_impl_start_line = 0
  let mut pending_impl_saw_with = false
  let mut pending_bodyless_declaration = false
  let mut declaration_start_line = 0
  let mut body_start_line = 0
  let mut paren_depth = 0
  let mut bracket_depth = 0
  for line_number in 1..<=snapshot.line_count() {
    let line = snapshot.get_line_content(line_number)
    if block_comment_depth == 0 &&
      brace_depth == 0 &&
      is_moonbit_plain_comment_line(line) {
      if comment_run_start_line == 0 {
        comment_run_start_line = line_number
      }
    } else {
      if comment_run_start_line > 0 && line_number - 1 > comment_run_start_line {
        comment_runs.push({
          start_line_number: comment_run_start_line,
          end_line_number: line_number - 1,
        })
      }
      comment_run_start_line = 0
    }
    let mut index = 0
    let mut quote = 0
    let mut escaped = false
    let mut interpolation_depth = 0
    let interpolation_resume_depths : Array[Int] = []
    let mut line_saw_equals = false
    while index < line.length() {
      let code = line[index].to_int()
      let next = if index + 1 < line.length() {
        line[index + 1].to_int()
      } else {
        0
      }
      if block_comment_depth > 0 {
        if code == '/' && next == '*' {
          block_comment_depth += 1
          index += 2
        } else if code == '*' && next == '/' {
          block_comment_depth -= 1
          index += 2
        } else {
          index += 1
        }
      } else if quote != 0 {
        if escaped {
          escaped = false
        } else if quote == '"' && code == '\\' && next == '{' {
          interpolation_depth += 1
          interpolation_resume_depths.push(interpolation_depth)
          quote = 0
          index += 2
        } else if code == '\\' {
          escaped = true
        } else if code == quote {
          quote = 0
        }
        if !(quote == 0 &&
          interpolation_depth > 0 &&
          code == '\\' &&
          next == '{') {
          index += 1
        }
      } else if interpolation_depth > 0 {
        if code == '/' && next == '/' {
          break
        } else if code == '/' && next == '*' {
          block_comment_depth = 1
          index += 2
        } else if code == '"' || code == '\'' {
          quote = code
          escaped = false
          index += 1
        } else if code == '{' {
          interpolation_depth += 1
          index += 1
        } else if code == '}' {
          if interpolation_resume_depths is [.., resume_depth] &&
            resume_depth == interpolation_depth {
            interpolation_resume_depths.pop() |> ignore
            interpolation_depth -= 1
            quote = '"'
          } else {
            interpolation_depth -= 1
          }
          index += 1
        } else {
          index += 1
        }
      } else if code == '/' && next == '/' {
        break
      } else if (code == '#' || code == '$') && next == '|' {
        function_keyword_line = 0
        pending_function_prefix_line = 0
        pending_function_prefix_paren_depth = 0
        pending_impl_start_line = 0
        pending_impl_saw_with = false
        break
      } else if code == '/' && next == '*' {
        block_comment_depth = 1
        index += 2
      } else if code == '"' || code == '\'' {
        function_keyword_line = 0
        pending_function_prefix_line = 0
        pending_function_prefix_paren_depth = 0
        pending_impl_start_line = 0
        pending_impl_saw_with = false
        quote = code
        escaped = false
        index += 1
      } else if is_moonbit_outline_identifier_start(code) {
        let start = index
        index += 1
        while index < line.length() &&
              is_moonbit_outline_identifier_continue(line[index].to_int()) {
          index += 1
        }
        let word = line[start:index].to_owned()
        if brace_depth == 0 && declaration_start_line == 0 {
          if word == "declare" {
            pending_bodyless_declaration = true
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
          } else if pending_bodyless_declaration && word == "fn" {
            pending_bodyless_declaration = false
          } else if pending_bodyless_declaration &&
            (
              word == "pub" ||
              word == "priv" ||
              word == "all" ||
              word == "open" ||
              word == "async"
            ) {
            ()
          } else if pending_bodyless_declaration {
            pending_bodyless_declaration = false
          } else if function_keyword_line > 0 &&
            function_keyword_bracket_depth == 0 {
            declaration_start_line = function_keyword_line
            function_keyword_line = 0
            paren_depth = 0
            bracket_depth = 0
          } else if word == "pub" || word == "priv" || word == "async" {
            if pending_function_prefix_line == 0 {
              pending_function_prefix_line = line_number
            }
          } else if pending_function_prefix_line > 0 &&
            pending_function_prefix_paren_depth > 0 &&
            (word == "all" || word == "open") {
            ()
          } else if word == "impl" {
            pending_impl_start_line = if pending_function_prefix_line > 0 {
              pending_function_prefix_line
            } else {
              line_number
            }
            pending_impl_saw_with = false
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          } else if pending_impl_start_line > 0 && word == "with" {
            pending_impl_saw_with = true
          } else if pending_impl_start_line > 0 &&
            pending_impl_saw_with &&
            word == "async" {
            ()
          } else if pending_impl_start_line > 0 && word == "fn" {
            function_keyword_line = if pending_impl_saw_with {
              pending_impl_start_line
            } else {
              line_number
            }
            function_keyword_bracket_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
          } else if !line_saw_equals && word == "fn" {
            function_keyword_line = if pending_function_prefix_line > 0 {
              pending_function_prefix_line
            } else {
              line_number
            }
            function_keyword_bracket_depth = 0
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          } else {
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          }
        }
      } else {
        if function_keyword_line > 0 {
          match code {
            '[' => function_keyword_bracket_depth += 1
            ']' if function_keyword_bracket_depth > 0 =>
              function_keyword_bracket_depth -= 1
            '@' if function_keyword_bracket_depth == 0 => ()
            _ if code != ' ' &&
              code != '\t' &&
              function_keyword_bracket_depth == 0 => {
              function_keyword_line = 0
              function_keyword_bracket_depth = 0
            }
            _ => ()
          }
        }
        if pending_function_prefix_line > 0 && function_keyword_line == 0 {
          match code {
            '(' => pending_function_prefix_paren_depth += 1
            ')' if pending_function_prefix_paren_depth > 0 =>
              pending_function_prefix_paren_depth -= 1
            _ if code != ' ' && code != '\t' => {
              pending_function_prefix_line = 0
              pending_function_prefix_paren_depth = 0
            }
            _ => ()
          }
        }
        if pending_impl_start_line > 0 && function_keyword_line == 0 {
          match code {
            '=' | ';' | '{' => {
              pending_impl_start_line = 0
              pending_impl_saw_with = false
            }
            _ => ()
          }
        }
        if declaration_start_line > 0 && body_start_line == 0 {
          match code {
            '(' => paren_depth += 1
            ')' => if paren_depth > 0 { paren_depth -= 1 }
            '[' => bracket_depth += 1
            ']' => if bracket_depth > 0 { bracket_depth -= 1 }
            '=' if paren_depth == 0 && bracket_depth == 0 => {
              declaration_start_line = 0
              pending_function_prefix_line = 0
              pending_function_prefix_paren_depth = 0
              pending_impl_start_line = 0
              pending_impl_saw_with = false
              line_saw_equals = true
            }
            _ => ()
          }
        } else if code == '=' && brace_depth == 0 {
          line_saw_equals = true
        }
        if code == '{' {
          if brace_depth == 0 &&
            declaration_start_line > 0 &&
            body_start_line == 0 &&
            paren_depth == 0 &&
            bracket_depth == 0 {
            body_start_line = line_number
          }
          if brace_depth == 0 && declaration_start_line == 0 {
            pending_bodyless_declaration = false
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
          }
          brace_depth += 1
        } else if code == '}' && brace_depth > 0 {
          brace_depth -= 1
          if brace_depth == 0 && body_start_line > 0 {
            folds.push({
              declaration_start_line_number: declaration_start_line,
              body_start_line_number: body_start_line,
              body_end_line_number: line_number,
            })
            function_keyword_line = 0
            function_keyword_bracket_depth = 0
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
            declaration_start_line = 0
            body_start_line = 0
            paren_depth = 0
            bracket_depth = 0
          }
        }
        index += 1
      }
    }
  }
  if comment_run_start_line > 0 &&
    snapshot.line_count() > comment_run_start_line {
    comment_runs.push({
      start_line_number: comment_run_start_line,
      end_line_number: snapshot.line_count(),
    })
  }
  { function_bodies: folds, comment_runs }
}

///|
/// Whether the regions already carry host-computed MoonBit outline folds —
/// function bodies or comment runs — meaning the outline transform has been
/// applied to this generation of ranges.
fn has_moonbit_outline_folding_ranges(
  regions : @folding_browser.FoldingRegions,
) -> Bool {
  for index in 0..<regions.length() {
    if regions.get_type(index) is Some(range_type) &&
      (
        range_type == @folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE ||
        range_type == COMMENT_RUN_FOLDING_RANGE_TYPE
      ) {
      return true
    }
  }
  false
}

///|
/// One host-computed outline fold in document order. Function bodies protect
/// their declaration lines and fold from the opening-brace line; comment runs
/// protect only their own span and fold from their first line.
priv struct MoonbitOutlineFold {
  /// First line of the protected construct. Provider ranges reaching into
  /// `protected_start_line_number..=fold_end_line_number` are replaced by the
  /// host fold unless they sit strictly inside the folded span.
  protected_start_line_number : Int
  fold_start_line_number : Int
  fold_end_line_number : Int
  range_type : String
}

///|
fn MoonbitCommentRunFold::to_outline_fold(
  self : MoonbitCommentRunFold,
) -> MoonbitOutlineFold {
  {
    protected_start_line_number: self.start_line_number,
    fold_start_line_number: self.start_line_number,
    fold_end_line_number: self.end_line_number,
    range_type: COMMENT_RUN_FOLDING_RANGE_TYPE,
  }
}

///|
/// Merges the two document-ordered, mutually disjoint scan results into one
/// document-ordered host-fold list.
fn moonbit_outline_folds(
  source_folds : MoonbitSourceFolds,
) -> Array[MoonbitOutlineFold] {
  let outline_folds : Array[MoonbitOutlineFold] = []
  let mut comment_index = 0
  for body_fold in source_folds.function_bodies {
    while comment_index < source_folds.comment_runs.length() &&
          source_folds.comment_runs[comment_index].start_line_number <
          body_fold.declaration_start_line_number {
      outline_folds.push(
        source_folds.comment_runs[comment_index].to_outline_fold(),
      )
      comment_index += 1
    }
    outline_folds.push({
      protected_start_line_number: body_fold.declaration_start_line_number,
      fold_start_line_number: body_fold.body_start_line_number,
      fold_end_line_number: body_fold.body_end_line_number,
      range_type: @folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE,
    })
  }
  while comment_index < source_folds.comment_runs.length() {
    outline_folds.push(
      source_folds.comment_runs[comment_index].to_outline_fold(),
    )
    comment_index += 1
  }
  outline_folds
}

///|
/// Replaces provider folds that would hide a function header or split a
/// plain-comment run with host folds: bodies fold from the opening-brace
/// line, comment runs from their first comment line. Ordinary ranges outside
/// each construct and nested ranges strictly inside a folded span retain
/// their current state.
fn moonbit_outline_folding_regions(
  snapshot : @model.TextSnapshot,
  regions : @folding_browser.FoldingRegions,
  limit : Int,
) -> @folding_browser.FoldingRegions {
  let outline_folds = moonbit_outline_folds(moonbit_source_folds(snapshot))
  if outline_folds.length() == 0 || has_moonbit_outline_folding_ranges(regions) {
    return regions
  }
  let capped_limit = limit.max(0).min(@folding_browser.MAX_FOLDING_REGIONS)
  if capped_limit == 0 && regions.length() == 0 {
    return regions
  }
  let retained_ranges : Array[@folding_browser.FoldRange] = []
  let mut outline_index = 0
  for index in 0..<regions.length() {
    let range = regions.to_fold_range(index)
    while outline_index < outline_folds.length() &&
          outline_folds[outline_index].fold_end_line_number <
          range.start_line_number {
      outline_index += 1
    }
    if outline_index == outline_folds.length() ||
      range.end_line_number <
      outline_folds[outline_index].protected_start_line_number {
      retained_ranges.push(range)
    } else {
      let outline_fold = outline_folds[outline_index]
      if range.start_line_number > outline_fold.fold_start_line_number &&
        range.end_line_number <= outline_fold.fold_end_line_number {
        retained_ranges.push(range)
      }
    }
  }

  let foldable_outline_folds : Array[MoonbitOutlineFold] = []
  for outline_fold in outline_folds {
    if outline_fold.fold_end_line_number > outline_fold.fold_start_line_number {
      foldable_outline_folds.push(outline_fold)
    }
  }
  // Both inputs are already in document order. Merge them directly and stop
  // at the configured/provider limit instead of sorting or allowing host
  // ranges to bypass the limit enforced by the indentation provider. A body
  // that closes on its opening-brace line protects the signature above but
  // contributes no zero-height replacement range here.
  let ranges : Array[@folding_browser.FoldRange] = []
  let mut retained_index = 0
  outline_index = 0
  while ranges.length() < capped_limit &&
        (
          retained_index < retained_ranges.length() ||
          outline_index < foldable_outline_folds.length()
        ) {
    let take_outline = if outline_index == foldable_outline_folds.length() {
      false
    } else if retained_index == retained_ranges.length() {
      true
    } else {
      let outline_fold = foldable_outline_folds[outline_index]
      let retained = retained_ranges[retained_index]
      outline_fold.fold_start_line_number < retained.start_line_number ||
      (
        outline_fold.fold_start_line_number == retained.start_line_number &&
        outline_fold.fold_end_line_number >= retained.end_line_number
      )
    }
    if take_outline {
      let outline_fold = foldable_outline_folds[outline_index]
      ranges.push(
        FoldRange(
          outline_fold.fold_start_line_number,
          outline_fold.fold_end_line_number,
          type_=outline_fold.range_type,
        ),
      )
      outline_index += 1
    } else {
      ranges.push(retained_ranges[retained_index])
      retained_index += 1
    }
  }
  @folding_browser.FoldingRegions::from_fold_ranges(ranges)
}
