///| Faithful ports of a few `base/common/strings.ts` helpers from the
/// checked-in vscode source. Kept here, the
/// lowest-level shared package, so model/view code shares one definition.

///|
/// `0xD800 <= charCode <= 0xDBFF`. Mirrors `strings.isHighSurrogate`; the std
/// `Int::is_leading_surrogate` is the identical range check.
pub fn is_high_surrogate(char_code : Int) -> Bool {
  char_code.is_leading_surrogate()
}

///|
/// `0xDC00 <= charCode <= 0xDFFF`. Mirrors `strings.isLowSurrogate`; the std
/// `Int::is_trailing_surrogate` is the identical range check.
pub fn is_low_surrogate(char_code : Int) -> Bool {
  char_code.is_trailing_surrogate()
}

///|
/// Whether `text` contains any right-to-left character. Mirrors
/// `strings.containsRTL` over the common BMP RTL blocks (Hebrew/Arabic
/// `U+0590..U+08FF`, Arabic Presentation Forms-A `U+FB1D..U+FDFF` and Forms-B
/// `U+FE70..U+FEFF`); supplementary-plane RTL is not detected, matching the
/// viewer's existing simplified port.
pub fn contains_rtl(text : String) -> Bool {
  for i in 0..<text.length() {
    let code = text[i].to_int()
    if (code >= 0x0590 && code <= 0x08ff) ||
      (code >= 0xfb1d && code <= 0xfdff) ||
      (code >= 0xfe70 && code <= 0xfeff) {
      return true
    }
  }
  false
}

///|
/// Index of the first non-whitespace (non-space, non-tab) character, or `-1`.
/// Mirrors `strings.firstNonWhitespaceIndex`.
pub fn first_non_whitespace_index(text : String) -> Int {
  for i in 0..<text.length() {
    let code = text[i].to_int()
    if code != 32 && code != 9 {
      return i
    }
  }
  -1
}

///|
/// Index of the last non-whitespace (non-space, non-tab) character, or `-1`.
/// Mirrors `strings.lastNonWhitespaceIndex`.
pub fn last_non_whitespace_index(text : String) -> Int {
  for i = text.length() - 1; i >= 0; i = i - 1 {
    let code = text[i].to_int()
    if code != 32 && code != 9 {
      return i
    }
  }
  -1
}

///|
/// Whether `char_code` is a full-width character (CJK and related blocks).
/// Mirrors `strings.isFullWidthCharacter`.
pub fn is_full_width_character(char_code : Int) -> Bool {
  (char_code >= 0x2E80 && char_code <= 0xD7AF) ||
  (char_code >= 0xF900 && char_code <= 0xFAFF) ||
  (char_code >= 0xFF01 && char_code <= 0xFF5E) ||
  (char_code >= 0xFFE0 && char_code <= 0xFFE6)
}

///|
/// Maps `n` to a single letter (`a..z` then `A..Z`, wrapping). Mirrors
/// `strings.singleLetterHash`; Monaco uses it to prefix per-instance id
/// namespaces (model decoration ids, whitespace ids).
pub fn single_letter_hash(n : Int) -> String {
  let letters_cnt = 'Z'.to_int() - 'A'.to_int() + 1
  let n = n % (2 * letters_cnt)
  if n < letters_cnt {
    Int::unsafe_to_char('a'.to_int() + n).to_string()
  } else {
    Int::unsafe_to_char('A'.to_int() + n - letters_cnt).to_string()
  }
}

///|
/// Mirrors `strings.compare` (strings.ts:343): JS `<`/`>` on strings is
/// charwise UTF-16 code-unit lexicographic. Required because MoonBit's
/// built-in `String` compare is length-first (`"z" > "aa"` here, not there).
pub fn compare(a : String, b : String) -> Int {
  let a_len = a.length()
  let b_len = b.length()
  let len = if a_len < b_len { a_len } else { b_len }
  for i in 0..<len {
    let code_a = a[i].to_int()
    let code_b = b[i].to_int()
    if code_a < code_b {
      return -1
    } else if code_a > code_b {
      return 1
    }
  }
  if a_len < b_len {
    -1
  } else if a_len > b_len {
    1
  } else {
    0
  }
}

