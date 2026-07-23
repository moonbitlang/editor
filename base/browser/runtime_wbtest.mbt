///|
test "browser runtime clocks and pixel ratio expose valid values" {
  assert_true(monotonic_now_ms() >= 0.0)
  assert_true(wall_clock_now_ms() > 0.0)
  assert_true(device_pixel_ratio() > 0.0)
}

///|
test "scheduled timeout cancellation is idempotent" {
  let delivered = Ref(false)
  let timeout = schedule_timeout(() => delivered.val = true, 60000)
  timeout.dispose()
  timeout.dispose()
  assert_false(delivered.val)
}
