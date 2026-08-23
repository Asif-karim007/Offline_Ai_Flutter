import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'document_chunk.dart';
import 'document_chunker.dart';
import 'document_index.dart';
import 'document_retriever.dart';
import 'document_text_extractor.dart';
import 'local_document_reference.dart';
import 'pdf_text_extractor.dart';
import 'plain_text_extractor.dart';

/// One file the user has attached to the active session.
class AttachedDocument {
  const AttachedDocument({
    required this.id,
    required this.displayName,
    required this.sourceUri,
  });

  final String id;
  final String displayName;
  final Uri sourceUri;

  @override
  bool operator ==(Object other) =>
      other is AttachedDocument &&
      other.id == id &&
      other.displayName == displayName &&
      other.sourceUri == sourceUri;

  @override
  int get hashCode => Object.hash(id, displayName, sourceUri);
}

/// Owns the active session's user-attached documents: import, extraction, chunking, indexing,
/// and removal.
///
/// Import is via the standard file picker only — never a folder scan or arbitrary-storage
/// walk. iOS needed `startAccessingSecurityScopedResource()` around extraction for picked
/// files; `file_picker` copies the picked file into the app's own sandbox before handing back a
/// path, so there is no security-scoped bookmark to open here and the ceremony drops out.
/// Cleaning up those cached copies belongs to whatever drove the picker.
///
/// Swift made this an `actor`. Here [addDocument], [removeDocument] and [clearSession] run
/// through a serial queue instead: each awaits extraction or indexing, and letting a
/// `clearSession()` land between an import's extraction and its append would leave a chunk in
/// the index belonging to a document the user believes they removed.
class LocalDocumentManager {
  LocalDocumentManager({
    List<DocumentTextExtractor>? extractors,
    DocumentChunker chunker = const DocumentChunker(),
    DocumentIndex? index,
    DocumentRetriever? retriever,
  })  :
        // Order matters: the PDF extractor is asked first, so a `.pdf` never falls through to
        // the plain-text reader that would happily hand back binary noise.
        _extractors = extractors ?? const [PdfTextExtractor(), PlainTextExtractor()],
        _chunker = chunker,
        _index = index ?? DocumentIndex(),
        _retriever = retriever ?? DocumentRetriever();

  final List<DocumentTextExtractor> _extractors;
  final DocumentChunker _chunker;
  final DocumentIndex _index;
  final DocumentRetriever _retriever;

  final List<AttachedDocument> _attachedDocuments = [];

  Future<void> _queue = Future<void>.value();

  List<AttachedDocument> get attachedDocuments => List.unmodifiable(_attachedDocuments);

  List<LocalDocumentReference> get references => _attachedDocuments
      .map((document) =>
          LocalDocumentReference(id: document.id, displayName: document.displayName))
      .toList();

  bool get isEmpty => _attachedDocuments.isEmpty;

  Future<AttachedDocument> addDocument(Uri pickedUri) {
    return _serial(() async {
      final fileName = p.basename(pickedUri.toFilePath());

      DocumentTextExtractor? extractor;
      for (final candidate in _extractors) {
        if (candidate.canHandle(pickedUri)) {
          extractor = candidate;
          break;
        }
      }
      if (extractor == null) {
        throw DocumentExtractionError.unsupportedFormat(fileName);
      }

      final file = File(pickedUri.toFilePath());
      if (!await file.exists()) {
        throw const DocumentExtractionError.fileAccessDenied();
      }

      final extracted = await extractor.extract(pickedUri);
      final chunks = _chunker.chunk(extracted);
      await _index.add(chunks);

      final document = AttachedDocument(
        id: extracted.id,
        displayName: extracted.name,
        sourceUri: pickedUri,
      );
      _attachedDocuments.add(document);
      return document;
    });
  }

  Future<void> removeDocument(String id) {
    return _serialVoid(() async {
      _attachedDocuments.removeWhere((document) => document.id == id);
      _index.remove(documentId: id);
    });
  }

  Future<void> clearSession() {
    return _serialVoid(() async {
      _attachedDocuments.clear();
      _index.clear();
    });
  }

  /// Not serialised: retrieval only reads, and the read it performs is a synchronous snapshot of
  /// the chunk list taken before it awaits anything.
  Future<List<DocumentChunk>> retrieveRelevantChunks(String query, {int limit = 6}) {
    return _retriever.retrieve(query: query, index: _index, limit: limit);
  }

  /// Chains each mutating operation onto the previous one so their `await` points cannot
  /// interleave. A failure is routed to the caller's own future rather than escaping into the
  /// chain, because an error propagating along `_queue` would break every operation queued
  /// behind it.
  Future<T> _serial<T extends Object>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queue = _queue.then<void>((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// The result-free twin of [_serial]. Kept separate rather than instantiating the generic at
  /// `void`, which would mean handing a void-typed expression to `Completer.complete`.
  Future<void> _serialVoid(Future<void> Function() operation) {
    final completer = Completer<void>();
    _queue = _queue.then<void>((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
