///|
/// Language provider backed by the `moon` command line. Hover shells out to
/// `moon ide hover --output-json` and definitions to `moon ide peek-def
/// --json` against the workspace on disk; diagnostics flow through the `moon
/// check` push path (`MoonCheckDiagnostics`) instead of a pull provider.
/// Remaining semantic features without a machine-readable `moon` query return
/// empty results.
pub(all) struct MoonWorkspaceLanguageProvider {
  /// Shared with the host's workspace switching, so every request runs
  /// against the currently served root.
  root : Ref[String]
  moon_command : String
}

///|
/// Creates a moon-command language provider over a shared workspace root.
pub fn MoonWorkspaceLanguageProvider::MoonWorkspaceLanguageProvider(
  root : Ref[String],
  moon_command? : String = "moon",
) -> MoonWorkspaceLanguageProvider {
  { root, moon_command }
}

///|
/// The root a request runs against, captured once per request so a
/// concurrent switch cannot mix two roots inside one query.
fn MoonWorkspaceLanguageProvider::current_root(
  self : MoonWorkspaceLanguageProvider,
) -> String {
  normalize_host_path(self.root.val)
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
  // The runner receives the root captured by `provide_hover_with_runner` so
  // the command cwd and the pre/post disk snapshots always agree, even when a
  // workspace switch lands mid-request.
  self.provide_hover_with_runner(model, position, (root, args) => {
    let output = Some(
      @process.collect_stdout(self.moon_command, args, cwd=root),
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
  run : async (String, Array[String]) -> (Int, String)?,
) -> @language.Hover? {
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let root = self.current_root()
      let model_identity = model.identity()
      let model_version = model.version
      let content_version = model.get_version_id()
      let model_uri = model.uri.to_string()
      let model_revision = model.revision
      let model_text = model.snapshot.get_value()
      guard read_native_disk_snapshot(root, path) is Some(before) else {
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
      let output = run(root, ["ide", "hover", "--loc", loc, "--output-json"])
      guard read_native_disk_snapshot(root, path) is Some(after) &&
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
/// Runs `moon ide peek-def --loc <path:line:column> --json`. Unlike hover this
/// intentionally does not pass `--no-check`: definition lookup uses the CLI's
/// normal check/update behavior. Results are kept in CLI order; malformed or
/// out-of-workspace locations are dropped.
pub impl @language.DefinitionProvider for MoonWorkspaceLanguageProvider with fn provide_definition(
  self,
  model,
  position,
  token,
) {
  if token.is_cancellation_requested() {
    return []
  }
  match @server.resolve_remote_document_uri(model.uri) {
    ParsedRemotePath(path) => {
      let root = self.current_root()
      let loc = "\{path.to_string()}:\{position.line_number}:\{position.column}"
      let output = Some(
        @process.collect_stdout(
          self.moon_command,
          ["ide", "peek-def", "--loc", loc, "--json"],
          cwd=root,
        ),
      ) catch {
        _ => None
      }
      if token.is_cancellation_requested() {
        return []
      }
      match output {
        Some((0, data)) =>
          match (Some(data.text()) catch { _ => None }) {
            Some(raw) => parse_moon_definition_output(root, raw)
            None => []
          }
        _ => []
      }
    }
    RemotePathError(_) => []
  }
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

///|
/// Parses the ordered JSON array emitted by `moon ide peek-def --json`.
/// Absolute paths must be contained by `root`; safe root-relative paths are
/// also accepted. Invalid entries are ignored independently.
pub fn parse_moon_definition_output(
  root : String,
  raw : String,
) -> Array[@language.Location] {
  guard (Some(@json.parse(raw)) catch { _ => None }) is Some(Array(items)) else {
    return []
  }
  let locations : Array[@language.Location] = []
  for item in items {
    if item is { "path": String(path), "range": String(raw_range), .. } {
      match
        (
          definition_uri_under_root(root, path),
          parse_moon_definition_range(raw_range),
        ) {
        (Some(uri), Some(range)) => locations.push({ uri, range })
        _ => ()
      }
    }
  }
  locations
}

///|
fn definition_uri_under_root(
  root : String,
  raw_path : String,
) -> @base_common.Uri? {
  let root = normalize_host_path(root)
  let path = normalize_host_path(raw_path)
  let root_prefix = if root == "/" { "/" } else { root + "/" }
  let relative = if path.has_prefix(root_prefix) {
    path[root_prefix.length():].to_owned()
  } else if path.has_prefix("/") {
    return None
  } else {
    path
  }
  match @workspace.SourcePath::normalize_root_relative_path(relative) {
    ParsedSourcePath(path) => @server.remote_document_uri(path.to_string())
    SourcePathError(_) => None
  }
}

///|
fn parse_moon_definition_range(raw : String) -> @base_common.Range? {
  guard raw.find("-") is Some(dash) else { return None }
  match
    (
      parse_positive_position(raw[0:dash]),
      parse_positive_position(raw[dash + 1:]),
    ) {
    (Some(start), Some(end)) =>
      if start.is_before_or_equal(end) {
        Some(@base_common.Range::from_positions(start, end))
      } else {
        None
      }
    _ => None
  }
}

///|
fn parse_positive_position(raw : StringView) -> @base_common.Position? {
  guard raw.find(":") is Some(colon) else { return None }
  let parsed = Some(
    (
      @string.parse_int(raw[0:colon], base=10),
      @string.parse_int(raw[colon + 1:], base=10),
    ),
  ) catch {
    _ => None
  }
  match parsed {
    Some((line, column)) =>
      if line >= 1 && column >= 1 {
        Some(Position(line, column))
      } else {
        None
      }
    None => None
  }
}
