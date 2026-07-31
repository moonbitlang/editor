///|
/// Immutable identity for the token under a definition-link gesture. The
/// browser target is reduced to model coordinates before entering this
/// DOM-free package. Every field is part of the freshness contract.
pub(all) struct DefinitionTargetFingerprint {
  model_identity : Int
  model_generation : Int
  model_version_id : Int
  position : @base_common.Position
  word_range : @base_common.Range
  word : String
} derive(Eq, Debug)

///|
pub fn DefinitionTargetFingerprint::from_model(
  model : @model.TextModel,
  model_generation : Int,
  position : @base_common.Position,
  word : @model.WordAtPosition,
) -> DefinitionTargetFingerprint {
  {
    model_identity: model.identity(),
    model_generation,
    model_version_id: model.get_version_id(),
    position,
    word_range: Range(
      position.line_number,
      word.start_column,
      position.line_number,
      word.end_column,
    ),
    word: word.word,
  }
}

///|
/// Whether the physical model and its content are still the ones captured by
/// this target. Callers separately compare the live mouse target when exact
/// down/up identity matters.
pub fn DefinitionTargetFingerprint::is_current(
  self : DefinitionTargetFingerprint,
  model : @model.TextModel,
  model_generation : Int,
) -> Bool {
  self.model_identity == model.identity() &&
  self.model_generation == model_generation &&
  self.model_version_id == model.get_version_id() &&
  !model.is_disposed()
}

///|
/// Whether two pointer positions address the same word in the same immutable
/// model snapshot. Monaco caches definition-link preview work by the word,
/// rather than issuing a new request for every caret column inside that word.
pub fn DefinitionTargetFingerprint::same_word(
  self : DefinitionTargetFingerprint,
  other : DefinitionTargetFingerprint,
) -> Bool {
  self.model_identity == other.model_identity &&
  self.model_generation == other.model_generation &&
  self.model_version_id == other.model_version_id &&
  self.word_range == other.word_range &&
  self.word == other.word
}

///|
/// A definition request sequence plus its immutable source target.
pub(all) struct DefinitionRequestStamp {
  sequence : Int
  target : DefinitionTargetFingerprint
} derive(Eq, Debug)

///|
/// Stable result normalization. Provider and CLI order is preserved; exact
/// URI+range duplicates keep their first occurrence, which is also the normal
/// goto target.
pub fn normalize_definition_locations(
  locations : Array[@language.Location],
) -> Array[@language.Location] {
  let normalized : Array[@language.Location] = []
  for candidate in locations {
    let mut duplicate = false
    for existing in normalized {
      if existing.uri.to_string() == candidate.uri.to_string() &&
        existing.range == candidate.range {
        duplicate = true
        break
      }
    }
    if !duplicate {
      normalized.push(candidate)
    }
  }
  normalized
}

///|
/// DOM-free link-gesture state. Cancellation tokens and decorations remain
/// with the root/browser owner; this enum only records the algorithmic
/// transition payload.
pub(all) enum DefinitionLinkState {
  LinkIdle
  LinkResolving(DefinitionRequestStamp)
  LinkResolvedEmpty(DefinitionRequestStamp)
  LinkArmed(DefinitionRequestStamp, Array[@language.Location])
}

///|
/// Logical Peek lifecycle. Browser resources are held by the root Viewer and
/// keyed by these generations rather than embedded in the state enum.
pub(all) enum DefinitionPeekPhase {
  PeekClosed
  PeekLoadingDefinitions(Int)
  PeekLoadingPreview(Int, Int)
  PeekShown(Int, Int)
  PeekUnavailable(Int, Int)
} derive(Eq, Debug)
