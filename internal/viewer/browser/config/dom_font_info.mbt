// Ported from `vscode/src/vs/editor/browser/config/domFontInfo.ts`.

///|
/// Monaco `applyFontInfo`: writes a `BareFontInfo`'s font style properties
/// onto an element's inline style.
pub fn apply_font_info(
  node : @rdom.Element,
  font_info : @common_config.BareFontInfo,
) -> Unit {
  @base_browser.set_style_property(
    node,
    "font-family",
    font_info.get_massaged_font_family(),
  )
  @base_browser.set_style_property(node, "font-weight", font_info.font_weight)
  @base_browser.set_style_property(
    node,
    "font-size",
    "\{font_info.font_size}px",
  )
  @base_browser.set_style_property(
    node,
    "font-feature-settings",
    font_info.font_feature_settings,
  )
  @base_browser.set_style_property(
    node,
    "font-variation-settings",
    font_info.font_variation_settings,
  )
  @base_browser.set_style_property(
    node,
    "line-height",
    "\{font_info.line_height}px",
  )
  @base_browser.set_style_property(
    node,
    "letter-spacing",
    "\{font_info.letter_spacing}px",
  )
}
