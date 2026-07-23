// The Viewer-owned public/ordering seam for the per-model browser ViewZones
// part. Registration, DOM, and whitespace mutation live on `View.view_zones`;
// this root method owns the CodeEditorWidget guard, internal-before-outgoing
// delivery, and unconditional render schedule.

///|
/// Constructs the complete mutable ViewZone delegate through the public root
/// package. Browser scenarios therefore need only `@viewer.view_zone(...)`;
/// the internal browser ViewPart package stays an implementation detail.
pub fn view_zone(
  after_line_number : Int,
  dom_node : @rdom.Element,
  after_column? : Int,
  after_column_affinity? : @model.PositionAffinity,
  show_in_hidden_areas? : Bool,
  ignore_hidden_area_source? : String,
  ordinal? : Int,
  suppress_mouse_down? : Bool,
  height_in_lines? : Double,
  height_in_px? : Double,
  min_width_in_px? : Double,
  margin_dom_node? : @rdom.Element,
  on_dom_node_top? : (Double) -> Unit raise,
  on_computed_height? : (Double) -> Unit raise,
) -> @editor_browser.ViewZone {
  ViewZone(
    after_line_number,
    dom_node,
    after_column?,
    after_column_affinity?,
    show_in_hidden_areas?,
    ignore_hidden_area_source?,
    ordinal?,
    suppress_mouse_down?,
    height_in_lines?,
    height_in_px?,
    min_width_in_px?,
    margin_dom_node?,
    on_dom_node_top?,
    on_computed_height?,
  )
}

///|
/// Applies one source-shaped ViewZones transaction. With no model or no real
/// browser View the callback is not invoked. A live callback is safely
/// contained by the ViewZones part; afterward this method always schedules one
/// render, while actual whitespace changes first finish the internal ViewEvent
/// and then enter the ViewModel outgoing queue/public event.
pub fn Viewer::change_view_zones(
  self : Viewer,
  update : (@editor_browser.ViewZoneChangeAccessor) -> Unit raise,
) -> Unit {
  if self.disposed {
    return
  }
  guard self.current_browser_data() is Some(browser) else { return }
  browser.view.change_view_zones(update)
  self.schedule_render()
}
