// Shared DOM-free editor layout constants used by the browser view,
// controller, and root viewer facade. They live in common/core so every
// browser tier can consume the same values without reversing the dependency
// direction back into the root `viewer` package.

///|
/// Right padding of `.view-line-content`, part of the horizontal scroll extent.
pub let code_right_padding = 16.0

///|
/// Editor scrollbar defaults from Monaco's `EditorScrollbar` option.
pub let editor_vertical_scrollbar_size = 14.0

///|
pub let editor_horizontal_scrollbar_size = 12.0
