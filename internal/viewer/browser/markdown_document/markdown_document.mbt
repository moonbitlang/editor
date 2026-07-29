///|
/// One JS-only readonly Markdown surface. The source model stays owned by the
/// root Viewer; this value owns only presentation DOM, the retained same-parse
/// projection, and listeners whose lifetime is one model attachment.
pub struct MarkdownDocumentView {
  priv root : @rdom.Element
  priv viewport : @rdom.Element
  priv article : @rdom.Element
  priv overlay_mount : @rdom.Element
  priv resource_kind : @markdown_core.MarkdownResourceKind
  priv language_id : String
  priv base_uri : @base_common.Uri
  priv on_size_changed : () -> Unit
  priv mut source : String
  priv mut source_model_version : Int
  priv mut theme : String
  priv mut projection_generation : Int
  priv mut rendered : @browser_markdown.RenderedMarkdown
  priv listeners : Array[@base_common.Disposable]
  priv mut disposed : Bool
}

///|
pub fn MarkdownDocumentView::MarkdownDocumentView(
  source : String,
  source_model_version : Int,
  language_id : String,
  base_uri : @base_common.Uri,
  resource_kind : @markdown_core.MarkdownResourceKind,
  theme : String,
  on_scroll : () -> Unit,
  on_focus_changed : (Bool) -> Unit,
  on_size_changed : () -> Unit,
) -> MarkdownDocumentView {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-viewer-markdown-document")
  root.set_attribute("aria-label", "Readonly Markdown viewer")
  root.set_attribute("tabindex", "0")
  root.set_attribute("data-theme", theme)
  root.set_attribute("data-uri", base_uri.to_string())
  root.set_attribute("data-source-uri", base_uri.to_string())
  let viewport = document.create_element("div")
  viewport.set_attribute("class", "moonbit-viewer-markdown-document-viewport")
  let article = document.create_element("article")
  article.set_attribute("class", "moonbit-viewer-markdown-document-article")
  let overlay_mount = document.create_element("div")
  overlay_mount.set_attribute(
    "class", "moonbit-viewer-markdown-document-overlays",
  )
  viewport.append_child(article.as_node())
  root.append_child(viewport.as_node())
  root.append_child(overlay_mount.as_node())
  let rendered = render_markdown_document(
    source, language_id, base_uri, resource_kind, theme, article, on_size_changed,
  )
  let view : MarkdownDocumentView = {
    root,
    viewport,
    article,
    overlay_mount,
    resource_kind,
    language_id,
    base_uri,
    on_size_changed,
    source,
    source_model_version,
    theme,
    projection_generation: 1,
    rendered,
    listeners: [],
    disposed: false,
  }
  view.post_render()
  view.listen(viewport, "scroll", _event => if !view.disposed { on_scroll() })
  view.listen(root, "focus", _event => {
    if !view.disposed {
      on_focus_changed(true)
    }
  })
  view.listen(root, "blur", _event => {
    if !view.disposed {
      on_focus_changed(false)
    }
  })
  view
}

///|
fn render_markdown_document(
  source : String,
  language_id : String,
  base_uri : @base_common.Uri,
  resource_kind : @markdown_core.MarkdownResourceKind,
  theme : String,
  article : @rdom.Element,
  on_size_changed : () -> Unit,
) -> @browser_markdown.RenderedMarkdown {
  @browser_markdown.render_markdown(
    source,
    options=MarkdownRenderOptions(
      language_id~,
      base_uri~,
      action_handler=@browser_markdown.open_external_link,
      code_block_renderer=(code_block, active_language_id) => {
        render_markdown_document_code_block(
          code_block, active_language_id, resource_kind,
        )
      },
      on_size_changed~,
      allow_remote_images=true,
      mermaid_theme=markdown_document_mermaid_theme(theme),
    ),
    target=article,
  )
}

///|
fn render_markdown_document_code_block(
  code_block : @markdown_core.MarkdownCodeBlock,
  active_language_id : String?,
  resource_kind : @markdown_core.MarkdownResourceKind,
) -> String {
  let fallback = @markdown_core.render_tokenized_code_block(
    code_block, active_language_id,
  )
  let body = match code_block.language_id {
    Some("mermaid") =>
      "<div class=\"moonbit-viewer-markdown-diagram\" " +
      "data-diagram-language=\"mermaid\" " +
      "data-mermaid-state=\"fallback\">\n" +
      fallback +
      "\n</div>\n"
    _ => fallback
  }
  let semantic_attribute = if code_block.is_moonbit_check_fence(resource_kind) {
    " data-markdown-semantic=\"moonbit-check\""
  } else {
    ""
  }
  "<div class=\"moonbit-viewer-markdown-code-block\" " +
  "data-markdown-code-block=\"\{code_block.block_index}\"" +
  semantic_attribute +
  ">\n" +
  body +
  "</div>\n"
}

