// Root-private instrumentation remains only for white-box assertions. Browser
// tests and the workbench subscribe through the Viewer-id-keyed
// `internal/viewer/browser/testing` registry, so none of these hooks or
// payloads leak through the public Viewer facade.

///|
/// Fires after a model's content is prepared for rendering (view-model build
/// at attach, token re-warm on tokenizer changes) — tokenize/build timings
/// and counts for telemetry and test synchronization.
fn debug_on_did_build_view_model(
  viewer : Viewer,
  listener : (@viewer_testing.ViewModelBuiltObservation) -> Unit,
) -> @base_common.Disposable {
  viewer.did_build_view_model.event(listener)
}

///|
/// White-box-only seam retained in the ordinary library build.
let _debug_build_test_seam_anchor : Unit = ignore(debug_on_did_build_view_model)

///|
fn Viewer::emit_view_model_built(
  self : Viewer,
  observation : @viewer_testing.ViewModelBuiltObservation,
) -> Unit {
  self.did_build_view_model.fire(observation)
  @viewer_testing.publish_view_model_built(self.get_id(), observation)
}

///|
fn Viewer::emit_model_rendered(
  self : Viewer,
  observation : @viewer_testing.ModelRenderedObservation,
) -> Unit {
  @viewer_testing.publish_model_rendered(self.get_id(), observation)
}

///|
fn Viewer::emit_hover_resolved(
  self : Viewer,
  observation : @viewer_testing.HoverResolvedObservation,
) -> Unit {
  @viewer_testing.publish_hover_resolved(self.get_id(), observation)
}

///|
/// Emits the internal scroll/render trace without exposing it through the
/// public Viewer facade. `publish_scroll_frame` remains allocation-free when
/// no browser-test/workbench listener is installed.
fn Viewer::emit_scroll_frame_phase(
  self : Viewer,
  phase : @viewer_testing.ScrollFramePhase,
  scroll_top : Double,
  scroll_left : Double,
) -> Unit {
  @viewer_testing.publish_scroll_frame(
    self.get_id(),
    phase,
    scroll_top,
    scroll_left,
  )
}
