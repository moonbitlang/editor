///|
/// Small non-destructive status surface for definition actions. The root
/// Viewer chooses whether to mount it as an overlay widget or in another
/// editor-owned container.
pub struct DefinitionMessageWidget {
  priv root : @rdom.Element
  priv mut disposed : Bool
}

///|
/// Constructs a detached, hidden status node.
#alias(new, deprecated)
pub fn DefinitionMessageWidget::DefinitionMessageWidget() -> DefinitionMessageWidget {
  let root = @rdom.document().create_element("div")
  root.set_attribute("class", "moonbit-viewer-definition-message")
  root.set_attribute("role", "status")
  root.set_attribute("aria-live", "polite")
  root.set_attribute("aria-atomic", "true")
  root.set_attribute("hidden", "")
  root.set_attribute("aria-hidden", "true")
  { root, disposed: false }
}

///|
/// Detached root node mounted by the root Viewer.
pub fn DefinitionMessageWidget::get_dom_node(
  self : DefinitionMessageWidget,
) -> @rdom.Element {
  self.root
}

///|
/// Replaces the message text without changing visibility.
pub fn DefinitionMessageWidget::set_message(
  self : DefinitionMessageWidget,
  message : String,
) -> Unit {
  if self.disposed {
    return
  }
  self.root.set_inner_html("")
  self.root.append_child(@rdom.document().create_text_node(message).as_node())
}

///|
/// Shows the current message. Empty text remains a valid status update; the
/// root contribution decides which user-facing strings to publish.
pub fn DefinitionMessageWidget::show(self : DefinitionMessageWidget) -> Unit {
  if self.disposed {
    return
  }
  self.root.remove_attribute("hidden")
  self.root.set_attribute("aria-hidden", "false")
}

///|
/// Hides the status without discarding its text.
pub fn DefinitionMessageWidget::hide(self : DefinitionMessageWidget) -> Unit {
  if self.disposed {
    return
  }
  self.root.set_attribute("hidden", "")
  self.root.set_attribute("aria-hidden", "true")
}

///|
/// Hides and clears the detached status node exactly once.
pub fn DefinitionMessageWidget::dispose(self : DefinitionMessageWidget) -> Unit {
  if self.disposed {
    return
  }
  self.root.set_attribute("hidden", "")
  self.root.set_attribute("aria-hidden", "true")
  self.root.set_inner_html("")
  self.disposed = true
}
