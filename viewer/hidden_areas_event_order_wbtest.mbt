///|
test "hidden areas collect recovery scroll before mapping delivery" {
  let source = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"
  with_mounted_test_viewer(source, viewer => {
    guard viewer.model_slot.current is Some(model_data) else {
      fail("mounted model data missing")
    }
    guard model_data.browser is Some(browser) else {
      fail("mounted model data missing browser bundle")
    }
    let view = browser.view
    let layout = model_data.view_model.view_layout
    layout.set_viewport_size(width=400.0, height=18.0) |> ignore
    let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
    layout.scroll_to(scroll_top=old_top) |> ignore
    view.view_zones.did_render()

    // The Viewer scroll listener was registered during model construction.
    // This later observer therefore sees whether that listener delivered the
    // recovery Scroll event immediately or merely appended it to the outer
    // hidden-area collector. Every observation must remain clean until the
    // projected-line mutation and its Mapping events have completed.
    let dirty_during_recovery : Array[Bool] = []
    let observer = layout.on_did_scroll(_change => {
      dirty_during_recovery.push(view.view_zones.should_render())
    })
    defer observer.dispose()

    viewer.set_hidden_areas([Range(2, 1, 3, 1)])
    assert_true(dirty_during_recovery.length() > 0)
    for dirty in dirty_during_recovery {
      assert_false(dirty)
    }
    assert_true(view.view_zones.should_render())
  })
}
