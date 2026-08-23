import 'agent_decision.dart';

/// Whether a route's answer is allowed to proceed without successfully-retrieved evidence.
///
/// [AgentOrchestrator] derives this from the routed [AgentDecision.action] and uses it to decide
/// whether missing or failed retrieval should produce a deterministic "can't verify" response
/// instead of letting the local model guess at a fact it cannot actually know.
enum EvidenceRequirement {
  none,
  webRequired,
  documentRequired,
  webAndDocumentRequired;

  static EvidenceRequirement forAction(AgentAction action) => switch (action) {
        AgentAction.webSearch => EvidenceRequirement.webRequired,
        AgentAction.fileSearch => EvidenceRequirement.documentRequired,
        AgentAction.webAndFileSearch => EvidenceRequirement.webAndDocumentRequired,
        AgentAction.answer || AgentAction.deviceContext => EvidenceRequirement.none,
      };

  bool get requiresWeb =>
      this == EvidenceRequirement.webRequired ||
      this == EvidenceRequirement.webAndDocumentRequired;

  bool get requiresDocuments =>
      this == EvidenceRequirement.documentRequired ||
      this == EvidenceRequirement.webAndDocumentRequired;
}
