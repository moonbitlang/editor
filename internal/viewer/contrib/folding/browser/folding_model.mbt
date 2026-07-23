// Port of `vscode/src/vs/editor/contrib/folding/browser/foldingModel.ts`
// (checked-in vscode submodule): the
// `FoldingModel` (regions + their tracking editor decorations + the change
// emitter) and the collapse-state helper functions the commands drive.
//
// Omissions: `getMemento`/`applyMemento`/`_getLinesChecksum` (view-state
// persistence has no consumer in the readonly viewer).

///|
/// The exact decoration capabilities `FoldingModel` writes through — Monaco's
/// structural `IDecorationProvider` (`foldingModel.ts:13`). This is a closed
/// function record instead of a MoonBit trait object: the source boundary is
/// three callbacks, not a runtime-subtyped object hierarchy.
pub struct FoldingDecorationAccess {
  priv get_decoration_option_ : (Bool, Bool, Bool) -> @model.ModelDecorationOptions
  priv change_decorations_ : ((@model.ModelDecorationsChangeAccessor) -> Unit) -> Unit
  priv remove_decorations_ : (Array[String]) -> Unit
}

///|
fn FoldingDecorationAccess::new(
  get_decoration_option : (Bool, Bool, Bool) -> @model.ModelDecorationOptions,
  change_decorations : ((@model.ModelDecorationsChangeAccessor) -> Unit) -> Unit,
  remove_decorations : (Array[String]) -> Unit,
) -> FoldingDecorationAccess {
  {
    get_decoration_option_: get_decoration_option,
    change_decorations_: change_decorations,
    remove_decorations_: remove_decorations,
  }
}

///|
fn FoldingDecorationAccess::get_decoration_option(
  self : FoldingDecorationAccess,
  is_collapsed : Bool,
  is_hidden : Bool,
  is_manual : Bool,
) -> @model.ModelDecorationOptions {
  (self.get_decoration_option_)(is_collapsed, is_hidden, is_manual)
}

///|
fn FoldingDecorationAccess::change_decorations(
  self : FoldingDecorationAccess,
  callback : (@model.ModelDecorationsChangeAccessor) -> Unit,
) -> Unit {
  (self.change_decorations_)(callback)
}

///|
fn FoldingDecorationAccess::remove_decorations(
  self : FoldingDecorationAccess,
  decoration_ids : Array[String],
) -> Unit {
  (self.remove_decorations_)(decoration_ids)
}

///|
/// `FoldingModelChangeEvent` (`foldingModel.ts:19`).
pub struct FoldingModelChangeEvent {
  model : FoldingModel
  collapse_state_changed : Array[FoldingRegion]?
}

///|
/// The folding state of one text model — Monaco's `FoldingModel`
/// (`foldingModel.ts:32`): the current `FoldingRegions` plus one editor
/// decoration per region. The decorations both render the fold UI (chevron,
/// highlight, `⋯`) and anchor the regions across edits.
pub struct FoldingModel {
  priv text_model : @model.TextModel
  priv decoration_access : FoldingDecorationAccess
  priv mut regions : FoldingRegions
  priv mut editor_decoration_ids : Array[String]
  priv update_event_emitter : @base_common.Emitter[FoldingModelChangeEvent]
}

///|
#alias(new, deprecated)
pub fn FoldingModel::FoldingModel(
  text_model : @model.TextModel,
  decoration_access : FoldingDecorationAccess,
) -> FoldingModel {
  {
    text_model,
    decoration_access,
    regions: FoldingRegions(FixedArray::make(0, 0U), FixedArray::make(0, 0U)),
    editor_decoration_ids: [],
    update_event_emitter: Emitter(),
  }
}

///|
/// The `regions` getter.
pub fn FoldingModel::regions(self : FoldingModel) -> FoldingRegions {
  self.regions
}

///|
/// The `textModel` getter.
pub fn FoldingModel::text_model(self : FoldingModel) -> @model.TextModel {
  self.text_model
}

///|
/// `onDidChange` subscription.
pub fn FoldingModel::on_did_change(
  self : FoldingModel,
  listener : (FoldingModelChangeEvent) -> Unit,
) -> @base_common.Disposable {
  self.update_event_emitter.event(listener)
}

