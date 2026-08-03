// Mounted white-box coverage for Markdown section folding: fold state,
// auto-fold seeding, toggle, and conservative reconciliation are all
// synchronous root-owned state, so this is the lowest layer that can observe
// them (docs/harness.md). Real pointer clicks, computed `display:none`, and
// hover interleavings belong to the Playwright component scenario.

///|
fn markdown_folding_fixture_source() -> String {
  (
    #|# Top
    #|
    #|intro paragraph
    #|
    #|## Guide
    #|
    #|guide paragraph
    #|
    #|```mbt check
    #|fn folded_answer() -> Int { 42 }
    #|```
    #|
    #|### Deep
    #|
    #|deep one
    #|
    #|deep two
    #|
    #|deep three
    #|
    #|deep four
    #|
    #|deep five
    #|
    #|deep six
    #|
    #|### Tiny
    #|
    #|tiny body
    #|
  )
}

///|
fn markdown_folding_offset_of(source : String, needle : String) -> Int raise {
  guard source.find(needle) is Some(offset) else {
    fail("fixture must contain \{needle}")
  }
  offset
}

///|
fn markdown_folding_article(
  markdown : @markdown_document.MarkdownDocumentView,
) -> @rdom.Element raise {
  guard markdown
    .root()
    .query_selector(".moonbit-viewer-markdown-document-article")
    is Some(article) else {
    fail("Markdown article is missing from the public root DOM")
  }
  article
}

///|
fn markdown_folding_hidden_count(
  markdown : @markdown_document.MarkdownDocumentView,
) -> Int raise {
  markdown_folding_article(markdown)
  .query_selector_all("[data-markdown-section-hidden=\"true\"]")
  .length()
}

///|
fn markdown_folding_toc_state(
  markdown : @markdown_document.MarkdownDocumentView,
) -> (Bool, Bool) raise {
  guard markdown.root().query_selector(".moonbit-viewer-markdown-toc")
    is Some(toc) else {
    fail("Markdown TOC is missing from the public root DOM")
  }
  (
    toc.get_attribute("data-toc-visible") == Some("true"),
    toc.get_attribute("data-toc-expanded") == Some("true"),
  )
}

///|
test "auto-fold seeds depth-3 bulk, toggles by offset, and keeps the parse" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  let source = markdown_folding_fixture_source()
  let model = markdown_presentation_test_model(
    "/src/folding.mbt.md", "moonbit", source,
  )
  defer {
    viewer.dispose()
    model.dispose()
  }
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 320.0, 180.0)
  viewer.attach(host)
  viewer.set_model(Some(model))
  flush_mounted_test_frames()
  guard viewer.current_markdown_document() is Some(markdown) else {
    fail("mounted .mbt.md did not install Markdown")
  }
  let generation_before = markdown.projection_generation()

  // The auto-fold policy collapsed exactly the bulky depth-3 section: Top and
  // Guide are shallower than the depth floor, Tiny is under both bulk
  // thresholds.
  let deep_offset = markdown_folding_offset_of(source, "### Deep")
  assert_eq(viewer.collapsed_markdown_sections(), [deep_offset])
  let hidden_while_seeded = markdown_folding_hidden_count(markdown)
  assert_eq(hidden_while_seeded, 6)

  // Every foldable heading carries one control; the collapsed one says so in
  // both the CSS-facing and the accessibility-facing state.
  let article = markdown_folding_article(markdown)
  let toggles = article.query_selector_all(
    ".moonbit-viewer-markdown-fold-toggle",
  )
  assert_eq(toggles.length(), 4)
  guard article.query_selector("[data-collapsed=\"true\"]")
    is Some(collapsed_toggle) else {
    fail("expected the seeded section's toggle to display collapsed")
  }
  assert_eq(collapsed_toggle.get_attribute("aria-expanded"), Some("false"))

  // Expanding by heading offset is the host-facing seam; the DOM follows, and
  // none of it re-parses the document.
  assert_true(viewer.toggle_markdown_section_at(deep_offset))
  assert_eq(viewer.collapsed_markdown_sections(), [])
  assert_eq(markdown_folding_hidden_count(markdown), 0)
  assert_true(viewer.toggle_markdown_section_at(deep_offset))
  assert_eq(viewer.collapsed_markdown_sections(), [deep_offset])
  assert_eq(markdown_folding_hidden_count(markdown), hidden_while_seeded)
  assert_eq(markdown.projection_generation(), generation_before)

  // A fence inside a collapsed section keeps its semantic rows registered:
  // collapse is visibility, not membership.
  assert_true(
    viewer.toggle_markdown_section_at(
      markdown_folding_offset_of(source, "## Guide"),
    ),
  )
  assert_true(markdown.semantic_code_lines().length() > 0)
  assert_eq(markdown.projection_generation(), generation_before)

  // An offset before every heading, and a Code presentation, both refuse.
  assert_false(viewer.toggle_markdown_section_at(9999999))
}

