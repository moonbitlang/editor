///|
/// Node branch of `process.ts:24-31`: `VSCODE_CWD` ∥ `process.cwd()`; the web
/// branch (process.ts:43) hardcodes `/`.
extern "js" fn process_cwd_raw() -> String =
  #| () => {
  #|   if (typeof process !== "undefined" && typeof process?.versions?.node === "string") {
  #|     return process.env["VSCODE_CWD"] || process.cwd();
  #|   }
  #|   return "/";
  #| }

///|
/// Node branch of `process.ts:28`: `process.env[key]` (empty string when
/// unset); the web branch (process.ts:42) has an empty env.
extern "js" fn process_env_raw(key : String) -> String =
  #| (key) => {
  #|   if (typeof process !== "undefined" && typeof process?.versions?.node === "string") {
  #|     const value = process.env[key];
  #|     return value === undefined ? "" : value;
  #|   }
  #|   return "";
  #| }
