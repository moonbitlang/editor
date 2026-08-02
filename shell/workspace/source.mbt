///|
/// Converts a normalized source path to the local file URI convention used by
/// simple embedders: `file:///local/<path>` (the old string concatenation
/// made `local` a URI authority, i.e. a UNC-shaped fsPath).
fn SourcePath::file_uri(self : SourcePath) -> @base_common.Uri {
  @base_common.Uri::file("/local/\{self.value}")
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
  for unit in value.code_units() {
    if unit == 0 {
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
