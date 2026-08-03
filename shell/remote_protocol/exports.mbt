///|
/// Current client/server wire-protocol version.
pub fn protocol_version() -> Int {
  protocol_version_impl()
}

///|
/// Accepts only the exact current protocol version.
pub fn negotiate_protocol_version(version : Int) -> ProtocolNegotiation {
  negotiate_protocol_version_impl(version)
}
