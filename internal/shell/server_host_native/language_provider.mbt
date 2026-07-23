///|
/// Language provider backed by the `moon` command line. Hover shells out to
/// `moon ide hover --output-json` against the workspace on disk; diagnostics
/// flow through the `moon check` push path (`MoonCheckDiagnostics`) instead of
/// a pull provider. The remaining semantic features have no `moon` subcommand
/// equivalent and return empty results.
pub(all) struct MoonWorkspaceLanguageProvider {
  root : String
  moon_command : String
}

///|
/// Creates a moon-command language provider rooted at `root`.
pub fn MoonWorkspaceLanguageProvider::MoonWorkspaceLanguageProvider(
  root : String,
  moon_command? : String = "moon",
) -> MoonWorkspaceLanguageProvider {
  { root: normalize_host_path(root), moon_command }
}

///|
/// Runs `moon ide hover` at the requested position. `--no-check` reuses the
/// check artifacts the diagnostics runner keeps fresh instead of re-checking
/// the workspace per hover.
pub impl @language.HoverProvider for MoonWorkspaceLanguageProvider with fn provide_hover(
  self,
  model,
  position,
  _token,
) {
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = Some(
        @process.collect_stdout(
          self.moon_command,
          ["ide", "hover", "--loc", loc, "--output-json", "--no-check"],
          cwd=self.root,
        ),
      ) catch {
        _ => None
      }
      match output {
        // A missing hover exits nonzero with a plain-text notice, so only an
        // exit-0 payload is parsed.
        Some((0, data)) =>
          match (Some(data.text()) catch { _ => None }) {
            Some(raw) => parse_moon_hover_output(raw, position)
            None => None
          }
        _ => None
      }
    }
    RemotePathError(_) => None
  }
}

///|
/// `moon` has no definition query; the feature is unavailable.
pub impl @language.DefinitionProvider for MoonWorkspaceLanguageProvider with fn provide_definition(
  _self,
  _model,
  _position,
  _token,
) {
  None
}

///|
/// `moon` has no machine-readable references query; the feature is
/// unavailable.
pub impl @language.ReferencesProvider for MoonWorkspaceLanguageProvider with fn provide_references(
  _self,
  _model,
  _position,
  _token,
) {
  []
}

///|
/// `moon` has no machine-readable document-symbol query; the feature is
/// unavailable.
pub impl @language.DocumentSymbolProvider for MoonWorkspaceLanguageProvider with fn provide_document_symbols(
  _self,
  _model,
  _token,
) {
  []
}

///|
/// Parses `moon ide hover --output-json` output: a 1-based
/// `line:col-line:col` range plus markdown content strings. A malformed or
/// empty payload yields no hover; a missing or malformed range degrades to a
/// one-column range at the requested position.
pub fn parse_moon_hover_output(
  raw : String,
  position : @base_common.Position,
) -> @language.Hover? {
  guard (Some(@json.parse(raw)) catch { _ => None }) is Some(json) else {
    return None
  }
  let contents : Array[@language.HoverContent] = []
  if json is { "contents": Array(items), .. } {
    for item in items {
      if item is String(text) && text != "" {
        contents.push(Markdown(text))
      }
    }
  }
  if contents.is_empty() {
    return None
  }
  let parsed_range = match json {
    { "range": String(loc), .. } => parse_moon_loc(loc)
    _ => None
  }
  let range = match parsed_range {
    Some(range) => range
    None =>
      Range(
        position.line_number,
        position.column,
        position.line_number,
        position.column + 1,
      )
  }
  Some({ range, contents })
}
