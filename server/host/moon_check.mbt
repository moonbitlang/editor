///|
/// Push source for workspace diagnostics: runs `moon check --output-json` and
/// publishes the parsed per-file diagnostics through `publish`. Runs are
/// single-flight — document syncs arriving while a check is in flight
/// collapse into one follow-up run.
pub struct MoonCheckDiagnostics {
  priv root : String
  priv publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit
  priv collect_check : async () -> String?
  priv running : Ref[Bool]
  priv dirty : Ref[Bool]
  priv sync_generation : Ref[Int]
  /// Exact synced model state per workspace URI.
  priv documents : Map[String, SyncedDocumentStamp]
  /// Last accepted set per workspace URI, including its producing state.
  priv published : Ref[Map[String, PublishedDiagnosticSet]]
}

///|
priv struct SyncedDocumentStamp {
  revision : String
  normalized_text : String
}

///|
priv struct PublishedDiagnosticSet {
  revision : String
  normalized_text : String
  diagnostics : Array[@language.Diagnostic]
}

///|
/// Creates a diagnostics runner for the workspace rooted at `root`.
pub fn MoonCheckDiagnostics::MoonCheckDiagnostics(
  root : String,
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit,
  moon_command? : String = "moon",
) -> MoonCheckDiagnostics {
  let root = normalize_host_path(root)
  new_moon_check_diagnostics(root, publish, () => {
    // `moon check` exits nonzero whenever errors exist, so the exit code is
    // ignored and stdout is parsed unconditionally.
    Some(
      @process.collect_stdout(
        moon_command,
        ["check", "--output-json"],
        cwd=root,
      ).1.text(),
    ) catch {
      _ => None
    }
  })
}

///|
fn new_moon_check_diagnostics(
  root : String,
  publish : (@base_common.Uri, String, Array[@language.Diagnostic]) -> Unit,
  collect_check : async () -> String?,
) -> MoonCheckDiagnostics {
  {
    root: normalize_host_path(root),
    publish,
    collect_check,
    running: Ref(false),
    dirty: Ref(false),
    sync_generation: Ref(0),
    documents: {},
    published: Ref({}),
  }
}

///|
/// Records the exact synced state. A freshly opened document replays only a
/// diagnostic set produced for the same revision and normalized text.
pub fn MoonCheckDiagnostics::note_document(
  self : MoonCheckDiagnostics,
  document : @workspace.DocumentSnapshot,
) -> Unit {
  let key = document.uri.to_string()
  let stamp : SyncedDocumentStamp = {
    revision: document.revision,
    normalized_text: @model.TextSnapshot(document.text).get_value(),
  }
  self.sync_generation.val += 1
  self.documents.set(key, stamp)
  if self.running.val {
    self.dirty.val = true
  }
  match self.published.val.get(key) {
    Some(published) =>
      if published.revision == stamp.revision &&
        published.normalized_text == stamp.normalized_text {
        self.emit(key, published.revision, published.diagnostics)
      }
    None => ()
  }
}

///|
/// Schedules a `moon check` run on `spawn_task`; a run already in flight
/// absorbs this request and re-runs once after it finishes.
pub fn MoonCheckDiagnostics::schedule(
  self : MoonCheckDiagnostics,
  spawn_task : (async () -> Unit) -> Unit,
) -> Unit {
  if self.running.val {
    self.dirty.val = true
    return
  }
  self.running.val = true
  spawn_task(() => {
    // The scheduler may be cancelled or the injected/process collector may
    // raise. A later sync must still be able to start a new run.
    defer {
      self.running.val = false
    }
    for ;; {
      self.dirty.val = false
      self.run_once()
      if !self.dirty.val {
        break
      }
    }
  })
}

///|
async fn MoonCheckDiagnostics::run_once(self : MoonCheckDiagnostics) -> Unit {
  let generation = self.sync_generation.val
  let documents = copy_synced_documents(self.documents)
  let before = capture_native_disk_snapshots(self.root, documents)
  let raw = (self.collect_check)()
  let after = capture_native_disk_snapshots(self.root, documents)
  if self.sync_generation.val != generation ||
    !same_native_disk_snapshot_map(before, after) {
    self.dirty.val = true
    return
  }
  guard raw is Some(raw) else { return }
  let next = parse_moon_check_diagnostics(self.root, raw)
  let accepted = copy_published_diagnostic_sets(self.published.val)
  for key, document in documents {
    // A stable disk/model mismatch is not a clear for the last accepted model.
    // Preserve that key and continue so historical entries cannot suppress
    // diagnostics for compatible active documents.
    if !native_disk_matches_document(before, key, document) {
      continue
    }
    let diagnostics = next.get(key).unwrap_or([])
    if !diagnostics.is_empty() || self.published.val.contains(key) {
      self.emit(key, document.revision, diagnostics)
    }
    if !diagnostics.is_empty() {
      accepted.set(key, {
        revision: document.revision,
        normalized_text: document.normalized_text,
        diagnostics,
      })
    } else {
      accepted.remove(key)
    }
  }
  self.published.val = accepted
}

