///|
/// Monaco-shaped language selector filter.
pub struct LanguageFilter {
  language : String?
  scheme : String?
  pattern : String?
} derive(Debug)

///|
/// Monaco-shaped language selector used during provider dispatch.
pub(all) enum LanguageSelector {
  LanguageId(String)
  LanguageFilter(LanguageFilter)
  LanguageSelectorList(Array[LanguageSelector])
} derive(Debug)

///|
/// Builds a selector filter with optional fields.
pub fn LanguageFilter::LanguageFilter(
  language? : String,
  scheme? : String,
  pattern? : String,
) -> LanguageFilter {
  { language, scheme, pattern }
}

///|
/// Whether this selector accepts a text model.
pub fn LanguageSelector::matches(
  self : LanguageSelector,
  model : @model.TextModel,
) -> Bool {
  match self {
    LanguageId(language_id) => model.language_id == language_id
    LanguageFilter(filter) => filter.matches(model)
    LanguageSelectorList(selectors) => {
      for selector in selectors {
        if selector.matches(model) {
          return true
        }
      }
      false
    }
  }
}

///|
/// Whether this filter accepts a text model.
pub fn LanguageFilter::matches(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Bool {
  match self.language {
    Some(language) => if language != model.language_id { return false }
    None => ()
  }
  match self.scheme {
    Some(scheme) => if scheme != model.uri.scheme { return false }
    None => ()
  }
  match self.pattern {
    // Monaco's `score()` matches globs against `uri.path` (leading slash
    // included); `path_pattern_matches` strips that slash so the relative
    // patterns hosts register keep matching.
    Some(pattern) => path_pattern_matches(pattern, model.uri.path)
    None => true
  }
}

///|
fn path_pattern_matches(pattern : String, path : String) -> Bool {
  if pattern == "" || pattern == "*" {
    return true
  }
  let path = if path.has_prefix("/") { path[1:].to_owned() } else { path }
  match pattern.find("*") {
    Some(index) => {
      let prefix = pattern[0:index].to_owned()
      let suffix = pattern[index + 1:].to_owned()
      path.has_prefix(prefix) && path.has_suffix(suffix)
    }
    None => path == pattern
  }
}
