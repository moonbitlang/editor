// Source-derived white-box platform matrix for
// `vscode/src/vs/editor/common/config/fontInfo.ts` at checked-in vscode submodule.

///|
test "EDITOR_FONT_DEFAULTS platform matrix" {
  let mac = editor_font_defaults_for_platform(MacOS)
  assert_eq(mac.font_family, default_mac_font_family)
  assert_eq(mac.font_weight, "normal")
  assert_eq(mac.font_size, 12.0)
  assert_eq(mac.line_height, 0.0)
  assert_eq(mac.letter_spacing, 0.0)
  let windows = editor_font_defaults_for_platform(Windows)
  assert_eq(windows.font_family, default_windows_font_family)
  assert_eq(windows.font_weight, "normal")
  assert_eq(windows.font_size, 14.0)
  assert_eq(windows.line_height, 0.0)
  assert_eq(windows.letter_spacing, 0.0)
  let other = editor_font_defaults_for_platform(Other)
  assert_eq(other.font_family, default_linux_font_family)
  assert_eq(other.font_weight, "normal")
  assert_eq(other.font_size, 14.0)
  assert_eq(other.line_height, 0.0)
  assert_eq(other.letter_spacing, 0.0)
  assert_eq(golden_line_height_ratio_for_platform(MacOS), 1.5)
  assert_eq(golden_line_height_ratio_for_platform(Windows), 1.35)
  assert_eq(golden_line_height_ratio_for_platform(Other), 1.35)
}

///|
test "massaged family omits an empty or identical fallback" {
  assert_eq(massage_font_family("Fira Code", ""), "\"Fira Code\"")
  assert_eq(massage_font_family("Fira", "Fallback"), "Fira, Fallback")
  assert_eq(
    massage_font_family(default_mac_font_family, default_mac_font_family),
    default_mac_font_family,
  )
}