///|
fn markdown_document_mermaid_theme(
  theme : String,
) -> @browser_markdown.MermaidTheme {
  if theme == "light" {
    Light
  } else {
    Dark
  }
}

///|
fn MarkdownDocumentView::listen(
  self : MarkdownDocumentView,
  target : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_name, listener)
    }),
  )
}

///|
/// The sole post-render choke point. It rebuilds DOM/source associations after
/// every article replacement; later semantic listeners and registries attach
/// here without creating a second parse or a parallel replacement path.
fn MarkdownDocumentView::post_render(self : MarkdownDocumentView) -> Unit {
  let children = self.article.get_children()
  for anchor in self.rendered.projection.block_anchors {
    guard anchor.rendered_element_index is Some(element_index) &&
      element_index >= 0 &&
      element_index < children.length() else {
      continue
    }
    let element = children[element_index]
    element.set_attribute(
      "data-markdown-block-anchor",
      anchor.index.to_string(),
    )
    element.set_attribute(
      "data-markdown-source-start",
      anchor.source_range.start.to_string(),
    )
    element.set_attribute(
      "data-markdown-source-end",
      anchor.source_range.end_exclusive.to_string(),
    )
  }
  self.root.set_attribute(
    "data-markdown-projection-generation",
    self.projection_generation.to_string(),
  )
  self.root.set_attribute(
    "data-markdown-source-version",
    self.source_model_version.to_string(),
  )
}

///|
/// Replaces the article from one source snapshot. The root, viewport, and
/// overlay mount survive. The returned projection and installed HTML always
/// come from the same parse.
pub fn MarkdownDocumentView::replace_source(
  self : MarkdownDocumentView,
  source : String,
  source_model_version : Int,
) -> Unit {
  guard !self.disposed else { return }
  self.rendered.dispose.dispose()
  self.source = source
  self.source_model_version = source_model_version
  self.projection_generation += 1
  self.rendered = render_markdown_document(
    source,
    self.language_id,
    self.base_uri,
    self.resource_kind,
    self.theme,
    self.article,
    self.on_size_changed,
  )
  self.post_render()
  (self.on_size_changed)()
}

///|
/// Theme refresh is a projection replacement, matching source-editor
/// highlighter refresh semantics. Scroll and overlay DOM survive.
pub fn MarkdownDocumentView::apply_theme(
  self : MarkdownDocumentView,
  theme : String,
) -> Unit {
  guard !self.disposed else { return }
  self.theme = theme
  self.root.set_attribute("data-theme", theme)
  self.replace_source(self.source, self.source_model_version)
}

///|
pub fn MarkdownDocumentView::root(self : MarkdownDocumentView) -> @rdom.Element {
  self.root
}

///|
pub fn MarkdownDocumentView::viewport(
  self : MarkdownDocumentView,
) -> @rdom.Element {
  self.viewport
}

///|
pub fn MarkdownDocumentView::article(
  self : MarkdownDocumentView,
) -> @rdom.Element {
  self.article
}

///|
pub fn MarkdownDocumentView::overlay_mount(
  self : MarkdownDocumentView,
) -> @rdom.Element {
  self.overlay_mount
}

///|
pub fn MarkdownDocumentView::projection(
  self : MarkdownDocumentView,
) -> @markdown_core.MarkdownDocumentProjection {
  self.rendered.projection
}

///|
pub fn MarkdownDocumentView::projection_generation(
  self : MarkdownDocumentView,
) -> Int {
  self.projection_generation
}

///|
pub fn MarkdownDocumentView::source_model_version(
  self : MarkdownDocumentView,
) -> Int {
  self.source_model_version
}

///|
pub fn MarkdownDocumentView::resource_kind(
  self : MarkdownDocumentView,
) -> @markdown_core.MarkdownResourceKind {
  self.resource_kind
}

///|
pub fn MarkdownDocumentView::layout(
  self : MarkdownDocumentView,
  width : Double,
  height : Double,
) -> Unit {
  guard !self.disposed else { return }
  @base_browser.set_style_property(self.root, "width", "\{width}px")
  @base_browser.set_style_property(self.root, "height", "\{height}px")
}

///|
pub fn MarkdownDocumentView::scroll_top(self : MarkdownDocumentView) -> Double {
  self.viewport.get_scroll_top()
}

///|
pub fn MarkdownDocumentView::scroll_left(self : MarkdownDocumentView) -> Double {
  self.viewport.get_scroll_left()
}

