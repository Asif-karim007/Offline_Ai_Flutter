import '../agent/documents/document_text_extractor.dart';
import '../llm/llama_error.dart';
import '../model_management/model_downloader.dart';
import '../model_management/model_store.dart';
import '../persistence/conversation_repository.dart';

/// The Dart stand-in for Swift's `error.localizedDescription`.
///
/// Every Swift error the view models caught conformed to `LocalizedError`, so
/// `localizedDescription` returned the app's own hand-written sentence rather than a debug
/// dump. Dart has no such protocol: `Object.toString()` on an exception is a developer string
/// (`LlamaError(modelLoadFailed, ...)`), and putting that in an error banner would leak
/// implementation detail into the UI.
///
/// This function is the one place that mapping lives. Every error type the already-written
/// layers throw publishes a user-facing `errorDescription`; they are enumerated here so that
/// adding a new one is a compile-time-visible omission rather than a silently ugly banner.
String describeError(Object error) {
  if (error is LlamaError) {
    return error.errorDescription;
  }
  if (error is ModelStoreException) {
    return error.errorDescription;
  }
  if (error is DocumentExtractionError) {
    return error.errorDescription;
  }
  if (error is ModelDownloadException) {
    return error.errorDescription;
  }
  if (error is RepositoryException) {
    // The repository's only typed failure is "the parent conversation is gone", which from
    // the user's side is indistinguishable from any other failed write. Reusing the existing
    // save-failure sentence keeps the app from inventing a second phrasing for it.
    return const LlamaError.databaseSaveFailed('').errorDescription;
  }
  return error.toString();
}
