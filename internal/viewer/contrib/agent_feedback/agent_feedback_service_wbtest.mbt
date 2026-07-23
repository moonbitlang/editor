// Behavior tests for the trimmed agent-feedback service
// (`agent_feedback_service.mbt`). Upstream's `agentFeedbackService.test.ts`
// leans on the sessions/chat stack; these cover the store role directly:
// the item lifecycle and its events, the anchor-clearing remove rule, the
// submit transition and counts, and prev/next navigation with wrap-around.
// The `uri` and `feedback_at` helpers are shared with
// `editor_comments_wbtest.mbt` (same wbtest package).

///|
fn uri(value : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(value)
}

///|
fn feedback_at(
  id : String,
  resource : @base_common.Uri,
  line : Int,
  text? : String = "note",
  kind? : @agent_feedback_api.AgentFeedbackKind = UserReview,
  replies? : Array[String] = [],
  state? : @agent_feedback_api.AgentFeedbackState = Accepted,
) -> @agent_feedback_api.AgentFeedback {
  { id, text, resource, range: Range(line, 1, line, 1), kind, replies, state }
}

///|
test "add_feedback stores an accepted item and fires change + add events" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let mut change_count = 0
  let mut changed_items = ""
  let mut added = ""
  let mut added_has_existing = false
  service.on_did_change_feedback(event => {
    change_count += 1
    changed_items = event.feedback_items.map(item => item.id).join(",")
  })
  |> ignore
  service.on_did_add_feedback(event => {
    added = event.feedback.id
    added_has_existing = event.has_existing_feedback_for_file
  })
  |> ignore
  let first = service.add_feedback(resource, Range(3, 1, 3, 10), "rename this")
  debug_inspect(first.state, content="Accepted")
  debug_inspect(first.kind, content="UserReview")
  assert_eq(added, first.id)
  assert_eq(added_has_existing, false)
  assert_eq(change_count, 1)
  assert_eq(changed_items, first.id)
  let second = service.add_feedback(resource, Range(9, 1, 9, 4), "and this")
  assert_eq(added, second.id)
  assert_eq(added_has_existing, true)
  assert_eq(service.get_feedback(resource).length(), 2)
}

///|
test "created items skip the add event until accepted" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let mut added = ""
  service.on_did_add_feedback(event => added = event.feedback.id) |> ignore
  let created = service.add_feedback(
    resource,
    Range(2, 1, 2, 1),
    "agent note",
    kind=AgentReview,
    state=Created,
  )
  assert_eq(added, "")
  debug_inspect(created.state, content="Created")
  service.accept_feedback(resource, created.id)
  debug_inspect(service.get_feedback(resource)[0].state, content="Accepted")
  // Accepting a non-Created item is a no-op.
  service.accept_feedback(resource, created.id)
  debug_inspect(service.get_feedback(resource)[0].state, content="Accepted")
}

///|
test "update, reply, and resolve replace the stored item and fire events" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let item = service.add_feedback(resource, Range(4, 1, 4, 8), "typo")
  service.update_feedback(resource, item.id, "typo here")
  assert_eq(service.get_feedback(resource)[0].text, "typo here")
  let mut reply_count = -1
  service.on_did_add_reply(event => reply_count = event.reply_count) |> ignore
  service.add_reply(resource, item.id, "also the docs")
  assert_eq(reply_count, 1)
  assert_true(service.get_feedback(resource)[0].replies is ["also the docs"])
  service.set_feedback_resolved(resource, item.id, true)
  debug_inspect(service.get_feedback(resource)[0].state, content="Resolved")
  service.set_feedback_resolved(resource, item.id, false)
  debug_inspect(service.get_feedback(resource)[0].state, content="Submitted")
}

///|
test "remove_feedback drops the item and a navigation anchor pointing at it" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let item = service.add_feedback(resource, Range(4, 1, 4, 8), "typo")
  let keep = service.add_feedback(resource, Range(9, 1, 9, 8), "keep")
  service.set_navigation_anchor(
    resource,
    Some(to_session_editor_comment_id(item.id)),
  )
  service.remove_feedback(resource, item.id)
  assert_eq(service.get_feedback(resource).map(i => i.id).join(","), keep.id)
  let bearing = service.get_navigation_bearing(resource, [
    to_session_editor_comment_id(item.id),
    to_session_editor_comment_id(keep.id),
  ])
  assert_eq(bearing.active_idx, -1)
  // Removing the last item empties the store for the resource.
  service.remove_feedback(resource, keep.id)
  assert_eq(service.get_feedback(resource).length(), 0)
}

