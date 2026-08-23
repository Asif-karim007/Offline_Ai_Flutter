import '../retrieval/text_embedding_provider.dart';
import 'document_chunk.dart';

/// In-memory, session-only store of chunks plus their cached embeddings for every currently
/// attached document.
///
/// No persistent vector database: at the scale of a handful of user-attached documents per
/// session, a linear list with per-chunk embeddings computed once at index time (never per
/// query) is sufficient, and it means nothing about an attached document survives the session.
///
/// Swift made this an `actor`. Dart's event loop already serialises the synchronous parts, and
/// the one `await` inside [add] is harmless to interleave: chunks are appended synchronously
/// before it, and embeddings are keyed by chunk id, so two concurrent [add] calls cannot corrupt
/// each other's state. No lock is needed here.
class DocumentIndex {
  DocumentIndex({TextEmbeddingProvider embeddingProvider = const NullEmbeddingProvider()})
      : _embeddingProvider = embeddingProvider;

  final TextEmbeddingProvider _embeddingProvider;

  final List<DocumentChunk> _chunks = [];
  final Map<String, List<double>?> _embeddings = {};

  List<DocumentChunk> get chunks => List.unmodifiable(_chunks);

  bool get isEmpty => _chunks.isEmpty;

  Future<void> add(List<DocumentChunk> newChunks) async {
    _chunks.addAll(newChunks);
    for (final chunk in newChunks) {
      _embeddings[chunk.id] = await _embeddingProvider.embed(chunk.text);
    }
  }

  void remove({required String documentId}) {
    final removedIds = _chunks
        .where((chunk) => chunk.documentId == documentId)
        .map((chunk) => chunk.id)
        .toList();
    _chunks.removeWhere((chunk) => chunk.documentId == documentId);
    for (final id in removedIds) {
      _embeddings.remove(id);
    }
  }

  void clear() {
    _chunks.clear();
    _embeddings.clear();
  }

  /// Embeddings for [chunks], in the same order. Entries are null for chunks whose embedding
  /// was never produced, which is every chunk while [NullEmbeddingProvider] is in use.
  List<List<double>?> precomputedEmbeddings(List<DocumentChunk> chunks) =>
      chunks.map((chunk) => _embeddings[chunk.id]).toList();
}