///|
/// `toggleCollapseState` (`foldingModel.ts:53`): flips each region's
/// collapse bit and rewrites the decoration options of every region whose
/// rendering that dirties (regions nested under a new fold become hidden,
/// under an unfold visible again).
pub fn FoldingModel::toggle_collapse_state(
  self : FoldingModel,
  toggled_regions : Array[FoldingRegion],
) -> Unit {
  if toggled_regions.length() == 0 {
    return
  }
  let toggled_regions = toggled_regions.copy()
  toggled_regions.sort_by((r1, r2) => r1.region_index() - r2.region_index())
  let processed : Map[String, Bool] = Map([])
  self.decoration_access.change_decorations(accessor => {
    // index from [0 ... this.regions.length]
    let k : Ref[Int] = { val: 0 }
    // end of the range where decorations need to be updated
    let dirty_region_end_line : Ref[Int] = { val: -1 }
    // the end of the last hidden lines
    let last_hidden_line : Ref[Int] = { val: -1 }
    let update_decorations_until = (index : Int) => {
      while k.val < index {
        let end_line_number = self.regions.get_end_line_number(k.val)
        let is_collapsed = self.regions.is_collapsed(k.val)
        if end_line_number <= dirty_region_end_line.val {
          let is_manual = self.regions.get_source(k.val) != Provider
          (accessor.change_decoration_options)(
            self.editor_decoration_ids[k.val],
            self.decoration_access.get_decoration_option(
              is_collapsed,
              end_line_number <= last_hidden_line.val,
              is_manual,
            ),
          )
        }
        if is_collapsed && end_line_number > last_hidden_line.val {
          last_hidden_line.val = end_line_number
        }
        k.val += 1
      }
    }
    for region in toggled_regions {
      let index = region.region_index()
      if index < self.editor_decoration_ids.length() {
        let editor_decoration_id = self.editor_decoration_ids[index]
        if !(processed.get(editor_decoration_id) is Some(true)) {
          processed[editor_decoration_id] = true
          // update all decorations up to current index using the old
          // dirtyRegionEndLine
          update_decorations_until(index)
          let new_collapse_state = !self.regions.is_collapsed(index)
          self.regions.set_collapsed(index, new_collapse_state)
          dirty_region_end_line.val = dirty_region_end_line.val.max(
            self.regions.get_end_line_number(index),
          )
        }
      }
    }
    update_decorations_until(self.regions.length())
  })
  self.update_event_emitter.fire({
    model: self,
    collapse_state_changed: Some(toggled_regions),
  })
}

///|
/// `removeManualRanges` (`foldingModel.ts:97`).
pub fn FoldingModel::remove_manual_ranges(
  self : FoldingModel,
  ranges : Array[LineRange],
) -> Unit {
  let new_folding_ranges : Array[FoldRange] = []
  let intersects = (fold_range : FoldRange) => {
    for range in ranges {
      if !(range.start_line_number > fold_range.end_line_number ||
        fold_range.start_line_number > range.end_line_number) {
        return true
      }
    }
    false
  }
  for i in 0..<self.regions.length() {
    let fold_range = self.regions.to_fold_range(i)
    if fold_range.source == Provider || !intersects(fold_range) {
      new_folding_ranges.push(fold_range)
    }
  }
  self.update_post(FoldingRegions::from_fold_ranges(new_folding_ranges))
}

///|
/// `update` (`foldingModel.ts:116`): reconciles freshly computed provider
/// regions with the currently folded/manual ranges.
pub fn FoldingModel::update(
  self : FoldingModel,
  new_regions : FoldingRegions,
  selection? : SelectedLines,
) -> Unit {
  let folded_or_manual_ranges = self.current_folded_or_manual_ranges(selection?)
  let new_ranges = FoldingRegions::sanitize_and_merge(
    Regions(new_regions),
    Ranges(folded_or_manual_ranges),
    Some(self.text_model.snapshot.line_count()),
    selection?,
  )
  self.update_post(FoldingRegions::from_fold_ranges(new_ranges))
}

