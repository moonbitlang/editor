///| Port of the `network.ts` `Schemas` constants the URI stack consumes
/// (network.ts:44/18/48). The rest of `network.ts` (RemoteAuthorities,
/// AppResourcePath, COI, …) is out of scope.

///|
/// `Schemas.file` (network.ts:44).
pub let schemas_file : String = "file"

///|
/// `Schemas.inMemory` (network.ts:18) — models that exist in memory only and
/// have no correspondence on a server or such.
pub let schemas_in_memory : String = "inmemory"

///|
/// `Schemas.untitled` (network.ts:48).
pub let schemas_untitled : String = "untitled"
