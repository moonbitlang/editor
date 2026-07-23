// The public decoration API slice of Monaco's `codeEditorWidget.ts`
// (decoration plan Phase 5), checked-in vscode submodule:
// `deltaDecorations` (:1368), `removeDecorations` (:1380),
// `getLineDecorations` (:1342), `getDecorationsInRange` (:1350).
//
// Deviations: the no-model `null` returns are empty arrays (MoonBit
// signatures stay non-optional, matching the viewer's public read API
// conventions); `filterFontDecorations` is constantly false (font
// decorations out of scope).

///|
/// `deltaDecorations` (`codeEditorWidget.ts:1368-1378`): atomically replace
/// `old_decorations` (ids) with `new_decorations`, owned by this viewer
/// (`ownerId` = the viewer's editor id). Returns the new decoration ids.
/// ModelDecorationOptions state lives on the model, so it follows the model across
/// `set_model` swaps like Monaco's — re-apply on swap.
pub fn Viewer::delta_decorations(
  self : Viewer,
  old_decorations : Array[String],
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  guard self.get_model() is Some(model) else { return [] }
  if old_decorations.length() == 0 && new_decorations.length() == 0 {
    return old_decorations
  }
  model.delta_decorations(
    old_decorations,
    new_decorations,
    owner_id=self.editor_id,
  )
}

///|
/// `removeDecorations` (`codeEditorWidget.ts:1380-1387`): delta to empty
/// through one `change_decorations` bracket.
pub fn Viewer::remove_decorations(
  self : Viewer,
  decoration_ids : Array[String],
) -> Unit {
  guard self.get_model() is Some(model) && decoration_ids.length() > 0 else {
    return
  }
  model.change_decorations(accessor => {
    ignore((accessor.delta_decorations)(decoration_ids, []))
  })
}

///|
/// `getLineDecorations` (`codeEditorWidget.ts:1342-1348`): the model's line
/// query filtered by this viewer's editor id and its
/// `renderValidationDecorations` option.
pub fn Viewer::get_line_decorations(
  self : Viewer,
  line_number : Int,
) -> Array[@model.ModelDecoration] {
  guard self.get_model() is Some(model) else { return [] }
  model.get_line_decorations(
    line_number,
    owner_id=self.editor_id,
    filter_out_validation=@view_model.filter_validation_decorations(
      self.get_options().render_validation_decorations,
    ),
  )
}

///|
/// `getDecorationsInRange` (`codeEditorWidget.ts:1350-1356`).
pub fn Viewer::get_decorations_in_range(
  self : Viewer,
  range : @base_common.Range,
) -> Array[@model.ModelDecoration] {
  guard self.get_model() is Some(model) else { return [] }
  model.get_decorations_in_range(
    range,
    owner_id=self.editor_id,
    filter_out_validation=@view_model.filter_validation_decorations(
      self.get_options().render_validation_decorations,
    ),
  )
}

///|
/// Monaco's `IEditorDecorationsCollection` (`editorCommon.ts:544`), the
/// non-deprecated decoration entry point: an id-managing wrapper over
/// `delta_decorations` bound to one viewer. `onDidChange` and `has` are not
/// ported (no consumer; the model-decoration event seam stays internal).
pub struct EditorDecorationsCollection {
  priv viewer : Viewer
  priv mut decoration_ids : Array[String]
}

///|
/// `createDecorationsCollection` (`codeEditorWidget.ts:1389`).
pub fn Viewer::create_decorations_collection(
  self : Viewer,
  decorations? : Array[@model.ModelDeltaDecoration] = [],
) -> EditorDecorationsCollection {
  let collection : EditorDecorationsCollection = {
    viewer: self,
    decoration_ids: [],
  }
  if decorations.length() > 0 {
    collection.set(decorations) |> ignore
  }
  collection
}

///|
/// Replaces all previous decorations with `new_decorations`; returns the new
/// ids.
pub fn EditorDecorationsCollection::set(
  self : EditorDecorationsCollection,
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  self.decoration_ids = self.viewer.delta_decorations(
    self.decoration_ids,
    new_decorations,
  )
  self.decoration_ids
}

///|
/// Appends `new_decorations` to the collection; returns the appended ids.
pub fn EditorDecorationsCollection::append(
  self : EditorDecorationsCollection,
  new_decorations : Array[@model.ModelDeltaDecoration],
) -> Array[String] {
  let appended = self.viewer.delta_decorations([], new_decorations)
  self.decoration_ids = self.decoration_ids + appended
  appended
}

///|
/// Removes every decoration in the collection.
pub fn EditorDecorationsCollection::clear(
  self : EditorDecorationsCollection,
) -> Unit {
  self.decoration_ids = self.viewer.delta_decorations(self.decoration_ids, [])
}

///|
/// The decoration count.
pub fn EditorDecorationsCollection::length(
  self : EditorDecorationsCollection,
) -> Int {
  self.decoration_ids.length()
}

///|
/// The current model range of the `index`-th decoration, `None` when the
/// index is out of bounds or the decoration no longer resolves.
pub fn EditorDecorationsCollection::get_range(
  self : EditorDecorationsCollection,
  index : Int,
) -> @base_common.Range? {
  guard index >= 0 && index < self.decoration_ids.length() else { return None }
  guard self.viewer.get_model() is Some(model) else { return None }
  model.get_decoration_range(self.decoration_ids[index])
}

///|
/// The current model ranges of every decoration that still resolves.
pub fn EditorDecorationsCollection::get_ranges(
  self : EditorDecorationsCollection,
) -> Array[@base_common.Range] {
  guard self.viewer.get_model() is Some(model) else { return [] }
  let ranges = []
  for id in self.decoration_ids {
    match model.get_decoration_range(id) {
      Some(range) => ranges.push(range)
      None => ()
    }
  }
  ranges
}
