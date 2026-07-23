///|
test "comment configuration defaults and normalized records round trip" {
  let languages = Languages()
  let missing = languages.get_language_configuration("missing")
  assert_true(missing.comments is None)
  assert_true(missing.folding_rules is None)

  let line = LineCommentRule("//")
  assert_eq(line.comment, "//")
  assert_false(line.no_indent)
  let no_indent = LineCommentRule("#", no_indent=true)
  assert_true(no_indent.no_indent)
  let comments : CommentRule = {
    line_comment: Some(line),
    block_comment: Some({ open: "/*", close: "*/" }),
  }
  languages.set_language_configuration("moonbit", {
    comments: Some(comments),
    folding_rules: None,
  })
  assert_true(
    languages.get_language_configuration("moonbit").comments == Some(comments),
  )
}

///|
test "comment configuration accepts line-only block-only and empty rules" {
  let languages = Languages()
  languages.set_language_configuration("line", {
    comments: Some({
      line_comment: Some(LineCommentRule("//")),
      block_comment: None,
    }),
    folding_rules: None,
  })
  languages.set_language_configuration("block", {
    comments: Some({
      line_comment: None,
      block_comment: Some({ open: "/*", close: "*/" }),
    }),
    folding_rules: None,
  })
  languages.set_language_configuration("empty", {
    comments: Some({ line_comment: None, block_comment: None }),
    folding_rules: None,
  })
  assert_true(
    languages.get_language_configuration("line").comments
    is Some({ line_comment: Some(_), block_comment: None }),
  )
  assert_true(
    languages.get_language_configuration("block").comments
    is Some({ line_comment: None, block_comment: Some(_) }),
  )
  assert_true(
    languages.get_language_configuration("empty").comments
    is Some({ line_comment: None, block_comment: None }),
  )
}

///|
test "panic comment configuration rejects an empty line delimiter" {
  Languages().set_language_configuration("invalid", {
    comments: Some({
      line_comment: Some(LineCommentRule("")),
      block_comment: None,
    }),
    folding_rules: None,
  })
}

///|
test "panic comment configuration rejects an empty block opening delimiter" {
  Languages().set_language_configuration("invalid", {
    comments: Some({
      line_comment: None,
      block_comment: Some({ open: "", close: "*/" }),
    }),
    folding_rules: None,
  })
}

///|
test "panic comment configuration rejects an empty block closing delimiter" {
  Languages().set_language_configuration("invalid", {
    comments: Some({
      line_comment: None,
      block_comment: Some({ open: "/*", close: "" }),
    }),
    folding_rules: None,
  })
}
