///|
suberror FixtureError String

///|
fn risky_step(flag : Bool) -> Int raise FixtureError {
  if flag {
    raise FixtureError("fixture failure")
  }
  1
}

///|
pub fn guarded_step() -> Int {
  risky_step(false) catch {
    _ => 0
  }
}
