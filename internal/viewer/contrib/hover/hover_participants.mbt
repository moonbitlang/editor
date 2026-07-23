///|
/// One renderable contribution to the content hover widget.
pub(all) enum HoverPart {
  MarkdownHover(
    range~ : @base_common.Range,
    contents~ : Array[@language.HoverContent],
    ordinal~ : Int
  )
  MarkerHover(range~ : @base_common.Range, marker~ : @markers.Marker)
  LoadingHover(range~ : @base_common.Range, message~ : String)
} derive(Eq, Debug)

///|
/// Complete hover result after participant parts have been merged and sorted.
pub struct ComputedHover {
  range : @base_common.Range
  parts : Array[HoverPart]
} derive(Eq, Debug)

///|
/// Inputs shared by synchronous and asynchronous hover participants. Mirrors
/// Monaco's `(anchor, lineDecorations, source)` compute arguments: it carries
/// only the hovered state, never a services bag — participants capture the
/// services they need at construction instead. `line_decorations` is selected
/// once by the computer and `source` is forwarded unchanged to every
/// sync/async participant.
pub struct HoverComputeContext {
  model : @model.TextModel
  anchor : HoverAnchor
  source : HoverStartSource
  line_decorations : Array[@model.ModelDecoration]
}

///|
/// Monaco `ContentHoverComputer._getLineDecorations`: selects the anchor line's
/// decorations with whole-line acceptance, strict ordinary containment, and
/// the `showIfCollapsed` one-column relaxation.
fn hover_line_decorations(
  model : @model.TextModel,
  anchor : HoverAnchor,
) -> Array[@model.ModelDecoration] {
  if !(anchor is HoverRangeAnchor(..)) && !anchor.supports_marker_hover() {
    return []
  }
  let anchor_range = anchor.range()
  let line_number = anchor_range.start_line_number
  if line_number > model.get_line_count() {
    return []
  }
  let max_column = model.get_line_max_column(line_number)
  model
  .get_line_decorations(line_number)
  .filter(decoration => {
    if decoration.options.is_whole_line {
      return true
    }
    let start_column = if decoration.range.start_line_number == line_number {
      decoration.range.start_column
    } else {
      1
    }
    let end_column = if decoration.range.end_line_number == line_number {
      decoration.range.end_column
    } else {
      max_column
    }
    if decoration.options.show_if_collapsed {
      !(start_column > anchor_range.start_column + 1 ||
      anchor_range.end_column - 1 > end_column)
    } else {
      !(start_column > anchor_range.start_column ||
      anchor_range.end_column > end_column)
    }
  })
}

///|
/// Value-level adapter for Monaco's `IEditorHoverParticipant`. The ordinal and
/// required synchronous computation remain required values; the source's
/// optional anchor suggestion, asynchronous computation, and loading-message
/// members remain independently optional closures instead of mandatory trait
/// methods with empty implementations.
///
/// Deviation: Monaco's anchor suggestion receives the whole
/// `IEditorMouseEvent`; that type is js-only here, so this multi-target handle
/// receives the extracted facts the ported participants read — the content-text
/// hit's injected text (if any), the hit's model range, and the recorded
/// pointer position
/// (`internal/viewer/contrib/hover/browser/hover_events.mbt` extracts them).
pub struct HoverParticipantHandle {
  ordinal : Int
  suggest_hover_anchor : ((
    @view_model.InjectedText?,
    @base_common.Range,
    Double?,
    Double?,
  ) -> HoverAnchor?)?
  compute_sync : (HoverComputeContext) -> Array[HoverPart]
  compute_async : (async (HoverComputeContext, @language.CancellationToken) -> Array[
    HoverPart,
  ] noraise)?
  create_loading_message : ((HoverAnchor) -> HoverPart?)?
}

///|
/// Creates an open hover-participant adapter. Optional callbacks preserve
/// Monaco's absent-member branches; closures capture any concrete participant
/// state they need at this construction boundary.
pub fn HoverParticipantHandle::HoverParticipantHandle(
  ordinal : Int,
  compute_sync : (HoverComputeContext) -> Array[HoverPart],
  suggest_hover_anchor? : (
    @view_model.InjectedText?,
    @base_common.Range,
    Double?,
    Double?,
  ) -> HoverAnchor?,
  compute_async? : async (HoverComputeContext, @language.CancellationToken) -> Array[
    HoverPart,
  ] noraise,
  create_loading_message? : (HoverAnchor) -> HoverPart?,
) -> HoverParticipantHandle {
  {
    ordinal,
    suggest_hover_anchor,
    compute_sync,
    compute_async,
    create_loading_message,
  }
}

