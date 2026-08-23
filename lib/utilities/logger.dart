import 'dart:developer' as developer;

import '../llm/llama_error.dart';

/// The three log channels the Swift app declared as `os.Logger` categories.
///
/// The names are the `category` strings from `Utilities/Logger.swift` and are what shows up
/// in `dart:developer`'s `name:` field, so a console filter written against the iOS build
/// keeps working against the Flutter build.
enum LogChannel {
  model('model'),
  persistence('persistence'),
  ui('ui');

  const LogChannel(this.category);

  final String category;
}

/// Fallback subsystem name, matching the Swift `Bundle.main.bundleIdentifier ?? "OfflineAiChat"`
/// fallback. Flutter has no dependency-free way to read the bundle identifier, so the port
/// always uses the fallback rather than pulling in `package_info_plus` for a log prefix.
const String _subsystem = 'OfflineAiChat';

/// One structured field on a log record.
///
/// This type exists to make the Swift file's policy comment — *"Never pass chat prompt or
/// response text to these -- only structural/metric information"* — a property of the API
/// rather than a rule someone has to remember. There is no constructor that takes arbitrary
/// text: a field is a count, a byte size, a duration, a boolean, or an enum case. An enum
/// case is a compile-time symbol, so it cannot smuggle a user's message into a log line.
sealed class LogField {
  const LogField(this.name);

  /// Number of things — tokens, messages, rows, retries.
  const factory LogField.count(String name, int value) = _CountField;

  /// A size in bytes. Rendered with a `B` suffix so it is not confused with a count.
  const factory LogField.bytes(String name, int value) = _BytesField;

  const factory LogField.duration(String name, Duration value) = _DurationField;

  const factory LogField.flag(String name, bool value) = _FlagField;

  /// A categorical value. Restricted to [Enum] precisely because an enum's set of values is
  /// fixed at compile time — [LlamaErrorKind], [LogChannel], a status, a mode. Passing a
  /// `String` here would reopen the hole this type closes.
  const factory LogField.category(String name, Enum value) = _CategoryField;

  final String name;

  String get renderedValue;

  @override
  String toString() => '$name=$renderedValue';
}

final class _CountField extends LogField {
  const _CountField(super.name, this.value);

  final int value;

  @override
  String get renderedValue => '$value';
}

final class _BytesField extends LogField {
  const _BytesField(super.name, this.value);

  final int value;

  @override
  String get renderedValue => '${value}B';
}

final class _DurationField extends LogField {
  const _DurationField(super.name, this.value);

  final Duration value;

  @override
  String get renderedValue => '${value.inMicroseconds / 1000}ms';
}

final class _FlagField extends LogField {
  const _FlagField(super.name, this.value);

  final bool value;

  @override
  String get renderedValue => value ? 'true' : 'false';
}

final class _CategoryField extends LogField {
  const _CategoryField(super.name, this.value);

  final Enum value;

  @override
  String get renderedValue => value.name;
}

/// Privacy-safe logging. The counterpart of `Utilities/Logger.swift`.
///
/// Nothing here can render chat content: [LogField] admits no free text, and [event] is
/// asserted to be a short single-line identifier so that an interpolated user message fails
/// loudly in debug rather than silently landing in the device console.
abstract final class AppLog {
  static void model(String event, {List<LogField> fields = const []}) =>
      _emit(LogChannel.model, event, fields, isError: false);

  static void persistence(String event, {List<LogField> fields = const []}) =>
      _emit(LogChannel.persistence, event, fields, isError: false);

  static void ui(String event, {List<LogField> fields = const []}) =>
      _emit(LogChannel.ui, event, fields, isError: false);

  /// Logs a failure by its *kind* only.
  ///
  /// [LlamaError.detail] is deliberately not logged: it can hold a file path or a native
  /// error string, and neither belongs in a persistent device log. Read it in the debug UI
  /// via `developerDetail` instead.
  static void failure(LogChannel channel, String event, LlamaErrorKind kind,
      {List<LogField> fields = const []}) {
    _emit(
      channel,
      event,
      [LogField.category('error', kind), ...fields],
      isError: true,
    );
  }

  static void _emit(
    LogChannel channel,
    String event,
    List<LogField> fields, {
    required bool isError,
  }) {
    assert(
      event.length <= 64 && !event.contains('\n'),
      'Log events are fixed identifiers, not messages. Got a long or multi-line string, '
      'which usually means user or model text was interpolated into it.',
    );

    final buffer = StringBuffer(event);
    for (final field in fields) {
      buffer
        ..write(' ')
        ..write(field);
    }

    developer.log(
      buffer.toString(),
      name: '$_subsystem.${channel.category}',
      // 1000 is `Level.SEVERE`, 800 is `Level.INFO`, using package:logging's scale — the
      // scale `dart:developer` documents even though this file does not depend on it.
      level: isError ? 1000 : 800,
    );
  }
}
