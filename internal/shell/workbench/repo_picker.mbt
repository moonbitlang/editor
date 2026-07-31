// The repository picker: a modal directory browser over the server host's
// filesystem. Clicking a row navigates into that directory; "Open This
// Folder" re-roots the served workspace at the listed directory. The switch
// itself is confirmed by the server — the requesting session resumes through
// its correlated response, every other session reacts to the broadcast push.

///|
priv struct RepoPickerModel {
  /// Absolute host path currently listed; empty until the first listing
  /// (the server starts from the current workspace root).
  path : String
  parent : String?
  entries : Array[@remote_protocol.HostDirectoryEntry]
  loading : Bool
  error : String
} derive(Eq)

///|
fn opening_repo_picker() -> RepoPickerModel {
  { path: "", parent: None, entries: [], loading: true, error: "" }
}

///|
fn open_repo_picker_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  (
    list_host_directory_cmd(emit, ""),
    { ..model, repo_picker: Some(opening_repo_picker()) },
  )
}

///|
fn browse_repo_directory_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
  path : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) =>
      (
        list_host_directory_cmd(emit, path),
        { ..model, repo_picker: Some({ ..picker, loading: true, error: "" }) },
      )
    None => (@rabbita.none, model)
  }
}

///|
/// A listing landing after the picker was cancelled is dropped.
fn repo_directory_listed_update(
  model : WorkbenchModel,
  result : Result[@remote_protocol.HostDirectoryListing, String],
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) => {
      let picker = match result {
        Ok(listing) =>
          {
            path: listing.path,
            parent: listing.parent,
            entries: listing.entries,
            loading: false,
            error: "",
          }
        Err(message) => { ..picker, loading: false, error: message }
      }
      (@rabbita.none, { ..model, repo_picker: Some(picker) })
    }
    None => (@rabbita.none, model)
  }
}

///|
fn confirm_repo_picker_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) =>
      if picker.loading || picker.path == "" {
        (@rabbita.none, model)
      } else {
        (
          switch_workspace_cmd(emit, picker.path),
          { ..model, repo_picker: Some({ ..picker, loading: true, error: "" }) },
        )
      }
    None => (@rabbita.none, model)
  }
}

///|
fn repo_switch_failed_update(
  model : WorkbenchModel,
  message : String,
) -> (@rabbita.Cmd, WorkbenchModel) {
  match model.repo_picker {
    Some(picker) =>
      (
        @rabbita.none,
        {
          ..model,
          repo_picker: Some({ ..picker, loading: false, error: message }),
        },
      )
    None => (@rabbita.none, model)
  }
}

///|
/// The served workspace root changed (confirmed switch from this session or a
/// broadcast from another): drop everything scoped to the old root — active
/// document and its watch, viewer model, moon markers — then re-resolve the
/// explorer and auto-open the new workspace's first file.
fn workspace_root_switched_update(
  emit : @rabbita.Emit[WorkbenchMsg],
  model : WorkbenchModel,
) -> (@rabbita.Cmd, WorkbenchModel) {
  (
    @rabbita.batch([
      @cmd.custom_cmd(_ => close_active_document_source()),
      viewer_cmd(() => {
        workbench_services().remote_language.invalidate()
        workbench_services().markers.change_all("moon", [])
        workbench_viewer().set_model(None)
      }),
      workspace_file_tree().refresh(),
      auto_open_first_file_cmd(emit),
    ]),
    {
      ..model,
      repo_picker: None,
      status: "loading",
      status_message: "",
      document: None,
      line_count: 0,
      diagnostics: [],
      viewer_has_frame: false,
    },
  )
}

///|
fn list_host_directory_cmd(
  emit : @rabbita.Emit[WorkbenchMsg],
  path : String,
) -> @rabbita.Cmd {
  @cmd.perform(result => emit(RepoDirectoryListed(result)), async fn() noraise {
    let response = protocol_request("list-dir", id => {
      ListHostDirectory({ id, path })
    })
    match response {
      HostDirectoryListed(payload) => Ok(payload.listing)
      RemoteError(error) => Err(error.message)
      _ => Err("Unexpected protocol response for host directory listing.")
    }
  })
}

