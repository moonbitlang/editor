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

///|
/// Snapshot length in the repo's JavaScript-compatible UTF-16 indexing model.
pub fn DocumentSnapshot::length(self : DocumentSnapshot) -> Int {
  self.length_impl()
}

///|
/// Number of logical lines, including a final empty line after a newline.
pub fn DocumentSnapshot::line_count(self : DocumentSnapshot) -> Int {
  self.line_count_impl()
}

///|
pub fn DocumentSnapshot::line_start_offset(
  self : DocumentSnapshot,
  line : Int,
) -> Int {
  self.line_start_offset_impl(line)
}

///|
pub fn DocumentSnapshot::line_end_offset(
  self : DocumentSnapshot,
  line : Int,
) -> Int {
  self.line_end_offset_impl(line)
}

///|
pub fn DocumentSnapshot::slice(
  self : DocumentSnapshot,
  range : @base_common.OffsetRange,
) -> String {
  self.slice_impl(range)
}

///|
pub fn DocumentSnapshot::line_at_offset(
  self : DocumentSnapshot,
  offset : Int,
) -> Int {
  self.line_at_offset_impl(offset)
}

///|
pub fn DocumentSnapshot::position_at_offset(
  self : DocumentSnapshot,
  offset : Int,
) -> @base_common.Position {
  self.position_at_offset_impl(offset)
}

///|
pub fn DocumentSnapshot::offset_at_position(
  self : DocumentSnapshot,
  position : @base_common.Position,
) -> Int {
  self.offset_at_position_impl(position)
}
