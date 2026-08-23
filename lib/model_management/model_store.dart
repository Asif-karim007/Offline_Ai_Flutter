import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/local_model_info.dart';
import '../llm/llama_error.dart';

/// Why a [ModelStore] operation failed.
///
/// Ported from the nested `ModelStore.StoreError`. Its user-facing text is deliberately the
/// same text `LlamaError` already publishes for the equivalent conditions — a copy that runs
/// out of space should read identically to the user whether it was the importer, the
/// bootstrap copy or the downloader that hit it.
enum ModelStoreErrorKind {
  insufficientStorage,
  copyFailed,

  /// Not present in the Swift original. See [ModelStore.pathForFileName].
  unsafeFileName,
}

class ModelStoreException implements Exception {
  const ModelStoreException(this.kind, {this.detail});

  final ModelStoreErrorKind kind;
  final String? detail;

  String get errorDescription => switch (kind) {
        ModelStoreErrorKind.insufficientStorage =>
          const LlamaError.insufficientStorage().errorDescription,
        ModelStoreErrorKind.copyFailed =>
          const LlamaError.modelCopyFailed('').errorDescription,
        ModelStoreErrorKind.unsafeFileName =>
          const LlamaError.modelCopyFailed('').errorDescription,
      };

  @override
  String toString() => 'ModelStoreException.${kind.name}($detail)';
}

/// Owns the on-disk `Models` directory where every installed GGUF file lives, however it
/// arrived — bundled asset or download. (Hand-importing a `.gguf` was removed; downloading
/// from the catalog is the only route a user has.)
class ModelStore {
  const ModelStore(this.modelsDirectory);

  /// The directory itself, not its path, so tests can point at a temporary one.
  final Directory modelsDirectory;

  /// Resolves `<application support>/Models`.
  ///
  /// On iOS this is the same `Library/Application Support/Models` the Swift app used, so an
  /// app updated in place finds its existing models. On Android it resolves to the app's
  /// private files directory, which is the correct analogue: not user-visible, not scanned
  /// by the media store, removed when the app is uninstalled.
  static Future<ModelStore> open() async {
    final support = await getApplicationSupportDirectory();
    return ModelStore(Directory(p.join(support.path, 'Models')));
  }

  Future<void> ensureDirectoryExists() async {
    if (!await modelsDirectory.exists()) {
      await modelsDirectory.create(recursive: true);
    }
  }

  /// The absolute path a model with this file name would occupy.
  ///
  /// **Hardened relative to the Swift original**, which appended the caller's string to the
  /// directory URL with no validation at all: a file name containing `../` escaped the
  /// models directory entirely, and the name comes from a user-picked file. Anything that is
  /// not a plain file name is rejected here rather than sanitised, because silently
  /// rewriting a name would make the imported file's identity differ from what the user saw
  /// in the picker.
  String pathForFileName(String fileName) {
    _requireSafeFileName(fileName);
    return p.join(modelsDirectory.path, fileName);
  }

  File fileForFileName(String fileName) => File(pathForFileName(fileName));

  Future<bool> modelExists(String fileName) {
    return File(pathForFileName(fileName)).exists();
  }

  /// Every installed `.gguf` file, newest first.
  ///
  /// "Newest" is the file's modification time, which is what a fresh copy or download sets,
  /// so it stands in for an import date without a separate index to keep in sync. The
  /// metadata fields of [LocalModelInfo] are left null: reading them means a vocab-only
  /// load per file, and this runs on every appearance of the model list.
  Future<List<LocalModelInfo>> installedModels() async {
    await ensureDirectoryExists();

    final entries = await modelsDirectory.list(followLinks: false).toList();
    final models = <LocalModelInfo>[];

    for (final entry in entries) {
      if (entry is! File) {
        continue;
      }
      final name = p.basename(entry.path);
      // `contentsOfDirectory(options: .skipsHiddenFiles)` had no Dart equivalent; dot-files
      // are filtered explicitly. Partial downloads end in `.part` and fail the extension
      // check below, so they never show up as installed models.
      if (name.startsWith('.')) {
        continue;
      }
      if (p.extension(name).toLowerCase() != '.gguf') {
        continue;
      }

      final stat = await entry.stat();
      models.add(LocalModelInfo(
        fileName: name,
        fileSizeBytes: stat.size,
        importedAt: stat.modified,
      ));
    }

    models.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return models;
  }

  Future<void> deleteModel(String fileName) async {
    final target = File(pathForFileName(fileName));
    if (!await target.exists()) {
      return;
    }
    await target.delete();
  }

  /// The honest counterpart of the Swift `isExcludedFromBackup` resource value.
  ///
  /// **This is not parity, and the difference is worth stating plainly.** The Swift version
  /// set `URLResourceValues.isExcludedFromBackup` on each copied file, which tells iOS to
  /// skip that specific file in iCloud and iTunes backups. Flutter exposes no such API, and
  /// implementing it means a platform channel calling
  /// `NSURL setResourceValue:forKey:NSURLIsExcludedFromBackupKey` — native code this port
  /// does not ship.
  ///
  /// What the port relies on instead is placement: the models directory lives under
  /// Application Support, and Apple's guidance is that files there *are* backed up unless
  /// excluded. So this is genuinely weaker than the original, not equivalent. A model file
  /// of several hundred megabytes to a few gigabytes, trivially re-downloadable from Hugging
  /// Face, is exactly the payload App Review flags under the iOS Data Storage Guidelines.
  ///
  /// **Before shipping on iOS, add the platform channel.** This method is the single seam it
  /// plugs into: every path that puts a file into the models directory — copy, import,
  /// download, bundled-asset bootstrap — calls it, which also closes the Swift app's own gap
  /// where downloaded models bypassed the import path and were never excluded at all.
  Future<void> excludeFromDeviceBackup(File file) async {
    // Deliberately a no-op rather than a throw: the file is already correctly placed, and
    // failing an import over a backup attribute would be worse than the backup.
  }

  static void _requireSafeFileName(String fileName) {
    final isPlainName = fileName.isNotEmpty &&
        fileName != '.' &&
        fileName != '..' &&
        !fileName.contains('/') &&
        !fileName.contains(r'\') &&
        p.basename(fileName) == fileName;
    if (!isPlainName) {
      throw ModelStoreException(
        ModelStoreErrorKind.unsafeFileName,
        detail: fileName,
      );
    }
  }
}
