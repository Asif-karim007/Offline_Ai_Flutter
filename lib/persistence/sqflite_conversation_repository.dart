import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/chat_message.dart';
import '../llm/llama_error.dart';
import '../utilities/logger.dart';
import 'conversation.dart';
import 'conversation_repository.dart';
import 'stored_message.dart';

/// Hand-written sqflite implementation of [ConversationRepository].
///
/// No drift and no code generation: a fresh clone of this repository is
/// `flutter pub get && flutter run`, with no build_runner step to forget. The schema is two
/// tables, so the SQL below is the whole of what a generator would have produced, and it
/// stays readable enough to diff against `Persistence/SwiftDataConversationRepository.swift`.
///
/// SwiftData behaviours that had to be re-established by hand rather than inherited:
///
/// * **Cascade delete.** SQLite enforces foreign keys only when asked, per connection, so
///   [_configure] issues `PRAGMA foreign_keys = ON` on every open. Without it the
///   `ON DELETE CASCADE` in the schema is inert and deleting a conversation would orphan
///   every message it owns.
/// * **Upsert on a duplicate id.** Inserting a row with an existing unique id is an upsert
///   in SwiftData and a constraint violation in SQLite, so [saveMessage] uses
///   `ConflictAlgorithm.replace`.
/// * **Explicit schema version.** SwiftData had no versioning or migration plan at all.
///   Flutter's stack will not silently lightweight-migrate anything, so this starts at an
///   explicit version 1 with a real [_migrate] to grow.
class SqfliteConversationRepository implements ConversationRepository {
  SqfliteConversationRepository._(this._database);

  /// Bump this and add a branch to [_migrate] for every schema change. Never edit an
  /// existing branch: a shipped device has already run it.
  static const int schemaVersion = 1;

  static const String _databaseFileName = 'conversations.db';

  static const String _conversationsTable = 'conversations';
  static const String _messagesTable = 'messages';

  final Database _database;

  Database get database => _database;

  /// Opens (creating if needed) the conversation store.
  ///
  /// The file lives in the application support directory rather than in sqflite's default
  /// `getDatabasesPath()`, which on iOS resolves inside `Documents` — a directory that
  /// becomes visible in the Files app the moment `UIFileSharingEnabled` is ever switched on.
  /// Chat transcripts are the most private data this app holds and they do not belong there.
  ///
  /// [directoryPath] exists for tests, which pass a temporary directory. Passing
  /// `inMemoryDatabasePath` as [directoryPath] is not supported; use [openInMemory].
  static Future<SqfliteConversationRepository> open({String? directoryPath}) async {
    final directory = directoryPath ?? (await getApplicationSupportDirectory()).path;
    return _openAt(p.join(directory, _databaseFileName));
  }

  /// An ephemeral store, for tests and for anything that must leave no trace on disk.
  static Future<SqfliteConversationRepository> openInMemory() =>
      _openAt(inMemoryDatabasePath);

