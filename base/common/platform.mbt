// Ported from `vscode/src/vs/base/common/platform.ts` (the OS facts only).
// Monaco reads `process.platform` in a native environment and falls back to
// `navigator.userAgent` sniffing in a browser; the js target applies the
// same order (`platform_js.mbt`) so unit tests under Node and browser runs
// agree on the host OS. Non-js targets report an unknown platform
// (`platform_fallback.mbt`) — they exist only for the no-DOM boundary check.

///|
priv enum HostPlatform {
  Mac
  Windows
  Linux
  UnknownPlatform
} derive(Eq)

///|
let host_platform : HostPlatform = match detect_platform_code() {
  1 => Mac
  2 => Windows
  3 => Linux
  _ => UnknownPlatform
}

///|
/// Monaco `platform.isMacintosh`.
pub let is_macintosh : Bool = host_platform == Mac

///|
/// Monaco `platform.isWindows`.
pub let is_windows : Bool = host_platform == Windows

///|
/// Monaco `platform.isLinux`.
pub let is_linux : Bool = host_platform == Linux

///|
/// D8 test seam for the URI/path stack: `None` reads the host platform.
let is_windows_override : Ref[Bool?] = { val: None }

///|
/// Debug-only override so non-Windows CI exercises the win32 branches that
/// `path.ts`/`uri.ts`/`resources.ts` gate on the global `isWindows`
/// (Deviation D8 of the URI-system port). Call with no argument to restore
/// the host platform.
pub fn set_is_windows_for_testing(value? : Bool) -> Unit {
  is_windows_override.val = value
}

///|
/// `path.ts:82 platformIsWin32` / the `platform.isWindows` reads inside
/// `uri.ts` and `resources.ts`. Monaco binds the value at module load; we
/// read it per call so the D8 test seam can flip it (observationally
/// identical — the platform never changes mid-session, Deviation D1).
pub fn platform_is_win32() -> Bool {
  match is_windows_override.val {
    Some(value) => value
    None => is_windows
  }
}
