// Deterministic browser exercise for async model-owned features. The provider
// calls stay suspended on per-call gates until Playwright releases them, so
// completion order is an explicit input instead of a timing assumption.

///|
priv struct AsyncFeatureGate {
  mut resolver : ((String) -> Unit)?
}

///|
fn AsyncFeatureGate::new() -> AsyncFeatureGate {
  { resolver: None }
}

///|
async fn AsyncFeatureGate::wait(self : AsyncFeatureGate) -> String noraise {
  @js.suspend((resolve : (String) -> Unit, _reject : (Error) -> Unit) => {
    self.resolver = Some(resolve)
  }) catch {
    _ => "empty"
  }
}

///|
fn AsyncFeatureGate::release(self : AsyncFeatureGate, outcome : String) -> Bool {
  match self.resolver {
    Some(resolve) => {
      self.resolver = None
      resolve(outcome)
      true
    }
    None => false
  }
}

///|
priv struct AsyncFeatureCall {
  id : Int
  kind : String
  model : @model.TextModel
  model_id : Int
  internal_version : Int
  token : @language.CancellationToken
  gate : AsyncFeatureGate
  mut released : Bool
  mut provider_settled : Bool
  mut settled : Bool
  mut outcome : String
}

///|
fn AsyncFeatureCall::to_json(self : AsyncFeatureCall) -> Json {
  Json::object({
    "id": self.id.to_json(),
    "kind": self.kind.to_json(),
    "modelId": self.model_id.to_json(),
    "uri": self.model.uri.to_string().to_json(),
    "hostVersion": self.model.version.to_json(),
    "revision": self.model.revision.to_json(),
    "internalVersion": self.internal_version.to_json(),
    "released": self.released.to_json(),
    "providerSettled": self.provider_settled.to_json(),
    "settled": self.settled.to_json(),
    "outcome": self.outcome.to_json(),
    "cancelled": self.token.is_cancellation_requested().to_json(),
  })
}

///|
priv struct AsyncHoverReport {
  ok : Bool
  revision : String
}

///|
fn AsyncHoverReport::to_json(self : AsyncHoverReport) -> Json {
  { "ok": self.ok.to_json(), "revision": self.revision.to_json() }
}

///|
priv struct AsyncFeatureHarness {
  next_call_id : Ref[Int]
  calls : Array[AsyncFeatureCall]
  models : Array[@model.TextModel]
}

///|
fn AsyncFeatureHarness::new() -> AsyncFeatureHarness {
  { next_call_id: Ref(1), calls: [], models: [] }
}

///|
fn AsyncFeatureHarness::model_id(
  self : AsyncFeatureHarness,
  model : @model.TextModel,
) -> Int {
  for index, known in self.models {
    if known.same(model) {
      return index + 1
    }
  }
  self.models.push(model)
  self.models.length()
}

///|
fn AsyncFeatureHarness::begin_call(
  self : AsyncFeatureHarness,
  kind : String,
  model : @model.TextModel,
  token : @language.CancellationToken,
) -> AsyncFeatureCall {
  let call : AsyncFeatureCall = {
    id: self.next_call_id.val,
    kind,
    model,
    model_id: self.model_id(model),
    internal_version: model.get_version_id(),
    token,
    gate: AsyncFeatureGate::new(),
    released: false,
    provider_settled: false,
    settled: false,
    outcome: "",
  }
  self.next_call_id.val += 1
  self.calls.push(call)
  call
}

///|
fn AsyncFeatureHarness::started_json(self : AsyncFeatureHarness) -> String {
  Json::array(self.calls.map(call => call.to_json())).stringify()
}

///|
fn AsyncFeatureHarness::release(
  self : AsyncFeatureHarness,
  call_id : Int,
  outcome : String,
) -> Bool {
  guard outcome.length() > 0 else { return false }
  for call in self.calls {
    if call.id == call_id {
      if call.released || call.settled {
        return false
      }
      let accepted = call.gate.release(outcome)
      if accepted {
        call.released = true
        call.outcome = outcome
      }
      return accepted
    }
  }
  false
}

///|
priv struct DeferredAsyncFeatureProvider {
  harness : AsyncFeatureHarness
}

///|
priv suberror DeferredAsyncFeatureProviderError {
  DeferredAsyncFeatureProviderError
}

///|
/// Marks public `settled` in the next task after the provider returned. A task
/// boundary drains the complete recursively queued promise-reaction chain, so
/// negative teardown assertions cannot pass before the Viewer apply boundary.
fn AsyncFeatureCall::settle_after_consumer_turn(
  self : AsyncFeatureCall,
) -> Unit {
  self.provider_settled = true
  async_feature_consumer_barrier(() => self.settled = true)
}

///|
extern "js" fn async_feature_consumer_barrier(callback : () -> Unit) -> Unit =
  #| (callback) => setTimeout(callback, 0)

