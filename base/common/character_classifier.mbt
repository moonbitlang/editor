// Port of Monaco/VS Code's CharacterClassifier.
//
// Source: vscode/src/vs/editor/common/core/characterClassifier.ts
//   with toUint8 from vscode/src/vs/base/common/uint.ts
// (checked-in vscode submodule).
//
// A fast character classifier: a dense Uint8 map for ASCII (0..255) plus a
// sparse map for the rest. Values are clamped to a byte.

///|
fn to_uint8(v : Int) -> Int {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
/// Classifies char codes into small integer buckets.
pub struct CharacterClassifier {
  ascii_map : Array[Int]
  map : Map[Int, Int]
  default_value : Int
}

///|
#alias(new, deprecated)
pub fn CharacterClassifier::CharacterClassifier(
  default_value : Int,
) -> CharacterClassifier {
  let dv = to_uint8(default_value)
  { ascii_map: Array::make(256, dv), map: Map([]), default_value: dv }
}

///|
pub fn CharacterClassifier::set(
  self : CharacterClassifier,
  char_code : Int,
  value : Int,
) -> Unit {
  let v = to_uint8(value)
  if char_code >= 0 && char_code < 256 {
    self.ascii_map[char_code] = v
  } else {
    self.map[char_code] = v
  }
}

///|
pub fn CharacterClassifier::get(
  self : CharacterClassifier,
  char_code : Int,
) -> Int {
  if char_code >= 0 && char_code < 256 {
    self.ascii_map[char_code]
  } else {
    // Mirrors upstream `this._map.get(charCode) || this._defaultValue`: a stored
    // 0 (falsy) also falls back to the default value.
    match self.map.get(char_code) {
      Some(v) => if v != 0 { v } else { self.default_value }
      None => self.default_value
    }
  }
}

///|
pub fn CharacterClassifier::clear(self : CharacterClassifier) -> Unit {
  for i in 0..<256 {
    self.ascii_map[i] = self.default_value
  }
  self.map.clear()
}

///|
/// A set of char codes, backed by a `CharacterClassifier`.
pub struct CharacterSet {
  actual : CharacterClassifier
}

///|
#alias(new, deprecated)
pub fn CharacterSet::CharacterSet() -> CharacterSet {
  { actual: CharacterClassifier(0) }
}

///|
pub fn CharacterSet::add(self : CharacterSet, char_code : Int) -> Unit {
  self.actual.set(char_code, 1)
}

///|
pub fn CharacterSet::has(self : CharacterSet, char_code : Int) -> Bool {
  self.actual.get(char_code) == 1
}

///|
pub fn CharacterSet::clear(self : CharacterSet) -> Unit {
  self.actual.clear()
}