///|
test "mark_feedback_submitted transitions accepted items and reports counts" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let mut submitted_ids = ""
  let mut user_count = -1
  let mut agent_review_count = -1
  let mut reply_count = -1
  service.on_did_submit_feedback(event => {
    submitted_ids = event.items.map(item => item.id).join(",")
    user_count = event.user_count
    agent_review_count = event.agent_review_count
    reply_count = event.reply_count
  })
  |> ignore
  // Nothing accepted yet: no event.
  service.mark_feedback_submitted(resource)
  assert_eq(user_count, -1)
  let user_item = service.add_feedback(resource, Range(1, 1, 1, 1), "a")
  service.add_reply(resource, user_item.id, "more")
  let agent_item = service.add_feedback(
    resource,
    Range(5, 1, 5, 1),
    "b",
    kind=AgentReview,
  )
  let pending = service.add_feedback(
    resource,
    Range(9, 1, 9, 1),
    "c",
    state=Created,
  )
  service.mark_feedback_submitted(resource)
  assert_eq(submitted_ids, user_item.id + "," + agent_item.id)
  assert_eq(user_count, 1)
  assert_eq(agent_review_count, 1)
  assert_eq(reply_count, 1)
  let states = service.get_feedback(resource).map(item => item.state)
  debug_inspect(states, content="[Submitted, Submitted, Created]")
  assert_eq(service.get_feedback(resource)[2].id, pending.id)
}

///|
test "set_feedback_items replaces the store and clear_feedback empties it" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  service.add_feedback(resource, Range(1, 1, 1, 1), "old") |> ignore
  let mut change_count = 0
  service.on_did_change_feedback(_ => change_count += 1) |> ignore
  service.set_feedback_items(resource, [
    feedback_at("host-1", resource, 3),
    feedback_at("host-2", resource, 7, state=Submitted),
  ])
  assert_eq(change_count, 1)
  assert_eq(
    service.get_feedback(resource).map(item => item.id).join(","),
    "host-1,host-2",
  )
  service.clear_feedback(resource)
  assert_eq(change_count, 2)
  assert_eq(service.get_feedback(resource).length(), 0)
}

///|
test "get_next_navigable_item steps with wrap-around and re-anchors" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let ids = ["c1", "c2", "c3"]
  // No anchor: next starts at the first item.
  assert_true(
    service.get_next_navigable_item(resource, ids, next=true) is Some("c1"),
  )
  assert_true(
    service.get_next_navigable_item(resource, ids, next=true) is Some("c2"),
  )
  assert_true(
    service.get_next_navigable_item(resource, ids, next=false) is Some("c1"),
  )
  // Wrap backward from the first item.
  assert_true(
    service.get_next_navigable_item(resource, ids, next=false) is Some("c3"),
  )
  // Wrap forward from the last item.
  assert_true(
    service.get_next_navigable_item(resource, ids, next=true) is Some("c1"),
  )
  debug_inspect(
    service.get_navigation_bearing(resource, ids),
    content="{ active_idx: 0, total_count: 3 }",
  )
  // Empty list clears the anchor and yields nothing.
  assert_true(service.get_next_navigable_item(resource, [], next=true) is None)
  debug_inspect(
    service.get_navigation_bearing(resource, ids),
    content="{ active_idx: -1, total_count: 3 }",
  )
}

///|
test "prev with no anchor anchors on the first item then steps back" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  // Upstream pins a missing anchor to index 0 for backward navigation, so
  // the first "previous" lands on the last item.
  assert_true(
    service.get_next_navigable_item(resource, ["c1", "c2", "c3"], next=false)
    is Some("c3"),
  )
}

///|
test "agent_feedback_handle adapts the concrete service and preserves defaults" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/handle.mbt")
  let handle = service.agent_feedback_handle()
  let mut change_count = 0
  let subscription = handle.on_did_change_feedback(_ => change_count += 1)
  service.set_feedback_enabled(resource, true)
  assert_true(handle.is_feedback_enabled(resource))
  let defaulted = handle.add_feedback(resource, Range(1, 1, 1, 3), "defaulted")
  assert_eq(defaulted.kind, UserReview)
  assert_eq(defaulted.state, Accepted)
  let explicit = handle.add_feedback(
    resource,
    Range(3, 1, 3, 3),
    "explicit",
    kind=AgentReview,
    state=Created,
  )
  assert_eq(explicit.kind, AgentReview)
  assert_eq(explicit.state, Created)
  assert_eq(handle.get_feedback(resource).length(), 2)
  handle.accept_feedback(resource, explicit.id)
  handle.update_feedback(resource, explicit.id, "updated")
  handle.add_reply(resource, explicit.id, "reply")
  handle.set_navigation_anchor(resource, Some(explicit.id))
  assert_eq(
    handle.get_navigation_bearing(resource, [defaulted.id, explicit.id]),
    { active_idx: 1, total_count: 2 },
  )
  handle.mark_feedback_submitted(resource)
  handle.remove_feedback(resource, defaulted.id)
  assert_true(change_count >= 7)
  subscription.dispose()
  service.dispose()
}
