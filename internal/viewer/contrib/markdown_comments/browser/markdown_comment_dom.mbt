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
/// Observes the inner Markdown content and reports its first/changed positive
/// integer height after one shared animation-frame boundary. Explicit requests
/// cover renderer replacement/image load while a zone is offscreen. The root
/// callback owns generation and zone-id stale checks before relayout.
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
    if disposed.val || !markdown_comment_element_is_connected(self.content) {
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
  let observer = markdown_comment_resize_observer(
    self.content,
    schedule_measure,
  )
  let lifetime = @base_common.Disposable::from(() => {
    disposed.val = true
    observer.disconnect()
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
#external
priv type MarkdownCommentResizeObserver

///|
extern "js" fn markdown_comment_resize_observer(
  target : @rdom.Element,
  notify : (Bool) -> Unit,
) -> MarkdownCommentResizeObserver =
  #| (target, notify) => {
  #|   const viewport = target.closest?.('.editor-scrollable') ?? null;
  #|   const observer = new ResizeObserver((entries) => {
  #|     notify(Boolean(viewport && entries.some((entry) => entry.target === viewport)));
  #|   });
  #|   observer.observe(target);
  #|   if (viewport && viewport !== target) observer.observe(viewport);
  #|   return observer;
  #| }

///|
extern "js" fn MarkdownCommentResizeObserver::disconnect(
  self : MarkdownCommentResizeObserver,
) -> Unit = "observer => observer.disconnect()"

///|
extern "js" fn markdown_comment_element_is_connected(
  element : @rdom.Element,
) -> Bool = "element => element?.isConnected === true"

///|
/// Reads visible content directly. For a connected `display:none` ViewZone,
/// temporarily lays out the caller-owned outer node invisibly at the editor
/// content viewport width, then restores every touched inline declaration and
/// priority before returning. A later zero-size ResizeObserver notification is
/// not allowed to repeat this hidden path unless the viewport or renderer
/// explicitly invalidated it.
extern "js" fn markdown_comment_measured_height(
  outer : @rdom.Element,
  content : @rdom.Element,
  allow_hidden : Bool,
) -> Int =
  #| (outer, content, allowHidden) => {
  #|   const direct = Math.trunc(content?.offsetHeight ?? 0);
  #|   if (direct > 0 || !allowHidden || content?.isConnected !== true) return direct;
  #|   const viewport = content.closest?.('.editor-scrollable') ?? null;
  #|   const width = Math.trunc(viewport?.clientWidth ?? 0);
  #|   if (width <= 0 || !outer?.style) return 0;
  #|   const names = ['display', 'visibility', 'pointer-events', 'height', 'width', 'top', 'left'];
  #|   const saved = names.map((name) => [
  #|     name,
  #|     outer.style.getPropertyValue(name),
  #|     outer.style.getPropertyPriority(name),
  #|   ]);
  #|   try {
  #|     outer.style.setProperty('display', 'block', 'important');
  #|     outer.style.setProperty('visibility', 'hidden', 'important');
  #|     outer.style.setProperty('pointer-events', 'none', 'important');
  #|     outer.style.setProperty('height', 'auto', 'important');
  #|     outer.style.setProperty('width', `${width}px`, 'important');
  #|     outer.style.setProperty('top', '0px', 'important');
  #|     outer.style.setProperty('left', '0px', 'important');
  #|     return Math.trunc(content.offsetHeight ?? 0);
  #|   } finally {
  #|     for (const [name, value, priority] of saved) {
  #|       if (value === '') outer.style.removeProperty(name);
  #|       else outer.style.setProperty(name, value, priority);
  #|     }
  #|   }
  #| }
