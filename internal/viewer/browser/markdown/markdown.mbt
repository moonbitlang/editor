///|
/// Browser policy and callbacks for one synchronous Markdown render.
pub(all) struct MarkdownRenderOptions {
  language_id : String?
  base_uri : @base_common.Uri?
  action_handler : ((String) -> Unit)?
  code_block_renderer : ((@markdown_core.MarkdownCodeBlock, String?) -> String)?
  on_size_changed : (() -> Unit)?
  allow_remote_images : Bool
}

///|
/// Builds renderer options. Remote images are opt-in; every callback is
/// synchronous. The `new` spelling remains only as the repository's deprecated
/// constructor alias.
#alias(new, deprecated)
pub fn MarkdownRenderOptions::MarkdownRenderOptions(
  language_id? : String,
  base_uri? : @base_common.Uri,
  action_handler? : (String) -> Unit,
  code_block_renderer? : (@markdown_core.MarkdownCodeBlock, String?) -> String,
  on_size_changed? : () -> Unit,
  allow_remote_images? : Bool = false,
) -> MarkdownRenderOptions {
  {
    language_id,
    base_uri,
    action_handler,
    code_block_renderer,
    on_size_changed,
    allow_remote_images,
  }
}

///|
/// The caller-owned/new target, idempotent renderer lifetime, and the pure
/// conversion fact used by hover/layout consumers.
pub(all) struct RenderedMarkdown {
  element : @rdom.Element
  dispose : @base_common.Disposable
  has_code_block : Bool
}

///|
/// Safely renders Markdown into a new `div` or an explicit reusable target.
/// Reusing a target disposes its previous renderer-owned listeners before its
/// children are replaced. Disposing a result never removes the target itself.
pub fn render_markdown(
  markdown : String,
  options? : MarkdownRenderOptions = MarkdownRenderOptions(),
  target? : @rdom.Element,
) -> RenderedMarkdown {
  let converted = @markdown_core.render_markdown(
    markdown,
    language_id?=options.language_id,
    code_block_renderer?=options.code_block_renderer,
  )
  let element = match target {
    Some(target) => target
    None => @rdom.document().create_element("div")
  }
  let base_uri = options.base_uri.map(uri => uri.to_string()).unwrap_or("")
  let action_handler = options.action_handler.unwrap_or(_ => ())
  let on_size_changed = options.on_size_changed.unwrap_or(() => ())
  let lifetime = install_markdown_dom(
    element,
    converted.html,
    base_uri,
    options.base_uri is Some(_),
    action_handler,
    options.action_handler is Some(_),
    on_size_changed,
    options.on_size_changed is Some(_),
    options.allow_remote_images,
  )
  {
    element,
    dispose: @base_common.Disposable::from(() => lifetime.dispose()),
    has_code_block: converted.has_code_block,
  }
}

///|
#external
priv type MarkdownDomLifetime

///|
extern "js" fn MarkdownDomLifetime::dispose(self : MarkdownDomLifetime) -> Unit = "(lifetime) => lifetime.dispose()"

