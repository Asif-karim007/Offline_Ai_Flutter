/// Removes sentences that echo the app's internal prompt vocabulary from a finished answer.
///
/// Small on-device models sometimes repeat what they were given verbatim. Seen on a phone:
/// a Bangla answer ending "আমি এখানে WEB_SEARCH_PERFORMED এবং DOCUMENT_SEARCH_PERFORMED
/// নির্দেশকৃত… ব্যবহার করেছিলাম" — meaningless and confusing to a student. The system prompt
/// forbids it (rule 18); this is the backstop for when a 2B model does it anyway. Applied to
/// the finished answer only, so streaming stays token by token.
abstract final class InternalTermScrubber {
  static final RegExp _internalTerm = RegExp(
    r'WEB_SEARCH_PERFORMED|DOCUMENT_SEARCH_PERFORMED|TEXTBOOK_SEARCH_PERFORMED|'
    r'REPLY_LANGUAGE|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMEZONE|'
    r'textbook_sources|document_sources|web_sources',
  );

  /// Sentence or line boundaries in Bangla (।) and English.
  static final RegExp _sentence = RegExp(r'[^।.!?\n]*[।.!?]?\s*');

  static String scrub(String text) {
    if (!_internalTerm.hasMatch(text)) return text;
    final kept = StringBuffer();
    for (final match in _sentence.allMatches(text)) {
      final sentence = match.group(0)!;
      if (!_internalTerm.hasMatch(sentence)) kept.write(sentence);
    }
    return kept.toString().trimRight();
  }
}
