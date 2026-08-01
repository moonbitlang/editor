// Marker store ported 1:1 from
// vscode/src/vs/platform/markers/common/markerService.ts

///|
/// Schemes excluded from marker statistics, `unsupportedSchemas`
/// (`markerService.ts:16`). The literal Monaco scheme strings; the viewer's own
/// document scheme is `memory`, which is *not* among these, so viewer documents
/// are counted (the faithful outcome).
let unsupported_schemes : Array[String] = [
  "inmemory", "vscode-source-control", "walkThrough", "walkThroughSnippet", "vscode-chat-code-block",
  "vscode-terminal",
]

///|
/// `DoubleResourceMap` (`markerService.ts:25`): markers indexed both by resource
/// (→ owner → markers) and by owner (→ resource → markers). Resource keys are
/// `uri.to_string()`, matching `ResourceMap`'s internal `toString` keying.
struct DoubleResourceMap {
  by_resource : Map[String, Map[String, Array[Marker]]]
  by_owner : Map[String, Map[String, Array[Marker]]]
}

///|
fn DoubleResourceMap::new() -> DoubleResourceMap {
  { by_resource: Map([]), by_owner: Map([]) }
}

///|
/// `set` (`markerService.ts:30`).
fn DoubleResourceMap::set(
  self : DoubleResourceMap,
  resource : @base_common.Uri,
  owner : String,
  value : Array[Marker],
) -> Unit {
  let key = resource.to_string()
  let owner_map = match self.by_resource.get(key) {
    Some(m) => m
    None => {
      let m : Map[String, Array[Marker]] = Map([])
      self.by_resource.set(key, m)
      m
    }
  }
  owner_map.set(owner, value)
  let resource_map = match self.by_owner.get(owner) {
    Some(m) => m
    None => {
      let m : Map[String, Array[Marker]] = Map([])
      self.by_owner.set(owner, m)
      m
    }
  }
  resource_map.set(key, value)
}

///|
/// `get` (`markerService.ts:46`).
fn DoubleResourceMap::get(
  self : DoubleResourceMap,
  resource : @base_common.Uri,
  owner : String,
) -> Array[Marker]? {
  match self.by_resource.get(resource.to_string()) {
    Some(owner_map) => owner_map.get(owner)
    None => None
  }
}

///|
/// `delete` with the illegal-state guard (`markerService.ts:51`).
fn DoubleResourceMap::delete(
  self : DoubleResourceMap,
  resource : @base_common.Uri,
  owner : String,
) -> Bool {
  let key = resource.to_string()
  let removed_a = match self.by_resource.get(key) {
    Some(owner_map) => {
      let had = owner_map.contains(owner)
      owner_map.remove(owner)
      had
    }
    None => false
  }
  let removed_b = match self.by_owner.get(owner) {
    Some(resource_map) => {
      let had = resource_map.contains(key)
      resource_map.remove(key)
      had
    }
    None => false
  }
  if removed_a != removed_b {
    abort("illegal state")
  }
  removed_a && removed_b
}

///|
/// `values()` with no key (`markerService.ts:75`): every marker array, owner by
/// owner.
fn DoubleResourceMap::values_all(
  self : DoubleResourceMap,
) -> Array[Array[Marker]] {
  let out : Array[Array[Marker]] = []
  for owner_map in self.by_owner.values() {
    for v in owner_map.values() {
      out.push(v)
    }
  }
  out
}

///|
/// `values(resource)` (`markerService.ts:72`).
fn DoubleResourceMap::values_by_resource(
  self : DoubleResourceMap,
  resource : @base_common.Uri,
) -> Array[Array[Marker]] {
  match self.by_resource.get(resource.to_string()) {
    Some(owner_map) => {
      let out : Array[Array[Marker]] = []
      for v in owner_map.values() {
        out.push(v)
      }
      out
    }
    None => []
  }
}

///|
/// `values(owner)` (`markerService.ts:69`).
fn DoubleResourceMap::values_by_owner(
  self : DoubleResourceMap,
  owner : String,
) -> Array[Array[Marker]] {
  match self.by_owner.get(owner) {
    Some(resource_map) => {
      let out : Array[Array[Marker]] = []
      for v in resource_map.values() {
        out.push(v)
      }
      out
    }
    None => []
  }
}

///|
/// Live per-severity statistics, `MarkerStats` (`markerService.ts:80`). Subscribes
/// to the service's change event and accumulates deltas per resource.
struct MarkerStats {
  mut errors : Int
  mut warnings : Int
  mut infos : Int
  mut unknowns : Int
  data : Map[String, MarkerStatistics]
  service : MarkerService
}

