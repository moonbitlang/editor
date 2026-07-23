// Applies the runtime squiggle theming pipeline (Monaco's
// `registerThemingParticipant`, ported as `@markers.squiggly_theme_css`) to
// this `View`'s DOM: reads the currently resolved theme foreground colors off
// the view root and (re)writes a dedicated `<style>` element with the
// generated background-image rules. Colors are read via `getComputedStyle`
// rather than duplicated into MoonBit, matching this viewer's design that
// theme colors cascade from the host's CSS custom properties (`theme.css`),
// not from a MoonBit-side theme registry.

///|
/// FFI gap-fill (no `getComputedStyle` binding exists in the vendored
/// `@rdom` package — only `CSSStyleDeclaration::get_property_value`).
extern "js" fn computed_style_property(
  el : @rdom.Element,
  property : String,
) -> String =
  #| (el, property) => getComputedStyle(el).getPropertyValue(property).trim()

///|
/// Mirrors `theme.getColor(...)` returning `undefined` for an unset token.
fn optional_color(value : String) -> String? {
  if value == "" {
    None
  } else {
    Some(value)
  }
}

///|
fn read_squiggly_theme_colors(
  root : @rdom.Element,
) -> @markers.SquigglyThemeColors {
  {
    error: optional_color(
      computed_style_property(root, "--vscode-editorError-foreground"),
    ),
    warning: optional_color(
      computed_style_property(root, "--vscode-editorWarning-foreground"),
    ),
    info: optional_color(
      computed_style_property(root, "--vscode-editorInfo-foreground"),
    ),
    hint: optional_color(
      computed_style_property(root, "--vscode-editorHint-foreground"),
    ),
  }
}

///|
/// Re-reads the live theme colors and rewrites the squiggle stylesheet. Call
/// after the view is attached to the document (`getComputedStyle` needs a
/// live element to resolve cascaded custom properties) and again whenever the
/// host pushes a new theme.
///
/// The read is deferred one macrotask, not run inline: the host
/// that owns the ancestor element carrying the theme's CSS custom properties
/// (e.g. this project's `.editor-shell`) may update its own `data-theme`
/// attribute through its own async render cycle (this project's `rabbita`
/// TEA runtime patches the DOM on the next `requestAnimationFrame`, strictly
/// after the command that calls `Viewer::set_theme` returns) — reading
/// `getComputedStyle` inline here would race that patch and see the old
/// theme's colors. `setTimeout(fn, 0)` reliably runs after any
/// already-pending `requestAnimationFrame` callback (deviation: Monaco's
/// `registerThemingParticipant` has no such race, since VS Code's own theme
/// service updates colors and the CSS variables it drives synchronously).
pub fn View::apply_squiggly_theme(self : View) -> Unit {
  @base_browser.schedule_timeout(
    () => {
      let colors = read_squiggly_theme_colors(self.root)
      self.squiggly_style.set_inner_html(@markers.squiggly_theme_css(colors))
    },
    0,
  )
  |> ignore
}
