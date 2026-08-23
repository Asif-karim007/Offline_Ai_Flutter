/// Extracts readable text from raw HTML: strips script/style/navigation blocks, converts common
/// block-level tags to line breaks, then strips remaining tags and decodes common entities.
///
/// Deliberately not a DOM parse. `package:html` would be the obvious choice for new code, but it
/// normalises whitespace differently and recovers from malformed markup
/// differently, so it produces different excerpt text — and excerpt text is what the model
/// answers from. Keeping the Swift regex pipeline keeps web evidence identical between the two
/// apps. The known cost is that nested same-name tags are handled incorrectly by the non-greedy
/// block strip; that was an accepted tradeoff in the original and remains one here.
abstract final class WebContentExtractor {
  static const List<String> _stripBlockTags = [
    'script', 'style', 'nav', 'header', 'footer', 'noscript', 'svg', 'form',
  ];

  static const List<String> _blockLevelTags = [
    'p', 'div', 'br', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'tr',
  ];

  static final RegExp _anyTagRegex = RegExp(r'<[^>]+>');
  static final RegExp _newlineRegex = RegExp(r'\r\n|\r|\n');

  static final Map<String, RegExp> _blockStripRegexes = {
    for (final tag in _stripBlockTags)
      tag: RegExp('<$tag\\b[^>]*>.*?</$tag>', caseSensitive: false, dotAll: true),
  };

  static final Map<String, List<RegExp>> _blockLevelRegexes = {
    for (final tag in _blockLevelTags)
      tag: [
        RegExp('</$tag>', caseSensitive: false),
        RegExp('<$tag>', caseSensitive: false),
      ],
  };

  static String extractReadableText(String html) {
    var text = html;

    for (final tag in _stripBlockTags) {
      text = text.replaceAll(_blockStripRegexes[tag]!, '');
    }

    // Turn common block-level opens and closes into line breaks before stripping tags, so
    // extracted text still reads as paragraphs rather than one run-on line. Only *bare* opening
    // tags are converted — `<p class="...">` is not, and gets removed unmarked by the general
    // tag strip below. That is the Swift behaviour.
    for (final tag in _blockLevelTags) {
      for (final regex in _blockLevelRegexes[tag]!) {
        text = text.replaceAll(regex, '\n');
      }
    }

    text = text.replaceAll(_anyTagRegex, '');
    text = _decodeEntities(text);

    final lines = text
        .split(_newlineRegex)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    return lines.join('\n');
  }

  /// A larger map than [DuckDuckGoResultParser]'s, and not a superset of it: `&#x27;` is absent
  /// here, and the curly-quote entities map to ASCII rather than to typographic characters.
  /// Both quirks are carried across as-is — the evidence text they produce is what the model was
  /// tuned against. `&amp;` is decoded last so `&amp;lt;` resolves correctly.
  static const Map<String, String> _entities = {
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
    '&mdash;': '—',
    '&ndash;': '–',
    '&rsquo;': "'",
    '&lsquo;': "'",
    '&rdquo;': '"',
    '&ldquo;': '"',
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
