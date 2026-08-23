import '../retrieval/hybrid_retriever.dart';
import 'document_chunk.dart';
import 'document_index.dart';

/// Top-k hybrid retrieval over the session's [DocumentIndex], with a relevance floor (via
/// [HybridRetriever]) so irrelevant chunks are never padded in just to reach a fixed count.
/// Fewer than [limit] chunks — or none at all — is a normal outcome, not a failure.
class DocumentRetriever {
  DocumentRetriever({HybridRetriever? retriever})
      : _retriever = retriever ?? HybridRetriever();

  final HybridRetriever _retriever;

  Future<List<DocumentChunk>> retrieve({
    required String query,
    required DocumentIndex index,
    int limit = 6,
  }) async {
    final chunks = index.chunks;
    if (chunks.isEmpty) return const [];
    final embeddings = index.precomputedEmbeddings(chunks);
    final ranked = await _retriever.rank<DocumentChunk>(
      query: query,
      items: chunks,
      limit: limit,
      precomputedEmbeddings: embeddings,
      text: (chunk) => chunk.text,
    );
    return ranked.map((scored) => scored.item).toList();
  }
}
