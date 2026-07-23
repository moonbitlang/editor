// Browser test for the Phase 3 deferred horizontal reveal — the one piece that
// can only be validated with real DOM client-rect measurement. It attaches a
// no-wrap viewer over a tall document of long lines, reveals a position that is
// both below the viewport and far to the right, and asserts the viewer scrolled
// vertically (line into view) AND horizontally (caret revealed via the deferred
// flush + the collapsed-caret `keep_empty` measurement path).

///|
fn run_reveal_horizontal_test() -> Unit {
  let ctx = @support.BrowserTestContext("reveal_horizontal")
  let last_scroll_left = Ref(0.0)
  let last_scroll_top = Ref(0.0)
  let done = Ref(false)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/reveal.txt",
  )
  let model = @model.TextModel(
    uri,
    "reveal.txt",
    "plaintext",
    1,
    "reveal-rev-1",
    reveal_source_text(),
  )
  match mount_host() {
    Some(host) => {
      // No soft wrap: long lines stay on one view line so a far-right column is
      // genuinely off-screen and needs a horizontal scroll to reveal.
      let viewer = @viewer.Viewer::create(
        host,
        options=ViewerOptions(
          soft_wrap=false,
          placeholder="Loading reveal fixture...",
        ),
      )
      viewer.on_did_scroll_change(event => {
        last_scroll_left.val = event.scroll_left
        last_scroll_top.val = event.scroll_top
      })
      |> ignore
      viewer.set_model(Some(model))
      viewer.handle_initialized()
      // Give the first render time to measure the char width, content width, and
      // viewport box, then reveal a position below and to the right of the
      // viewport and poll until the deferred horizontal scroll lands.
      @support.set_timeout(
        () => {
          viewer.reveal_position(Position(reveal_line(), reveal_column()))
          poll_reveal(ctx, last_scroll_left, last_scroll_top, done, 100)
        },
        100,
      )
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
fn poll_reveal(
  ctx : @support.BrowserTestContext,
  last_scroll_left : Ref[Double],
  last_scroll_top : Ref[Double],
  done : Ref[Bool],
  remaining : Int,
) -> Unit {
  if done.val {
    return
  }
  // The deferred horizontal reveal lands once the target line has rendered (one
  // frame to scroll vertically, the next to apply the measured scroll_left).
  if last_scroll_left.val > 0.0 {
    ctx.assert_true(
      last_scroll_top.val > 0.0,
      "reveal_position did not scroll the target line down into view",
    )
    ctx.assert_true(
      last_scroll_left.val > 0.0,
      "deferred horizontal reveal did not scroll the caret into view",
    )
    ctx.metric_number("scrollLeft", last_scroll_left.val)
    ctx.metric_number("scrollTop", last_scroll_top.val)
    done.val = true
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail(
      "timed out waiting for the deferred horizontal reveal to scroll right" +
      " (scroll_left=\{last_scroll_left.val}, scroll_top=\{last_scroll_top.val})",
    )
    done.val = true
    ctx.finish()
  } else {
    @support.set_timeout(
      () => {
        poll_reveal(ctx, last_scroll_left, last_scroll_top, done, remaining - 1)
      },
      30,
    )
  }
}

///|
fn mount_host() -> @rdom.Element? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      // Narrow + short so the reveal target is clearly outside both axes.
      host.set_attribute("style", "height:120px;width:240px;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}

///|
/// 1-based model line to reveal: well below the ~6 lines the 120px viewport
/// shows.
fn reveal_line() -> Int {
  30
}

///|
/// 1-based model column to reveal: far past the ~20 columns the 240px viewport
/// shows, so a horizontal scroll is required.
fn reveal_column() -> Int {
  100
}

///|
/// 60 lines, each long enough that column 100 sits well to the right of the
/// viewport.
fn reveal_source_text() -> String {
  let out = StringBuilder::new()
  for i in 0..<60 {
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string("line")
    out.write_string(i.to_string())
    for _ in 0..<120 {
      out.write_char('x')
    }
  }
  out.to_string()
}
