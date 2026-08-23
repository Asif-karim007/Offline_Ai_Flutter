enum _FilterState { visible, hiddenThinking }

/// Streaming state machine that removes `<think>...</think>` blocks from a token stream before
/// any of it becomes user-visible text.
///
/// A single llama.cpp token frequently does not align with tag boundaries at all (`<th` +
/// `ink>`, or `</thi` + `nk>`), so this never assumes a tag arrives whole — it holds back only
/// the minimal ambiguous suffix that could still become part of a tag, and only reveals text
/// once it is certain that text is not part of `<think>` or `</think>`. Reasoning text is
/// discarded as it streams, not rendered and later removed, so it never reaches the caller at
/// all.
///
/// Swift models this as a `mutating struct`; Dart has no mutating value semantics, so it is a
/// mutable class. Create one per generation — [flush] resets it, but sharing an instance across
/// two concurrent streams would interleave their buffers.
class ThinkingContentFilter {
  ThinkingContentFilter();

  static const String _openTag = '<think>';
  static const String _closeTag = '</think>';

  _FilterState _state = _FilterState.visible;
  String _pendingBuffer = '';

  /// Feeds a new chunk of decoded text and returns only the portion safe to show right now.
  /// Returns an empty string when the entire chunk is either still ambiguous (it might become
  /// part of a tag) or confirmed hidden reasoning content.
  String push(String chunk) {
    if (chunk.isEmpty) return '';
    _pendingBuffer += chunk;
    final output = StringBuffer();

    while (true) {
      if (_state == _FilterState.visible) {
        final openIndex = _pendingBuffer.indexOf(_openTag);
        if (openIndex >= 0) {
          output.write(_pendingBuffer.substring(0, openIndex));
          _pendingBuffer = _pendingBuffer.substring(openIndex + _openTag.length);
          _state = _FilterState.hiddenThinking;
          continue;
        }
        final holdLength = _longestSuffixOverlap(_pendingBuffer, _openTag);
        final emitEnd = _pendingBuffer.length - holdLength;
        output.write(_pendingBuffer.substring(0, emitEnd));
        _pendingBuffer = _pendingBuffer.substring(emitEnd);
        break;
      } else {
        final closeIndex = _pendingBuffer.indexOf(_closeTag);
        if (closeIndex >= 0) {
          _pendingBuffer = _pendingBuffer.substring(closeIndex + _closeTag.length);
          _state = _FilterState.visible;
          continue;
        }
        final holdLength = _longestSuffixOverlap(_pendingBuffer, _closeTag);
        final dropEnd = _pendingBuffer.length - holdLength;
        // Everything before the ambiguous suffix is reasoning: dropped, never emitted.
        _pendingBuffer = _pendingBuffer.substring(dropEnd);
        break;
      }
    }

    return output.toString();
  }

  /// Call once generation ends. Text still held back while visible — a suffix that looked like
  /// it might start a `<think>` tag, but generation stopped before disambiguating it — is
  /// genuine content and must be released. Text buffered while hidden is reasoning that never
  /// closed, and is correctly discarded.
  String flush() {
    final result = _state == _FilterState.visible ? _pendingBuffer : '';
    _pendingBuffer = '';
    _state = _FilterState.visible;
    return result;
  }

  /// How many trailing characters of [text] could be the beginning of [tag] if more text
  /// arrives next — the minimal amount that must be held back rather than emitted or discarded.
  /// Capped at `tag.length - 1` because a full tag is a match, not an ambiguity.
  static int _longestSuffixOverlap(String text, String tag) {
    final maxLength = text.length < tag.length - 1 ? text.length : tag.length - 1;
    if (maxLength <= 0) return 0;
    for (var length = maxLength; length >= 1; length--) {
      if (tag.startsWith(text.substring(text.length - length))) return length;
    }
    return 0;
  }
}