///|
/// The editor-scoped services a hover participant captures at construction, the
/// MoonBit analog of the services Monaco injects into participant constructors
/// (`IMarkerDecorationsService`, `ILanguageFeaturesService`, …). The registry
/// builds participants from this record, so the hover package never depends on
/// the viewer core's `ViewerServices`.
pub(all) struct HoverParticipantServices {
  languages : @languages.LanguageHandle
  marker_decorations : @markers.MarkerDecorationsHandle
}

///|
/// Hover participant that exposes diagnostics/markers at the anchor range.
pub struct MarkerHoverParticipant {
  priv marker_decorations : @markers.MarkerDecorationsHandle
}

///|
/// Creates the marker hover participant over the marker decorations service.
#alias(new, deprecated)
pub fn MarkerHoverParticipant::MarkerHoverParticipant(
  marker_decorations : @markers.MarkerDecorationsHandle,
) -> MarkerHoverParticipant {
  { marker_decorations, }
}

///|
/// Computes marker hover parts from the current marker decorations —
/// `computeSync` (`markerHoverParticipant.ts:74-101`) with
/// `ContentHoverComputer._getLineDecorations`'s anchor-line column filter
/// (`contentHoverComputer.ts:29-60`) folded in: the viewer's marker
/// decorations arrive as live `(range, marker)` pairs rather than as line
/// decorations, so the containment check — with the `showIfCollapsed` ±1
/// relaxation; marker decorations always set `showIfCollapsed` — applies
/// here. Part ranges clamp to the anchor's start line, per the source.
fn MarkerHoverParticipant::compute_sync(
  self : MarkerHoverParticipant,
  ctx : HoverComputeContext,
) -> Array[HoverPart] {
  let anchor = ctx.anchor
  if !(anchor is HoverRangeAnchor(..)) && !anchor.supports_marker_hover() {
    return []
  }
  let anchor_range = anchor.range()
  let line_number = anchor_range.start_line_number
  if line_number > ctx.model.get_line_count() {
    // invalid line (`contentHoverComputer.ts:37-40`)
    return []
  }
  let max_column = ctx.model.get_line_max_column(line_number)
  let parts : Array[HoverPart] = []
  for entry in self.marker_decorations.get_live_markers_for_model(ctx.model) {
    let (range, marker) = entry
    // `editor.getLineDecorations(lineNumber)`: only decorations touching the
    // anchor line participate.
    if range.start_line_number > line_number ||
      range.end_line_number < line_number {
      continue
    }
    let start_column = if range.start_line_number == line_number {
      range.start_column
    } else {
      1
    }
    let end_column = if range.end_line_number == line_number {
      range.end_column
    } else {
      max_column
    }
    // Relax check around `showIfCollapsed` decorations to also include +/- 1
    // character (`contentHoverComputer.ts:52-57`).
    if start_column > anchor_range.start_column + 1 ||
      anchor_range.end_column - 1 > end_column {
      continue
    }
    parts.push(
      MarkerHover(
        range=Range(line_number, start_column, line_number, end_column),
        marker~,
      ),
    )
  }
  parts
}

///|
/// Adapts the marker participant to the generic hover pipeline. Marker hover is
/// fully synchronous, so the three optional source members remain absent.
pub fn MarkerHoverParticipant::hover_participant_handle(
  self : MarkerHoverParticipant,
) -> HoverParticipantHandle {
  HoverParticipantHandle(0, ctx => self.compute_sync(ctx))
}

///|
/// Hover participant that queries registered markdown/plaintext hover providers.
pub struct MarkdownHoverParticipant {
  priv languages : @languages.LanguageHandle
}

///|
/// Creates the markdown hover participant over the language features registry.
#alias(new, deprecated)
pub fn MarkdownHoverParticipant::MarkdownHoverParticipant(
  languages : @languages.LanguageHandle,
) -> MarkdownHoverParticipant {
  { languages, }
}

