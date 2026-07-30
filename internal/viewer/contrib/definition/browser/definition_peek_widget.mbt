///|
/// Root-owned behavior injected into the browser-only Peek shell. Selection
/// and confirmation carry the result index so a host never has to infer it
/// from mutable DOM state.
pub(all) struct DefinitionPeekWidgetCallbacks {
  on_close : () -> Unit
  on_select : (Int) -> Unit
  on_confirm : (Int) -> Unit
  on_next : () -> Unit
  on_previous : () -> Unit
}

///|
/// The fixed ViewZone height used by the initial Peek implementation. The root
/// Viewer remains the ViewZone owner and may translate this line count through
/// its live layout configuration.
pub let definition_peek_height_in_lines : Int = 12

///|
/// Browser DOM shell for one Peek Definition session. `preview_host` is empty
/// shell-owned space: the root Viewer mounts and tears down the nested Viewer
/// there without creating a dependency cycle.
pub struct DefinitionPeekWidget {
  priv root : @rdom.Element
  priv list : @rdom.Element
  priv preview_host : @rdom.Element
  priv status : @rdom.Element
  priv callbacks : DefinitionPeekWidgetCallbacks
  priv persistent_listeners : Array[@base_common.Disposable]
  priv result_listeners : Array[@base_common.Disposable]
  priv mut locations : Array[@language.Location]
  priv mut selected_index : Int
  priv mut disposed : Bool
}

///|
/// Constructs the detached shell. The caller appends `get_dom_node()` to its
/// ViewZone before mounting a nested Viewer into `get_preview_host()`.
#alias(new, deprecated)
pub fn DefinitionPeekWidget::DefinitionPeekWidget(
  callbacks : DefinitionPeekWidgetCallbacks,
) -> DefinitionPeekWidget {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-viewer-definition-peek")
  root.set_attribute("role", "dialog")
  root.set_attribute("aria-label", "Peek Definition")
  root.set_attribute("tabindex", "-1")

  let header = document.create_element("header")
  header.set_attribute("class", "moonbit-viewer-definition-peek-header")
  let title = document.create_element("span")
  title.set_attribute("class", "moonbit-viewer-definition-peek-title")
  title.append_child(document.create_text_node("Peek Definition").as_node())
  header.append_child(title.as_node())
  let close = document.create_element("button")
  close.set_attribute("class", "moonbit-viewer-definition-peek-close")
  close.set_attribute("type", "button")
  close.set_attribute("aria-label", "Close Peek Definition")
  close.append_child(document.create_text_node("\u{00d7}").as_node())
  header.append_child(close.as_node())
  root.append_child(header.as_node())

  let body = document.create_element("div")
  body.set_attribute("class", "moonbit-viewer-definition-peek-body")
  let list = document.create_element("div")
  list.set_attribute("class", "moonbit-viewer-definition-peek-list")
  list.set_attribute("role", "listbox")
  list.set_attribute("aria-label", "Definition locations")
  let preview_host = document.create_element("div")
  preview_host.set_attribute("class", "moonbit-viewer-definition-peek-preview")
  preview_host.set_attribute("aria-label", "Definition preview")
  let status = document.create_element("div")
  status.set_attribute("class", "moonbit-viewer-definition-peek-status")
  status.set_attribute("role", "status")
  status.set_attribute("aria-live", "polite")
  body.append_child(list.as_node())
  body.append_child(preview_host.as_node())
  body.append_child(status.as_node())
  root.append_child(body.as_node())

  let widget : DefinitionPeekWidget = {
    root,
    list,
    preview_host,
    status,
    callbacks,
    persistent_listeners: [],
    result_listeners: [],
    locations: [],
    selected_index: -1,
    disposed: false,
  }
  widget.install_persistent_listeners(close)
  widget.show_loading()
  widget
}

///|
/// Root node appended by the ViewZone owner.
pub fn DefinitionPeekWidget::get_dom_node(
  self : DefinitionPeekWidget,
) -> @rdom.Element {
  self.root
}

///|
/// Result-list node, exposed for root-level layout and browser tests.
pub fn DefinitionPeekWidget::get_list_node(
  self : DefinitionPeekWidget,
) -> @rdom.Element {
  self.list
}

///|
/// Empty node where the root Viewer mounts its nested readonly Viewer.
pub fn DefinitionPeekWidget::get_preview_host(
  self : DefinitionPeekWidget,
) -> @rdom.Element {
  self.preview_host
}

///|
/// Moves focus to the shell without scrolling the outer editor.
pub fn DefinitionPeekWidget::focus(self : DefinitionPeekWidget) -> Unit {
  if !self.disposed {
    @base_browser.focus_prevent_scroll(self.root)
  }
}

