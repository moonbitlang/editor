// Marker → decoration transform + service ported from
// vscode/src/vs/editor/common/services/markerDecorationsService.ts

///|
/// Why an active model registration is being finalized. The local viewer has
/// no process-wide `IModelService`, so editor leases and a real model disposal
/// are deliberately different authorities.
priv enum ModelRegistrationRemovalReason {
  LeaseReleased
  ModelDisposed
  ServiceDisposed
}

///|
/// One identity-owned decoration projection. Reacquiring the exact same
/// `TextModel` increments `ref_count`; it never adds another model watch.
priv struct ModelMarkerRegistration {
  model : @model.TextModel
  marker_decorations : MarkerDecorations
  mut ref_count : Int
  mut active : Bool
  mut content_subscription : @base_common.Disposable?
  mut dispose_subscription : @base_common.Disposable?
  mut update_in_progress : Bool
  mut update_requested : Bool
  mut reset_requested : Bool
}

///|
/// Converts marker state into render decorations and live-marker lookups,
/// `MarkerDecorationsService` (`markerDecorationsService.ts:24`). In place of
/// Monaco's global `IModelService`, callers acquire identity-keyed leases. A
/// secondary URI index preserves source-compatible URI queries while allowing
/// distinct live models to share one URI.
pub struct MarkerDecorationsService {
  priv markers : MarkerServiceHandle
  priv model_registrations : Map[Int, ModelMarkerRegistration]
  priv model_ids_by_uri : Map[String, Array[Int]]
  priv blocked_model_ids : Map[Int, Unit]
  priv legacy_leases : Map[Int, @base_common.Disposable]
  priv suppressed_ranges : Map[String, Array[@base_common.Range]]
  priv did_change_marker_decorations : @base_common.Emitter[@model.TextModel]
  priv mut subscription : @base_common.Disposable?
  priv mut disposed : Bool
}

///|
/// Creates a decoration facade over the marker store and subscribes to its change
/// event (`markerDecorationsService.ts:43`).
#alias(new)
pub fn MarkerDecorationsService::MarkerDecorationsService(
  markers : MarkerServiceHandle,
) -> MarkerDecorationsService {
  let service : MarkerDecorationsService = {
    markers,
    model_registrations: Map([]),
    model_ids_by_uri: Map([]),
    blocked_model_ids: Map([]),
    legacy_leases: Map([]),
    suppressed_ranges: Map([]),
    did_change_marker_decorations: Emitter(),
    subscription: None,
    disposed: false,
  }
  service.subscription = Some(
    markers.on_did_change_markers(resources => {
      service.handle_marker_change(resources)
    }),
  )
  service
}

///|
/// Subscribes to per-model decoration-change events, `onDidChangeMarker`
/// (`markerDecorationsService.ts:29`). The payload is the changed model.
pub fn MarkerDecorationsService::on_did_change_marker_decorations(
  self : MarkerDecorationsService,
  listener : (@model.TextModel) -> Unit,
) -> @base_common.Disposable {
  self.did_change_marker_decorations.event(listener)
}

///|
/// Releases service-owned subscriptions and per-model owners (`dispose`,
/// `markerDecorationsService.ts:46`). Ingress is blocked first; model watches
/// and owners are then finalized exactly once; indexes are cleared last. The
/// injected marker-store handle and its host-owned diagnostics remain untouched.
pub fn MarkerDecorationsService::dispose(
  self : MarkerDecorationsService,
) -> Unit {
  if self.disposed {
    return
  }
  // Block both marker-service and outward-emitter ingress before any owner can
  // reenter through a model-decoration callback.
  self.disposed = true
  match self.subscription {
    Some(d) => {
      self.subscription = None
      d.dispose()
    }
    None => ()
  }
  self.did_change_marker_decorations.dispose()
  let registrations : Array[ModelMarkerRegistration] = []
  for _, registration in self.model_registrations {
    registrations.push(registration)
  }
  for registration in registrations {
    self.finalize_registration(registration, ServiceDisposed)
  }
  // These are the two ownership indexes. They intentionally survive until
  // every watch/owner is inert so teardown callbacks cannot observe a partial
  // service as live ingress.
  self.blocked_model_ids.clear()
  self.legacy_leases.clear()
  self.suppressed_ranges.clear()
  self.model_registrations.clear()
  self.model_ids_by_uri.clear()
}

