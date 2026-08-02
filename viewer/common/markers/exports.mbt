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
/// Compatibility shim that clears markers from every owner for one resource.
pub fn MarkerService::clear_resource(
  self : MarkerService,
  resource : @base_common.Uri,
) -> Unit {
  for owner in self.read(MarkerReadOptions(resource~)).map(m => m.owner) {
    self.remove(owner, [resource])
  }
}

///|
/// Compatibility shim returning markers for one resource, optionally capped.
pub fn MarkerService::markers_for_resource(
  self : MarkerService,
  resource : @base_common.Uri,
  limit? : Int = 0,
) -> Array[Marker] {
  self.read(MarkerReadOptions(resource~, take=limit))
}
