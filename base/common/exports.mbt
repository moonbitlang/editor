///|
/// Validation failure raised by the documented URI constructors.
pub suberror UriError {
  UriError(String)
} derive(Debug)

///|
/// A new position derived from this one. Retained as part of the documented
/// coordinate-value contract.
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
/// Derives a shifted position, clamping both axes to at least one.
pub fn Position::delta(
  self : Position,
  delta_line_number? : Int = 0,
  delta_column? : Int = 0,
) -> Position {
  self.with_(
    line_number=(self.line_number + delta_line_number).clamp(
      min=1,
      max=2147483647,
    ),
    column=(self.column + delta_column).clamp(min=1, max=2147483647),
  )
}

///|
/// Compares two positions by line and then column.
pub fn Position::compare(a : Position, b : Position) -> Int {
  if a.line_number == b.line_number {
    return a.column - b.column
  }
  a.line_number - b.line_number
}

///|
/// Indicates whether this half-open line range contains the line number.
pub fn LineRange::contains(self : LineRange, line_number : Int) -> Bool {
  self.start_line_number <= line_number &&
  line_number < self.end_line_number_exclusive
}

///|
/// Joins arrays of already sorted line ranges into one normalized array
/// without mutating caller arrays.
pub fn LineRange::join_many(
  line_ranges : Array[Array[LineRange]],
) -> Array[LineRange] {
  guard line_ranges is [first, ..] else { return [] }
  let result = for
    ranges in line_ranges[1:]
    result = LineRangeSet(normalized_ranges=first.copy()) {
    continue result.get_union(LineRangeSet(normalized_ranges=ranges.copy()))
  } nobreak {
    result
  }
  result.ranges()
}

///|
/// The host platform flag retained for the documented URI case-policy
/// relationship.
pub let is_linux : Bool = host_platform == Linux

///|
/// Compares the selected UTF-16 substrings without allocating slices.
pub fn compare_substring(
  a : String,
  b : String,
  a_start? : Int = 0,
  a_end? : Int = -1,
  b_start? : Int = 0,
  b_end? : Int = -1,
) -> Int {
  compare_substring_impl(a, b, a_start~, a_end~, b_start~, b_end~)
}

///|
/// Compares the selected UTF-16 substrings with the documented case-folding
/// policy and without allocating slices.
pub fn compare_substring_ignore_case(
  a : String,
  b : String,
  a_start? : Int = 0,
  a_end? : Int = -1,
  b_start? : Int = 0,
  b_end? : Int = -1,
) -> Int {
  compare_substring_ignore_case_impl(a, b, a_start~, a_end~, b_start~, b_end~)
}

///|
/// Case-insensitive whole-string equality retained as documented text API.
pub fn equals_ignore_case(a : String, b : String) -> Bool {
  equals_ignore_case_impl(a, b)
}

///|
/// Case-insensitive prefix matching retained as documented text API.
pub fn starts_with_ignore_case(str : String, candidate : String) -> Bool {
  starts_with_ignore_case_impl(str, candidate)
}

///|
/// Explicit Win32 path operations retained as the documented host-neutral
/// path contract.
pub fn Win32::resolve(path_segments : Array[String]) -> String {
  Win32::resolve_impl(path_segments)
}

///|
pub fn Win32::normalize(path : String) -> String {
  Win32::normalize_impl(path)
}

///|
pub fn Win32::is_absolute(path : String) -> Bool {
  Win32::is_absolute_impl(path)
}

///|
pub fn Win32::join(paths : Array[String]) -> String {
  Win32::join_impl(paths)
}

///|
pub fn Win32::relative(from : String, to : String) -> String {
  Win32::relative_impl(from, to)
}

///|
pub fn Win32::dirname(path : String) -> String {
  Win32::dirname_impl(path)
}

///|
pub fn Win32::basename(path : String, suffix? : String) -> String {
  Win32::basename_impl(path, suffix?)
}

///|
pub fn Win32::extname(path : String) -> String {
  Win32::extname_impl(path)
}

///|
pub fn Win32::sep() -> String {
  Win32::sep_impl()
}

///|
pub fn Win32::delimiter() -> String {
  Win32::delimiter_impl()
}

///|
/// Explicit POSIX path operations retained as the documented host-neutral
/// path contract.
pub fn Posix::resolve(path_segments : Array[String]) -> String {
  Posix::resolve_impl(path_segments)
}

///|
pub fn Posix::normalize(path : String) -> String {
  Posix::normalize_impl(path)
}

///|
pub fn Posix::is_absolute(path : String) -> Bool {
  Posix::is_absolute_impl(path)
}

///|
pub fn Posix::join(paths : Array[String]) -> String {
  Posix::join_impl(paths)
}

///|
pub fn Posix::relative(from : String, to : String) -> String {
  Posix::relative_impl(from, to)
}

///|
pub fn Posix::dirname(path : String) -> String {
  Posix::dirname_impl(path)
}

///|
pub fn Posix::basename(path : String, suffix? : String) -> String {
  Posix::basename_impl(path, suffix?)
}

///|
pub fn Posix::extname(path : String) -> String {
  Posix::extname_impl(path)
}

///|
pub fn Posix::sep() -> String {
  Posix::sep_impl()
}

///|
pub fn Posix::delimiter() -> String {
  Posix::delimiter_impl()
}

///|
/// URI comparison/path policies retained as the documented resource identity
/// contract.
pub let ext_uri : ExtUri = ext_uri_impl

///|
pub let ext_uri_biased_ignore_path_case : ExtUri = ext_uri_biased_ignore_path_case_impl

