// Intentionally staged host-facing API. The repository's built-in viewer
// consumes `QuickDiffHandle`; embedders will use the concrete service setter
// when SCM/provider integration supplies a baseline.

///|
/// Stores (or, with `None`, clears) the original content for `resource` and
/// fires the change event.
pub fn QuickDiffService::set_original_content(
  self : QuickDiffService,
  resource : @base_common.Uri,
  content : String?,
) -> Unit {
  self.set_original_content_impl(resource, content)
}
