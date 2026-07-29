///|
fn test_mouse_dispatch_data(
  reveal_type : NavigationCommandRevealType,
) -> MouseDispatchData {
  {
    position: Position(1, 1),
    mouse_column: 1,
    reveal_type,
    started_on_line_numbers: false,
    in_selection_mode: false,
    mouse_down_count: 1,
    alt_key: false,
    ctrl_key: false,
    meta_key: false,
    shift_key: false,
    left_button: true,
    middle_button: false,
    on_injected_text: false,
  }
}

///|
/// `NavigationCommandRevealType` is semantic dispatch data, not a Boolean:
/// direct pointer movement uses Minimal, ordinary programmatic dispatch can
/// use Regular, and edge auto-scroll carries None.
test "mouse dispatch data carries all navigation reveal types" {
  assert_true(test_mouse_dispatch_data(Regular).reveal_type == Regular)
  assert_true(test_mouse_dispatch_data(Minimal).reveal_type == Minimal)
  assert_true(test_mouse_dispatch_data(None).reveal_type == None)
  assert_true(Regular != Minimal)
  assert_true(Minimal != None)
  assert_true(Regular != None)
}

///|
test "pre-selection suppression preserves focus and public mousedown" {
  let events : Array[String] = []
  run_mouse_down_selection_contract(
    true,
    true,
    () => {
      events.push("before-selection")
      true
    },
    () => events.push("focus"),
    () => events.push("dispatch-selection"),
    () => events.push("non-content"),
    () => events.push("emit-mousedown"),
  )
  assert_eq(events.length(), 3)
  assert_eq(events[0], "before-selection")
  assert_eq(events[1], "focus")
  assert_eq(events[2], "emit-mousedown")
}

///|
test "pre-selection fallthrough preserves ordinary selection dispatch" {
  let events : Array[String] = []
  run_mouse_down_selection_contract(
    true,
    true,
    () => {
      events.push("before-selection")
      false
    },
    () => events.push("focus"),
    () => events.push("dispatch-selection"),
    () => events.push("non-content"),
    () => events.push("emit-mousedown"),
  )
  assert_eq(events.length(), 4)
  assert_eq(events[0], "before-selection")
  assert_eq(events[1], "focus")
  assert_eq(events[2], "dispatch-selection")
  assert_eq(events[3], "emit-mousedown")
}
