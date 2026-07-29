///|
/// Whether the installed model currently exposes the code-editor behavior
/// family. Presentation selection is retained for headless models as well as
/// mounted ones, so callers do not infer Code merely from a missing DOM root.
fn ModelData::is_code_presentation(self : ModelData) -> Bool {
  match self.presentation_kind {
    CodeDocument => true
    MarkdownDocument(_) => false
  }
}

///|
/// Root gate for cursor state, code contributions, and source-editor events.
fn Viewer::is_code_presentation(self : Viewer) -> Bool {
  match self.model_slot.current {
    Some(model_data) => model_data.is_code_presentation()
    None => false
  }
}

///|
/// Scroll truth for the active presentation. Mounted Markdown reads its native
/// viewport, Code reads `ViewLayout`, and headless Markdown has no scroll
/// surface.
fn Viewer::active_scroll_position(
  self : Viewer,
) -> @view_layout.ScrollPosition? {
  guard self.model_slot.current is Some(model_data) else { return None }
  match model_data.browser {
    Some(Markdown(markdown)) =>
      Some({
        scroll_top: markdown.view.scroll_top(),
        scroll_left: markdown.view.scroll_left(),
      })
    Some(Code(_)) | None =>
      if model_data.is_code_presentation() {
        Some(model_data.view_model.view_layout.position())
      } else {
        None
      }
  }
}

///|
fn Viewer::active_content_width(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  match model_data.browser {
    Some(Markdown(markdown)) => Some(markdown.view.content_width())
    Some(Code(_)) | None =>
      if model_data.is_code_presentation() {
        Some(model_data.view_model.view_layout.get_content_width())
      } else {
        None
      }
  }
}

///|
fn Viewer::active_scroll_width(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  match model_data.browser {
    Some(Markdown(markdown)) => Some(markdown.view.scroll_width())
    Some(Code(_)) | None =>
      if model_data.is_code_presentation() {
        Some(model_data.view_model.view_layout.get_scroll_width())
      } else {
        None
      }
  }
}

///|
fn Viewer::active_content_height(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  match model_data.browser {
    Some(Markdown(markdown)) => Some(markdown.view.content_height())
    Some(Code(_)) | None =>
      if model_data.is_code_presentation() {
        Some(model_data.view_model.view_layout.get_content_height())
      } else {
        None
      }
  }
}

///|
fn Viewer::active_scroll_height(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  match model_data.browser {
    Some(Markdown(markdown)) => Some(markdown.view.scroll_height())
    Some(Code(_)) | None =>
      if model_data.is_code_presentation() {
        Some(model_data.view_model.view_layout.get_scroll_height())
      } else {
        None
      }
  }
}

///|
fn Viewer::set_active_scroll_position(
  self : Viewer,
  scroll_top? : Double,
  scroll_left? : Double,
) -> Unit {
  guard self.model_slot.current is Some(model_data) else { return }
  match model_data.browser {
    Some(Markdown(markdown)) => {
      markdown.view.set_scroll_position(scroll_top?, scroll_left?)
      self.on_markdown_document_scroll()
    }
    Some(Code(_)) | None => {
      guard model_data.is_code_presentation() else { return }
      let layout = model_data.view_model.view_layout
      let position = layout.position()
      layout.scroll_to(
        scroll_top=scroll_top.unwrap_or(position.scroll_top),
        scroll_left=scroll_left.unwrap_or(position.scroll_left),
      )
      |> ignore
    }
  }
}

///|
fn Viewer::stabilize_active_scroll(self : Viewer) -> Unit {
  guard self.model_slot.current is Some(model_data) else { return }
  match model_data.browser {
    Some(Markdown(_)) => ()
    Some(Code(_)) | None =>
      if model_data.is_code_presentation() {
        model_data.view_model.visible_lines_stabilized()
      }
  }
}

///|
/// Layout publication after the host box has been measured. Code layout is
/// already committed through `ViewLayout`; this explicit dispatch is the seam
/// for independent presentation roots.
fn Viewer::layout_active_presentation(
  self : Viewer,
  _width : Double,
  _height : Double,
) -> Unit {
  match self.current_browser_presentation() {
    Some(Markdown(markdown)) => markdown.layout(_width, _height)
    Some(Code(_)) | None => ()
  }
}
