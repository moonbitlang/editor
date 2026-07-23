///|
/// Explorer-style workspace tree widget. It owns a tree of lazily
/// resolved `WorkspaceStat` nodes plus per-node expansion state (the
/// `ExplorerItem`/`AsyncDataTree` role): directories render collapsed
/// until expanded, expansion resolves exactly one level through the
/// provider and caches it on the node, and `set_active` is `autoReveal`.
/// Opening files is an intent reported through `on_open`; the widget
/// never opens documents itself.
pub struct FileTree {
  priv emit : @rabbita.Emit[FileTreeMsg]
  priv cell : @rabbita.Cell
}

///|
priv enum FileTreeMsg {
  Refresh
  DirectoryResolved(@base_common.Uri, @workspace.WorkspaceResolveResult)
  ToggleDirectory(@base_common.Uri)
  OpenFile(@base_common.Uri)
  SetActive(@base_common.Uri)
}

///|
/// Creates a file tree over a workspace provider and reports file-open
/// intents to the host.
pub fn FileTree::FileTree(
  provider : &@workspace.WorkspaceTreeProvider,
  on_open~ : (@base_common.Uri) -> Unit,
) -> FileTree {
  let model : FileTreeModel = {
    root: None,
    selected: None,
    pending_reveal: None,
  }
  let (emit, cell) = @rabbita.cell_with_emit(
    model~,
    update=(emit, msg, model) => {
      update_file_tree(provider, on_open, emit, msg, model)
    },
    view=view_file_tree,
  )
  { emit, cell }
}

///|
/// Embeds the tree as a Rabbita child cell.
pub fn FileTree::view(self : FileTree) -> @html.Html {
  self.cell.view()
}

///|
/// Re-resolves the tree from the provider's root, replacing every cached
/// node; the host calls this on (re)connect. The active file, if any, is
/// auto-revealed again in the fresh tree.
pub fn FileTree::refresh(self : FileTree) -> @rabbita.Cmd {
  (self.emit)(Refresh)
}

///|
/// `autoReveal`: resolves and expands the ancestor chain of `uri` (derived
/// from its root-relative path segments) and marks the node selected.
pub fn FileTree::set_active(
  self : FileTree,
  uri : @base_common.Uri,
) -> @rabbita.Cmd {
  (self.emit)(SetActive(uri))
}

///|
fn update_file_tree(
  provider : &@workspace.WorkspaceTreeProvider,
  on_open : (@base_common.Uri) -> Unit,
  emit : @rabbita.Emit[FileTreeMsg],
  msg : FileTreeMsg,
  model : FileTreeModel,
) -> (@rabbita.Cmd, FileTreeModel) {
  match msg {
    Refresh => (resolve_directory_cmd(provider, emit, provider.root()), model)
    DirectoryResolved(uri, result) =>
      directory_resolved_update(provider, emit, model, uri, result)
    ToggleDirectory(uri) =>
      match model.root {
        Some(root) =>
          match find_node(root, uri) {
            Some(node) =>
              match toggle_node(node) {
                ToggleResolve(uri) =>
                  (resolve_directory_cmd(provider, emit, uri), model)
                ToggleNone => (@rabbita.none, model)
              }
            None => (@rabbita.none, model)
          }
        None => (@rabbita.none, model)
      }
    OpenFile(uri) => {
      model.selected = Some(uri)
      (@cmd.custom_cmd(_ => on_open(uri)), model)
    }
    SetActive(uri) => {
      model.selected = Some(uri)
      model.pending_reveal = Some(uri)
      continue_reveal(provider, emit, model)
    }
  }
}

///|
fn directory_resolved_update(
  provider : &@workspace.WorkspaceTreeProvider,
  emit : @rabbita.Emit[FileTreeMsg],
  model : FileTreeModel,
  uri : @base_common.Uri,
  result : @workspace.WorkspaceResolveResult,
) -> (@rabbita.Cmd, FileTreeModel) {
  match result {
    WorkspaceResolved(stat) => {
      if uri == provider.root() {
        model.root = Some(node_from_stat(stat, expanded=true))
        if model.pending_reveal is None {
          model.pending_reveal = model.selected
        }
      } else {
        match model.root {
          Some(root) =>
            match find_node(root, uri) {
              Some(node) => apply_resolved(node, stat)
              None => ()
            }
          None => ()
        }
      }
      continue_reveal(provider, emit, model)
    }
    WorkspaceResolveError(_) => {
      // The folder keeps rendering as an empty-with-error level; children
      // stay unresolved so the next expand retries the resolve.
      match model.root {
        Some(root) =>
          match find_node(root, uri) {
            Some(node) => node.resolve_failed = true
            None => ()
          }
        None => ()
      }
      model.pending_reveal = None
      (@rabbita.none, model)
    }
  }
}

