///|
/// Workbench-side language client: implements the `@language` provider
/// traits over the live protocol socket through `protocol_request`. The
/// workbench registers it with the viewer's selected language registry at
/// startup.
priv struct RemoteLanguageClient {
  log_service : @log.LogService
}

///|
fn register_remote_language_providers(services : WorkbenchServices) -> Unit {
  let client = RemoteLanguageClient::{ log_service: services.log_service }
  let selector = @language.LanguageSelector::LanguageFilter(
    LanguageFilter(scheme="readonly-remote"),
  )
  services.languages.register_hover_provider(selector, client) |> ignore
  services.languages.register_document_symbol_provider(selector, client)
  |> ignore
}

///|
fn RemoteLanguageClient::emit_remote_error(
  self : RemoteLanguageClient,
  operation : String,
  model : @model.TextModel,
  packet : @remote_protocol.ServerPacket,
) -> Unit {
  match packet {
    RemoteError(error) =>
      self.log_service.error(
        "language.protocol",
        "remote protocol provider error",
        details=[
          ("operation", operation),
          ("model", model.uri.to_string()),
          ("revision", model.revision),
          ("code", error.code.label()),
          ("providerCode", error.provider_code),
          ("message", error.message),
          ("requestId", error.request_id),
        ],
      )
    _ => ()
  }
}

///|
impl @language.HoverProvider for RemoteLanguageClient with fn provide_hover(
  self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  let response = protocol_request("hover", id => {
    Hover({ id, uri: model.uri, document_revision: model.revision, offset })
  })
  match response {
    HoverResult(payload) => payload.hover
    packet => {
      self.emit_remote_error("hover", model, packet)
      None
    }
  }
}

///|
/// Applies a server-pushed diagnostics packet to the marker service — the
/// sink for backend `moon check` pushes, Monaco's `setModelMarkers` path.
/// The marker-change event re-renders the viewer; no pull exists.
fn apply_remote_diagnostics_cmd(
  payload : @remote_protocol.DiagnosticsPayload,
) -> @rabbita.Cmd {
  @cmd.custom_cmd(_ => {
    workbench_services().markers.set_diagnostics(
      "moon",
      payload.uri,
      payload.diagnostics,
    )
  })
}

///|
impl @language.DocumentSymbolProvider for RemoteLanguageClient with fn provide_document_symbols(
  self,
  model,
  _token,
) {
  let response = protocol_request("symbols", id => {
    DocumentSymbols({ id, uri: model.uri, document_revision: model.revision })
  })
  match response {
    DocumentSymbolsResult(payload) => payload.symbols
    packet => {
      self.emit_remote_error("documentSymbols", model, packet)
      []
    }
  }
}
