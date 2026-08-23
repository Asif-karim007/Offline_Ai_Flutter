import 'dart:convert';

import '../domain/generation_configuration.dart';
import '../llm/chat_engine.dart';
import 'agent_decision.dart';
import 'agent_request.dart';
import 'agent_router.dart';

/// Runs the small planner call for the genuinely ambiguous tier [AgentRouter] cannot decide
/// deterministically. Explicit instructions, device-context questions and hard freshness
/// patterns are all intercepted by the router *before* this is ever reached, precisely because a
/// 0.6B-parameter model is not trusted as sole authority for those obvious cases. The planner's
/// own output is never streamed and never shown to the user.
///
/// This deliberately does NOT use grammar-constrained decoding: `grammar` is always null at
/// this call site. `llama_sampler_init_grammar`/`llama_sampler_accept` can throw a C++ exception
/// when a model's actual output diverges from the grammar — observed in practice with Qwen3's
/// `<think>` preamble — and a C++ exception crossing the native boundary takes the process down
/// rather than surfacing as a catchable error. A planner parse failure must never be able to
/// terminate the app, so structural correctness here comes entirely from tolerant parsing plus a
/// deterministic fallback, never from constraining the sampler. The engine's `grammar` parameter
/// exists and stays unused; this is not an oversight to fix.
class AgentPlanner {
  const AgentPlanner({required ChatEngine chatEngine}) : _chatEngine = chatEngine;

  final ChatEngine _chatEngine;

  static const String systemPrompt = '''
You are a routing planner for an offline AI assistant. Decide whether the user's latest message needs a tool before it can be answered well.

Respond with ONLY a single compact JSON object matching this exact schema -- no explanation, no reasoning, no markdown code fences, no <think> block, nothing before or after the JSON:

{"action": "answer" | "web_search" | "file_search" | "web_and_file_search" | "device_context", "query": "short search phrase", "reason": "short internal reason", "needs_current_information": true or false, "needs_private_files": true or false}

Use "device_context" only if the user is asking for the current date, time, or timezone.
Only choose web_search or file_search when it is clearly necessary; prefer "answer" otherwise. "query" should be the smallest possible search phrase, never the full message. Output the JSON object and nothing else.''';

  /// Keep the planner's own output budget small — it is a routing decision, not an answer.
  static const int maxTokens = 120;

  Future<AgentDecision> decide({
    required AgentRequest request,
    required GenerationConfiguration configuration,
  }) async {
    final plannerConfiguration = configuration.copyWith(
      temperature: 0.2,
      minP: 0.0,
      topP: 1.0,
    );

    final hasDocuments = request.attachedDocuments.isNotEmpty;
    // "/no_think" is Qwen3's documented inline switch to suppress its default <think>...</think>
    // preamble. `llama_chat_apply_template` has no `enable_thinking` parameter — that is a
    // Python/HF-only kwarg — so an in-band directive is the only way to request non-thinking
    // output through llama.cpp's C API. This is purely an optimisation (shorter, cheaper planner
    // calls); correctness never depends on the model honouring it, because `tolerantParse`
    // strips <think> blocks regardless.
    final userPrompt = 'User message: ${request.userMessage}\n'
        'Documents attached this session: ${hasDocuments ? "yes" : "no"}\n'
        '/no_think';

    // The planner sends its own system message through the tuple API; the system prompt on the
    // configuration (the user-facing assistant persona) is deliberately not used here.
    final messages = <({String role, String content})>[
      (role: 'system', content: systemPrompt),
      (role: 'user', content: userPrompt),
    ];

    final String raw;
    try {
      raw = await _chatEngine.generateStructured(
        messages: messages,
        configuration: plannerConfiguration,
        maxTokens: maxTokens,
        grammar: null,
      );
    } catch (_) {
      return deterministicFallback(request: request, reason: 'planner_call_failed');
    }

    final decision = tolerantParse(raw);
    if (decision != null) return decision;
    return deterministicFallback(request: request, reason: 'planner_parse_failed');
  }

  // -----------------------------------------------------------------------------------------
  // Tolerant parsing
  // -----------------------------------------------------------------------------------------

  static final RegExp _thinkBlockRegex =
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
  static final RegExp _codeFenceRegex = RegExp(r'```[a-zA-Z]*');

