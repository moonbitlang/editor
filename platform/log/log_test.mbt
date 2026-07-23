///|
test "log service filters by level" {
  let memory = @log.MemoryLogger()
  let service = @log.LogService(level=Warning, logger=memory)
  service.info("test", "hidden")
  service.warn("test", "visible", details=[("key", "value")])
  service.error("test", "also visible")
  let entries = memory.entries()
  assert_eq(entries.length(), 2)
  assert_true(entries[0].level == Warning)
  assert_true(entries[0].details[0] == ("key", "value"))
  assert_true(entries[1].level == Error)
}

///|
test "null logger accepts entries and flushes" {
  let service = @log.LogService(logger=@log.NullLogger())
  service.error("test", "ignored")
  service.flush()
  assert_true(true)
}

///|
test "multiplex logger fans out entries and flushes" {
  let first = @log.MemoryLogger()
  let second = @log.MemoryLogger()
  let mux = @log.MultiplexLogger([first, second])
  let service = @log.LogService(level=Trace, logger=mux)
  service.debug("test", "fanout")
  service.flush()
  assert_eq(first.entries().length(), 1)
  assert_eq(second.entries().length(), 1)
  assert_eq(first.flush_count(), 1)
  assert_eq(second.flush_count(), 1)
}

///|
test "log handle forwards only warnings and errors with exact details" {
  let memory = @log.MemoryLogger()
  let service = @log.LogService(level=Trace, logger=memory)
  let handle = service.log_handle()
  handle.warn("handle", "warning", details=[("kind", "warn")])
  handle.error("handle", "error", details=[("kind", "error")])
  let entries = memory.entries()
  assert_eq(entries.length(), 2)
  assert_true(
    entries[0] ==
    {
      level: Warning,
      category: "handle",
      message: "warning",
      details: [("kind", "warn")],
    },
  )
  assert_true(
    entries[1] ==
    {
      level: Error,
      category: "handle",
      message: "error",
      details: [("kind", "error")],
    },
  )
}
