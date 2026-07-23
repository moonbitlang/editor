///|
/// Cooperative cancellation signal passed to language providers.
///
/// Tokens are stable values: repeated reads from a source return the same
/// token before and after cancellation. Cancellation ownership belongs to
/// `CancellationTokenSource`; `CancellationToken::new` and `cancel` remain as
/// compatibility entry points for existing direct-token callers.
pub struct CancellationToken {
  priv state : CancellationTokenState
}

///|
priv enum CancellationTokenState {
  NeverCancelled
  AlreadyCancelled((() -> Unit) -> @base_common.Disposable)
  CompatibilityMutable(MutableCancellationToken)
  SourceMutable(MutableCancellationToken)
}

///|
/// Listener state is allocated lazily, just as VS Code's `MutableToken` only
/// creates its emitter when a listener is first registered.
priv struct MutableCancellationToken {
  mut cancelled : Bool
  mut emitter : @base_common.Emitter[Unit]?
  schedule : (() -> Unit) -> @base_common.Disposable
}

///|
fn schedule_cancellation_inline(
  callback : () -> Unit,
) -> @base_common.Disposable {
  callback()
  @base_common.Disposable::from(() => ())
}

///|
let cancellation_none : CancellationToken = { state: NeverCancelled }

///|
let cancellation_cancelled : CancellationToken = {
  state: AlreadyCancelled(schedule_cancellation_inline),
}

///|
fn MutableCancellationToken::new(
  schedule : (() -> Unit) -> @base_common.Disposable,
) -> MutableCancellationToken {
  { cancelled: false, emitter: None, schedule }
}

///|
/// Creates a directly cancellable token for compatibility. New request owners
/// should create a `CancellationTokenSource` and pass its token instead.
pub fn CancellationToken::new() -> CancellationToken {
  {
    state: CompatibilityMutable(
      MutableCancellationToken::new(schedule_cancellation_inline),
    ),
  }
}

///|
/// Shared token that never requests cancellation.
pub fn CancellationToken::none() -> CancellationToken {
  cancellation_none
}

///|
/// Shared token whose cancellation has already been requested.
pub fn CancellationToken::cancelled() -> CancellationToken {
  cancellation_cancelled
}

///|
/// Requests cancellation for a compatibility token. Source-owned and shared
/// tokens keep their source-defined behavior.
pub fn CancellationToken::cancel(self : CancellationToken) -> Unit {
  match self.state {
    CompatibilityMutable(token) => token.cancel()
    NeverCancelled | AlreadyCancelled(_) | SourceMutable(_) => ()
  }
}

///|
/// Whether cancellation has been requested.
pub fn CancellationToken::is_cancellation_requested(
  self : CancellationToken,
) -> Bool {
  match self.state {
    NeverCancelled => false
    AlreadyCancelled(_) => true
    CompatibilityMutable(token) | SourceMutable(token) => token.cancelled
  }
}

///|
/// Registers a once-only cancellation listener in registration order.
///
/// A listener registered after cancellation is scheduled through the source's
/// scheduler and the returned disposable can suppress that pending delivery.
/// MoonBit closures capture the source `thisArgs` context directly. When a
/// disposable bucket is supplied, the returned subscription is appended to it.
pub fn CancellationToken::on_cancellation_requested(
  self : CancellationToken,
  listener : () -> Unit,
  disposables? : Array[@base_common.Disposable],
) -> @base_common.Disposable {
  let subscription = match self.state {
    NeverCancelled => @base_common.Disposable::from(() => ())
    AlreadyCancelled(schedule) => schedule(listener)
    CompatibilityMutable(token) | SourceMutable(token) =>
      token.on_cancellation_requested(listener)
  }
  match disposables {
    Some(bucket) => bucket.push(subscription)
    None => ()
  }
  subscription
}

