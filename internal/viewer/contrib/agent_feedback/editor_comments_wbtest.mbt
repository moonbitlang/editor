// Behavior tests for the editor-comment projection and grouping
// (`editor_comments.mbt`), transcribing the intent of
// `sessionEditorComments.test.ts` minus the PR-review arms: resolved
// filtering, deterministic ordering, the nearby-grouping threshold, and the
// expanded-height widening for long comments. Shared test helpers live in
// `agent_feedback_service_wbtest.mbt`.

///|
test "get_session_editor_comments hides resolved items and sorts by resource then line" {
  let a = uri("memory://session/a.mbt")
  let b = uri("memory://session/b.mbt")
  let comments = get_session_editor_comments([
    feedback_at("f3", b, 2),
    feedback_at("f1", a, 9),
    feedback_at("f2", a, 4),
    feedback_at("f4", a, 6, state=Resolved),
  ])
  assert_eq(comments.map(c => c.source_id).join(","), "f2,f1,f3")
  assert_eq(comments[0].id, "agentFeedback:f2")
  // Same position: the id breaks the tie.
  let tied = get_session_editor_comments([
    feedback_at("t2", a, 3),
    feedback_at("t1", a, 3),
  ])
  assert_eq(tied.map(c => c.source_id).join(","), "t1,t2")
}

///|
test "group_nearby_session_editor_comments splits on the line threshold and resource" {
  let a = uri("memory://session/a.mbt")
  let b = uri("memory://session/b.mbt")
  // A short comment estimates 2 expanded lines (1 text line + 1 header), so
  // the effective threshold from the group's first comment is 5 + 2 = 7.
  let groups = group_nearby_session_editor_comments(
    get_session_editor_comments([
      feedback_at("f1", a, 1),
      feedback_at("f2", a, 8), // span 7 <= 7: joins
      feedback_at("f3", a, 20), // span 19 > 5 + 2 + 2: new group
      feedback_at("f4", b, 21), // other resource: new group
    ]),
  )
  assert_eq(
    groups.map(group => group.map(c => c.source_id).join(",")).join(";"),
    "f1,f2;f3;f4",
  )
}

///|
test "a long first comment widens the group to items below it" {
  let a = uri("memory://session/a.mbt")
  let long_text = String::make(300, 'x')
  // 300 chars / 50 per line = 6 text lines + 1 header = estimate 7, so the
  // effective threshold is 5 + 7 = 12.
  let widened = group_nearby_session_editor_comments(
    get_session_editor_comments([
      feedback_at("f1", a, 1, text=long_text),
      feedback_at("f2", a, 13),
    ]),
  )
  assert_eq(
    widened.map(group => group.map(c => c.source_id).join(",")).join(";"),
    "f1,f2",
  )
  // The same span without the long text splits: 12 > 5 + 2.
  let split = group_nearby_session_editor_comments(
    get_session_editor_comments([
      feedback_at("f1", a, 1),
      feedback_at("f2", a, 13),
    ]),
  )
  assert_eq(
    split.map(group => group.map(c => c.source_id).join(",")).join(";"),
    "f1;f2",
  )
  assert_eq(group_nearby_session_editor_comments([]).length(), 0)
}

///|
test "replies widen the estimated group height" {
  let a = uri("memory://session/a.mbt")
  // Estimate for f1: 1 text line + 1 header + 4 reply lines (200 chars) = 6,
  // so the effective threshold is 5 + 6 = 11.
  let groups = group_nearby_session_editor_comments(
    get_session_editor_comments([
      feedback_at("f1", a, 1, replies=[String::make(200, 'r')]),
      feedback_at("f2", a, 12),
    ]),
  )
  assert_eq(
    groups.map(group => group.map(c => c.source_id).join(",")).join(";"),
    "f1,f2",
  )
}

///|
test "get_accepted_agent_feedback_comment_count counts only accepted comments" {
  let a = uri("memory://session/a.mbt")
  let comments = get_session_editor_comments([
    feedback_at("f1", a, 1),
    feedback_at("f2", a, 3, state=Created),
    feedback_at("f3", a, 5, state=Submitted),
    feedback_at("f4", a, 7),
  ])
  assert_eq(get_accepted_agent_feedback_comment_count(comments), 2)
}