///|
test "reconciliation preserves untouched folds and expands rewritten bodies" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  let source = markdown_folding_fixture_source()
  let model = markdown_presentation_test_model(
    "/src/folding.mbt.md", "moonbit", source,
  )
  defer {
    viewer.dispose()
    model.dispose()
  }
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 320.0, 180.0)
  viewer.attach(host)
  viewer.set_model(Some(model))
  flush_mounted_test_frames()
  let deep_offset = markdown_folding_offset_of(source, "### Deep")

  // An agent edit that touches only Tiny's body: Deep's key and body are
  // unchanged, so its collapse survives the reprojection.
  let edited_elsewhere = source.replace(
    old="tiny body",
    new="tiny body, edited",
  )
  model.set_value(edited_elsewhere)
  flush_mounted_test_frames()
  assert_eq(viewer.collapsed_markdown_sections(), [
    markdown_folding_offset_of(edited_elsewhere, "### Deep"),
  ])

  // An agent edit inside Deep's own body: the fingerprint no longer matches,
  // so the section opens rather than hiding freshly written content (P1).
  let edited_deep = edited_elsewhere.replace(
    old="deep three",
    new="deep three, rewritten by an agent",
  )
  model.set_value(edited_deep)
  flush_mounted_test_frames()
  assert_eq(viewer.collapsed_markdown_sections(), [])

  // Re-collapse, then change only the theme: the source is untouched, so the
  // re-rendered article comes back with the same fold state and controls.
  assert_true(viewer.toggle_markdown_section_at(deep_offset))
  viewer.update_options(viewer.get_options().with_theme("dark"))
  flush_mounted_test_frames()
  guard viewer.current_markdown_document() is Some(markdown) else {
    fail("theme change must not drop the Markdown presentation")
  }
  assert_eq(viewer.collapsed_markdown_sections(), [
    markdown_folding_offset_of(edited_deep, "### Deep"),
  ])
  assert_true(markdown_folding_hidden_count(markdown) > 0)
  assert_true(
    markdown_folding_article(markdown).query_selector(
      "[data-collapsed=\"true\"]",
    )
    is Some(_),
  )
}

///|
test "the toc bar lists sections, gates on three, and navigation expands" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  let source = markdown_folding_fixture_source()
  let model = markdown_presentation_test_model(
    "/src/folding.mbt.md", "moonbit", source,
  )
  defer {
    viewer.dispose()
    model.dispose()
  }
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 320.0, 180.0)
  viewer.attach(host)
  viewer.set_model(Some(model))
  flush_mounted_test_frames()
  guard viewer.current_markdown_document() is Some(markdown) else {
    fail("mounted .mbt.md did not install Markdown")
  }

  // Four sections -> the bar renders (collapsed), one row per section, with
  // structural depth carried for indentation.
  assert_eq(markdown_folding_toc_state(markdown), (true, false))
  let rows = markdown
    .root()
    .query_selector_all(".moonbit-viewer-markdown-toc-row")
  assert_eq(rows.length(), 4)
  assert_eq(rows[0].get_attribute("data-toc-depth"), Some("1"))
  assert_eq(rows[2].get_attribute("data-toc-depth"), Some("3"))

  // Navigating to the auto-collapsed Deep section expands it (the reveal
  // chain stays open) and records the expansion as a reader decision that
  // survives an unrelated agent edit.
  let deep_offset = markdown_folding_offset_of(source, "### Deep")
  guard viewer.current_markdown_browser_data() is Some(data) else {
    fail("expected root Markdown composition")
  }
  data.navigate_markdown_section(deep_offset)
  assert_eq(viewer.collapsed_markdown_sections(), [])
  model.set_value(source.replace(old="tiny body", new="tiny body, edited"))
  flush_mounted_test_frames()
  assert_eq(viewer.collapsed_markdown_sections(), [])

  // A two-section document renders no bar.
  let small = markdown_presentation_test_model(
    "/src/small.mbt.md",
    "moonbit",
    (
      #|# One
      #|
      #|body
      #|
      #|# Two
      #|
      #|body
      #|
    ),
  )
  viewer.set_model(Some(small))
  flush_mounted_test_frames()
  guard viewer.current_markdown_document() is Some(small_markdown) else {
    fail("expected Markdown for the small document")
  }
  assert_eq(markdown_folding_toc_state(small_markdown), (false, false))
  small.dispose()
}
