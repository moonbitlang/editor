///|
extern "js" fn install_view_zones_dirty_state_diagnostic() -> Unit =
  #| () => {
  #|   globalThis.__readonlyEditorViewZonesDiagnostic = undefined;
  #|   globalThis.__acceptReadonlyEditorViewZonesDiagnostic = diagnostic => {
  #|     globalThis.__readonlyEditorViewZonesDiagnostic = diagnostic;
  #|   };
  #| }

///|
extern "js" fn clear_view_zones_dirty_state_diagnostic() -> Unit =
  #| () => {
  #|   delete globalThis.__acceptReadonlyEditorViewZonesDiagnostic;
  #|   delete globalThis.__readonlyEditorViewZonesDiagnostic;
  #| }

///|
extern "js" fn view_zones_diagnostic_did_render() -> Unit =
  #| () => globalThis.__readonlyEditorViewZonesDiagnostic.didRender()

///|
extern "js" fn view_zones_diagnostic_should_render() -> Bool =
  #| () => globalThis.__readonlyEditorViewZonesDiagnostic.shouldRender()

///|
test "hidden areas collect recovery scroll before mapping delivery" {
  install_view_zones_dirty_state_diagnostic()
  defer clear_view_zones_dirty_state_diagnostic()
  let source =
    #|one
    #|two
    #|three
    #|four
    #|five
    #|six
    #|seven
    #|eight
  with_mounted_test_viewer(source, viewer => {
    guard viewer.model_slot.current is Some(model_data) else {
      fail("mounted model data missing")
    }
    let layout = model_data.view_model.view_layout
    layout.set_viewport_size(width=400.0, height=18.0) |> ignore
    let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
    layout.scroll_to(scroll_top=old_top) |> ignore
    view_zones_diagnostic_did_render()

    // The Viewer scroll listener was registered during model construction.
    // This later observer therefore sees whether that listener delivered the
    // recovery Scroll event immediately or merely appended it to the outer
    // hidden-area collector. Every observation must remain clean until the
    // projected-line mutation and its Mapping events have completed. The
    // package-private browser bridge preserves that exact evidence without
    // exposing ViewZones state through MoonBit's public interface.
    let dirty_during_recovery : Array[Bool] = []
    let observer = layout.on_did_scroll(_change => {
      dirty_during_recovery.push(view_zones_diagnostic_should_render())
    })
    defer observer.dispose()

    viewer.set_hidden_areas([Range(2, 1, 3, 1)])
    assert_true(dirty_during_recovery.length() > 0)
    for dirty in dirty_during_recovery {
      assert_false(dirty)
    }
    assert_true(view_zones_diagnostic_should_render())
  })
}
