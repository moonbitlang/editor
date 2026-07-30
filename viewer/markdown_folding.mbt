// Root-owned Markdown section-fold state. The document view owns only the
// control DOM and the visibility attribute; every policy decision -- which
// sections exist, what starts collapsed, what a reader override means, and how
// state survives an agent edit -- lives here, per
// docs/exec-plans/markdown-section-folding.md.

///|
/// One section's retained fold state. `fingerprint` is the exact body source
/// text at the time the record was written; reconciliation refuses to carry a
/// record onto a section whose body has changed.
///
/// The review asked for tri-state over a collapsed-key set so that a reader who
/// expands an auto-collapsed section is distinguishable from one who never
/// touched it. This record map subsumes that: a retained `collapsed=false`
/// record *is* that distinction, and because reconciliation never re-runs the
/// auto-fold policy, no separate override tag is observable. If a future policy
/// re-run is added, the explicit tag must return with it.
priv struct MarkdownFoldRecord {
  mut collapsed : Bool
  fingerprint : String
}

///|
/// Model-scoped fold state, keyed by the section reconciliation key
/// (`@markdown_core.markdown_section_keys`). Created empty per model
/// attachment and never carried across a model swap (plan decision D3).
priv struct MarkdownFoldState {
  mut source : String
  mut section_keys : Array[String]
  records : Map[String, MarkdownFoldRecord]
}

///|
fn MarkdownFoldState::MarkdownFoldState() -> MarkdownFoldState {
  { source: "", section_keys: [], records: Map([]) }
}

///|
/// Seeds the fold state for a freshly attached model: every section starts at
/// the auto-fold policy (`markdown_default_collapsed_sections`) with no reader
/// override, then the DOM is brought in line.
fn MarkdownBrowserData::initialize_markdown_folding(
  self : MarkdownBrowserData,
  source : String,
) -> Unit {
  let projection = self.view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let keys = @markdown_core.markdown_section_keys(sections, projection, source)
  let defaults = @markdown_core.markdown_default_collapsed_sections(
    projection, source,
  )
  self.fold.source = source
  self.fold.section_keys = keys
  self.fold.records.clear()
  for section_index, section in sections {
    guard section_index < keys.length() else { continue }
    self.fold.records[keys[section_index]] = {
      collapsed: defaults.contains(section_index),
      fingerprint: markdown_fold_fingerprint(section, source),
    }
  }
  self.view.set_section_fold_toggle_handler(section_index => {
    self.toggle_markdown_section(section_index) |> ignore
  })
  self.apply_markdown_folding()
}

///|
/// Conservative reconciliation after a source or theme reprojection (plan
/// principle P1: when uncertain, expand).
///
/// A record survives only when its key still resolves *and* the section's body
/// text is unchanged. A theme change trivially satisfies both, so fold state
/// is preserved exactly; an agent edit preserves state for untouched sections
/// and opens everything changed, new, or ambiguous. Newly appearing sections
/// are *not* auto-collapsed: the reader is presumably interested in what the
/// agent just wrote.
///
/// Runs inside the caller's hover-bridge replacement bracket, and therefore
/// must not call `layout_changed` itself: `before_projection_replaced` already
/// invalidated the pending request, and `after_projection_replaced` refreshes
/// diagnostics only after final visibility is installed here.
fn MarkdownBrowserData::reconcile_markdown_folding(
  self : MarkdownBrowserData,
  source : String,
) -> Unit {
  let projection = self.view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let keys = @markdown_core.markdown_section_keys(sections, projection, source)
  let retained : Map[String, MarkdownFoldRecord] = Map([])
  for section_index, section in sections {
    guard section_index < keys.length() else { continue }
    let key = keys[section_index]
    let fingerprint = markdown_fold_fingerprint(section, source)
    retained[key] = match self.fold.records.get(key) {
      Some(record) if record.fingerprint == fingerprint => record
      _ => { collapsed: false, fingerprint }
    }
  }
  self.fold.source = source
  self.fold.section_keys = keys
  self.fold.records.clear()
  for key, record in retained {
    self.fold.records[key] = record
  }
  self.apply_markdown_folding()
}