///|
/// `updatePost` (`foldingModel.ts:122`): adopts the new regions and rewrites
/// every region's tracking decoration. The decoration spans the fold —
/// header line's last column through the end line — so edits move the
/// region with the text.
pub fn FoldingModel::update_post(
  self : FoldingModel,
  new_regions : FoldingRegions,
) -> Unit {
  let new_editor_decorations : Array[@model.ModelDeltaDecoration] = []
  let mut last_hidden_line = -1
  for index in 0..<new_regions.length() {
    let start_line_number = new_regions.get_start_line_number(index)
    let end_line_number = new_regions.get_end_line_number(index)
    let is_collapsed = new_regions.is_collapsed(index)
    let is_manual = new_regions.get_source(index) != Provider
    let decoration_range : @base_common.Range = Range(
      start_line_number,
      self.text_model.snapshot.get_line_max_column(start_line_number),
      end_line_number,
      self.text_model.snapshot.get_line_max_column(end_line_number) + 1,
    )
    new_editor_decorations.push({
      range: decoration_range,
      options: self.decoration_access.get_decoration_option(
        is_collapsed,
        end_line_number <= last_hidden_line,
        is_manual,
      ),
    })
    if is_collapsed && end_line_number > last_hidden_line {
      last_hidden_line = end_line_number
    }
  }
  self.decoration_access.change_decorations(accessor => {
    self.editor_decoration_ids = (accessor.delta_decorations)(
      self.editor_decoration_ids,
      new_editor_decorations,
    )
  })
  self.regions = new_regions
  self.update_event_emitter.fire({ model: self, collapse_state_changed: None })
}

///|
/// `_currentFoldedOrManualRanges` (`foldingModel.ts:146`): the folded and
/// user-defined ranges, read back through their tracking decorations so
/// edits since the last update are reflected.
fn FoldingModel::current_folded_or_manual_ranges(
  self : FoldingModel,
  selection? : SelectedLines,
) -> Array[FoldRange] {
  let folded_ranges : Array[FoldRange] = []
  for i in 0..<self.regions.length() {
    let mut is_collapsed = self.regions.is_collapsed(i)
    let source = self.regions.get_source(i)
    if is_collapsed || source != Provider {
      let fold_range = self.regions.to_fold_range(i)
      match
        self.text_model.get_decoration_range(self.editor_decoration_ids[i]) {
        Some(dec_range) => {
          if is_collapsed &&
            selection is Some(sel) &&
            (sel.starts_inside)(
              dec_range.start_line_number + 1,
              dec_range.end_line_number,
            ) {
            is_collapsed = false // uncollapse is the range is blocked
          }
          folded_ranges.push({
            start_line_number: dec_range.start_line_number,
            end_line_number: dec_range.end_line_number,
            type_: fold_range.type_,
            is_collapsed,
            source,
          })
        }
        None => ()
      }
    }
  }
  folded_ranges
}

///|
/// `dispose` (`foldingModel.ts:231`).
pub fn FoldingModel::dispose(self : FoldingModel) -> Unit {
  self.decoration_access.remove_decorations(self.editor_decoration_ids)
}

///|
/// `getAllRegionsAtLine` (`foldingModel.ts:236`): the innermost region at
/// `line_number` and its parents, innermost first, optionally filtered by
/// `(region, level)` (level 1 = innermost).
pub fn FoldingModel::get_all_regions_at_line(
  self : FoldingModel,
  line_number : Int,
  filter? : (FoldingRegion, Int) -> Bool,
) -> Array[FoldingRegion] {
  let result : Array[FoldingRegion] = []
  let mut index = self.regions.find_range(line_number)
  let mut level = 1
  while index >= 0 {
    let current = self.regions.to_region(index)
    match filter {
      Some(filter) => if filter(current, level) { result.push(current) }
      None => result.push(current)
    }
    level += 1
    index = current.parent_index()
  }
  result
}

///|
/// `getRegionAtLine` (`foldingModel.ts:253`): the innermost region at
/// `line_number`.
pub fn FoldingModel::get_region_at_line(
  self : FoldingModel,
  line_number : Int,
) -> FoldingRegion? {
  let index = self.regions.find_range(line_number)
  if index >= 0 {
    return Some(self.regions.to_region(index))
  }
  None
}

///|
/// The `RegionFilter | RegionFilterWithLevel` union of `getRegionsInside`
/// (`foldingModel.ts:263,301-302`): the with-level form tracks the nesting
/// depth relative to `region` with a stack.
pub(all) enum RegionFilter {
  RegionFilter((FoldingRegion) -> Bool)
  RegionFilterWithLevel((FoldingRegion, Int) -> Bool)
}