///|
/// Replaces the result UI with a non-destructive loading state.
pub fn DefinitionPeekWidget::show_loading(self : DefinitionPeekWidget) -> Unit {
  if self.disposed {
    return
  }
  self.clear_results()
  self.list.set_attribute("hidden", "")
  self.status.remove_attribute("hidden")
  self.status.set_attribute(
    "class", "moonbit-viewer-definition-peek-status moonbit-viewer-definition-peek-loading",
  )
  self.status.set_inner_html("")
  self.status.append_child(
    @rdom.document().create_text_node("Loading definitions\u{2026}").as_node(),
  )
  self.preview_host.set_attribute("aria-busy", "true")
}

///|
/// Replaces the result UI with an unavailable state supplied by the root.
pub fn DefinitionPeekWidget::show_unavailable(
  self : DefinitionPeekWidget,
  message : String,
) -> Unit {
  if self.disposed {
    return
  }
  self.clear_results()
  self.list.set_attribute("hidden", "")
  self.status.remove_attribute("hidden")
  self.status.set_attribute(
    "class", "moonbit-viewer-definition-peek-status moonbit-viewer-definition-peek-unavailable",
  )
  self.status.set_inner_html("")
  self.status.append_child(@rdom.document().create_text_node(message).as_node())
  self.preview_host.remove_attribute("aria-busy")
}

///|
/// Shows preview-resolution progress without replacing the definition result
/// list or its selected index. The caller releases any prior preview child
/// before entering this state.
pub fn DefinitionPeekWidget::show_preview_loading(
  self : DefinitionPeekWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.status.remove_attribute("hidden")
  self.status.set_attribute(
    "class", "moonbit-viewer-definition-peek-status moonbit-viewer-definition-peek-loading",
  )
  self.status.set_inner_html("")
  self.status.append_child(
    @rdom.document().create_text_node("Loading preview\u{2026}").as_node(),
  )
  self.preview_host.set_attribute("aria-busy", "true")
}

///|
/// Shows a per-result preview failure while retaining the list and selection,
/// so the user can switch to another definition.
pub fn DefinitionPeekWidget::show_preview_unavailable(
  self : DefinitionPeekWidget,
  message : String,
) -> Unit {
  if self.disposed {
    return
  }
  self.status.remove_attribute("hidden")
  self.status.set_attribute(
    "class", "moonbit-viewer-definition-peek-status moonbit-viewer-definition-peek-unavailable",
  )
  self.status.set_inner_html("")
  self.status.append_child(@rdom.document().create_text_node(message).as_node())
  self.preview_host.remove_attribute("aria-busy")
}

///|
/// Hides a per-result preview status after the nested Viewer is mounted.
pub fn DefinitionPeekWidget::show_preview_ready(
  self : DefinitionPeekWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.status.set_attribute("hidden", "")
  self.status.set_inner_html("")
  self.preview_host.remove_attribute("aria-busy")
}

///|
/// Rebuilds the ordered location list. Empty input becomes the standard
/// no-definition unavailable state. A non-empty selection is clamped into the
/// new list and reflected through `aria-selected`.
pub fn DefinitionPeekWidget::set_locations(
  self : DefinitionPeekWidget,
  locations : Array[@language.Location],
  selected_index : Int,
) -> Unit {
  if self.disposed {
    return
  }
  self.clear_results()
  if locations.length() == 0 {
    self.show_unavailable("No definition found")
    return
  }
  self.locations = locations.copy()
  self.selected_index = clamp_definition_peek_index(
    selected_index,
    self.locations.length(),
  )
  self.status.set_attribute("hidden", "")
  self.list.remove_attribute("hidden")
  self.preview_host.remove_attribute("aria-busy")
  let document = @rdom.document()
  let count = self.locations.length()
  for i in 0..<count {
    let index = i
    let item = document.create_element("button")
    item.set_attribute(
      "class",
      definition_peek_item_class(index == self.selected_index),
    )
    item.set_attribute("type", "button")
    item.set_attribute("role", "option")
    item.set_attribute("tabindex", "-1")
    item.set_attribute(
      "aria-selected",
      if index == self.selected_index {
        "true"
      } else {
        "false"
      },
    )
    item.set_attribute("aria-posinset", (index + 1).to_string())
    item.set_attribute("aria-setsize", count.to_string())
    item.set_attribute("data-definition-index", index.to_string())
    item.append_child(
      document
      .create_text_node(definition_peek_location_label(self.locations[index]))
      .as_node(),
    )
    self.listen_result(item, "click", event => {
      event.prevent_default()
      event.stop_propagation()
      if !self.disposed {
        self.set_selected_index(index)
        (self.callbacks.on_select)(index)
      }
    })
    self.listen_result(item, "dblclick", event => {
      event.prevent_default()
      event.stop_propagation()
      if !self.disposed {
        self.set_selected_index(index)
        (self.callbacks.on_select)(index)
        (self.callbacks.on_confirm)(index)
      }
    })
    self.list.append_child(item.as_node())
  }
}

