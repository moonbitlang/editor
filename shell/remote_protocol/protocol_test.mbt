///|
test "encodes and decodes document client packets" {
  let uri = expect_uri(
    "readonly-remote://workspace/tests/fixtures/workspace/src/main.mbt",
  )
  let packet = @remote_protocol.OpenDocument({ id: "open-1", uri })
  let encoded = packet.to_json().stringify()
  assert_true(encoded.contains("\"type\":\"OpenDocument\""))
  assert_true(encoded.contains("\"version\":4"))

  match @remote_protocol.decode_client_packet(encoded) {
    DecodedClientPacket(OpenDocument(request)) => {
      assert_eq(request.id, "open-1")
      assert_eq(request.uri.to_string(), uri.to_string())
    }
    DecodedClientPacket(_) => fail("unexpected client packet")
    ClientPacketDecodeError(error) => fail(error.message)
  }
}

///|
test "encodes and decodes semantic client packets" {
  let uri = expect_uri("readonly-remote://workspace/src/main.mbt")
  let hover = @remote_protocol.Hover({
    id: "hover-1",
    uri,
    document_revision: "rev-4",
    offset: 17,
  })
  match @remote_protocol.decode_client_packet(hover.to_json().stringify()) {
    DecodedClientPacket(Hover(request)) => {
      assert_eq(request.id, "hover-1")
      assert_eq(request.document_revision, "rev-4")
      assert_eq(request.offset, 17)
    }
    DecodedClientPacket(_) => fail("unexpected hover packet")
    ClientPacketDecodeError(error) => fail(error.message)
  }

  let definition = @remote_protocol.Definition({
    id: "def-1",
    uri,
    document_revision: "rev-4",
    offset: 18,
  })
  match
    @remote_protocol.decode_client_packet(definition.to_json().stringify()) {
    DecodedClientPacket(Definition(request)) => {
      assert_eq(request.id, "def-1")
      assert_eq(request.offset, 18)
    }
    DecodedClientPacket(_) => fail("unexpected definition packet")
    ClientPacketDecodeError(error) => fail(error.message)
  }

  let references = @remote_protocol.References({
    id: "refs-1",
    uri,
    document_revision: "rev-4",
    offset: 19,
  })
  match
    @remote_protocol.decode_client_packet(references.to_json().stringify()) {
    DecodedClientPacket(References(request)) => {
      assert_eq(request.id, "refs-1")
      assert_eq(request.document_revision, "rev-4")
      assert_eq(request.offset, 19)
    }
    DecodedClientPacket(_) => fail("unexpected references packet")
    ClientPacketDecodeError(error) => fail(error.message)
  }

  let symbols = @remote_protocol.DocumentSymbols({
    id: "symbols-1",
    uri,
    document_revision: "rev-5",
  })
  match @remote_protocol.decode_client_packet(symbols.to_json().stringify()) {
    DecodedClientPacket(DocumentSymbols(request)) => {
      assert_eq(request.id, "symbols-1")
      assert_eq(request.document_revision, "rev-5")
    }
    DecodedClientPacket(_) => fail("unexpected document symbols packet")
    ClientPacketDecodeError(error) => fail(error.message)
  }
}

