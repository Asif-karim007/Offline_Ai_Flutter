/// One downloadable curriculum pack, as listed in the dataset's `manifest.json`.
///
/// The packs are built by `scripts/curriculum/nctb_pipeline.py` and published at
/// [CurriculumManifest.repository] on Hugging Face. One pack is one stream, class and version —
/// `general_class-9-10_bn` is every class 9–10 Bangla-version textbook — so a student
/// downloads only their own syllabus.
class CurriculumPack {
  const CurriculumPack({
    required this.id,
    required this.fileName,
    required this.stream,
    required this.classKey,
    required this.version,
    required this.bookCount,
    required this.chunkCount,
    required this.sizeBytes,
    required this.sha256,
  });

  factory CurriculumPack.fromJson(Map<String, Object?> json) => CurriculumPack(
        id: json['id']! as String,
        fileName: json['file']! as String,
        stream: json['stream']! as String,
        classKey: json['class']! as String,
        version: json['version']! as String,
        bookCount: (json['books'] as num?)?.toInt() ?? 0,
        chunkCount: (json['chunks'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String?,
      );

  final String id;
  final String fileName;

  /// `general`, `hsc`, `madrasa` or `technical`.
  final String stream;

  /// `class-3`, `class-9-10`, `class-11-12`, …
  final String classKey;

  /// `bn` (Bangla version) or `en` (English version).
  final String version;

  final int bookCount;
  final int chunkCount;
  final int sizeBytes;
  final String? sha256;

  /// The class numbers this pack covers, e.g. `[9, 10]`. Used for ordering and labels.
  List<int> get classNumbers => RegExp(r'\d+')
      .allMatches(classKey)
      .map((match) => int.parse(match.group(0)!))
      .toList(growable: false);

  bool get isBanglaVersion => version == 'bn';

  /// Where the pack file is served from. `resolve` follows LFS pointers and redirects to the
  /// CDN, exactly as model downloads do.
  Uri get downloadUrl => Uri.parse(
      'https://huggingface.co/datasets/${CurriculumManifest.repository}/resolve/main/$fileName');
}

/// The parsed `manifest.json`.
class CurriculumManifest {
  const CurriculumManifest({required this.academicYear, required this.packs});

  factory CurriculumManifest.fromJson(Map<String, Object?> json) {
    final packs = [
      for (final entry in (json['packs'] as List<Object?>? ?? const []))
        if (entry is Map<String, Object?>) CurriculumPack.fromJson(entry),
    ]..sort(_byClassThenVersion);
    return CurriculumManifest(
      academicYear: (json['academic_year'] as num?)?.toInt(),
      packs: packs,
    );
  }

  /// The Hugging Face dataset the packs are published in. Must be public: the app downloads
  /// anonymously and never holds a token.
  static const String repository = 'Asifkarim/nctb-curriculum-packs';

  static final Uri url = Uri.parse(
      'https://huggingface.co/datasets/$repository/resolve/main/manifest.json');

  final int? academicYear;
  final List<CurriculumPack> packs;

  CurriculumPack? byId(String id) {
    for (final pack in packs) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }

  /// Class 1 first, Bangla version before English version within a class.
  static int _byClassThenVersion(CurriculumPack a, CurriculumPack b) {
    final aClass = a.classNumbers.isEmpty ? 99 : a.classNumbers.first;
    final bClass = b.classNumbers.isEmpty ? 99 : b.classNumbers.first;
    if (aClass != bClass) {
      return aClass.compareTo(bClass);
    }
    if (a.stream != b.stream) {
      return a.stream.compareTo(b.stream);
    }
    return a.isBanglaVersion == b.isBanglaVersion ? 0 : (a.isBanglaVersion ? -1 : 1);
  }
}