///|
pub let ext_uri_ignore_path_case : ExtUri = ext_uri_ignore_path_case_impl

///|
pub fn ExtUri::compare(
  self : ExtUri,
  uri1 : Uri,
  uri2 : Uri,
  ignore_fragment? : Bool = false,
) -> Int {
  self.compare_impl(uri1, uri2, ignore_fragment~)
}

///|
pub fn ExtUri::is_equal(
  self : ExtUri,
  uri1 : Uri?,
  uri2 : Uri?,
  ignore_fragment? : Bool = false,
) -> Bool {
  self.is_equal_impl(uri1, uri2, ignore_fragment~)
}

///|
pub fn ExtUri::get_comparison_key(
  self : ExtUri,
  uri : Uri,
  ignore_fragment? : Bool = false,
) -> String {
  self.get_comparison_key_impl(uri, ignore_fragment~)
}

///|
pub fn ExtUri::ignore_path_casing(self : ExtUri, uri : Uri) -> Bool {
  self.ignore_path_casing_impl(uri)
}

///|
pub fn ExtUri::is_equal_or_parent(
  self : ExtUri,
  base : Uri,
  parent_candidate : Uri,
  ignore_fragment? : Bool = false,
) -> Bool {
  self.is_equal_or_parent_impl(base, parent_candidate, ignore_fragment~)
}

///|
pub fn ExtUri::join_path(
  self : ExtUri,
  resource : Uri,
  path_fragment : Array[String],
) -> Uri {
  self.join_path_impl(resource, path_fragment)
}

///|
pub fn ExtUri::basename_or_authority(self : ExtUri, resource : Uri) -> String {
  self.basename_or_authority_impl(resource)
}

///|
pub fn ExtUri::basename(
  self : ExtUri,
  resource : Uri,
  suffix? : String,
) -> String {
  self.basename_impl(resource, suffix?)
}

///|
pub fn ExtUri::extname(self : ExtUri, resource : Uri) -> String {
  self.extname_impl(resource)
}

///|
pub fn ExtUri::dirname(self : ExtUri, resource : Uri) -> Uri {
  self.dirname_impl(resource)
}

///|
pub fn ExtUri::normalize_path(self : ExtUri, resource : Uri) -> Uri {
  self.normalize_path_impl(resource)
}

///|
pub fn ExtUri::relative_path(self : ExtUri, from : Uri, to : Uri) -> String? {
  self.relative_path_impl(from, to)
}

///|
pub fn ExtUri::resolve_path(self : ExtUri, base : Uri, path : String) -> Uri {
  self.resolve_path_impl(base, path)
}

///|
pub fn ExtUri::is_absolute_path(self : ExtUri, resource : Uri) -> Bool {
  self.is_absolute_path_impl(resource)
}

///|
pub fn ExtUri::is_equal_authority(
  self : ExtUri,
  a1 : String,
  a2 : String,
) -> Bool {
  self.is_equal_authority_impl(a1, a2)
}

///|
pub fn ExtUri::has_trailing_path_separator(
  self : ExtUri,
  resource : Uri,
  sep? : String,
) -> Bool {
  self.has_trailing_path_separator_impl(resource, sep?)
}

///|
pub fn ExtUri::remove_trailing_path_separator(
  self : ExtUri,
  resource : Uri,
  sep? : String,
) -> Uri {
  self.remove_trailing_path_separator_impl(resource, sep?)
}

///|
/// Creates the documented character-code set abstraction.
pub fn CharacterSet::CharacterSet() -> CharacterSet {
  CharacterSet::new_impl()
}

///|
pub fn CharacterSet::add(self : CharacterSet, char_code : Int) -> Unit {
  self.add_impl(char_code)
}

///|
pub fn CharacterSet::has(self : CharacterSet, char_code : Int) -> Bool {
  self.has_impl(char_code)
}

///|
pub fn Range::contains_range(self : Range, other : Range) -> Bool {
  self.contains_range_impl(other)
}

///|
pub fn Range::strict_contains_range(self : Range, other : Range) -> Bool {
  self.strict_contains_range_impl(other)
}

///|
pub fn Range::are_intersecting(a : Range, b : Range) -> Bool {
  Range::are_intersecting_impl(a, b)
}

///|
/// Hashes URI identity components while excluding lazy formatting caches.
pub impl Hash for Uri with fn hash_combine(self, hasher) {
  hasher.combine(self.scheme)
  hasher.combine(self.authority)
  hasher.combine(self.path)
  hasher.combine(self.query)
  hasher.combine(self.fragment)
}

///|
/// Returns a URI with selected components replaced.
pub fn Uri::with_(
  self : Uri,
  scheme? : String,
  authority? : String,
  path? : String,
  query? : String,
  fragment? : String,
) -> Uri raise UriError {
  self.with_impl(scheme?, authority?, path?, query?, fragment?)
}

///|
/// Joins path fragments onto a URI path.
pub fn Uri::join_path(uri : Uri, path_fragment : Array[String]) -> Uri {
  Uri::join_path_impl(uri, path_fragment)
}

///|
/// Returns the URI's platform-specific filesystem path.
pub fn Uri::fs_path(self : Uri) -> String {
  self.fs_path_impl()
}

///|
/// Computes a platform-specific filesystem path with explicit drive-letter
/// casing policy.
pub fn uri_to_fs_path(uri : Uri, keep_drive_letter_casing : Bool) -> String {
  uri_to_fs_path_impl(uri, keep_drive_letter_casing)
}
