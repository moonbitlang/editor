///|
fn is_moonbit_identifier_start(code : Int) -> Bool {
  (code >= 'a' && code <= 'z') ||
  (code >= 'A' && code <= 'Z') ||
  code == '_' ||
  code >= 0x80
}

///|
fn is_moonbit_identifier_continue(code : Int) -> Bool {
  is_moonbit_identifier_start(code) || (code >= '0' && code <= '9')
}

///|
fn line_has_code_before(line : String, end : Int) -> Bool {
  for index in 0..<end {
    let code = line[index].to_int()
    if code != ' ' && code != '\t' {
      return true
    }
  }
  false
}

///|
/// Finds declaration-sized ranges for top-level MoonBit functions. This is a
/// deliberately narrow lexical scan: it recognizes the `fn` declaration token
/// at brace depth zero, ignores comments/string literals, rejects `declare`
/// and `=`-backed bodyless declarations plus function values, accepts
/// package-qualified method names, and balances the body braces. It does not
/// attempt to build or expose a MoonBit syntax tree.
fn moonbit_signature_folding_ranges(
  snapshot : @model.TextSnapshot,
) -> Array[@folding_browser.SignatureFoldingRange] {
  let ranges : Array[@folding_browser.SignatureFoldingRange] = []
  let mut block_comment_depth = 0
  let mut brace_depth = 0
  let mut function_keyword_line = 0
  let mut function_keyword_bracket_depth = 0
  let mut pending_function_prefix_line = 0
  let mut pending_function_prefix_paren_depth = 0
  let mut pending_impl_start_line = 0
  let mut pending_impl_saw_with = false
  let mut pending_bodyless_declaration = false
  let mut function_start_line = 0
  let mut body_start_line = 0
  let mut first_hidden_line = 0
  let mut hidden_suffix_line = 0
  let mut hidden_suffix_column = 0
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
          // An escaped backslash before `{` is literal text, not the start of
          // a string interpolation.
          escaped = false
        } else if quote == '"' && code == '\\' && next == '{' {
          // A normal MoonBit string can enter an interpolation expression,
          // which can itself contain quoted strings and further
          // interpolations. Record the brace depth that resumes this string.
          interpolation_depth += 1
          interpolation_resume_depths.push(interpolation_depth)
          quote = 0
          escaped = false
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
        // MoonBit's raw/interpolated multiline string lines: the remainder is
        // string content, not structural source, even when it contains braces.
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
      } else if is_moonbit_identifier_start(code) {
        let start = index
        index += 1
        while index < line.length() &&
              is_moonbit_identifier_continue(line[index].to_int()) {
          index += 1
        }
        let word = line[start:index].to_owned()
        if brace_depth == 0 && function_start_line == 0 {
          if word == "declare" {
            // `declare fn` has a signature but no MoonBit body. Carry the
            // modifier to the next declaration-kind token.
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
            // Visibility and function modifiers, including the identifier
            // inside `pub(all)`/`pub(open)`, remain part of the declaration.
          } else if pending_bodyless_declaration {
            // A different declared item (for example `declare type`) must not
            // suppress a later, independent function declaration.
            pending_bodyless_declaration = false
          } else if function_keyword_line > 0 &&
            function_keyword_bracket_depth == 0 {
            // A declaration has a name after `fn`; function values have `(`
            // immediately after it and are rejected in the delimiter branch.
            function_start_line = function_keyword_line
            function_keyword_line = 0
            paren_depth = 0
            bracket_depth = 0
          } else if word == "pub" || word == "priv" || word == "async" {
            // MoonBit permits declaration modifiers to be split onto lines
            // before `fn`. Keep that prefix in the fold range so an enclosing
            // indentation fold cannot hide the function signature.
            if pending_function_prefix_line == 0 {
              pending_function_prefix_line = line_number
            }
          } else if pending_function_prefix_line > 0 &&
            pending_function_prefix_paren_depth > 0 &&
            (word == "all" || word == "open") {
            // The visibility qualifier in `pub(all)` / `pub(open)`.
          } else if word == "impl" {
            // MoonBit's formatter splits a long `impl ... with fn ...` after
            // `with`. Treat the implementation header as the declaration
            // prefix so the provider's enclosing indentation fold cannot hide
            // the method signature.
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
            // An async method modifier remains between `with` and `fn`.
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
            // Package-qualified method declarations begin with `@pkg.Type`.
            // The first identifier after `@` is enough to establish that this
            // is a named declaration; the rest remains part of its signature.
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
        if function_start_line > 0 && body_start_line == 0 {
          match code {
            '(' => paren_depth += 1
            ')' => if paren_depth > 0 { paren_depth -= 1 }
            '[' => bracket_depth += 1
            ']' => if bracket_depth > 0 { bracket_depth -= 1 }
            '=' if paren_depth == 0 && bracket_depth == 0 => {
              // `extern ... fn ... = ...` and top-level function values do not
              // own a brace-delimited body.
              function_start_line = 0
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
            function_start_line > 0 &&
            body_start_line == 0 &&
            paren_depth == 0 &&
            bracket_depth == 0 {
            body_start_line = line_number
            let mut suffix_start = index
            while suffix_start > 0 &&
                  (
                    line[suffix_start - 1].to_int() == ' ' ||
                    line[suffix_start - 1].to_int() == '\t'
                  ) {
              suffix_start -= 1
            }
            if line_has_code_before(line, suffix_start) {
              first_hidden_line = line_number + 1
              hidden_suffix_line = line_number
              // Columns are 1-based UTF-16 offsets; include whitespace before
              // the delimiter so the visible signature has no trailing gap.
              hidden_suffix_column = suffix_start + 1
            } else {
              first_hidden_line = line_number
              hidden_suffix_line = line_number
              hidden_suffix_column = 0
            }
          }
          if brace_depth == 0 && function_start_line == 0 {
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
            if line_number > function_start_line {
              ranges.push(
                SignatureFoldingRange(
                  function_start_line, line_number, first_hidden_line, hidden_suffix_line,
                  hidden_suffix_column,
                ),
              )
            }
            function_keyword_line = 0
            function_keyword_bracket_depth = 0
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
            function_start_line = 0
            body_start_line = 0
            first_hidden_line = 0
            hidden_suffix_line = 0
            hidden_suffix_column = 0
            paren_depth = 0
            bracket_depth = 0
          }
        }
        index += 1
      }
    }
  }
  ranges
}
