import 'dart:math';

import '../domain/chat_message.dart';

/// A saved conversation.
///
/// The Swift app had a SwiftData `@Model` class here, which meant the object the UI held was
/// live-attached to a `ModelContext`. This is a plain value instead: the repository reads
/// rows and hands back immutable snapshots, so nothing above `lib/persistence/` can mutate
/// the database by assigning to a field, and a `Conversation` is safe to send across an
/// isolate boundary.
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages,
  });

  /// A canonical lowercase UUID v4 string.
  ///
  /// SwiftData stored a native `UUID`; SQLite has no UUID type, so the port stores the
  /// 36-character canonical text form. Keeping the same format (rather than, say, packing
  /// 16 bytes into a BLOB) is what would let an existing iOS store be migrated row for row.
  final String id;

  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// `null` means "not loaded", which is a different state from "loaded and empty".
  ///
  /// Sidebar rows never load messages — that is the whole point of [ConversationSummary] —
  /// so a `null` here is the normal case, and a caller that needs the transcript asks the
  /// repository for it explicitly rather than lazily faulting one in. The SwiftData version
  /// could not express the distinction and paid for it: `lastMessagePreview` faulted in
  /// every message of every conversation just to render the sidebar.
  final List<ChatMessage>? messages;

  bool get hasLoadedMessages => messages != null;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  /// Generates a conversation identifier.
  ///
  /// Hand-rolled rather than pulled from `package:uuid`, which is not a declared dependency
  /// of this project. `Random.secure` is used over the default generator so two conversations
  /// created in the same millisecond on the same device cannot collide through a seeded PRNG.
  static String newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    // RFC 4122 section 4.4: version 4 in the high nibble of byte 6, variant 10x in byte 8.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  static final Random _random = Random.secure();

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      other.id == id &&
      other.title == title &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      _sameMessages(other.messages, messages);

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt, messages?.length);

  static bool _sameMessages(List<ChatMessage>? a, List<ChatMessage>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// What the sidebar list needs and nothing more.
///
/// Ported from `ConversationSummary` in `Persistence/ConversationRepository.swift`. The
/// preview is computed by SQL — a correlated subquery for the newest message — rather than
/// by loading a relationship, which is the one place this port deliberately diverges from
/// the Swift behaviour for performance rather than for platform reasons.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.lastMessagePreview,
  });

  final String id;
  final String title;
  final DateTime updatedAt;

  /// The newest message's content, trimmed of leading and trailing whitespace and newlines,
  /// or the empty string when the conversation has no messages.
  final String lastMessagePreview;

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.id == id &&
      other.title == title &&
      other.updatedAt == updatedAt &&
      other.lastMessagePreview == lastMessagePreview;

  @override
  int get hashCode => Object.hash(id, title, updatedAt, lastMessagePreview);
}
