import '../agent_id.dart';
import '../documents/document_chunk.dart';
import '../documents/document_chunker.dart';
import '../documents/extracted_document.dart';
import '../retrieval/hybrid_retriever.dart';
import 'retrieved_web_chunk.dart';
import 'web_content_extractor.dart';
import 'web_page_fetcher.dart';
import 'web_search_provider.dart';
import 'web_search_result.dart';

/// Ties search → page fetch → readable-text extraction → local relevance ranking into the small
/// set of excerpts actually handed to the local model.
///
/// The search provider and the fetched pages are the *only* things in the whole app that touch
/// the network. Everything after extraction is local computation, and only the minimised query
/// string this type receives ever leaves the device — never the conversation, never document
/// contents.
class WebSearchService {
  WebSearchService({
    required WebSearchProvider provider,
    WebPageFetching? fetcher,
    DocumentChunker chunker = const DocumentChunker(),
    HybridRetriever? retriever,
  })  : _provider = provider,
        _fetcher = fetcher ?? WebPageFetcher(),
        // The same chunker and the same parameters local documents use, so evidence from a web
        // page and evidence from a PDF arrive at the model in the same shape.
        _chunker = chunker,
        _retriever = retriever ?? HybridRetriever();

  final WebSearchProvider _provider;
  final WebPageFetching _fetcher;
  final DocumentChunker _chunker;
  final HybridRetriever _retriever;

  static const int maxResultsToConsider = 5;
  static const int maxExcerptsPerPage = 2;

  /// Throws whatever the provider throws — the orchestrator catches and swallows it there, and
  /// logs the kind. Per-*page* failures are swallowed here instead, so one dead link does not
  /// cost the whole batch.
  Future<List<RetrievedWebChunk>> searchAndFetch(String query) async {
    final results =
        await _provider.search(query: query, maxResults: maxResultsToConsider);
    if (results.isEmpty) return const [];

    final deduped = _dedupedByDomain(_rankedByDomainAuthority(results));
    // One timestamp for the whole batch, so every chunk from one search agrees on when it was
    // retrieved.
    final retrievedAt = DateTime.now();

    final chunks = <RetrievedWebChunk>[];
    // Sequential, not concurrent. Fetching five pages at once on a phone that is about to run a
    // local model competes for exactly the memory and CPU the generation needs.
    for (final result in deduped) {
      List<String> excerpts;
      try {
        excerpts = await _excerpts(result, query);
      } catch (_) {
        excerpts = const [];
      }
      for (final excerpt in excerpts) {
        chunks.add(RetrievedWebChunk(
          id: newAgentId(),
          sourceId: result.id,
          title: result.title,
          url: result.url,
          text: excerpt,
          publishedDate: result.publishedDate,
          retrievedAt: retrievedAt,
        ));
      }
    }
    return chunks;
  }

  Future<List<String>> _excerpts(WebSearchResult result, String query) async {
    final html = await _fetcher.fetch(result.url);
    final readableText = WebContentExtractor.extractReadableText(html);
    if (readableText.isEmpty) {
      return result.snippet.isEmpty ? const [] : [result.snippet];
    }

    final document = ExtractedDocument(
      id: newAgentId(),
      name: result.title,
      sourceUri: result.url,
      text: readableText,
      metadata: const {},
    );
    final pageChunks = _chunker.chunk(document);
    if (pageChunks.isEmpty) {
      return result.snippet.isEmpty ? const [] : [result.snippet];
    }

    final ranked = await _retriever.rank<DocumentChunk>(
      query: query,
      items: pageChunks,
      limit: maxExcerptsPerPage,
      text: (chunk) => chunk.text,
    );
    final selected = ranked.map((scored) => scored.item.text).toList();
    // The relevance floor can drop everything on a page whose chunks all score alike; falling
    // back to the first chunk beats returning a fetched page with nothing to show for it.
    return selected.isEmpty ? [pageChunks.first.text] : selected;
  }

  /// Lightweight authority boost for well-known official documentation and vendor domains — a
  /// version question should prefer python.org over an SEO blog when both appear. Not a hard
  /// filter: nothing is excluded, results are only re-ordered so authoritative sources win the
  /// per-domain dedup below.
  static const Set<String> authoritativeDomains = {
    'python.org', 'docs.python.org', 'swift.org', 'docs.swift.org',
    'developer.apple.com', 'apple.com', 'support.apple.com',
    'github.com', 'developer.mozilla.org', 'learn.microsoft.com',
    'huggingface.co', 'qwenlm.github.io', 'qwen.ai',
  };

  static bool _isAuthoritative(Uri url) {
    final host = url.host.toLowerCase();
    if (host.isEmpty) return false;
    return authoritativeDomains
        .any((domain) => host == domain || host.endsWith('.$domain'));
  }

  /// A stable partition rather than a `sort`. Swift wrote this as
  /// `sorted { isAuthoritative($0) && !isAuthoritative($1) }`, which is not a strict weak
  /// ordering and whose result depends on the sort implementation; the partition is the
  /// behaviour that predicate was reaching for, and it is deterministic.
  static List<WebSearchResult> _rankedByDomainAuthority(List<WebSearchResult> results) {
    final authoritative = <WebSearchResult>[];
    final rest = <WebSearchResult>[];
    for (final result in results) {
      (_isAuthoritative(result.url) ? authoritative : rest).add(result);
    }
    return [...authoritative, ...rest];
  }

  static List<WebSearchResult> _dedupedByDomain(List<WebSearchResult> results) {
    final seenHosts = <String>{};
    final deduped = <WebSearchResult>[];
    for (final result in results) {
      final host = result.url.host.isEmpty ? result.url.toString() : result.url.host;
      if (!seenHosts.add(host)) continue;
      deduped.add(result);
    }
    return deduped;
  }
}
