///|
/// Root-owned adapter from one rendered Markdown projection to the shared
/// definition contribution. It never creates a virtual code model: native
/// caret hits are reduced to original-model offsets before entering provider
/// state.
priv struct MarkdownDocumentDefinitionBridge {
  viewer : Viewer
  view : @markdown_document.MarkdownDocumentView
  model : @model.TextModel
  attach_generation : Int
  listeners : Array[@base_common.Disposable]
  mut active : Bool
  mut disposed : Bool
}

///|
fn MarkdownDocumentDefinitionBridge::MarkdownDocumentDefinitionBridge(
  viewer : Viewer,
  view : @markdown_document.MarkdownDocumentView,
  model : @model.TextModel,
  attach_generation : Int,
) -> MarkdownDocumentDefinitionBridge {
  {
    viewer,
    view,
    model,
    attach_generation,
    listeners: [],
    active: false,
    disposed: false,
  }
}

///|
fn MarkdownDocumentDefinitionBridge::is_current(
  self : MarkdownDocumentDefinitionBridge,
) -> Bool {
  self.active &&
  !self.disposed &&
  self.viewer.is_current_model_data_generation(self.attach_generation) &&
  self.viewer.is_current_model(self.model) &&
  !self.model.is_disposed() &&
  self.view.source_model_version() == self.model.get_version_id()
}

///|
fn MarkdownDocumentDefinitionBridge::listen(
  self : MarkdownDocumentDefinitionBridge,
  element : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  element.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      element.remove_event_listener(event_name, listener)
    }),
  )
}

///|
fn MarkdownDocumentDefinitionBridge::target_at(
  self : MarkdownDocumentDefinitionBridge,
  client_x : Double,
  client_y : Double,
) -> @definition.DefinitionTargetFingerprint? {
  guard self.is_current() &&
    self.view.semantic_pointer_hit(client_x, client_y) is Some(hit) else {
    return None
  }
  self.viewer.definition_target_from_source_offset(hit.source_offset)
}

