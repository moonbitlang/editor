// Root policy for the selected behavior port of Monaco's
// `ContextMenuController`. Browser DOM/lifetime lives in
// `internal/viewer/contrib/contextmenu/browser`; this file owns editor target
// filtering, cursor/selection policy, command resolution, and Code anchors.

///|
let context_menu_contribution_id : String = "editor.contrib.contextmenu"

///|
priv struct MarkdownContextMenuAnchor {
  client_x : Double
  client_y : Double
}

///|
priv struct ContextMenuContributionState {
  mut widget : @contextmenu_browser.ContextMenuWidget?
  mut markdown_anchor : MarkdownContextMenuAnchor?
  mut disposed : Bool
}

///|
fn ContextMenuContributionState::ContextMenuContributionState() -> ContextMenuContributionState {
  { widget: None, markdown_anchor: None, disposed: false }
}

///|
/// The shell is browser-only and therefore created on first mounted show,
/// keeping headless Viewer construction DOM-free.
fn ContextMenuContributionState::get_or_create_widget(
  self : ContextMenuContributionState,
  viewer : Viewer,
) -> @contextmenu_browser.ContextMenuWidget? {
  if self.disposed {
    return None
  }
  match self.widget {
    Some(widget) => Some(widget)
    None => {
      let widget = @contextmenu_browser.ContextMenuWidget({
        on_action: command_id => {
          editor_registry().run_editor_command(viewer, command_id) |> ignore
        },
        on_hide: _was_cancelled => (),
      })
      self.widget = Some(widget)
      Some(widget)
    }
  }
}

///|
fn ContextMenuContributionState::dispose(
  self : ContextMenuContributionState,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  match self.widget {
    Some(widget) => widget.dispose()
    None => ()
  }
  self.widget = None
  self.markdown_anchor = None
}

///|
fn register_context_menu_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    context_menu_contribution_id,
    BeforeFirstInteraction,
    _viewer => ContextMenu(ContextMenuContributionState()),
    viewer => {
      [
        viewer.on_context_menu(event => viewer.on_editor_context_menu(event)),
        viewer.on_did_change_model(_ => {
          viewer.clear_markdown_context_menu_anchor()
          viewer.hide_context_menu()
        }),
        viewer.on_did_change_model_content(_ => {
          viewer.clear_markdown_context_menu_anchor()
          viewer.hide_context_menu()
        }),
        viewer.on_did_scroll_change(_ => {
          viewer.clear_markdown_context_menu_anchor()
          viewer.hide_context_menu()
        }),
      ]
    },
  )
  registry.register_editor_command(
    "editor.action.showContextMenu",
    viewer => viewer.code_context_menu_available(),
    viewer => viewer.show_code_context_menu_from_keyboard() |> ignore,
    [("ContextMenu", false, false)],
    shift_keybindings=[("F10", false, false)],
    title="Show Editor Context Menu",
  )
}

///|
fn Viewer::context_menu_contribution(
  self : Viewer,
) -> ContextMenuContributionState? {
  match self.contributions.lookup(context_menu_contribution_id) {
    Some(entry) =>
      match entry.instance {
        ContextMenu(state) => Some(state)
        _ => None
      }
    None => None
  }
}

///|
fn Viewer::code_context_menu_available(self : Viewer) -> Bool {
  !self.disposed &&
  self.get_model() is Some(_) &&
  self.current_code_browser_data() is Some(_)
}

///|
fn Viewer::hide_context_menu(self : Viewer) -> Unit {
  match self.context_menu_contribution() {
    Some(state) =>
      match state.widget {
        Some(widget) => widget.hide(was_cancelled=true)
        None => ()
      }
    None => ()
  }
}

///|
fn Viewer::context_menu_is_visible(self : Viewer) -> Bool {
  match self.context_menu_contribution() {
    Some(state) =>
      match state.widget {
        Some(widget) => widget.is_visible()
        None => false
      }
    None => false
  }
}

///|
fn Viewer::clear_markdown_context_menu_anchor(self : Viewer) -> Unit {
  match self.context_menu_contribution() {
    Some(state) => state.markdown_anchor = None
    None => ()
  }
}

///|
fn Viewer::record_markdown_context_menu_anchor(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
  client_x : Double,
  client_y : Double,
) -> Unit {
  guard self.context_menu_contribution() is Some(state) else { return }
  state.markdown_anchor = match target {
    Some(target) if self.definition_link_target_is_current(target) =>
      Some({ client_x, client_y })
    _ => None
  }
}

