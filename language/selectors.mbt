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
  self.score(model) > 0
}

///|
/// Monaco-compatible priority for the selector surface represented locally.
/// Exact language/scheme/pattern matches score 10, wildcard language/scheme
/// matches score 5, selector lists take their highest member, and a filter
/// without any constraining field does not select a model.
pub fn LanguageSelector::score(
  self : LanguageSelector,
  model : @model.TextModel,
) -> Int {
  match self {
    LanguageId("*") => 5
    LanguageId(language_id) =>
      if model.language_id == language_id {
        10
      } else {
        0
      }
    LanguageFilter(filter) => filter.score(model)
    LanguageSelectorList(selectors) => {
      let mut result = 0
      for selector in selectors {
        let score = selector.score(model)
        if score == 10 {
          return 10
        }
        if score > result {
          result = score
        }
      }
      result
    }
  }
}

///|
/// Whether this filter accepts a text model.
pub fn LanguageFilter::matches(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Bool {
  self.score(model) > 0
}

///|
/// Scores the language, scheme, and path-pattern subset of Monaco's
/// `LanguageFilter`.
pub fn LanguageFilter::score(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Int {
  let mut result = 0
  match self.language {
    Some(language) =>
      if language == model.language_id {
        result = 10
      } else if language == "*" {
        result = 5
      } else {
        return 0
      }
    None => ()
  }
  match self.scheme {
    Some(scheme) =>
      if scheme == model.uri.scheme {
        result = 10
      } else if scheme == "*" {
        if result < 5 {
          result = 5
        }
      } else {
        return 0
      }
    None => ()
  }
  match self.pattern {
    // Monaco's `score()` matches globs against `uri.path` (leading slash
    // included); `path_pattern_matches` strips that slash so the relative
    // patterns hosts register keep matching.
    Some(pattern) =>
      if path_pattern_matches(pattern, model.uri.path) {
        result = 10
      } else {
        return 0
      }
    None => ()
  }
  result
}

///|
fn path_pattern_matches(pattern : String, path : String) -> Bool {
  if pattern == "" {
    return false
  }
  if pattern == "*" {
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