///|
fn MarkdownDocumentDefinitionBridge::bind_semantic_dom(
  self : MarkdownDocumentDefinitionBridge,
) -> Unit {
  guard self.is_current() else { return }
  self.view.listen_semantic_dom("mousemove", event => {
    guard event.to_mouse_event() is Some(mouse) else {
      self.viewer.clear_markdown_context_menu_anchor()
      self.viewer.reset_definition_link()
      return
    }
    let client_x = mouse.get_client_x().to_double()
    let client_y = mouse.get_client_y().to_double()
    let target = self.target_at(client_x, client_y)
    self.viewer.handle_definition_pointer_move(
      target,
      mouse.get_ctrl_key(),
      mouse.get_meta_key(),
      mouse.get_alt_key(),
      mouse.get_shift_key(),
      mouse.get_buttons(),
    )
    if mouse.get_buttons() == 0 {
      self.viewer.record_markdown_context_menu_anchor(
        target, client_x, client_y,
      )
    } else {
      self.viewer.clear_markdown_context_menu_anchor()
    }
  })
  self.view.listen_semantic_dom("contextmenu", event => {
    guard self.is_current() && event.to_mouse_event() is Some(mouse) else {
      return
    }
    let client_x = mouse.get_client_x().to_double()
    let client_y = mouse.get_client_y().to_double()
    if self.viewer.show_markdown_context_menu(
        self.target_at(client_x, client_y),
        client_x,
        client_y,
      ) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  self.view.listen_semantic_dom("mousedown", event => {
    guard self.is_current() && event.to_mouse_event() is Some(mouse) else {
      return
    }
    let standard = @base_browser.StandardMouseEvent(mouse)
    guard standard.left_button && standard.detail <= 1 else { return }
    let target = self.target_at(
      mouse.get_client_x().to_double(),
      mouse.get_client_y().to_double(),
    )
    self.viewer.focus()
    let modifier_active = definition_link_modifier_is_active(
      standard.ctrl_key,
      standard.meta_key,
      standard.alt_key,
      standard.shift_key,
    )
    if !modifier_active {
      self.viewer.commit_plain_definition_pointer_target(target)
    } else if self.viewer.before_definition_target_mouse_down(target) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  self.view.listen_semantic_dom("mouseup", event => {
    guard self.is_current() && event.to_mouse_event() is Some(mouse) else {
      return
    }
    let standard = @base_browser.StandardMouseEvent(mouse)
    let handled = self.viewer.handle_definition_pointer_up(
      self.target_at(
        mouse.get_client_x().to_double(),
        mouse.get_client_y().to_double(),
      ),
      mouse.get_ctrl_key(),
      mouse.get_meta_key(),
      mouse.get_alt_key(),
      mouse.get_shift_key(),
      left_button=standard.left_button,
      detail=standard.detail,
    )
    if handled {
      event.prevent_default()
      event.stop_propagation()
    }
  })
}

///|
fn MarkdownDocumentDefinitionBridge::activate(
  self : MarkdownDocumentDefinitionBridge,
) -> Unit {
  guard !self.active && !self.disposed else { return }
  self.active = true
  self.listen(self.view.root(), "keydown", event => {
    guard self.is_current() &&
      @base_browser.event_target_is(event, self.view.root()) &&
      event.to_keyboard_event() is Some(keyboard) else {
      return
    }
    self.viewer.handle_definition_modifier_key(
      keyboard.key(),
      true,
      keyboard.ctrl_key(),
      keyboard.meta_key(),
      keyboard.alt_key(),
      keyboard.shift_key(),
    )
    if self.viewer.handle_markdown_definition_key_down(
        keyboard.key(),
        keyboard.alt_key(),
        keyboard.ctrl_key() || keyboard.meta_key(),
        keyboard.shift_key(),
      ) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  self.listen(self.view.root(), "keyup", event => {
    guard self.is_current() &&
      @base_browser.event_target_is(event, self.view.root()) &&
      event.to_keyboard_event() is Some(keyboard) else {
      return
    }
    self.viewer.handle_definition_modifier_key(
      keyboard.key(),
      false,
      keyboard.ctrl_key(),
      keyboard.meta_key(),
      keyboard.alt_key(),
      keyboard.shift_key(),
    )
  })
  self.listen(self.view.root(), "mouseleave", _ => {
    // Inserting the detached menu under the stationary pointer can make the
    // browser synthesize a leave from the Markdown article. Retire only the
    // modifier gesture while that menu is visible so Escape followed by
    // Shift+F10 can still use the clicked semantic source anchor.
    if self.viewer.context_menu_is_visible() {
      self.viewer.cancel_definition_link()
    } else {
      self.viewer.clear_markdown_context_menu_anchor()
      self.viewer.reset_definition_link()
    }
  })
  // Peek moves focus into its overlay while the provider request remains
  // anchored to the last semantic pointer hit.
  self.listen(self.view.root(), "blur", _ => {
    self.viewer.cancel_definition_link()
  })
  self.listen(self.view.viewport(), "scroll", _ => {
    self.viewer.clear_markdown_context_menu_anchor()
    self.viewer.reset_definition_link()
  })
  self.bind_semantic_dom()
}

///|
fn MarkdownDocumentDefinitionBridge::before_projection_replaced(
  self : MarkdownDocumentDefinitionBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.viewer.reset_definition_requests()
}

///|
fn MarkdownDocumentDefinitionBridge::after_projection_replaced(
  self : MarkdownDocumentDefinitionBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.bind_semantic_dom()
}

///|
fn MarkdownDocumentDefinitionBridge::layout_changed(
  self : MarkdownDocumentDefinitionBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.viewer.clear_markdown_context_menu_anchor()
  self.viewer.reset_definition_link()
}

///|
fn MarkdownDocumentDefinitionBridge::dispose(
  self : MarkdownDocumentDefinitionBridge,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.viewer.reset_definition_requests()
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
}