///|
/// Queries language hover providers at the anchor position — `computeAsync`
/// (`markdownHoverParticipant.ts:168-171`): range anchors only, queried at
/// `anchor.range.getStartPosition()` (the mouse position). The languages
/// registry is offset-addressed, so the conversion happens at this query
/// boundary only.
async fn MarkdownHoverParticipant::compute_async(
  self : MarkdownHoverParticipant,
  ctx : HoverComputeContext,
  token : @language.CancellationToken,
) -> Array[HoverPart] noraise {
  if token.is_cancellation_requested() {
    return []
  }
  guard ctx.anchor is HoverRangeAnchor(range=anchor_range, ..) else {
    return []
  }
  let offset = ctx.model.get_offset_at(anchor_range.get_start_position())
  let hover = self.languages.hover_at(ctx.model, offset, token~)
  if token.is_cancellation_requested() {
    return []
  }
  match hover {
    Some(hover) =>
      if hover.contents.length() == 0 {
        []
      } else {
        [MarkdownHover(range=hover.range, contents=hover.contents, ordinal=100)]
      }
    None => []
  }
}

///|
/// Markdown's source-shaped loading placeholder while its provider request is
/// pending.
fn MarkdownHoverParticipant::create_loading_message(
  _self : MarkdownHoverParticipant,
  anchor : HoverAnchor,
) -> HoverPart? {
  Some(LoadingHover(range=anchor.range(), message="Loading..."))
}

///|
/// Adapts the Markdown participant to the generic hover pipeline. The required
/// synchronous callback returns no parts, as in Monaco; anchor suggestion is
/// absent, while async computation and loading-message production are present.
pub fn MarkdownHoverParticipant::hover_participant_handle(
  self : MarkdownHoverParticipant,
) -> HoverParticipantHandle {
  HoverParticipantHandle(
    100,
    _ctx => [],
    compute_async=(ctx, token) => self.compute_async(ctx, token),
    create_loading_message=anchor => self.create_loading_message(anchor),
  )
}

///|
/// Coordinates hover participants for one viewer service set.
pub struct ContentHoverComputer {
  participants : Array[HoverParticipantHandle]
}

///|
/// Creates a content-hover computer, instantiating the registered default
/// participants with the given services — Monaco's
/// `ContentHoverWidgetWrapper._initializeHoverParticipants`.
#alias(new, deprecated)
pub fn ContentHoverComputer::ContentHoverComputer(
  services : HoverParticipantServices,
) -> ContentHoverComputer {
  { participants: hover_participant_registry.build_all(services) }
}

