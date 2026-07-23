///|
/// Emits a browser-test report object to the Playwright bridge and console.
pub extern "js" fn report_json(payload : String) -> Unit =
  #| (payload) => {
  #|   let parsed = null;
  #|   try {
  #|     parsed = JSON.parse(String(payload ?? "{}"));
  #|   } catch (error) {
  #|     parsed = {
  #|       suite: "unknown",
  #|       status: "failed",
  #|       failures: [`invalid report JSON: ${error?.message ?? String(error)}`],
  #|       metrics: {}
  #|     };
  #|   }
  #|   if (typeof globalThis.__readonlyEditorBrowserTestReport === "function") {
  #|     globalThis.__readonlyEditorBrowserTestReport(parsed);
  #|   }
  #|   console.info("[readonly-editor-browser-test]", JSON.stringify(parsed));
  #| }
