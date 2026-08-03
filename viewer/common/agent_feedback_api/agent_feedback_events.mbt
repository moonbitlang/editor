///|
/// Fired after a resource's feedback collection changes.
pub(all) struct AgentFeedbackChangeEvent {
  resource : @base_common.Uri
  feedback_items : Array[AgentFeedback]
} derive(Debug)

///|
/// Fired when a brand-new feedback item enters the accepted state. Hosts that
/// run their own feedback store publish this payload from their own emitter,
/// so it stays a shared value contract rather than moving into the concrete
/// service alongside the reply notification.
pub(all) struct AgentFeedbackAddedEvent {
  feedback : AgentFeedback
  has_existing_feedback_for_file : Bool
} derive(Debug)

///|
/// The position of a navigation anchor in a caller-supplied item order.
/// `active_idx` is `-1` when no live anchor exists.
pub(all) struct AgentFeedbackNavigationBearing {
  active_idx : Int
  total_count : Int
} derive(Eq, Debug)