///|
/// DOM parsing happens in an inert template so denied image URLs are removed
/// before insertion into the live document. The symbol-keyed target slot gives
/// each explicit reusable target exactly one active renderer-owned lifetime.
extern "js" fn install_markdown_dom(
  target : @rdom.Element,
  html : String,
  base_uri : String,
  has_base_uri : Bool,
  action_handler : (String) -> Unit,
  has_action_handler : Bool,
  on_size_changed : () -> Unit,
  has_on_size_changed : Bool,
  allow_remote_images : Bool,
) -> MarkdownDomLifetime =
  #| (target, html, baseUri, hasBaseUri, actionHandler, hasActionHandler, onSizeChanged, hasOnSizeChanged, allowRemoteImages) => {
  #|   const lifetimeSlot = Symbol.for("moonbit-community/editor/internal/viewer/browser/markdown/lifetime");
  #|   const previousDispose = target[lifetimeSlot];
  #|   if (typeof previousDispose === "function") previousDispose();
  #|
  #|   let active = true;
  #|   const listeners = [];
  #|   const listen = (node, type, listener) => {
  #|     node.addEventListener(type, listener);
  #|     listeners.push([node, type, listener]);
  #|   };
  #|   const ownerDocument = target.ownerDocument || globalThis.document;
  #|   const template = ownerDocument.createElement("template");
  #|   template.innerHTML = html;
  #|   const content = template.content || template;
  #|
  #|   const resolveUri = (raw, image) => {
  #|     if (!raw) return null;
  #|     try {
  #|       const resolved = hasBaseUri ? new URL(raw, baseUri) : new URL(raw);
  #|       const protocol = resolved.protocol.toLowerCase();
  #|       if (image) {
  #|         return protocol === "http:" || protocol === "https:" ? resolved.href : null;
  #|       }
  #|       return protocol === "http:" || protocol === "https:" || protocol === "mailto:"
  #|         ? resolved.href
  #|         : null;
  #|     } catch (_error) {
  #|       return null;
  #|     }
  #|   };
  #|
  #|   for (const input of Array.from(content.querySelectorAll("input"))) {
  #|     if ((input.getAttribute("type") || "").toLowerCase() !== "checkbox") {
  #|       input.remove();
  #|       continue;
  #|     }
  #|     input.disabled = true;
  #|     input.setAttribute("disabled", "");
  #|   }
  #|
  #|   for (const image of Array.from(content.querySelectorAll("img"))) {
  #|     const resolved = allowRemoteImages
  #|       ? resolveUri(image.getAttribute("src") || "", true)
  #|       : null;
  #|     if (!resolved) {
  #|       image.remove();
  #|       continue;
  #|     }
  #|     image.setAttribute("src", resolved);
  #|     if (hasOnSizeChanged) {
  #|       listen(image, "load", () => {
  #|         if (active) onSizeChanged();
  #|       });
  #|     }
  #|   }
  #|
  #|   const makeInert = (anchor) => {
  #|     anchor.removeAttribute("href");
  #|     anchor.removeAttribute("target");
  #|     anchor.removeAttribute("rel");
  #|     anchor.removeAttribute("role");
  #|     anchor.removeAttribute("tabindex");
  #|   };
  #|   for (const anchor of Array.from(content.querySelectorAll("a"))) {
  #|     const resolved = resolveUri(anchor.getAttribute("href") || "", false);
  #|     if (!resolved) {
  #|       makeInert(anchor);
  #|       continue;
  #|     }
  #|     if (!hasActionHandler) {
  #|       anchor.setAttribute("href", resolved);
  #|       anchor.setAttribute("target", "_blank");
  #|       anchor.setAttribute("rel", "noopener noreferrer");
  #|       continue;
  #|     }
  #|
  #|     anchor.removeAttribute("href");
  #|     anchor.removeAttribute("target");
  #|     anchor.removeAttribute("rel");
  #|     anchor.setAttribute("role", "link");
  #|     anchor.setAttribute("tabindex", "0");
  #|     listen(anchor, "click", (event) => {
  #|       event.preventDefault();
  #|       if (active && (event.button === undefined || event.button === 0)) {
  #|         actionHandler(resolved);
  #|       }
  #|     });
  #|     listen(anchor, "auxclick", (event) => {
  #|       event.preventDefault();
  #|       if (active && event.button === 1) actionHandler(resolved);
  #|     });
  #|     listen(anchor, "keydown", (event) => {
  #|       if (event.key !== "Enter" && event.key !== " " && event.key !== "Space" && event.key !== "Spacebar") return;
  #|       event.preventDefault();
  #|       if (active) actionHandler(resolved);
  #|     });
  #|   }
  #|
  #|   const canScroll = (delta, position, clientSize, scrollSize) => {
  #|     if (delta < 0) return position > 0;
  #|     if (delta > 0) return position + clientSize < scrollSize - 1;
  #|     return false;
  #|   };
  #|   for (const diagram of Array.from(content.querySelectorAll("div"))) {
  #|     const classes = (diagram.getAttribute("class") || "").split(/\s+/);
  #|     if (!classes.includes("moonbit-viewer-markdown-diagram")) continue;
  #|     listen(diagram, "wheel", (event) => {
  #|       if (!active) return;
  #|       const deltaX = Number(event.deltaX || (event.shiftKey ? event.deltaY : 0));
  #|       const deltaY = Number(event.shiftKey ? 0 : event.deltaY || 0);
  #|       const consumesX = canScroll(
  #|         deltaX,
  #|         diagram.scrollLeft,
  #|         diagram.clientWidth,
  #|         diagram.scrollWidth,
  #|       );
  #|       const consumesY = canScroll(
  #|         deltaY,
  #|         diagram.scrollTop,
  #|         diagram.clientHeight,
  #|         diagram.scrollHeight,
  #|       );
  #|       // Preserve the browser's native inner scroll. When neither axis can
  #|       // consume the delta, let it reach the owning surface's scroller.
  #|       if (consumesX || consumesY) event.stopPropagation();
  #|     });
  #|   }
  #|
  #|   target.replaceChildren(content);
  #|   const dispose = () => {
  #|     if (!active) return;
  #|     active = false;
  #|     for (const [node, type, listener] of listeners) {
  #|       node.removeEventListener(type, listener);
  #|     }
  #|     listeners.length = 0;
  #|     if (target[lifetimeSlot] === dispose) delete target[lifetimeSlot];
  #|   };
  #|   target[lifetimeSlot] = dispose;
  #|   return { dispose };
  #| }
