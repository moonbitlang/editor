///|
/// The stable DOM pair retained by one whole-line Markdown-comment ViewZone.
/// `outer` is the caller-owned ViewZone node; `content` is both the shared
/// Markdown renderer target and the auto-height ResizeObserver target.
pub(all) struct MarkdownCommentDom {
  outer : @rdom.Element
  content : @rdom.Element
}

///|
/// Creates the required outer/content shape for one normalized half-open line
/// range. Projection and ViewZone registration remain root responsibilities.
#alias(new, deprecated)
pub fn MarkdownCommentDom::MarkdownCommentDom(
  start_line_number : Int,
  end_line_number_exclusive : Int,
) -> MarkdownCommentDom {
  let document = @rdom.document()
  let outer = document.create_element("div")
  outer.set_attribute("class", "moonbit-viewer-markdown-comment")
  outer.set_attribute("data-start-line", start_line_number.to_string())
  outer.set_attribute("data-end-line", end_line_number_exclusive.to_string())
  let content = document.create_element("div")
  content.set_attribute("class", "moonbit-viewer-markdown-comment-content")
  outer.append_child(content.as_node())
  { outer, content }
}

///|
/// Pins the caller-owned ViewZone node to the visible content viewport. The
/// ordinary ViewZone write performed by `add_zone` deliberately uses the
/// model's horizontal scroll plane; this contribution-specific write runs
/// immediately afterwards and consumes geometry published by ViewLines.
pub fn MarkdownCommentDom::pin_to_content_viewport(
  self : MarkdownCommentDom,
) -> Unit {
  @base_browser.set_style_property(
    self.outer,
    "left",
    "var(--moonbit-viewer-rendered-scroll-left, 0px)",
  )
  @base_browser.set_style_property(
    self.outer,
    "width",
    "var(--moonbit-viewer-visible-content-width, 0px)",
  )
}

///|
/// Observes the inner Markdown content and reports its first/changed positive
/// integer height after one shared animation-frame boundary. Explicit requests
/// cover renderer replacement, image load, and model-scoped viewport-width
/// changes while a zone is offscreen. The root callback owns generation and
/// zone-id stale checks before relayout.
pub fn MarkdownCommentDom::observe_size(
  self : MarkdownCommentDom,
  on_height_changed : (Int) -> Unit,
) -> MarkdownCommentSizeObserver {
  let disposed = Ref(false)
  let frame_scheduled = Ref(false)
  let force_hidden_measure = Ref(false)
  let pending_frame : Ref[@base_common.Disposable?] = Ref(None)
  let last_height = Ref(0)
  let measure = () => {
    frame_scheduled.val = false
    pending_frame.val = None
    if disposed.val || !@base_browser.element_is_connected(self.content) {
      return
    }
    let allow_hidden = force_hidden_measure.val || last_height.val == 0
    force_hidden_measure.val = false
    let height = markdown_comment_measured_height(
      self.outer,
      self.content,
      allow_hidden,
    )
    if height <= 0 || height == last_height.val {
      return
    }
    last_height.val = height
    on_height_changed(height)
  }
  let schedule_measure = (force_hidden : Bool) => {
    if disposed.val {
      return
    }
    force_hidden_measure.val = force_hidden_measure.val || force_hidden
    if frame_scheduled.val {
      return
    }
    frame_scheduled.val = true
    let registration = @base_browser.schedule_at_next_animation_frame(measure)
    // Native requestAnimationFrame is asynchronous, but retaining this branch
    // makes the owner correct under a synchronous test/browser shim too.
    if frame_scheduled.val {
      pending_frame.val = Some(registration)
    } else {
      registration.dispose()
    }
  }
  let observer = @base_browser.observe_element_resize(self.content, () => {
    schedule_measure(false)
  })
  let lifetime = @base_common.Disposable::from(() => {
    disposed.val = true
    match observer {
      Some(observer) => observer.dispose()
      None => ()
    }
    match pending_frame.val {
      Some(registration) => registration.dispose()
      None => ()
    }
    pending_frame.val = None
    frame_scheduled.val = false
  })
  { request_measure_: () => schedule_measure(true), lifetime }
}

///|
/// A disposable size-observation lifetime with an explicit invalidation seam
/// for content replacement and image-load callbacks owned by the renderer.
pub struct MarkdownCommentSizeObserver {
  priv request_measure_ : () -> Unit
  priv lifetime : @base_common.Disposable
}

