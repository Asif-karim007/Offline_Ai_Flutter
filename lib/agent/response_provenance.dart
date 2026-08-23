import 'source_reference.dart';

/// The icon half of the provenance badge.
///
/// Swift stored an SF Symbol name (`doc.text` / `network` / `iphone`) directly on the struct.
/// Those names mean nothing to Flutter, and importing `material.dart` here would drag the
/// widget layer into the agent layer, so the badge exposes a symbolic case and the view maps it
/// to an `IconData` in one place. The original SF Symbol is recorded on each case so the two
/// apps' badges can be diffed.
enum ProvenanceBadgeIcon {
  /// SF Symbol `doc.text`.
  document,

  /// SF Symbol `network`.
  network,

  /// SF Symbol `iphone`.
  device,
}

/// Structured record of what actually happened while producing one assistant answer — whether
/// the public web, attached documents, or device-local facts were consulted.
///
/// Built entirely from real pipeline state inside [AgentOrchestrator], never inferred from what
/// the model's text claims, so the badge can never say more than what genuinely occurred.
class ResponseProvenance {
  const ResponseProvenance({
    required this.usedWeb,
    required this.usedDocuments,
    required this.usedDeviceContext,
    required this.sources,
  });

  final bool usedWeb;
  final bool usedDocuments;
  final bool usedDeviceContext;
  final List<SourceReference> sources;

  static const ResponseProvenance empty = ResponseProvenance(
    usedWeb: false,
    usedDocuments: false,
    usedDeviceContext: false,
    sources: [],
  );

  /// The exact four-way badge matrix, derived only from [usedDocuments]/[usedWeb]. Lives on the
  /// model rather than only in the view so it is covered by plain unit tests.
  ///
  /// The separator in the files-only case is U+2022 BULLET, matching the Swift string.
  String get badgeText {
    if (usedDocuments && usedWeb) return 'On Device + Files + Web';
    if (!usedDocuments && usedWeb) return 'On Device + Web';
    if (usedDocuments && !usedWeb) return 'On Device • Files';
    return 'On Device';
  }

  ProvenanceBadgeIcon get badgeIcon {
    if (usedWeb) return ProvenanceBadgeIcon.network;
    if (usedDocuments) return ProvenanceBadgeIcon.document;
    return ProvenanceBadgeIcon.device;
  }

  ResponseProvenance copyWith({
    bool? usedWeb,
    bool? usedDocuments,
    bool? usedDeviceContext,
    List<SourceReference>? sources,
  }) {
    return ResponseProvenance(
      usedWeb: usedWeb ?? this.usedWeb,
      usedDocuments: usedDocuments ?? this.usedDocuments,
      usedDeviceContext: usedDeviceContext ?? this.usedDeviceContext,
      sources: sources ?? this.sources,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! ResponseProvenance) return false;
    if (other.usedWeb != usedWeb ||
        other.usedDocuments != usedDocuments ||
        other.usedDeviceContext != usedDeviceContext ||
        other.sources.length != sources.length) {
      return false;
    }
    for (var index = 0; index < sources.length; index++) {
      if (other.sources[index] != sources[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        usedWeb,
        usedDocuments,
        usedDeviceContext,
        Object.hashAll(sources),
      );
}