///|
/// Mirrors `strings.compareSubstring` (strings.ts:353).
pub fn compare_substring(
  a : String,
  b : String,
  a_start? : Int = 0,
  a_end? : Int = -1,
  b_start? : Int = 0,
  b_end? : Int = -1,
) -> Int {
  let a_end = if a_end < 0 { a.length() } else { a_end }
  let b_end = if b_end < 0 { b.length() } else { b_end }
  let mut a_start = a_start
  let mut b_start = b_start
  while a_start < a_end && b_start < b_end {
    let code_a = a[a_start].to_int()
    let code_b = b[b_start].to_int()
    if code_a < code_b {
      return -1
    } else if code_a > code_b {
      return 1
    }
    a_start += 1
    b_start += 1
  }
  let a_len = a_end - a_start
  let b_len = b_end - b_start
  if a_len < b_len {
    -1
  } else if a_len > b_len {
    1
  } else {
    0
  }
}

///|
/// Simple lowercase mapping for one UTF-16 code unit — the stand-in for JS
/// `String.prototype.toLowerCase` (MoonBit's `String::to_lower` is
/// ASCII-only). Covers ASCII, Latin-1, Latin Extended-A, Greek, Cyrillic and
/// fullwidth Latin; other scripts and the rare length-changing mappings
/// (e.g. `İ`) pass through unchanged — a documented deviation from the full
/// Unicode table JS applies.
fn to_lower_code_unit(code : Int) -> Int {
  if code >= 'A'.to_int() && code <= 'Z'.to_int() {
    return code + 32
  }
  // Latin-1 Supplement: À-Þ except ×
  if (code >= 0x00C0 && code <= 0x00D6) || (code >= 0x00D8 && code <= 0x00DE) {
    return code + 32
  }
  // Latin Extended-A: alternating upper/lower pairs
  if (code >= 0x0100 && code <= 0x0137) || (code >= 0x014A && code <= 0x0177) {
    return if code % 2 == 0 { code + 1 } else { code }
  }
  if (code >= 0x0139 && code <= 0x0148) || (code >= 0x0179 && code <= 0x017E) {
    return if code % 2 == 1 { code + 1 } else { code }
  }
  if code == 0x0178 {
    return 0x00FF // Ÿ → ÿ
  }
  // Greek
  if (code >= 0x0391 && code <= 0x03A1) || (code >= 0x03A3 && code <= 0x03AB) {
    return code + 32
  }
  // Cyrillic
  if code >= 0x0410 && code <= 0x042F {
    return code + 32
  }
  if code >= 0x0400 && code <= 0x040F {
    return code + 80
  }
  // Fullwidth Latin
  if code >= 0xFF21 && code <= 0xFF3A {
    return code + 32
  }
  code
}

///|
/// Per-code-unit `to_lower_code_unit` over a string — the JS
/// `toLowerCase()` call sites of the URI stack route through this so
/// non-ASCII authorities/paths fold the way Monaco's do.
fn to_lower_js(s : String) -> String {
  let mut changed = false
  for i in 0..<s.length() {
    if to_lower_code_unit(s[i].to_int()) != s[i].to_int() {
      changed = true
      break
    }
  }
  if !changed {
    return s
  }
  // Copy unchanged runs as substring chunks: every mapped unit is a BMP
  // non-surrogate, so chunk boundaries never split a surrogate pair.
  let sb = StringBuilder::new()
  let mut chunk_start = 0
  for i in 0..<s.length() {
    let code = s[i].to_int()
    let lowered = to_lower_code_unit(code)
    if lowered != code {
      if chunk_start < i {
        sb.write_string(s[chunk_start:i].to_owned())
      }
      sb.write_char(Int::unsafe_to_char(lowered))
      chunk_start = i + 1
    }
  }
  if chunk_start < s.length() {
    sb.write_string(s[chunk_start:].to_owned())
  }
  sb.to_string()
}