///|
fn switch_workspace_cmd(
  emit : @rabbita.Emit[WorkbenchMsg],
  path : String,
) -> @rabbita.Cmd {
  @cmd.perform(
    result => {
      match result {
        Ok(_) => emit(WorkspaceRootSwitched)
        Err(message) => emit(RepoSwitchFailed(message))
      }
    },
    async fn() noraise {
      let response = protocol_request("switch", id => {
        SwitchWorkspace({ id, path })
      })
      match response {
        WorkspaceSwitched(payload) => Ok(payload.root)
        RemoteError(error) => Err(error.message)
        _ => Err("Unexpected protocol response for workspace switch.")
      }
    },
  )
}

///|
fn view_repo_picker(
  emit : @rabbita.Emit[WorkbenchMsg],
  picker : RepoPickerModel,
) -> @html.Html {
  let rows : Array[@html.Html] = []
  match picker.parent {
    Some(parent) =>
      rows.push(
        @html.button(
          type_="button",
          class="repo-picker-entry repo-picker-parent",
          on_click=emit(BrowseRepoDirectory(parent)),
          attrs=@html.Attrs::build().data_set("repo-path", parent),
          [
            @html.span(class="repo-picker-entry-icon", icon_folder()),
            @html.span(class="repo-picker-entry-label", ".."),
          ],
        ),
      )
    None => ()
  }
  for entry in picker.entries {
    let children : Array[@html.Html] = [
      @html.span(class="repo-picker-entry-icon", icon_folder()),
      @html.span(class="repo-picker-entry-label", entry.name),
    ]
    if entry.is_workspace {
      children.push(@html.span(class="repo-picker-badge", "repo"))
    }
    rows.push(
      @html.button(
        type_="button",
        class="repo-picker-entry",
        on_click=emit(BrowseRepoDirectory(entry.path)),
        attrs=@html.Attrs::build().data_set("repo-path", entry.path),
        children,
      ),
    )
  }
  if !picker.loading && picker.entries.is_empty() {
    rows.push(@html.div(class="repo-picker-empty", "No subdirectories"))
  }
  let body : Array[@html.Html] = [
    @html.div(class="repo-picker-header", [
      @html.span(class="repo-picker-title", "Open Repository"),
      @html.button(
        type_="button",
        class="sidebar-action",
        title="Close",
        on_click=emit(CloseRepoPicker),
        attrs=@html.Attrs::build()
          .data_set("action", "close-repo-picker")
          .aria_label("Close repository picker"),
        "\u{2715}",
      ),
    ]),
    @html.div(
      class="repo-picker-path",
      if picker.path == "" {
        "Loading..."
      } else {
        picker.path
      },
    ),
  ]
  if picker.error != "" {
    body.push(@html.div(class="repo-picker-error", picker.error))
  }
  body.push(
    @html.div(
      class=if picker.loading {
        "repo-picker-list is-loading"
      } else {
        "repo-picker-list"
      },
      rows,
    ),
  )
  body.push(
    @html.div(class="repo-picker-footer", [
      @html.button(
        type_="button",
        class="repo-picker-button",
        on_click=emit(CloseRepoPicker),
        attrs=@html.Attrs::build().data_set("action", "cancel-repo-picker"),
        "Cancel",
      ),
      @html.button(
        type_="button",
        class="repo-picker-button repo-picker-button-primary",
        on_click=emit(ConfirmRepoPicker),
        attrs=@html.Attrs::build().data_set("action", "confirm-repo-picker"),
        "Open This Folder",
      ),
    ]),
  )
  @html.div(class="repo-picker-overlay", [
    @html.div(
      class="repo-picker",
      attrs=@html.Attrs::build().aria_label("Open repository"),
      body,
    ),
  ])
}
