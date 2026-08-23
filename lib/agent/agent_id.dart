import 'dart:math';

/// Replacement for Swift's built-in `UUID()`, which the whole `Agent/` layer uses for chunk,
/// document, search-result and benchmark identity.
///
/// This file has no Swift counterpart. It exists because `package:uuid` is deliberately not a
/// dependency of this port — every identifier the agent layer mints is session-scoped and
/// never crosses a process boundary or gets compared against an identifier produced by another
/// system, so a 12-line RFC 4122 v4 generator over `Random.secure()` is the whole requirement.
///
/// Output is lowercase-hyphenated. Swift's `UUID.uuidString` is uppercase; the only place the
/// string form is ever read is `RetrievedWebChunk.sourceID`, which is compared to nothing.
String newAgentId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

  // Version 4, variant 1 — the two bit-fixups that make this a well-formed v4 UUID rather
  // than 16 arbitrary bytes wearing the shape of one.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int start, int end) {
    final buffer = StringBuffer();
    for (var index = start; index < end; index++) {
      buffer.write(bytes[index].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

final Random _random = Random.secure();
