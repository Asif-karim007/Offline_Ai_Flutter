import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/model_management/model_catalog.dart';

/// Guards the catalog's download URLs.
///
/// These matter more than they look: importing a `.gguf` by hand was removed, so a wrong
/// repository, revision or file name here is not a degraded experience — it is a 404 and a
/// device with no way at all to obtain a model. The failure surfaces at download time on a
/// user's phone, never at build time, which is exactly the kind of thing worth pinning.
void main() {
  group('CatalogModel.downloadUrl', () {
    test('is the Hugging Face resolve endpoint for the pinned revision', () {
      expect(
        ModelCatalog.qwen352B.downloadUrl.toString(),
        'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/'
            'Qwen3.5-2B-Q4_K_M.gguf',
      );
    });

    test('every entry produces an https URL ending in its own file name', () {
      for (final model in ModelCatalog.all) {
        final url = model.downloadUrl;
        expect(url.scheme, 'https', reason: model.id);
        expect(url.host, 'huggingface.co', reason: model.id);
        expect(url.pathSegments, contains('resolve'), reason: model.id);
        expect(url.pathSegments.last, model.fileName, reason: model.id);
        expect(url.pathSegments, contains(model.revision), reason: model.id);
      }
    });

    test('respects a non-default revision', () {
      const pinned = CatalogModel(
        id: 'pinned',
        displayName: 'Pinned',
        repository: 'acme/Pinned-GGUF',
        fileName: 'pinned-Q4_K_M.gguf',
        downloadSizeBytes: 1,
        license: 'MIT',
        promptFormat: PromptFormat.chatml,
        tier: ModelTier.recommended,
        minimumDeviceMemoryBytes: 1,
        note: '',
        revision: 'abc123',
      );

      expect(
        pinned.downloadUrl.toString(),
        'https://huggingface.co/acme/Pinned-GGUF/resolve/abc123/pinned-Q4_K_M.gguf',
      );
    });
  });

  group('ModelCatalog', () {
    test('chatModels excludes embedding models and is non-empty', () {
      expect(ModelCatalog.chatModels, isNotEmpty);
      expect(
        ModelCatalog.chatModels.every((model) => !model.isEmbeddingModel),
        isTrue,
      );
    });

    test('the download-only app can still reach its default model', () {
      // If this ever fails, first run has nothing to offer and the app is unusable.
      expect(ModelCatalog.chatModels, contains(ModelCatalog.bundledDefault));
    });

    test('fittingMemory keeps everything when memory is unknown', () {
      expect(ModelCatalog.fittingMemory(null).length, ModelCatalog.all.length);
    });

    test('fittingMemory filters on the model floor', () {
      final fitting = ModelCatalog.fittingMemory(4 * 1024 * 1024 * 1024);
      expect(fitting, contains(ModelCatalog.qwen352B));
      expect(fitting, isNot(contains(ModelCatalog.qwen354B)));
    });
  });
}
