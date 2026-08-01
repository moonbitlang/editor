// Ported from `vscode/src/vs/base/browser/fastDomNode.ts` at
// checked-in source. This is the scrolling geometry
// cluster only: the cached width/height/top/left/line-height, layer-hint and
// contain writes used by editor view layers.

///|
/// A CSS length accepted by Monaco's `numberAsPixels`: numeric values gain a
/// `px` suffix while already-formed CSS strings pass through unchanged.
pub(all) enum CssLength {
  Pixels(Double)
  Raw(String)
} derive(Eq, Debug)

///|
/// `numberAsPixels` (`fastDomNode.ts:314-316`).
pub fn number_as_pixels(value : CssLength) -> String {
  match value {
    Pixels(value) => value.to_string() + "px"
    Raw(value) => value
  }
}

///|
/// The narrow `FastDomNode` cache used by scrolling. Each setter compares the
/// exact CSS value before touching `element.style`, preserving Monaco's hot-
/// path no-op behavior for retained rows.
pub struct CachedDomNode {
  priv dom_node : @rdom.Element
  priv mut width : String
  priv mut height : String
  priv mut top : String
  priv mut left : String
  priv mut line_height : String
  priv mut position : String
  priv mut layer_hint : Bool
  priv mut contain : String
}

///|
/// `FastDomNode` constructor (`fastDomNode.ts:38-40`).
#alias(new)
pub fn CachedDomNode::CachedDomNode(dom_node : @rdom.Element) -> CachedDomNode {
  {
    dom_node,
    width: "",
    height: "",
    top: "",
    left: "",
    line_height: "",
    position: "",
    layer_hint: false,
    contain: "none",
  }
}

///|
pub fn CachedDomNode::element(self : CachedDomNode) -> @rdom.Element {
  self.dom_node
}

///|
/// `FastDomNode.setWidth` (`fastDomNode.ts:55-62`).
pub fn CachedDomNode::set_width(
  self : CachedDomNode,
  value : CssLength,
) -> Unit {
  let value = number_as_pixels(value)
  if self.width == value {
    return
  }
  self.width = value
  set_cached_style_property(self.dom_node, "width", value)
}

///|
/// `FastDomNode.setHeight` (`fastDomNode.ts:64-71`).
pub fn CachedDomNode::set_height(
  self : CachedDomNode,
  value : CssLength,
) -> Unit {
  let value = number_as_pixels(value)
  if self.height == value {
    return
  }
  self.height = value
  set_cached_style_property(self.dom_node, "height", value)
}

///|
/// `FastDomNode.setTop` (`fastDomNode.ts:73-80`).
pub fn CachedDomNode::set_top(self : CachedDomNode, value : CssLength) -> Unit {
  let value = number_as_pixels(value)
  if self.top == value {
    return
  }
  self.top = value
  set_cached_style_property(self.dom_node, "top", value)
}

///|
/// `FastDomNode.setLeft` (`fastDomNode.ts:82-89`).
pub fn CachedDomNode::set_left(self : CachedDomNode, value : CssLength) -> Unit {
  let value = number_as_pixels(value)
  if self.left == value {
    return
  }
  self.left = value
  set_cached_style_property(self.dom_node, "left", value)
}

///|
/// `FastDomNode.setLineHeight` (`fastDomNode.ts:202-209`).
pub fn CachedDomNode::set_line_height(
  self : CachedDomNode,
  value : CssLength,
) -> Unit {
  let value = number_as_pixels(value)
  if self.line_height == value {
    return
  }
  self.line_height = value
  set_cached_style_property(self.dom_node, "line-height", value)
}

///|
/// `FastDomNode.setPosition` (`fastDomNode.ts:241-247`), used by the shared
/// lines-content rail during `View` construction.
pub fn CachedDomNode::set_position(
  self : CachedDomNode,
  position : String,
) -> Unit {
  if self.position == position {
    return
  }
  self.position = position
  set_cached_style_property(self.dom_node, "position", position)
}

///|
/// `FastDomNode.setLayerHinting` (`fastDomNode.ts:273-279`).
pub fn CachedDomNode::set_layer_hinting(
  self : CachedDomNode,
  layer_hint : Bool,
) -> Unit {
  if self.layer_hint == layer_hint {
    return
  }
  self.layer_hint = layer_hint
  set_cached_style_property(
    self.dom_node,
    "transform",
    if layer_hint {
      "translate3d(0px, 0px, 0px)"
    } else {
      ""
    },
  )
}

///|
/// `FastDomNode.setContain` (`fastDomNode.ts:289-295`).
pub fn CachedDomNode::set_contain(
  self : CachedDomNode,
  contain : String,
) -> Unit {
  if self.contain == contain {
    return
  }
  self.contain = contain
  set_cached_style_property(self.dom_node, "contain", contain)
}

///|
/// Per-property style write plus the scrollbar harness's unique metrics seam.
fn set_cached_style_property(
  element : @rdom.Element,
  name : String,
  value : String,
) -> Unit {
  @base_browser.set_style_property(element, name, value)
  record_cached_style_write(element, name)
}

///|
/// When the browser conformance harness enables
/// `__moonbitViewerScrollMetrics`, records the exact hot-path write without
/// changing production behavior.
extern "js" fn record_cached_style_write(
  element : @rdom.Element,
  name : String,
) -> Unit =
  #| (element, name) => {
  #|   const metrics = globalThis.__moonbitViewerScrollMetrics;
  #|   if (!metrics) return;
  #|   metrics.styleWrites = (metrics.styleWrites || 0) + 1;
  #|   const part = element.getAttribute('data-view-part') || element.className || element.tagName;
  #|   const key = `${part}:${name}`;
  #|   metrics.styleWritesByKey ||= {};
  #|   metrics.styleWritesByKey[key] = (metrics.styleWritesByKey[key] || 0) + 1;
  #| }
