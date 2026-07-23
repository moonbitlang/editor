///|
pub struct StartupEvent {
  message : String
}

///|
pub fn startup_event() -> StartupEvent {
  { message: "readonly fixture ready" }
}
