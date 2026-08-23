/// A curated list of models the app can download.
///
/// **New in the port.** The Swift app had no catalog: one hardcoded Hugging Face URL in
/// `ModelDownloadViewModel` and one hardcoded bundle resource name in
/// `ModelBootstrapService`, with the size of the download written as a literal in the view
/// so the button label could be formatted. Adding a second model meant editing three files.
///
/// The entries below are the 2026 recommendation for this app: one small default, one
/// mid-size step up, one that is only sensible on 8 GB devices, and an embedding model for
/// the retrieval pipeline.
library;

/// How prominently a model is offered, and to whom.
enum ModelTier {
  /// Shipped as the bundled asset and preselected on first launch.
  bundledDefault('bundled/default'),

  /// The step up most users should take once they know the app works.
  recommended('recommended'),

  /// Offered but gated on device memory.
  max('max'),

  /// Not a chat model. Feeds the retrieval pipeline, never the chat engine.
  embedding('embedding');

  const ModelTier(this.wireValue);

  final String wireValue;
}

/// The prompt format a model's chat template implements.
///
/// Recorded per entry rather than derived, because the engine reads the template out of the
/// GGUF itself and this is only used to tell the user what they are getting — and to make an
/// entry with no chat template at all (an embedding model) obvious at a glance.
enum PromptFormat {
  chatml('ChatML'),

  /// Embedding models have no chat template.
  none('none');

  const PromptFormat(this.label);

  final String label;
}

class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.displayName,
    required this.repository,
    required this.fileName,
    required this.downloadSizeBytes,
    required this.license,
    required this.promptFormat,
    required this.tier,
    required this.minimumDeviceMemoryBytes,
    required this.note,
    this.contextLength,
    this.revision = defaultRevision,
    this.isEmbeddingModel = false,
    this.embeddingDimensions,
  });

  /// Stable identifier for settings and analytics. Not the file name, so a repository that
  /// re-quantises and renames a file does not orphan a user's selection.
  final String id;

  final String displayName;

  /// Hugging Face `owner/repo`.
  final String repository;

  /// The exact file inside the repository. GGUF repositories hold several quantisations of
  /// the same weights, and this names the one this entry means.
  final String fileName;

  /// Git revision to resolve the file at.
  ///
  /// Defaults to [defaultRevision] — the branch tip. **A real ship should pin a commit SHA
  /// here.** `main` moves: a repository owner can re-upload a file under the same name, and
  /// the download would then silently deliver different weights than the size, quantisation
  /// and benchmark figures recorded in this file describe. A SHA also makes the URL
  /// cacheable and lets a mismatch be detected instead of absorbed.
  final String revision;

  /// Bytes over the wire, decimal (matching what Hugging Face's file listing shows and what
  /// `FileSizeFormatter` renders), except where the source quotes mebibytes.
  final int downloadSizeBytes;

  final String license;
  final PromptFormat promptFormat;

  /// Trained context length from the model card. `null` for models where it does not apply.
  final int? contextLength;

  final ModelTier tier;

  /// The device RAM below which this model should not be offered.
  ///
  /// Weights are only part of the requirement — the KV cache for a long context can exceed
  /// the weights themselves — so these are set above the file size with room for the cache,
  /// the Flutter engine and whatever else the OS is holding.
  final int minimumDeviceMemoryBytes;

  /// One line of why this entry is in the list. Shown in the picker.
  final String note;

  /// Embedding models produce vectors, not text. The chat engine must never be pointed at
  /// one: it has no chat template, and loading it as a chat model fails at
  /// `missingChatTemplate` after a full load.
  final bool isEmbeddingModel;

  /// Output vector width, for embedding models only. The retrieval index is built against
  /// this and cannot be reused across models with different dimensions.
  final int? embeddingDimensions;

  /// The default branch. See [revision].
  static const String defaultRevision = 'main';

  /// Hugging Face's resolve endpoint. `resolve` follows LFS pointers and redirects to the
  /// CDN, which is what makes a plain streaming GET work for a multi-gigabyte file.
  Uri get downloadUrl =>
      Uri.parse('https://huggingface.co/$repository/resolve/$revision/$fileName');

  /// Whether this model fits in [availableMemoryBytes].
  ///
  /// `null` means the platform could not report its memory (see `MemoryReporter`), and the
  /// answer is then `true`: refusing to show any model because the RAM figure is unavailable
  /// would be worse than letting a user try one that might not load.
  bool fitsInMemory(int? availableMemoryBytes) =>
      availableMemoryBytes == null || availableMemoryBytes >= minimumDeviceMemoryBytes;
}

