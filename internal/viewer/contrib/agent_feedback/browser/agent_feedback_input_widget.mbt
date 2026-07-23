// The inline "Add Feedback" input, porting `AgentFeedbackInputWidget`
// (`vscode/src/vs/sessions/contrib/agentFeedback/browser/
// agentFeedbackEditorInputContribution.ts:44-242`): a floating overlay node
// with an auto-growing textarea, a hidden measure span for width sizing, and
// one icon action that swaps Add ↔ Add-and-Submit while Alt is held
// (upstream's `ModifierKeyEmitter` swap, driven here from the textarea's own
// keydown/keyup since the widget owns the focus while typing). The widget is
// a null-position overlay widget: the glue positions it by writing
// `top`/`left` (`setPosition` → `layoutOverlayWidget` upstream). Keyboard is
// handled on the textarea directly (Enter adds, Alt+Enter adds and submits,
// Escape cancels) — the editor-keydown steal/`Ctrl+I` focus routing of the
// upstream contribution goes through the viewer's keybinding registry
// instead. Dropped: the ActionBar/keybinding-label chrome (a plain button)
// and the readonly-editor typing capture.

///|
/// `_MIN_WIDTH` / `_MAX_WIDTH` / `_MAX_WIDTH_EDITOR_FRACTION`.
let input_min_width_px : Double = 150.0

///|
let input_max_width_px : Double = 400.0

///|
pub let input_max_width_editor_fraction : Double = 0.9

///|
/// The textarea line height the widget sizes against (`_lineHeight = 22`).
let input_line_height_px : Double = 22.0

///|
/// The glue-facing seam: submit/cancel routing plus the geometry reads the
/// widget needs while sizing (the upstream widget reached back into
/// `ICodeEditor.getLayoutInfo` for these).
pub(all) struct AgentFeedbackInputWidgetHost {
  /// Enter — `onDidTriggerAdd`.
  on_add : () -> Unit
  /// Alt+Enter — `onDidTriggerAddAndSubmit`.
  on_add_and_submit : () -> Unit
  /// Escape inside the textarea — the contribution hides and refocuses.
  on_cancel : () -> Unit
  /// The textarea grew/shrank; the glue repositions the widget
  /// (`this._updatePosition()` on `input`).
  on_layout : () -> Unit
  /// Focus left the textarea with no draft text; the glue auto-hides.
  on_blur_empty : () -> Unit
  /// `_computeMaxWidth`'s editor content width (layout width − content left).
  content_width : () -> Double
}

///|
pub struct AgentFeedbackInputWidget {
  host : AgentFeedbackInputWidgetHost
  root : @rdom.Element
  textarea : @rdom.Element
  measure : @rdom.Element
  action : @rdom.Element
  mut showing_alt : Bool
}

///|
#alias(new, deprecated)
pub fn AgentFeedbackInputWidget::AgentFeedbackInputWidget(
  host : AgentFeedbackInputWidgetHost,
) -> AgentFeedbackInputWidget {
  let document = @rdom.document()
  let root = document.create_element("div")
  root.set_attribute("class", "agent-feedback-input-widget")
  root.set_attribute("style", "display:none")
  let textarea = document.create_element("textarea")
  textarea.set_attribute("rows", "1")
  textarea.set_attribute("placeholder", "Add Feedback")
  textarea.set_attribute("data-agent-feedback-input", "true")
  root.append_child(textarea.as_node())
  let measure = document.create_element("span")
  measure.set_attribute("class", "agent-feedback-input-measure")
  root.append_child(measure.as_node())
  let actions = document.create_element("div")
  actions.set_attribute("class", "agent-feedback-input-actions")
  let action = document.create_element("button")
  action.set_attribute("type", "button")
  action.set_attribute("data-agent-feedback-action", "add")
  actions.append_child(action.as_node())
  root.append_child(actions.as_node())
  let widget : AgentFeedbackInputWidget = {
    host,
    root,
    textarea,
    measure,
    action,
    showing_alt: false,
  }
  widget.render_action()
  widget.hook_events()
  widget
}

///|
pub fn AgentFeedbackInputWidget::get_dom_node(
  self : AgentFeedbackInputWidget,
) -> @rdom.Element {
  self.root
}

