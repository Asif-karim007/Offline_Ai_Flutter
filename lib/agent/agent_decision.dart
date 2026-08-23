/// The action half of `AgentDecision`.
///
/// Swift nests this as `AgentDecision.Action`; Dart has no nested enums, so it is a top-level
/// type. The wire values are the strings the planner prompt names in its schema, so renaming
/// one silently breaks planner output parsing.
enum AgentAction {
  answer('answer'),
  webSearch('web_search'),
  fileSearch('file_search'),
  webAndFileSearch('web_and_file_search'),

  /// Answered from [DeviceContextTool] (date/time/timezone) — never from pretrained model
  /// knowledge and never from the network. [AgentRouter] decides this deterministically for
  /// clear cases; it is in the planner's schema too for phrasings the router does not know.
  deviceContext('device_context');

  const AgentAction(this.wireValue);

  final String wireValue;

  /// Returns null rather than a default for an unrecognised value. That strictness is
  /// load-bearing: it is what makes an invented action string fall through to
  /// `AgentPlanner.deterministicFallback` instead of silently routing somewhere plausible.
  static AgentAction? fromWireValue(String value) {
    for (final action in AgentAction.values) {
      if (action.wireValue == value) return action;
    }
    return null;
  }
}

/// The planner's structured decision. `AgentPlanner` prompts for this exact JSON shape and
/// tolerantly extracts it from unconstrained model output — it is never produced by
/// grammar-constrained decoding, and a decode failure falls back to
/// `AgentPlanner.deterministicFallback` rather than ever producing an invalid decision.
class AgentDecision {
  const AgentDecision({
    required this.action,
    required this.query,
    required this.reason,
    required this.needsCurrentInformation,
    required this.needsPrivateFiles,
  });

  final AgentAction action;
  final String query;
  final String reason;
  final bool needsCurrentInformation;
  final bool needsPrivateFiles;

  /// Used whenever the planner call fails or returns something that does not parse — always
  /// safe to fall back to a plain local answer rather than guessing at tool use.
  static AgentDecision fallbackAnswer({required String reason}) => AgentDecision(
        action: AgentAction.answer,
        query: '',
        reason: reason,
        needsCurrentInformation: false,
        needsPrivateFiles: false,
      );

  /// Deliberately as strict as Swift's synthesized `Codable`: an unknown `action`, a missing
  /// key, or a value of the wrong type all yield null. There are no defaults here on purpose —
  /// a lenient decoder would turn malformed model output into a confident routing decision,
  /// which is precisely the failure mode the deterministic fallback exists to catch. Unknown
  /// *extra* keys are ignored, which is also what `JSONDecoder` does.
  static AgentDecision? fromJson(Object? decoded) {
    if (decoded is! Map) return null;

    final rawAction = decoded['action'];
    if (rawAction is! String) return null;
    final action = AgentAction.fromWireValue(rawAction);
    if (action == null) return null;

    final query = decoded['query'];
    if (query is! String) return null;

    final reason = decoded['reason'];
    if (reason is! String) return null;

    final needsCurrentInformation = decoded['needs_current_information'];
    if (needsCurrentInformation is! bool) return null;

    final needsPrivateFiles = decoded['needs_private_files'];
    if (needsPrivateFiles is! bool) return null;

    return AgentDecision(
      action: action,
      query: query,
      reason: reason,
      needsCurrentInformation: needsCurrentInformation,
      needsPrivateFiles: needsPrivateFiles,
    );
  }

  Map<String, Object?> toJson() => {
        'action': action.wireValue,
        'query': query,
        'reason': reason,
        'needs_current_information': needsCurrentInformation,
        'needs_private_files': needsPrivateFiles,
      };

  AgentDecision copyWith({
    AgentAction? action,
    String? query,
    String? reason,
    bool? needsCurrentInformation,
    bool? needsPrivateFiles,
  }) {
    return AgentDecision(
      action: action ?? this.action,
      query: query ?? this.query,
      reason: reason ?? this.reason,
      needsCurrentInformation: needsCurrentInformation ?? this.needsCurrentInformation,
      needsPrivateFiles: needsPrivateFiles ?? this.needsPrivateFiles,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentDecision &&
      other.action == action &&
      other.query == query &&
      other.reason == reason &&
      other.needsCurrentInformation == needsCurrentInformation &&
      other.needsPrivateFiles == needsPrivateFiles;

  @override
  int get hashCode =>
      Object.hash(action, query, reason, needsCurrentInformation, needsPrivateFiles);
}
