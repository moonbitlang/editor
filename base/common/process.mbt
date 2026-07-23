///| Port of the `process.ts` `cwd`/`env` facade (process.ts:26-29 node,
/// process.ts:38-43 web). The js target reads the real Node `process` when one
/// exists and falls back to the web shape (`cwd() => '/'`, empty env)
/// otherwise; non-js targets always report the web shape
/// (`process_fallback.mbt`).

///|
/// `process.cwd()` — node: `VSCODE_CWD` ∥ `process.cwd()`; web: `'/'`.
pub fn cwd() -> String {
  process_cwd_raw()
}

///|
/// `process.env[key]` — node: the variable when set; web: always `None`.
/// A set-but-empty variable maps to `None`; Monaco's only consumer
/// (win32.resolve's per-drive cwd, path.ts:232) reads it through `||` so the
/// two are indistinguishable.
pub fn env(key : String) -> String? {
  let value = process_env_raw(key)
  if value == "" {
    None
  } else {
    Some(value)
  }
}