///|
/// `_updateActionForAlt`: one button whose icon/title swap between Add
/// (plus) and Add-and-Submit (send) with the Alt key.
fn AgentFeedbackInputWidget::render_action(
  self : AgentFeedbackInputWidget,
) -> Unit {
  if self.showing_alt {
    self.action.set_attribute(
      "class", "agent-feedback-input-action agent-feedback-input-action-send",
    )
    self.action.set_attribute("title", "Add Feedback and Submit (Alt+Enter)")
  } else {
    self.action.set_attribute(
      "class", "agent-feedback-input-action agent-feedback-input-action-add",
    )
    self.action.set_attribute("title", "Add Feedback (Enter)")
  }
  self.update_action_enabled()
}

///|
fn AgentFeedbackInputWidget::hook_events(
  self : AgentFeedbackInputWidget,
) -> Unit {
  // Containment (the comment widget precedent): interactions must not reach
  // the editor's root refocus / key handling.
  self.root.add_event_listener("mouseup", event => event.stop_propagation())
  self.root.add_event_listener("click", event => event.stop_propagation())
  self.root.add_event_listener("contextmenu", event => event.stop_propagation())
  // Mousedown anywhere on the widget that isn't the textarea itself focuses
  // the textarea (upstream's padding-click handler).
  self.root.add_event_listener("mousedown", event => {
    event.stop_propagation()
    if !input_event_targets(event, self.textarea) &&
      !input_event_targets(event, self.action) {
      event.prevent_default()
      @base_browser.focus_prevent_scroll(self.textarea)
    }
  })
  self.action.add_event_listener("click", event => {
    event.prevent_default()
    event.stop_propagation()
    if self.has_text() {
      if self.showing_alt {
        (self.host.on_add_and_submit)()
      } else {
        (self.host.on_add)()
      }
    }
  })
  self.textarea.add_event_listener("keydown", event => {
    match event.to_keyboard_event() {
      Some(keyboard) => self.handle_keydown(event, keyboard)
      None => ()
    }
    event.stop_propagation()
  })
  self.textarea.add_event_listener("keyup", event => {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        if self.showing_alt && !keyboard.alt_key() {
          self.showing_alt = false
          self.render_action()
        }
      None => ()
    }
    event.stop_propagation()
  })
  self.textarea.add_event_listener("input", _ => {
    self.auto_size()
    self.update_action_enabled()
    (self.host.on_layout)()
  })
  self.textarea.add_event_listener("blur", _ => {
    if !self.has_text() {
      (self.host.on_blur_empty)()
    }
  })
}

///|
fn AgentFeedbackInputWidget::handle_keydown(
  self : AgentFeedbackInputWidget,
  event : @rdom.Event,
  keyboard : @rdom.KeyboardEvent,
) -> Unit {
  if keyboard.alt_key() != self.showing_alt {
    self.showing_alt = keyboard.alt_key()
    self.render_action()
  }
  match keyboard.key() {
    "Escape" => {
      event.prevent_default()
      (self.host.on_cancel)()
    }
    "Enter" => {
      event.prevent_default()
      if !self.has_text() {
        return
      }
      if keyboard.alt_key() {
        (self.host.on_add_and_submit)()
      } else {
        (self.host.on_add)()
      }
    }
    _ => ()
  }
}

// --- glue-facing surface ---------------------------------------------------------

///|
pub fn AgentFeedbackInputWidget::show(self : AgentFeedbackInputWidget) -> Unit {
  @base_browser.set_style_property(self.root, "display", "")
}

///|
pub fn AgentFeedbackInputWidget::hide(self : AgentFeedbackInputWidget) -> Unit {
  @base_browser.set_style_property(self.root, "display", "none")
}

///|
/// Writes the overlay position (`setPosition` → the widget's absolute
/// `top`/`left` inside the `.overlayWidgets` container).
pub fn AgentFeedbackInputWidget::set_position(
  self : AgentFeedbackInputWidget,
  top : Double,
  left : Double,
) -> Unit {
  @base_browser.set_style_property(self.root, "top", top.to_string() + "px")
  @base_browser.set_style_property(self.root, "left", left.to_string() + "px")
}

///|
pub fn AgentFeedbackInputWidget::clear_input(
  self : AgentFeedbackInputWidget,
) -> Unit {
  input_set_textarea_value(self.textarea, "")
  self.update_action_enabled()
  self.auto_size()
}

///|
pub fn AgentFeedbackInputWidget::set_placeholder(
  self : AgentFeedbackInputWidget,
  placeholder : String,
) -> Unit {
  self.textarea.set_attribute("placeholder", placeholder)
  self.auto_size()
}

