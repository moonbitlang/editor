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
/// Finds brace-bodied top-level MoonBit functions without treating braces in
/// comments, strings, interpolations, or raw lines as source delimiters. The
/// scan is intentionally declaration-specific: `declare` and `=`-backed
/// functions have no MoonBit body, while qualified methods and formatted
/// `impl ... with fn ...` declarations are included.
fn moonbit_function_body_folds(
  snapshot : @model.TextSnapshot,
) -> Array[MoonbitFunctionBodyFold] {
  let folds : Array[MoonbitFunctionBodyFold] = []
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
  folds
}

///|
fn has_outline_body_folding_ranges(
  regions : @folding_browser.FoldingRegions,
) -> Bool {
  for index in 0..<regions.length() {
    if regions.get_type(index) ==
      Some(@folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE) {
      return true
    }
  }
  false
}

///|
/// Replaces provider folds that would hide a function header with one fold
/// beginning on the opening-brace line. Ordinary ranges outside each function
/// and nested ranges strictly inside its body retain their current state.
fn moonbit_outline_folding_regions(
  snapshot : @model.TextSnapshot,
  regions : @folding_browser.FoldingRegions,
  limit : Int,
) -> @folding_browser.FoldingRegions {
  let body_folds = moonbit_function_body_folds(snapshot)
  if body_folds.length() == 0 || has_outline_body_folding_ranges(regions) {
    return regions
  }
  let capped_limit = limit.max(0).min(@folding_browser.MAX_FOLDING_REGIONS)
  if capped_limit == 0 && regions.length() == 0 {
    return regions
  }
  let retained_ranges : Array[@folding_browser.FoldRange] = []
  let mut body_index = 0
  for index in 0..<regions.length() {
    let range = regions.to_fold_range(index)
    while body_index < body_folds.length() &&
          body_folds[body_index].body_end_line_number < range.start_line_number {
      body_index += 1
    }
    if body_index == body_folds.length() ||
      range.end_line_number <
      body_folds[body_index].declaration_start_line_number {
      retained_ranges.push(range)
    } else {
      let body_fold = body_folds[body_index]
      if range.start_line_number > body_fold.body_start_line_number &&
        range.end_line_number <= body_fold.body_end_line_number {
        retained_ranges.push(range)
      }
    }
  }

  let foldable_body_folds : Array[MoonbitFunctionBodyFold] = []
  for body_fold in body_folds {
    if body_fold.body_end_line_number > body_fold.body_start_line_number {
      foldable_body_folds.push(body_fold)
    }
  }
  // Both inputs are already in document order. Merge them directly and stop
  // at the configured/provider limit instead of sorting or allowing host
  // ranges to bypass the limit enforced by the indentation provider. A body
  // that closes on its opening-brace line protects the signature above but
  // contributes no zero-height replacement range here.
  let ranges : Array[@folding_browser.FoldRange] = []
  let mut retained_index = 0
  body_index = 0
  while ranges.length() < capped_limit &&
        (
          retained_index < retained_ranges.length() ||
          body_index < foldable_body_folds.length()
        ) {
    let take_body = if body_index == foldable_body_folds.length() {
      false
    } else if retained_index == retained_ranges.length() {
      true
    } else {
      let body_fold = foldable_body_folds[body_index]
      let retained = retained_ranges[retained_index]
      body_fold.body_start_line_number < retained.start_line_number ||
      (
        body_fold.body_start_line_number == retained.start_line_number &&
        body_fold.body_end_line_number >= retained.end_line_number
      )
    }
    if take_body {
      let body_fold = foldable_body_folds[body_index]
      ranges.push(
        FoldRange(
          body_fold.body_start_line_number,
          body_fold.body_end_line_number,
          type_=@folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE,
        ),
      )
      body_index += 1
    } else {
      ranges.push(retained_ranges[retained_index])
      retained_index += 1
    }
  }
  @folding_browser.FoldingRegions::from_fold_ranges(ranges)
}
