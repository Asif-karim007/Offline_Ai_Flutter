/// Produces a semantic embedding vector for a piece of text.
///
/// Implementations must never throw for "unsupported" cases — unsupported language, unavailable
/// model, empty text. They return null so [HybridRetriever] degrades gracefully to lexical-only
/// scoring rather than failing retrieval entirely. That contract is what makes
/// [NullEmbeddingProvider] a legitimate implementation rather than a stub.
abstract interface class TextEmbeddingProvider {
  Future<List<double>?> embed(String text);
}

/// The provider this port ships with: it always returns null, so every retrieval path runs
/// lexical-only (BM25).
///
/// The Swift app used `NLEmbedding.sentenceEmbedding(for:)` from Apple's `NaturalLanguage`
/// framework. There is no cross-platform equivalent, and `NLEmbedding` itself returns nil for
/// languages and OS versions it does not cover — which is exactly why the protocol is optional
/// and why [HybridRetriever] already has a real, exercised lexical-only path. On those devices
/// the iOS app behaves precisely the way this provider makes the Flutter app behave, so this is
/// a faithful port of an existing code path rather than a placeholder.
///
/// The intended production implementation is a small GGUF embedding model — multilingual-e5-small
/// — loaded as a second model alongside the chat model and reached through the same FFI plugin.
/// It is deliberately not wired up in this pass: it needs a second `llama_context`, its own
/// memory budget on a device already running a chat model, and a decision about whether it ships
/// bundled or is downloaded. Filling this in with plausible-looking numbers instead would be
/// worse than lexical-only, because ranking would then be driven by noise that looks like signal.
///
/// One consequence worth knowing before changing anything downstream: with all-zero semantic
/// scores, [HybridRetriever]'s combined score collapses to `0.30 * normalizedLexical`, so its
/// `0.15` relevance floor demands a normalised lexical score of at least 0.5. In lexical-only
/// mode a chunk must therefore score at least half of the best BM25 score in the candidate set
/// to survive. That is stricter than it looks, and it is the existing iOS behaviour.
class NullEmbeddingProvider implements TextEmbeddingProvider {
  const NullEmbeddingProvider();

  @override
  Future<List<double>?> embed(String text) async => null;
}
