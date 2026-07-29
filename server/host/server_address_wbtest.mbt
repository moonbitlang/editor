///|
test "wildcard bind reports loopback and discovered LAN URLs" {
  debug_inspect(
    editor_server_listening_messages("0.0.0.0", 5173, Some("192.168.1.24")),
    content=(
      #|[
      #|  "Readonly editor native server listening on:",
      #|  "  Local:   http://127.0.0.1:5173/",
      #|  "  Network: http://192.168.1.24:5173/",
      #|  "  WARNING: no authentication; use only on a trusted network.",
      #|]
    ),
  )
}

///|
test "wildcard bind explains LAN fallback when route discovery fails" {
  debug_inspect(
    editor_server_listening_messages("0.0.0.0", 4173, None),
    content=(
      #|[
      #|  "Readonly editor native server listening on:",
      #|  "  Local:   http://127.0.0.1:4173/",
      #|  "  Network: use this device's LAN IPv4 address on port 4173",
      #|  "  WARNING: no authentication; use only on a trusted network.",
      #|]
    ),
  )
}

///|
test "concrete binds report only reachable listener routes" {
  debug_inspect(
    editor_server_listening_messages("127.0.0.1", 5173, None),
    content=(
      #|[
      #|  "Readonly editor native server listening on:",
      #|  "  Local:   http://127.0.0.1:5173/",
      #|]
    ),
  )
  debug_inspect(
    editor_server_listening_messages("192.168.1.24", 5173, None),
    content=(
      #|[
      #|  "Readonly editor native server listening on:",
      #|  "  Network: http://192.168.1.24:5173/",
      #|  "  WARNING: no authentication; use only on a trusted network.",
      #|]
    ),
  )
}

///|
test "IPv4 formatter preserves network byte order" {
  assert_eq(format_ipv4_address(0xc0a80118), "192.168.1.24")
}
