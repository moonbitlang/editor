// Whole-line Markdown-comment contribution. Detection/normalization stays in
// the multi-target contribution package; this root file owns the Viewer-lived
// registry entry, model-scoped ViewZones/hidden source, and reconciliation
// ordering across browser/common tiers.

///|
let markdown_comment_contribution_id : String = "editor.contrib.markdownComments"

///|
let markdown_comment_hidden_source : String = "markdown-comments"

///|
priv struct MarkdownCommentContributionState {
  mut generation : Int
  rendered : Map[String, RenderedMarkdownComment]
  listeners : Array[@base_common.Disposable]
  mut viewport_observer : @markdown_comments_browser.MarkdownCommentViewportObserver?
  mut geometry_lease : @base_common.Disposable?
}

///|
fn MarkdownCommentContributionState::MarkdownCommentContributionState() -> MarkdownCommentContributionState {
  {
    generation: 0,
    rendered: Map([]),
    listeners: [],
    viewport_observer: None,
    geometry_lease: None,
  }
}

///|
priv struct RenderedMarkdownComment {
  mut block : @language.MarkdownCommentBlock
  mut foldable : Bool
  dom : @markdown_comments_browser.MarkdownCommentDom
  zone : @editor_browser.ViewZone
  zone_id : String
  mut rendered_markdown : @browser_markdown.RenderedMarkdown
  mut preview_rendered_markdown : @browser_markdown.RenderedMarkdown?
  mut fold_lifetime : @base_common.Disposable?
  fold_expanded : Ref[Bool]
  mut diagram_viewports : @markdown_comments_browser.MarkdownCommentDiagramViewports
  size_observer : @markdown_comments_browser.MarkdownCommentSizeObserver
  mut measured_height : Double
  generation : Ref[Int]
}

///|
fn RenderedMarkdownComment::dispose_body_resources(
  self : RenderedMarkdownComment,
) -> Unit {
  match self.fold_lifetime {
    Some(lifetime) => lifetime.dispose()
    None => ()
  }
  self.fold_lifetime = None
  self.diagram_viewports.dispose()
  self.rendered_markdown.dispose.dispose()
  match self.preview_rendered_markdown {
    Some(preview) => preview.dispose.dispose()
    None => ()
  }
  self.preview_rendered_markdown = None
}

///|
fn RenderedMarkdownComment::dispose_render_resources(
  self : RenderedMarkdownComment,
) -> Unit {
  self.dispose_body_resources()
  self.size_observer.dispose()
}

///|
fn MarkdownCommentContributionState::ensure_geometry_lease(
  self : MarkdownCommentContributionState,
  view_lines : @view.ViewLines,
) -> Unit {
  if self.geometry_lease is None {
    self.geometry_lease = Some(view_lines.acquire_content_viewport_geometry())
  }
}

///|
fn MarkdownCommentContributionState::dispose_geometry_lease(
  self : MarkdownCommentContributionState,
) -> Unit {
  match self.geometry_lease {
    Some(lease) => lease.dispose()
    None => ()
  }
  self.geometry_lease = None
}

///|
fn MarkdownCommentContributionState::request_all_measures(
  self : MarkdownCommentContributionState,
) -> Unit {
  for _, entry in self.rendered {
    entry.size_observer.request_measure()
  }
}

///|
fn MarkdownCommentContributionState::ensure_viewport_observer(
  self : MarkdownCommentContributionState,
  dom : @markdown_comments_browser.MarkdownCommentDom,
) -> Unit {
  if self.viewport_observer is None {
    self.viewport_observer = Some(
      dom.observe_viewport_width(() => self.request_all_measures()),
    )
  }
}

///|
fn MarkdownCommentContributionState::dispose_viewport_observer(
  self : MarkdownCommentContributionState,
) -> Unit {
  match self.viewport_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  self.viewport_observer = None
}

