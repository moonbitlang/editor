// The `Viewer::` half of Monaco's `FoldingController`
// (`vscode/src/vs/editor/contrib/folding/browser/folding.ts`, vscode
// checked-in submodule): the
// event-handler bodies that need the editor. The controller *state* is owned
// by the Viewer's central contribution entry; editor-facing glue stays beside
// the root-owned Viewer state so the folding implementation remains below the
// public facade.
//
// Deviations beyond the contrib file's recorded omissions:
//   * `triggerFoldingModelChanged` runs synchronously — no `Delayer`
//     debounce and no cancelable promise (the indent provider is sync).
//   * `revealCursor` runs directly on cursor changes — no 200ms
//     `RunOnceScheduler`.

///|
/// The typed central-registry lookup backing Monaco's
/// `FoldingController.get`.
fn Viewer::folding_controller(
  self : Viewer,
) -> @folding_browser.FoldingController? {
  match self.contributions.lookup(@folding_browser.FOLDING_CONTROLLER_ID) {
    Some(entry) =>
      match entry.instance {
        Folding(controller) => Some(controller)
        _ => None
      }
    _ => None
  }
}

///|
/// `onModelChanged` (`folding.ts:227`).
fn Viewer::folding_on_model_changed(self : Viewer) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  controller.clear_local()
  let options = self.get_options()
  guard options.folding && self.get_model() is Some(model) else { return }
  let decoration_provider = @folding_browser.FoldingDecorationProvider(
    model,
    owner_id=self.editor_id,
  )
  decoration_provider.update_options(
    show_folding_controls=options.show_folding_controls,
    show_folding_highlights=options.folding_highlight,
  )
  controller.folding_decoration_provider = Some(decoration_provider)
  let folding_model = @folding_browser.FoldingModel(
    model,
    decoration_provider.access(),
  )
  controller.folding_model = Some(folding_model)
  let hidden_range_model = @folding_browser.HiddenRangeModel(folding_model)
  controller.hidden_range_model = Some(hidden_range_model)
  controller.local_to_dispose.push(
    hidden_range_model.on_did_change(hidden_ranges => {
      self.folding_on_hidden_ranges_changes(hidden_ranges)
    }),
  )
  self.trigger_folding_model_changed()
}

///|
/// The `onDidChangeConfiguration` cluster (`folding.ts:155-180`), reduced to
/// the option axes the viewer carries.
fn Viewer::folding_on_configuration_changed(
  self : Viewer,
  previous : ViewerOptions,
) -> Unit {
  let options = self.get_options()
  if previous.folding != options.folding ||
    previous.folding_maximum_regions != options.folding_maximum_regions ||
    previous.tab_size != options.tab_size {
    self.folding_on_model_changed()
    return
  }
  if previous.show_folding_controls != options.show_folding_controls ||
    previous.folding_highlight != options.folding_highlight {
    match self.folding_controller() {
      Some(controller) =>
        match controller.folding_decoration_provider {
          Some(decoration_provider) => {
            decoration_provider.update_options(
              show_folding_controls=options.show_folding_controls,
              show_folding_highlights=options.folding_highlight,
            )
            self.trigger_folding_model_changed()
          }
          None => ()
        }
      None => ()
    }
  }
}

///|
/// `getRangeProvider` (`folding.ts:280`), indent strategy only.
fn Viewer::folding_range_provider(
  self : Viewer,
  controller : @folding_browser.FoldingController,
  editor_model : @model.TextModel,
) -> @folding_browser.IndentRangeProvider {
  match controller.range_provider {
    Some(provider) => provider
    None => {
      let indent_range_provider = @folding_browser.IndentRangeProvider(
        editor_model,
        self.services.languages,
        {
          limit: () => self.get_options().folding_maximum_regions,
          update: (_computed, _limited) => (),
        },
        tab_size=self.get_options().tab_size,
      )
      controller.range_provider = Some(indent_range_provider)
      indent_range_provider
    }
  }
}

///|
/// `triggerFoldingModelChanged` (`folding.ts:305`), synchronous: computes
/// the provider ranges and reconciles them into the folding model.
fn Viewer::trigger_folding_model_changed(self : Viewer) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  guard controller.folding_model is Some(folding_model) else { return }
  let provider = self.folding_range_provider(
    controller,
    folding_model.text_model(),
  )
  let folding_ranges = provider.compute()
  // some cursors might have moved into hidden regions, make sure they are
  // in expanded regions
  let selections = self.get_selections().unwrap_or([])
  folding_model.update(
    folding_ranges,
    selection=@folding_browser.to_selected_lines(selections),
  )
}

///|
/// `onHiddenRangesChanges` (`folding.ts:352`).
fn Viewer::folding_on_hidden_ranges_changes(
  self : Viewer,
  hidden_ranges : Array[@base_common.Range],
) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  if controller.hidden_range_model is Some(hidden_range_model) &&
    hidden_ranges.length() > 0 {
    match self.get_selections() {
      Some(selections) =>
        if hidden_range_model.adjust_selections(selections) {
          self.set_selections(selections)
        }
      None => ()
    }
  }
  self.set_hidden_areas(
    hidden_ranges,
    source=@folding_browser.FOLDING_CONTROLLER_ID,
  )
}

