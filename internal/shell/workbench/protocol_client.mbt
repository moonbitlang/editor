///|
/// In-flight protocol requests awaiting their response packet, keyed by
/// request id. A module-level registry, like `browser_dispatch`.
let pending_requests : Map[String, (@remote_protocol.ServerPacket) -> Unit] = Map([],
)

///|
let request_counter : Ref[Int] = Ref(0)

///|
/// Sends a client packet over the live protocol socket. Installed at mount
/// so async provider code can transmit without threading a scheduler.
let protocol_send : Ref[((@remote_protocol.ClientPacket) -> Unit)?] = Ref(None)

///|
fn send_protocol_packet(packet : @remote_protocol.ClientPacket) -> Unit {
  match protocol_send.val {
    Some(send) => send(packet)
    None => ()
  }
}

///|
fn next_request_id(prefix : String) -> String {
  request_counter.val = request_counter.val + 1
  prefix + "-" + request_counter.val.to_string()
}

///|
/// Sends a request packet and suspends until the response with the same id
/// arrives. Correlation is by request id, so two in-flight requests of the
/// same kind can no longer cross. The reject continuation is never called;
/// failures resolve as `RemoteError` packets instead.
async fn protocol_request(
  prefix : String,
  make_packet : (String) -> @remote_protocol.ClientPacket,
) -> @remote_protocol.ServerPacket noraise {
  let id = next_request_id(prefix)
  @js.suspend((
    resolve : (@remote_protocol.ServerPacket) -> Unit,
    _reject : (Error) -> Unit,
  ) => {
    pending_requests[id] = resolve
    send_protocol_packet(make_packet(id))
  }) catch {
    _ =>
      RemoteError(
        ProtocolError(
          ProtocolProviderError,
          "Protocol request failed.",
          request_id=id,
        ),
      )
  }
}

///|
/// Routes a decoded server packet to its waiting request, if any. Returns
/// whether the packet was consumed as a response.
fn resolve_pending_response(packet : @remote_protocol.ServerPacket) -> Bool {
  let id = server_packet_request_id(packet)
  if id == "" {
    return false
  }
  match pending_requests.get(id) {
    Some(resolve) => {
      pending_requests.remove(id)
      resolve(packet)
      true
    }
    None => false
  }
}

///|
/// Fails every in-flight request, used when the socket drops so suspended
/// providers resolve instead of leaking.
fn fail_pending_requests(message : String) -> Unit {
  let ids : Array[String] = []
  for id, _resolve in pending_requests {
    ids.push(id)
  }
  for id in ids {
    match pending_requests.get(id) {
      Some(resolve) => {
        pending_requests.remove(id)
        resolve(
          RemoteError(
            ProtocolError(ProtocolProviderError, message, request_id=id),
          ),
        )
      }
      None => ()
    }
  }
}

///|
fn server_packet_request_id(packet : @remote_protocol.ServerPacket) -> String {
  match packet {
    DirectoryResolved(payload) => payload.id
    DocumentLoaded(payload) => payload.id
    DocumentChanged(payload) => payload.id
    // Diagnostics packets are server pushes and never answer a request.
    Diagnostics(_) => ""
    HoverResult(payload) => payload.id
    DefinitionResult(payload) => payload.id
    ReferencesResult(payload) => payload.id
    DocumentSymbolsResult(payload) => payload.id
    RemoteError(error) => error.request_id
  }
}

///|
fn connect_protocol_cmd(emit : @rabbita.Emit[WorkbenchMsg]) -> @rabbita.Cmd {
  @websocket.connect(
    protocol_connection_id(),
    protocol_websocket_url(),
    on_event=event => emit(ProtocolEvent(event)),
    failed=message => emit(ProtocolSendFailed(message)),
  )
}

///|
fn send_client_packet_cmd(
  emit : @rabbita.Emit[WorkbenchMsg],
  packet : @remote_protocol.ClientPacket,
) -> @rabbita.Cmd {
  @websocket.send(
    protocol_connection_id(),
    Text(packet.to_json().stringify()),
    failed=message => emit(ProtocolSendFailed(message)),
  )
}

///|
fn protocol_connection_id() -> String {
  "readonly-editor-protocol"
}
