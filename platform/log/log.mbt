///|
/// Log threshold and entry severity. `Off` disables emission.
pub(all) enum LogLevel {
  Off
  Trace
  Debug
  Info
  Warning
  Error
} derive(Eq, Debug)

///|
/// Structured log event emitted by app and viewer services.
pub(all) struct LogEntry {
  level : LogLevel
  category : String
  message : String
  details : Array[(String, String)]
} derive(Eq, Debug)

///|
/// Minimal logger sink abstraction. Methods are `noraise` so logging cannot
/// fail a viewer or server workflow.
pub(open) trait Logger {
  fn log(Self, LogEntry) -> Unit noraise
  fn flush(Self) -> Unit noraise
}

///|
/// Logger sink that drops every entry.
pub struct NullLogger {}

///|
/// Creates a sink that ignores logs and flushes.
#alias(new)
#warnings("-unnecessary_annotation")
pub fn NullLogger::NullLogger() -> NullLogger {
  NullLogger::{  }
}

///|
/// Drops one log entry.
pub impl Logger for NullLogger with fn log(_self, _entry) {
  ()
}

///|
/// No-op flush for the null sink.
pub impl Logger for NullLogger with fn flush(_self) {
  ()
}

///|
/// In-memory logger used by tests and harness-facing diagnostics.
pub struct MemoryLogger {
  entries : Array[LogEntry]
  flush_count : Ref[Int]
}

///|
/// Creates an empty in-memory log sink.
#alias(new)
pub fn MemoryLogger::MemoryLogger() -> MemoryLogger {
  { entries: [], flush_count: Ref(0) }
}

///|
/// Snapshot of collected log entries.
pub fn MemoryLogger::entries(self : MemoryLogger) -> Array[LogEntry] {
  self.entries.copy()
}

///|
/// Number of flush calls observed by the memory sink.
pub fn MemoryLogger::flush_count(self : MemoryLogger) -> Int {
  self.flush_count.val
}

///|
/// Records one log entry in memory.
pub impl Logger for MemoryLogger with fn log(self, entry) {
  self.entries.push(entry)
}

///|
/// Records a flush boundary in memory.
pub impl Logger for MemoryLogger with fn flush(self) {
  self.flush_count.val = self.flush_count.val + 1
}

///|
/// Logger sink that fans each entry and flush to multiple sinks.
pub struct MultiplexLogger {
  loggers : Array[&Logger]
}

///|
/// Creates a logger fan-out over the supplied sinks.
#alias(new)
pub fn MultiplexLogger::MultiplexLogger(
  loggers : Array[&Logger],
) -> MultiplexLogger {
  { loggers, }
}

///|
/// Emits one entry to every child logger.
pub impl Logger for MultiplexLogger with fn log(self, entry) {
  for logger in self.loggers {
    logger.log(entry)
  }
}

///|
/// Flushes every child logger.
pub impl Logger for MultiplexLogger with fn flush(self) {
  for logger in self.loggers {
    logger.flush()
  }
}

///|
/// Thresholded logging facade used by services that should not know the sink
/// implementation.
pub struct LogService {
  level : LogLevel
  logger : &Logger
}

///|
/// Opaque logging capability passed across public service boundaries. It
/// exposes only the warning and error operations consumed by Viewer runtime
/// code and does not reveal the concrete sink or threshold policy.
pub struct LogHandle {
  priv warn_callback : (String, String, Array[(String, String)]) -> Unit
  priv error_callback : (String, String, Array[(String, String)]) -> Unit
}

///|
/// Creates a log service with an optional threshold and sink.
#alias(new)
pub fn LogService::LogService(
  level? : LogLevel = Info,
  logger? : &Logger = NullLogger(),
) -> LogService {
  { level, logger }
}

///|
/// Derives the minimal Viewer logging capability from this concrete service.
/// The handle borrows behavior through callbacks; it owns neither the service
/// nor its logger.
pub fn LogService::log_handle(self : LogService) -> LogHandle {
  {
    warn_callback: (category, message, details) => {
      self.warn(category, message, details~)
    },
    error_callback: (category, message, details) => {
      self.error(category, message, details~)
    },
  }
}

///|
/// Emits a warning through the captured logging capability.
pub fn LogHandle::warn(
  self : LogHandle,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  (self.warn_callback)(category, message, details)
}

///|
/// Emits an error through the captured logging capability.
pub fn LogHandle::error(
  self : LogHandle,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  (self.error_callback)(category, message, details)
}

///|
/// Emits an already-structured log entry when it passes the threshold.
pub fn LogService::log(self : LogService, entry : LogEntry) -> Unit {
  if should_log(self.level, entry.level) {
    self.logger.log(entry)
  }
}

///|
/// Emits a trace-level entry.
pub fn LogService::trace(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Trace, category, message, details })
}

///|
/// Emits a debug-level entry.
pub fn LogService::debug(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Debug, category, message, details })
}

///|
/// Emits an info-level entry.
pub fn LogService::info(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Info, category, message, details })
}

///|
/// Emits a warning-level entry.
pub fn LogService::warn(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Warning, category, message, details })
}

///|
/// Emits an error-level entry.
pub fn LogService::error(
  self : LogService,
  category : String,
  message : String,
  details? : Array[(String, String)] = [],
) -> Unit {
  self.log({ level: Error, category, message, details })
}

///|
/// Flushes the configured log sink.
pub fn LogService::flush(self : LogService) -> Unit {
  self.logger.flush()
}

///|
/// Stable lowercase label for configuration and diagnostics.
pub fn LogLevel::label(self : LogLevel) -> String {
  match self {
    Off => "off"
    Trace => "trace"
    Debug => "debug"
    Info => "info"
    Warning => "warning"
    Error => "error"
  }
}

///|
/// Whether the level should be treated as a failure signal by harness checks.
pub fn LogLevel::is_warning_or_error(self : LogLevel) -> Bool {
  level_rank(self) >= level_rank(Warning) && self != Off
}

///|
fn should_log(configured : LogLevel, entry : LogLevel) -> Bool {
  configured != Off &&
  entry != Off &&
  level_rank(entry) >= level_rank(configured)
}

///|
fn level_rank(level : LogLevel) -> Int {
  match level {
    Off => 99
    Trace => 0
    Debug => 1
    Info => 2
    Warning => 3
    Error => 4
  }
}
