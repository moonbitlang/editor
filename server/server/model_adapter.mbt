///|
fn text_model_from_document(
  document : @workspace.DocumentSnapshot,
) -> @model.TextModel {
  TextModel(
    document.uri,
    document.display_name,
    document.language_id,
    1,
    document.revision,
    document.text,
  )
}