///|
/// Applies the host's selected result. Out-of-range values clamp to the
/// closest valid row; with no results the selection remains absent.
pub fn DefinitionPeekWidget::set_selected_index(
  self : DefinitionPeekWidget,
  selected_index : Int,
) -> Unit {
  if self.disposed || self.locations.length() == 0 {
    return
  }
  self.selected_index = clamp_definition_peek_index(
    selected_index,
    self.locations.length(),
  )
  let children = self.list.get_children()
  for i in 0..<children.length() {
    let selected = i == self.selected_index
    children[i].set_attribute("class", definition_peek_item_class(selected))
    children[i].set_attribute(
      "aria-selected",
      if selected {
        "true"
      } else {
        "false"
      },
    )
  }
}

///|
/// Current selected result, or `None` while loading/unavailable.
pub fn DefinitionPeekWidget::get_selected_index(
  self : DefinitionPeekWidget,
) -> Int? {
  if self.selected_index >= 0 && self.selected_index < self.locations.length() {
    Some(self.selected_index)
  } else {
    None
  }
}

///|
/// Releases all listeners exactly once. The caller separately owns ViewZone
/// removal and the nested Viewer/reference teardown.
pub fn DefinitionPeekWidget::dispose(self : DefinitionPeekWidget) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.dispose_result_listeners()
  while self.persistent_listeners.length() > 0 {
    self.persistent_listeners
    .remove(self.persistent_listeners.length() - 1)
    .dispose()
  }
}

///|
fn DefinitionPeekWidget::install_persistent_listeners(
  self : DefinitionPeekWidget,
  close : @rdom.Element,
) -> Unit {
  self.listen_persistent(close, "click", event => {
    event.prevent_default()
    event.stop_propagation()
    if !self.disposed {
      (self.callbacks.on_close)()
    }
  })
  // Let native Enter/Space activate the close button without being interpreted
  // as "confirm definition" by the shell root. Other keys still bubble into
  // the Peek command router, so Escape and F4 work while the button is focused.
  self.listen_persistent(close, "keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        match keyboard.key() {
          "Enter" | " " | "Spacebar" => event.stop_propagation()
          _ => ()
        }
      None => ()
    }
  })
  // Enter confirms only from the result-list focus domain. Keeping this
  // listener on the list (rather than inferring descendants at the shell
  // root) also lets Enter retain its native meaning inside the nested preview.
  self.listen_persistent(self.list, "keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        if keyboard.key() == "Enter" {
          event.stop_propagation()
          guard self.get_selected_index() is Some(index) else { return }
          event.prevent_default()
          (self.callbacks.on_confirm)(index)
        }
      None => ()
    }
  })
  for
    event_type in [
      "mousedown", "mouseup", "click", "contextmenu", "focusin", "focusout", "wheel",
    ] {
    self.listen_persistent(self.root, event_type, event => {
      event.stop_propagation()
    })
  }
  self.listen_persistent(self.root, "keydown", event => {
    event.stop_propagation()
    guard !self.disposed else { return }
    match event.to_keyboard_event() {
      Some(keyboard) =>
        match keyboard.key() {
          "Escape" => {
            event.prevent_default()
            (self.callbacks.on_close)()
          }
          "Enter" => {
            // `focus()` deliberately focuses the shell root while loading.
            // Result-list Enter is handled above; Enter from the nested
            // preview must stop here without confirming the selected result.
            guard @base_browser.event_target_is(event, self.root) else {
              return
            }
            guard self.get_selected_index() is Some(index) else { return }
            event.prevent_default()
            (self.callbacks.on_confirm)(index)
          }
          "F4" => {
            event.prevent_default()
            if keyboard.shift_key() {
              (self.callbacks.on_previous)()
            } else {
              (self.callbacks.on_next)()
            }
          }
          _ => ()
        }
      None => ()
    }
  })
}

///|
fn DefinitionPeekWidget::listen_persistent(
  self : DefinitionPeekWidget,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  self.persistent_listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn DefinitionPeekWidget::listen_result(
  self : DefinitionPeekWidget,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  self.result_listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn DefinitionPeekWidget::clear_results(self : DefinitionPeekWidget) -> Unit {
  self.dispose_result_listeners()
  self.list.set_inner_html("")
  self.locations = []
  self.selected_index = -1
}

///|
fn DefinitionPeekWidget::dispose_result_listeners(
  self : DefinitionPeekWidget,
) -> Unit {
  while self.result_listeners.length() > 0 {
    self.result_listeners.remove(self.result_listeners.length() - 1).dispose()
  }
}

///|
fn clamp_definition_peek_index(index : Int, length : Int) -> Int {
  if length <= 0 {
    -1
  } else if index < 0 {
    0
  } else if index >= length {
    length - 1
  } else {
    index
  }
}

///|
fn definition_peek_item_class(selected : Bool) -> String {
  if selected {
    "moonbit-viewer-definition-peek-item selected"
  } else {
    "moonbit-viewer-definition-peek-item"
  }
}

///|
fn definition_peek_location_label(location : @language.Location) -> String {
  let start = location.range.get_start_position()
  location.uri.to_string() +
  ":" +
  start.line_number.to_string() +
  ":" +
  start.column.to_string()
}