///|
/// Splits `text` on `\r\n` / `\r` / `\n`. Mirrors `strings.splitLines`
/// (strings.ts:251), whose split regex treats `\r\n` as one separator.
pub fn split_lines(text : String) -> Array[String] {
  let lines = []
  let len = text.length()
  let mut line_start = 0
  let mut i = 0
  while i < len {
    let code = text[i].to_int()
    if code == 13 { // \r
      lines.push(text[line_start:i].to_owned())
      if i + 1 < len && text[i + 1].to_int() == 10 {
        i += 1 // consume the \n of a \r\n pair
      }
      line_start = i + 1
    } else if code == 10 { // \n
      lines.push(text[line_start:i].to_owned())
      line_start = i + 1
    }
    i += 1
  }
  lines.push(text[line_start:].to_owned())
  lines
}

///|
/// Mirrors `strings.isLowerAsciiLetter` (strings.ts:428).
pub fn is_lower_ascii_letter(code : Int) -> Bool {
  code >= 'a'.to_int() && code <= 'z'.to_int()
}

///|
/// Mirrors `strings.isUpperAsciiLetter` (strings.ts:432).
pub fn is_upper_ascii_letter(code : Int) -> Bool {
  code >= 'A'.to_int() && code <= 'Z'.to_int()
}

///|
/// Mirrors `strings.compareSubstringIgnoreCase` (strings.ts:377): per-char
/// ASCII case-fold compare, falling back to lower-cased `compareSubstring`
/// when a non-ASCII unit is hit.
pub fn compare_substring_ignore_case(
  a : String,
  b : String,
  a_start? : Int = 0,
  a_end? : Int = -1,
  b_start? : Int = 0,
  b_end? : Int = -1,
) -> Int {
  let a_end = if a_end < 0 { a.length() } else { a_end }
  let b_end = if b_end < 0 { b.length() } else { b_end }
  let mut a_start = a_start
  let mut b_start = b_start
  while a_start < a_end && b_start < b_end {
    let mut code_a = a[a_start].to_int()
    let mut code_b = b[b_start].to_int()
    if code_a == code_b {
      // equal
      a_start += 1
      b_start += 1
      continue
    }
    if code_a >= 128 || code_b >= 128 {
      // not ASCII letters -> fallback to lower-casing strings
      return compare_substring(
        to_lower_js(a),
        to_lower_js(b),
        a_start~,
        a_end~,
        b_start~,
        b_end~,
      )
    }
    // map lower-case ascii letter onto upper-case variants
    // [97-122] (lower ascii) --> [65-90] (upper ascii)
    if is_lower_ascii_letter(code_a) {
      code_a -= 32
    }
    if is_lower_ascii_letter(code_b) {
      code_b -= 32
    }
    // compare both code points
    let diff = code_a - code_b
    if diff == 0 {
      a_start += 1
      b_start += 1
      continue
    }
    return diff
  }
  let a_len = a_end - a_start
  let b_len = b_end - b_start
  if a_len < b_len {
    -1
  } else if a_len > b_len {
    1
  } else {
    0
  }
}

///|
/// Mirrors `strings.equalsIgnoreCase` (strings.ts:436): length gate +
/// per-char case-fold compare.
pub fn equals_ignore_case(a : String, b : String) -> Bool {
  a.length() == b.length() && compare_substring_ignore_case(a, b) == 0
}

///|
/// Mirrors `strings.startsWithIgnoreCase` (strings.ts:444): length gate +
/// prefix case-fold compare.
pub fn starts_with_ignore_case(str : String, candidate : String) -> Bool {
  let len = candidate.length()
  len <= str.length() &&
  compare_substring_ignore_case(str, candidate, a_start=0, a_end=len) == 0
}

///|
/// HTML-escapes `&`, `<`, `>`. Mirrors `strings.escape` (note: unlike the view's
/// `escape_html`, it does not escape `"`, matching Monaco's `_tokenizeToString`).
pub fn escape(text : String) -> String {
  let sb = StringBuilder::new()
  for ch in text {
    match ch {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}
