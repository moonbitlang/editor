///|
/// The selection subset of Monaco's `coreCommands.ts` `CoreNavigationCommands`
/// that the readonly viewing path drives. These are the commands a
/// `ViewController.dispatchMouse` (Phase 4) maps pointer gestures to; here they
/// are thin, named transcriptions over the `CursorsController`.
///
/// `MoveTo` collapses the selection at a position (a plain click); `MoveToSelect`
/// extends the existing selection to a position (shift-click / drag). Both take
/// a view position, matching the viewer's DOM-caret hit test.

///|
/// `CoreNavigationCommands.MoveTo`: collapse the cursor at `view_position`.
pub fn move_to(
  controller : CursorsController,
  view_position : @base_common.Position,
) -> Unit {
  controller.move_to(view_position, false) |> ignore
}

///|
/// `CoreNavigationCommands.MoveToSelect`: extend the selection to `view_position`.
pub fn move_to_select(
  controller : CursorsController,
  view_position : @base_common.Position,
) -> Unit {
  controller.move_to(view_position, true) |> ignore
}
