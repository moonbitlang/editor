// Explicit staged context-menu contract. The submenu row is implemented but
// not yet created by the root Viewer; keeping the closed entry union here
// makes that intentional reservation visible to `moon ide analyze`.

///|
/// Concrete rows understood by the browser menu shell. Command ids remain
/// opaque here; the root Viewer resolves and executes them.
pub(all) enum ContextMenuEntry {
  ContextMenuAction(id~ : String, label~ : String, keybinding_label~ : String?)
  ContextMenuSeparator
  ContextMenuSubmenu(label~ : String, entries~ : Array[ContextMenuEntry])
}
