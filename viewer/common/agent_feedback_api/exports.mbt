// Intentionally staged agent-loop payload. The generic handle is sufficient
// for the bundled viewer and workbench; an agent host will consume this value
// through AgentFeedbackService::on_did_submit_feedback.

///|
/// Accepted feedback submitted for one resource, including host-forwardable
/// items and the per-kind/reply counts.
pub(all) struct AgentFeedbackSubmittedEvent {
  resource : @base_common.Uri
  items : Array[AgentFeedback]
  user_count : Int
  agent_review_count : Int
  reply_count : Int
} derive(Debug)
