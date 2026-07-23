///|
fn uri(raw : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(raw)
}

///|
fn dir_stat(raw : String, name : String) -> @workspace.WorkspaceStat {
  { uri: uri(raw), name, kind: Directory, children: None }
}

///|
fn file_stat(raw : String, name : String) -> @workspace.WorkspaceStat {
  { uri: uri(raw), name, kind: File, children: None }
}

///|
let root_raw : String = "readonly-remote://workspace"

///|
fn resolved_root() -> TreeNode {
  node_from_stat(
    {
      uri: uri(root_raw),
      name: "workspace",
      kind: Directory,
      children: Some([
        file_stat(root_raw + "/moon.mod", "moon.mod"),
        dir_stat(root_raw + "/src", "src"),
      ]),
    },
    expanded=true,
  )
}

///|
test "orders resolved children directories first" {
  let root = resolved_root()
  let rows = visible_rows(Some(root))
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].node.name, "src")
  assert_true(rows[0].node.kind == Directory)
  assert_eq(rows[1].node.name, "moon.mod")
  assert_eq(rows[0].depth, 0)
}

///|
test "directories start collapsed and expansion resolves once" {
  let root = resolved_root()
  let src = find_node(root, uri(root_raw + "/src")).unwrap()
  assert_false(src.expanded)

  // First expand: unresolved children ask for a provider resolve.
  match toggle_node(src) {
    ToggleResolve(resolve_uri) =>
      assert_eq(resolve_uri.to_string(), root_raw + "/src")
    ToggleNone => fail("expected resolve effect")
  }
  assert_true(src.expanded)
  apply_resolved(src, {
    uri: src.uri,
    name: "src",
    kind: Directory,
    children: Some([file_stat(root_raw + "/src/main.mbt", "main.mbt")]),
  })

  // Collapse keeps the cache; the next expand is free.
  match toggle_node(src) {
    ToggleNone => assert_false(src.expanded)
    ToggleResolve(_) => fail("collapse must not resolve")
  }
  match toggle_node(src) {
    ToggleNone => assert_true(src.expanded)
    ToggleResolve(_) => fail("cached children must not re-resolve")
  }
  let rows = visible_rows(Some(root))
  assert_eq(rows.length(), 3)
  assert_eq(rows[1].node.name, "main.mbt")
  assert_eq(rows[1].depth, 1)
}

///|
test "failed resolve is retried on the next expand" {
  let root = resolved_root()
  let src = find_node(root, uri(root_raw + "/src")).unwrap()
  ignore(toggle_node(src))
  src.resolve_failed = true

  // Collapse, then expand again: children are still None, so the expand
  // retries the resolve and clears the error state.
  ignore(toggle_node(src))
  match toggle_node(src) {
    ToggleResolve(_) => assert_false(src.resolve_failed)
    ToggleNone => fail("expected resolve retry after failure")
  }
}

///|
test "reveal expands resolved ancestors and stops at unresolved levels" {
  let root = resolved_root()
  let target = uri(root_raw + "/src/lib/util.mbt")

  // src is unresolved: the reveal must resolve it first.
  match reveal_step(root, uri(root_raw), target) {
    RevealResolve(resolve_uri) =>
      assert_eq(resolve_uri.to_string(), root_raw + "/src")
    _ => fail("expected resolve step for src")
  }
  let src = find_node(root, uri(root_raw + "/src")).unwrap()
  assert_true(src.expanded)
  apply_resolved(src, {
    uri: src.uri,
    name: "src",
    kind: Directory,
    children: Some([dir_stat(root_raw + "/src/lib", "lib")]),
  })

  // lib is now reachable but unresolved.
  match reveal_step(root, uri(root_raw), target) {
    RevealResolve(resolve_uri) =>
      assert_eq(resolve_uri.to_string(), root_raw + "/src/lib")
    _ => fail("expected resolve step for src/lib")
  }
  let lib = find_node(root, uri(root_raw + "/src/lib")).unwrap()
  assert_true(lib.expanded)
  apply_resolved(lib, {
    uri: lib.uri,
    name: "lib",
    kind: Directory,
    children: Some([file_stat(root_raw + "/src/lib/util.mbt", "util.mbt")]),
  })
  match reveal_step(root, uri(root_raw), target) {
    RevealDone => ()
    _ => fail("expected completed reveal")
  }
  let rows = visible_rows(Some(root))
  assert_eq(rows.length(), 4)
  assert_eq(rows[2].node.name, "util.mbt")
  assert_eq(rows[2].depth, 2)
}

