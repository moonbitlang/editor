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
/// Runs `moon ide hover` at the requested position. The ordinary command
/// checks current disk content before answering; exact pre/post disk snapshots
/// additionally prevent a raced result from being assigned the model revision.
pub impl @language.HoverProvider for MoonWorkspaceLanguageProvider with fn provide_hover(
  self,
  model,
  position,
  _token,
) {
  self.provide_hover_with_runner(model, position, args => {
    let output = Some(
      @process.collect_stdout(self.moon_command, args, cwd=self.root),
    ) catch {
      _ => None
    }
    match output {
      Some((exit_code, data)) =>
        match (Some(data.text()) catch { _ => None }) {
          Some(raw) => Some((exit_code, raw))
          None => None
        }
      None => None
    }
  })
}

///|
async fn MoonWorkspaceLanguageProvider::provide_hover_with_runner(
  self : MoonWorkspaceLanguageProvider,
  model : @model.TextModel,
  position : @base_common.Position,
  run : async (Array[String]) -> (Int, String)?,
) -> @language.Hover? {
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let model_identity = model.identity()
      let model_version = model.version
      let content_version = model.get_version_id()
      let model_uri = model.uri.to_string()
      let model_revision = model.revision
      let model_text = model.snapshot.get_value()
      guard read_native_disk_snapshot(self.root, path) is Some(before) else {
        return None
      }
      guard before.signature == model_revision &&
        before.normalized_text == model_text else {
        return None
      }
      guard !model.is_disposed() &&
        model.identity() == model_identity &&
        model.version == model_version &&
        model.get_version_id() == content_version &&
        model.uri.to_string() == model_uri &&
        model.revision == model_revision &&
        model.snapshot.get_value() == model_text else {
        return None
      }
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = run(["ide", "hover", "--loc", loc, "--output-json"])
      guard read_native_disk_snapshot(self.root, path) is Some(after) &&
        after == before &&
        !model.is_disposed() &&
        model.identity() == model_identity &&
        model.version == model_version &&
        model.get_version_id() == content_version &&
        model.uri.to_string() == model_uri &&
        model.revision == model_revision &&
        model.snapshot.get_value() == model_text else {
        return None
      }
      match output {
        // A missing hover exits nonzero with a plain-text notice, so only an
        // exit-0 payload is parsed.
        Some((0, raw)) => parse_moon_hover_output(raw, position)
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
