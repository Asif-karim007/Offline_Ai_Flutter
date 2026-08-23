import 'web_search_result.dart';

enum WebSearchErrorKind { notConfigured, requestFailed, invalidResponse }

/// Failures a provider or page fetch can produce. One class with a [kind] discriminator, the
/// same shape as `LlamaError`, rather than a sealed hierarchy — the orchestrator swallows these
/// wholesale and only ever logs the kind.
class WebSearchError implements Exception {
  const WebSearchError(this.kind, {this.message});

  final WebSearchErrorKind kind;

  /// Only set for [WebSearchErrorKind.requestFailed]. Developer-facing.
  final String? message;

  const WebSearchError.notConfigured() : this(WebSearchErrorKind.notConfigured);

  const WebSearchError.requestFailed(String message)
      : this(WebSearchErrorKind.requestFailed, message: message);

  const WebSearchError.invalidResponse() : this(WebSearchErrorKind.invalidResponse);

  String get errorDescription => switch (kind) {
        WebSearchErrorKind.notConfigured => "Web search isn't configured.",
        WebSearchErrorKind.requestFailed => 'Web search failed: $message',
        WebSearchErrorKind.invalidResponse => 'Web search returned an unexpected response.',
      };

  @override
  bool operator ==(Object other) =>
      other is WebSearchError && other.kind == kind && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'WebSearchError.${kind.name}${message == null ? '' : '($message)'}';
}

/// Search-provider abstraction.
///
/// [WebSearchService] and the orchestrator depend only on this interface, never on a specific
/// vendor. When no provider is configured the orchestrator's web-search dependency is null and
/// the rest of the agent — memory, local document RAG, device context, local reasoning — works
/// fully offline.
///
/// Two implementations ship: [BraveWebSearchProvider] (the documented, supported provider, used
/// whenever an API key is configured) and [DuckDuckGoHtmlSearchProvider] (zero-configuration
/// fallback).
///
/// The Swift app had a third, `WKWebViewSearchProvider`, which drove an off-screen `WKWebView`
/// so that DuckDuckGo saw a real browser session rather than a bare HTTP client — some endpoints
/// serve a bot-detection challenge to the latter and full results to the former. It is
/// deliberately **not** ported. It has no cross-platform equivalent: `webview_flutter` cannot
/// run headless, and `flutter_inappwebview`'s `HeadlessInAppWebView` is a large dependency that
/// behaves differently on Android (a different engine, different UA handling, different
/// challenge outcomes) than the WebKit it was written against — so porting it would mean
/// shipping something that shares its name but not its behaviour. Rather than fabricate that,
/// this port leaves Brave and the plain-HTTP DuckDuckGo provider, and accepts that a challenged
/// DuckDuckGo request now surfaces as an empty result set instead of being worked around. The
/// orchestrator already treats empty web evidence as a hard refusal rather than a licence to
/// guess, so the failure mode is honest.
abstract interface class WebSearchProvider {
  Future<List<WebSearchResult>> search({required String query, required int maxResults});
}
