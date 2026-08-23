import '../agent_id.dart';
import 'web_search_result.dart';

/// Parses DuckDuckGo's HTML search-results markup into [WebSearchResult]s.
///
/// This targets the server-rendered `html.duckduckgo.com/html/` markup specifically. It is
/// screen-scraping, not a documented or versioned API, so it can break if DuckDuckGo changes
/// their markup without notice.
///
/// The regex pipeline is kept rather than reaching for `package:html`. A DOM parse handles
/// malformed markup differently and would produce different titles and snippets on exactly the
/// pages where the two disagree, which is precisely where a difference is hardest to notice.
abstract final class DuckDuckGoResultParser {
  static final RegExp _linkRegex = RegExp(
    r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _snippetRegex = RegExp(
    r'<a[^>]+class="result__snippet"[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _tagRegex = RegExp(r'<[^>]+>');

  static List<WebSearchResult> parseResults(String html) {
    final linkMatches = _linkRegex.allMatches(html).toList();
    final snippetMatches = _snippetRegex.allMatches(html).toList();

    final results = <WebSearchResult>[];
    for (var index = 0; index < linkMatches.length; index++) {
      final match = linkMatches[index];
      final href = match.group(1);
      final titleRaw = match.group(2);
      if (href == null || titleRaw == null) continue;

      final resolvedUrl = _resolveRedirect(href);
      if (resolvedUrl == null) continue;

      final title = _stripTags(_decodeEntities(titleRaw));

      // Snippets are matched to links by position, not DOM proximity — if the page emits an
      // unequal number of the two, later results simply lose their snippet.
      var snippet = '';
      if (index < snippetMatches.length) {
        final snippetRaw = snippetMatches[index].group(1);
        if (snippetRaw != null) snippet = _stripTags(_decodeEntities(snippetRaw));
      }

      results.add(WebSearchResult(
        id: newAgentId(),
        title: title,
        url: resolvedUrl,
        snippet: snippet,
        sourceName: resolvedUrl.host.isEmpty ? null : resolvedUrl.host,
        publishedDate: null,
      ));
    }
    return results;
  }

  /// Some responses point result links directly at the target site; others wrap them as
  /// `//duckduckgo.com/l/?uddg=<percent-encoded-target>&...`. Unwrap that redirect so callers
  /// always get the real destination.
  static Uri? _resolveRedirect(String href) {
    final normalized = href.startsWith('//') ? 'https:$href' : href;
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return null;
    if (parsed.host.contains('duckduckgo.com')) {
      final uddg = parsed.queryParameters['uddg'];
      if (uddg != null) return Uri.tryParse(uddg);
    }
    return parsed;
  }

  static String _stripTags(String text) => text.replaceAll(_tagRegex, '').trim();

  /// `&amp;` is decoded last on purpose. Swift iterated an unordered `Dictionary` here, so
  /// `&amp;lt;` could decode to `<` or to `&lt;` depending on the run; Dart map literals iterate
  /// in insertion order, which lets that ambiguity be resolved correctly instead of
  /// bug-compatibly.
  static const Map<String, String> _entities = {
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&#x27;': "'",
    '&nbsp;': ' ',
    '&amp;': '&',
  };

  static String _decodeEntities(String text) {
    var result = text;
    for (final entry in _entities.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
