///|
/// Borrowed marker-store capabilities required by `MarkerDecorationsService`.
/// The concrete store remains caller-owned; this adapter exposes only the
/// change subscription, filtered read, and removal operations used by the
/// decoration projection.
pub struct MarkerServiceHandle {
  priv on_did_change_markers : ((Array[@base_common.Uri]) -> Unit) -> @base_common.Disposable
  priv read : (MarkerReadOptions) -> Array[Marker]
  priv remove : (String, Array[@base_common.Uri]) -> Unit
}

///|
/// Narrows a concrete marker store to the capabilities required by the
/// decorations adapter. Disposing the handle's returned subscriptions never
/// disposes the caller-owned store.
pub fn MarkerService::marker_service_handle(
  self : MarkerService,
) -> MarkerServiceHandle {
  {
    on_did_change_markers: listener => self.on_did_change_markers(listener),
    read: options => self.read(options),
    remove: (owner, resources) => self.remove(owner, resources),
  }
}

///|
/// Subscribes to marker-store changes through the borrowed adapter.
pub fn MarkerServiceHandle::on_did_change_markers(
  self : MarkerServiceHandle,
  listener : (Array[@base_common.Uri]) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_markers)(listener)
}

///|
/// Reads markers through the borrowed adapter.
pub fn MarkerServiceHandle::read(
  self : MarkerServiceHandle,
  options : MarkerReadOptions,
) -> Array[Marker] {
  (self.read)(options)
}

///|
/// Removes the owner's markers for the supplied resources through the borrowed
/// adapter.
pub fn MarkerServiceHandle::remove(
  self : MarkerServiceHandle,
  owner : String,
  resources : Array[@base_common.Uri],
) -> Unit {
  (self.remove)(owner, resources)
}

///|
/// Production marker-decoration capabilities consumed by Viewer and editor
/// contributions. The concrete decoration service retains lifecycle ownership;
/// leases and subscriptions returned here remain independently disposable.
pub struct MarkerDecorationsHandle {
  priv acquire_model : (@model.TextModel) -> @base_common.Disposable
  priv on_did_change_marker_decorations : ((@model.TextModel) -> Unit) -> @base_common.Disposable
  priv get_live_markers_for_model : (@model.TextModel) -> Array[
    (@base_common.Range, Marker),
  ]
}

///|
/// Narrows a concrete decoration service to the production Viewer surface.
pub fn MarkerDecorationsService::marker_decorations_handle(
  self : MarkerDecorationsService,
) -> MarkerDecorationsHandle {
  {
    acquire_model: model => self.acquire_model(model),
    on_did_change_marker_decorations: listener => {
      self.on_did_change_marker_decorations(listener)
    },
    get_live_markers_for_model: model => self.get_live_markers_for_model(model),
  }
}

///|
/// Acquires one model-scoped decoration lease.
pub fn MarkerDecorationsHandle::acquire_model(
  self : MarkerDecorationsHandle,
  model : @model.TextModel,
) -> @base_common.Disposable {
  (self.acquire_model)(model)
}

///|
/// Subscribes to changes in live marker decorations.
pub fn MarkerDecorationsHandle::on_did_change_marker_decorations(
  self : MarkerDecorationsHandle,
  listener : (@model.TextModel) -> Unit,
) -> @base_common.Disposable {
  (self.on_did_change_marker_decorations)(listener)
}

///|
/// Returns live marker decorations for this exact model identity.
pub fn MarkerDecorationsHandle::get_live_markers_for_model(
  self : MarkerDecorationsHandle,
  model : @model.TextModel,
) -> Array[(@base_common.Range, Marker)] {
  (self.get_live_markers_for_model)(model)
}

///|
/// Closed marker backing accepted by `ViewerServices`: either a caller-owned
/// store from which the bundle creates its decorations adapter, or an already
/// adapted caller-owned decoration service.
pub(all) enum MarkerDecorationsSource {
  MarkerStore(MarkerServiceHandle)
  Decorations(MarkerDecorationsHandle)
}
