// The hover-anchor types of Monaco's `hoverTypes.ts` (:42-82) and the
// wrapper's anchor-candidate pass (`contentHoverWidgetWrapper.ts:263-296`).
// The anchor is the *mouse position* as a collapsed model range (Monaco's
// `target.range`), not the hovered token's span — participants decide what
// spans the position covers.

///|
/// `HoverAnchorType` (`hoverTypes.ts:42-45`).
pub enum HoverAnchorType {
  Range
  ForeignElement
} derive(Eq, Debug)

///|
/// Stable identity of the participant that owns a foreign-element anchor.
/// Monaco compares participant objects by identity; the multi-target MoonBit
/// port mints an explicit identity so copying or rebuilding a participant
/// handle cannot change anchor equality or adoption.
pub struct HoverParticipantOwner {
  priv id : Int
} derive(Eq, Debug)

///|
let next_hover_participant_owner_id : Ref[Int] = Ref(0)

///|
/// Mints one logical participant identity. A factory that rebuilds handles for
/// separate input/compute passes must retain and reuse this value across them.
#alias(new, deprecated)
pub fn HoverParticipantOwner::HoverParticipantOwner() -> HoverParticipantOwner {
  next_hover_participant_owner_id.val += 1
  { id: next_hover_participant_owner_id.val }
}

///|
/// Monaco `HoverRangeAnchor` / `HoverForeignElementAnchor`
/// (`hoverTypes.ts:47-82`). `range` is model-space. The foreign variant's
/// `owner` is the explicitly minted identity of the suggesting participant;
/// `injected_text_index` is the local payload for injected text and takes no
/// part in `equals` (the source inherits the owner-only comparison).
/// `initial_mouse_pos_*` are carried per the source shape; the
/// mouse-getting-closer seam reads the live recorded pointer instead
/// (`MouseCloserState`, Phase 4 increment 2).
pub(all) enum HoverAnchor {
  HoverRangeAnchor(
    priority~ : Int,
    range~ : @base_common.Range,
    initial_mouse_pos_x~ : Double?,
    initial_mouse_pos_y~ : Double?
  )
  HoverForeignElementAnchor(
    priority~ : Int,
    owner~ : HoverParticipantOwner,
    injected_text_index~ : Int,
    range~ : @base_common.Range,
    initial_mouse_pos_x~ : Double?,
    initial_mouse_pos_y~ : Double?,
    supports_marker_hover~ : Bool
  )
} derive(Eq, Debug)

///|
pub fn HoverAnchor::anchor_type(self : HoverAnchor) -> HoverAnchorType {
  match self {
    HoverRangeAnchor(..) => Range
    HoverForeignElementAnchor(..) => ForeignElement
  }
}

///|
pub fn HoverAnchor::priority(self : HoverAnchor) -> Int {
  match self {
    HoverRangeAnchor(priority~, ..)
    | HoverForeignElementAnchor(priority~, ..) => priority
  }
}

///|
pub fn HoverAnchor::range(self : HoverAnchor) -> @base_common.Range {
  match self {
    HoverRangeAnchor(range~, ..) | HoverForeignElementAnchor(range~, ..) =>
      range
  }
}

///|
/// `HoverForeignElementAnchor.supportsMarkerHover`; a range anchor reads as
/// Monaco's `undefined` (`false`) — its consumers gate on the anchor type
/// first (`anchor.type !== Range && !anchor.supportsMarkerHover`).
pub fn HoverAnchor::supports_marker_hover(self : HoverAnchor) -> Bool {
  match self {
    HoverRangeAnchor(..) => false
    HoverForeignElementAnchor(supports_marker_hover~, ..) =>
      supports_marker_hover
  }
}

///|
/// Monaco `HoverAnchor.equals` (`hoverTypes.ts:56-58,:75-77`): range anchors
/// compare their ranges; foreign anchors compare their explicit participant
/// owners only.
pub fn hover_anchor_equals(left : HoverAnchor, right : HoverAnchor) -> Bool {
  match left {
    HoverRangeAnchor(range=left_range, ..) =>
      right is HoverRangeAnchor(range=right_range, ..) &&
      left_range == right_range
    HoverForeignElementAnchor(owner=left_owner, ..) =>
      right is HoverForeignElementAnchor(owner=right_owner, ..) &&
      left_owner == right_owner
  }
}

///|
/// Monaco `HoverAnchor.canAdoptVisibleHover` (`hoverTypes.ts:59-61,:78-80`):
/// a new range anchor adopts a visible hover shown from a range anchor on the
/// same line (the source compares against the widget's shown position, which
/// `computeHoverPositions` clamps to the anchor line — the last anchor's
/// start line is that line); a new foreign anchor adopts a visible hover
/// shown from the same owner's foreign anchor.
pub fn hover_anchor_can_adopt(
  new_anchor : HoverAnchor,
  last_anchor : HoverAnchor,
) -> Bool {
  hover_anchor_can_adopt_at(
    new_anchor,
    last_anchor,
    last_anchor.range().get_start_position(),
  )
}

///|
/// Source-exact adoption predicate with the currently shown widget position.
/// Range adoption compares that position's line with the new anchor; foreign
/// adoption ignores it and compares only participant owner identity.
pub fn hover_anchor_can_adopt_at(
  new_anchor : HoverAnchor,
  last_anchor : HoverAnchor,
  show_at_position : @base_common.Position,
) -> Bool {
  match new_anchor {
    HoverRangeAnchor(range~, ..) =>
      last_anchor is HoverRangeAnchor(..) &&
      show_at_position.line_number == range.start_line_number
    HoverForeignElementAnchor(owner=new_owner, ..) =>
      last_anchor is HoverForeignElementAnchor(owner=last_owner, ..) &&
      new_owner == last_owner
  }
}