abstract final class ModelCatalog {
  static const int _gibibyte = 1024 * 1024 * 1024;
  static const int _mebibyte = 1024 * 1024;
  static const int _megabyte = 1000 * 1000;

  static const CatalogModel qwen35Point8B = CatalogModel(
    id: 'qwen3.5-0.8b-q4_k_m',
    displayName: 'Qwen3.5-0.8B-Q4_K_M',
    repository: 'unsloth/Qwen3.5-0.8B-GGUF',
    fileName: 'Qwen3.5-0.8B-Q4_K_M.gguf',
    downloadSizeBytes: 533 * _megabyte,
    license: 'Apache-2.0',
    promptFormat: PromptFormat.chatml,
    contextLength: 262144,
    tier: ModelTier.bundledDefault,
    minimumDeviceMemoryBytes: 3 * _gibibyte,
    note: 'Recommended starting point. 201 languages including Bengali.',
  );

  static const CatalogModel qwen352B = CatalogModel(
    id: 'qwen3.5-2b-q4_k_m',
    displayName: 'Qwen3.5-2B-Q4_K_M',
    repository: 'unsloth/Qwen3.5-2B-GGUF',
    fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
    downloadSizeBytes: 1280 * _megabyte,
    license: 'Apache-2.0',
    promptFormat: PromptFormat.chatml,
    contextLength: 262144,
    tier: ModelTier.recommended,
    minimumDeviceMemoryBytes: 4 * _gibibyte,
    note: 'Measured 39 tok/s at 1.48 GB peak on A19 Pro.',
  );

  static const CatalogModel qwen354B = CatalogModel(
    id: 'qwen3.5-4b-q4_k_m',
    displayName: 'Qwen3.5-4B-Q4_K_M',
    repository: 'unsloth/Qwen3.5-4B-GGUF',
    fileName: 'Qwen3.5-4B-Q4_K_M.gguf',
    downloadSizeBytes: 2740 * _megabyte,
    license: 'Apache-2.0',
    promptFormat: PromptFormat.chatml,
    contextLength: 262144,
    tier: ModelTier.max,
    // The 8 GB requirement is the model card's, not an inference from the file size.
    minimumDeviceMemoryBytes: 8 * _gibibyte,
    note: 'Weights alone are 2.74 GB before KV cache.',
  );

  /// The retrieval-side embedding model.
  ///
  /// The file name is the conventional `<model>-<quant>.gguf` form for this repository.
  /// Unlike the Qwen entries, whose naming is fixed by Unsloth's publishing convention, this
  /// one is worth confirming against the repository's file listing before shipping — a
  /// wrong name here surfaces as a 404 at download time, not at build time.
  static const CatalogModel multilingualE5Small = CatalogModel(
    id: 'multilingual-e5-small-q8_0',
    displayName: 'multilingual-e5-small Q8_0',
    repository: 'cstr/multilingual-e5-small-GGUF',
    fileName: 'multilingual-e5-small-Q8_0.gguf',
    downloadSizeBytes: 126 * _mebibyte,
    license: 'MIT',
    promptFormat: PromptFormat.none,
    tier: ModelTier.embedding,
    minimumDeviceMemoryBytes: 2 * _gibibyte,
    note: 'Embedding model for hybrid retrieval. Not usable for chat.',
    isEmbeddingModel: true,
    embeddingDimensions: 384,
  );

  /// Every entry, in the order they should be presented.
  static const List<CatalogModel> all = [
    qwen35Point8B,
    qwen352B,
    qwen354B,
    multilingualE5Small,
  ];

  /// The model the bundled asset and first-launch selection refer to.
  static const CatalogModel bundledDefault = qwen35Point8B;

  /// Chat models only — everything the model picker may offer as a conversational model.
  static List<CatalogModel> get chatModels =>
      all.where((model) => !model.isEmbeddingModel).toList(growable: false);

  static List<CatalogModel> get embeddingModels =>
      all.where((model) => model.isEmbeddingModel).toList(growable: false);

  /// The catalog filtered to what this device can be expected to run.
  ///
  /// Pass `MemoryReporter.availablePhysicalMemoryBytes()` — or
  /// `totalPhysicalMemoryBytes()` when offering a model to download for later rather than to
  /// load right now. A `null` figure disables filtering entirely rather than emptying the
  /// list; see [CatalogModel.fitsInMemory].
  static List<CatalogModel> fittingMemory(int? availableMemoryBytes) => all
      .where((model) => model.fitsInMemory(availableMemoryBytes))
      .toList(growable: false);

  static CatalogModel? byId(String id) {
    for (final model in all) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }

  static CatalogModel? byFileName(String fileName) {
    for (final model in all) {
      if (model.fileName == fileName) {
        return model;
      }
    }
    return null;
  }
}
