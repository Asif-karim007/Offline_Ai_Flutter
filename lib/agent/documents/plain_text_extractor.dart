import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent_id.dart';
import 'document_text_extractor.dart';
import 'extracted_document.dart';

/// Extracts .txt/.md/.json/.csv and common source-code/text files by reading them as UTF-8,
/// falling back to Latin-1 for files that are not valid UTF-8. No parsing beyond decoding —
/// structure (headings, paragraphs) is handled later by [DocumentChunker].
class PlainTextExtractor implements DocumentTextExtractor {
  const PlainTextExtractor();

  static const Set<String> supportedExtensions = {
    'txt', 'md', 'markdown', 'json', 'csv', 'swift', 'py', 'js', 'ts', 'java', 'c', 'cpp',
    'h', 'hpp', 'rb', 'go', 'rs', 'html', 'css', 'yaml', 'yml', 'xml', 'log',
  };

  @override
  bool canHandle(Uri uri) => supportedExtensions.contains(_extension(uri));

  @override
  Future<ExtractedDocument> extract(Uri uri) async {
    final path = uri.toFilePath();
    final bytes = await File(path).readAsBytes();

    // Swift's `String(data:encoding:.utf8)` is strict and returns nil on malformed bytes; the
    // `allowMalformed: false` default matches that, so the Latin-1 fallback fires in the same
    // cases rather than silently producing replacement characters.
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      try {
        text = latin1.decode(bytes);
      } on FormatException {
        text = '';
      }
    }

    return ExtractedDocument(
      id: newAgentId(),
      name: p.basename(path),
      sourceUri: uri,
      text: text,
      metadata: const {},
    );
  }

  /// `p.extension` returns the leading dot; Swift's `pathExtension` does not.
  static String _extension(Uri uri) {
    final extension = p.extension(uri.path);
    if (extension.isEmpty) return '';
    return extension.substring(1).toLowerCase();
  }
}
