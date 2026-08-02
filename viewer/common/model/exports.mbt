// Deliberate external/staged contracts without non-test field consumers in
// this repository. Keeping them here makes the `moon ide analyze` exception
// explicit without hiding payloads carried by surviving public APIs.

///|
/// `IModelContentChange` (`model/mirrorTextModel.ts`): one change entry of
/// the public content-changed payload.
pub(all) struct ModelContentChange {
  /// The range that got replaced.
  range : @base_common.Range
  /// The offset of the range that got replaced.
  range_offset : Int
  /// The length of the range that got replaced.
  range_length : Int
  /// The new text for the range.
  text : String
} derive(Debug)
