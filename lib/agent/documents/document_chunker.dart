import '../agent_id.dart';
import '../token_estimator.dart';
import 'document_chunk.dart';
import 'extracted_document.dart';

/// Where a page starts, as a character offset into the marker-stripped text.
class _PageBoundary {
  const _PageBoundary(this.offset, this.page);

  final int offset;
  final int page;
}

/// Splits extracted document text into chunks of roughly 400–700 estimated tokens with ~75
/// tokens of overlap between consecutive chunks. Prefers paragraph boundaries; a paragraph that
/// alone exceeds the maximum is split by sentence, and a single sentence still too long is
/// hard-split by character span as a last resort.
///
/// Also used verbatim by [WebSearchService] for fetched pages, so the same chunk shape reaches
/// the model whether evidence came from a local file or the web.
class DocumentChunker {
  const DocumentChunker({
    this.targetTokens = 550,
    this.minTokens = 400,
    this.maxTokens = 700,
    this.overlapTokens = 75,
  });

  final int targetTokens;
  final int minTokens;
  final int maxTokens;
  final int overlapTokens;

  List<DocumentChunk> chunk(ExtractedDocument document) {
    final (plainText, pageBoundaries) = _stripPageMarkers(document.text);
    final units = _splitIntoUnits(plainText, maxTokens);
    if (units.isEmpty) return const [];

    final chunks = <DocumentChunk>[];
    var currentUnits = <String>[];
    var currentTokenCount = 0;
    var chunkIndex = 0;
    var currentStartOffset = 0;
    var runningOffset = 0;

    void flush() {
      if (currentUnits.isEmpty) return;
      final text = currentUnits.join('\n\n');
      final page = _pageNumberAtOffset(currentStartOffset, pageBoundaries);
      chunks.add(DocumentChunk(
        id: newAgentId(),
        documentId: document.id,
        documentName: document.name,
        chunkIndex: chunkIndex,
        text: text,
        startOffset: currentStartOffset,
        pageNumber: page,
      ));
      chunkIndex += 1;
      // Note that this does not clear `currentUnits` — carrying the tail forward is
      // `rollOverWithOverlap`'s job, and the two are always called as a pair.
    }

    void rollOverWithOverlap() {
      final overlapUnits = _overlapSuffix(currentUnits, overlapTokens);
      currentUnits = overlapUnits;
      currentTokenCount = overlapUnits.fold<int>(
          0, (sum, unit) => sum + TokenEstimator.estimateTokenCount(unit));
      // `runningOffset` has already been advanced past the overlap units, but they are the new
      // chunk's opening text — so wind back over them. `startOffset` has to name the chunk's real
      // first character, because `_pageNumberAtOffset` resolves the chunk's page from it; leaving
      // it at `runningOffset` labels a chunk with the following page whenever a page boundary
      // falls inside the overlap.
      currentStartOffset = runningOffset -
          overlapUnits.fold<int>(0, (sum, unit) => sum + unit.length + 2);
    }

    for (final unit in units) {
      final unitTokens = TokenEstimator.estimateTokenCount(unit);

      if (currentTokenCount + unitTokens > maxTokens && currentTokenCount >= minTokens) {
        // `runningOffset` still points at the START of `unit` here, unlike the rollover below
        // where it has already moved past it. Either way it sits just past the overlap suffix,
        // which is what `rollOverWithOverlap` winds back over.
        flush();
        rollOverWithOverlap();
      }

      currentUnits.add(unit);
      currentTokenCount += unitTokens;
      runningOffset += unit.length + 2; // +2 for the "\n\n" joiner

      if (currentTokenCount >= targetTokens) {
        flush();
        rollOverWithOverlap();
      }
    }
    // When the loop's last iteration ended in the branch above, this trailing flush re-emits
    // the overlap suffix as a standalone final chunk with duplicated tail content. That happens
    // only when the final unit is small enough (≤ overlapTokens) to survive `_overlapSuffix`;
    // a larger final unit leaves the suffix empty and the guard in `flush` suppresses it.
    flush();

    return chunks;
  }

