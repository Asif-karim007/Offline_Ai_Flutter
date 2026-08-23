import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent_id.dart';
import 'web_search_provider.dart';
import 'web_search_result.dart';

/// [WebSearchProvider] backed by the Brave Search API — the provider selected for this project.
///
/// Requires a Brave Search API subscription key, read from [ApiKeyStore] by the caller and
/// passed in here; never hard-coded in the app bundle.
///
/// Only `title`/`url`/`description` are decoded. Brave's real response carries more fields
/// (age, thumbnail, and others) that vary by plan and endpoint version, and `publishedDate` is
/// left null rather than guessing at an undocumented field name — a wrong date on a piece of
/// evidence is worse than no date.
class BraveWebSearchProvider implements WebSearchProvider {
  BraveWebSearchProvider({required String apiKey, http.Client? client})
      : _apiKey = apiKey,
        _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  static final Uri _endpoint = Uri.parse('https://api.search.brave.com/res/v1/web/search');

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<List<WebSearchResult>> search({
    required String query,
    required int maxResults,
  }) async {
    final count = maxResults < 1 ? 1 : (maxResults > 10 ? 10 : maxResults);
    final url = _endpoint.replace(queryParameters: {'q': query, 'count': '$count'});

    final response = await _client.get(url, headers: {
      'Accept': 'application/json',
      'X-Subscription-Token': _apiKey,
    }).timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebSearchError.requestFailed('HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const WebSearchError.invalidResponse();
    }
    if (decoded is! Map) throw const WebSearchError.invalidResponse();

    final web = decoded['web'];
    final rawResults = web is Map ? web['results'] : null;
    if (rawResults is! List) return const [];

    final results = <WebSearchResult>[];
    for (final entry in rawResults) {
      if (results.length >= maxResults) break;
      if (entry is! Map) continue;
      final title = entry['title'];
      final rawUrl = entry['url'];
      if (title is! String || rawUrl is! String) continue;
      final url = Uri.tryParse(rawUrl);
      if (url == null) continue;
      final description = entry['description'];
      results.add(WebSearchResult(
        id: newAgentId(),
        title: title,
        url: url,
        snippet: description is String ? description : '',
        sourceName: url.host.isEmpty ? null : url.host,
        publishedDate: null,
      ));
    }
    return results;
  }
}
