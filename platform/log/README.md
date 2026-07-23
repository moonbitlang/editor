# platform/log

Host-neutral structured logging used by the viewer and reference shell.

- `LogEntry` carries a level, category, message, and string key/value details.
- `LogService` applies a minimum `LogLevel`; `Off` disables emission and the
  convenience methods (`trace` through `error`) forward to a `Logger` sink.
- `NullLogger` drops output, `MemoryLogger` records entries and flushes for tests,
  and `MultiplexLogger` fans out to each child sink. `Logger` methods are
  `noraise`, so logging cannot fail the calling workflow.

This is the explicit, dependency-injected role of Monaco/VS Code's logging service,
not a port of its global service container. The package has no product, viewer,
browser, native, transport, or shell dependency; hosts choose the sink. See
`pkg.generated.mbti` for the complete API and run
`moon test --target js platform/log` for focused coverage.

`LogService::log_handle()` returns the opaque Viewer capability with exactly
`warn` and `error`. It captures the concrete service without transferring
ownership, so hosts retain the logger, level control, lower-severity methods,
flush operation, and lifecycle outside `ViewerServices`.
