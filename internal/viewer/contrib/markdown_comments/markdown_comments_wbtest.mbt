///|
fn line_comments(delimiter : String) -> @languages.CommentRule {
  { line_comment: Some(LineCommentRule(delimiter)), block_comment: None }
}

///|
fn block_comments(open : String, close : String) -> @languages.CommentRule {
  { line_comment: None, block_comment: Some({ open, close }) }
}

///|
fn both_comments() -> @languages.CommentRule {
  {
    line_comment: Some(LineCommentRule("//")),
    block_comment: Some({ open: "/*", close: "*/" }),
  }
}

///|
fn block(
  start_line_number : Int,
  end_line_number_exclusive : Int,
  markdown : String,
) -> @language.MarkdownCommentBlock {
  {
    line_range: LineRange(start_line_number, end_line_number_exclusive),
    markdown,
  }
}

///|
fn test_model(text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="markdown-comments",
      path="/detector.mbt",
    ),
    "detector.mbt",
    "moonbit",
    1,
    "test",
    text,
  )
}

///|
test "line comments allow indentation group blanks and preserve Unicode" {
  let snapshot = @model.TextSnapshot(
    "  // heading\r\n\t// 世界 🌙\r\n//\r\n\r\ncode\r\n // second",
  )
  assert_eq(snapshot.line_count(), 6)
  assert_eq(
    detect_markdown_comments_in_snapshot(snapshot, line_comments("//")),
    [block(1, 4, "heading\n世界 🌙\n"), block(6, 7, "second")],
  )
}

///|
test "line comments strip at most one ASCII space" {
  assert_eq(
    detect_markdown_comments_in_snapshot(
      TextSnapshot("//  two\n//\tTabbed\n//space"),
      line_comments("//"),
    ),
    [block(1, 4, " two\n\tTabbed\nspace")],
  )
}

///|
test "blank non-comment and source lines separate line comment blocks" {
  assert_eq(
    detect_markdown_comments_in_snapshot(
      TextSnapshot("// first\n\n// second\nvalue\n// third"),
      line_comments("//"),
    ),
    [block(1, 2, "first"), block(3, 4, "second"), block(5, 6, "third")],
  )
}

///|
test "TextModel entry point reads one snapshot and allows leading indent" {
  let model = test_model("  # title\nvalue")
  assert_eq(detect_markdown_comments(model, line_comments("#")), [
    block(1, 2, "title"),
  ])
}

///|
test "empty comment rules detect no blocks" {
  let rule : @languages.CommentRule = {
    line_comment: None,
    block_comment: None,
  }
  assert_eq(
    detect_markdown_comments_in_snapshot(
      TextSnapshot("// source\n/* source */"),
      rule,
    ),
    [],
  )
}

///|
test "single and multiline block comments strip boundaries indent and stars" {
  let snapshot = @model.TextSnapshot(
    "  /* single */  \nvalue\n/**\n * Heading\n * * item\n *\n * 世界\n */",
  )
  assert_eq(
    detect_markdown_comments_in_snapshot(snapshot, block_comments("/*", "*/")),
    [block(1, 2, "single "), block(3, 9, "\nHeading\n* item\n\n世界\n")],
  )
}

///|
test "multiline block comments remove common indentation and preserve shape" {
  let snapshot = @model.TextSnapshot(
    "  /* first\n     second\n       third\n  */",
  )
  assert_eq(
    detect_markdown_comments_in_snapshot(snapshot, block_comments("/*", "*/")),
    [block(1, 5, "first\n    second\n      third\n")],
  )
}

///|
test "block comments dedent mixed starred and unstarred content" {
  let snapshot = @model.TextSnapshot("/**\n * first\n   continuation\n */")
  assert_eq(
    detect_markdown_comments_in_snapshot(snapshot, block_comments("/*", "*/")),
    [block(1, 5, "\nfirst\n  continuation\n")],
  )
}

///|
test "block comments reject inline and trailing boundary source" {
  let snapshot = @model.TextSnapshot(
    "let x = /* inline */\n/* closed */ trailing\n/* first */ trailing */\n  /* valid */",
  )
  assert_eq(
    detect_markdown_comments_in_snapshot(snapshot, block_comments("/*", "*/")),
    [block(4, 5, "valid ")],
  )
}

///|
test "line and block rules coexist with deterministic line-first precedence" {
  assert_eq(
    detect_markdown_comments_in_snapshot(
      TextSnapshot("// line\ncode\n/* block */"),
      both_comments(),
    ),
    [block(1, 2, "line"), block(3, 4, "block ")],
  )
  let overlapping : @languages.CommentRule = {
    line_comment: Some(LineCommentRule("/*")),
    block_comment: Some({ open: "/*", close: "*/" }),
  }
  assert_eq(
    detect_markdown_comments_in_snapshot(
      TextSnapshot("/* line wins */"),
      overlapping,
    ),
    [block(1, 2, "line wins */")],
  )
}

///|
test "unmatched block opening does not reinterpret its interior as line comments" {
  assert_eq(
    detect_markdown_comments_in_snapshot(
      TextSnapshot("/* open\n// still block\ntext"),
      both_comments(),
    ),
    [],
  )
}

///|
test "normalization rejects invalid reversed and out-of-model ranges" {
  let memory = @log.MemoryLogger()
  let log_handle = @log.LogService(logger=memory).log_handle()
  let result = normalize_markdown_comment_blocks(
    [
      block(0, 2, "zero"),
      block(2, 2, "empty range"),
      block(4, 3, "reversed"),
      block(1, 5, "past end"),
      block(2, 4, "valid"),
    ],
    3,
    log_handle,
  )
  assert_eq(result, [block(2, 4, "valid")])
  let entries = memory.entries()
  assert_eq(entries.length(), 4)
  for entry in entries {
    assert_eq(entry.level, Warning)
    assert_eq(entry.category, "viewer.markdownComments")
    assert_true(entry.message.contains("invalid line range"))
  }
}