///|
/// Acquires one independently idempotent lease for the model's stable identity.
/// The first lease installs exactly one content watch and one model-dispose
/// watch, appends the identity to its URI bucket, and seeds decorations.
/// Reacquisition only increments the refcount and preserves URI order.
pub fn MarkerDecorationsService::acquire_model(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> @base_common.Disposable {
  let model_id = model.identity()
  if self.disposed ||
    model.is_disposed() ||
    self.blocked_model_ids.contains(model_id) {
    return @base_common.Disposable::from(() => ())
  }
  match self.model_registrations.get(model_id) {
    Some(registration) => registration.ref_count += 1
    None => {
      let registration : ModelMarkerRegistration = {
        model,
        marker_decorations: MarkerDecorations::new(model),
        ref_count: 1,
        active: true,
        content_subscription: None,
        dispose_subscription: None,
        update_in_progress: false,
        update_requested: false,
        reset_requested: false,
      }
      self.model_registrations.set(model_id, registration)
      let uri_key = model.uri.to_string()
      let model_ids = match self.model_ids_by_uri.get(uri_key) {
        Some(ids) => ids
        None => {
          let ids : Array[Int] = []
          self.model_ids_by_uri.set(uri_key, ids)
          ids
        }
      }
      model_ids.push(model_id)
      // Ordering is contractual: content watch, model-dispose watch, seed.
      registration.content_subscription = Some(
        model.on_did_change_content(_ => {
          self.refresh_model_registration(model_id)
        }),
      )
      registration.dispose_subscription = Some(
        model.on_will_dispose(() => {
          self.remove_model_registration(model_id, ModelDisposed)
        }),
      )
      self.update_decorations(registration)
    }
  }
  @base_common.Disposable::from(() => {
    self.remove_model_registration(model_id, LeaseReleased)
  })
}

///|
/// Compatibility entry point for callers that still use the historical
/// paired add/remove API. New viewer ownership uses `acquire_model` directly.
/// A repeated add refreshes the existing owner and never increments its lease.
pub fn MarkerDecorationsService::on_model_added(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> Unit {
  if self.disposed {
    return
  }
  let model_id = model.identity()
  match self.model_registrations.get(model_id) {
    Some(_) => self.refresh_model_registration(model_id)
    None => {
      let lease = self.acquire_model(model)
      if self.model_registrations.contains(model_id) {
        self.legacy_leases.set(model_id, lease)
      }
    }
  }
}

///|
/// Compatibility counterpart to `on_model_added`. Ordinary paired removal is
/// a lease release and therefore never deletes host-owned diagnostics.
pub fn MarkerDecorationsService::on_model_removed(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> Unit {
  let model_id = model.identity()
  match self.legacy_leases.get(model_id) {
    Some(lease) => {
      self.legacy_leases.remove(model_id)
      lease.dispose()
    }
    None => ()
  }
}

///|
fn MarkerDecorationsService::remove_model_registration(
  self : MarkerDecorationsService,
  model_id : Int,
  reason : ModelRegistrationRemovalReason,
) -> Unit {
  if self.disposed && !(reason is ServiceDisposed) {
    return
  }
  guard self.model_registrations.get(model_id) is Some(registration) else {
    return
  }
  if !registration.active {
    return
  }
  if reason is LeaseReleased && registration.ref_count > 1 {
    registration.ref_count -= 1
    return
  }
  registration.active = false
  self.blocked_model_ids.set(model_id, ())
  // Source order is observable through the model-decoration callback fired by
  // owner disposal: make the owner inert first, dispose it while both indexes
  // still identify the registration, then delete those indexes. `active` and
  // `blocked_model_ids` prevent every reentrant update/acquisition lane.
  self.finalize_registration(registration, reason)
  self.model_registrations.remove(model_id)
  self.remove_model_from_uri_index(registration.model.uri, model_id)
  self.legacy_leases.remove(model_id)
  match reason {
    LeaseReleased => self.blocked_model_ids.remove(model_id)
    ModelDisposed =>
      // Transient diagnostics belong to the dying model lifetime, but a
      // distinct live identity sharing the URI still owns that URI bucket.
      if !self.model_ids_by_uri.contains(registration.model.uri.to_string()) {
        self.remove_transient_markers(registration.model)
      }
    ServiceDisposed => ()
  }
}

///|
fn MarkerDecorationsService::finalize_registration(
  _self : MarkerDecorationsService,
  registration : ModelMarkerRegistration,
  _reason : ModelRegistrationRemovalReason,
) -> Unit {
  if registration.active {
    registration.active = false
  }
  registration.update_requested = false
  registration.reset_requested = false
  match registration.content_subscription {
    Some(subscription) => {
      registration.content_subscription = None
      subscription.dispose()
    }
    None => ()
  }
  match registration.dispose_subscription {
    Some(subscription) => {
      registration.dispose_subscription = None
      subscription.dispose()
    }
    None => ()
  }
  registration.marker_decorations.dispose()
}

///|
fn MarkerDecorationsService::remove_model_from_uri_index(
  self : MarkerDecorationsService,
  uri : @base_common.Uri,
  model_id : Int,
) -> Unit {
  let uri_key = uri.to_string()
  match self.model_ids_by_uri.get(uri_key) {
    Some(model_ids) => {
      match model_ids.search(model_id) {
        Some(index) => model_ids.remove(index) |> ignore
        None => ()
      }
      if model_ids.length() == 0 {
        self.model_ids_by_uri.remove(uri_key)
      }
    }
    None => ()
  }
}

///|
fn MarkerDecorationsService::remove_transient_markers(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> Unit {
  let scheme = model.uri.scheme
  if scheme == "inmemory" || scheme == "internal" || scheme == "vscode" {
    let owners : Map[String, Unit] = Map([])
    for marker in self.markers.read(MarkerReadOptions(resource=model.uri)) {
      owners.set(marker.owner, ())
    }
    for owner, _ in owners {
      self.markers.remove(owner, [model.uri])
    }
  }
}

///|
/// Per-resource `_updateDecorations`, `_handleMarkerChange`
/// (`markerDecorationsService.ts:84`).
fn MarkerDecorationsService::handle_marker_change(
  self : MarkerDecorationsService,
  changed_resources : Array[@base_common.Uri],
) -> Unit {
  if self.disposed {
    return
  }
  for resource in changed_resources {
    if self.disposed {
      return
    }
    match self.model_ids_by_uri.get(resource.to_string()) {
      Some(model_ids) =>
        for model_id in model_ids.copy() {
          if self.disposed {
            return
          }
          match self.model_registrations.get(model_id) {
            Some(registration) => self.update_decorations(registration)
            None => ()
          }
        }
      None => ()
    }
  }
}

///|
fn MarkerDecorationsService::refresh_model_registration(
  self : MarkerDecorationsService,
  model_id : Int,
) -> Unit {
  if self.disposed {
    return
  }
  guard self.model_registrations.get(model_id) is Some(registration) else {
    return
  }
  if !registration.active {
    return
  }
  self.update_decorations(registration, reset=true)
}

///|
/// `_updateDecorations` (`markerDecorationsService.ts:114`): read the first 500
/// markers, drop ones inside suppressed ranges, push them through `update`, and
/// fire the change event when something changed.
fn MarkerDecorationsService::update_decorations(
  self : MarkerDecorationsService,
  registration : ModelMarkerRegistration,
  reset? : Bool = false,
) -> Unit {
  if self.disposed || !registration.active {
    return
  }
  registration.update_requested = true
  if reset {
    registration.reset_requested = true
  }
  if registration.update_in_progress {
    return
  }
  registration.update_in_progress = true
  for ;; {
    if self.disposed || !registration.active {
      break
    }
    let reset_before_update = registration.reset_requested
    registration.reset_requested = false
    registration.update_requested = false
    if reset_before_update {
      registration.marker_decorations.reset()
    }
    if self.disposed || !registration.active {
      break
    }
    self.update_decorations_once(registration)
    if !registration.update_requested && !registration.reset_requested {
      break
    }
  }
  registration.update_in_progress = false
}

///|
/// Runs one stable marker-store read and owner update. Reentrant marker or
/// model-content callbacks only set the registration's pending flags; the
/// outer update drains them after `delta_decorations` has returned.
fn MarkerDecorationsService::update_decorations_once(
  self : MarkerDecorationsService,
  registration : ModelMarkerRegistration,
) -> Unit {
  if self.disposed || !registration.active {
    return
  }
  let marker_decorations = registration.marker_decorations
  // Limit to the first 500 errors/warnings
  let mut markers = self.markers.read(
    MarkerReadOptions(resource=marker_decorations.model.uri, take=500),
  )
  // filter markers from suppressed ranges
  match self.suppressed_ranges.get(marker_decorations.model.uri.to_string()) {
    Some(suppressed_ranges) =>
      markers = markers.filter(marker => {
        !suppressed_ranges.any(candidate => {
          @base_common.Range::are_intersecting_or_touching(
            candidate,
            marker.range(),
          )
        })
      })
    None => ()
  }
  if marker_decorations.update(markers) && !self.disposed && registration.active {
    self.did_change_marker_decorations.fire(marker_decorations.model)
  }
}

///|
/// `getMarker` (`markerDecorationsService.ts:52`): the marker behind a decoration
/// id on `uri`. The URI bucket is scanned in acquisition order; model-generated
/// decoration ids carry the model identity prefix, so distinct live same-URI
/// models remain unambiguous.
pub fn MarkerDecorationsService::get_marker(
  self : MarkerDecorationsService,
  uri : @base_common.Uri,
  decoration_id : String,
) -> Marker? {
  guard self.model_ids_by_uri.get(uri.to_string()) is Some(model_ids) else {
    return None
  }
  for model_id in model_ids {
    match self.model_registrations.get(model_id) {
      Some(registration) =>
        match registration.marker_decorations.get_marker(decoration_id) {
          Some(marker) => return Some(marker)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
/// `getLiveMarkers` (`markerDecorationsService.ts:57`): `(range, marker)` pairs for
/// every live identity at the resource, concatenated in acquisition order.
/// Identity-sensitive consumers such as hover use
/// `get_live_markers_for_model` instead.
pub fn MarkerDecorationsService::get_live_markers(
  self : MarkerDecorationsService,
  uri : @base_common.Uri,
) -> Array[(@base_common.Range, Marker)] {
  let result : Array[(@base_common.Range, Marker)] = []
  match self.model_ids_by_uri.get(uri.to_string()) {
    Some(model_ids) =>
      for model_id in model_ids {
        match self.model_registrations.get(model_id) {
          Some(registration) =>
            result.append(registration.marker_decorations.get_markers())
          None => ()
        }
      }
    None => ()
  }
  result
}

///|
/// Returns only the live marker decorations owned by this exact model
/// identity. Hover uses this helper so two live models sharing one URI cannot
/// contribute ranges from each other's snapshots.
pub fn MarkerDecorationsService::get_live_markers_for_model(
  self : MarkerDecorationsService,
  model : @model.TextModel,
) -> Array[(@base_common.Range, Marker)] {
  match self.model_registrations.get(model.identity()) {
    Some(registration) => registration.marker_decorations.get_markers()
    None => []
  }
}

///|
/// `addMarkerSuppression` (`markerDecorationsService.ts:62`): suppress markers in
/// `range` on `uri`; the disposable removes the suppression (D5).
pub fn MarkerDecorationsService::add_marker_suppression(
  self : MarkerDecorationsService,
  uri : @base_common.Uri,
  range : @base_common.Range,
) -> @base_common.Disposable {
  if self.disposed {
    return @base_common.Disposable::from(() => ())
  }
  let key = uri.to_string()
  let suppressed_ranges = match self.suppressed_ranges.get(key) {
    Some(r) => r
    None => {
      let r : Array[@base_common.Range] = []
      self.suppressed_ranges.set(key, r)
      r
    }
  }
  suppressed_ranges.push(range)
  self.handle_marker_change([uri])
  @base_common.Disposable::from(() => {
    match self.suppressed_ranges.get(key) {
      Some(suppressed_ranges) => {
        match suppressed_ranges.search(range) {
          Some(index) => suppressed_ranges.remove(index) |> ignore
          None => ()
        }
        if suppressed_ranges.length() == 0 {
          self.suppressed_ranges.remove(key)
        }
        self.handle_marker_change([uri])
      }
      None => ()
    }
  })
}

// Theme-color ids the option matrix carries (inert; plan D4). From
// editorColorRegistry.ts:74-76 and colors/minimapColors.ts:29-37.

///|
let overview_ruler_error : String = "editorOverviewRuler.errorForeground"

///|
let overview_ruler_warning : String = "editorOverviewRuler.warningForeground"

///|
let overview_ruler_info : String = "editorOverviewRuler.infoForeground"

///|
let minimap_error : String = "minimap.errorHighlight"

///|
let minimap_warning : String = "minimap.warningHighlight"

///|
let minimap_info : String = "minimap.infoHighlight"

///|
/// `MarkerDecorations._createDecorationOption`
/// (`markerDecorationsService.ts:226`): the severity→option matrix plus tag
/// overrides. An empty `class_name` is Monaco's `className: undefined`
/// (Hint+Deprecated); the range travels separately as the
/// `IModelDeltaDecoration` pair (`create_decoration_range`).
pub fn create_decoration_option(
  marker : Marker,
) -> @model.ModelDecorationOptions {
  let mut class_name = ""
  let mut color : String? = None
  let mut z_index = 0
  let mut inline_class_name : String? = None
  let mut minimap : @model.ModelDecorationMinimapOptions? = None
  match marker.severity {
    Hint => {
      if marker.has_tag(Deprecated) {
        class_name = ""
      } else if marker.has_tag(Unnecessary) {
        class_name = "squiggly-unnecessary"
      } else {
        class_name = "squiggly-hint"
      }
      z_index = 0
    }
    Info => {
      class_name = "squiggly-info"
      color = Some(overview_ruler_info)
      z_index = 10
      minimap = Some({ color: minimap_info, position: Inline })
    }
    Warning => {
      class_name = "squiggly-warning"
      color = Some(overview_ruler_warning)
      z_index = 20
      minimap = Some({ color: minimap_warning, position: Inline })
    }
    Error => {
      // default
      class_name = "squiggly-error"
      color = Some(overview_ruler_error)
      z_index = 30
      minimap = Some({ color: minimap_error, position: Inline })
    }
  }
  match marker.tags {
    Some(tags) => {
      if tags.contains(Unnecessary) {
        inline_class_name = Some("squiggly-inline-unnecessary")
      }
      if tags.contains(Deprecated) {
        inline_class_name = Some("squiggly-inline-deprecated")
      }
    }
    None => ()
  }
  ModelDecorationOptions(
    class_name,
    message=marker.message,
    inline_class_name?,
    z_index~,
    show_if_collapsed=true,
    stickiness=NeverGrowsWhenTypingAtEdges,
    overview_ruler={ color, position: Right },
    minimap?,
    description="marker-decoration",
  )
}

///|
/// `MarkerDecorations._createDecorationRange` (`markerDecorationsService.ts:190`):
/// turns a raw marker into the decoration's render `Range`. Four branches:
///   1. Hint without Unnecessary/Deprecated → single line, `+2` columns (room for
///      three dots);
///   2. clamp via `validateRange`;
///   3. empty range → keep 1ch (empty line / behind EOL) or expand to the
///      surrounding word;
///   4. full-line marker (`endColumn == MAX_VALUE`, `startColumn == 1`, single
///      line) → snap the start to the first non-whitespace column (and mutate the
///      raw marker, as Monaco does).
pub fn create_decoration_range(
  model : @model.TextModel,
  raw_marker : Marker,
) -> @base_common.Range {
  let mut ret = raw_marker.range()
  if raw_marker.severity == Hint &&
    !raw_marker.has_tag(Unnecessary) &&
    !raw_marker.has_tag(Deprecated) {
    // * never render hints on multiple lines
    // * make enough space for three dots
    ret = ret.set_end_position(ret.start_line_number, ret.start_column + 2)
  }
  ret = model.validate_range(ret)
  if ret.is_empty() {
    let last_non_ws = model.get_line_last_non_whitespace_column(
      ret.start_line_number,
    )
    let max_column = if last_non_ws != 0 {
      last_non_ws
    } else {
      model.get_line_max_column(ret.start_line_number)
    }
    if max_column == 1 || ret.end_column >= max_column {
      // empty line or behind eol
      // keep the range as is, it will be rendered 1ch wide
      return ret
    }
    match model.get_word_at_position(ret.get_start_position()) {
      Some(word) =>
        ret = Range(
          ret.start_line_number,
          word.start_column,
          ret.end_line_number,
          word.end_column,
        )
      None => ()
    }
  } else if raw_marker.end_column == max_value_column &&
    raw_marker.start_column == 1 &&
    ret.start_line_number == ret.end_line_number {
    let min_column = model.get_line_first_non_whitespace_column(
      raw_marker.start_line_number,
    )
    if min_column < ret.end_column {
      ret = Range(
        ret.start_line_number,
        min_column,
        ret.end_line_number,
        ret.end_column,
      )
      raw_marker.start_column = min_column
    }
  }
  ret
}