///|
fn register_markdown_comment_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    markdown_comment_contribution_id,
    AfterFirstRender,
    _viewer => MarkdownComments(MarkdownCommentContributionState()),
    viewer => {
      guard viewer.markdown_comment_contribution() is Some(state) else {
        abort("Markdown-comment contribution variant mismatch")
      }
      state.listeners.push(
        viewer.on_did_change_model(_ => {
          viewer.refresh_markdown_comments(force_update=false)
        }),
      )
      state.listeners.push(
        viewer.on_did_change_model_content(_ => {
          // `set_value` rebuilt the projected line collection even when the
          // normalized block ranges stayed equal.
          viewer.refresh_markdown_comments(force_update=true)
        }),
      )
      viewer.refresh_markdown_comments(force_update=false)
      []
    },
  )
}

///|
fn Viewer::markdown_comment_contribution(
  self : Viewer,
) -> MarkdownCommentContributionState? {
  match self.contributions.lookup(markdown_comment_contribution_id) {
    Some(entry) =>
      match entry.instance {
        MarkdownComments(state) => Some(state)
        _ => None
      }
    None => None
  }
}

///|
fn markdown_comment_key(block : @language.MarkdownCommentBlock) -> String {
  let range = block.line_range
  range.start_line_number.to_string() +
  ":" +
  range.end_line_number_exclusive.to_string()
}

///|
fn markdown_comment_hidden_ranges(
  blocks : Array[@language.MarkdownCommentBlock],
) -> Array[@base_common.Range] {
  blocks.map(block => {
    let range = block.line_range
    Range(range.start_line_number, 1, range.end_line_number_exclusive - 1, 1)
  })
}

///|
fn markdown_comment_mermaid_theme(
  viewer_theme : String,
) -> @browser_markdown.MermaidTheme {
  if viewer_theme == "light" {
    Light
  } else {
    Dark
  }
}

///|
fn render_markdown_comment_code_block(
  code_block : @markdown_core.MarkdownCodeBlock,
  active_language_id : String?,
) -> String {
  let fallback = @markdown_core.render_tokenized_code_block(
    code_block, active_language_id,
  )
  match code_block.language_id {
    Some("mermaid") =>
      "<div class=\"moonbit-viewer-markdown-diagram\" " +
      "data-diagram-language=\"mermaid\" " +
      "data-mermaid-state=\"fallback\">\n" +
      fallback +
      "\n</div>\n"
    _ => fallback
  }
}

///|
fn render_markdown_comment_body(
  model : @model.TextModel,
  markdown : String,
  target : @rdom.Element,
  on_size_changed : () -> Unit,
  mermaid_theme : @browser_markdown.MermaidTheme,
) -> @browser_markdown.RenderedMarkdown {
  @browser_markdown.render_markdown(
    markdown,
    options=MarkdownRenderOptions(
      language_id=model.get_language_id(),
      base_uri=model.uri,
      action_handler=open_markdown_comment_link,
      code_block_renderer=render_markdown_comment_code_block,
      on_size_changed~,
      allow_remote_images=true,
      mermaid_theme~,
    ),
    target~,
  )
}

///|
/// Selects the first non-empty Markdown source line as the collapsed preview
/// only for an item-delimited API document with meaningful content after it.
/// The leading exact thematic break remains visible in both presentations;
/// ordinary whole-line Markdown keeps its historical always-expanded surface.
fn markdown_comment_folded_preview(
  markdown : String,
  foldable : Bool,
) -> String? {
  if !foldable {
    return None
  }
  let normalized = markdown
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let has_leading_separator = normalized == "---" ||
    normalized.has_prefix("---\n")
  if !has_leading_separator {
    return None
  }
  let mut first_line = true
  let mut preview_line : String? = None
  let mut has_more = false
  for line_view in normalized.split("\n") {
    let line = line_view.to_owned()
    if first_line {
      first_line = false
      if line == "---" {
        continue
      }
    }
    if line.trim().is_empty() {
      continue
    }
    match preview_line {
      None => preview_line = Some(line)
      Some(_) => {
        has_more = true
        break
      }
    }
  }
  guard has_more && preview_line is Some(preview) else { return None }
  let trimmed_preview = preview.trim()
  // A fence opener is not a self-contained Markdown preview and cmark expects
  // the closing delimiter. Keep diagram/code-first documentation expanded
  // instead of synthesizing or truncating its source semantics.
  if trimmed_preview.has_prefix("```") || trimmed_preview.has_prefix("~~~") {
    return None
  }
  Some("---\n\n" + preview)
}

