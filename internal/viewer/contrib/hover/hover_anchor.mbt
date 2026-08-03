// The hover-anchor types of Monaco's `hoverTypes.ts` (:42-82) and the
// wrapper's anchor-candidate pass (`contentHoverWidgetWrapper.ts:263-296`).
// The anchor is the *mouse position* as a collapsed model range (Monaco's
// `target.range`), not the hovered token's span — participants decide what
// spans the position covers.

///|
/// `HoverAnchorType` (`hoverTypes.ts:42-45`).
priv enum HoverAnchorType {
  Range
  ForeignElement
} derive(Eq, Debug)

///|
/// Stable identity of the participant that owns a foreign-element anchor.
/// Monaco compares participant objects by identity; the multi-target MoonBit
/// port mints an explicit identity so copying or rebuilding a participant
/// handle cannot change anchor equality or adoption.
struct HoverParticipantOwner {
  id : Int
} derive(Eq, Debug)

///|
let next_hover_participant_owner_id : Ref[Int] = Ref(0)

///|
fn HoverAnchor::anchor_type(self : HoverAnchor) -> HoverAnchorType {
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
fn HoverAnchor::range(self : HoverAnchor) -> @base_common.Range {
  match self {
    HoverRangeAnchor(range~, ..) | HoverForeignElementAnchor(range~, ..) =>
      range
  }
}

///|
/// `HoverForeignElementAnchor.supportsMarkerHover`; a range anchor reads as
/// Monaco's `undefined` (`false`) — its consumers gate on the anchor type
/// first (`anchor.type !== Range && !anchor.supportsMarkerHover`).
fn HoverAnchor::supports_marker_hover(self : HoverAnchor) -> Bool {
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
fn hover_anchor_equals(left : HoverAnchor, right : HoverAnchor) -> Bool {
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
fn hover_anchor_can_adopt(
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
fn hover_anchor_can_adopt_at(
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
