import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../agent/curriculum/textbook_retriever.dart';
import '../agent/retrieval/bm25_scorer.dart';
import '../utilities/bangla_text.dart';

/// Keyword search over one curriculum pack, inside the pack's own SQLite file.
///
/// A class 9–10 pack holds ~20,000 passages (~15 million characters). Loading that into Dart
/// to score it — what `BM25Scorer` does for a handful of attached documents — would cost tens
/// of megabytes and seconds per question. Instead the pack gets an SQLite FTS4 index the first
/// time it is opened, and each search asks SQLite for the matching rows plus their term
/// statistics (`matchinfo`), from which BM25 is computed here. Only the few winning passages'
/// text ever crosses into Dart.
///
/// FTS4 with the `unicode61` tokenizer, deliberately: it is in every SQLite that Android and
/// iOS ship, and `unicode61` treats combining marks as part of a word, so Bangla words stay
/// whole — the exact bug `BM25Scorer` had. FTS5 would be nicer but is not guaranteed on
/// Android's system SQLite.
class CurriculumIndex {
  CurriculumIndex._(this._db);

  /// Opens the pack at [path], building its full-text index first if this is the first
  /// open. The build is a one-off that takes seconds on a large pack; later opens are instant.
  static Future<CurriculumIndex> open(String path, {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(path);
    final index = CurriculumIndex._(db);
    try {
      await index._ensureFullTextIndex();
    } catch (_) {
      await db.close();
      rethrow;
    }
    return index;
  }

  final Database _db;

  /// Bumped whenever the index definition changes, so an existing pack is re-indexed.
  static const String _indexVersion = '1';
  static const String _indexVersionKey = 'app_fts_version';

  Future<void> _ensureFullTextIndex() async {
    final rows = await _db.rawQuery(
      'SELECT value FROM meta WHERE key = ?',
      [_indexVersionKey],
    );
    if (rows.isNotEmpty && rows.first['value'] == _indexVersion) {
      return;
    }
    await _db.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS chunks_fts');
      // External content: the index stores no second copy of the text, only the postings,
      // and its docid is `chunks.id`.
      await txn.execute(
        'CREATE VIRTUAL TABLE chunks_fts USING fts4(content="chunks", text, tokenize=unicode61)',
      );
      await txn.execute("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild')");
      await txn.execute(
        'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        [_indexVersionKey, _indexVersion],
      );
    });
  }

  Future<void> close() => _db.close();

  /// The best passages for [query], most relevant first.
  Future<List<TextbookExcerpt>> search(String query, {int limit = 3}) async {
    final terms = queryTerms(query);
    if (terms.isEmpty) {
      return const [];
    }

    final rows = await _db.rawQuery(
      "SELECT docid, matchinfo(chunks_fts, 'pcnalx') AS info "
      'FROM chunks_fts WHERE chunks_fts MATCH ?',
      [terms.join(' OR ')],
    );
    if (rows.isEmpty) {
      return const [];
    }

    final scored = <(int, double)>[
      for (final row in rows)
        (row['docid']! as int, bm25FromMatchInfo(row['info']! as Uint8List)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    final best = scored.take(limit).where((entry) => entry.$2 > 0).toList();
    if (best.isEmpty) {
      return const [];
    }

    final ids = best.map((entry) => entry.$1).toList();
    final passages = await _db.rawQuery(
      'SELECT c.id AS id, c.page_start AS page, c.text AS text, b.title AS title '
      'FROM chunks c JOIN books b ON b.id = c.book_id '
      'WHERE c.id IN (${List.filled(ids.length, '?').join(', ')})',
      ids,
    );
    final byId = {for (final row in passages) row['id']! as int: row};
    return [
      for (final id in ids)
        if (byId[id] case final row?)
          TextbookExcerpt(
            bookTitle: row['title']! as String,
            page: row['page'] as int?,
            text: row['text']! as String,
          ),
    ];
  }

  // --- query construction ------------------------------------------------------------------

  /// The FTS4 terms for [query]: tokenised and normalised exactly as the pack text was,
  /// with Bangla case endings stripped and turned into prefix queries, so that
  /// "সালোকসংশ্লেষণের" in a question finds "সালোকসংশ্লেষণ" in the book and vice versa.
  static List<String> queryTerms(String query) {
    final terms = <String>{};
    for (final token in BM25Scorer.tokenize(query)) {
      if (_isBengali(token)) {
        if (_banglaStopwords.contains(token)) {
          continue;
        }
        final stem = _stripBanglaSuffix(token);
        if (stem.runes.length >= 2) {
          terms.add('$stem*');
        }
      } else if (token.length >= 3 && !_englishStopwords.contains(token)) {
        terms.add(token);
      }
      if (terms.length == _maxTerms) {
        break;
      }
    }
    // Quoted so a term can never be read as FTS syntax (`OR`, `NEAR`, a column filter). In
    // FTS4 a prefix query keeps its asterisk inside the quotes: `"word*"`.
    return [for (final term in terms) '"$term"'];
  }

  static const int _maxTerms = 12;

  /// Case endings and classifiers, longest first. Stripped only when a real stem remains,
  /// and the result is searched as a prefix — so over-stripping costs a little precision,
  /// never a miss.
  static final List<String> _banglaSuffixes = [
    'গুলোর', 'গুলির', 'গুলোকে', 'গুলো', 'গুলি', 'দেরকে', 'দের', 'য়ের', 'য়ে', 'টির', 'টার',
    'টিকে', 'টি', 'টা', 'খানা', 'ের', 'কে', 'তে', 'রা', 'র', 'ে',
  ].map(BanglaText.normalize).toList();

  static String _stripBanglaSuffix(String token) {
    for (final suffix in _banglaSuffixes) {
      if (token.endsWith(suffix) && (token.length - suffix.length) >= 3) {
        return token.substring(0, token.length - suffix.length);
      }
    }
    return token;
  }

  static bool _isBengali(String token) {
    for (final unit in token.codeUnits) {
      if (unit >= 0x0980 && unit <= 0x09FF) {
        return true;
      }
    }
    return false;
  }

  /// Question words and filler. Without these, "সালোকসংশ্লেষণ কী?" against a book that never
  /// mentions photosynthesis still "matches" — on কী alone — and hands the model a page of
  /// unrelated arithmetic as evidence. Removing them means a question only matches on its
  /// content words, and returns nothing when those are absent.
  static final Set<String> _banglaStopwords = {
    'কী', 'কি', 'কে', 'কাকে', 'কেন', 'কীভাবে', 'কিভাবে', 'কোন', 'কোনো', 'কোথায়', 'কখন', 'কত',
    'কয়টি', 'কেমন', 'বলে', 'বলতে', 'বলা', 'বোঝায়', 'বুঝায়', 'বোঝ', 'বুঝিয়ে', 'লেখ', 'লেখো',
    'লিখ', 'দাও', 'দিন', 'করো', 'কর', 'করে', 'আছে', 'হয়', 'হলো', 'হল', 'এবং', 'ও', 'তা', 'এই',
    'সেই', 'এর', 'একটি', 'একটা', 'সম্পর্কে', 'আমাকে', 'আমি', 'তুমি', 'আপনি', 'যে', 'না',
    'থেকে', 'জন্য', 'সাথে', 'দিয়ে', 'আর', 'বা', 'নিয়ে', 'সহজভাবে', 'ব্যাখ্যা',
  }.map(BanglaText.normalize).toSet();

  static const Set<String> _englishStopwords = {
    'the', 'and', 'what', 'why', 'how', 'who', 'when', 'where', 'which', 'does', 'did',
    'are', 'was', 'were', 'is', 'for', 'with', 'from', 'that', 'this', 'about', 'explain',
    'please', 'tell', 'give', 'can', 'you', 'your', 'me',
  };

  // --- scoring -----------------------------------------------------------------------------

  static const double _k1 = 1.2;
  static const double _b = 0.75;

  /// BM25 for one row from FTS4's `matchinfo(..., 'pcnalx')` blob: 32-bit unsigned integers
  /// in the order p (phrases), c (columns), n (rows), a[c] (average tokens per column),
  /// l[c] (this row's tokens per column), then for every phrase × column the triple
  /// (hits in this row, hits in all rows, rows with a hit).
  static double bm25FromMatchInfo(Uint8List blob) {
    final info = blob.buffer.asUint32List(blob.offsetInBytes, blob.lengthInBytes ~/ 4);
    final phrases = info[0];
    final columns = info[1];
    final rowCount = info[2];
    const averageLengthOffset = 3;
    final lengthOffset = averageLengthOffset + columns;
    final hitsOffset = lengthOffset + columns;

    var score = 0.0;
    for (var phrase = 0; phrase < phrases; phrase++) {
      for (var column = 0; column < columns; column++) {
        final base = hitsOffset + 3 * (phrase * columns + column);
        final termFrequency = info[base];
        if (termFrequency == 0) {
          continue;
        }
        final documentFrequency = info[base + 2];
        final idf = math.log(1 + (rowCount - documentFrequency + 0.5) / (documentFrequency + 0.5));
        final averageLength = math.max(1, info[averageLengthOffset + column]);
        final length = info[lengthOffset + column];
        final normalisation = _k1 * (1 - _b + _b * length / averageLength);
        score += idf * (termFrequency * (_k1 + 1)) / (termFrequency + normalisation);
      }
    }
    return score;
  }
}