///|
/// Builds the complete and optional one-line Markdown lifetimes before
/// mounting diagram controls. The visibility toggle invalidates only the
/// existing coalesced size observer; ViewZone height still has one writer.
fn render_markdown_comment_presentations(
  model : @model.TextModel,
  markdown : String,
  foldable : Bool,
  dom : @markdown_comments_browser.MarkdownCommentDom,
  fold_expanded : Ref[Bool],
  size_observer : @markdown_comments_browser.MarkdownCommentSizeObserver,
  mermaid_theme : @browser_markdown.MermaidTheme,
) -> (
  @browser_markdown.RenderedMarkdown,
  @browser_markdown.RenderedMarkdown?,
  @base_common.Disposable?,
  @markdown_comments_browser.MarkdownCommentDiagramViewports,
) {
  let on_size_changed = () => size_observer.request_measure()
  let rendered_markdown = render_markdown_comment_body(
    model,
    markdown,
    dom.full,
    on_size_changed,
    mermaid_theme,
  )
  let (preview_rendered_markdown, fold_lifetime) = match
    markdown_comment_folded_preview(markdown, foldable) {
    Some(preview_markdown) => {
      let preview = render_markdown_comment_body(
        model,
        preview_markdown,
        dom.preview,
        on_size_changed,
        mermaid_theme,
      )
      let lifetime = dom.enable_folding(fold_expanded, on_size_changed)
      (Some(preview), Some(lifetime))
    }
    None => {
      dom.disable_folding()
      (None, None)
    }
  }
  let diagram_viewports = @markdown_comments_browser.MarkdownCommentDiagramViewports(
    rendered_markdown.element,
    on_size_changed,
  )
  (
    rendered_markdown, preview_rendered_markdown, fold_lifetime, diagram_viewports,
  )
}

///|
extern "js" fn open_markdown_comment_link(uri : String) -> Unit =
  #| uri => {
  #|   const opened = globalThis.open?.(uri, "_blank", "noopener,noreferrer");
  #|   if (opened) opened.opener = null;
  #| }

