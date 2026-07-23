///|
/// Ordered registry of hover-participant factories. The MoonBit analog of
/// Monaco's `HoverParticipantRegistry` singleton in `hoverTypes.ts`: a free
/// global that the hover contribution populates, not state the viewer services
/// own. Each factory builds a participant from the editor-scoped services, like
/// Monaco's `instantiationService.createInstance(ctor, editor)`.
pub struct HoverParticipantRegistry {
  entries : Array[(HoverParticipantServices) -> HoverParticipantHandle]
}

///|
/// Creates an empty hover participant registry.
#alias(new, deprecated)
pub fn HoverParticipantRegistry::HoverParticipantRegistry() -> HoverParticipantRegistry {
  { entries: [] }
}

///|
/// Adds a hover participant factory to the registry.
pub fn HoverParticipantRegistry::register(
  self : HoverParticipantRegistry,
  factory : (HoverParticipantServices) -> HoverParticipantHandle,
) -> Unit {
  self.entries.push(factory)
}

///|
/// Builds one participant instance per registered factory for the given
/// services — Monaco's per-editor `_initializeHoverParticipants`.
pub fn HoverParticipantRegistry::build_all(
  self : HoverParticipantRegistry,
  services : HoverParticipantServices,
) -> Array[HoverParticipantHandle] {
  let participants = self.entries.map(factory => factory(services))
  // MoonBit's Array::sort_by is unstable, while JavaScript's source sort is
  // stable. Carry the registration index as an explicit tie-break so equal
  // ordinals retain registration order on every backend.
  let indexed : Array[(Int, HoverParticipantHandle)] = []
  for index, participant in participants {
    indexed.push((index, participant))
  }
  indexed.sort_by((left, right) => {
    let by_ordinal = left.1.ordinal - right.1.ordinal
    if by_ordinal != 0 {
      by_ordinal
    } else {
      left.0 - right.0
    }
  })
  indexed.map(entry => entry.1)
}

///|
/// Returns the mutable backing factory array, matching Monaco's `getAll()`
/// aliasing contract. `build_all` remains the instance-producing, ordinal-sort
/// boundary.
pub fn HoverParticipantRegistry::get_all(
  self : HoverParticipantRegistry,
) -> Array[(HoverParticipantServices) -> HoverParticipantHandle] {
  self.entries
}

///|
/// Process-wide hover participant registry, populated with the built-in
/// participants. The analog of Monaco's module-level `HoverParticipantRegistry`
/// plus the `HoverParticipantRegistry.register(...)` calls in
/// `hoverContribution.ts`.
pub let hover_participant_registry : HoverParticipantRegistry = make_default_hover_participant_registry()

///|
fn make_default_hover_participant_registry() -> HoverParticipantRegistry {
  let registry = HoverParticipantRegistry()
  register_default_hover_participants(registry)
  registry
}

///|
/// Registers the built-in marker and markdown hover participants
/// into `registry`, mirroring `hoverContribution.ts`. Registration lives here,
/// in the hover feature, never in the viewer services constructor.
pub fn register_default_hover_participants(
  registry : HoverParticipantRegistry,
) -> Unit {
  registry.register(services => {
    MarkerHoverParticipant(services.marker_decorations).hover_participant_handle()
  })
  registry.register(services => {
    MarkdownHoverParticipant(services.languages).hover_participant_handle()
  })
}