///|
/// `_onContextMenu`: only text and content-empty hits enter the custom menu.
/// Injected text, widgets, scrollbars, margins, zones, and unknown regions
/// retain the browser's native menu because this readonly port has no actions
/// for those surfaces.
fn Viewer::on_editor_context_menu(
  self : Viewer,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  guard self.code_context_menu_available() else { return }
  match event.target {
    MouseTargetContentText(detail~, ..) if detail.injected_text is Some(_) =>
      return
    MouseTargetContentText(..) | MouseTargetContentEmpty(..) => ()
    _ => return
  }
  // The selected surface contains only currently available commands. When
  // that set is empty, leave the native browser menu intact instead of
  // suppressing it in favor of an invisible custom menu.
  guard editor_registry().resolve_editor_menu(self, EditorContext).length() > 0 else {
    return
  }
  event.event.prevent_default()
  event.event.stop_propagation()
  self.focus()
  match event.target.position() {
    Some(position) => {
      let mut inside_selection = false
      match self.get_selections() {
        Some(selections) =>
          for selection in selections {
            let start = selection.start()
            let end = selection.end()
            if @base_common.Range(
                start.line_number,
                start.column,
                end.line_number,
                end.column,
              ).contains_position(position) {
              inside_selection = true
              break
            }
          }
        None => ()
      }
      if !inside_selection {
        self.set_position(position, source="contextmenu")
      }
    }
    None => ()
  }
  let client = event.event.pos.to_client_coordinates()
  self.show_context_menu_at(client.client_x, client.client_y) |> ignore
}

///|
fn Viewer::show_context_menu_at(
  self : Viewer,
  client_x : Double,
  client_y : Double,
  auto_select_first? : Bool = false,
) -> Bool {
  guard self.context_menu_contribution() is Some(state) else { return false }
  guard state.get_or_create_widget(self) is Some(widget) else { return false }
  guard self.current_browser_presentation() is Some(presentation) else {
    return false
  }
  let entries = editor_registry().resolve_editor_menu(self, EditorContext)
  widget.show(
    entries,
    client_x,
    client_y,
    self.configuration.snapshot().options.theme,
    theme_source=presentation.root(),
    auto_select_first~,
  )
}

///|
/// Keyboard invocation anchors under the rendered Code cursor after a
/// synchronous flush, matching Monaco's reveal/render/visible-position path.
fn Viewer::show_code_context_menu_from_keyboard(self : Viewer) -> Bool {
  guard self.code_context_menu_available() else { return false }
  guard self.get_position() is Some(position) else { return false }
  self.reveal_position(position)
  self.flush_render()
  guard self.get_scrolled_visible_position(position) is Some(cursor) else {
    return false
  }
  guard self.current_browser_presentation() is Some(presentation) else {
    return false
  }
  let rect = presentation.root().get_bounding_client_rect()
  self.show_context_menu_at(
    rect.get_left() + cursor.left,
    rect.get_top() + cursor.top + cursor.height,
    auto_select_first=true,
  )
}

///|
/// A semantic Markdown row supplies its original-model target before the menu
/// is resolved. Ordinary Markdown and projected padding return false so their
/// browser-native context menu remains untouched.
fn Viewer::show_markdown_context_menu(
  self : Viewer,
  target : @definition.DefinitionTargetFingerprint?,
  client_x : Double,
  client_y : Double,
) -> Bool {
  guard self.current_markdown_document() is Some(_) &&
    target is Some(target) &&
    self.definition_link_target_is_current(target) else {
    self.reset_definition_link()
    return false
  }
  guard editor_registry().resolve_editor_menu(self, EditorContext).length() > 0 else {
    self.reset_definition_link()
    return false
  }
  self.record_markdown_context_menu_anchor(Some(target), client_x, client_y)
  self.commit_plain_definition_pointer_target(Some(target))
  self.focus()
  self.show_context_menu_at(client_x, client_y)
}

///|
/// The Markdown presentation has no Code cursor geometry. Its keyboard menu
/// therefore reuses the most recent still-valid semantic pointer coordinate,
/// which is the same projected source anchor used by F12.
fn Viewer::show_markdown_context_menu_from_keyboard(self : Viewer) -> Bool {
  guard self.current_markdown_document() is Some(_) &&
    self.definition_command_position() is Some(_) &&
    self.context_menu_contribution() is Some(state) &&
    state.markdown_anchor is Some(anchor) else {
    return false
  }
  self.show_context_menu_at(
    anchor.client_x,
    anchor.client_y,
    auto_select_first=true,
  )
}
