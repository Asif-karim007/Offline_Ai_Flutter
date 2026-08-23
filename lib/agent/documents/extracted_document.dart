/// The full plain text of one attached file, before chunking.
class ExtractedDocument {
  const ExtractedDocument({
    required this.id,
    required this.name,
    required this.sourceUri,
    required this.text,
    required this.metadata,
  });

  final String id;
  final String name;
  final Uri sourceUri;
  final String text;
  final Map<String, String> metadata;

  @override
  bool operator ==(Object other) {
    if (other is! ExtractedDocument) return false;
    if (other.id != id ||
        other.name != name ||
        other.sourceUri != sourceUri ||
        other.text != text ||
        other.metadata.length != metadata.length) {
      return false;
    }
    for (final entry in metadata.entries) {
      if (other.metadata[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, name, sourceUri, text, metadata.length);
}
