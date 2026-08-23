import 'dart:convert';

import 'package:http/http.dart' as http;

import 'duckduckgo_result_parser.dart';
import 'web_search_provider.dart';
import 'web_search_result.dart';

/// [WebSearchProvider] backed by DuckDuckGo's free, unauthenticated HTML search surface — no API
/// key or subscription required.
///
/// A plain HTTP request. Some networks and endpoints challenge non-browser clients like this
/// one; the Swift app answered that with a `WKWebView`-driven provider, which this port does not
/// have (see [WebSearchProvider] for why). [BraveWebSearchProvider] remains the documented,
/// supported provider when a key is configured; this exists as the zero-configuration fallback.
class DuckDuckGoHtmlSearchProvider implements WebSearchProvider {
  DuckDuckGoHtmlSearchProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _endpoint = Uri.parse('https://html.duckduckgo.com/html/');

  /// The HTML endpoint returns a challenge page rather than results for requests with no or an
  /// unusual User-Agent, so this presents as a normal mobile browser.
  static const String userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<List<WebSearchResult>> search({
    required String query,
    required int maxResults,
  }) async {
    // No `count` parameter — the HTML surface does not take one.
    final url = _endpoint.replace(queryParameters: {'q': query});

    final response =
        await _client.get(url, headers: {'User-Agent': userAgent}).timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebSearchError.requestFailed('HTTP ${response.statusCode}');
    }

    final String html;
    try {
      html = utf8.decode(response.bodyBytes);
    } on FormatException {
      throw const WebSearchError.invalidResponse();
    }

    final results = DuckDuckGoResultParser.parseResults(html);
    return results.length <= maxResults ? results : results.sublist(0, maxResults);
  }
}