///|
/// `onCursorPositionChanged` + `revealCursor` (`folding.ts:364-394`),
/// without the source's 200ms scheduler: a cursor that lands in a hidden
/// range unfolds the regions hiding it.
fn Viewer::folding_on_cursor_position_changed(self : Viewer) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  guard controller.hidden_range_model is Some(hidden_range_model) else {
    return
  }
  guard controller.folding_model is Some(folding_model) else { return }
  if !hidden_range_model.has_ranges() {
    return
  }
  let selections = self.get_selections().unwrap_or([])
  if selections.length() > 0 {
    let to_toggle : Array[@folding_browser.FoldingRegion] = []
    for selection in selections {
      let line_number = selection.get_selection_start().line_number
      if hidden_range_model.is_hidden(line_number) {
        to_toggle.append(
          folding_model.get_all_regions_at_line(line_number, filter=(r, _level) => {
            r.is_collapsed() && line_number > r.start_line_number()
          }),
        )
      }
    }
    if to_toggle.length() > 0 {
      folding_model.toggle_collapse_state(to_toggle)
      self.folding_reveal(selections[0].get_position())
    }
  }
}

///|
/// `reveal` (`folding.ts:512`).
fn Viewer::folding_reveal(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  self.reveal_position_in_center_if_outside_viewport(position)
}

///|
/// `onEditorMouseDown` (`folding.ts:396-447`). Targets arrive model-space
/// (the public-event boundary converts), so `e.target.range` is Monaco's
/// `range` verbatim.
fn Viewer::folding_on_editor_mouse_down(
  self : Viewer,
  e : @editor_browser.EditorMouseEvent,
) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  controller.mouse_down_info = None
  guard controller.hidden_range_model is Some(hidden_range_model) else {
    return
  }
  guard e.target.range() is Some(range) else { return }
  if !e.event.left_button && !e.event.middle_button {
    return
  }
  let mut icon_clicked = false
  match e.target {
    MouseTargetMargin(type_=GutterLineDecorations, element~, detail~, ..) => {
      guard element is Some(element) else { return }
      guard element.to_html_element() is Some(html_element) else { return }
      let offset_left_in_gutter = html_element.get_offset_left()
      let gutter_offset_x = detail.offset_x - offset_left_in_gutter

      // TODO@joao TODO@alex TODO@martin this is such that we don't collide
      // with dirty diff
      if gutter_offset_x < 4.0 {
        // the whitespace between the border and the real folding icon border
        // is 4px
        return
      }
      icon_clicked = true
    }
    MouseTargetContentEmpty(detail~, ..) =>
      if self.get_options().unfold_on_click_after_end_of_line &&
        hidden_range_model.has_ranges() {
        if !detail.is_after_lines {
          // proceed: a click past the end of a real line's text
          ()
        } else {
          return
        }
      } else {
        return
      }
    MouseTargetContentText(..) => {
      guard self.get_model() is Some(model) else { return }
      if hidden_range_model.has_ranges() &&
        range.start_column ==
        model.snapshot.get_line_max_column(range.start_line_number) {
        // proceed: the click sits at/after the end of the line's text — on a
        // folded header that is the collapsed `⋯` after-content (the DOM
        // `offsetWidth` line width includes it, so the hit stays
        // CONTENT_TEXT)
        ()
      } else {
        return
      }
    }
    _ => return
  }
  controller.mouse_down_info = Some({
    line_number: range.start_line_number,
    icon_clicked,
  })
}

///|
/// `onEditorMouseUp` (`folding.ts:449-510`), including the previously
/// unreachable modifier variants (the reduced event carried no modifiers):
/// alt-click folds/unfolds the surrounding regions, middle- or shift-click
/// toggles recursively.
fn Viewer::folding_on_editor_mouse_up(
  self : Viewer,
  e : @editor_browser.EditorMouseEvent,
) -> Unit {
  guard self.folding_controller() is Some(controller) else { return }
  guard controller.folding_model is Some(folding_model) else { return }
  guard controller.mouse_down_info is Some(mouse_down_info) else { return }
  let line_number = mouse_down_info.line_number
  let icon_clicked = mouse_down_info.icon_clicked
  guard e.target.range() is Some(range) else { return }
  if range.start_line_number != line_number {
    return
  }
  if icon_clicked {
    if !(e.target.type_() is GutterLineDecorations) {
      return
    }
  } else {
    guard self.get_model() is Some(model) else { return }
    if range.start_column != model.snapshot.get_line_max_column(line_number) {
      return
    }
  }
  guard folding_model.get_region_at_line(line_number) is Some(region) else {
    return
  }
  if region.start_line_number() == line_number {
    let is_collapsed = region.is_collapsed()
    if icon_clicked || is_collapsed {
      let surrounding = e.event.alt_key
      let mut to_toggle : Array[@folding_browser.FoldingRegion] = []
      if surrounding {
        let region_line_range : @folding_browser.LineRange = {
          start_line_number: region.start_line_number(),
          end_line_number: region.end_line_number(),
        }
        let filter = @folding_browser.RegionFilter(other_region => {
          let other_line_range : @folding_browser.LineRange = {
            start_line_number: other_region.start_line_number(),
            end_line_number: other_region.end_line_number(),
          }
          !other_region.contained_by(region_line_range) &&
          !region.contained_by(other_line_range)
        })
        let to_maybe_toggle = folding_model.get_regions_inside(None, filter~)
        for r in to_maybe_toggle {
          if r.is_collapsed() {
            to_toggle.push(r)
          }
        }
        // if any surrounding regions are folded, unfold those. Otherwise,
        // fold all surrounding
        if to_toggle.length() == 0 {
          to_toggle = to_maybe_toggle
        }
      } else {
        let recursive = e.event.middle_button || e.event.shift_key
        if recursive {
          for r in folding_model.get_regions_inside(Some(region)) {
            if r.is_collapsed() == is_collapsed {
              to_toggle.push(r)
            }
          }
        }
        // when recursive, first only collapse all children. If all are
        // already folded or there are no children, also fold parent.
        if is_collapsed || !recursive || to_toggle.length() == 0 {
          to_toggle.push(region)
        }
      }
      folding_model.toggle_collapse_state(to_toggle)
      self.folding_reveal(Position(line_number, 1))
    }
  }
}