///|
pub fn MarkdownCommentSizeObserver::request_measure(
  self : MarkdownCommentSizeObserver,
) -> Unit {
  (self.request_measure_)()
}

///|
pub fn MarkdownCommentSizeObserver::dispose(
  self : MarkdownCommentSizeObserver,
) -> Unit {
  self.lifetime.dispose()
}

///|
/// One model-scoped observer for the editor content viewport. Width transitions
/// are deduplicated here; zero is remembered but not published so restoring a
/// previously equal positive width still invalidates hidden comment heights.
pub fn MarkdownCommentDom::observe_viewport_width(
  self : MarkdownCommentDom,
  on_width_changed : () -> Unit,
) -> MarkdownCommentViewportObserver {
  let disposed = Ref(false)
  let lifetime = match markdown_comment_content_viewport(self.outer) {
    Some(viewport) => {
      let last_width = Ref(
        @base_browser.element_client_width(viewport).to_int(),
      )
      let observer = @base_browser.observe_element_resize(viewport, () => {
        if disposed.val {
          return
        }
        let width = @base_browser.element_client_width(viewport).to_int()
        if width == last_width.val {
          return
        }
        last_width.val = width
        if width > 0 {
          on_width_changed()
        }
      })
      @base_common.Disposable::from(() => {
        disposed.val = true
        match observer {
          Some(observer) => observer.dispose()
          None => ()
        }
      })
    }
    None => @base_common.Disposable::from(() => disposed.val = true)
  }
  { lifetime, }
}

///|
pub struct MarkdownCommentViewportObserver {
  priv lifetime : @base_common.Disposable
}

///|
pub fn MarkdownCommentViewportObserver::dispose(
  self : MarkdownCommentViewportObserver,
) -> Unit {
  self.lifetime.dispose()
}

///|
fn markdown_comment_content_viewport(element : @rdom.Element) -> @rdom.Element? {
  if element_has_class(element, "editor-scrollable") {
    return Some(element)
  }
  match element.get_parent_node().to_option() {
    Some(parent) =>
      match parent.to_element() {
        Some(parent) => markdown_comment_content_viewport(parent)
        None => None
      }
    None => None
  }
}

///|
priv struct MarkdownCommentSavedStyle {
  name : String
  value : String
  priority : String
}

///|
fn save_markdown_comment_style(
  element : @rdom.Element,
  name : String,
) -> MarkdownCommentSavedStyle {
  {
    name,
    value: @base_browser.element_style_value(element, name),
    priority: @base_browser.element_style_priority(element, name),
  }
}

///|
fn restore_markdown_comment_style(
  element : @rdom.Element,
  saved : MarkdownCommentSavedStyle,
) -> Unit {
  if saved.value == "" {
    @base_browser.remove_style_property(element, saved.name)
  } else {
    @base_browser.set_style_property_with_priority(
      element,
      saved.name,
      saved.value,
      saved.priority,
    )
  }
}

///|
/// Reads visible content directly. For a connected `display:none` ViewZone,
/// temporarily lays out the caller-owned outer node invisibly without replacing
/// its viewport-pinned `left` or `width`, then restores every touched inline
/// declaration and priority before returning. A later zero-size ResizeObserver
/// notification is not allowed to repeat this hidden path unless the shared
/// viewport observer or renderer explicitly invalidated it.
fn markdown_comment_measured_height(
  outer : @rdom.Element,
  content : @rdom.Element,
  allow_hidden : Bool,
) -> Int {
  let direct = @base_browser.element_offset_height(content).to_int()
  if direct > 0 || !allow_hidden || !@base_browser.element_is_connected(content) {
    return direct
  }
  let saved = ["display", "visibility", "pointer-events", "height", "top"].map(name => {
    save_markdown_comment_style(outer, name)
  })
  defer (for declaration in saved {
    restore_markdown_comment_style(outer, declaration)
  })
  @base_browser.set_style_property_with_priority(
    outer, "display", "block", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "visibility", "hidden", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "pointer-events", "none", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "height", "auto", "important",
  )
  @base_browser.set_style_property_with_priority(
    outer, "top", "0px", "important",
  )
  let rect_width = outer.get_bounding_client_rect().get_width()
  let width = if rect_width > 0.0 {
    rect_width
  } else {
    @base_browser.element_offset_width(outer)
  }
  if width <= 0.0 {
    return 0
  }
  @base_browser.element_offset_height(content).to_int()
}
