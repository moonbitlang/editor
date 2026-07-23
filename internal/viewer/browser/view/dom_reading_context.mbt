// Ported from
// `vscode/src/vs/editor/browser/viewParts/viewLines/domReadingContext.ts`
// (checked-in vscode submodule): the
// lazy client-rect cache shared by one batch of DOM reads off the view-lines
// node. `end_node` is the source's `_textRangeRestingSpot`, the detached span
// `RangeUtil` parks DOM ranges on between reads.

///|
priv struct DomReadingContext {
  dom_node : @rdom.Element
  end_node : @rdom.Element
  mut did_dom_layout_flag : Bool
  mut client_rect_delta_left_value : Double
  mut client_rect_scale_value : Double
  mut client_rect_read : Bool
}

///|
fn DomReadingContext::DomReadingContext(
  dom_node : @rdom.Element,
  end_node : @rdom.Element,
) -> DomReadingContext {
  {
    dom_node,
    end_node,
    did_dom_layout_flag: false,
    client_rect_delta_left_value: 0.0,
    client_rect_scale_value: 1.0,
    client_rect_read: false,
  }
}

///|
fn DomReadingContext::read_client_rect(self : DomReadingContext) -> Unit {
  if !self.client_rect_read {
    self.client_rect_read = true
    let rect = self.dom_node.get_bounding_client_rect()
    self.mark_did_dom_layout()
    self.client_rect_delta_left_value = rect.get_left()
    let offset_width = @base_browser.element_offset_width(self.dom_node)
    self.client_rect_scale_value = if offset_width > 0.0 {
      rect.get_width() / offset_width
    } else {
      1.0
    }
  }
}

///|
fn DomReadingContext::client_rect_delta_left(
  self : DomReadingContext,
) -> Double {
  if !self.client_rect_read {
    self.read_client_rect()
  }
  self.client_rect_delta_left_value
}

///|
fn DomReadingContext::client_rect_scale(self : DomReadingContext) -> Double {
  if !self.client_rect_read {
    self.read_client_rect()
  }
  self.client_rect_scale_value
}

///|
fn DomReadingContext::did_dom_layout(self : DomReadingContext) -> Bool {
  self.did_dom_layout_flag
}

///|
fn DomReadingContext::mark_did_dom_layout(self : DomReadingContext) -> Unit {
  self.did_dom_layout_flag = true
}
