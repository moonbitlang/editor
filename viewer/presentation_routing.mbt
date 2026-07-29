///|
/// Whether the installed model currently exposes the code-editor behavior
/// family. A headless model is Code in this first seam milestone; later
/// presentation selection refines that branch without constructing DOM.
fn ModelData::is_code_presentation(self : ModelData) -> Bool {
  match self.browser {
    Some(presentation) => presentation.code() is Some(_)
    None => true
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
/// Scroll truth for the active presentation. Code and the private headless
/// harness continue to use `ViewLayout`; later browser presentations join this
/// exhaustive routing point.
fn Viewer::active_scroll_position(
  self : Viewer,
) -> @view_layout.ScrollPosition? {
  guard self.model_slot.current is Some(model_data) else { return None }
  if model_data.is_code_presentation() {
    Some(model_data.view_model.view_layout.position())
  } else {
    None
  }
}

///|
fn Viewer::active_content_width(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  if model_data.is_code_presentation() {
    Some(model_data.view_model.view_layout.get_content_width())
  } else {
    None
  }
}

///|
fn Viewer::active_scroll_width(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  if model_data.is_code_presentation() {
    Some(model_data.view_model.view_layout.get_scroll_width())
  } else {
    None
  }
}

///|
fn Viewer::active_content_height(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  if model_data.is_code_presentation() {
    Some(model_data.view_model.view_layout.get_content_height())
  } else {
    None
  }
}

///|
fn Viewer::active_scroll_height(self : Viewer) -> Double? {
  guard self.model_slot.current is Some(model_data) else { return None }
  if model_data.is_code_presentation() {
    Some(model_data.view_model.view_layout.get_scroll_height())
  } else {
    None
  }
}

///|
fn Viewer::set_active_scroll_position(
  self : Viewer,
  scroll_top? : Double,
  scroll_left? : Double,
) -> Unit {
  guard self.model_slot.current is Some(model_data) else { return }
  guard model_data.is_code_presentation() else { return }
  let layout = model_data.view_model.view_layout
  let position = layout.position()
  layout.scroll_to(
    scroll_top=scroll_top.unwrap_or(position.scroll_top),
    scroll_left=scroll_left.unwrap_or(position.scroll_left),
  )
  |> ignore
}

///|
fn Viewer::stabilize_active_scroll(self : Viewer) -> Unit {
  guard self.model_slot.current is Some(model_data) else { return }
  if model_data.is_code_presentation() {
    model_data.view_model.visible_lines_stabilized()
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
    Some(Code(_)) | None => ()
  }
}
