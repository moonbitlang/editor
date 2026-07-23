///|
/// The browser-attachment state of a Viewer. Construction starts headless and
/// `attach` performs the sole transition to `Mounted`; disposal deliberately
/// retains the mounted host so `get_container_dom_node` remains valid.
priv enum ViewerMount {
  Headless
  Mounted(MountedViewer)
}

///|
/// Viewer-lifetime state that exists only after a host has been attached.
/// Per-model browser state remains owned by `ModelBrowserData`.
priv struct MountedViewer {
  container : @rdom.Element
  mut placeholder : PlaceholderDom?
  mut render_frame : @base_common.Disposable?
  mut editor_has_focus : Bool
}

///|
/// The no-model placeholder is one atomic DOM capability: callers can never
/// observe a root without its corresponding text node.
priv struct PlaceholderDom {
  root : @rdom.Element
  text : @rdom.Element
}

///|
fn PlaceholderDom::PlaceholderDom(theme : String) -> PlaceholderDom {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", @view.empty_editor_class_name())
  root.set_attribute("data-theme", theme)
  let message = document.create_element("div")
  message.set_attribute("class", "source-message")
  let text = document.create_text_node("")
  message.append_child(text.as_node())
  root.append_child(message.as_node())
  { root, text }
}

///|
fn PlaceholderDom::apply_theme(self : PlaceholderDom, theme : String) -> Unit {
  self.root.set_attribute("data-theme", theme)
}

///|
fn PlaceholderDom::render(
  self : PlaceholderDom,
  class_name : String,
  message : String,
) -> Unit {
  self.root.set_attribute("class", class_name)
  self.text.set_node_value(@js.Nullable::from_option(Some(message)))
}

///|
fn MountedViewer::MountedViewer(
  container : @rdom.Element,
  placeholder : PlaceholderDom,
) -> MountedViewer {
  {
    container,
    placeholder: Some(placeholder),
    render_frame: None,
    editor_has_focus: false,
  }
}

///|
fn MountedViewer::cancel_render_frame(self : MountedViewer) -> Unit {
  match self.render_frame {
    Some(frame) => {
      // Clear first so cancellation/disposal callbacks cannot observe a stale
      // publication or suppress a later legitimate schedule.
      self.render_frame = None
      frame.dispose()
    }
    None => ()
  }
}

///|
fn MountedViewer::schedule_render(
  self : MountedViewer,
  callback : () -> Unit,
) -> Unit {
  if self.render_frame is Some(_) {
    return
  }
  self.render_frame = Some(
    @base_browser.run_at_this_or_schedule_at_next_animation_frame(
      () => {
        // The scheduled slot is idle before any Viewer callback runs.
        self.render_frame = None
        callback()
      },
      priority=100,
    ),
  )
}

///|
fn MountedViewer::has_pending_render(self : MountedViewer) -> Bool {
  self.render_frame is Some(_)
}

///|
fn MountedViewer::set_editor_focus(
  self : MountedViewer,
  focused : Bool,
) -> Bool {
  if self.editor_has_focus == focused {
    return false
  }
  self.editor_has_focus = focused
  true
}

///|
fn MountedViewer::apply_placeholder_theme(
  self : MountedViewer,
  theme : String,
) -> Unit {
  match self.placeholder {
    Some(placeholder) => placeholder.apply_theme(theme)
    None => ()
  }
}

///|
fn MountedViewer::render_placeholder(
  self : MountedViewer,
  class_name : String,
  message : String,
) -> Unit {
  match self.placeholder {
    Some(placeholder) => placeholder.render(class_name, message)
    None => ()
  }
}

///|
fn MountedViewer::hide_placeholder(self : MountedViewer) -> Unit {
  match self.placeholder {
    Some(placeholder) =>
      remove_element_if_contained(self.container, placeholder.root)
    None => ()
  }
}

///|
fn MountedViewer::restore_placeholder(self : MountedViewer) -> Unit {
  match self.placeholder {
    Some(placeholder) =>
      if !@base_browser.element_contains(self.container, placeholder.root) {
        self.container.append_child(placeholder.root.as_node())
      }
    None => ()
  }
}

///|
fn MountedViewer::remove_view(
  self : MountedViewer,
  root : @rdom.Element,
  restore_placeholder~ : Bool,
) -> Unit {
  remove_element_if_contained(self.container, root)
  if restore_placeholder {
    self.restore_placeholder()
  }
}

///|
fn MountedViewer::remove_owned_placeholder_dom(self : MountedViewer) -> Unit {
  self.hide_placeholder()
}

///|
fn MountedViewer::clear_disposed_state(self : MountedViewer) -> Unit {
  self.placeholder = None
  self.editor_has_focus = false
}

///|
fn ViewerMount::has_pending_render(self : ViewerMount) -> Bool {
  match self {
    Headless => false
    Mounted(mounted) => mounted.has_pending_render()
  }
}
