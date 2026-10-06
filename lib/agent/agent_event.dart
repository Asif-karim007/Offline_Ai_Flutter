import '../domain/generation_metrics.dart';
import '../llm/chat_engine.dart';
import 'response_provenance.dart';

/// Activity/result stream from `AgentOrchestrator.handle`.
///
/// Only [AgentTokenEvent] carries user-facing answer text; every other case is UI status or
/// metadata. Planner output and `<think>` content are never emitted here — the planner's JSON
/// never reaches this stream at all, and reasoning is stripped by [ThinkingContentFilter]
/// before a token is yielded.
sealed class AgentEvent {
  const AgentEvent();
}

final class AgentRoutingEvent extends AgentEvent {
  const AgentRoutingEvent();

  @override
  bool operator ==(Object other) => other is AgentRoutingEvent;

  @override
  int get hashCode => (AgentRoutingEvent).hashCode;
}

final class AgentPlanningEvent extends AgentEvent {
  const AgentPlanningEvent();

  @override
  bool operator ==(Object other) => other is AgentPlanningEvent;

  @override
  int get hashCode => (AgentPlanningEvent).hashCode;
}

final class AgentSearchingWebEvent extends AgentEvent {
  const AgentSearchingWebEvent(this.query);

  final String query;

  @override
  bool operator ==(Object other) => other is AgentSearchingWebEvent && other.query == query;

  @override
  int get hashCode => Object.hash(AgentSearchingWebEvent, query);
}

final class AgentReadingDocumentsEvent extends AgentEvent {
  const AgentReadingDocumentsEvent();

  @override
  bool operator ==(Object other) => other is AgentReadingDocumentsEvent;

  @override
  int get hashCode => (AgentReadingDocumentsEvent).hashCode;
}

/// The question is being looked up in the student's curriculum pack.
final class AgentSearchingTextbooksEvent extends AgentEvent {
  const AgentSearchingTextbooksEvent();

  @override
  bool operator ==(Object other) => other is AgentSearchingTextbooksEvent;

  @override
  int get hashCode => (AgentSearchingTextbooksEvent).hashCode;
}

/// Emitted instead of generating when the web-search mode is "ask" and the route wants a web
/// search the user has not approved for this turn. The stream then ends without a completion
/// event; the caller re-submits the request with approval granted.
final class AgentNeedsWebSearchConfirmationEvent extends AgentEvent {
  const AgentNeedsWebSearchConfirmationEvent(this.query);

  final String query;

  @override
  bool operator ==(Object other) =>
      other is AgentNeedsWebSearchConfirmationEvent && other.query == query;

  @override
  int get hashCode => Object.hash(AgentNeedsWebSearchConfirmationEvent, query);
}

final class AgentGeneratingEvent extends AgentEvent {
  const AgentGeneratingEvent();

  @override
  bool operator ==(Object other) => other is AgentGeneratingEvent;

  @override
  int get hashCode => (AgentGeneratingEvent).hashCode;
}

final class AgentTokenEvent extends AgentEvent {
  const AgentTokenEvent(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is AgentTokenEvent && other.text == text;

  @override
  int get hashCode => Object.hash(AgentTokenEvent, text);
}

/// Emitted once per turn, before generation starts, with the real provenance of whatever
/// evidence was actually used. The UI badge reads this, never the model's text.
final class AgentProvenanceUpdatedEvent extends AgentEvent {
  const AgentProvenanceUpdatedEvent(this.provenance);

  final ResponseProvenance provenance;

  @override
  bool operator ==(Object other) =>
      other is AgentProvenanceUpdatedEvent && other.provenance == provenance;

  @override
  int get hashCode => Object.hash(AgentProvenanceUpdatedEvent, provenance);
}

final class AgentCompletedEvent extends AgentEvent {
  const AgentCompletedEvent({required this.reason, required this.metrics});

  final GenerationFinishReason reason;
  final GenerationMetrics metrics;

  @override
  bool operator ==(Object other) =>
      other is AgentCompletedEvent && other.reason == reason && other.metrics == metrics;

  @override
  int get hashCode => Object.hash(AgentCompletedEvent, reason, metrics);
}