///|
fn MarkerStats::new(service : MarkerService) -> MarkerStats {
  let stats = {
    errors: 0,
    warnings: 0,
    infos: 0,
    unknowns: 0,
    data: Map([]),
    service,
  }
  service.did_change_markers.event(resources => stats.update(resources))
  |> ignore
  stats
}

///|
/// `_update` (`markerService.ts:100`).
fn MarkerStats::update(
  self : MarkerStats,
  resources : Array[@base_common.Uri],
) -> Unit {
  for resource in resources {
    match self.data.get(resource.to_string()) {
      Some(old_stats) => self.subtract(old_stats)
      None => ()
    }
    let new_stats = self.resource_stats(resource)
    self.add(new_stats)
    self.data.set(resource.to_string(), new_stats)
  }
}

///|
/// `_resourceStats` (`markerService.ts:112`): skip unsupported schemes; bucket by
/// severity.
fn MarkerStats::resource_stats(
  self : MarkerStats,
  resource : @base_common.Uri,
) -> MarkerStatistics {
  let result : MarkerStatistics = {
    errors: 0,
    warnings: 0,
    infos: 0,
    unknowns: 0,
  }
  // TODO this is a hack (markerService.ts:115)
  if unsupported_schemes.contains(resource.scheme) {
    return result
  }
  for marker in self.service.read(MarkerReadOptions(resource~)) {
    match marker.severity {
      Error => result.errors += 1
      Warning => result.warnings += 1
      Info => result.infos += 1
      _ => result.unknowns += 1
    }
  }
  result
}

///|
/// `_substract` (`markerService.ts:135`).
fn MarkerStats::subtract(self : MarkerStats, op : MarkerStatistics) -> Unit {
  self.errors -= op.errors
  self.warnings -= op.warnings
  self.infos -= op.infos
  self.unknowns -= op.unknowns
}

///|
/// `_add` (`markerService.ts:142`).
fn MarkerStats::add(self : MarkerStats, op : MarkerStatistics) -> Unit {
  self.errors += op.errors
  self.warnings += op.warnings
  self.infos += op.infos
  self.unknowns += op.unknowns
}

///|
/// `_merge` (`markerService.ts:405`): unions every queued change's URI set,
/// first-seen order, keyed like `ResourceMap.defaultToKey` (`uri.toString()`).
fn merge_changed_uris(
  all : Array[Array[@base_common.Uri]],
) -> Array[@base_common.Uri] {
  let set : Map[String, @base_common.Uri] = Map([])
  for array in all {
    for item in array {
      set.set(item.to_string(), item)
    }
  }
  set.values().collect()
}

///|
/// In-memory marker store keyed by owner/resource pairs, `MarkerService`
/// (`markerService.ts:150`).
pub struct MarkerService {
  did_change_markers : @base_common.MicrotaskEmitter[Array[@base_common.Uri]]
  data : DoubleResourceMap
  filtered_resources : Map[String, Array[String]]
  mut stats : MarkerStats?
}

///|
/// Creates an empty marker store. `schedule` is the flush scheduler for the
/// change event's `MicrotaskEmitter` (`markerService.ts:154-156` hardcodes
/// `queueMicrotask`; the default here flushes inline — see the deviation note
/// on `@base_common.MicrotaskEmitter`).
#alias(new)
pub fn MarkerService::MarkerService(
  schedule? : (() -> Unit) -> Unit,
) -> MarkerService {
  let did_change_markers : @base_common.MicrotaskEmitter[
    Array[@base_common.Uri],
  ] = match schedule {
    Some(schedule) => MicrotaskEmitter(merge=merge_changed_uris, schedule~)
    None => MicrotaskEmitter(merge=merge_changed_uris)
  }
  let service : MarkerService = {
    did_change_markers,
    data: DoubleResourceMap::new(),
    filtered_resources: Map([]),
    stats: None,
  }
  service.stats = Some(MarkerStats::new(service))
  service
}

///|
/// Subscribes to marker-change events, `onMarkerChanged` (`markerService.ts:158`).
pub fn MarkerService::on_did_change_markers(
  self : MarkerService,
  listener : (Array[@base_common.Uri]) -> Unit,
) -> @base_common.Disposable {
  self.did_change_markers.event(listener)
}

///|
/// Releases the change emitter.
pub fn MarkerService::dispose(self : MarkerService) -> Unit {
  self.did_change_markers.dispose()
}

///|
/// `getStatistics` (`markerService.ts:169`): a snapshot of the live stats. (Monaco
/// returns the live object; the snapshot reads identically for any caller that
/// consumes it immediately.)
pub fn MarkerService::statistics(self : MarkerService) -> MarkerStatistics {
  match self.stats {
    Some(stats) =>
      {
        errors: stats.errors,
        warnings: stats.warnings,
        infos: stats.infos,
        unknowns: stats.unknowns,
      }
    None => { errors: 0, warnings: 0, infos: 0, unknowns: 0 }
  }
}