///|
/// Flips one section between collapsed and expanded as an explicit reader
/// decision, then republishes visibility and invalidates the hover bridge.
///
/// Ordering is the plan's standalone rule: DOM visibility first
/// (`apply_markdown_folding`), `layout_changed` second, so a pending hover
/// request over content that just disappeared can never complete against
/// stale geometry.
fn MarkdownBrowserData::toggle_markdown_section(
  self : MarkdownBrowserData,
  section_index : Int,
) -> Bool {
  guard section_index >= 0 && section_index < self.fold.section_keys.length() else {
    return false
  }
  guard self.fold.records.get(self.fold.section_keys[section_index])
    is Some(record) else {
    return false
  }
  record.collapsed = !record.collapsed
  self.apply_markdown_folding()
  self.hover_bridge.layout_changed()
  true
}

///|
/// Publishes the current fold state into the view: the union of every
/// collapsed section's hideable run, plus one fold control per foldable
/// heading. Pure visibility -- never a re-render, never a projection rebuild.
fn MarkdownBrowserData::apply_markdown_folding(
  self : MarkdownBrowserData,
) -> Unit {
  let projection = self.view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  let hidden : Set[Int] = Set([])
  let controls : Array[@markdown_document.MarkdownSectionFoldControl] = []
  for section_index, section in sections {
    guard section.is_foldable(projection) &&
      section_index < self.fold.section_keys.length() else {
      continue
    }
    let collapsed = match
      self.fold.records.get(self.fold.section_keys[section_index]) {
      Some(record) => record.collapsed
      None => false
    }
    match
      projection.block_anchors[section.heading_anchor_index].rendered_element_index {
      Some(heading_element_index) =>
        controls.push({ heading_element_index, section_index, collapsed })
      None => continue
    }
    if collapsed {
      for element_index in section.body_rendered_element_indexes(projection) {
        hidden.add(element_index)
      }
    }
  }
  let hidden_sorted = hidden.to_array()
  hidden_sorted.sort()
  self.view.set_hidden_root_elements(hidden_sorted)
  self.view.install_section_fold_controls(controls)
}

///|
/// The section's exact body source text. Records store it so reconciliation
/// can tell an untouched section from a rewritten one; identical heading plus
/// identical body means hiding either candidate shows the reader the same
/// document, so key-level ambiguity is already conservative enough.
fn markdown_fold_fingerprint(
  section : @markdown_core.MarkdownSection,
  source : String,
) -> String {
  match section.body_source_range {
    Some(range) => {
      let start = range.start.max(0).min(source.length())
      let end = range.end_exclusive.max(start).min(source.length())
      source[start:end].to_owned()
    }
    None => ""
  }
}

///|
/// Collapses or expands the Markdown section owning `source_offset` (a 0-based
/// UTF-16 offset into the original model text, the innermost section winning),
/// as if the reader had clicked its fold control. Returns `false` when the
/// current presentation is not Markdown or no foldable section owns the
/// offset.
///
/// This is the host-facing seam the table-of-contents UI and agent drivers
/// use; the control DOM itself routes through the same toggle.
pub fn Viewer::toggle_markdown_section_at(
  self : Viewer,
  source_offset : Int,
) -> Bool {
  guard self.current_markdown_browser_data() is Some(data) else { return false }
  let projection = data.view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  guard @markdown_core.markdown_section_at_source_offset(
      sections, source_offset,
    )
    is Some(section) else {
    return false
  }
  guard section.is_foldable(projection) else { return false }
  for section_index, candidate in sections {
    if candidate.heading_anchor_index == section.heading_anchor_index {
      return data.toggle_markdown_section(section_index)
    }
  }
  false
}

///|
/// The heading source offsets of every currently collapsed Markdown section,
/// in document order; empty for a Code presentation. The offsets are the same
/// coordinates `toggle_markdown_section_at` accepts, so read-back and control
/// share one coordinate system.
pub fn Viewer::collapsed_markdown_sections(self : Viewer) -> Array[Int] {
  let collapsed = []
  guard self.current_markdown_browser_data() is Some(data) else {
    return collapsed
  }
  let projection = data.view.projection()
  let sections = @markdown_core.markdown_sections(projection)
  for section_index, section in sections {
    guard section_index < data.fold.section_keys.length() else { continue }
    match data.fold.records.get(data.fold.section_keys[section_index]) {
      Some(record) if record.collapsed =>
        collapsed.push(
          projection.block_anchors[section.heading_anchor_index].source_range.start,
        )
      _ => ()
    }
  }
  collapsed
}