///|
pub fn AgentFeedbackInputWidget::focus_input(
  self : AgentFeedbackInputWidget,
) -> Unit {
  @base_browser.focus_prevent_scroll(self.textarea)
}

///|
pub fn AgentFeedbackInputWidget::value(
  self : AgentFeedbackInputWidget,
) -> String {
  input_textarea_value(self.textarea)
}

///|
/// Whether the textarea holds non-whitespace draft text — the upstream
/// `_hasInputText` freeze/auto-hide gate.
pub fn AgentFeedbackInputWidget::has_text(
  self : AgentFeedbackInputWidget,
) -> Bool {
  !is_blank(self.value())
}

///|
/// The rendered size, for the glue's flip/clamp positioning (upstream read
/// `offsetHeight`/`offsetWidth` with the same `30`/`150` fallbacks).
pub fn AgentFeedbackInputWidget::measured_height(
  self : AgentFeedbackInputWidget,
) -> Double {
  let height = @base_browser.element_offset_height(self.root)
  if height > 0.0 {
    height
  } else {
    30.0
  }
}

///|
pub fn AgentFeedbackInputWidget::measured_width(
  self : AgentFeedbackInputWidget,
) -> Double {
  let width = @base_browser.element_offset_width(self.root)
  if width > 0.0 {
    width
  } else {
    input_min_width_px
  }
}

///|
fn AgentFeedbackInputWidget::update_action_enabled(
  self : AgentFeedbackInputWidget,
) -> Unit {
  if self.has_text() {
    self.action.remove_attribute("disabled")
  } else {
    self.action.set_attribute("disabled", "true")
  }
}

///|
/// `_autoSize`: width from the measured text (clamped between an effective
/// minimum and a maximum that never exceeds the editor content area), height
/// from the textarea's scroll height.
pub fn AgentFeedbackInputWidget::auto_size(
  self : AgentFeedbackInputWidget,
) -> Unit {
  let value = self.value()
  let text = if value.is_empty() {
    self.textarea.get_attribute("placeholder")
  } else {
    value
  }
  self.measure.set_inner_html(input_escape_html(text))
  let text_width = input_scroll_width(self.measure)
  let max_width_cap = (self.host.content_width)() *
    input_max_width_editor_fraction
  let max_width = if input_max_width_px < max_width_cap {
    input_max_width_px
  } else {
    max_width_cap
  }
  let min_width = if input_min_width_px < max_width {
    input_min_width_px
  } else {
    max_width
  }
  let desired = if text_width + 10.0 > min_width {
    text_width + 10.0
  } else {
    min_width
  }
  let width = if desired < max_width { desired } else { max_width }
  @base_browser.set_style_property(
    self.textarea,
    "min-width",
    min_width.to_string() + "px",
  )
  @base_browser.set_style_property(
    self.textarea,
    "width",
    width.to_string() + "px",
  )
  let height = input_textarea_grown_height(self.textarea)
  let clamped_height = if height > input_line_height_px {
    height
  } else {
    input_line_height_px
  }
  @base_browser.set_style_property(
    self.textarea,
    "height",
    clamped_height.to_string() + "px",
  )
}

// --- helpers / FFI ---------------------------------------------------------------

///|
fn is_blank(text : String) -> Bool {
  for ch in text {
    if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
      return false
    }
  }
  true
}

///|
fn input_escape_html(text : String) -> String {
  let out = StringBuilder::new()
  for ch in text {
    match ch {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

///|
/// FFI gap-fills, following the comment widget's extern pattern.
extern "js" fn input_textarea_value(element : @rdom.Element) -> String = "(el) => el.value ?? ''"

///|
extern "js" fn input_set_textarea_value(
  element : @rdom.Element,
  value : String,
) -> Unit = "(el, v) => { el.value = v }"

///|
extern "js" fn input_scroll_width(element : @rdom.Element) -> Double = "(el) => el.scrollWidth ?? 0"

///|
/// Resets the textarea height to `auto` and reports the content height —
/// upstream's two-step `height = 'auto'; height = scrollHeight`.
extern "js" fn input_textarea_grown_height(element : @rdom.Element) -> Double =
  #| (el) => { el.style.height = 'auto'; return el.scrollHeight ?? 0 }

///|
/// Whether the event's target is (inside) the given element.
extern "js" fn input_event_targets(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool =
  #| (ev, el) => el === ev.target || (el.contains?.(ev.target) ?? false)
