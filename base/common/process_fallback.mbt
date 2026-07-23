///|
/// Non-js targets have no Node `process`; they report the web shape of
/// `process.ts:38-43` (`cwd() => '/'`, empty env).
fn process_cwd_raw() -> String {
  "/"
}

///|
fn process_env_raw(_key : String) -> String {
  ""
}
