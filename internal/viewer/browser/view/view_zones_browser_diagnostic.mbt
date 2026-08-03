///|
/// Offers the package-private ViewZones dirty-state controls only to an
/// explicitly installed JavaScript test receiver. Normal hosts perform one
/// receiver check when a View is created and allocate no diagnostic closures.
fn offer_view_zones_browser_diagnostic(view_zones : ViewZones) -> Unit {
  if has_view_zones_browser_diagnostic_receiver() {
    accept_view_zones_browser_diagnostic(() => view_zones.should_render(), () => {
      view_zones.did_render()
    })
  }
}

///|
extern "js" fn has_view_zones_browser_diagnostic_receiver() -> Bool =
  #| () => typeof globalThis.__acceptReadonlyEditorViewZonesDiagnostic === "function"

///|
extern "js" fn accept_view_zones_browser_diagnostic(
  should_render : () -> Bool,
  did_render : () -> Unit,
) -> Unit =
  #| (shouldRender, didRender) => {
  #|   globalThis.__acceptReadonlyEditorViewZonesDiagnostic?.({
  #|     shouldRender,
  #|     didRender,
  #|   });
  #| }