///|
fn continue_reveal(
  provider : &@workspace.WorkspaceTreeProvider,
  emit : @rabbita.Emit[FileTreeMsg],
  model : FileTreeModel,
) -> (@rabbita.Cmd, FileTreeModel) {
  match (model.root, model.pending_reveal) {
    (Some(root), Some(target)) =>
      match reveal_step(root, provider.root(), target) {
        RevealResolve(uri) =>
          (resolve_directory_cmd(provider, emit, uri), model)
        RevealDone | RevealUnreachable => {
          model.pending_reveal = None
          (@rabbita.none, model)
        }
      }
    _ => (@rabbita.none, model)
  }
}

///|
fn resolve_directory_cmd(
  provider : &@workspace.WorkspaceTreeProvider,
  emit : @rabbita.Emit[FileTreeMsg],
  uri : @base_common.Uri,
) -> @rabbita.Cmd {
  @cmd.perform(result => emit(DirectoryResolved(uri, result)), async fn() noraise {
    provider.resolve(uri) catch {
      _ =>
        WorkspaceResolveError(
          FileSystemProviderError(
            Unavailable,
            "Directory resolve failed.",
            uri~,
          ),
        )
    }
  })
}

///|
fn view_file_tree(
  emit : @rabbita.Emit[FileTreeMsg],
  model : FileTreeModel,
) -> @html.Html {
  let children : Array[@html.Html] = []
  for row in visible_rows(model.root) {
    if row.node.kind == Directory {
      children.push(view_folder_row(emit, row))
    } else {
      children.push(view_file_row(emit, model, row))
    }
  }
  @html.div(class="file-tree", children)
}

///|
fn view_folder_row(
  emit : @rabbita.Emit[FileTreeMsg],
  row : TreeRow,
) -> @html.Html {
  let node = row.node
  let class_name = if node.resolve_failed {
    "workspace-item workspace-folder resolve-failed"
  } else {
    "workspace-item workspace-folder"
  }
  @html.button(
    type_="button",
    class=class_name,
    on_click=emit(ToggleDirectory(node.uri)),
    attrs=@html.Attrs::build()
      .data_set("workspace-id", node.uri.to_string())
      .data_set("workspace-kind", "folder")
      .aria_expanded(node.expanded.to_string())
      .style("--depth", row.depth.to_string()),
    [
      view_indent_guides(row.depth),
      @html.span(class="workspace-twistie", icon_chevron_right()),
      @html.span(class="workspace-label", node.name),
    ],
  )
}

///|
fn view_file_row(
  emit : @rabbita.Emit[FileTreeMsg],
  model : FileTreeModel,
  row : TreeRow,
) -> @html.Html {
  let node = row.node
  let selected = model.selected is Some(uri) && uri == node.uri
  let class_name = if selected {
    "workspace-item workspace-file is-selected"
  } else {
    "workspace-item workspace-file"
  }
  @html.button(
    type_="button",
    class=class_name,
    on_click=emit(OpenFile(node.uri)),
    attrs=@html.Attrs::build()
      .data_set("workspace-id", node.uri.to_string())
      .data_set("workspace-kind", "file")
      .data_set("selected", selected.to_string())
      .aria_selected(selected.to_string())
      .style("--depth", row.depth.to_string()),
    [
      view_indent_guides(row.depth),
      @html.span(class="workspace-twistie workspace-twistie-spacer", ""),
      @html.span(class="workspace-file-icon", icon_file()),
      @html.span(class="workspace-label", node.name),
    ],
  )
}

///|
fn view_indent_guides(depth : Int) -> @html.Html {
  let guides : Array[@html.Html] = []
  for _ in 0..<depth {
    guides.push(@html.span(class="indent-guide", ""))
  }
  @html.span(class="workspace-guides", guides)
}
