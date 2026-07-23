///|
/// One tree node, the `ExplorerItem` role: a cached `WorkspaceStat` plus
/// per-node expansion state. `children: None` means the directory level
/// has not been resolved yet; a resolve result is cached on the node and
/// survives collapse/expand cycles.
priv struct TreeNode {
  uri : @base_common.Uri
  name : String
  kind : @workspace.WorkspaceEntryKind
  mut children : Array[TreeNode]?
  mut expanded : Bool
  mut resolve_failed : Bool
}

///|
priv struct FileTreeModel {
  mut root : TreeNode?
  mut selected : @base_common.Uri?
  mut pending_reveal : @base_common.Uri?
}

///|
priv struct TreeRow {
  node : TreeNode
  depth : Int
}

///|
priv enum ToggleEffect {
  ToggleNone
  ToggleResolve(@base_common.Uri)
}

///|
priv enum RevealStep {
  RevealResolve(@base_common.Uri)
  RevealDone
  RevealUnreachable
}

///|
/// Builds a node from a resolved stat. Children render directories first,
/// then files, keeping the provider's name order within each group (the
/// explorer's default sort).
fn node_from_stat(
  stat : @workspace.WorkspaceStat,
  expanded~ : Bool,
) -> TreeNode {
  {
    uri: stat.uri,
    name: stat.name,
    kind: stat.kind,
    children: stat.children.map(children_from_stats),
    expanded,
    resolve_failed: false,
  }
}

///|
fn children_from_stats(
  stats : Array[@workspace.WorkspaceStat],
) -> Array[TreeNode] {
  let nodes : Array[TreeNode] = []
  for stat in stats {
    if stat.kind == Directory {
      nodes.push(node_from_stat(stat, expanded=false))
    }
  }
  for stat in stats {
    if stat.kind == File {
      nodes.push(node_from_stat(stat, expanded=false))
    }
  }
  nodes
}

///|
fn find_node(node : TreeNode, uri : @base_common.Uri) -> TreeNode? {
  if node.uri == uri {
    return Some(node)
  }
  match node.children {
    Some(children) =>
      for child in children {
        match find_node(child, uri) {
          Some(found) => return Some(found)
          None => ()
        }
      }
    None => ()
  }
  None
}

///|
/// Caches a freshly resolved level on the node. A re-resolve replaces the
/// cached children wholesale.
fn apply_resolved(node : TreeNode, stat : @workspace.WorkspaceStat) -> Unit {
  node.children = stat.children.map(children_from_stats)
  node.resolve_failed = false
}

///|
/// Collapses an expanded directory, or expands a collapsed one. Expanding
/// a directory whose children are unresolved (including one whose last
/// resolve failed) asks for a resolve; cached children expand for free.
fn toggle_node(node : TreeNode) -> ToggleEffect {
  if node.expanded {
    node.expanded = false
    ToggleNone
  } else {
    node.expanded = true
    match node.children {
      Some(_) => ToggleNone
      None => {
        node.resolve_failed = false
        ToggleResolve(node.uri)
      }
    }
  }
}

///|
/// The directory URIs between the root (exclusive) and `target`
/// (exclusive), derived from the root-relative path segments. `None` when
/// the target does not live under the root.
fn ancestor_uris(
  root_uri : @base_common.Uri,
  target : @base_common.Uri,
) -> Array[@base_common.Uri]? {
  let root_raw = root_uri.to_string()
  let target_raw = target.to_string()
  if !target_raw.has_prefix(root_raw + "/") {
    return None
  }
  let relative = target_raw[root_raw.length() + 1:].to_owned()
  let ancestors : Array[@base_common.Uri] = []
  let mut prefix = root_raw
  let segments = []
  for segment_view in relative.split("/") {
    let segment = segment_view.to_owned()
    if segment != "" {
      segments.push(segment)
    }
  }
  for i in 0..<(segments.length() - 1) {
    prefix = prefix + "/" + segments[i]
    // `prefix` extends the canonical form of a valid URI with path
    // segments, so re-parsing cannot fail.
    ancestors.push(try! @base_common.Uri::parse(prefix))
  }
  Some(ancestors)
}

///|
/// One `autoReveal` step: expands resolved ancestors of `target` from the
/// root down, stopping at the first unresolved level (which must be
/// resolved before the reveal can continue).
fn reveal_step(
  root : TreeNode,
  root_uri : @base_common.Uri,
  target : @base_common.Uri,
) -> RevealStep {
  guard ancestor_uris(root_uri, target) is Some(ancestors) else {
    return RevealUnreachable
  }
  let mut node = root
  for ancestor in ancestors {
    guard node.children is Some(children) else {
      return RevealResolve(node.uri)
    }
    let mut next : TreeNode? = None
    for child in children {
      if child.uri == ancestor {
        next = Some(child)
        break
      }
    }
    guard next is Some(found) else { return RevealUnreachable }
    found.expanded = true
    node = found
  }
  if node.children is None {
    return RevealResolve(node.uri)
  }
  RevealDone
}

///|
/// The rows the tree renders: the root's children at depth zero, then the
/// cached children of every expanded directory. Collapsed or unresolved
/// directories contribute only their own row.
fn visible_rows(root : TreeNode?) -> Array[TreeRow] {
  let rows : Array[TreeRow] = []
  match root {
    Some(root) =>
      match root.children {
        Some(children) =>
          for child in children {
            push_rows(rows, child, 0)
          }
        None => ()
      }
    None => ()
  }
  rows
}

///|
fn push_rows(rows : Array[TreeRow], node : TreeNode, depth : Int) -> Unit {
  rows.push({ node, depth })
  if node.kind == Directory && node.expanded {
    match node.children {
      Some(children) =>
        for child in children {
          push_rows(rows, child, depth + 1)
        }
      None => ()
    }
  }
}
