// Ported from `vscode/src/vs/editor/browser/view/viewOverlays.ts`
// (`MarginViewOverlays`) and `viewParts/margin/margin.ts`, vscode submodule
// checked-in source.

///|
/// `MarginViewOverlays` (`viewOverlays.ts:236`): the margin-side rows
/// container, hosting the current-line-margin, lines-decorations, and
/// line-number overlays in Monaco's margin registration order
/// (`view.ts:225-231`; the glyph-margin overlay between them is unported).
/// The viewer keeps Monaco's separate `Margin` part (`margin.ts` — the
/// `.margin` background/clip container) merged onto this struct: the
/// readonly margin has no glyph lane to justify the split.
priv struct MarginViewOverlays {
  dom_node : @rdom.Element
  overlays : ViewOverlays
  current_line_margin : CurrentLineMarginHighlightOverlay
  mut should_render : Bool
  // `MarginViewOverlays._contentLeft` (`viewOverlays.ts:238,244-248,265`).
  mut content_left : Double
  mut read_content_left : () -> Double
}

///|
fn MarginViewOverlays::MarginViewOverlays(
  document : @rdom.Document,
) -> MarginViewOverlays {
  let dom_node = document.create_element("div")
  dom_node.set_attribute("class", "margin")
  dom_node.set_attribute("data-view-part", "margin")
  dom_node.set_attribute("aria-hidden", "true")
  let overlays = ViewOverlays::ViewOverlays(document, "margin-view-overlays")
  let current_line_margin = CurrentLineMarginHighlightOverlay::CurrentLineMarginHighlightOverlay()
  let lines_decorations = LinesDecorationsOverlay::LinesDecorationsOverlay()
  let line_numbers = LineNumbersOverlay::LineNumbersOverlay()
  overlays.add_dynamic_overlay(CurrentLineMargin(current_line_margin))
  overlays.add_dynamic_overlay(LinesDecorations(lines_decorations))
  overlays.add_dynamic_overlay(LineNumbers(line_numbers))
  dom_node.append_child(overlays.dom_node.element().as_node())
  {
    dom_node,
    overlays,
    current_line_margin,
    should_render: true,
    content_left: 0.0,
    read_content_left: () => 0.0,
  }
}

///|
/// Attaches ViewZones' margin container before every margin overlay child.
/// The merged local `MarginViewOverlays` remains the sole `.margin` ViewPart;
/// re-appending its retained overlay node performs the DOM move without
/// recreating or mutating that node.
fn MarginViewOverlays::attach_view_zones_margin(
  self : MarginViewOverlays,
  margin_view_zones : @rdom.Element,
) -> Unit {
  self.dom_node.append_child(margin_view_zones.as_node())
  self.dom_node.append_child(self.overlays.dom_node.element().as_node())
}

///|
/// Installs the local `ViewContext.configuration.options.layoutInfo` seam and
/// performs the constructor-time `_contentLeft` read.
fn MarginViewOverlays::install_content_left_reader(
  self : MarginViewOverlays,
  read_content_left : () -> Double,
) -> Unit {
  self.read_content_left = read_content_left
  self.on_configuration_changed()
}

///|
/// `MarginViewOverlays.onConfigurationChanged`'s retained layout read.
fn MarginViewOverlays::on_configuration_changed(
  self : MarginViewOverlays,
) -> Unit {
  self.content_left = (self.read_content_left)()
}

///|
/// Applies the base `ViewOverlays.render` focus-class write to the margin
/// overlay container from its retained focus cache.
fn MarginViewOverlays::render_focused(self : MarginViewOverlays) -> Unit {
  self.overlays.render_focused_class("margin-view-overlays")
}

///|
fn MarginViewOverlays::get_dom_node(self : MarginViewOverlays) -> @rdom.Element {
  self.dom_node
}
