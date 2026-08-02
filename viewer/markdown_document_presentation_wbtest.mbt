///|
fn markdown_presentation_test_model(
  path : String,
  language_id : String,
  source : String,
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="markdown-tests",
      path~,
    ),
    path,
    language_id,
    1,
    "markdown-presentation-rev-1",
    source,
  )
}

///|
fn assert_markdown_kind(
  model : @model.TextModel,
  expected_resource_kind : @markdown_core.MarkdownResourceKind,
) -> Unit raise {
  match document_presentation_kind(model) {
    MarkdownDocument(actual) => assert_true(actual == expected_resource_kind)
    CodeDocument => fail("expected Markdown document presentation")
  }
}

///|
test "Markdown presentation classifier is exact over URI path and language id" {
  let ordinary = markdown_presentation_test_model(
    "/README.md", "plaintext", "# ordinary",
  )
  let moonbit = markdown_presentation_test_model(
    "/src/literate.mbt.md", "moonbit", "# literate",
  )
  let untitled = markdown_presentation_test_model(
    "/untitled", "markdown", "# untitled",
  )
  let uppercase = markdown_presentation_test_model(
    "/README.MD", "plaintext", "# code",
  )
  defer {
    ordinary.dispose()
    moonbit.dispose()
    untitled.dispose()
    uppercase.dispose()
  }
  assert_markdown_kind(ordinary, OrdinaryMarkdown)
  assert_markdown_kind(moonbit, MoonBitMarkdown)
  assert_markdown_kind(untitled, OrdinaryMarkdown)
  assert_true(document_presentation_kind(uppercase) is CodeDocument)

  let viewer = Viewer::Viewer()
  viewer.set_model(Some(moonbit))
  assert_false(viewer.is_code_presentation())
  assert_true(viewer.current_browser_presentation() is None)
  viewer.set_model(Some(uppercase))
  assert_true(viewer.is_code_presentation())
  viewer.dispose()
}

///|
extern "js" fn markdown_document_test_same_element(
  left : @rdom.Element,
  right : @rdom.Element,
) -> Bool = "(left, right) => left === right"