  static Future<SqfliteConversationRepository> _openAt(String path) async {
    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _configure,
      onCreate: (db, version) => _migrate(db, 0, version),
      onUpgrade: _migrate,
    );
    AppLog.persistence('store.opened',
        fields: const [LogField.count('schemaVersion', schemaVersion)]);
    return SqfliteConversationRepository._(database);
  }

  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// The single place the schema is defined and evolved.
  ///
  /// [from] is `0` on a first install, which lets creation and migration share one code path
  /// — the alternative, an `onCreate` that duplicates the final shape of every table, is how
  /// a freshly installed schema silently drifts from a migrated one.
  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      await db.execute('''
        CREATE TABLE $_conversationsTable (
          id         TEXT    PRIMARY KEY NOT NULL,
          title      TEXT    NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE $_messagesTable (
          id              TEXT    PRIMARY KEY NOT NULL,
          conversation_id TEXT    NOT NULL
                                  REFERENCES $_conversationsTable (id) ON DELETE CASCADE,
          role            TEXT    NOT NULL,
          content         TEXT    NOT NULL,
          created_at      INTEGER NOT NULL,
          status          TEXT    NOT NULL
        )
      ''');

      // Covers both message queries: the transcript load filters on conversation_id and
      // orders by created_at, and the sidebar's newest-message subquery does the same in
      // reverse. Without it every sidebar render is a full scan of the messages table.
      await db.execute('''
        CREATE INDEX idx_messages_conversation_created
          ON $_messagesTable (conversation_id, created_at)
      ''');

      // The sidebar's only sort. Cheap to maintain and it turns fetchAllSummaries from a
      // scan-and-sort into an index walk.
      await db.execute('''
        CREATE INDEX idx_conversations_updated
          ON $_conversationsTable (updated_at DESC)
      ''');
    }
  }

  Future<void> close() => _database.close();

  @override
  Future<void> createConversation({
    required String id,
    required String title,
    required DateTime createdAt,
  }) async {
    final timestamp = _toStorage(createdAt);
    await _guarded(() => _database.insert(
          _conversationsTable,
          {
            'id': id,
            'title': title,
            'created_at': timestamp,
            // Seeded with createdAt, not with "now" — see ConversationRepository.
            'updated_at': timestamp,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
  }

  @override
  Future<void> saveMessage(ChatMessage message, {required String conversationId}) async {
    final exists = await _conversationExists(conversationId);
    if (!exists) {
      throw RepositoryException(
        RepositoryErrorKind.conversationNotFound,
        conversationId: conversationId,
      );
    }

    final row = StoredMessage.fromChatMessage(message, conversationId).toRow();
    await _guarded(() => _database.insert(
          _messagesTable,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
  }

  @override
  Future<void> touchConversation({
    required String id,
    required DateTime updatedAt,
  }) async {
    // No existence check: UPDATE on a missing row affects zero rows, which is exactly the
    // silent no-op the Swift version produced by guarding on a failed fetch.
    await _guarded(() => _database.update(
          _conversationsTable,
          {'updated_at': _toStorage(updatedAt)},
          where: 'id = ?',
          whereArgs: [id],
        ));
  }

  @override
  Future<void> renameConversation({required String id, required String title}) async {
    await _guarded(() => _database.update(
          _conversationsTable,
          {'title': title},
          where: 'id = ?',
          whereArgs: [id],
        ));
  }

  @override
  Future<void> deleteConversation(String id) async {
    await _guarded(() => _database.delete(
          _conversationsTable,
          where: 'id = ?',
          whereArgs: [id],
        ));
  }

  @override
  Future<void> deleteAllConversations() async {
    // The Swift version fetched every conversation and deleted them one at a time. One
    // statement plus the cascade is the same outcome, and it is the difference between one
    // transaction and N for a user clearing a long history.
    await _guarded(() => _database.delete(_conversationsTable));
  }

  @override
  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final rows = await _database.query(
      _messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows.map((row) => StoredMessage.fromRow(row).toChatMessage()).toList();
  }

  @override
  Future<List<ConversationSummary>> fetchAllSummaries() async {
    // The preview comes from a correlated subquery rather than from loading the
    // relationship. `lastMessagePreview` in SwiftData was O(messages) per conversation and
    // was evaluated for every row of the sidebar; this is one index seek per row.
    final rows = await _database.rawQuery('''
      SELECT
        c.id         AS id,
        c.title      AS title,
        c.updated_at AS updated_at,
        (
          SELECT m.content
            FROM $_messagesTable m
           WHERE m.conversation_id = c.id
           ORDER BY m.created_at DESC
           LIMIT 1
        ) AS preview
      FROM $_conversationsTable c
      ORDER BY c.updated_at DESC
    ''');

    return rows
        .map((row) => ConversationSummary(
              id: row['id']! as String,
              title: row['title']! as String,
              updatedAt: _fromStorage(row['updated_at']! as int),
              // `null` when the conversation has no messages yet, which the Swift computed
              // property also flattened to the empty string.
              lastMessagePreview: (row['preview'] as String?)?.trim() ?? '',
            ))
        .toList();
  }

  Future<bool> _conversationExists(String id) async {
    final rows = await _database.query(
      _conversationsTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Every write goes through here so that no SQLite failure escapes as a raw
  /// [DatabaseException]. The Swift `save()` helper did the same rewrite, and the UI's error
  /// handling only knows how to render a [LlamaError].
  Future<T> _guarded<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DatabaseException catch (error) {
      AppLog.failure(
        LogChannel.persistence,
        'store.writeFailed',
        LlamaErrorKind.databaseSaveFailed,
      );
      throw LlamaError.databaseSaveFailed(error.toString());
    }
  }

  /// Millis since the Unix epoch in UTC. Storing local millis would make the ordering of a
  /// history that crossed a time-zone change wrong.
  static int _toStorage(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static DateTime _fromStorage(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
}
