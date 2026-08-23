import 'dart:convert';
import 'dart:typed_data';

/// Reassembles raw UTF-8 fragments arriving one llama.cpp token at a time into complete text.
///
/// A single token frequently encodes only part of a multi-byte scalar — accented Latin,
/// Bengali, CJK, emoji — so bytes have to be held back until a full sequence is available.
/// Decoding eagerly produces a stream of U+FFFD replacement characters that then get
/// appended to the visible message and cannot be taken back.
///
/// This matters more here than in an English-first app: Bengali is entirely three-byte
/// scalars, so nearly every token boundary lands mid-character.
class Utf8TokenBuffer {
  final List<int> _pending = <int>[];

  /// Feeds in new bytes and returns whatever complete text can be emitted right now.
  /// Returns an empty string when the new bytes only extend a still-incomplete sequence.
  String push(Uint8List bytes) {
    _pending.addAll(bytes);
    if (_pending.isEmpty) return '';

    final whole = _tryDecode(_pending);
    if (whole != null) {
      _pending.clear();
      return whole;
    }

    // The tail is an incomplete sequence. A UTF-8 scalar is at most four bytes, so at most
    // three can be dangling — walk backward to find the longest valid prefix.
    final maxBacktrack = _pending.length - 1 < 3 ? _pending.length - 1 : 3;
    if (maxBacktrack <= 0) return '';

    for (var backtrack = 1; backtrack <= maxBacktrack; backtrack++) {
      final candidateLength = _pending.length - backtrack;
      if (candidateLength <= 0) continue;
      final prefix = _tryDecode(_pending.sublist(0, candidateLength));
      if (prefix != null) {
        _pending.removeRange(0, candidateLength);
        return prefix;
      }
    }

    return '';
  }

  /// Called at the end of generation to force-decode whatever is left.
  ///
  /// Uses lenient decoding so a genuinely invalid trailing sequence becomes a replacement
  /// character rather than being silently dropped — losing the last character of a response
  /// without trace is worse than showing that something was malformed.
  String flush() {
    if (_pending.isEmpty) return '';
    final result = utf8.decode(_pending, allowMalformed: true);
    _pending.clear();
    return result;
  }

  bool get hasPendingBytes => _pending.isNotEmpty;

  static String? _tryDecode(List<int> bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } on FormatException {
      return null;
    }
  }
}
