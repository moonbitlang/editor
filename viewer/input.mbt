///|
/// Hooks the view's native input listeners. The pointer input (moves, downs,
/// ups, leaves, selection drags) is owned entirely by the
/// `internal/viewer/browser/controller` `MouseHandler`, which registers its own
/// DOM listeners on the view root through `EditorMouseEventFactory` — the
/// viewer builds it here with a `PointerHandlerHelper` closing over the view (the
/// local analog of Monaco's `View._createPointerHandlerHelper`). Copy,
/// keyboard, focus tracking, wheel and the scrollbar/browser-reveal cluster
/// stay here.
fn Viewer::hook_view_input(
  self : Viewer,
  view : @view.View,
) -> @controller.MouseHandler {
  let handler = @controller.MouseHandler(self.pointer_handler_helper(view))
  // View is the sole disposable owner. ModelBrowserData only retains this
  // reference so lifecycle commands can reach the live per-View handler.
  view.add_disposable(@base_common.Disposable::from(() => handler.dispose()))
  // Monaco tracks focus on the hidden textarea / edit context and fans it out
  // as `ViewFocusChangedEvent`; the viewer's focusable surface is the root
  // itself. `focus`/`blur` do not bubble, so these observe only the root's own
  // focus and emit only on the actual Bool transition.
  add_view_event_listener(view, view.root, "focus", _ => {
    match self.mount {
      Headless => ()
      Mounted(mounted) =>
        if mounted.set_editor_focus(true) {
          self.emit_view_event(ViewFocusChanged(ViewFocusChangedEvent(true)))
          self.schedule_render()
        }
    }
  })
  add_view_event_listener(view, view.root, "blur", _ => {
    match self.mount {
      Headless => ()
      Mounted(mounted) =>
        if mounted.set_editor_focus(false) {
          self.emit_view_event(ViewFocusChanged(ViewFocusChangedEvent(false)))
          self.schedule_render()
        }
    }
  })
  add_view_event_listener(view, view.root, "copy", event => {
    if self.handle_copy_event(event, view.root) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  // The editor owns its keyboard input (Monaco routes keys through the hidden
  // textarea / edit context into editor commands); the focusable root receives
  // keys once the mousedown handler focuses it.
  add_view_event_listener(view, view.root, "keydown", event => {
    // A root listener also observes bubbling input from caller ViewZones and
    // widgets. Only the root itself is this readonly viewer's input surface;
    // focusable descendants retain their native keyboard semantics.
    guard @base_browser.event_target_is(event, view.root) else { return }
    match event.to_keyboard_event() {
      Some(keyboard) =>
        if self.handle_editor_key_down(
            keyboard.key(),
            alt=keyboard.alt_key(),
            ctrl_cmd=keyboard.ctrl_key() || keyboard.meta_key(),
            shift=keyboard.shift_key(),
          ) {
          event.prevent_default()
          event.stop_propagation()
        }
      None => ()
    }
  })
  add_view_event_listener(view, view.overflow_guard, "wheel", event => {
    match event.to_wheel_event() {
      Some(wheel) =>
        if handler.handle_editor_wheel(event, wheel) {
          event.prevent_default()
          event.stop_propagation()
        }
      None => ()
    }
  })
  handler.hook_scrollable_scrollbar_input(
    view.editor_scrollbar.scrollable(),
    EditorScrollableElement,
  )
  handler.hook_browser_desperate_reveal()
  handler
}

///|
/// Registers one DOM listener in the per-model View lifetime store. The same
/// closure identity is used for removal, and a late registration is disposed
/// immediately by `View::add_disposable`.
fn add_view_event_listener(
  view : @view.View,
  element : @rdom.Element,
  event_name : String,
  listener : (@rdom.Event) -> Unit,
) -> Unit {
  element.add_event_listener(event_name, listener)
  view.add_disposable(
    @base_common.Disposable::from(() => {
      element.remove_event_listener(event_name, listener)
    }),
  )
}

///|
/// The readonly viewer's keyboard entry: the registered commands resolve
/// in registration order (`editor.action.hideHover` on Escape, the focused
/// hover navigation cluster, then the 16 primary cursor navigation bindings).
/// Returns whether the key was handled (and the browser default
/// suppressed). Exact chord matching leaves unregistered Alt/CtrlCmd variants
/// to the browser. A cursor command whose model-bound precondition wins stays
/// handled even when it reaches a document boundary and changes no state.
fn Viewer::handle_editor_key_down(
  self : Viewer,
  key : String,
  alt~ : Bool,
  ctrl_cmd~ : Bool,
  shift? : Bool = false,
) -> Bool {
  editor_registry().dispatch_keybinding(self, key, alt~, ctrl_cmd~, shift~)
}

///|
/// Removes an owned descendant without assuming it is a direct child. This is
/// the source `contains` guard plus `node.remove()`, avoiding `removeChild`
/// exceptions when host DOM was rearranged.
fn remove_element_if_contained(
  container : @rdom.Element,
  child : @rdom.Element,
) -> Unit {
  if @base_browser.element_contains(container, child) {
    @base_browser.remove_element(child)
  }
}

///|
/// Re-derives the active `FontInfo` from the current options: through
/// `FontMeasurements.readFontInfo` when a DOM view exists (Monaco's
/// `_readConfiguration`), the headless estimate otherwise. A changed line
/// height re-flows the layout; the view root is restyled in place.
fn Viewer::refresh_font_info(self : Viewer) -> Unit {
  let bare = self.configuration.snapshot().options.bare_font_info(
    pixel_ratio=@base_browser.device_pixel_ratio(),
  )
  let font_info = match self.get_view() {
    Some(_) => @browser_config.font_measurements().read_font_info(bare)
    None => @config.FontInfo::estimated(bare)
  }
  if !self.configuration.commit_font_info(font_info) {
    return
  }
  match self.get_view_model() {
    Some(view_model) =>
      view_model.view_layout.set_line_height(font_info.line_height) |> ignore
    None => ()
  }
  match self.get_view() {
    Some(view) => self.apply_font_info_to_view(view)
    None => ()
  }
}

///|
/// Monaco `applyFontInfo` on the editor root (`view.ts`). The stylesheets
/// consume the font through the `--editor-*` custom properties
/// (`view_lines.css` / `margin.css` / `theme.css`), so those are refreshed
/// alongside the inline font style.
fn Viewer::apply_font_info_to_view(self : Viewer, view : @view.View) -> Unit {
  let bare = self.configuration.snapshot().font_info.bare()
  @browser_config.apply_font_info(view.root, bare)
  @base_browser.set_style_property(
    view.root,
    "--editor-font-family",
    bare.get_massaged_font_family(),
  )
  @base_browser.set_style_property(
    view.root,
    "--editor-font-size",
    "\{bare.font_size}px",
  )
  @base_browser.set_style_property(
    view.root,
    "--editor-line-height",
    "\{bare.line_height}px",
  )
}

///|
/// Monaco `ElementSizeObserver.measureReferenceDomElement`: read the host's
/// untransformed client box and clamp both axes to the source's 5px minimum.
/// This helper is also used before `Viewer` construction publishes its
/// configuration, so it deliberately has no `Viewer` dependency.
fn read_container_size(container : @rdom.Element) -> (Double, Double) {
  let width = @base_browser.element_client_width(container)
  let height = @base_browser.element_client_height(container)
  (
    if width > 5.0 {
      width
    } else {
      5.0
    },
    if height > 5.0 {
      height
    } else {
      5.0
    },
  )
}

///|
/// Read phase of the render loop: the host client box, the measured font, and
/// the derived gutter width feed the layout model and every later hit
/// test. DOM scroll offsets are treated only as browser reveal deltas;
/// `ViewLayout` owns the editor scroll truth.
fn Viewer::measure(self : Viewer) -> Unit {
  let container = match self.mount {
    Headless => return
    Mounted(mounted) => mounted.container
  }
  let (width, height) = read_container_size(container)
  let previous_configuration = self.configuration.event_snapshot()
  let event_batch = self.begin_view_event_batch()
  self.refresh_font_info()
  self.configuration.commit_measured_container_size(width, height)
  let measured_configuration = self.configuration.snapshot()
  match self.get_view_model() {
    Some(view_model) =>
      view_model.view_layout.set_viewport_size(
        width=measured_configuration.content_width,
        height=measured_configuration.height,
      )
      |> ignore
    None => ()
  }
  if self.configuration.recompute_soft_wrap_column() {
    self.on_configuration_changed()
  } else {
    self.sync_content_width()
  }
  let current_view_line_count = match self.get_view_model() {
    Some(view_model) => view_model.line_count()
    None => 0
  }
  let current_model_line_count = match self.get_model() {
    Some(model) => model.snapshot.line_count()
    None => 0
  }
  self.configuration.set_line_counts(
    current_model_line_count, current_view_line_count,
  )
  match
    previous_configuration.changed_event(self.configuration.event_snapshot()) {
    Some(event) => self.emit_view_event(ViewConfigurationChanged(event))
    None => ()
  }
  end_view_event_batch(event_batch)
}

///|
fn Viewer::sync_content_width(self : Viewer) -> Unit {
  guard self.get_view_model() is Some(view_model) else { return }
  // Rendered ViewLines now owns the measured maximum and feeds it into
  // ViewLayout. The Viewer only supplies the wrapping policy; logical UTF-16
  // length must never stand in for browser geometry.
  view_model.view_layout.set_is_viewport_wrapping(
    self.configuration.snapshot().word_wrap(),
  )
  |> ignore
}