///|
test "normalization sorts drops later overlaps and keeps touching ranges" {
  let memory = @log.MemoryLogger()
  let normalized = normalize_markdown_comment_blocks(
    [
      block(3, 5, "third"),
      block(5, 6, "touching"),
      block(2, 4, "overlap"),
      block(1, 3, "first"),
    ],
    6,
    @log.LogService(logger=memory).log_handle(),
  )
  assert_eq(normalized, [
    block(1, 3, "first"),
    block(3, 5, "third"),
    block(5, 6, "touching"),
  ])
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].level, Warning)
  assert_true(entries[0].message.contains("overlapping"))
}

///|
test "equal provider ranges deterministically keep the earlier input" {
  let memory = @log.MemoryLogger()
  assert_eq(
    normalize_markdown_comment_blocks(
      [block(2, 3, "earlier"), block(2, 3, "later")],
      3,
      @log.LogService(logger=memory).log_handle(),
    ),
    [block(2, 3, "earlier")],
  )
  assert_eq(memory.entries().length(), 1)
}

///|
test "normalization drops exact-empty bodies but preserves whitespace bodies" {
  let normalized = normalize_markdown_comment_blocks(
    [block(1, 2, ""), block(2, 3, " ")],
    3,
    @log.LogService().log_handle(),
  )
  assert_eq(normalized, [block(2, 3, " ")])
}

///|
test "normalization uses the all-model-lines visibility fallback" {
  assert_eq(
    normalize_markdown_comment_blocks(
      [block(1, 2, "first"), block(2, 5, "rest")],
      4,
      @log.LogService().log_handle(),
    ),
    [],
  )
  let snapshot = @model.TextSnapshot("// all\r\n// lines")
  let detected = detect_markdown_comments_in_snapshot(
    snapshot,
    line_comments("//"),
  )
  assert_eq(detected, [block(1, 3, "all\nlines")])
  assert_eq(
    normalize_markdown_comment_blocks(
      detected,
      snapshot.line_count(),
      @log.LogService().log_handle(),
    ),
    [],
  )
}

///|
test "resolver falls back to the model language comment configuration" {
  let registry = @languages.Languages()
  registry.set_language_configuration("moonbit", {
    comments: Some(line_comments("//")),
    folding_rules: None,
  })
  let log_handle = @log.LogService().log_handle()
  let handle = registry.language_handle(log_handle)
  assert_eq(
    resolve_markdown_comment_blocks(
      test_model("// configured\nsource"),
      handle,
      log_handle,
    ),
    [block(1, 2, "configured")],
  )
}

///|
test "resolver treats an empty provider result as authoritative" {
  let registry = @languages.Languages()
  registry.set_language_configuration("moonbit", {
    comments: Some(line_comments("//")),
    folding_rules: None,
  })
  let calls = Ref(0)
  let registration = registry.register_markdown_comment_provider(
    LanguageId("moonbit"),
    ResolverMarkdownCommentProvider::{ blocks: [], calls },
  )
  let log_handle = @log.LogService().log_handle()
  let handle = registry.language_handle(log_handle)
  assert_eq(
    resolve_markdown_comment_blocks(
      test_model("// configured\nsource"),
      handle,
      log_handle,
    ),
    [],
  )
  assert_eq(calls.val, 1)
  registration.dispose()
}

///|
test "resolver normalizes provider ranges and reports discarded entries" {
  let registry = @languages.Languages()
  let calls = Ref(0)
  let registration = registry.register_markdown_comment_provider(
    LanguageId("moonbit"),
    ResolverMarkdownCommentProvider::{
      blocks: [
        block(3, 5, "third"),
        block(1, 3, "first"),
        block(2, 4, "overlap"),
        block(8, 9, "outside"),
      ],
      calls,
    },
  )
  let memory = @log.MemoryLogger()
  let log_handle = @log.LogService(logger=memory).log_handle()
  let handle = registry.language_handle(log_handle)
  assert_eq(
    resolve_markdown_comment_blocks(
      test_model("one\ntwo\nthree\nfour\nfive\nsix"),
      handle,
      log_handle,
    ),
    [block(1, 3, "first"), block(3, 5, "third")],
  )
  assert_eq(calls.val, 1)
  assert_eq(memory.entries().length(), 2)
  registration.dispose()
}

///|
test "disposing an authoritative provider restores configuration fallback" {
  let registry = @languages.Languages()
  registry.set_language_configuration("moonbit", {
    comments: Some(line_comments("//")),
    folding_rules: None,
  })
  let calls = Ref(0)
  let registration = registry.register_markdown_comment_provider(
    LanguageId("moonbit"),
    ResolverMarkdownCommentProvider::{
      blocks: [block(2, 3, "provider")],
      calls,
    },
  )
  let log_handle = @log.LogService().log_handle()
  let handle = registry.language_handle(log_handle)
  let model = test_model("// configured\nsource")
  assert_eq(resolve_markdown_comment_blocks(model, handle, log_handle), [
    block(2, 3, "provider"),
  ])
  registration.dispose()
  assert_eq(resolve_markdown_comment_blocks(model, handle, log_handle), [
    block(1, 2, "configured"),
  ])
  assert_eq(calls.val, 1)
}

///|
priv struct ResolverMarkdownCommentProvider {
  blocks : Array[@language.MarkdownCommentBlock]
  calls : Ref[Int]
}

///|
impl @language.MarkdownCommentProvider for ResolverMarkdownCommentProvider with fn provide_markdown_comments(
  self,
  _model,
) {
  self.calls.val += 1
  self.blocks.copy()
}
