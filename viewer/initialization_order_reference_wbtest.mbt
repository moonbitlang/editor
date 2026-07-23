// Initialization-order behavior port from Monaco
// b18492a288de038fbc7643aae6de8247029d11bd:
// - `browser/config/elementSizeObserver.ts:21-28,101-119`
// - `browser/widget/codeEditor/codeEditorWidget.ts:1750-1764,1889-1920`
// - `browser/widget/codeEditor/codeEditorWidget.ts:1074-1076`
// - `workbench/contrib/files/browser/editors/textFileEditor.ts:129-156`

///|
priv struct InitializationCountingTokenizer {
  calls : Ref[Int]
}

///|
impl @syntax.LineTokenizer for InitializationCountingTokenizer with fn initial_state(
  _self,
) {
  TokenizerState("initialization-order")
}

///|
impl @syntax.LineTokenizer for InitializationCountingTokenizer with fn tokenize_line(
  self,
  line_text,
  state,
) {
  self.calls.val += 1
  let tokens : Array[@syntax.LineToken] = []
  if line_text.length() > 0 {
    tokens.push({ start: 0, end: 1, tag: Keyword })
  }
  (tokens, state)
}

///|
test "mounted initialization uses the client box before model attach" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "initialization-order-mounted",
    InitializationCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let host = @rdom.document().create_element("div")
  // The fake bounding rect remains 100x100. A 320x180 result therefore proves
  // the source `clientWidth`/`clientHeight` semantics, not merely nonzero size.
  set_mounted_test_client_size(host, 320.0, 180.0)
  let viewer = Viewer::create(
    host,
    options=ViewerOptions(
      soft_wrap=true,
      font_size=12,
      line_height=18,
      line_numbers_min_chars=1,
      folding=false,
    ),
  )
  defer viewer.dispose()
  let initial_layout = viewer.get_layout_info()
  assert_eq(initial_layout.width, 320.0)
  assert_eq(initial_layout.height, 180.0)
  assert_true(viewer.configuration.snapshot().soft_wrap_column > 0)

  let model = test_model(
    long_document(100),
    language_id="initialization-order-mounted",
  )
  defer model.dispose()
  viewer.set_model(Some(model))

  let attached_layout = viewer.get_layout_info()
  let view_model = viewer.test_view_model()
  let dimensions = view_model.view_layout.dimensions()
  assert_eq(attached_layout.width, 320.0)
  assert_eq(dimensions.width, attached_layout.content_width)
  assert_eq(dimensions.height, 180.0)
  assert_true(viewer.get_visible_ranges()[0].end_line_number > 1)
  // `_attachModel` has completed, but its workbench-style initialization hook
  // belongs to root orchestration after synchronous restore/options work.
  assert_eq(calls.val, 0)

  viewer.handle_initialized()
  assert_true(calls.val > 1)
  let calls_after_initialization = calls.val

  // A scroll publishes a new unstable range and arms the model's 50 ms
  // debounce. A repeated host boundary must synchronously stabilize that new
  // range (and cancel the pending work); a one-shot initialization guard would
  // leave lexer demand unchanged here.
  viewer.set_scroll_top(360.0)
  assert_eq(calls.val, calls_after_initialization)
  viewer.handle_initialized()
  assert_true(calls.val > calls_after_initialization)
  let calls_after_scroll_initialization = calls.val
  viewer.handle_initialized()
  assert_eq(calls.val, calls_after_scroll_initialization)
}

///|
test "no-model layout consumes client measurement and clamps hidden hosts" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  let host = @rdom.document().create_element("div")
  set_mounted_test_client_size(host, 0.0, 0.0)
  let viewer = Viewer::create(host)
  defer viewer.dispose()
  let clamped = viewer.get_layout_info()
  assert_eq(clamped.width, 5.0)
  assert_eq(clamped.height, 5.0)

  set_mounted_test_client_size(host, 240.0, 120.0)
  viewer.layout()
  run_one_mounted_test_frame()
  let resized = viewer.get_layout_info()
  assert_eq(resized.width, 240.0)
  assert_eq(resized.height, 120.0)
  assert_true(resized.content_left > 0.0)
  assert_eq(resized.width, resized.content_left + resized.content_width)
  assert_false(viewer.configuration.consume_measure_request())
}

///|
test "headless model attach waits for explicit initialization" {
  let calls = Ref(0)
  let registration = @syntax.tokenization_registry.register(
    "initialization-order-headless",
    InitializationCountingTokenizer::{ calls, },
  )
  defer registration.dispose()
  let viewer = Viewer::Viewer(
    options=ViewerOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  let model = test_model(
    long_document(20),
    language_id="initialization-order-headless",
  )
  defer model.dispose()
  viewer.set_model(Some(model))
  viewer.test_set_viewport(width=200.0, height=90.0)
  assert_eq(calls.val, 0)

  viewer.handle_initialized()
  assert_true(calls.val > 1)
}

///|
test "initialization reentry does not initialize a replacement model" {
  let first_calls = Ref(0)
  let first_registration = @syntax.tokenization_registry.register(
    "initialization-order-reentry-first",
    InitializationCountingTokenizer::{ calls: first_calls },
  )
  defer first_registration.dispose()
  let replacement_calls = Ref(0)
  let replacement_registration = @syntax.tokenization_registry.register(
    "initialization-order-reentry-replacement",
    InitializationCountingTokenizer::{ calls: replacement_calls },
  )
  defer replacement_registration.dispose()
  let viewer = Viewer::Viewer()
  defer viewer.dispose()
  let first = test_model(
    long_document(4),
    language_id="initialization-order-reentry-first",
  )
  defer first.dispose()
  let replacement = test_model(
    long_document(6),
    language_id="initialization-order-reentry-replacement",
  )
  defer replacement.dispose()
  let replaced = Ref(false)
  let subscription = debug_on_did_build_view_model(viewer, _ => {
    if !replaced.val && first_calls.val > 0 {
      replaced.val = true
      viewer.set_model(Some(replacement))
    }
  })
  defer subscription.dispose()
  viewer.set_model(Some(first))
  viewer.test_set_viewport(width=200.0, height=90.0)

  viewer.handle_initialized()
  assert_true(replaced.val)
  assert_true(viewer.get_model().unwrap().same(replacement))
  assert_eq(replacement_calls.val, 0)

  viewer.handle_initialized()
  assert_true(replacement_calls.val > 0)
}
