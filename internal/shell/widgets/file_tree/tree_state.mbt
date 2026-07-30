///|
/// One tree node, the `ExplorerItem` role: a cached `WorkspaceStat` plus
/// per-node expansion state. `children: None` means the directory level
/// has not been resolved yet; a resolve result is cached on the node and
/// survives collapse/expand cycles. Nodes and their child vectors are immutable:
/// every change rebuilds the path from the root, preserving prior snapshots.
priv struct TreeNode {
  uri : @base_common.Uri
  name : String
  kind : @workspace.WorkspaceEntryKind
  children : @vec.Vector[TreeNode]?
  expanded : Bool
  resolve_failed : Bool
} derive(Eq)

///|
priv struct FileTreeModel {
  root : TreeNode?
  selected : @base_common.Uri?
  pending_reveal : @base_common.Uri?
} derive(Eq)

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
/// Builds a node from a resolved stat. Children render in the level order
/// `rank` describes (see `TreeNode::from_stats`).
fn TreeNode::from_stat(
  stat : @workspace.WorkspaceStat,
  expanded~ : Bool,
  rank~ : (@workspace.WorkspaceStat) -> Int,
) -> TreeNode {
  {
    uri: stat.uri,
    name: stat.name,
    kind: stat.kind,
    children: stat.children.map(stats => TreeNode::from_stats(stats, rank~)),
    expanded,
    resolve_failed: false,
  }
}

///|
/// Orders one resolved directory level: ascending `rank` first, then
/// directories before files, then the provider's own order. `Array::sort_by`
/// is unstable, so the source position is the last sort key rather than an
/// assumed tie-break.
fn TreeNode::from_stats(
  stats : Array[@workspace.WorkspaceStat],
  rank~ : (@workspace.WorkspaceStat) -> Int,
) -> @vec.Vector[TreeNode] {
  let ranks = stats.map(rank)
  let order = Array::makei(stats.length(), index => index)
  order.sort_by((left, right) => {
    match ranks[left].compare(ranks[right]) {
      0 =>
        match
          kind_rank(stats[left].kind).compare(kind_rank(stats[right].kind)) {
          0 => left.compare(right)
          by_kind => by_kind
        }
      by_rank => by_rank
    }
  })
  Vector(
    order.map(index => TreeNode::from_stat(stats[index], expanded=false, rank~)),
  )
}

///|
/// Directories before files within one rank (the explorer's default sort).
fn kind_rank(kind : @workspace.WorkspaceEntryKind) -> Int {
  match kind {
    Directory => 0
    File => 1
  }
}

///|
/// Replaces one resolved level and rebuilds the ancestors leading to it.
fn TreeNode::with_resolved(
  self : TreeNode,
  uri : @base_common.Uri,
  stat : @workspace.WorkspaceStat,
  rank~ : (@workspace.WorkspaceStat) -> Int,
) -> TreeNode? {
  if self.uri == uri {
    return Some({
      ..self,
      children: stat.children.map(stats => TreeNode::from_stats(stats, rank~)),
      resolve_failed: false,
    })
  }
  guard self.children is Some(children) else { return None }
  let mut index = 0
  for child in children {
    if child.with_resolved(uri, stat, rank~) is Some(next) {
      return Some({ ..self, children: Some(children.set(index, next)) })
    }
    index = index + 1
  }
  None
}

///|
/// Collapses an expanded directory, or expands a collapsed one. Expanding
/// a directory whose children are unresolved (including one whose last
/// resolve failed) asks for a resolve; cached children expand for free. The
/// returned root shares unchanged branches but never mutates `self`.
fn TreeNode::toggle(
  self : TreeNode,
  uri : @base_common.Uri,
) -> (TreeNode, ToggleEffect)? {
  if self.uri == uri {
    if self.expanded {
      return Some(({ ..self, expanded: false }, ToggleNone))
    }
    let next = { ..self, expanded: true, resolve_failed: false }
    let effect = match self.children {
      Some(_) => ToggleNone
      None => ToggleResolve(self.uri)
    }
    return Some((next, effect))
  }
  guard self.children is Some(children) else { return None }
  let mut index = 0
  for child in children {
    if child.toggle(uri) is Some((next, effect)) {
      return Some(
        ({ ..self, children: Some(children.set(index, next)) }, effect),
      )
    }
    index = index + 1
  }
  None
}

///|
/// Records a resolve failure on one node without changing an older root.
fn TreeNode::with_resolve_failed(
  self : TreeNode,
  uri : @base_common.Uri,
) -> TreeNode? {
  if self.uri == uri {
    return Some({ ..self, resolve_failed: true })
  }
  guard self.children is Some(children) else { return None }
  let mut index = 0
  for child in children {
    if child.with_resolve_failed(uri) is Some(next) {
      return Some({ ..self, children: Some(children.set(index, next)) })
    }
    index = index + 1
  }
  None
}

///|
/// The directory URIs between this root (exclusive) and `target`
/// (exclusive), derived from the root-relative path segments. `None` when
/// the target does not live under the root.
fn TreeNode::ancestor_uris(
  self : TreeNode,
  target : @base_common.Uri,
) -> Array[@base_common.Uri]? {
  let root_raw = self.uri.to_string()
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
/// Expands the remaining resolved ancestor path and rebuilds every changed
/// parent. The first unresolved node becomes the next resolve request.
fn TreeNode::reveal_ancestors(
  self : TreeNode,
  ancestors : ArrayView[@base_common.Uri],
  index : Int,
) -> (TreeNode, RevealStep) {
  if index == ancestors.length() {
    return match self.children {
      Some(_) => (self, RevealDone)
      None => (self, RevealResolve(self.uri))
    }
  }
  guard self.children is Some(children) else {
    return (self, RevealResolve(self.uri))
  }
  let mut child_index = 0
  for child in children {
    if child.uri == ancestors[index] {
      let expanded = { ..child, expanded: true }
      let (next, step) = expanded.reveal_ancestors(ancestors, index + 1)
      return ({ ..self, children: Some(children.set(child_index, next)) }, step)
    }
    child_index = child_index + 1
  }
  (self, RevealUnreachable)
}

///|
/// One `autoReveal` step: expands resolved ancestors of `target` from the
/// root down, stopping at the first unresolved level. The returned root is a
/// new snapshot whenever expansion state changes.
fn TreeNode::reveal_step(
  self : TreeNode,
  target : @base_common.Uri,
) -> (TreeNode, RevealStep) {
  guard self.ancestor_uris(target) is Some(ancestors) else {
    return (self, RevealUnreachable)
  }
  self.reveal_ancestors(ancestors[:], 0)
}

///|
/// The rows the tree renders: this root's children at depth zero, then the
/// cached children of every expanded directory. Collapsed or unresolved
/// directories contribute only their own row.
fn TreeNode::visible_rows(self : TreeNode) -> Array[TreeRow] {
  let rows : Array[TreeRow] = []
  match self.children {
    Some(children) =>
      for child in children {
        child.push_rows(rows, 0)
      }
    None => ()
  }
  rows
}

///|
fn TreeNode::push_rows(
  self : TreeNode,
  rows : Array[TreeRow],
  depth : Int,
) -> Unit {
  rows.push({ node: self, depth })
  if self.kind == Directory && self.expanded {
    match self.children {
      Some(children) =>
        for child in children {
          child.push_rows(rows, depth + 1)
        }
      None => ()
    }
  }
}