///|
test "reveal of targets outside the tree is unreachable" {
  let root = resolved_root()
  match reveal_step(root, uri(root_raw), uri("memory://other/file.mbt")) {
    RevealUnreachable => ()
    _ => fail("expected unreachable target outside the root")
  }
  match reveal_step(root, uri(root_raw), uri(root_raw + "/gone/file.mbt")) {
    RevealUnreachable => ()
    _ => fail("expected unreachable target in a missing directory")
  }
}

///|
struct MemoryTreeProvider {
  root_uri : @base_common.Uri
  directories : Map[String, Array[@workspace.WorkspaceStat]]
  resolve_counts : Map[String, Int]
}

///|
impl @workspace.WorkspaceTreeProvider for MemoryTreeProvider with fn root(self) {
  self.root_uri
}

///|
impl @workspace.WorkspaceTreeProvider for MemoryTreeProvider with fn resolve(
  self,
  uri,
) {
  let key = uri.to_string()
  self.resolve_counts[key] = self.resolve_counts.get(key).unwrap_or(0) + 1
  match self.directories.get(key) {
    Some(children) =>
      WorkspaceResolved({
        uri,
        name: @base_common.basename_or_authority(uri),
        kind: Directory,
        children: Some(children),
      })
    None =>
      WorkspaceResolveError(
        FileSystemProviderError(FileNotFound, "Directory does not exist.", uri~),
      )
  }
}

///|
extend MemoryTreeProvider with @workspace.WorkspaceTreeProvider::{root, resolve}

///|
async test "in-memory provider resolves one level per request" {
  let directories : Map[String, Array[@workspace.WorkspaceStat]] = Map([])
  directories[root_raw] = [
    file_stat(root_raw + "/moon.mod", "moon.mod"),
    dir_stat(root_raw + "/src", "src"),
  ]
  directories[root_raw + "/src"] = [
    file_stat(root_raw + "/src/main.mbt", "main.mbt"),
  ]
  let provider : MemoryTreeProvider = {
    root_uri: uri(root_raw),
    directories,
    resolve_counts: Map([]),
  }
  match provider.resolve(provider.root()) {
    WorkspaceResolved(stat) => {
      let root = node_from_stat(stat, expanded=true)
      let src = find_node(root, uri(root_raw + "/src")).unwrap()
      // The resolved level carries unresolved directory children.
      assert_true(src.children is None)
      match toggle_node(src) {
        ToggleResolve(resolve_uri) =>
          match provider.resolve(resolve_uri) {
            WorkspaceResolved(stat) => apply_resolved(src, stat)
            WorkspaceResolveError(error) => fail(error.message)
          }
        ToggleNone => fail("expected resolve effect")
      }
      let rows = visible_rows(Some(root))
      assert_eq(rows.length(), 3)
      assert_eq(rows[1].node.name, "main.mbt")
    }
    WorkspaceResolveError(error) => fail(error.message)
  }
  match provider.resolve(uri(root_raw + "/missing")) {
    WorkspaceResolveError(error) => assert_true(error.code == FileNotFound)
    WorkspaceResolved(_) => fail("expected missing directory error")
  }
  assert_true(provider.resolve_counts.get(root_raw) is Some(1))
  assert_true(provider.resolve_counts.get(root_raw + "/src") is Some(1))
}