///|
test "encodes and decodes directory resolve packets" {
  let root_uri = expect_uri("readonly-remote://workspace")
  let request = @remote_protocol.ResolveDirectory({
    id: "resolve-1",
    uri: root_uri,
  })
  let encoded = request.to_json().stringify()
  assert_true(encoded.contains("\"type\":\"ResolveDirectory\""))
  match @remote_protocol.decode_client_packet(encoded) {
    DecodedClientPacket(ResolveDirectory(decoded)) => {
      assert_eq(decoded.id, "resolve-1")
      assert_eq(decoded.uri.to_string(), "readonly-remote://workspace")
    }
    DecodedClientPacket(_) => fail("unexpected resolve directory packet")
    ClientPacketDecodeError(error) => fail(error.message)
  }
  let src_uri = expect_uri("readonly-remote://workspace/src")
  let resolved = @remote_protocol.DirectoryResolved({
    id: "resolve-1",
    stat: {
      uri: root_uri,
      name: "workspace",
      kind: Directory,
      children: Some([
        {
          uri: expect_uri("readonly-remote://workspace/moon.mod"),
          name: "moon.mod",
          kind: File,
          children: None,
        },
        { uri: src_uri, name: "src", kind: Directory, children: None },
      ]),
    },
  })
  match @remote_protocol.decode_server_packet(resolved.to_json().stringify()) {
    DecodedServerPacket(DirectoryResolved(payload)) => {
      assert_eq(payload.id, "resolve-1")
      assert_eq(payload.stat.uri.to_string(), "readonly-remote://workspace")
      assert_eq(payload.stat.name, "workspace")
      assert_true(payload.stat.kind == Directory)
      match payload.stat.children {
        Some(children) => {
          assert_eq(children.length(), 2)
          assert_eq(children[0].name, "moon.mod")
          assert_true(children[0].kind == File)
          assert_true(children[0].children is None)
          assert_eq(
            children[1].uri.to_string(),
            "readonly-remote://workspace/src",
          )
          assert_true(children[1].kind == Directory)
          assert_true(children[1].children is None)
        }
        None => fail("expected resolved children")
      }
    }
    DecodedServerPacket(_) => fail("unexpected directory resolved packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  // An empty resolved directory stays Some([]) across the wire; only
  // unresolved children round-trip as None.
  let empty = @remote_protocol.DirectoryResolved({
    id: "resolve-2",
    stat: { uri: src_uri, name: "src", kind: Directory, children: Some([]) },
  })
  match @remote_protocol.decode_server_packet(empty.to_json().stringify()) {
    DecodedServerPacket(DirectoryResolved(payload)) =>
      match payload.stat.children {
        Some(children) => assert_eq(children.length(), 0)
        None => fail("expected empty children")
      }
    DecodedServerPacket(_) => fail("unexpected empty directory packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }
}

///|
test "encodes and decodes server document and language packets" {
  let uri = expect_uri(
    "readonly-remote://workspace/tests/fixtures/workspace/src/main.mbt",
  )
  let document = @workspace.DocumentSnapshot(
    uri, "main.mbt", "moonbit", "rev-2", "pub fn main {}\n",
  )
  let loaded = @remote_protocol.DocumentLoaded({ id: "open-1", document })
  match @remote_protocol.decode_server_packet(loaded.to_json().stringify()) {
    DecodedServerPacket(DocumentLoaded(payload)) => {
      assert_eq(payload.id, "open-1")
      assert_eq(payload.document.uri.to_string(), uri.to_string())
      assert_eq(payload.document.revision, "rev-2")
    }
    DecodedServerPacket(_) => fail("unexpected server packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  let hover = @remote_protocol.HoverResult({
    id: "hover-1",
    uri,
    revision: "rev-2",
    hover: Some({
      range: Range(1, 8, 1, 12),
      contents: [PlainText("fn main"), Markdown("**main**")],
    }),
  })
  match @remote_protocol.decode_server_packet(hover.to_json().stringify()) {
    DecodedServerPacket(HoverResult(payload)) =>
      match payload.hover {
        Some(item) => {
          assert_eq(payload.revision, "rev-2")
          assert_eq(item.contents.length(), 2)
          assert_hover_plaintext(item, 0, "fn main")
          assert_hover_markdown(item, 1, "**main**")
          assert_true(item.range == Range(1, 8, 1, 12))
        }
        None => fail("missing hover")
      }
    DecodedServerPacket(_) => fail("unexpected hover result packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  let references_result = @remote_protocol.ReferencesResult({
    id: "refs-1",
    uri,
    revision: "rev-2",
    references: [
      {
        uri,
        range: Range(1, 8, 1, 12),
        line: 1,
        column: 8,
        line_text: "pub fn main {}",
      },
      { uri, range: Range(2, 1, 2, 5), line: 2, column: 1, line_text: "main()" },
    ],
  })
  match
    @remote_protocol.decode_server_packet(
      references_result.to_json().stringify(),
    ) {
    DecodedServerPacket(ReferencesResult(payload)) => {
      assert_eq(payload.id, "refs-1")
      assert_eq(payload.revision, "rev-2")
      assert_eq(payload.references.length(), 2)
      assert_eq(payload.references[0].line, 1)
      assert_eq(payload.references[0].column, 8)
      assert_eq(payload.references[0].line_text, "pub fn main {}")
      assert_true(payload.references[1].range == Range(2, 1, 2, 5))
    }
    DecodedServerPacket(_) => fail("unexpected references result packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  let empty_references = @remote_protocol.ReferencesResult({
    id: "refs-2",
    uri,
    revision: "rev-3",
    references: [],
  })
  match
    @remote_protocol.decode_server_packet(
      empty_references.to_json().stringify(),
    ) {
    DecodedServerPacket(ReferencesResult(payload)) => {
      assert_eq(payload.references.length(), 0)
      assert_eq(payload.revision, "rev-3")
    }
    DecodedServerPacket(_) => fail("unexpected empty references packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  // Diagnostics packets are server pushes: no request id on the wire.
  let diagnostics = @remote_protocol.ServerPacket::Diagnostics({
    uri,
    revision: "rev-2",
    diagnostics: [
      {
        range: Range(1, 1, 1, 4),
        severity: Warning,
        message: "check me",
        tags: None,
      },
    ],
  })
  let encoded_diagnostics = diagnostics.to_json().stringify()
  assert_true(!encoded_diagnostics.contains("\"id\""))
  match @remote_protocol.decode_server_packet(encoded_diagnostics) {
    DecodedServerPacket(Diagnostics(payload)) => {
      assert_eq(payload.uri.to_string(), uri.to_string())
      assert_eq(payload.revision, "rev-2")
      assert_eq(payload.diagnostics.length(), 1)
      assert_eq(payload.diagnostics[0].message, "check me")
    }
    DecodedServerPacket(_) => fail("unexpected diagnostics packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  let hint_diagnostics = @remote_protocol.ServerPacket::Diagnostics({
    uri,
    revision: "rev-3",
    diagnostics: [
      {
        range: Range(1, 1, 1, 4),
        severity: Hint,
        message: "unused",
        tags: Some([Unnecessary, Deprecated]),
      },
    ],
  })
  match
    @remote_protocol.decode_server_packet(
      hint_diagnostics.to_json().stringify(),
    ) {
    DecodedServerPacket(Diagnostics(payload)) => {
      assert_eq(payload.diagnostics.length(), 1)
      assert_true(payload.diagnostics[0].severity == Hint)
      assert_true(
        payload.diagnostics[0].tags == Some([Unnecessary, Deprecated]),
      )
    }
    DecodedServerPacket(_) => fail("unexpected diagnostics packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }

  let symbols = @remote_protocol.DocumentSymbolsResult({
    id: "symbols-1",
    uri,
    revision: "rev-2",
    symbols: [{ name: "main", kind: "function", range: Range(1, 8, 1, 12) }],
  })
  match @remote_protocol.decode_server_packet(symbols.to_json().stringify()) {
    DecodedServerPacket(DocumentSymbolsResult(payload)) => {
      assert_eq(payload.symbols.length(), 1)
      assert_eq(payload.symbols[0].name, "main")
    }
    DecodedServerPacket(_) => fail("unexpected document symbols result packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }
}

///|
test "round-trips document text containing control characters" {
  // Form feed and vertical tab are valid in source files but invalid in
  // JSON strings unless escaped; the old hand-rolled escaping emitted
  // MoonBit-style `\u{c}` and broke the peer's decode.
  let uri = expect_uri("readonly-remote://workspace/src/control.mbt")
  let text = "form\u{0c}feed\u{0b}tab\tquote\"backslash\\\nend"
  let document = @workspace.DocumentSnapshot(
    uri, "control.mbt", "moonbit", "rev-1", text,
  )
  let loaded = @remote_protocol.DocumentLoaded({ id: "open-ctl", document })
  match @remote_protocol.decode_server_packet(loaded.to_json().stringify()) {
    DecodedServerPacket(DocumentLoaded(payload)) =>
      assert_eq(payload.document.text, text)
    DecodedServerPacket(_) => fail("unexpected server packet")
    ServerPacketDecodeError(error) => fail(error.message)
  }
}

///|
test "reports protocol decode errors" {
  match @remote_protocol.decode_client_packet("{") {
    ClientPacketDecodeError(error) =>
      assert_true(error.code == ProtocolInvalidJson)
    DecodedClientPacket(_) => fail("expected invalid JSON error")
  }

  match
    @remote_protocol.decode_client_packet(
      "{\"version\":99,\"type\":\"OpenDocument\",\"id\":\"x\",\"uri\":\"readonly-remote://workspace/a.mbt\"}",
    ) {
    ClientPacketDecodeError(error) =>
      assert_true(error.code == ProtocolUnsupportedVersion)
    DecodedClientPacket(_) => fail("expected unsupported version error")
  }

  match
    @remote_protocol.decode_client_packet(
      "{\"version\":4,\"type\":\"OpenDocument\",\"id\":\"x\",\"uri\":\"bad\"}",
    ) {
    ClientPacketDecodeError(error) =>
      assert_true(error.code == ProtocolInvalidUri)
    DecodedClientPacket(_) => fail("expected invalid URI error")
  }
}

///|
test "negotiates protocol versions" {
  match @remote_protocol.negotiate_protocol_version(4) {
    ProtocolAccepted(version) => assert_eq(version, 4)
    ProtocolRejected(error) => fail(error.message)
  }

  match @remote_protocol.negotiate_protocol_version(3) {
    ProtocolRejected(error) =>
      assert_true(error.code == ProtocolUnsupportedVersion)
    ProtocolAccepted(_) => fail("expected rejected protocol")
  }
}

///|
fn assert_hover_plaintext(
  hover : @language.Hover,
  index : Int,
  expected : String,
) -> Unit raise {
  match hover.contents.get(index) {
    Some(PlainText(text)) => assert_eq(text, expected)
    Some(Markdown(_)) => fail("expected plaintext hover")
    None => fail("missing hover content")
  }
}

///|
fn assert_hover_markdown(
  hover : @language.Hover,
  index : Int,
  expected : String,
) -> Unit raise {
  match hover.contents.get(index) {
    Some(Markdown(text)) => assert_eq(text, expected)
    Some(PlainText(_)) => fail("expected markdown hover")
    None => fail("missing hover content")
  }
}

///|
fn expect_uri(raw : String) -> @base_common.Uri raise {
  @base_common.Uri::parse(raw)
}
