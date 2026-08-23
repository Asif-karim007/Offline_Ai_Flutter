import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../agent_id.dart';
import 'document_text_extractor.dart';
import 'extracted_document.dart';

/// Text-layer extraction for PDFs.
///
/// Swift used PDFKit (`PDFDocument` + `page.string`); this uses `pdfrx`, which is PDFium-backed
/// and behaves the same way for the one thing this needs: reading an existing text layer. If a
/// PDF has no extractable text — a scan with no text layer — this throws
/// [DocumentExtractionErrorKind.noExtractableText] rather than guessing. OCR is intentionally
/// out of scope and would need to be a deliberate, separate feature, not a silent fallback that
/// makes a scanned document look like it was read successfully.
///
/// `pdfrx` needs its one-time platform initialisation to have run before this is called; that
/// belongs in the app's `main()`, not here.
class PdfTextExtractor implements DocumentTextExtractor {
  const PdfTextExtractor();

  @override
  bool canHandle(Uri uri) {
    final extension = p.extension(uri.path);
    return extension.isNotEmpty && extension.substring(1).toLowerCase() == 'pdf';
  }

  @override
  Future<ExtractedDocument> extract(Uri uri) async {
    final path = uri.toFilePath();
    final fileName = p.basename(path);

    PdfDocument document;
    try {
      document = await PdfDocument.openFile(path);
    } catch (_) {
      // PDFKit signalled the same condition by returning nil from its initialiser.
      throw DocumentExtractionError.unsupportedFormat(fileName);
    }

    try {
      final pageTexts = <String>[];
      final pageCount = document.pages.length;
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        String pageText;
        try {
          pageText = (await document.pages[pageIndex].loadText()).fullText;
        } catch (_) {
          continue;
        }
        if (pageText.trim().isEmpty) continue;
        // These markers are an in-band protocol consumed by `DocumentChunker.stripPageMarkers`:
        // it is how a chunk acquires a page number without threading a parallel structure
        // through chunking. The format is load-bearing — do not reformat it.
        pageTexts.add('[[page:${pageIndex + 1}]]\n$pageText');
      }

      if (pageTexts.isEmpty) {
        throw const DocumentExtractionError.noExtractableText();
      }

      return ExtractedDocument(
        id: newAgentId(),
        name: fileName,
        sourceUri: uri,
        text: pageTexts.join('\n\n'),
        metadata: {'pageCount': '$pageCount'},
      );
    } finally {
      await document.dispose();
    }
  }
}
