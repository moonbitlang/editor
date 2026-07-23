///|
fn main {
  if initial_size_requested() {
    run_initial_size_test()
  } else if markdown_comments_requested() {
    run_markdown_comments_test()
  } else if view_zones_requested() {
    run_view_zones_test()
  } else if browser_geometry_requested() {
    run_browser_geometry_test()
  } else if cursor_input_events_requested() {
    run_cursor_input_events_test()
  } else if async_features_requested() {
    run_async_model_features_test()
  } else if render_invalidation_requested() {
    run_render_invalidation_test()
  } else if scroll_perf_requested() {
    run_scroll_perf_test()
  } else {
    run_viewer_api_test()
  }
}

///|
extern "js" fn initial_size_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('initialSize')

///|
extern "js" fn markdown_comments_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('markdownComments')

///|
extern "js" fn view_zones_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('viewZones')

///|
extern "js" fn browser_geometry_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('browserGeometry')

///|
extern "js" fn cursor_input_events_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('cursorInput')

///|
extern "js" fn async_features_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('asyncFeatures')

///|
extern "js" fn render_invalidation_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('renderInvalidation')

///|
extern "js" fn scroll_perf_requested() -> Bool =
  #| () => new URLSearchParams(location.search).has('scrollPerf')