///|
pub fn MarkdownDocumentView::set_scroll_position(
  self : MarkdownDocumentView,
  scroll_top? : Double,
  scroll_left? : Double,
) -> Unit {
  guard !self.disposed else { return }
  match scroll_top {
    Some(value) => self.viewport.set_scroll_top(value)
    None => ()
  }
  match scroll_left {
    Some(value) => self.viewport.set_scroll_left(value)
    None => ()
  }
}

///|
pub fn MarkdownDocumentView::content_width(
  self : MarkdownDocumentView,
) -> Double {
  self.article.get_scroll_width()
}

///|
pub fn MarkdownDocumentView::content_height(
  self : MarkdownDocumentView,
) -> Double {
  self.article.get_scroll_height()
}

///|
pub fn MarkdownDocumentView::scroll_width(
  self : MarkdownDocumentView,
) -> Double {
  self.viewport.get_scroll_width()
}

///|
pub fn MarkdownDocumentView::scroll_height(
  self : MarkdownDocumentView,
) -> Double {
  self.viewport.get_scroll_height()
}

///|
fn MarkdownDocumentView::element_for_source_offset(
  self : MarkdownDocumentView,
  source_offset : Int,
) -> @rdom.Element? {
  for block in self.rendered.projection.code_blocks {
    if block.block_source_range.contains(source_offset) ||
      source_offset == block.block_source_range.end_exclusive {
      match
        self.article.query_selector(
          "[data-markdown-code-block=\"\{block.block_index}\"]",
        ) {
        Some(element) => return Some(element)
        None => ()
      }
    }
  }
  let children = self.article.get_children()
  for anchor in self.rendered.projection.block_anchors {
    if !(anchor.source_range.contains(source_offset) ||
      source_offset == anchor.source_range.end_exclusive) {
      continue
    }
    match anchor.rendered_element_index {
      Some(index) if index >= 0 && index < children.length() =>
        return Some(children[index])
      _ => ()
    }
  }
  let mut nearest_before : @rdom.Element? = None
  let mut first_mapped : @rdom.Element? = None
  for anchor in self.rendered.projection.block_anchors {
    guard anchor.rendered_element_index is Some(index) &&
      index >= 0 &&
      index < children.length() else {
      continue
    }
    let element = children[index]
    if first_mapped is None {
      first_mapped = Some(element)
    }
    if anchor.source_range.start <= source_offset {
      nearest_before = Some(element)
    } else {
      break
    }
  }
  match nearest_before {
    Some(element) => Some(element)
    None => first_mapped
  }
}

///|
/// Reveals the nearest retained source anchor. Horizontal source columns do
/// not synthesize code-editor scrolling; browser layout owns the native block.
pub fn MarkdownDocumentView::reveal_source_offset(
  self : MarkdownDocumentView,
  source_offset : Int,
  vertical_alignment : String,
) -> Unit {
  guard !self.disposed &&
    self.element_for_source_offset(source_offset) is Some(element) else {
    return
  }
  element.scroll_into_view_with_options(
    behavior="auto",
    block=vertical_alignment,
    inline="nearest",
  )
}

///|
/// Original-source anchors whose rendered root intersects the viewport.
pub fn MarkdownDocumentView::visible_source_ranges(
  self : MarkdownDocumentView,
) -> Array[@base_common.OffsetRange] {
  guard !self.disposed else { return [] }
  let viewport_rect = self.viewport.get_bounding_client_rect()
  let viewport_top = viewport_rect.get_top()
  let viewport_bottom = viewport_rect.get_bottom()
  let children = self.article.get_children()
  let result : Array[@base_common.OffsetRange] = []
  for anchor in self.rendered.projection.block_anchors {
    guard anchor.rendered_element_index is Some(index) &&
      index >= 0 &&
      index < children.length() else {
      continue
    }
    let rect = children[index].get_bounding_client_rect()
    if rect.get_bottom() > viewport_top && rect.get_top() < viewport_bottom {
      result.push(anchor.source_range)
    }
  }
  result
}

///|
pub fn MarkdownDocumentView::has_rendered_source_anchors(
  self : MarkdownDocumentView,
) -> Bool {
  let child_count = self.article.get_children().length()
  self.rendered.projection.block_anchors.any(anchor => {
    match anchor.rendered_element_index {
      Some(index) => index >= 0 && index < child_count
      None => false
    }
  })
}

///|
pub fn MarkdownDocumentView::dispose(self : MarkdownDocumentView) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.projection_generation += 1
  while self.listeners.length() > 0 {
    let listener = self.listeners.remove(self.listeners.length() - 1)
    listener.dispose()
  }
  self.rendered.dispose.dispose()
}