///|
/// `remove` (`markerService.ts:173`): clears markers for `owner` on each resource.
pub fn MarkerService::remove(
  self : MarkerService,
  owner : String,
  resources : Array[@base_common.Uri],
) -> Unit {
  for resource in resources {
    self.change_one(owner, resource, [])
  }
}

///|
/// `changeOne` (`markerService.ts:179`): empty data removes the (owner,resource)
/// entry; otherwise sanitizes and stores. Fires the change event in both cases
/// when something happened.
pub fn MarkerService::change_one(
  self : MarkerService,
  owner : String,
  resource : @base_common.Uri,
  marker_data : Array[MarkerData],
) -> Unit {
  if marker_data.is_empty() {
    // remove marker for this (owner,resource)-tuple
    let removed = self.data.delete(resource, owner)
    if removed {
      self.did_change_markers.fire([resource])
    }
  } else {
    // insert marker for this (owner,resource)-tuple
    let markers : Array[Marker] = []
    for data in marker_data {
      match data.to_marker(owner, resource) {
        Some(marker) => markers.push(marker)
        None => ()
      }
    }
    self.data.set(resource, owner, markers)
    self.did_change_markers.fire([resource])
  }
}

///|
/// `installResourceFilter` (`markerService.ts:202`): records a filter reason for a
/// resource and returns a disposable that removes it (D5).
pub fn MarkerService::install_resource_filter(
  self : MarkerService,
  resource : @base_common.Uri,
  reason : String,
) -> @base_common.Disposable {
  let key = resource.to_string()
  let reasons = match self.filtered_resources.get(key) {
    Some(r) => r
    None => {
      let r : Array[String] = []
      self.filtered_resources.set(key, r)
      r
    }
  }
  reasons.push(reason)
  self.did_change_markers.fire([resource])
  @base_common.Disposable::from(() => {
    match self.filtered_resources.get(key) {
      None => ()
      Some(reasons) => {
        let reason_index = reasons.search(reason)
        match reason_index {
          Some(index) => {
            reasons.remove(index) |> ignore
            if reasons.length() == 0 {
              self.filtered_resources.remove(key)
            }
            self.did_change_markers.fire([resource])
          }
          None => ()
        }
      }
    }
  })
}

///|
/// `_createFilteredMarker` (`markerService.ts:315`): the "Problems are paused"
/// info marker shown in place of a filtered resource's real markers.
fn MarkerService::create_filtered_marker(
  resource : @base_common.Uri,
  reasons : Array[String],
) -> Marker {
  let message = if reasons.length() == 1 {
    "Problems are paused because: \"" + reasons[0] + "\""
  } else {
    "Problems are paused because: \"" +
    reasons[0] +
    "\" and " +
    (reasons.length() - 1).to_string() +
    " more"
  }
  {
    owner: "markersFilter",
    resource,
    severity: Info,
    code: None,
    message,
    source: None,
    start_column: 1,
    start_line_number: 1,
    end_line_number: 1,
    end_column: 1,
    model_version_id: None,
    related_information: None,
    tags: None,
    origin: None,
  }
}

///|
/// `read` (`markerService.ts:332`): the owner∧resource fast path and the
/// owner∨resource (or all) path with `ResourceSet` dedup, severities bitmask
/// (`_accept`), resource filters, and `take` cap.
pub fn MarkerService::read(
  self : MarkerService,
  filter : MarkerReadOptions,
) -> Array[Marker] {
  let owner = filter.owner
  let resource = filter.resource
  let severities = filter.severities
  let take = match filter.take {
    Some(t) if t > 0 => t
    _ => -1
  }
  match (owner, resource) {
    (Some(owner), Some(resource)) => {
      // exactly one owner AND resource
      let reasons = if !filter.ignore_resource_filters {
        self.filtered_resources.get(resource.to_string())
      } else {
        None
      }
      if reasons is Some(r) && r.length() > 0 {
        return [MarkerService::create_filtered_marker(resource, r)]
      }
      let data = match self.data.get(resource, owner) {
        Some(d) => d
        None => return []
      }
      let result : Array[Marker] = []
      for marker in data {
        if take > 0 && result.length() == take {
          break
        }
        let reasons = if !filter.ignore_resource_filters {
          self.filtered_resources.get(resource.to_string())
        } else {
          None
        }
        if reasons is Some(r) && r.length() > 0 {
          result.push(MarkerService::create_filtered_marker(resource, r))
        } else if MarkerService::accept(marker, severities) {
          result.push(marker)
        }
      }
      result
    }
    _ => {
      // of one resource OR owner
      let iterable = match (owner, resource) {
        (None, None) => self.data.values_all()
        _ =>
          match resource {
            Some(resource) => self.data.values_by_resource(resource)
            None => self.data.values_by_owner(owner.unwrap())
          }
      }
      let result : Array[Marker] = []
      let filtered : Set[String] = Set([])
      for markers in iterable {
        for data in markers {
          if filtered.contains(data.resource.to_string()) {
            continue
          }
          if take > 0 && result.length() == take {
            break
          }
          let reasons = if !filter.ignore_resource_filters {
            self.filtered_resources.get(data.resource.to_string())
          } else {
            None
          }
          if reasons is Some(r) && r.length() > 0 {
            result.push(MarkerService::create_filtered_marker(data.resource, r))
            filtered.add(data.resource.to_string())
          } else if MarkerService::accept(data, severities) {
            result.push(data)
          }
        }
      }
      result
    }
  }
}