///|
fn MoonCheckDiagnostics::emit(
  self : MoonCheckDiagnostics,
  uri_key : String,
  revision : String,
  diagnostics : Array[@language.Diagnostic],
) -> Unit {
  let uri = Some(@base_common.Uri::parse(uri_key)) catch { _ => None }
  match uri {
    Some(uri) => (self.publish)(uri, revision, diagnostics)
    None => ()
  }
}

///|
fn copy_synced_documents(
  documents : Map[String, SyncedDocumentStamp],
) -> Map[String, SyncedDocumentStamp] {
  let copy : Map[String, SyncedDocumentStamp] = Map([])
  for key, document in documents {
    copy.set(key, document)
  }
  copy
}

///|
fn copy_published_diagnostic_sets(
  published : Map[String, PublishedDiagnosticSet],
) -> Map[String, PublishedDiagnosticSet] {
  let copy : Map[String, PublishedDiagnosticSet] = Map([])
  for key, diagnostic_set in published {
    copy.set(key, diagnostic_set)
  }
  copy
}

///|
async fn capture_native_disk_snapshots(
  root : String,
  documents : Map[String, SyncedDocumentStamp],
) -> Map[String, NativeDiskSnapshot] {
  let snapshots : Map[String, NativeDiskSnapshot] = Map([])
  for key, _document in documents {
    let uri = Some(@base_common.Uri::parse(key)) catch { _ => None }
    match uri {
      Some(uri) =>
        match @server.resolve_remote_document_uri(uri) {
          ParsedRemotePath(path) =>
            match read_native_disk_snapshot(root, path) {
              Some(snapshot) => snapshots.set(key, snapshot)
              None => ()
            }
          RemotePathError(_) => ()
        }
      None => ()
    }
  }
  snapshots
}

///|
fn same_native_disk_snapshot_map(
  left : Map[String, NativeDiskSnapshot],
  right : Map[String, NativeDiskSnapshot],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for key, snapshot in left {
    match right.get(key) {
      Some(other) => if snapshot != other { return false }
      None => return false
    }
  }
  true
}

///|
fn native_disk_matches_document(
  snapshots : Map[String, NativeDiskSnapshot],
  key : String,
  document : SyncedDocumentStamp,
) -> Bool {
  match snapshots.get(key) {
    Some(disk) =>
      disk.signature == document.revision &&
      disk.normalized_text == document.normalized_text
    None => false
  }
}

///|
/// Parses `moon check --output-json` output — one JSON diagnostic per line —
/// into diagnostics grouped by remote workspace URI. Diagnostic paths outside
/// `root` and non-diagnostic lines are dropped. `loc` is 1-based
/// `line:col-line:col` with an exclusive end column, matching the viewer's
/// range convention directly.
pub fn parse_moon_check_diagnostics(
  root : String,
  raw : String,
) -> Map[String, Array[@language.Diagnostic]] {
  let prefix = normalize_host_path(root) + "/"
  let grouped : Map[String, Array[@language.Diagnostic]] = Map([])
  for line in raw.split("\n") {
    let trimmed = line.trim(char_set="\r\n ").to_owned()
    if trimmed == "" {
      continue
    }
    match (Some(@json.parse(trimmed)) catch { _ => None }) {
      Some(
        {
          "$message_type": "diagnostic",
          "level": String(level),
          "path": String(path),
          "loc": String(loc),
          "message": String(message),
          ..
        }
      ) => {
        let normalized = normalize_host_path(path)
        if !normalized.has_prefix(prefix) {
          continue
        }
        let relative = normalized[prefix.length():].to_owned()
        match (parse_moon_loc(loc), @server.remote_document_uri(relative)) {
          (Some(range), Some(uri)) => {
            let diagnostic : @language.Diagnostic = {
              range,
              severity: check_level_severity(level),
              message,
              tags: None,
            }
            match grouped.get(uri.to_string()) {
              Some(diagnostics) => diagnostics.push(diagnostic)
              None => grouped.set(uri.to_string(), [diagnostic])
            }
          }
          _ => ()
        }
      }
      _ => ()
    }
  }
  grouped
}

///|
fn check_level_severity(level : String) -> @language.DiagnosticSeverity {
  match level {
    "error" => Error
    "warning" => Warning
    _ => Info
  }
}

///|
/// Parses a `moon check` location: `line:col-line:col`, or a bare `line:col`
/// which degrades to an empty range at that position.
fn parse_moon_loc(loc : String) -> @base_common.Range? {
  match loc.find("-") {
    Some(dash) =>
      match
        (
          parse_check_position(loc[0:dash]),
          parse_check_position(loc[dash + 1:]),
        ) {
        (Some(start), Some(end)) =>
          Some(@base_common.Range::from_positions(start, end))
        _ => None
      }
    None =>
      match parse_check_position(loc[:]) {
        Some(position) =>
          Some(@base_common.Range::from_positions(position, position))
        None => None
      }
  }
}

///|
fn parse_check_position(view : StringView) -> @base_common.Position? {
  match view.find(":") {
    Some(colon) => {
      let parsed = Some(
        (
          @string.parse_int(view[0:colon], base=10),
          @string.parse_int(view[colon + 1:], base=10),
        ),
      ) catch {
        _ => None
      }
      match parsed {
        Some((line, column)) => Some(Position(line, column))
        None => None
      }
    }
    None => None
  }
}
