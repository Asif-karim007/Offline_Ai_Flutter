import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/local_model_info.dart';
import '../llm/llama_error.dart';
import '../utilities/logger.dart';
import 'model_store.dart';

/// Validates a user-picked GGUF file and copies it into the managed models directory.
///
/// The model is never loaded from the picker's own path. On iOS `file_picker` hands back a
/// path inside the app's temporary directory that the system is free to reclaim; on Android
/// it can be a cache copy of a `content://` stream. Either way it is not a stable location
/// for a file the engine will `mmap` for the lifetime of the app — hence the copy, which is
/// the same reason the Swift version refused to run from the security-scoped URL.
///
/// Security-scoped resource access (`startAccessingSecurityScopedResource`) has no Flutter
/// analogue and is not needed: `file_picker` has already copied the file out of the
/// provider's sandbox by the time a path is returned. The existence, readability and
/// size checks it bracketed are all kept.
class ModelImporter {
  const ModelImporter(this.modelStore);

  final ModelStore modelStore;

  /// Copies [pickedPath] into the store and returns the installed model.
  ///
  /// Validation order matches the original exactly, because the order determines which error
  /// the user sees for a file that fails more than one check.
  Future<LocalModelInfo> importModel(String pickedPath) async {
    final fileName = p.basename(pickedPath);

    if (p.extension(pickedPath).toLowerCase() != '.gguf') {
      throw LlamaError.invalidFileExtension(fileName);
    }

    final source = File(pickedPath);
    if (!await source.exists()) {
      throw LlamaError.modelFileMissing(pickedPath);
    }

    // `dart:io` has no `isReadableFile`. Opening the file for reading and closing it again
    // asks the same question of the filesystem and answers it authoritatively, rather than
    // inferring readability from a permissions bit that says nothing about sandboxing or a
    // revoked provider grant.
    try {
      final handle = await source.open();
      await handle.close();
    } on FileSystemException {
      throw LlamaError.fileAccessDenied(pickedPath);
    }

    final sourceSize = await source.length();
    if (sourceSize <= 0) {
      // A zero-byte file is reported as missing, not as an invalid model: it is what a
      // failed or interrupted export from another app leaves behind, and "the file could not
      // be found" describes that better than "unsupported format" would.
      throw LlamaError.modelFileMissing(pickedPath);
    }

    // The picked name is preserved verbatim — no renaming, no uniquifying. Importing a file
    // whose name matches an installed model replaces it, which is what a user re-importing a
    // corrupted download expects.
    final destination =
        await modelStore.copyModel(source: source, fileName: fileName);

    // Re-stat rather than trusting the source size: a copy that was truncated by a full disk
    // must not be recorded at its intended size.
    final copiedSize = await destination.length();

    AppLog.model('model.imported', fields: [
      LogField.bytes('size', copiedSize),
      LogField.flag('sizeMatchedSource', copiedSize == sourceSize),
    ]);

    return LocalModelInfo(
      fileName: fileName,
      fileSizeBytes: copiedSize,
      importedAt: DateTime.now(),
    );
  }

  /// The extension filter to hand `FilePicker.platform.pickFiles`.
  ///
  /// GGUF has no registered UTI or MIME type, which is why the Swift app built a dynamic
  /// `UTType` from the extension and why iOS widens it to `public.data` in practice. The
  /// picker filter is therefore advisory only, and [importModel] re-checks the extension —
  /// that second check is the one that actually holds.
  static const List<String> allowedExtensions = ['gguf'];
}
