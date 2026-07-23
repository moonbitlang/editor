///|
/// The Monaco-shaped option identifiers that view parts query from
/// `ViewConfigurationChangedEvent.hasChanged`.  The root `Viewer` maps its
/// concrete option diffs to this semantic set; view parts never need to know
/// about the root option record.
pub(all) enum ViewConfigurationOption {
  LayoutInfo
  FontInfo
  LineHeight
  WrappingInfo
  RevealHorizontalRightPadding
  CursorSurroundingLines
  CursorSurroundingLinesStyle
  DisableLayerHinting
  StickyScroll
  RenderWhitespace
  RenderControlCharacters
  RenderLineHighlight
  RenderLineHighlightOnlyWhenFocus
  RenderValidationDecorations
  ReadOnly
  CursorBlinking
  EffectiveCursorStyle
  CursorSmoothCaretAnimation
  EffectiveEditContext
} derive(Eq, Debug)

///|
/// Source-shaped configuration payload.  `changed_options` is a typed bitset
/// represented as a deduplicated array because the readonly viewer has a
/// deliberately small option surface.
pub struct ViewConfigurationChangedEvent {
  priv changed_options : Array[ViewConfigurationOption]
}

///|
pub fn ViewConfigurationChangedEvent::from_changed_options(
  changed_options : Array[ViewConfigurationOption],
) -> ViewConfigurationChangedEvent {
  let result : Array[ViewConfigurationOption] = []
  for option in changed_options {
    if !view_configuration_options_contain(result, option) {
      result.push(option)
    }
  }
  { changed_options: result }
}

///|
fn ViewConfigurationChangedEvent::has_changed(
  self : ViewConfigurationChangedEvent,
  option : ViewConfigurationOption,
) -> Bool {
  view_configuration_options_contain(self.changed_options, option)
}

///|
fn view_configuration_options_contain(
  options : Array[ViewConfigurationOption],
  expected : ViewConfigurationOption,
) -> Bool {
  for option in options {
    if option == expected {
      return true
    }
  }
  false
}

///|
/// Consumed `ViewCursorStateChangedEvent` payload. Browser view parts only use
/// the projected view-space selections; model-space selections and the cursor
/// reason remain owned by the root Viewer's public event delivery.
pub struct ViewCursorStateChangedEvent {
  priv selections : Array[@core.Selection]
}

///|
pub fn ViewCursorStateChangedEvent::ViewCursorStateChangedEvent(
  selections : Array[@core.Selection],
) -> ViewCursorStateChangedEvent {
  { selections, }
}

///|
pub struct ViewFocusChangedEvent {
  priv is_focused : Bool
}

///|
pub fn ViewFocusChangedEvent::ViewFocusChangedEvent(
  is_focused : Bool,
) -> ViewFocusChangedEvent {
  { is_focused, }
}

///|
/// Consumed `ViewScrollChangedEvent` payload. ViewLines needs the new width;
/// view parts use the four independent changed flags. The root Viewer owns the
/// complete position/dimension values used by its public scroll event.
pub struct ViewScrollChangedEvent {
  priv scroll_width : Double
  priv scroll_width_changed : Bool
  priv scroll_left_changed : Bool
  priv scroll_height_changed : Bool
  priv scroll_top_changed : Bool
}

///|
pub fn ViewScrollChangedEvent::ViewScrollChangedEvent(
  scroll_width : Double,
  scroll_width_changed : Bool,
  scroll_left_changed : Bool,
  scroll_height_changed : Bool,
  scroll_top_changed : Bool,
) -> ViewScrollChangedEvent {
  {
    scroll_width,
    scroll_width_changed,
    scroll_left_changed,
    scroll_height_changed,
    scroll_top_changed,
  }
}

///|
/// Inclusive line range carried by `ViewTokensChangedEvent`.
pub struct ViewTokenChangeRange {
  priv from_line_number : Int
  priv to_line_number : Int
}

///|
pub fn ViewTokenChangeRange::ViewTokenChangeRange(
  from_line_number : Int,
  to_line_number : Int,
) -> ViewTokenChangeRange {
  { from_line_number, to_line_number }
}

///|
pub struct ViewTokensChangedEvent {
  priv ranges : Array[ViewTokenChangeRange]
}

///|
pub fn ViewTokensChangedEvent::ViewTokensChangedEvent(
  ranges : Array[ViewTokenChangeRange],
) -> ViewTokensChangedEvent {
  { ranges, }
}

///|
/// Closed readonly-view event union containing only events emitted by the
/// current Viewer and consumed by at least one browser view part.
pub(all) enum ViewEvent {
  ViewConfigurationChanged(ViewConfigurationChangedEvent)
  ViewCursorStateChanged(ViewCursorStateChangedEvent)
  ViewDecorationsChanged
  ViewFlushed
  ViewFocusChanged(ViewFocusChangedEvent)
  ViewLineMappingChanged
  ViewScrollChanged(ViewScrollChangedEvent)
  ViewTokensChanged(ViewTokensChangedEvent)
  ViewZonesChanged
}
