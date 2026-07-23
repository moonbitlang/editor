///|
/// Root-relative source path accepted from UI or protocol input after
/// normalization rejects absolute paths, parent traversal, and NUL bytes.
pub struct SourcePath {
  value : String
} derive(Eq, Debug)

///|
/// Validation failures for user-facing source paths and document URIs.
pub(all) enum SourceError {
  MissingPath
  InvalidPath
} derive(Eq, Debug)

///|
/// Stable protocol/debug label for source validation failures.
pub fn SourceError::to_string(self : SourceError) -> String {
  match self {
    MissingPath => "MissingPath"
    InvalidPath => "InvalidPath"
  }
}

///|
/// Result wrapper used instead of raising while normalizing source paths.
pub enum SourcePathResult {
  ParsedSourcePath(SourcePath)
  SourcePathError(SourceError)
} derive(Eq, Debug)

///|
/// Normalizes a user-provided workspace path into a safe root-relative path.
pub fn SourcePath::normalize_root_relative_path(
  raw_path : String,
) -> SourcePathResult {
  if raw_path == "" {
    return SourcePathError(MissingPath)
  }
  if contains_null(raw_path) {
    return SourcePathError(InvalidPath)
  }
  let slash_path = raw_path.replace_all(old="\\", new="/")
  if slash_path.has_prefix("/") ||
    slash_path.has_prefix("//") ||
    is_windows_drive_path(slash_path) {
    return SourcePathError(InvalidPath)
  }

  let segments = []
  for segment_view in slash_path.split("/") {
    let segment = segment_view.to_owned()
    if segment == ".." {
      return SourcePathError(InvalidPath)
    }
    if segment != "" && segment != "." {
      segments.push(segment)
    }
  }
  if segments.length() == 0 {
    return SourcePathError(InvalidPath)
  }

  let mut normalized = segments[0]
  for i in 1..<segments.length() {
    normalized = normalized + "/" + segments[i]
  }
  ParsedSourcePath({ value: normalized })
}

///|
/// Returns the normalized root-relative path string.
pub fn SourcePath::to_string(self : SourcePath) -> String {
  self.value
}

///|
/// Display label for a source path; currently the normalized path itself.
pub fn SourcePath::display_name(self : SourcePath) -> String {
  self.value
}

///|
/// Converts a normalized source path to the local file URI convention used by
/// simple embedders: `file:///local/<path>` (the old string concatenation
/// made `local` a URI authority, i.e. a UNC-shaped fsPath).
pub fn SourcePath::file_uri(self : SourcePath) -> @base_common.Uri {
  @base_common.Uri::file("/local/" + self.value)
}

///|
/// Maps common source extensions to the language ids used by tokenizer and
/// feature registries.
pub fn infer_language_id(path_or_name : String) -> String {
  if path_or_name.has_suffix(".mbt") || path_or_name.has_suffix(".mbt.md") {
    "moonbit"
  } else if path_or_name.has_suffix(".js") || path_or_name.has_suffix(".mjs") {
    "javascript"
  } else if path_or_name.has_suffix(".ts") {
    "typescript"
  } else if path_or_name.has_suffix(".json") {
    "json"
  } else if path_or_name.has_suffix(".md") {
    "markdown"
  } else if path_or_name.has_suffix(".css") {
    "css"
  } else if path_or_name.has_suffix(".html") {
    "html"
  } else if path_or_name.has_suffix(".txt") {
    "plaintext"
  } else {
    "moonbit"
  }
}

///|
fn contains_null(value : String) -> Bool {
  for i in 0..<value.length() {
    if value[i].to_int() == 0 {
      return true
    }
  }
  false
}

///|
fn is_windows_drive_path(path : String) -> Bool {
  path.length() >= 2 &&
  is_ascii_alpha(path[0].to_int()) &&
  path[1].to_int() == 58
}

///|
fn is_ascii_alpha(unit : Int) -> Bool {
  (65 <= unit && unit <= 90) || (97 <= unit && unit <= 122)
}
