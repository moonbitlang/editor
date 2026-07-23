// Port of `vscode/src/vs/editor/common/diff/linesDiffComputers.ts` (vscode
// checked-in submodule): the computer
// registry.
//
// Parity ledger: `getDefault` — PORTED (package-level fn; the viewer has no
// namespace object). `getLegacy` — N-A (the legacy engine is not ported; the
// default computer is piediff-backed, see
// `default_lines_diff_computer.mbt`).

///|
/// `linesDiffComputers.getDefault()` (`linesDiffComputers.ts:11`).
pub fn get_default() -> DefaultLinesDiffComputer {
  DefaultLinesDiffComputer()
}
