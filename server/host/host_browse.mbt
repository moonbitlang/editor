// Host filesystem browsing for the repository picker: listing absolute host
// directories and switching the served workspace root. These are host-level
// packets handled outside the per-session policy server; anyone who can reach
// the protocol socket can browse directory names and re-root the server, which
// matches the loopback-by-default posture of this dev server.

///|
/// One resolved host directory level or a filesystem-shaped failure.
priv enum HostDirectoryListResult {
  HostDirectoryListOk(@remote_protocol.HostDirectoryListing)
  HostDirectoryListError(@workspace.FileSystemProviderErrorCode, String)
}

///|
/// Answers `ListHostDirectory`: child directories of one absolute host path
/// (the current workspace root when the path is empty), dot-entries skipped,
/// repository-looking children flagged.
async fn list_host_directory_packet(
  workspace : NativeWorkspace,
  request : @remote_protocol.HostPathRequest,
) -> String {
  let target = if request.path == "" {
    workspace.root.val
  } else {
    request.path
  }
  let packet : @remote_protocol.ServerPacket = match
    resolve_host_directory_listing(target) {
    HostDirectoryListOk(listing) =>
      HostDirectoryListed({ id: request.id, listing })
    HostDirectoryListError(code, message) =>
      host_browse_error(request.id, code, message)
  }
  packet.to_json().stringify()
}

///|
async fn resolve_host_directory_listing(
  target : String,
) -> HostDirectoryListResult {
  if (Some(@fs.exists(target)) catch { _ => None }) != Some(true) {
    return HostDirectoryListError(FileNotFound, "Directory does not exist.")
  }
  let real = realpath_or_normalized(target)
  match (Some(@fs.kind(real)) catch { _ => None }) {
    Some(Directory) => ()
    _ =>
      return HostDirectoryListError(
        FileNotADirectory,
        "Path is not a directory.",
      )
  }
  let names = Some(@fs.readdir(real, include_hidden=true)) catch { _ => None }
  guard names is Some(names) else {
    return HostDirectoryListError(Unavailable, "Unable to read directory.")
  }
  // MoonBit's default String order is shortlex; a directory picker wants
  // plain lexicographic order.
  names.sort_by(compare_names_lexicographic)
  let entries : Array[@remote_protocol.HostDirectoryEntry] = []
  for name in names {
    // The picker chooses repositories; hidden directories are noise there.
    if name.has_prefix(".") {
      continue
    }
    let child = join_host_path(real, name)
    match (Some(@fs.kind(child)) catch { _ => None }) {
      Some(Directory) =>
        entries.push({
          name,
          path: child,
          is_workspace: looks_like_repository_root(child),
        })
      _ => ()
    }
  }
  HostDirectoryListOk({ path: real, parent: parent_host_path(real), entries })
}

///|
/// Answers `SwitchWorkspace`: validates the target, re-roots the shared
/// workspace state, responds to the requester with its request id, and pushes
/// an uncorrelated `WorkspaceSwitched` to every other session so all
/// connected clients move together.
async fn switch_workspace_packets(
  workspace : NativeWorkspace,
  session : Int,
  outbox : @aqueue.Queue[String],
  request : @remote_protocol.HostPathRequest,
) -> Unit {
  match resolve_switch_target(request.path) {
    HostSwitchTarget(real) => {
      workspace.switch_root(real)
      let name = host_basename(real)
      let response : @remote_protocol.ServerPacket = WorkspaceSwitched({
        id: request.id,
        root: real,
        name,
      })
      outbox.put(response.to_json().stringify())
      let push : @remote_protocol.ServerPacket = WorkspaceSwitched({
        id: "",
        root: real,
        name,
      })
      workspace.sessions.broadcast_except(session, push.to_json().stringify())
    }
    HostSwitchError(code, message) => {
      let error : @remote_protocol.ServerPacket = host_browse_error(
        request.id,
        code,
        message,
      )
      outbox.put(error.to_json().stringify())
    }
  }
}

///|
priv enum HostSwitchResult {
  HostSwitchTarget(String)
  HostSwitchError(@workspace.FileSystemProviderErrorCode, String)
}

///|
async fn resolve_switch_target(path : String) -> HostSwitchResult {
  if path == "" {
    return HostSwitchError(InvalidUri, "Workspace path is required.")
  }
  if (Some(@fs.exists(path)) catch { _ => None }) != Some(true) {
    return HostSwitchError(FileNotFound, "Workspace directory does not exist.")
  }
  let real = realpath_or_normalized(path)
  match (Some(@fs.kind(real)) catch { _ => None }) {
    Some(Directory) => HostSwitchTarget(real)
    _ =>
      HostSwitchError(FileNotADirectory, "Workspace path is not a directory.")
  }
}

///|
fn host_browse_error(
  request_id : String,
  code : @workspace.FileSystemProviderErrorCode,
  message : String,
) -> @remote_protocol.ServerPacket {
  RemoteError(
    ProtocolError(
      ProtocolProviderError,
      message,
      request_id~,
      provider_code=code.to_string(),
    ),
  )
}

///|
/// A directory reads as a repository root when it carries MoonBit module
/// metadata or a git checkout marker.
async fn looks_like_repository_root(path : String) -> Bool {
  for marker in ["moon.mod", "moon.mod.json", ".git"] {
    if (Some(@fs.exists(join_host_path(path, marker))) catch { _ => None }) ==
      Some(true) {
      return true
    }
  }
  false
}

///|
/// Code-unit lexicographic comparison (the default `String` order is
/// shortlex, which reads wrongly in a file listing).
fn compare_names_lexicographic(left : String, right : String) -> Int {
  let shared = left.length().min(right.length())
  for index in 0..<shared {
    let l = left[index].to_int()
    let r = right[index].to_int()
    if l != r {
      return l - r
    }
  }
  left.length() - right.length()
}

///|
fn join_host_path(base : String, name : String) -> String {
  if base == "/" {
    "/" + name
  } else {
    base + "/" + name
  }
}

///|
/// The parent of a normalized absolute path; `None` at the filesystem root.
fn parent_host_path(path : String) -> String? {
  if path == "/" {
    return None
  }
  match path.rev_find("/") {
    Some(0) => Some("/")
    Some(index) => Some(path[0:index].to_owned())
    None => None
  }
}

///|
fn host_basename(path : String) -> String {
  if path == "/" {
    return "/"
  }
  match path.rev_after("/") {
    Some(name) => name.to_owned()
    None => path
  }
}
