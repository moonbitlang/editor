///|
/// Minimal baseline-content capability used by the quick-diff contribution.
/// The handle owns no captured backing state or lifecycle.
pub struct QuickDiffHandle {
  priv get_original_content_callback : (@base_common.Uri) -> String?
  priv on_did_change_original_callback : ((@base_common.Uri) -> Unit) -> @base_common.Disposable
}

///|
/// Constructs a handle from both required quick-diff callbacks.
#alias(new)
pub fn QuickDiffHandle::QuickDiffHandle(
  get_original_content~ : (@base_common.Uri) -> String?,
  on_did_change_original~ : ((@base_common.Uri) -> Unit) -> @base_common.Disposable,
) -> QuickDiffHandle {
  {
    get_original_content_callback: get_original_content,
    on_did_change_original_callback: on_did_change_original,
  }
}

///|
pub fn QuickDiffHandle::get_original_content(
  self : QuickDiffHandle,
  resource : @base_common.Uri,
) -> String? {
  (self.get_original_content_callback)(resource)
}

///|
pub fn QuickDiffHandle::on_did_change_original(
  self : QuickDiffHandle,
  listener : (@base_common.Uri) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_original_callback)(listener)
}
