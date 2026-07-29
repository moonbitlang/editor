///|
/// One source-bearing DOM line from the current same-parse Markdown
/// projection. The stable block/line indices are presentation identities;
/// `code_line` retains the exact UTF-16 boundary map back into the original
/// model snapshot.
pub(all) struct MarkdownSemanticCodeLineDom {
  block_index : Int
  block_source_range : @base_common.OffsetRange
  line_index : Int
  code_line : @markdown_core.MarkdownCodeLine
  element : @rdom.Element
}

///|
/// Everything attached to one installed article generation. It is retired
/// before `RenderedMarkdown::dispose`, so callbacks cannot observe detached
/// line nodes and a caller can never retain a registry from two parses.
priv struct MarkdownSemanticDomLifetime {
  lines : Array[MarkdownSemanticCodeLineDom]
  listeners : Array[@base_common.Disposable]
  mut disposed : Bool
}

///|
fn MarkdownSemanticDomLifetime::empty() -> MarkdownSemanticDomLifetime {
  { lines: [], listeners: [], disposed: false }
}

///|
fn MarkdownSemanticDomLifetime::dispose(
  self : MarkdownSemanticDomLifetime,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
  self.lines.clear()
}

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
  priv mut semantic_dom : MarkdownSemanticDomLifetime
  priv listeners : Array[@base_common.Disposable]
  priv mut disposed : Bool
}

