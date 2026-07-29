// Section derivation over a real parse. Every case renders actual Markdown
// rather than hand-building anchors, so these assertions also pin the
// heading-level retention added to `MarkdownBlockAnchor`.

///|
/// Renders `source` and describes each derived section as
/// `level:heading_anchor:[body anchors]:foldable`.
fn describe_sections(source : String) -> Array[String] {
  let projection = @markdown.render_markdown(source).projection
  @markdown.markdown_sections(projection).map(section => {
    "level \{section.level} heading@\{section.heading_anchor_index} body\{Repr(section.body_anchor_indexes)} foldable=\{section.is_foldable()}"
  })
}

///|
test "a heading owns every following block until a same-or-shallower heading" {
  debug_inspect(
    describe_sections(
      (
        #|# One
        #|
        #|body of one
        #|
        #|# Two
        #|
        #|body of two
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1] foldable=true",
      #|  "level 1 heading@2 body[3] foldable=true",
      #|]
    ),
  )
}

///|
test "a deeper heading nests inside the section above it" {
  debug_inspect(
    describe_sections(
      (
        #|# Outer
        #|
        #|outer body
        #|
        #|## Inner
        #|
        #|inner body
        #|
        #|# Next
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1, 2, 3] foldable=true",
      #|  "level 2 heading@2 body[3] foldable=true",
      #|  "level 1 heading@4 body[] foldable=false",
      #|]
    ),
  )
}

///|
test "a heading with no body is not foldable" {
  debug_inspect(
    describe_sections(
      (
        #|# Empty
        #|# Also empty
        #|## Deeper, and this one has a body
        #|
        #|body text
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[] foldable=false",
      #|  "level 1 heading@1 body[2, 3] foldable=true",
      #|  "level 2 heading@2 body[3] foldable=true",
      #|]
    ),
  )
}

///|
test "a level jump does not create an intermediate section" {
  debug_inspect(
    describe_sections(
      (
        #|# One
        #|
        #|### Three
        #|
        #|body
        #|
        #|## Two
        #|
        #|body two
        #|
      ),
    ),
    content=(
      #|[
      #|  "level 1 heading@0 body[1, 2, 3, 4] foldable=true",
      #|  "level 3 heading@1 body[2] foldable=true",
      #|  "level 2 heading@3 body[4] foldable=true",
      #|]
    ),
  )
}

///|
test "setext headings behave exactly like their ATX levels" {
  debug_inspect(
    (
      describe_sections(
        (
          #|Title
          #|=====
          #|
          #|body
          #|
          #|Subtitle
          #|--------
          #|
          #|sub body
          #|
        ),
      ),
      describe_sections(
        (
          #|# Title
          #|
          #|body
          #|
          #|## Subtitle
          #|
          #|sub body
          #|
        ),
      ),
    ),
    content=(
      #|(
      #|  [
      #|    "level 1 heading@0 body[1, 2, 3] foldable=true",
      #|    "level 2 heading@2 body[3] foldable=true",
      #|  ],
      #|  [
      #|    "level 1 heading@0 body[1, 2, 3] foldable=true",
      #|    "level 2 heading@2 body[3] foldable=true",
      #|  ],
      #|)
    ),
  )
}

///|
test "a document with no heading has no sections" {
  debug_inspect(
    describe_sections(
      (
        #|just prose
        #|
        #|and more prose
        #|
      ),
    ),
    content=(
      #|[]
    ),
  )
}

///|
test "a preamble before the first heading belongs to no section" {
  debug_inspect(
    describe_sections(
      (
        #|preamble prose
        #|
        #|# First
        #|
        #|body
        #|
      ),
    ),
    content=(
      #|["level 1 heading@1 body[2] foldable=true"]
    ),
  )
}

///|
test "the body source range covers the body and excludes the heading" {
  let source =
    #|# Title
    #|
    #|body line
    #|
  let projection = @markdown.render_markdown(source).projection
  let sections = @markdown.markdown_sections(projection)
  guard sections is [section, ..] else { fail("expected one section") }
  let heading = projection.block_anchors[section.heading_anchor_index]
  debug_inspect(
    (
      section.source_range,
      section.body_source_range,
      // the body starts after the heading ends
      section.body_source_range.map(body => {
        body.start >= heading.source_range.end_exclusive
      }),
    ),
    content=(
      #|(
      #|  { start: 0, end_exclusive: 18 },
      #|  Some({ start: 9, end_exclusive: 18 }),
      #|  Some(true),
      #|)
    ),
  )
}

///|
test "the hidden run is the body's rendered ordinals, never the heading's" {
  let source =
    #|# Title
    #|
    #|first paragraph
    #|
    #|second paragraph
    #|
    #|# Next
    #|
  let projection = @markdown.render_markdown(source).projection
  let sections = @markdown.markdown_sections(projection)
  guard sections is [first, ..] else { fail("expected a first section") }
  let heading_ordinal = projection.block_anchors[first.heading_anchor_index].rendered_element_index
  debug_inspect(
    (
      heading_ordinal,
      first.body_rendered_element_indexes(projection),
      // the heading's own element is never in the hidden run
      first
      .body_rendered_element_indexes(projection)
      .contains(heading_ordinal.unwrap_or(-1)),
    ),
    content=(
      #|(Some(0), [1, 2], false)
    ),
  )
}

///|
test "a code fence inside a section is part of that section's body" {
  let source =
    #|# Example
    #|
    #|```mbt check
    #|test { }
    #|```
    #|
    #|# Other
    #|
  let projection = @markdown.render_markdown(source).projection
  let sections = @markdown.markdown_sections(projection)
  guard sections is [example, ..] else { fail("expected the example section") }
  guard projection.code_blocks is [block, ..] else {
    fail("expected one code block")
  }
  debug_inspect(
    (
      example.is_foldable(),
      // the fence's own anchor is inside the section's source span
      example.source_range.contains(block.block_source_range.start),
      block.is_moonbit_check_fence(MoonBitMarkdown),
    ),
    content=(
      #|(true, true, true)
    ),
  )
}

///|
test "section lookup by source offset returns the innermost match" {
  let source =
    #|# Outer
    #|
    #|outer body
    #|
    #|## Inner
    #|
    #|inner body
    #|
  let projection = @markdown.render_markdown(source).projection
  let sections = @markdown.markdown_sections(projection)
  guard source.find("inner body") is Some(inner_body_offset) else {
    fail("fixture must contain the inner body")
  }
  guard source.find("outer body") is Some(outer_body_offset) else {
    fail("fixture must contain the outer body")
  }
  let level_at = offset => {
    @markdown.markdown_section_at_source_offset(sections, offset).map(section => {
      section.level
    })
  }
  debug_inspect(
    (level_at(outer_body_offset), level_at(inner_body_offset), level_at(0)),
    content=(
      #|(Some(1), Some(2), Some(1))
    ),
  )
}
