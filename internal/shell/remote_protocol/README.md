# internal/shell/remote_protocol

MoonBit-owned JSON contract between the reference browser workbench and native
server. Protocol version `4` is carried by every packet and must match exactly.

## Wire contract

- Client requests: `ResolveDirectory`, `OpenDocument`, `WatchDocument`,
  `CloseDocument`, `Hover`, `Definition`, `References`, and `DocumentSymbols`.
- Server packets: directory/document results, watched `DocumentChanged` pushes,
  pushed `Diagnostics`, semantic feature results, and `RemoteError`.
- Position requests carry a document revision and UTF-16 offset; whole-document
  feature requests carry a revision. Request IDs correlate replies. Diagnostics
  deliberately have no request ID; watch pushes reuse the watch request ID.
- Decoders return structured errors for invalid JSON, version, packet shape,
  URI, or provider failure. `provider_code` preserves the lower-level category.
- Reference results add line, column, and line-text preview fields. There is no
  semantic-token packet.

The public surface is the packet/payload types plus `protocol_version`,
`negotiate_protocol_version`, `decode_client_packet`, and
`decode_server_packet`; see `pkg.generated.mbti` for exact fields.

## Boundary and validation

This package may depend on domain types and `internal/shell/workspace`, but not
on browser, viewer implementation, server routing, or native effects.

Run `moon test internal/shell/remote_protocol --target js` and `just check`.
