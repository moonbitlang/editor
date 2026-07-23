///|
/// Monaco's `IEditorMouseEvent`: raw editor-DOM facts plus a hit-tested target
/// in the coordinate space established by the producer.
pub(all) struct EditorMouseEvent {
  event : EditorDomMouseEvent
  target : MouseTarget
}

///|
/// Monaco's `IPartialEditorMouseEvent`; mouse-leave delivery has no target.
pub(all) struct PartialEditorMouseEvent {
  event : EditorDomMouseEvent
  target : MouseTarget?
}