///|
/// `getRegionsInside` (`foldingModel.ts:263`): every region strictly inside
/// `region` (or all regions for `None`), in document order.
pub fn FoldingModel::get_regions_inside(
  self : FoldingModel,
  region : FoldingRegion?,
  filter? : RegionFilter,
) -> Array[FoldingRegion] {
  let result : Array[FoldingRegion] = []
  let index = match region {
    Some(region) => region.region_index() + 1
    None => 0
  }
  let end_line_number = match region {
    Some(region) => region.end_line_number()
    None => 0x7FFFFFFF // Number.MAX_VALUE
  }
  match filter {
    Some(RegionFilterWithLevel(filter)) => {
      let level_stack : Array[FoldingRegion] = []
      for i in index..<self.regions.length() {
        let current = self.regions.to_region(i)
        if self.regions.get_start_line_number(i) < end_line_number {
          while level_stack.length() > 0 &&
                !current.contained_by({
                  start_line_number: level_stack[level_stack.length() - 1].start_line_number(),
                  end_line_number: level_stack[level_stack.length() - 1].end_line_number(),
                }) {
            level_stack.pop() |> ignore
          }
          level_stack.push(current)
          if filter(current, level_stack.length()) {
            result.push(current)
          }
        } else {
          break
        }
      }
    }
    _ => {
      let plain_filter = match filter {
        Some(RegionFilter(f)) => Some(f)
        _ => None
      }
      for i in index..<self.regions.length() {
        let current = self.regions.to_region(i)
        if self.regions.get_start_line_number(i) < end_line_number {
          match plain_filter {
            Some(f) => if f(current) { result.push(current) }
            None => result.push(current)
          }
        } else {
          break
        }
      }
    }
  }
  result
}

