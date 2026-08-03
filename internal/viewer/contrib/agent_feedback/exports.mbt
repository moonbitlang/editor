// Intentionally staged host/agent-loop APIs. The bundled workbench persists
// generic feedback snapshots today; a future agent host will subscribe to
// submitted batches and resolve them after processing.

///|
/// Subscribes to accepted feedback batches transitioning to `Submitted`.
pub fn AgentFeedbackService::on_did_submit_feedback(
  self : AgentFeedbackService,
  listener : (@agent_feedback_api.AgentFeedbackSubmittedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_submit_feedback.event(listener)
}

///|
/// Resolving hides an item from the editor UI; un-resolving returns it to
/// `Submitted` so an agent host can process it again.
pub fn AgentFeedbackService::set_feedback_resolved(
  self : AgentFeedbackService,
  resource : @base_common.Uri,
  feedback_id : String,
  resolved : Bool,
) -> Unit {
  guard self.feedback_by_id(resource, feedback_id) is Some(existing) else {
    return
  }
  let next_state : @agent_feedback_api.AgentFeedbackState = if resolved {
    Resolved
  } else {
    Submitted
  }
  if existing.state != next_state {
    self.replace_item(resource, { ..existing, state: next_state })
  }
}