///|
/// Selects the first participant-provided loading message in participant order,
/// matching `ContentHoverWidgetWrapper._addLoadingMessage`'s absent/null/present
/// control flow.
pub fn ContentHoverComputer::create_loading_message(
  self : ContentHoverComputer,
  anchor : HoverAnchor,
) -> HoverPart? {
  for participant in self.participants {
    match participant.create_loading_message {
      Some(create_loading_message) =>
        match create_loading_message(anchor) {
          Some(message) => return Some(message)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
/// Computes hover parts that are immediately available from viewer state.
pub fn ContentHoverComputer::compute_sync(
  self : ContentHoverComputer,
  model : @model.TextModel,
  anchor : HoverAnchor,
  source? : HoverStartSource = HoverStartMouse,
) -> ComputedHover? {
  let ctx : HoverComputeContext = {
    model,
    anchor,
    source,
    line_decorations: hover_line_decorations(model, anchor),
  }
  let parts : Array[HoverPart] = []
  for participant in self.participants {
    parts.append((participant.compute_sync)(ctx))
  }
  computed_hover_from_parts(anchor.range(), parts)
}

///|
/// Computes hover parts that may require provider calls.
pub async fn ContentHoverComputer::compute_async(
  self : ContentHoverComputer,
  model : @model.TextModel,
  anchor : HoverAnchor,
  source? : HoverStartSource = HoverStartMouse,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  is_current? : () -> Bool = () => true,
) -> ComputedHover? noraise {
  if token.is_cancellation_requested() || !is_current() {
    return None
  }
  let ctx : HoverComputeContext = {
    model,
    anchor,
    source,
    line_decorations: hover_line_decorations(model, anchor),
  }
  let parts : Array[HoverPart] = []
  for participant in self.participants {
    match participant.compute_async {
      Some(compute_async) => {
        if token.is_cancellation_requested() || !is_current() {
          return None
        }
        let participant_parts = compute_async(ctx, token)
        if token.is_cancellation_requested() || !is_current() {
          return None
        }
        parts.append(participant_parts)
      }
      None => ()
    }
  }
  computed_hover_from_parts(anchor.range(), parts)
}

///|
/// Streams asynchronous hover parts participant by participant, invoking `emit`
/// with each participant's non-empty parts as they resolve. Mirrors Monaco
/// `HoverOperation`'s incremental `computeAsync` consumption: results are fed to
/// the operation as they arrive rather than gathered into a single resolution.
pub async fn ContentHoverComputer::compute_async_each(
  self : ContentHoverComputer,
  model : @model.TextModel,
  anchor : HoverAnchor,
  source? : HoverStartSource = HoverStartMouse,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  is_current? : () -> Bool = () => true,
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
  emit~ : (Array[HoverPart]) -> Unit,
) -> Unit noraise {
  if token.is_cancellation_requested() || !is_current() {
    return
  }
  let ctx : HoverComputeContext = {
    model,
    anchor,
    source,
    line_decorations: hover_line_decorations(model, anchor),
  }
  // Package callers use the runtime-neutral sequential runner. The browser
  // host injects its Promise runner, starting every participant concurrently
  // without coupling this multi-target package to the JS or moonbitlang/async
  // runtimes. Emits therefore follow completion order under the host runner.
  let tasks : Array[async () -> Unit] = []
  for participant in self.participants {
    match participant.compute_async {
      Some(compute_async) =>
        tasks.push(() => {
          if token.is_cancellation_requested() || !is_current() {
            return
          }
          let parts = compute_async(ctx, token)
          if token.is_cancellation_requested() || !is_current() {
            return
          }
          if parts.length() > 0 {
            emit(parts)
          }
        })
      None => ()
    }
  }
  run_tasks(tasks) catch {
    _ => ()
  }
}

///|
/// Union range of accumulated hover parts, falling back to the anchor range
/// when there are none. The hover widget anchors on this span.
pub fn hover_parts_range(
  parts : Array[HoverPart],
  fallback : @base_common.Range,
) -> @base_common.Range {
  let mut range = fallback
  for part in parts {
    range = union_range(range, hover_part_range(part))
  }
  range
}

///|
fn computed_hover_from_parts(
  fallback_range : @base_common.Range,
  parts : Array[HoverPart],
) -> ComputedHover? {
  if parts.length() == 0 {
    return None
  }
  let sorted = sort_hover_parts_stably(parts)
  let mut range = fallback_range
  for part in sorted {
    range = union_range(range, hover_part_range(part))
  }
  Some({ range, parts: sorted })
}

///|
/// JavaScript's source sort is stable while MoonBit's `Array::sort_by` is not.
/// Carry the arrival index as the final comparator key so equal participant
/// ordinal/range-start parts retain provider completion order on every target.
fn sort_hover_parts_stably(parts : Array[HoverPart]) -> Array[HoverPart] {
  let indexed : Array[(Int, HoverPart)] = []
  for index, part in parts {
    indexed.push((index, part))
  }
  indexed.sort_by((left, right) => {
    let order = compare_hover_parts(left.1, right.1)
    if order != 0 {
      order
    } else {
      left.0 - right.0
    }
  })
  indexed.map(item => item.1)
}

///|
/// Orders hover parts by participant ordinal, then by start offset. Exposed for
/// the viewer core's hover controller, which merges late-arriving async parts
/// into an already-shown hover.
pub fn compare_hover_parts(left : HoverPart, right : HoverPart) -> Int {
  let ordinal = hover_part_ordinal(left) - hover_part_ordinal(right)
  if ordinal != 0 {
    ordinal
  } else {
    @base_common.Range::compare_ranges_using_starts(
      hover_part_range(left),
      hover_part_range(right),
    )
  }
}

///|
fn hover_part_ordinal(part : HoverPart) -> Int {
  match part {
    MarkdownHover(ordinal~, ..) => ordinal
    MarkerHover(_) => 0
    // `MarkdownHoverParticipant.createLoadingMessage` uses ordinal 2000 so
    // the placeholder follows resolved marker/markdown content.
    LoadingHover(_) => 2000
  }
}

///|
fn union_range(
  left : @base_common.Range,
  right : @base_common.Range,
) -> @base_common.Range {
  @base_common.Range::plus_range(left, right)
}
