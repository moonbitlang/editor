///|
/// Browser-side workspace tree provider: implements
/// `@workspace.WorkspaceTreeProvider` over the protocol client with
/// correlated `ResolveDirectory` requests.
priv struct RemoteWorkspaceTreeProvider {}

///|
let workspace_tree_provider : &@workspace.WorkspaceTreeProvider = RemoteWorkspaceTreeProvider::{

}

///|
impl @workspace.WorkspaceTreeProvider for RemoteWorkspaceTreeProvider with fn root(
  _self,
) {
  try! @base_common.Uri::parse("readonly-remote://workspace")
}

///|
impl @workspace.WorkspaceTreeProvider for RemoteWorkspaceTreeProvider with fn resolve(
  _self,
  uri,
) {
  let response = protocol_request("resolve", id => ResolveDirectory({ id, uri }))
  match response {
    DirectoryResolved(payload) => WorkspaceResolved(payload.stat)
    RemoteError(error) =>
      WorkspaceResolveError(
        FileSystemProviderError(
          @workspace.FileSystemProviderErrorCode::from_string(
            error.provider_code,
          ),
          error.message,
          uri~,
        ),
      )
    _ =>
      WorkspaceResolveError(
        FileSystemProviderError(
          Unavailable,
          "Unexpected protocol response for directory resolve.",
          uri~,
        ),
      )
  }
}

///|
/// Explorer-only provider view: filename sorting belongs to the visible tree
/// policy and must not change the raw provider order used by auto-open.
priv struct ExplorerWorkspaceTreeProvider {}

///|
let explorer_workspace_tree_provider : &@workspace.WorkspaceTreeProvider = ExplorerWorkspaceTreeProvider::{

}

///|
impl @workspace.WorkspaceTreeProvider for ExplorerWorkspaceTreeProvider with fn root(
  _self,
) {
  workspace_tree_provider.root()
}

///|
impl @workspace.WorkspaceTreeProvider for ExplorerWorkspaceTreeProvider with fn resolve(
  _self,
  uri,
) {
  match workspace_tree_provider.resolve(uri) {
    WorkspaceResolved(stat) =>
      WorkspaceResolved(order_workspace_stat_children(stat))
    WorkspaceResolveError(error) => WorkspaceResolveError(error)
  }
}

///|
/// The explorer widget instance, created on first use so the protocol
/// dispatch hooks installed at mount are already in place.
let file_tree_cell : Ref[@file_tree.FileTree?] = Ref(None)

///|
fn workspace_file_tree() -> @file_tree.FileTree {
  match file_tree_cell.val {
    Some(tree) => tree
    None => {
      let tree = @file_tree.FileTree(
        explorer_workspace_tree_provider,
        on_open=uri => dispatch_workbench_msg(SelectWorkspace(uri)),
        rank=workspace_entry_rank,
      )
      file_tree_cell.val = Some(tree)
      tree
    }
  }
}

///|
/// Explorer ordering policy (app policy, not widget behavior): the files that
/// describe a MoonBit package to a reader — its README first (any extension,
/// including `README.mbt.md`), then the generated `pkg.generated.mbti`
/// interface, then `moon.pkg` — lead every directory level, above the widget's
/// directories-before-files default. Everything else keeps that default after
/// the level has been ordered lexicographically by name.
fn workspace_entry_rank(stat : @workspace.WorkspaceStat) -> Int {
  guard stat.kind is File else { return 0 }
  match stat.name {
    "README" | [.. "README.", ..] => -3
    "pkg.generated.mbti" => -2
    "moon.pkg" => -1
    _ => 0
  }
}

///|
/// Applies the explorer's filename order before the file-tree widget groups
/// entries by rank and kind. MoonBit's default `String` order is shortlex;
/// filenames use UTF-16 code-unit lexicographic order instead.
fn order_workspace_stat_children(
  stat : @workspace.WorkspaceStat,
) -> @workspace.WorkspaceStat {
  guard stat.children is Some(children) else { return stat }
  children.sort_by((left, right) => left.name.lexical_compare(right.name))
  { ..stat, children: Some(children) }
}

///|
/// Auto-open policy (app policy, not widget behavior): a bounded
/// depth-first resolve walk that opens the first `.mbt` file, falling back
/// to the first file of any kind; `set_active` then reveals it in the tree
/// once the document renders.
fn auto_open_first_file_cmd(emit : @rabbita.Emit[WorkbenchMsg]) -> @rabbita.Cmd {
  @cmd.perform(result => emit(AutoOpenResolved(result)), async fn() noraise {
    find_first_workspace_file() catch {
      _ => None
    }
  })
}

///|
let auto_open_max_resolves = 32

///|
let auto_open_max_depth = 6

///|
async fn find_first_workspace_file() -> @base_common.Uri? {
  let first_file : Ref[@base_common.Uri?] = Ref(None)
  let budget : Ref[Int] = Ref(auto_open_max_resolves)
  match
    first_moonbit_file(workspace_tree_provider.root(), budget, 0, first_file) {
    Some(uri) => Some(uri)
    None => first_file.val
  }
}

///|
async fn first_moonbit_file(
  uri : @base_common.Uri,
  budget : Ref[Int],
  depth : Int,
  first_file : Ref[@base_common.Uri?],
) -> @base_common.Uri? {
  if budget.val <= 0 || depth > auto_open_max_depth {
    return None
  }
  budget.val = budget.val - 1
  match workspace_tree_provider.resolve(uri) {
    WorkspaceResolved(stat) =>
      match stat.children {
        Some(children) => {
          for child in children {
            if child.kind == File {
              if child.name.has_suffix(".mbt") {
                return Some(child.uri)
              }
              if first_file.val is None {
                first_file.val = Some(child.uri)
              }
            }
          }
          for child in children {
            if child.kind == Directory {
              match
                first_moonbit_file(child.uri, budget, depth + 1, first_file) {
                Some(found) => return Some(found)
                None => ()
              }
            }
          }
          None
        }
        None => None
      }
    WorkspaceResolveError(_) => None
  }
}
