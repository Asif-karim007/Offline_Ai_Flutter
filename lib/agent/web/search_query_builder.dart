/// Deterministic, LLM-free query minimisation for the router's definite web routes.
///
/// Only a light trim of conversational wrapper phrases and trailing punctuation. This
/// intentionally does not attempt semantic rewriting — that would need another model call and
/// add latency and reliability risk for marginal benefit. The stronger privacy guarantee is
/// structural anyway: [WebSearchService] only ever receives this single query string, never the
/// conversation history, other messages, or document contents.
abstract final class SearchQueryBuilder {
  /// Each entry carries a trailing space, so the prefix only matches at a word boundary.
  static const List<String> _stripPrefixes = [
    'please ', 'can you ', 'could you ', 'would you ', 'i want to know ',
    "i'd like to know ", 'tell me ', 'search for ', 'search the web for ',
    'search online for ', 'look up ', 'find out ',
  ];

  /// The prefix loop restarts after every match, so nested wrappers unwind:
  /// "Please can you tell me the weather in Paris?" becomes "the weather in Paris".
  static String minimalQuery(String message) {
    var text = message.trim();

    var didStrip = true;
    while (didStrip) {
      didStrip = false;
      final lowered = text.toLowerCase();
      for (final prefix in _stripPrefixes) {
        if (lowered.startsWith(prefix)) {
          // Matched against the lowercased copy, dropped from the original-case text by the
          // same character count — the two stay aligned because `toLowerCase` is length
          // preserving for every character these prefixes contain.
          text = text.substring(prefix.length).trim();
          didStrip = true;
          break;
        }
      }
    }

    while (text.isNotEmpty && '.?!'.contains(text[text.length - 1])) {
      text = text.substring(0, text.length - 1);
    }

    final trimmed = text.trim();
    return trimmed.isEmpty ? message.trim() : trimmed;
  }
}