///|
/// Collapse or expand the regions at the given locations — the free
/// `toggleCollapseState` (`foldingModel.ts:310`). `levels` = 1 impacts only
/// the innermost region at each location.
pub fn toggle_collapse_state(
  folding_model : FoldingModel,
  levels : Int,
  line_numbers : Array[Int],
) -> Unit {
  let to_toggle : Array[FoldingRegion] = []
  for line_number in line_numbers {
    match folding_model.get_region_at_line(line_number) {
      Some(region) => {
        let do_collapse = !region.is_collapsed()
        to_toggle.push(region)
        if levels > 1 {
          let regions_inside = folding_model.get_regions_inside(
            Some(region),
            filter=RegionFilterWithLevel((r, level) => {
              r.is_collapsed() != do_collapse && level < levels
            }),
          )
          to_toggle.append(regions_inside)
        }
      }
      None => ()
    }
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateLevelsDown` (`foldingModel.ts:333`): collapse or expand
/// the regions at the given locations including `levels` levels of
/// children; all regions when `line_numbers` is absent.
pub fn set_collapse_state_levels_down(
  folding_model : FoldingModel,
  do_collapse : Bool,
  levels? : Int = 0x7FFFFFFF,
  line_numbers? : Array[Int],
) -> Unit {
  let to_toggle : Array[FoldingRegion] = []
  match line_numbers {
    Some(line_numbers) if line_numbers.length() > 0 =>
      for line_number in line_numbers {
        match folding_model.get_region_at_line(line_number) {
          Some(region) => {
            if region.is_collapsed() != do_collapse {
              to_toggle.push(region)
            }
            if levels > 1 {
              let regions_inside = folding_model.get_regions_inside(
                Some(region),
                filter=RegionFilterWithLevel((r, level) => {
                  r.is_collapsed() != do_collapse && level < levels
                }),
              )
              to_toggle.append(regions_inside)
            }
          }
          None => ()
        }
      }
    _ => {
      let regions_inside = folding_model.get_regions_inside(
        None,
        filter=RegionFilterWithLevel((r, level) => {
          r.is_collapsed() != do_collapse && level < levels
        }),
      )
      to_toggle.append(regions_inside)
    }
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateLevelsUp` (`foldingModel.ts:361`): collapse or expand
/// the regions at the given locations including `levels` levels of parents.
pub fn set_collapse_state_levels_up(
  folding_model : FoldingModel,
  do_collapse : Bool,
  levels : Int,
  line_numbers : Array[Int],
) -> Unit {
  let to_toggle : Array[FoldingRegion] = []
  for line_number in line_numbers {
    let regions = folding_model.get_all_regions_at_line(line_number, filter=(
      region,
      level,
    ) => region.is_collapsed() != do_collapse && level <= levels)
    to_toggle.append(regions)
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateUp` (`foldingModel.ts:375`): collapse or expand the
/// innermost not-yet-matching region at each location.
pub fn set_collapse_state_up(
  folding_model : FoldingModel,
  do_collapse : Bool,
  line_numbers : Array[Int],
) -> Unit {
  let to_toggle : Array[FoldingRegion] = []
  for line_number in line_numbers {
    let regions = folding_model.get_all_regions_at_line(line_number, filter=(
      region,
      _level,
    ) => region.is_collapsed() != do_collapse)
    if regions.length() > 0 {
      to_toggle.push(regions[0])
    }
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateAtLevel` (`foldingModel.ts:391`): folds or unfolds all
/// regions at `fold_level` (1 = top level), except those containing a
/// blocked line.
pub fn set_collapse_state_at_level(
  folding_model : FoldingModel,
  fold_level : Int,
  do_collapse : Bool,
  blocked_line_numbers : Array[Int],
) -> Unit {
  let filter = RegionFilterWithLevel((region, level) => {
    level == fold_level &&
    region.is_collapsed() != do_collapse &&
    !blocked_line_numbers.iter().any(line => region.contains_line(line))
  })
  let to_toggle = folding_model.get_regions_inside(None, filter~)
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateForRest` (`foldingModel.ts:402`): folds or unfolds all
/// regions except those containing or contained by a blocked line's region.
pub fn set_collapse_state_for_rest(
  folding_model : FoldingModel,
  do_collapse : Bool,
  blocked_line_numbers : Array[Int],
) -> Unit {
  let filtered_regions : Array[FoldingRegion] = []
  for line_number in blocked_line_numbers {
    let regions = folding_model.get_all_regions_at_line(line_number)
    if regions.length() > 0 {
      filtered_regions.push(regions[0])
    }
  }
  let filter = RegionFilter(region => {
    filtered_regions
    .iter()
    .all(filtered_region => {
      let region_line_range : LineRange = {
        start_line_number: region.start_line_number(),
        end_line_number: region.end_line_number(),
      }
      let filtered_line_range : LineRange = {
        start_line_number: filtered_region.start_line_number(),
        end_line_number: filtered_region.end_line_number(),
      }
      !filtered_region.contained_by(region_line_range) &&
      !region.contained_by(filtered_line_range)
    }) &&
    region.is_collapsed() != do_collapse
  })
  let to_toggle = folding_model.get_regions_inside(None, filter~)
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateForMatchingLines` (`foldingModel.ts:419`): folds all
/// regions whose start line matches. The source's `RegExp` is a predicate
/// here.
pub fn set_collapse_state_for_matching_lines(
  folding_model : FoldingModel,
  matches : (String) -> Bool,
  do_collapse : Bool,
) -> Unit {
  let editor_model = folding_model.text_model()
  let regions = folding_model.regions()
  let to_toggle : Array[FoldingRegion] = []
  for i = regions.length() - 1; i >= 0; i = i - 1 {
    if do_collapse != regions.is_collapsed(i) {
      let start_line_number = regions.get_start_line_number(i)
      if matches(editor_model.snapshot.line_text(start_line_number - 1)) {
        to_toggle.push(regions.to_region(i))
      }
    }
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `setCollapseStateForType` (`foldingModel.ts:438`): folds all regions of
/// the given type.
pub fn set_collapse_state_for_type(
  folding_model : FoldingModel,
  type_ : String,
  do_collapse : Bool,
) -> Unit {
  let regions = folding_model.regions()
  let to_toggle : Array[FoldingRegion] = []
  for i = regions.length() - 1; i >= 0; i = i - 1 {
    if do_collapse != regions.is_collapsed(i) &&
      regions.get_type(i) is Some(t) &&
      t == type_ {
      to_toggle.push(regions.to_region(i))
    }
  }
  folding_model.toggle_collapse_state(to_toggle)
}

///|
/// `getParentFoldLine` (`foldingModel.ts:456`): the start line of the fold
/// enclosing the fold at `line_number`.
pub fn get_parent_fold_line(
  line_number : Int,
  folding_model : FoldingModel,
) -> Int? {
  let mut start_line_number : Int? = None
  let folding_region = folding_model.get_region_at_line(line_number)
  if folding_region is Some(region) {
    start_line_number = Some(region.start_line_number())
    // If current line is not the start of the current fold, go to top line
    // of current fold. If not, go to parent fold
    if line_number == region.start_line_number() {
      let parent_folding_idx = region.parent_index()
      if parent_folding_idx != -1 {
        start_line_number = Some(
          folding_model.regions().get_start_line_number(parent_folding_idx),
        )
      } else {
        start_line_number = None
      }
    }
  }
  start_line_number
}

///|
/// `getPreviousFoldLine` (`foldingModel.ts:481`): the start line of the
/// previous fold at the same nesting level.
pub fn get_previous_fold_line(
  line_number : Int,
  folding_model : FoldingModel,
) -> Int? {
  let regions = folding_model.regions()
  let mut folding_region = folding_model.get_region_at_line(line_number)
  // If on the folding range start line, go to previous sibling.
  if folding_region is Some(region) && region.start_line_number() == line_number {
    // Find min line number to stay within parent.
    let expected_parent_index = region.parent_index()
    let mut min_line_number = 0
    if expected_parent_index != -1 {
      min_line_number = regions.get_start_line_number(expected_parent_index)
    }
    // Find fold at same level.
    while folding_region is Some(current) {
      if current.region_index() > 0 {
        let previous = regions.to_region(current.region_index() - 1)
        folding_region = Some(previous)
        // Keep at same level.
        if previous.start_line_number() <= min_line_number {
          return None
        } else if previous.parent_index() == expected_parent_index {
          return Some(previous.start_line_number())
        }
      } else {
        return None
      }
    }
    // Go to last fold that's before the current line.
  } else if regions.length() > 0 {
    folding_region = Some(regions.to_region(regions.length() - 1))
    while folding_region is Some(current) {
      // Found fold before current line.
      if current.start_line_number() < line_number {
        return Some(current.start_line_number())
      }
      if current.region_index() > 0 {
        folding_region = Some(regions.to_region(current.region_index() - 1))
      } else {
        folding_region = None
      }
    }
  }
  None
}

///|
/// `getNextFoldLine` (`foldingModel.ts:539`): the start line of the next
/// fold at the same nesting level. (The source's walk reads one index past
/// the end — harmless on a JS typed array; the port bounds the walk.)
pub fn get_next_fold_line(
  line_number : Int,
  folding_model : FoldingModel,
) -> Int? {
  let regions = folding_model.regions()
  let mut folding_region = folding_model.get_region_at_line(line_number)
  // If on the folding range start line, go to next sibling.
  if folding_region is Some(region) && region.start_line_number() == line_number {
    // Find max line number to stay within parent.
    let expected_parent_index = region.parent_index()
    let mut max_line_number = 0
    if expected_parent_index != -1 {
      max_line_number = regions.get_end_line_number(expected_parent_index)
    } else if regions.length() == 0 {
      return None
    } else {
      max_line_number = regions.get_end_line_number(regions.length() - 1)
    }
    // Find fold at same level.
    while folding_region is Some(current) {
      if current.region_index() + 1 < regions.length() {
        let next = regions.to_region(current.region_index() + 1)
        folding_region = Some(next)
        // Keep at same level.
        if next.start_line_number() >= max_line_number {
          return None
        } else if next.parent_index() == expected_parent_index {
          return Some(next.start_line_number())
        }
      } else {
        return None
      }
    }
    // Go to first fold that's after the current line.
  } else if regions.length() > 0 {
    folding_region = Some(regions.to_region(0))
    while folding_region is Some(current) {
      // Found fold after current line.
      if current.start_line_number() > line_number {
        return Some(current.start_line_number())
      }
      if current.region_index() + 1 < regions.length() {
        folding_region = Some(regions.to_region(current.region_index() + 1))
      } else {
        folding_region = None
      }
    }
  }
  None
}