  /// Best-effort extraction of a valid [AgentDecision] from raw, unconstrained model output.
  /// Handles a `<think>` preamble, Markdown code fences, and surrounding prose. Returns null —
  /// never throws — when nothing usable is found, so the caller falls back to deterministic
  /// routing rather than guessing.
  static AgentDecision? tolerantParse(String raw) {
    final withoutThinking = removingThinkBlocks(raw);
    final withoutFences = strippingCodeFences(withoutThinking);
    final jsonSubstring = firstBalancedJsonObject(withoutFences);
    if (jsonSubstring == null) return null;
    try {
      return AgentDecision.fromJson(jsonDecode(jsonSubstring));
    } on FormatException {
      return null;
    }
  }

  static String removingThinkBlocks(String text) => text.replaceAll(_thinkBlockRegex, '');

  static String strippingCodeFences(String text) => text.replaceAll(_codeFenceRegex, '');

  /// Scans for the first `{`, then walks forward tracking brace depth — respecting string
  /// literals and `\"`/`\\` escapes so braces inside JSON string values do not throw off the
  /// count — to find its matching `}`.
  ///
  /// Deliberately not "first `{` to last `}`": that would over-capture past the object into
  /// trailing prose. Returns null for unbalanced input, which is what truncation at `maxTokens`
  /// produces.
  static String? firstBalancedJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var isEscaped = false;

    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        if (isEscaped) {
          isEscaped = false;
        } else if (char == '\\') {
          isEscaped = true;
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) return text.substring(start, index + 1);
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------------------------
  // Deterministic fallback routing
  // -----------------------------------------------------------------------------------------

  /// Used whenever the planner call fails or its output cannot be parsed.
  ///
  /// Mirrors the router's own phrase and pattern signals so a broken or unavailable planner
  /// degrades to roughly the judgment the router would have made, rather than universally
  /// answering with no tool.
  ///
  /// One asymmetry against [AgentRouter.route] is intentional: this branch treats the *soft*
  /// [AgentRouter.currentInformationPhrases] as web-worthy, where the router only sends those to
  /// the planner. With no planner available there is nothing left to adjudicate them, so leaning
  /// toward retrieving evidence beats leaning toward guessing.
  static AgentDecision deterministicFallback({
    required AgentRequest request,
    required String reason,
  }) {
    final lowered = request.userMessage.toLowerCase();
    final hasDocuments = request.attachedDocuments.isNotEmpty;

    final isDefinitionalUseOfFreshnessWord =
        AgentRouter.negativeFreshnessGuards.any(lowered.contains);

    if (AgentRouter.explicitNoWebPhrases.any(lowered.contains)) {
      final needsCurrentInfo = !isDefinitionalUseOfFreshnessWord &&
          AgentRouter.matchesHardFreshness(lowered);
      // `needsPrivateFiles` follows the attachments even when the action is a plain answer —
      // matching the Swift, where the two are computed independently.
      return AgentDecision(
        action: hasDocuments ? AgentAction.fileSearch : AgentAction.answer,
        query: request.userMessage,
        reason: reason,
        needsCurrentInformation: needsCurrentInfo,
        needsPrivateFiles: hasDocuments,
      );
    }

    if (AgentRouter.explicitWebPhrases.any(lowered.contains)) {
      return AgentDecision(
        action: hasDocuments ? AgentAction.webAndFileSearch : AgentAction.webSearch,
        query: request.userMessage,
        reason: reason,
        needsCurrentInformation: true,
        needsPrivateFiles: hasDocuments,
      );
    }

    if (AgentRouter.deviceTimePhrases.any(lowered.contains) ||
        AgentRouter.deviceDatePhrases.any(lowered.contains)) {
      return AgentDecision(
        action: AgentAction.deviceContext,
        query: request.userMessage,
        reason: reason,
        needsCurrentInformation: false,
        needsPrivateFiles: false,
      );
    }

    final wantsWeb = !isDefinitionalUseOfFreshnessWord &&
        (AgentRouter.matchesHardFreshness(lowered) ||
            AgentRouter.currentInformationPhrases.any(lowered.contains));
    // Mirrors the router's "always plan when documents are attached" rule: a document question
    // does not need an explicit "in this file" phrase to be about the file.
    final wantsFiles = hasDocuments;

    final AgentAction action;
    if (wantsWeb && wantsFiles) {
      action = AgentAction.webAndFileSearch;
    } else if (wantsWeb) {
      action = AgentAction.webSearch;
    } else if (wantsFiles) {
      action = AgentAction.fileSearch;
    } else {
      action = AgentAction.answer;
    }

    return AgentDecision(
      action: action,
      query: request.userMessage,
      reason: reason,
      needsCurrentInformation: wantsWeb,
      needsPrivateFiles: wantsFiles,
    );
  }
}
