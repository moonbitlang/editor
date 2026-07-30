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
/// Whether collapsing this section would actually hide something.
///
/// This is deliberately defined by the hideable run rather than by the body
/// anchor count: an anchor that produced no in-place root element cannot be
/// hidden, so a body made only of such anchors must not be given a control
/// that does nothing.
pub fn MarkdownSection::is_foldable(
  self : MarkdownSection,
  projection : MarkdownDocumentProjection,
) -> Bool {
  self.body_rendered_element_indexes(projection).length() > 0
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
/// The level at which this anchor opens a section, or `None` if it opens none.
///
/// A heading only bounds a section when it is a *top-level* block, which is
/// exactly when it produced a root element. A heading nested in a blockquote or
/// a list item renders inside its container and has no root ordinal of its own,
/// so it can neither be hidden independently nor end the enclosing section --
/// treating it as a boundary would leave the container's following siblings
/// stranded outside every section.
fn markdown_anchor_section_level(anchor : MarkdownBlockAnchor) -> Int? {
  match (anchor.heading_level, anchor.rendered_element_index) {
    (Some(level), Some(_)) => Some(level)
    _ => None
  }
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
    guard markdown_anchor_section_level(anchor) is Some(level) else { continue }
    // The body ends before the next anchor that is a heading at this level or
    // shallower; a deeper heading is part of this body and opens its own
    // nested section on its own iteration.
    let body_indexes = []
    let mut end_offset = anchor.source_range.end_exclusive
    for follower = index + 1
        follower < anchors.length()
        follower = follower + 1 {
      let candidate = anchors[follower]
      if markdown_anchor_section_level(candidate) is Some(candidate_level) &&
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

///|
/// A reconciliation key that survives a source or theme reprojection.
///
/// Element identity cannot be used: a reprojection replaces the article
/// wholesale, so every node is new. Anchor index alone is not enough either —
/// editing one paragraph shifts every later index. The key is therefore the
/// heading's level, its normalized text, and its ordinal among identical
/// (level, text) pairs, which is stable under edits elsewhere in the document
/// and still distinguishes repeated headings such as two `## Example` sections.
///
/// `source` must be the exact snapshot the projection was parsed from; passing
/// a different string yields keys that will not match on the next reprojection.
fn MarkdownSection::stable_key(
  self : MarkdownSection,
  projection : MarkdownDocumentProjection,
  source : String,
  occurrence : Int,
) -> String {
  let text = markdown_section_heading_text(self, projection, source)
  "\{self.level}\u{1f}\{text}\u{1f}\{occurrence}"
}

///|
/// The heading's identity text for reconciliation.
///
/// The parsed inline plaintext retained at parse time is authoritative: it has
/// already applied the markup rules, so emphasis, code spans, and a multi-line
/// setext heading all reduce to the words a reader sees. The source-derived
/// fallback exists only for a projection built before that field was retained.
fn markdown_section_heading_text(
  section : MarkdownSection,
  projection : MarkdownDocumentProjection,
  source : String,
) -> String {
  guard section.heading_anchor_index >= 0 &&
    section.heading_anchor_index < projection.block_anchors.length() else {
    return ""
  }
  let anchor = projection.block_anchors[section.heading_anchor_index]
  match anchor.heading_text {
    Some(text) => text
    None => markdown_heading_text_from_source(anchor, source)
  }
}

///|
/// Last-resort text extraction straight from the snapshot. Strips the opening
/// ATX run and a whitespace-delimited closing run, then collapses whitespace.
fn markdown_heading_text_from_source(
  anchor : MarkdownBlockAnchor,
  source : String,
) -> String {
  let range = anchor.source_range
  let start = range.start.max(0).min(source.length())
  let end = range.end_exclusive.max(start).min(source.length())
  let raw = source[start:end].to_owned()
  let first_line = match raw.find("\n") {
    Some(index) => raw[0:index].to_owned()
    None => raw
  }
  let mut trimmed = first_line.trim(chars=" \t\r")
  while trimmed.has_prefix("#") {
    trimmed = trimmed[1:].to_owned()
  }
  let mut hashes = 0
  while hashes < trimmed.length() &&
        trimmed[trimmed.length() - 1 - hashes] == '#' {
    hashes = hashes + 1
  }
  if hashes > 0 {
    let before = trimmed.length() - hashes
    if before == 0 || trimmed[before - 1] == ' ' || trimmed[before - 1] == '\t' {
      trimmed = trimmed[0:before].to_owned()
    }
  }
  let collapsed = StringBuilder::new()
  let mut wrote_any = false
  let mut in_space = false
  for unit in trimmed.trim(chars=" \t\r") {
    if unit == ' ' || unit == '\t' {
      in_space = true
    } else {
      if in_space && wrote_any {
        collapsed.write_char(' ')
      }
      in_space = false
      wrote_any = true
      collapsed.write_char(unit)
    }
  }
  collapsed.to_string()
}

///|
/// Assigns each section its reconciliation key, resolving the occurrence
/// ordinal for repeated headings. Returned in the same order as `sections`.
pub fn markdown_section_keys(
  sections : Array[MarkdownSection],
  projection : MarkdownDocumentProjection,
  source : String,
) -> Array[String] {
  let seen : Map[String, Int] = Map([])
  let keys = []
  for section in sections {
    let base = section.stable_key(projection, source, 0)
    let occurrence = seen.get(base).unwrap_or(0)
    seen[base] = occurrence + 1
    keys.push(section.stable_key(projection, source, occurrence))
  }
  keys
}