///|
fn MutableCancellationToken::cancel(self : MutableCancellationToken) -> Unit {
  if self.cancelled {
    return
  }
  // The flag changes before notification so every listener observes the
  // one-way state transition.
  self.cancelled = true
  match self.emitter {
    Some(emitter) => {
      emitter.fire(())
      emitter.dispose()
      self.emitter = None
    }
    None => ()
  }
}

///|
fn MutableCancellationToken::on_cancellation_requested(
  self : MutableCancellationToken,
  listener : () -> Unit,
) -> @base_common.Disposable {
  if self.cancelled {
    return (self.schedule)(listener)
  }
  let emitter = match self.emitter {
    Some(emitter) => emitter
    None => {
      let emitter : @base_common.Emitter[Unit] = Emitter()
      self.emitter = Some(emitter)
      emitter
    }
  }
  emitter.event(_ => listener())
}

///|
/// Retires listener state without changing the cancellation flag.
fn MutableCancellationToken::dispose(self : MutableCancellationToken) -> Unit {
  match self.emitter {
    Some(emitter) => {
      emitter.dispose()
      self.emitter = None
    }
    None => ()
  }
}

///|
/// Owner for one lazily created cancellation token and its optional parent
/// subscription. `dispose(cancel=false)` releases listeners without requesting
/// cancellation; `dispose(cancel=true)` cancels first.
pub struct CancellationTokenSource {
  priv mut token_value : CancellationToken?
  priv mut parent_listener : @base_common.Disposable?
  priv schedule : (() -> Unit) -> @base_common.Disposable
}

///|
/// Creates a cancellation source. A parent cancellation propagates once to the
/// child. `schedule` adapts VS Code's zero-delay shortcut event to the host;
/// the host-neutral default delivers inline, while JS hosts or tests may inject
/// a disposable next-turn scheduler.
#alias(new, deprecated)
pub fn CancellationTokenSource::CancellationTokenSource(
  parent? : CancellationToken,
  schedule? : (() -> Unit) -> @base_common.Disposable = schedule_cancellation_inline,
) -> CancellationTokenSource {
  let source : CancellationTokenSource = {
    token_value: None,
    parent_listener: None,
    schedule,
  }
  match parent {
    Some(parent) =>
      source.parent_listener = Some(
        parent.on_cancellation_requested(() => source.cancel()),
      )
    None => ()
  }
  source
}

///|
/// Returns the source's stable token, allocating mutable state only on the
/// first read.
pub fn CancellationTokenSource::token(
  self : CancellationTokenSource,
) -> CancellationToken {
  match self.token_value {
    Some(token) => token
    None => {
      let token : CancellationToken = {
        state: SourceMutable(MutableCancellationToken::new(self.schedule)),
      }
      self.token_value = Some(token)
      token
    }
  }
}

///|
/// Requests cancellation once. Cancellation before the first token read avoids
/// mutable listener state but retains this source's scheduler, so a late
/// listener still has next-turn/disposable delivery semantics.
pub fn CancellationTokenSource::cancel(self : CancellationTokenSource) -> Unit {
  match self.token_value {
    None => self.token_value = Some({ state: AlreadyCancelled(self.schedule) })
    Some({ state: SourceMutable(token) }) => token.cancel()
    Some(
      { state: NeverCancelled | AlreadyCancelled(_) | CompatibilityMutable(_) }
    ) => ()
  }
}

///|
/// Releases the parent subscription and mutable listener state. Disposal is
/// idempotent. When no token has been read, non-cancelling disposal installs
/// the shared never-cancelled token so a later `cancel` remains a no-op.
pub fn CancellationTokenSource::dispose(
  self : CancellationTokenSource,
  cancel? : Bool = false,
) -> Unit {
  if cancel {
    self.cancel()
  }
  match self.parent_listener {
    Some(listener) => listener.dispose()
    None => ()
  }
  match self.token_value {
    None => self.token_value = Some(cancellation_none)
    Some({ state: SourceMutable(token) }) => token.dispose()
    Some(
      { state: NeverCancelled | AlreadyCancelled(_) | CompatibilityMutable(_) }
    ) => ()
  }
}
