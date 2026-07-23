///|
/// Fired after a resource's feedback collection changes.
pub(all) struct AgentFeedbackChangeEvent {
  resource : @base_common.Uri
  feedback_items : Array[AgentFeedback]
} derive(Debug)

///|
/// Fired when a brand-new feedback item enters the accepted state.
pub(all) struct AgentFeedbackAddedEvent {
  feedback : AgentFeedback
  has_existing_feedback_for_file : Bool
} derive(Debug)

///|
/// Fired when a reply is appended to an existing feedback thread.
pub(all) struct AgentFeedbackReplyAddedEvent {
  feedback : AgentFeedback
  reply_count : Int
} derive(Debug)

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

///|
/// The position of a navigation anchor in a caller-supplied item order.
/// `active_idx` is `-1` when no live anchor exists.
pub(all) struct AgentFeedbackNavigationBearing {
  active_idx : Int
  total_count : Int
} derive(Eq, Debug)