///|
/// Reconciles the current model's normalized Markdown blocks with the
/// model-scoped rendered-zone map. Provider execution and ViewZone publication
/// are both reentrant boundaries, so a generation check separates every
/// external phase from the next state mutation.
///
/// ```mermaid
/// sequenceDiagram
///   participant V as Viewer
///   participant P as provider or detector
///   participant R as stable-key reconciler
///   participant Z as ViewZones
///   participant H as hidden-area projection
///   V->>V: increment generation
///   V->>P: resolve normalized blocks
///   Note over V,P: provider may synchronously mutate or replace the model
///   P-->>V: blocks
///   V->>V: verify model and generation
///   V->>R: reconcile by half-open source range
///   R->>Z: dispose removals, update bodies, add zones
///   Z-->>V: publish synchronous zone changes
///   V->>V: verify model and generation again
///   V->>H: replace the markdown-comments source ranges
///   V->>V: schedule render
/// ```
///
/// ```d2
/// direction: right
///
/// source: model source
/// blocks: normalized blocks
/// zones: measured zones
/// hidden: hidden ranges
/// projection: projection
/// browser: browser view
/// copy: selection and copy
///
/// source -> blocks: provider
/// blocks -> zones: Markdown body
/// blocks -> hidden: owned lines
/// zones -> projection: geometry
/// hidden -> projection: hide source
/// projection -> browser
/// source -> copy: model coordinates
/// ```
fn Viewer::refresh_markdown_comments(
  self : Viewer,
  force_update~ : Bool,
) -> Unit {
  guard !self.disposed else { return }
  guard self.markdown_comment_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  // A headless Viewer has no replacement DOM and must keep source visible.
  guard self.current_code_browser_data() is Some(browser) else { return }
  let mermaid_theme = markdown_comment_mermaid_theme(
    self.configuration.snapshot().options.theme,
  )
  // Reserve this generation before invoking an open provider. Provider code
  // can synchronously mutate or replace the model through an external owner;
  // any nested refresh then invalidates this attempt before it mutates zones.
  state.generation += 1
  let generation = state.generation
  let resolved = @markdown_comments.resolve_markdown_comment_blocks_with_presentation(
    model,
    self.services.languages,
    self.services.log_service,
  )
  let blocks = resolved.blocks
  let foldable = resolved.foldable
  guard self.markdown_comment_refresh_is_current(state, model, generation) else {
    return
  }
  if !blocks.is_empty() {
    state.ensure_geometry_lease(browser.view.view_lines)
  } else {
    // With no surviving consumer, stop width invalidations before disposing
    // the per-comment observers and removing their zones below.
    state.dispose_viewport_observer()
  }
  let next : Map[String, @language.MarkdownCommentBlock] = Map([])
  for block in blocks {
    next.set(markdown_comment_key(block), block)
  }
  // A single block spanning the model (an opened Markdown document) gets the
  // bounded reading-measure presentation; documentation zones keep the full
  // content width.
  let document_presentation = blocks is [only] &&
    only.line_range.start_line_number == 1 &&
    only.line_range.end_line_number_exclusive >= model.get_line_count()
  let old_keys : Array[String] = []
  for key, _ in state.rendered {
    old_keys.push(key)
  }
  self.change_view_zones(accessor => {
    // Renderer and observer lifetimes end before their caller-owned zone DOM
    // leaves the retained ViewZones registry.
    for key in old_keys {
      if !next.contains(key) {
        let removed = state.rendered[key]
        removed.dispose_render_resources()
        accessor.remove_zone(removed.zone_id)
        state.rendered.remove(key)
      }
    }
    for block in blocks {
      let key = markdown_comment_key(block)
      match state.rendered.get(key) {
        Some(existing) => {
          existing.generation.val = generation
          if existing.block.markdown != block.markdown ||
            existing.foldable != foldable {
            existing.dispose_body_resources()
            let (
              rendered_markdown,
              preview_rendered_markdown,
              fold_lifetime,
              diagram_viewports,
            ) = render_markdown_comment_presentations(
              model,
              block.markdown,
              foldable,
              existing.dom,
              existing.fold_expanded,
              existing.size_observer,
              mermaid_theme,
            )
            existing.rendered_markdown = rendered_markdown
            existing.preview_rendered_markdown = preview_rendered_markdown
            existing.fold_lifetime = fold_lifetime
            existing.diagram_viewports = diagram_viewports
            existing.size_observer.request_measure()
          }
          existing.block = block
          existing.foldable = foldable
          existing.dom.set_document_presentation(document_presentation)
        }
        None => {
          let dom = @markdown_comments_browser.MarkdownCommentDom(
            block.line_range.start_line_number,
            block.line_range.end_line_number_exclusive,
          )
          // Keep the gutter chevron on the code-folding column: the rendered
          // lane is the configured `lineDecorationsWidth` plus the folding
          // control reserve, and other contributions (e.g. agent feedback)
          // may have widened it before this zone mounted.
          dom.set_margin_fold_lane_width(
            self.configuration.snapshot().layout_decorations_width().to_int(),
          )
          let zone = @editor_browser.ViewZone(
            block.line_range.end_line_number_exclusive - 1,
            dom.outer,
            margin_dom_node=dom.margin,
            ignore_hidden_area_source=markdown_comment_hidden_source,
            suppress_mouse_down=false,
            height_in_lines=1.0,
          )
          let zone_id = accessor.add_zone(zone)
          dom.expose_accessible_content()
          dom.set_document_presentation(document_presentation)
          // `add_zone` writes the ordinary scroll-plane `width: 100%`.
          // Replace it before any observer or renderer can measure the node.
          dom.pin_to_content_viewport()
          let entry_generation = Ref(generation)
          let size_observer = dom.observe_size(height => {
            self.apply_markdown_comment_height(
              state, key, zone_id, entry_generation, height,
            )
          })
          let fold_expanded = Ref(false)
          let (
            rendered_markdown,
            preview_rendered_markdown,
            fold_lifetime,
            diagram_viewports,
          ) = render_markdown_comment_presentations(
            model,
            block.markdown,
            foldable,
            dom,
            fold_expanded,
            size_observer,
            mermaid_theme,
          )
          let entry : RenderedMarkdownComment = {
            block,
            foldable,
            dom,
            zone,
            zone_id,
            rendered_markdown,
            preview_rendered_markdown,
            fold_lifetime,
            fold_expanded,
            diagram_viewports,
            size_observer,
            measured_height: 0.0,
            generation: entry_generation,
          }
          state.rendered.set(key, entry)
          state.ensure_viewport_observer(dom)
          size_observer.request_measure()
        }
      }
    }
  })
  // `change_view_zones` publishes synchronously. A listener may flush, swap,
  // detach, or dispose the model, and that nested transition owns the newer
  // generation/source. Never let this older refresh overwrite its ranges.
  guard self.markdown_comment_refresh_is_current(state, model, generation) else {
    return
  }
  if state.rendered.is_empty() {
    // The last geometry consumer is gone only after ViewZones detached its
    // caller-owned nodes.
    state.dispose_geometry_lease()
  }
  self.set_hidden_areas(
    markdown_comment_hidden_ranges(blocks),
    source=markdown_comment_hidden_source,
    force_update~,
  )
  self.schedule_render()
}

