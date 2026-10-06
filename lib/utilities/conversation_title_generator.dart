import '../l10n/app_strings.dart';

/// Derives a conversation title from the first user message, with no extra model call.
///
/// Ported step for step from `Utilities/ConversationTitleGenerator.swift`, including the
/// parts that look like bugs:
///
/// * Interior runs of spaces and tabs are **not** collapsed, despite the Swift local
///   variable being named `collapsedWhitespace`. A CRLF becomes two spaces, because
///   `components(separatedBy: .newlines)` splits on each newline character individually and
///   leaves an empty component between the two — which then joins as a second space.
/// * Trimming uses `.whitespaces` (tab plus the Unicode `Zs` category) and not
///   `.whitespacesAndNewlines`. After the first step there are no newlines left anyway, but
///   the distinction is preserved so the two implementations read the same.
///
/// Keeping these makes titles identical to the iOS app for the same input, which is what a
/// future migration of an existing store would be diffed against.
///
/// The character sets are written as code-unit tables rather than regular expressions so
/// that every member of Swift's `CharacterSet.newlines` and `.whitespaces` is visible and
/// auditable in the source, instead of hiding behind escapes.
abstract final class ConversationTitleGenerator {
  static const int maxLength = 40;

  /// `CharacterSet.newlines`: LF, VT, FF, CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR.
  static const Set<int> _newlines = {
    0x000A,
    0x000B,
    0x000C,
    0x000D,
    0x0085,
    0x2028,
    0x2029,
  };

  /// `CharacterSet.whitespaces`: horizontal tab plus the Unicode `Zs` category.
  static const Set<int> _whitespace = {
    0x0009, // tab
    0x0020, // space
    0x00A0, // no-break space
    0x1680, // ogham space mark
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005,
    0x2006, 0x2007, 0x2008, 0x2009, 0x200A, // en/em quad through hair space
    0x202F, // narrow no-break space
    0x205F, // medium mathematical space
    0x3000, // ideographic space
  };

  static String titleFromFirstMessage(String text) {
    final flattened = _trimWhitespace(_replaceNewlinesWithSpaces(text));

    if (flattened.isEmpty) {
      // Stored as the conversation's title, so it is in the language the app was in when the
      // conversation was created and does not follow a later language switch.
      return AppStrings.current.newChat;
    }

    // Swift counts and slices by extended grapheme cluster; this counts by Unicode code
    // point. The two agree for every script the model is likely to be asked about — the
    // divergence is limited to combining marks, regional-indicator flags and ZWJ emoji
    // sequences, where this can cut a cluster in half. Closing that gap needs
    // `package:characters`, which this project does not declare as a dependency, and a rare
    // mid-emoji truncation in a sidebar title did not justify adding one.
    final codePoints = flattened.runes.toList(growable: false);
    if (codePoints.length <= maxLength) {
      return flattened;
    }

    final truncated =
        _trimWhitespace(String.fromCharCodes(codePoints.take(maxLength)));
    return '$truncated…';
  }

  /// Every newline code unit becomes one space — one *per character*, which is why CRLF
  /// yields two.
  static String _replaceNewlinesWithSpaces(String text) {
    final units = List<int>.of(text.codeUnits);
    for (var i = 0; i < units.length; i++) {
      if (_newlines.contains(units[i])) {
        units[i] = 0x0020;
      }
    }
    return String.fromCharCodes(units);
  }

  static String _trimWhitespace(String value) {
    var start = 0;
    var end = value.length;
    while (start < end && _whitespace.contains(value.codeUnitAt(start))) {
      start += 1;
    }
    while (end > start && _whitespace.contains(value.codeUnitAt(end - 1))) {
      end -= 1;
    }
    return start == 0 && end == value.length ? value : value.substring(start, end);
  }
}