///|
fn markdown_document_root_class(show_unused : Bool) -> String {
  "moonbit-viewer-markdown-document" +
  (if show_unused { " showUnused" } else { "" })
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
  show_unused? : Bool = true,
) -> MarkdownDocumentView {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", markdown_document_root_class(show_unused))
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
    semantic_dom: MarkdownSemanticDomLifetime::empty(),
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
  let tokenized = if code_block.is_moonbit_check_fence(resource_kind) {
    render_semantic_tokenized_code_lines(code_block, fallback)
  } else {
    fallback
  }
  let body = match code_block.language_id {
    Some("mermaid") =>
      "<div class=\"moonbit-viewer-markdown-diagram\" " +
      "data-diagram-language=\"mermaid\" " +
      "data-mermaid-state=\"fallback\">\n" +
      tokenized +
      "\n</div>\n"
    _ => tokenized
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
/// Wraps exactly the source-bearing projected lines after the whole block has
/// already been tokenized. This preserves the tokenizer's cross-line state
/// while dropping only `_tokenizeToString`'s synthetic final empty segment
/// caused by the code block's mandatory trailing newline.
fn render_semantic_tokenized_code_lines(
  code_block : @markdown_core.MarkdownCodeBlock,
  tokenized : String,
) -> String {
  let prefix = "<div class=\"monaco-tokenized-source\">"
  let suffix = "</div>"
  guard tokenized.has_prefix(prefix) &&
    tokenized.has_suffix(suffix) &&
    tokenized.length() >= prefix.length() + suffix.length() else {
    return tokenized
  }
  let inner = tokenized[prefix.length():tokenized.length() - suffix.length()].to_owned()
  let rendered_lines = split_tokenized_code_lines(inner)
  // `MarkdownCodeBlock::code` ends in one source newline. The shared
  // tokenizer must therefore produce exactly the projected lines plus one
  // final empty segment. Any future renderer-shape drift disables semantic
  // line markup rather than guessing at source coordinates.
  guard rendered_lines.length() == code_block.code_lines.length() + 1 &&
    tokenized_line_segment_is_empty(rendered_lines[rendered_lines.length() - 1]) else {
    return tokenized
  }
  let result = StringBuilder::new()
  result.write_string(prefix)
  for line_index, code_line in code_block.code_lines {
    if line_index > 0 {
      result.write_string("<br/>")
    }
    result.write_string(
      "<span class=\"moonbit-viewer-markdown-code-line\" " +
      "data-markdown-block-index=\"\{code_block.block_index}\" " +
      "data-markdown-code-line=\"\{line_index}\" " +
      "data-markdown-source-line=\"\{code_line.source_line_number}\" " +
      "data-markdown-source-start=\"\{code_line.source_range.start}\" " +
      "data-markdown-source-end=\"\{code_line.source_range.end_exclusive}\">",
    )
    result.write_string(rendered_lines[line_index])
    result.write_string("</span>")
  }
  result.write_string(suffix)
  result.to_string()
}

///|
/// The shared tokenizer represents an empty line as one empty token span, not
/// an empty string. Recognize only that reviewed shape; arbitrary markup is
/// not accepted as the synthetic trailing line.
fn tokenized_line_segment_is_empty(segment : String) -> Bool {
  guard segment.has_prefix("<span class=\"") &&
    segment.find("\">") is Some(content_start) else {
    return false
  }
  segment[content_start + 2:] == "</span>"
}

///|
/// Deterministic split that retains leading, adjacent, and trailing empty
/// lines. Core `String::split` intentionally drops the final empty item, but
/// here that item is the reviewed tokenizer-shape sentinel.
fn split_tokenized_code_lines(inner : String) -> Array[String] {
  let separator = "<br/>"
  let result : Array[String] = []
  let mut start = 0
  while start <= inner.length() {
    let remainder = inner[start:]
    match remainder.find(separator) {
      Some(relative) => {
        result.push(inner[start:start + relative].to_owned())
        start = start + relative + separator.length()
      }
      None => {
        result.push(inner[start:].to_owned())
        break
      }
    }
  }
  result
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
  self.semantic_dom.dispose()
  let semantic_dom = MarkdownSemanticDomLifetime::empty()
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
  for block in self.rendered.projection.code_blocks {
    guard block.is_moonbit_check_fence(self.resource_kind) &&
      self.article.query_selector(
        "[data-markdown-code-block=\"\{block.block_index}\"]",
      )
      is Some(block_element) else {
      continue
    }
    let block_lines : Array[MarkdownSemanticCodeLineDom] = []
    let mut block_is_valid = true
    for line_index, code_line in block.code_lines {
      match
        block_element.query_selector(
          "[data-markdown-code-line=\"\{line_index}\"]",
        ) {
        Some(element) => {
          let dom_text = markdown_semantic_line_text(element)
          if dom_text != code_line.displayed_text ||
            dom_text.length() != code_line.displayed_text.length() {
            block_is_valid = false
          }
          block_lines.push({
            block_index: block.block_index,
            block_source_range: block.block_source_range,
            line_index,
            code_line,
            element,
          })
        }
        None => block_is_valid = false
      }
    }
    if block_is_valid && block_lines.length() == block.code_lines.length() {
      semantic_dom.lines.append(block_lines)
    } else {
      // Keep ordinary tokenized presentation but remove every source-bearing
      // affordance from the mismatched block.
      block_element.remove_attribute("data-markdown-semantic")
      for line in block_lines {
        line.element.remove_attribute("data-markdown-block-index")
        line.element.remove_attribute("data-markdown-code-line")
        line.element.remove_attribute("data-markdown-source-line")
        line.element.remove_attribute("data-markdown-source-start")
        line.element.remove_attribute("data-markdown-source-end")
      }
    }
  }
  self.semantic_dom = semantic_dom
}

///|
extern "js" fn markdown_semantic_line_text(element : @rdom.Element) -> String =
  #| (element) => String(element.textContent || "")

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
  self.semantic_dom.dispose()
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
pub fn MarkdownDocumentView::language_id(self : MarkdownDocumentView) -> String {
  self.language_id
}

///|
/// Mirrors the Code root's `showUnused` option class without rebuilding the
/// current Markdown projection.
pub fn MarkdownDocumentView::apply_marker_unused_visibility(
  self : MarkdownDocumentView,
  show_unused : Bool,
) -> Unit {
  guard !self.disposed else { return }
  self.root.set_attribute("class", markdown_document_root_class(show_unused))
}

///|
/// Hides exactly the root elements at `hidden_element_indexes` and shows every
/// other rendered root element.
///
/// This is a pure visibility operation over already-rendered nodes: it never
/// re-renders, never rebuilds the projection, and never advances
/// `projection_generation`. That is what preserves the `.mbt.md` semantic-fence
/// contract across folding — the hover bridge resolves a caret through retained
/// per-line boundary maps plus a DOM descendant check, both of which survive a
/// visibility change untouched.
///
/// `display:none` is required rather than `visibility:hidden` or a zero height:
/// only `display:none` removes the subtree from hit testing, so
/// `caretPositionFromPoint` cannot return a node inside hidden content and the
/// bridge's descendant check fails closed. A hidden-but-hit-testable element
/// would produce hovers on text the reader cannot see.
///
/// The view owns no fold policy. Which sections are collapsed, and how that
/// survives a source or theme replacement, belongs to the root Viewer; a
/// replacement resets every element to visible and the root re-applies.
/// Out-of-range indexes are ignored so a stale caller cannot abort a render.
pub fn MarkdownDocumentView::set_hidden_root_elements(
  self : MarkdownDocumentView,
  hidden_element_indexes : Array[Int],
) -> Unit {
  guard !self.disposed else { return }
  let children = self.article.get_children()
  let hidden : Set[Int] = Set([])
  for index in hidden_element_indexes {
    if index >= 0 && index < children.length() {
      hidden.add(index)
    }
  }
  for index, child in children {
    if hidden.contains(index) {
      child.set_attribute("style", markdown_hidden_element_style)
      child.set_attribute("aria-hidden", "true")
    } else {
      child.remove_attribute("style")
      child.remove_attribute("aria-hidden")
    }
  }
}

///|
/// The root-element ordinals currently hidden, in document order. Read back for
/// tests and for the root Viewer's reconciliation.
pub fn MarkdownDocumentView::hidden_root_elements(
  self : MarkdownDocumentView,
) -> Array[Int] {
  let result = []
  guard !self.disposed else { return result }
  for index, child in self.article.get_children() {
    if child.get_attribute("style") is Some(style) &&
      style == markdown_hidden_element_style {
      result.push(index)
    }
  }
  result
}

///|
/// Collapsed body elements are removed from layout *and* from the
/// accessibility tree; a collapsed section must not be reachable by a screen
/// reader any more than by the pointer.
let markdown_hidden_element_style : String = "display:none"

///|
/// Snapshot of the current replacement-scoped line registry. The returned
/// array may be reordered by a caller without mutating the view's registry.
pub fn MarkdownDocumentView::semantic_code_lines(
  self : MarkdownDocumentView,
) -> Array[MarkdownSemanticCodeLineDom] {
  self.semantic_dom.lines.copy()
}

///|
/// Installs a delegated semantic-surface listener into the current article
/// generation. Root-owned bridges call this again after a source/theme
/// replacement; the old listener is always removed before old rendered
/// Markdown resources are released.
pub fn MarkdownDocumentView::listen_semantic_dom(
  self : MarkdownDocumentView,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  guard !self.disposed &&
    !self.semantic_dom.disposed &&
    self.semantic_dom.lines.length() > 0 else {
    return
  }
  self.article.add_event_listener(event_name, listener)
  self.semantic_dom.listeners.push(
    @base_common.Disposable::from(() => {
      self.article.remove_event_listener(event_name, listener)
    }),
  )
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
  self.semantic_dom.dispose()
  self.rendered.dispose.dispose()
}
