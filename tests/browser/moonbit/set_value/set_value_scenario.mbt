// Pins the `set_value` flush lane (Monaco's `TextModel.setValue` behind
// `codeEditorWidget.setValue`, plan `monaco-set-value-api-port.md`): unlike
// `set_model`, the same editor root survives (no view rebuild), the scroll
// is kept/clamped instead of reset, and the content-change consumers
// refresh — the quick-diff gutter recomputes against the new snapshot and
// the folding chevrons re-derive after the flush destroyed their
// decorations. Gutter assertions target lines inside the rendered viewport
// (the margin overlays render viewport-only rows).

///|
/// A 40-line document: the marker line, an indent-provider folding region
/// at lines 2-4 (visible at the top), then filler; `last_line` replaces the
/// final filler line when given (the bottom-visible needle for the
/// scrolled flush).
fn set_value_document(marker : String, last_line? : String) -> String {
  let lines = StringBuilder()
  lines.write_string(marker)
  lines.write_string("\nfold_start")
  lines.write_string("\n  fold_inner")
  lines.write_string("\nfold_end")
  for index in 5..<40 {
    lines.write_char('\n')
    lines.write_string("line_\{index}_of_doc")
  }
  lines.write_char('\n')
  match last_line {
    Some(text) => lines.write_string(text)
    None => lines.write_string("line_40_of_doc")
  }
  lines.to_string()
}

///|
fn run_set_value_test() -> Unit {
  let ctx = @support.BrowserTestContext("set_value")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host")
  host.set_attribute("style", "height:200px;width:400px;")
  app.append_child(host.as_node())
  // The page owns the mutable baseline store. The Viewer bundle receives a
  // borrowed handle and remains live with the fixture until document teardown.
  let quick_diff = @quick_diff.QuickDiffService()
  let services = @viewer.ViewerServices(
    quick_diff=quick_diff.quick_diff_handle(),
  )
  let original = set_value_document("alpha_document_marker")
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/set-value.txt",
    ),
    "set-value.txt",
    "plaintext",
    1,
    "set-value-rev-1",
    original,
  )
  // The quick-diff baseline equals the initial content: no gutter pieces
  // until set_value changes the modified side.
  quick_diff.set_original_content(model.uri, Some(original))
  let viewer = @viewer.Viewer::create(host, services~)
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  wait_for_text(ctx, "alpha_document_marker", 80, () => {
    ctx.assert_true(
      @support.query_count(".viewer-host > .monaco-editor") == 1,
      "expected exactly one editor root before the flush",
    )
    ctx.assert_true(
      @support.query_count(".margin-view-overlays .cldr.dirty-diff-modified") ==
      0,
      "expected no dirty-diff pieces while content equals the baseline",
    )
    ctx.assert_true(
      @support.query_count(
        ".margin-view-overlays .cldr.codicon-folding-expanded",
      ) ==
      1,
      "expected the indent region's chevron before the flush",
    )
    // Stamp the live root: `set_value` must keep this exact DOM subtree
    // (a rebuilt view — `set_model`'s behavior — would drop the stamp).
    match document.query_selector(".viewer-host > .monaco-editor").to_option() {
      Some(root) => root.set_attribute("data-flush-stamp", "kept")
      None => ctx.fail("missing editor root to stamp")
    }
    // First flush: the top-visible marker line changes — one modified
    // quick-diff piece, same view, folding rederived.
    viewer.set_value(set_value_document("beta_document_marker"))
    wait_for_text(ctx, "beta_document_marker", 80, () => {
      ctx.assert_true(
        @support.query_count(".viewer-host > .monaco-editor") == 1,
        "expected exactly one editor root after the flush",
      )
      ctx.assert_true(
        @support.query_attribute(
          ".viewer-host > .monaco-editor", "data-flush-stamp",
        ) ==
        "kept",
        "the editor root was rebuilt: set_value must keep the same view",
      )
      ctx.assert_true(
        @support.query_attribute(".viewer-host > .monaco-editor", "data-uri") ==
        model.uri.to_string(),
        "data-uri changed across the flush",
      )
      let modified = @support.query_count(
        ".margin-view-overlays .cldr.dirty-diff-modified",
      )
      ctx.metric_int("modified", modified)
      ctx.assert_true(
        modified == 1,
        "expected one modified gutter piece after the flush, saw " +
        modified.to_string(),
      )
      // The flush destroyed the folding decorations; the content-change
      // subscription re-derived the same region.
      ctx.assert_true(
        @support.query_count(
          ".margin-view-overlays .cldr.codicon-folding-expanded",
        ) ==
        1,
        "expected the folding chevron to survive the flush recompute",
      )
      // Second flush, scrolled to the bottom: the scroll position is kept
      // (clamped) across `set_value` — `set_model` would reset it.
      viewer.set_scroll_top(100000.0)
      let scrolled_top = viewer.get_scroll_top()
      ctx.assert_true(
        scrolled_top > 0.0,
        "expected the pre-flush scroll to move",
      )
      viewer.set_value(
        set_value_document(
          "beta_document_marker",
          last_line="gamma_document_marker",
        ),
      )
      wait_for_text(ctx, "gamma_document_marker", 80, () => {
        ctx.assert_true(
          viewer.get_scroll_top() == scrolled_top,
          "the scroll position did not survive the flush (saw " +
          viewer.get_scroll_top().to_string() +
          ", expected " +
          scrolled_top.to_string() +
          ")",
        )
        ctx.assert_true(
          @support.query_attribute(
            ".viewer-host > .monaco-editor", "data-flush-stamp",
          ) ==
          "kept",
          "the editor root was rebuilt by the second flush",
        )
        ctx.finish()
      })
    })
  })
}

///|
/// Polls until the editor surface contains `needle`, then runs `body`.
/// Needles must be space-free: view-line textContent uses non-breaking
/// spaces.
fn wait_for_text(
  ctx : @support.BrowserTestContext,
  needle : String,
  remaining : Int,
  body : () -> Unit,
) -> Unit {
  if @support.query_text(".viewer-host").contains(needle) {
    body()
    return
  }
  if remaining <= 0 {
    ctx.fail(
      "timed out waiting for text: " +
      needle +
      " (saw: " +
      @support.query_text(".viewer-host") +
      ")",
    )
    ctx.finish()
    return
  }
  @support.set_timeout(
    () => wait_for_text(ctx, needle, remaining - 1, body),
    50,
  )
}