///|
impl @language.HoverProvider for DeferredAsyncFeatureProvider with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  let call = self.harness.begin_call("hover", model, token)
  let outcome = call.gate.wait()
  call.settle_after_consumer_turn()
  if outcome == "error" {
    raise DeferredAsyncFeatureProviderError
  }
  if outcome == "empty" ||
    (outcome == "cancelled-empty" && token.is_cancellation_requested()) {
    None
  } else {
    let offset = model.get_offset_at(position)
    let end_offset = Int::min(offset + 1, model.snapshot.text.length())
    Some({
      range: model.get_range_at(offset, end_offset),
      contents: [PlainText(outcome)],
    })
  }
}

///|
fn async_feature_source(marker : String) -> String {
  "pub fn target() -> Int { // " + marker + "\n  1\n}\n"
}

///|
fn async_feature_uri() -> @base_common.Uri {
  try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/async-features.mbt",
  )
}

///|
fn async_feature_model(source : String) -> @model.TextModel {
  TextModel(
    async_feature_uri(),
    "async-features.mbt",
    "moonbit",
    7,
    "shared-host-revision",
    source,
  )
}

///|
fn async_feature_state_json(
  harness : AsyncFeatureHarness,
  viewer : @viewer.Viewer,
  reports : Array[AsyncHoverReport],
  disposed : Ref[Bool],
) -> String {
  let mut settled = 0
  let mut released = 0
  for call in harness.calls {
    if call.settled {
      settled += 1
    }
    if call.released {
      released += 1
    }
  }
  let (
    current_model_id,
    current_uri,
    current_host_version,
    current_revision,
    internal_version,
  ) = match viewer.get_model() {
    Some(model) =>
      (
        harness.model_id(model),
        model.uri.to_string(),
        model.version,
        model.revision,
        model.get_version_id(),
      )
    None => (-1, "", -1, "", -1)
  }
  Json::object({
    "started": harness.calls.length().to_json(),
    "released": released.to_json(),
    "settled": settled.to_json(),
    "pending": (harness.calls.length() - settled).to_json(),
    "resolveReports": reports.length().to_json(),
    "reports": Json::array(reports.map(report => report.to_json())),
    "attached": @viewer_testing.has_model(viewer.get_id()).to_json(),
    "disposed": disposed.val.to_json(),
    "currentModelId": current_model_id.to_json(),
    "currentUri": current_uri.to_json(),
    "currentHostVersion": current_host_version.to_json(),
    "currentRevision": current_revision.to_json(),
    "internalVersion": internal_version.to_json(),
  }).stringify()
}

///|
fn run_async_model_features_test() -> Unit {
  guard mount_async_feature_host() is Some(host) else { return }
  let harness = AsyncFeatureHarness::new()
  let provider = DeferredAsyncFeatureProvider::{ harness, }
  let languages = @languages.Languages()
  languages.register_hover_provider(LanguageId("moonbit"), provider) |> ignore
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    log_service=log_handle,
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(
      soft_wrap=false,
      folding=false,
      placeholder="async feature fixture detached",
    ),
  )
  let reports : Array[AsyncHoverReport] = []
  @viewer_testing.on_did_resolve_hover(viewer.get_id(), event => {
    reports.push({ ok: event.ok, revision: event.revision })
  })
  |> ignore
  let disposed = Ref(false)
  viewer.set_model(Some(async_feature_model(async_feature_source("initial"))))
  viewer.handle_initialized()
  install_async_feature_controls(
    () => harness.started_json(),
    () => async_feature_state_json(harness, viewer, reports, disposed),
    (call_id, outcome) => harness.release(call_id, outcome),
    value => viewer.set_value(value),
    value => {
      viewer.set_model(Some(async_feature_model(value)))
      viewer.handle_initialized()
    },
    () => {
      match viewer.get_model() {
        Some(model) => model.dispose()
        None => ()
      }
    },
    () => viewer.set_model(None),
    () => {
      viewer.dispose()
      services.dispose()
      disposed.val = true
    },
  )
}

///|
fn mount_async_feature_host() -> @rdom.Element? {
  match @rdom.document().query_selector("#app").to_option() {
    Some(app) => {
      let shell = @rdom.document().create_element("main")
      shell.set_attribute("class", "editor-shell async-feature-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = @rdom.document().create_element("div")
      host.set_attribute("class", "viewer-host async-feature-host")
      host.set_attribute("style", "height:180px;width:640px;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}

///|
extern "js" fn install_async_feature_controls(
  started_json : () -> String,
  state_json : () -> String,
  release : (Int, String) -> Bool,
  set_value : (String) -> Unit,
  replace_same_uri : (String) -> Unit,
  dispose_model : () -> Unit,
  detach : () -> Unit,
  dispose : () -> Unit,
) -> Unit =
  #| (startedJson, stateJson, release, setValue, replaceSameUri, disposeModel, detach, dispose) => {
  #|   globalThis.__asyncFeatureControls = {
  #|     started: () => JSON.parse(startedJson()),
  #|     state: () => JSON.parse(stateJson()),
  #|     release,
  #|     set_value: setValue,
  #|     replace_same_uri: replaceSameUri,
  #|     dispose_model: disposeModel,
  #|     detach,
  #|     dispose,
  #|   };
  #| }
