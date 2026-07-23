// `get_editor_class_name` ports Monaco's `EditorClassName.compute`
// (`editorOptions.ts:1660-1690`): `showUnused`/`showDeprecated` are
// option-driven root classes, present by default and dropped when the
// corresponding option is off.

///|
test "root class defaults include showUnused and showDeprecated" {
  inspect(
    get_editor_class_name(
      "source-loaded",
      is_safari=false,
      is_webkit_webview=false,
      is_macos=false,
    ),
    content="monaco-editor moonbit-viewer readonly-editor no-user-select showUnused showDeprecated source-loaded",
  )
}

///|
test "show_unused off drops only the showUnused class" {
  inspect(
    get_editor_class_name(
      "source-loaded",
      show_unused=false,
      is_safari=false,
      is_webkit_webview=false,
      is_macos=false,
    ),
    content="monaco-editor moonbit-viewer readonly-editor no-user-select showDeprecated source-loaded",
  )
}

///|
test "show_deprecated off drops only the showDeprecated class" {
  inspect(
    get_editor_class_name(
      "source-loaded",
      show_deprecated=false,
      is_safari=false,
      is_webkit_webview=false,
      is_macos=false,
    ),
    content="monaco-editor moonbit-viewer readonly-editor no-user-select showUnused source-loaded",
  )
}

///|
test "both off keeps the base classes and focus suffix" {
  inspect(
    get_editor_class_name(
      "source-empty",
      focused=true,
      show_unused=false,
      show_deprecated=false,
      is_safari=false,
      is_webkit_webview=false,
      is_macos=false,
    ),
    content="monaco-editor moonbit-viewer readonly-editor no-user-select source-empty focused",
  )
}

///|
test "extra editor classes cover browser and macOS axes" {
  inspect(
    extra_editor_class_name(false, false, false),
    content="no-user-select",
  )
  inspect(
    extra_editor_class_name(false, false, true),
    content="no-user-select mac",
  )
  inspect(
    extra_editor_class_name(true, false, false),
    content="no-minimap-shadow enable-user-select",
  )
  inspect(
    extra_editor_class_name(true, false, true),
    content="no-minimap-shadow enable-user-select mac",
  )
  inspect(
    extra_editor_class_name(false, true, false),
    content="no-minimap-shadow enable-user-select",
  )
  inspect(
    extra_editor_class_name(false, true, true),
    content="no-minimap-shadow enable-user-select mac",
  )
  inspect(
    extra_editor_class_name(true, true, false),
    content="no-minimap-shadow enable-user-select",
  )
  inspect(
    extra_editor_class_name(true, true, true),
    content="no-minimap-shadow enable-user-select mac",
  )
}