///|
/// `changeAll` (`markerService.ts:266`): clears the owner's prior markers, groups
/// the new data by resource, stores it, and fires the merged change set.
pub fn MarkerService::change_all(
  self : MarkerService,
  owner : String,
  data : Array[ResourceMarker],
) -> Unit {
  let changes : Array[@base_common.Uri] = []

  // remove old marker
  let existing = self.data.values_by_owner(owner)
  for markers in existing {
    match markers.get(0) {
      Some(first) => {
        changes.push(first.resource)
        self.data.delete(first.resource, owner) |> ignore
      }
      None => ()
    }
  }

  // add new markers
  if !data.is_empty() {
    // group by resource
    let groups : Map[String, Array[Marker]] = Map([])
    for rm in data {
      match rm.marker.to_marker(owner, rm.resource) {
        None =>
          // filter bad markers
          continue
        Some(marker) => {
          let key = rm.resource.to_string()
          match groups.get(key) {
            None => {
              groups.set(key, [marker])
              changes.push(rm.resource)
            }
            Some(array) => array.push(marker)
          }
        }
      }
    }

    // insert all
    for _, value in groups {
      self.data.set(value[0].resource, owner, value)
    }
  }
  if changes.length() > 0 {
    self.did_change_markers.fire(changes)
  }
}

///|
/// `_accept` (`markerService.ts:399`): no severities filter, or the marker's
/// severity bit is present in the requested bitmask.
fn MarkerService::accept(marker : Marker, severities : Int?) -> Bool {
  match severities {
    None => true
    Some(s) => (s & marker.severity.value()) == marker.severity.value()
  }
}

// --- viewer shims over the faithful API (kept so existing consumers compile
// through the migration; see plan increment B) ---

///|
/// Replaces diagnostics for one owner/resource pair, routing through
/// `change_one`.
pub fn MarkerService::set_diagnostics(
  self : MarkerService,
  owner : String,
  resource : @base_common.Uri,
  diagnostics : Array[@language.Diagnostic],
) -> Unit {
  let data : Array[MarkerData] = []
  for diagnostic in diagnostics {
    data.push(
      MarkerData(
        severity=MarkerSeverity::from_diagnostic_severity(diagnostic.severity),
        message=diagnostic.message,
        start_line_number=diagnostic.range.start_line_number,
        start_column=diagnostic.range.start_column,
        end_line_number=diagnostic.range.end_line_number,
        end_column=diagnostic.range.end_column,
      ),
    )
  }
  self.change_one(owner, resource, data)
}

///|
/// Clears markers for one owner/resource pair.
pub fn MarkerService::remove_owner_resource(
  self : MarkerService,
  owner : String,
  resource : @base_common.Uri,
) -> Unit {
  self.change_one(owner, resource, [])
}

///|
/// Clears markers from every owner for one resource.
pub fn MarkerService::clear_resource(
  self : MarkerService,
  resource : @base_common.Uri,
) -> Unit {
  for owner in self.read(MarkerReadOptions(resource~)).map(m => m.owner) {
    self.remove(owner, [resource])
  }
}

///|
/// Returns markers for one resource, optionally capped by `limit`.
pub fn MarkerService::markers_for_resource(
  self : MarkerService,
  resource : @base_common.Uri,
  limit? : Int = 0,
) -> Array[Marker] {
  self.read(MarkerReadOptions(resource~, take=limit))
}

///|
/// Returns resource markers in the shared diagnostic shape.
pub fn MarkerService::diagnostics_for_resource(
  self : MarkerService,
  resource : @base_common.Uri,
) -> Array[@language.Diagnostic] {
  self.markers_for_resource(resource).map(m => m.to_diagnostic())
}
