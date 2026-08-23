import 'dart:convert';

import 'package:http/http.dart' as http;

import 'web_search_provider.dart';

/// Fetches the raw contents of a single web page. [WebPageFetcher] is the real implementation;
/// tests substitute a fake so [WebSearchService] can be exercised without hitting the network.
abstract interface class WebPageFetching {
  Future<String> fetch(Uri url);
}

/// Fetches one page with a timeout and a maximum download size, rejecting content types that
/// are not readable text or HTML.
///
/// Every fetched page is treated as untrusted external data — see [WebContentExtractor] and the
/// `<web_sources>` wrapping in [ContextAssembler] — never as instructions.
class WebPageFetcher implements WebPageFetching {
  WebPageFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.maxBytes = 2000000,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maxBytes;

  static const List<String> allowedContentTypePrefixes = [
    'text/html',
    'text/plain',
    'application/xhtml+xml',
  ];

  @override
  Future<String> fetch(Uri url) async {
    final response = await _client
        .get(url, headers: {'Accept': 'text/html,text/plain;q=0.9'}).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const WebSearchError.requestFailed('page fetch failed');
    }

    final contentType = response.headers['content-type']?.toLowerCase();
    // An absent Content-Type is allowed through — only a present-and-wrong one is rejected.
    if (contentType != null) {
      final allowed = allowedContentTypePrefixes.any(contentType.startsWith);
      if (!allowed) {
        throw const WebSearchError.requestFailed('unsupported content type');
      }
    }

    // The size check lands after the body has already been downloaded. `package:http`'s simple
    // `get` has no streaming abort, and the Swift original had the same shape — the cap is a
    // guard on how much text reaches the chunker, not a bandwidth control.
    final bytes = response.bodyBytes;
    if (bytes.length > maxBytes) {
      throw const WebSearchError.requestFailed('page too large');
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      try {
        return latin1.decode(bytes);
      } on FormatException {
        throw const WebSearchError.invalidResponse();
      }
    }
  }
}
