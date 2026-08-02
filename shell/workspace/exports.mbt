///|
/// Document-provider adapters retained as the documented host-neutral
/// workspace contract.
pub async fn read_document(
  provider : &FileSystemProvider,
  uri : @base_common.Uri,
) -> DocumentReadResult {
  read_document_impl(provider, uri)
}

///|
pub fn watch_file(
  provider : &FileSystemProvider,
  uri : @base_common.Uri,
  listener : (Array[FileChange]) -> Unit,
) -> FileWatch {
  watch_file_impl(provider, uri, listener)
}

///|
/// Stable content-derived revision retained for provider implementations.
pub fn revision_from_text(text : String) -> String {
  revision_from_text_impl(text)
}