///|
fn markdown_document_test_article(
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
extern "js" fn markdown_document_test_text(element : @rdom.Element) -> String = "(element) => String(element.textContent || '')"

///|
extern "js" fn markdown_document_test_scroll_alignment(
  element : @rdom.Element,
) -> String =
  #| element => String(element?.__scrollIntoView?.block || "")

///|
extern "js" fn markdown_document_test_dispatch_scroll(
  element : @rdom.Element,
) -> Unit = "(element) => element.dispatchEvent(new Event('scroll'))"

///|
extern "js" fn markdown_document_test_style_property(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => String(element.style[name] || '')"

///|
test "mounted Markdown keeps model truth and stable presentation capabilities" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  let model = markdown_presentation_test_model(
    "/src/literate.mbt.md",
    "moonbit",
    (
      #|# Literate source
      #|
      #|```mbt check
      #|fn answer() -> Int { 42 }
      #|```
    ),
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
  assert_true(viewer.current_markdown_browser_data() is Some(_))
  let root = markdown.root()
  let article = markdown_document_test_article(markdown)
  let overlay = markdown.overlay_mount()
  assert_eq(markdown_document_test_style_property(root, "width"), "320px")
  assert_eq(markdown_document_test_style_property(root, "height"), "180px")
  set_mounted_test_client_size(host, 480.0, 240.0)
  viewer.layout()
  flush_mounted_test_frames()
  assert_eq(markdown_document_test_style_property(root, "width"), "480px")
  assert_eq(markdown_document_test_style_property(root, "height"), "240px")
  assert_true(viewer.get_model().unwrap().same(model))
  assert_eq(viewer.get_value(), model.get_value())
  assert_true(
    markdown_document_test_same_element(viewer.get_dom_node().unwrap(), root),
  )
  assert_true(@base_browser.element_contains(root, markdown.viewport()))
  assert_true(@base_browser.element_contains(root, article))
  assert_true(@base_browser.element_contains(root, overlay))
  assert_eq(root.get_attribute("data-source-uri"), Some(model.uri.to_string()))
  assert_markdown_kind(model, MoonBitMarkdown)
  assert_eq(markdown.source_model_version(), model.get_version_id())
  assert_eq(markdown.projection().code_blocks.length(), 1)
  assert_eq(markdown.semantic_code_lines().length(), 1)
  let wrapper = article.query_selector(".moonbit-viewer-markdown-code-block")
  assert_true(wrapper is Some(_))
  assert_eq(
    wrapper.unwrap().get_attribute("data-markdown-semantic"),
    Some("moonbit-check"),
  )

  let initial_generation = markdown.projection_generation()
  viewer.set_value(
    (
      #|# Replacement
      #|
      #|```mbt check trailing
      #|fn replacement() -> Int { 7 }
      #|```
    ),
  )
  flush_mounted_test_frames()
  assert_true(
    markdown_document_test_same_element(
      viewer.current_markdown_document().unwrap().root(),
      root,
    ),
  )
  assert_true(
    markdown_document_test_same_element(
      markdown_document_test_article(markdown),
      article,
    ),
  )
  assert_true(
    markdown_document_test_same_element(markdown.overlay_mount(), overlay),
  )
  assert_eq(markdown.projection_generation(), initial_generation + 1)
  assert_eq(markdown.source_model_version(), model.get_version_id())
  assert_true(markdown_document_test_text(article).contains("replacement"))

  let theme_generation = markdown.projection_generation()
  viewer.update_options(
    viewer.get_options().with_theme("markdown-document-test-theme"),
  )
  flush_mounted_test_frames()
  assert_eq(markdown.projection_generation(), theme_generation + 1)
  assert_eq(
    root.get_attribute("data-theme"),
    Some("markdown-document-test-theme"),
  )
  assert_true(root.get_attribute("class").unwrap().contains("showUnused"))
  viewer.update_options({ ..viewer.get_options(), show_unused: false })
  assert_false(root.get_attribute("class").unwrap().contains("showUnused"))
  viewer.update_options({ ..viewer.get_options(), show_unused: true })
  assert_true(root.get_attribute("class").unwrap().contains("showUnused"))
  assert_true(
    markdown_document_test_same_element(
      markdown_document_test_article(markdown),
      article,
    ),
  )

  viewer.focus()
  assert_true(viewer.has_text_focus())
  let scroll_events = Ref(0)
  let scroll_subscription = viewer.on_did_scroll_change(_ => {
    scroll_events.val += 1
  })
  viewer.set_scroll_position(scroll_top=24.0, scroll_left=5.0)
  flush_mounted_test_frames()
  assert_eq(scroll_events.val, 1)
  markdown_document_test_dispatch_scroll(markdown.viewport())
  flush_mounted_test_frames()
  assert_eq(scroll_events.val, 1)
  scroll_subscription.dispose()
  assert_eq(viewer.get_scroll_top(), 24.0)
  assert_eq(viewer.get_scroll_left(), 5.0)
  assert_true(viewer.get_visible_ranges().length() > 0)
  viewer.reveal_line(3)
  let current_wrapper = article.query_selector(
    ".moonbit-viewer-markdown-code-block",
  )
  assert_eq(
    markdown_document_test_scroll_alignment(current_wrapper.unwrap()),
    "start",
  )
  viewer.send_reveal_range(Range(3, 1, 3, 1), Bottom, reveal_horizontal=false)
  assert_eq(
    markdown_document_test_scroll_alignment(current_wrapper.unwrap()),
    "end",
  )
  viewer.set_value("")
  flush_mounted_test_frames()
  let empty_visible = viewer.get_visible_ranges()
  assert_eq(empty_visible.length(), 1)
  assert_true(empty_visible[0] == model.get_full_model_range())
  viewer.dispose()
}

///|
test "Markdown detach retires presentation and root before model transition" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let viewer = Viewer::Viewer()
  let model = markdown_presentation_test_model(
    "/src/detach-order.mbt.md",
    "moonbit",
    (
      #|# Detach order
      #|
      #|```mbt check
      #|fn answer() -> Int { 42 }
      #|```
    ),
  )
  defer {
    viewer.dispose()
    model.dispose()
  }
  let host = @rdom.document().create_element("div")
  viewer.attach(host)
  viewer.set_model(Some(model))
  guard viewer.current_markdown_document() is Some(markdown) else {
    fail("mounted .mbt.md did not install Markdown")
  }
  guard viewer.mount is Mounted(mounted) &&
    mounted.placeholder is Some(placeholder) else {
    fail("mounted Viewer did not retain its placeholder")
  }
  let root = markdown.root()
  let overlay = markdown.overlay_mount()
  assert_true(@base_browser.element_contains(host, root))
  assert_true(markdown.semantic_code_lines().length() > 0)
  assert_true(
    overlay.query_selector(".moonbit-viewer-markdown-hover-widget") is Some(_),
  )

  let final_detachment_observed = Ref(false)
  let detachment_saw_disposed_semantic_dom = Ref(false)
  let detachment_saw_removed_hover_widget = Ref(false)
  let detachment_saw_removed_root = Ref(false)
  let detachment_saw_restored_placeholder = Ref(false)
  let subscription = viewer.on_did_detach_model_for_diagnostics(() => {
    final_detachment_observed.val = true
    detachment_saw_disposed_semantic_dom.val = markdown
      .semantic_code_lines()
      .is_empty()
    detachment_saw_removed_hover_widget.val = overlay.query_selector(
        ".moonbit-viewer-markdown-hover-widget",
      )
      is None
    detachment_saw_removed_root.val = !@base_browser.element_contains(
      host, root,
    )
    detachment_saw_restored_placeholder.val = @base_browser.element_contains(
      host,
      placeholder.root,
    )
  })
  viewer.set_model(None)
  subscription.dispose()
  assert_true(final_detachment_observed.val)
  assert_true(detachment_saw_disposed_semantic_dom.val)
  assert_true(detachment_saw_removed_hover_widget.val)
  assert_true(detachment_saw_removed_root.val)
  assert_true(detachment_saw_restored_placeholder.val)
  assert_true(markdown.semantic_code_lines().is_empty())
  assert_true(
    overlay.query_selector(".moonbit-viewer-markdown-hover-widget") is None,
  )
  assert_false(@base_browser.element_contains(host, root))
  assert_true(@base_browser.element_contains(host, placeholder.root))
}

///|
test "two mounted Markdown Viewers over one model isolate DOM scroll and lifetime" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let first = Viewer::Viewer()
  let second = Viewer::Viewer()
  let first_model = markdown_presentation_test_model(
    "/first.md", "markdown", "# First",
  )
  let code_model = markdown_presentation_test_model(
    "/code.mbt", "moonbit", "fn main {}",
  )
  defer {
    first.dispose()
    second.dispose()
    code_model.dispose()
  }
  first.attach(@rdom.document().create_element("div"))
  second.attach(@rdom.document().create_element("div"))
  first.set_model(Some(first_model))
  second.set_model(Some(first_model))
  guard (first.current_markdown_document(), second.current_markdown_document())
    is (Some(first_markdown), Some(second_markdown)) else {
    fail("two Markdown viewers were not mounted")
  }
  assert_false(
    markdown_document_test_same_element(
      first_markdown.root(),
      second_markdown.root(),
    ),
  )
  first.set_scroll_top(31.0)
  flush_mounted_test_frames()
  assert_eq(first.get_scroll_top(), 31.0)
  assert_eq(second.get_scroll_top(), 0.0)
  let first_generation = first_markdown.projection_generation()
  let second_generation = second_markdown.projection_generation()
  first.set_value("# First replacement")
  assert_eq(first_markdown.projection_generation(), first_generation + 1)
  assert_eq(second_markdown.projection_generation(), second_generation + 1)
  assert_true(
    markdown_document_test_text(markdown_document_test_article(first_markdown)).contains(
      "First replacement",
    ),
  )
  assert_true(
    markdown_document_test_text(markdown_document_test_article(second_markdown)).contains(
      "First replacement",
    ),
  )

  first.focus()
  assert_true(first.has_text_focus())
  first.set_model(Some(code_model))
  assert_true(first.has_text_focus())
  assert_true(first.current_markdown_document() is None)
  assert_true(first.current_code_browser_data() is Some(_))
  first.set_model(Some(first_model))
  assert_true(first.has_text_focus())
  assert_true(first.current_markdown_document() is Some(_))
  assert_true(second.current_markdown_document() is Some(_))
  first.dispose()
  first.dispose()
  assert_true(second.current_markdown_document() is Some(_))
  first_model.dispose()
  assert_true(second.get_model() is None)
  assert_true(second.current_markdown_document() is None)
}
