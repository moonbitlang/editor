// Section structure over an already-parsed Markdown document. This file is
// DOM-free and derives everything from `MarkdownDocumentProjection`, so the
// rendered article, the source projection, and the section tree are all facts
// of the same parse.

///|
/// One foldable heading section in document order.
///
/// `heading_anchor_index` and `body_anchor_indexes` index
/// `MarkdownDocumentProjection::block_anchors`. `source_range` spans the heading
/// and its body in original-snapshot UTF-16 offsets; `body_source_range` spans
/// the body alone and is `None` for a heading with no body.
///
/// A section is foldable exactly when it has a body: a heading immediately
/// followed by a same-or-higher-level heading collapses to nothing, so it
/// carries no control.
pub(all) struct MarkdownSection {
  heading_anchor_index : Int
  level : Int
  body_anchor_indexes : Array[Int]
  source_range : @common.OffsetRange
  body_source_range : @common.OffsetRange?
} derive(Eq, Debug)

///|
/// Whether collapsing this section would hide anything.
pub fn MarkdownSection::is_foldable(self : MarkdownSection) -> Bool {
  self.body_anchor_indexes.length() > 0
}

///|
/// The root-element ordinals this section's body occupies, in document order.
///
/// Anchors that produced no in-place root element (blank lines, link reference
/// definitions, omitted raw HTML, and nested anchors) contribute nothing, so
/// hiding this run never shifts an unrelated element's ordinal. The heading's
/// own element is deliberately excluded: collapsing hides the body and leaves
/// the heading as the affordance.
pub fn MarkdownSection::body_rendered_element_indexes(
  self : MarkdownSection,
  projection : MarkdownDocumentProjection,
) -> Array[Int] {
  let result = []
  for anchor_index in self.body_anchor_indexes {
    if anchor_index >= 0 && anchor_index < projection.block_anchors.length() {
      match projection.block_anchors[anchor_index].rendered_element_index {
        Some(rendered) => result.push(rendered)
        None => ()
      }
    }
  }
  result
}

///|
/// Derives the section tree from a parsed projection.
///
/// A heading at level `L` opens a section whose body runs to the anchor before
/// the next anchor at level `L` or lower, or to the end of the document.
/// Sections nest, and the result is in document order with an outer section
/// appearing before the inner sections it contains.
///
/// Anchors before the first heading belong to no section: a document preamble
/// is not foldable because it has no heading to fold into.
pub fn markdown_sections(
  projection : MarkdownDocumentProjection,
) -> Array[MarkdownSection] {
  let anchors = projection.block_anchors
  let sections = []
  for index, anchor in anchors {
    guard anchor.heading_level is Some(level) else { continue }
    // The body ends before the next anchor that is a heading at this level or
    // shallower; a deeper heading is part of this body and opens its own
    // nested section on its own iteration.
    let body_indexes = []
    let mut end_offset = anchor.source_range.end_exclusive
    for follower = index + 1
        follower < anchors.length()
        follower = follower + 1 {
      let candidate = anchors[follower]
      if candidate.heading_level is Some(candidate_level) &&
        candidate_level <= level {
        break
      }
      body_indexes.push(follower)
      if candidate.source_range.end_exclusive > end_offset {
        end_offset = candidate.source_range.end_exclusive
      }
    }
    let body_source_range = if body_indexes.length() == 0 {
      None
    } else {
      Some(
        @common.OffsetRange(
          anchors[body_indexes[0]].source_range.start,
          end_offset,
        ),
      )
    }
    sections.push({
      heading_anchor_index: index,
      level,
      body_anchor_indexes: body_indexes,
      source_range: OffsetRange(anchor.source_range.start, end_offset),
      body_source_range,
    })
  }
  sections
}

///|
/// The innermost section containing `source_offset`, or `None` when the offset
/// precedes every heading. Used to answer "which section owns this position"
/// without a second scan of the document.
pub fn markdown_section_at_source_offset(
  sections : Array[MarkdownSection],
  source_offset : Int,
) -> MarkdownSection? {
  let mut found = None
  for section in sections {
    if section.source_range.contains(source_offset) {
      // Sections are emitted outermost-first, so a later containing section is
      // strictly more nested than an earlier one.
      found = Some(section)
    }
  }
  found
}
