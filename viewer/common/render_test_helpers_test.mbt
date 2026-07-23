///|
/// Registers the generic fallback lexer for the `moonbit` language id the
/// test models carry (the real lexers are registered by the shell, not the
/// common tier). Idempotent; the registration lives for the test binary.
fn register_plain_moonbit() -> Unit {
  @syntax.tokenization_registry.register("moonbit", @syntax.PlainTokenizer())
  |> ignore
}

///|
/// Builds a view model over `doc`, with the generic fallback lexer
/// registered for the model's `moonbit` language id
/// (`register_plain_moonbit`, shared with the mouse-target tests).
fn view_model_for(doc : @model.TextSnapshot) -> @view_model.ViewModel {
  register_plain_moonbit()
  // The retained stabilized-range demand advances through an invalid frontier
  // only when the requested end lies beyond it. Give one-line render fixtures
  // an inert trailing line so line 1 follows the same production path.
  let model_text = if doc.line_count() == 1 {
    doc.get_value() + "\n"
  } else {
    doc.get_value()
  }
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/frame.mbt",
    ),
    "",
    "moonbit",
    1,
    "",
    model_text,
  )
  // View reads are deliberately passive. Rendering fixtures that assert
  // grammar classes own one source-shaped stabilized visible-range demand
  // before constructing lines, then release the temporary attachment.
  let attached_view = model.on_before_attached()
  attached_view.set_visible_lines(
    [{ start_line_number: 1, end_line_number: model.get_line_count() }],
    true,
  )
  model.on_before_detached(attached_view)
  ViewModel(model)
}