///|
fn Viewer::markdown_comments_on_theme_changed(
  self : Viewer,
  viewer_theme : String,
) -> Unit {
  guard self.markdown_comment_contribution() is Some(state) else { return }
  let mermaid_theme = markdown_comment_mermaid_theme(viewer_theme)
  for _, entry in state.rendered {
    entry.rendered_markdown.rerender_mermaid(mermaid_theme)
    match entry.preview_rendered_markdown {
      Some(preview) => preview.rerender_mermaid(mermaid_theme)
      None => ()
    }
  }
}

///|
fn Viewer::markdown_comment_refresh_is_current(
  self : Viewer,
  state : MarkdownCommentContributionState,
  model : @model.TextModel,
  generation : Int,
) -> Bool {
  if self.disposed || state.generation != generation {
    return false
  }
  match self.get_model() {
    Some(current_model) => current_model.same(model)
    None => false
  }
}

///|
fn Viewer::apply_markdown_comment_height(
  self : Viewer,
  state : MarkdownCommentContributionState,
  key : String,
  expected_zone_id : String,
  entry_generation : Ref[Int],
  height : Int,
) -> Unit {
  guard !self.disposed else { return }
  guard entry_generation.val == state.generation else { return }
  guard state.rendered.get(key) is Some(entry) else { return }
  guard entry.zone_id == expected_zone_id else { return }
  let measured = height.to_double()
  if measured <= 0.0 || measured == entry.measured_height {
    return
  }
  entry.measured_height = measured
  entry.zone.height_in_px = Some(measured)
  self.change_view_zones(accessor => accessor.layout_zone(expected_zone_id))
}

///|
fn Viewer::clear_markdown_comment_model_state(self : Viewer) -> Unit {
  guard self.markdown_comment_contribution() is Some(state) else { return }
  state.generation += 1
  // Stop model-wide invalidation first. Per-comment content/renderer
  // lifetimes follow, then structural zones, and finally ViewLines geometry.
  state.dispose_viewport_observer()
  let entries : Array[RenderedMarkdownComment] = []
  for _, entry in state.rendered {
    entries.push(entry)
  }
  // Dispose before structural removal so late image/ResizeObserver callbacks
  // cannot reach a zone while the outgoing View is being torn down.
  for entry in entries {
    entry.dispose_render_resources()
  }
  match self.current_code_browser_data() {
    Some(browser) =>
      browser.view.change_view_zones(accessor => {
        for entry in entries {
          accessor.remove_zone(entry.zone_id)
        }
      })
    None => ()
  }
  state.rendered.clear()
  state.dispose_geometry_lease()
  self.set_hidden_areas([], source=markdown_comment_hidden_source)
}

///|
fn MarkdownCommentContributionState::dispose(
  self : MarkdownCommentContributionState,
  viewer : Viewer,
) -> Unit {
  viewer.clear_markdown_comment_model_state()
  for listener in self.listeners {
    listener.dispose()
  }
  self.listeners.clear()
}
