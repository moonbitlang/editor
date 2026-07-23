///| Host-neutral tokenization scheduling contracts.

///|
/// Idle callback deadline. Callers must read `time_remaining` immediately.
pub struct TokenizationIdleDeadline {
  priv read_time_remaining : () -> Double
}

///|
/// Creates a deadline backed by a host-provided remaining-time reader.
pub fn TokenizationIdleDeadline::TokenizationIdleDeadline(
  read_time_remaining : () -> Double,
) -> TokenizationIdleDeadline {
  { read_time_remaining, }
}

///|
/// Remaining idle budget in milliseconds.
fn TokenizationIdleDeadline::time_remaining(
  self : TokenizationIdleDeadline,
) -> Double {
  (self.read_time_remaining)()
}

///|
/// FFI-free scheduling surface supplied by a browser host or deterministic test.
pub struct TokenizationScheduler {
  priv schedule_idle : ((TokenizationIdleDeadline) -> Unit) -> @base_common.Disposable
  priv schedule_zero : (() -> Unit) -> @base_common.Disposable
  priv schedule_delay : (Int, () -> Unit) -> @base_common.Disposable
  priv read_now : () -> Double
}

///|
/// Creates a scheduler from cancellable idle, zero-timeout, delayed, and clock
/// operations. All durations and clock values use milliseconds.
pub fn TokenizationScheduler::TokenizationScheduler(
  idle~ : ((TokenizationIdleDeadline) -> Unit) -> @base_common.Disposable,
  zero_timeout~ : (() -> Unit) -> @base_common.Disposable,
  delay~ : (Int, () -> Unit) -> @base_common.Disposable,
  now~ : () -> Double,
) -> TokenizationScheduler {
  {
    schedule_idle: idle,
    schedule_zero: zero_timeout,
    schedule_delay: delay,
    read_now: now,
  }
}

///|
/// Schedules cancellable idle work.
fn TokenizationScheduler::idle(
  self : TokenizationScheduler,
  callback : (TokenizationIdleDeadline) -> Unit,
) -> @base_common.Disposable {
  (self.schedule_idle)(callback)
}

///|
/// Schedules a cancellable zero-timeout continuation.
fn TokenizationScheduler::zero_timeout(
  self : TokenizationScheduler,
  callback : () -> Unit,
) -> @base_common.Disposable {
  (self.schedule_zero)(callback)
}

///|
/// Schedules a cancellable delayed continuation.
fn TokenizationScheduler::delay(
  self : TokenizationScheduler,
  milliseconds : Int,
  callback : () -> Unit,
) -> @base_common.Disposable {
  (self.schedule_delay)(milliseconds, callback)
}

///|
/// Reads the scheduler's monotonic millisecond clock.
fn TokenizationScheduler::now(self : TokenizationScheduler) -> Double {
  (self.read_now)()
}
