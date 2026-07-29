///|
/// Shared browser action policy for sanitized Markdown links. URI validation
/// and protocol allowlisting already happened in the renderer; this capability
/// opens that accepted URI without granting the new window an opener.
pub fn open_external_link(uri : String) -> Unit {
  open_external_link_js(uri)
}

///|
extern "js" fn open_external_link_js(uri : String) -> Unit =
  #| uri => {
  #|   const opened = globalThis.open?.(uri, "_blank", "noopener,noreferrer");
  #|   if (opened) opened.opener = null;
  #| }