  // -----------------------------------------------------------------------------------------
  // Splitting
  // -----------------------------------------------------------------------------------------

  static List<String> _splitIntoUnits(String text, int maxTokens) {
    final paragraphs = text
        .split('\n\n')
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty);

    final units = <String>[];
    for (final paragraph in paragraphs) {
      if (TokenEstimator.estimateTokenCount(paragraph) <= maxTokens) {
        units.add(paragraph);
      } else {
        units.addAll(_splitBySentence(paragraph, maxTokens));
      }
    }
    return units;
  }

  /// Swift used `String.enumerateSubstrings(options: .bySentences)`, which is ICU's sentence
  /// breaker and knows that "Dr. Smith" and "e.g." are not sentence ends. Dart has no equivalent
  /// and none of the allowed dependencies provides one, so this splits after `.`/`!`/`?`
  /// followed by whitespace.
  ///
  /// This is the largest fidelity gap in the port: an abbreviation produces a split ICU would
  /// not, so chunk boundaries can differ from the Swift app on prose containing abbreviations.
  /// Nothing downstream breaks — chunks are still bounded and overlapping — but a retrieval
  /// golden test written against iOS output will not match token for token here. It only
  /// matters at all for paragraphs already over `maxTokens`, since shorter paragraphs never
  /// reach this path.
  static final RegExp _sentenceBoundary = RegExp(r'(?<=[.!?])\s+');

  static List<String> _splitBySentence(String text, int maxTokens) {
    final sentences = text
        .split(_sentenceBoundary)
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return [text];

    final result = <String>[];
    for (final sentence in sentences) {
      if (TokenEstimator.estimateTokenCount(sentence) > maxTokens) {
        result.addAll(_splitByCharacterSpan(sentence, maxTokens * 4));
      } else {
        result.add(sentence);
      }
    }
    return result;
  }

  static List<String> _splitByCharacterSpan(String text, int approxCharBudget) {
    final result = <String>[];
    var start = 0;
    while (start < text.length) {
      final end =
          start + approxCharBudget < text.length ? start + approxCharBudget : text.length;
      result.add(text.substring(start, end));
      start = end;
    }
    return result;
  }

  /// Walks backwards accumulating whole units until the next one would exceed the budget, then
  /// stops — it does not skip an oversized unit and keep looking further back.
  static List<String> _overlapSuffix(List<String> units, int tokenBudget) {
    final result = <String>[];
    var total = 0;
    for (var index = units.length - 1; index >= 0; index--) {
      final tokens = TokenEstimator.estimateTokenCount(units[index]);
      if (total + tokens > tokenBudget) break;
      result.insert(0, units[index]);
      total += tokens;
    }
    return result;
  }

  // -----------------------------------------------------------------------------------------
  // Page tracking (PDF only)
  // -----------------------------------------------------------------------------------------

  static final RegExp _pageMarker = RegExp(r'\[\[page:(\d+)\]\]\n?');

  static (String, List<_PageBoundary>) _stripPageMarkers(String text) {
    if (!text.contains('[[page:')) return (text, const <_PageBoundary>[]);

    final boundaries = <_PageBoundary>[];
    final result = StringBuffer();
    var remaining = text;

    while (true) {
      final match = _pageMarker.firstMatch(remaining);
      if (match == null) break;
      result.write(remaining.substring(0, match.start));
      final page = int.tryParse(match.group(1)!);
      // Offset is recorded *after* appending the prefix, so it points at the first character of
      // the page's own text in the stripped result.
      if (page != null) boundaries.add(_PageBoundary(result.length, page));
      remaining = remaining.substring(match.end);
    }
    result.write(remaining);
    return (result.toString(), boundaries);
  }

  static int? _pageNumberAtOffset(int offset, List<_PageBoundary> boundaries) {
    if (boundaries.isEmpty) return null;
    int? page;
    for (final boundary in boundaries) {
      if (boundary.offset > offset) break; // boundaries are in ascending order
      page = boundary.page;
    }
    // An offset before the first boundary belongs to the first page, not to no page.
    return page ?? boundaries.first.page;
  }
}
