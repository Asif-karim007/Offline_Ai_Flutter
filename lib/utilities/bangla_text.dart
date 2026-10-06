/// Canonical form for Bengali-script text, so the same word typed on two keyboards compares
/// equal.
///
/// Several Bengali letters have two valid Unicode spellings. `য়` can arrive as the single
/// code point U+09DF or as `য` + nukta (U+09AF U+09BC); `ো` as U+09CB or as `ে` + `া`.
/// Bangla keyboards disagree about which they emit, so a plain `contains` — the router's
/// phrase tables, BM25's term matching — misses a word that is visibly identical.
///
/// Dart has no Unicode normalisation in its core libraries, so this implements Unicode NFC
/// for exactly the Bengali characters affected, and nothing else. It matches what Python's
/// `unicodedata.normalize('NFC', ...)` produces, which is how the curriculum packs in
/// `scripts/curriculum/` are written — so text from a pack and text from the keyboard meet in
/// the same form. Note that NFC *decomposes* the three nukta letters (they are composition
/// exclusions) but *composes* the two split vowel signs.
abstract final class BanglaText {
  static String normalize(String text) {
    if (!_hasBengali(text)) {
      return text; // the common case for English text: no allocation at all
    }
    final out = StringBuffer();
    final units = text.codeUnits;
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      final next = index + 1 < units.length ? units[index + 1] : -1;
      switch (unit) {
        case 0x09DC: // ড়
          out.writeCharCode(0x09A1);
          out.writeCharCode(0x09BC);
        case 0x09DD: // ঢ়
          out.writeCharCode(0x09A2);
          out.writeCharCode(0x09BC);
        case 0x09DF: // য়
          out.writeCharCode(0x09AF);
          out.writeCharCode(0x09BC);
        case 0x09C7 when next == 0x09BE: // ে + া → ো
          out.writeCharCode(0x09CB);
          index++;
        case 0x09C7 when next == 0x09D7: // ে + ৗ → ৌ
          out.writeCharCode(0x09CC);
          index++;
        default:
          out.writeCharCode(unit);
      }
    }
    return out.toString();
  }

  static bool _hasBengali(String text) {
    for (final unit in text.codeUnits) {
      if (unit >= 0x0980 && unit <= 0x09FF) {
        return true;
      }
    }
    return false;
  }
}
