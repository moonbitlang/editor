///|
test "hidden areas publish recovery scroll before the public change event" {
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

    // Observe the supported ordering contract directly: recovery scrolling is
    // delivered before the public hidden-area notification.
    let order : Array[String] = []
    let observer = layout.on_did_scroll(_change => order.push("scroll"))
    defer observer.dispose()
    viewer.on_did_change_hidden_areas(() => order.push("hidden")) |> ignore

    viewer.set_hidden_areas([Range(2, 1, 3, 1)])
    assert_true(order.length() > 1)
    assert_eq(order[order.length() - 1], "hidden")
    for index = 0; index < order.length() - 1; index = index + 1 {
      assert_eq(order[index], "scroll")
    }
  })
}
