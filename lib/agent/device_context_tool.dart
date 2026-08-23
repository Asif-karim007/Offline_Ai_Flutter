import 'package:intl/intl.dart';

import 'agent_router.dart';

/// Trusted, always-current device-local facts a GGUF model has no way to know on its own — a
/// static set of weights has no clock. No network access, no LLM call.
class DeviceContext {
  const DeviceContext({
    required this.currentDate,
    required this.timeZoneIdentifier,
    required this.localeName,
  });

  final DateTime currentDate;

  /// Swift used `TimeZone.identifier`, an IANA name such as `America/Los_Angeles`. Dart's core
  /// library exposes only `DateTime.timeZoneName`, which on most platforms is the abbreviation
  /// (`PDT`), and this port deliberately does not add `flutter_timezone` to the dependency list
  /// for one string. The value is used as prompt metadata only — nothing computes with it — so
  /// the abbreviation carries the same meaning to the model. See [DeviceContextTool.currentTimeZoneIdentifier].
  final String timeZoneIdentifier;

  final String localeName;

  @override
  bool operator ==(Object other) =>
      other is DeviceContext &&
      other.currentDate == currentDate &&
      other.timeZoneIdentifier == timeZoneIdentifier &&
      other.localeName == localeName;

  @override
  int get hashCode => Object.hash(currentDate, timeZoneIdentifier, localeName);
}

/// Answers date/time questions deterministically, bypassing the LLM entirely for simple cases.
///
/// [AgentRouter] routes these questions here directly (see [AgentRouter.deviceTimePhrases] and
/// [AgentRouter.deviceDatePhrases]) precisely so the model is never asked to guess something the
/// device already knows exactly — this tool exists to make that guarantee cheap to fulfil: no
/// second generation, no added latency, no battery cost.
abstract final class DeviceContextTool {
  static DeviceContext currentContext({String? localeName, String? timeZoneIdentifier}) {
    final now = DateTime.now();
    return DeviceContext(
      currentDate: now,
      timeZoneIdentifier: timeZoneIdentifier ?? currentTimeZoneIdentifier(),
      localeName: localeName ?? Intl.getCurrentLocale(),
    );
  }

  /// Best-effort stand-in for `TimeZone.current.identifier`. See [DeviceContext.timeZoneIdentifier]
  /// for why this is an abbreviation rather than an IANA name in this port.
  static String currentTimeZoneIdentifier() => DateTime.now().timeZoneName;

  /// A short, deterministic, formatted answer for a simple date/time question.
  ///
  /// [query] is only used to decide whether the user asked about the time, the date, or both —
  /// it is never sent anywhere, and never used to derive the actual values, which always come
  /// from [context]. The two flags are computed independently and can both be true: "the time
  /// today" appears in the *date* phrase list.
  static String formattedAnswer(String query, {DeviceContext? context}) {
    final resolved = context ?? currentContext();
    final lowered = query.toLowerCase();
    final wantsDate = AgentRouter.deviceDatePhrases.any(lowered.contains);
    final wantsTime = AgentRouter.deviceTimePhrases.any(lowered.contains);

    final time = _format(() => DateFormat.jm(resolved.localeName), () => DateFormat.jm('en_US'),
        resolved.currentDate);
    final date = _format(() => DateFormat.yMMMMEEEEd(resolved.localeName),
        () => DateFormat.yMMMMEEEEd('en_US'), resolved.currentDate);

    if (wantsTime && wantsDate) return "It's $time on $date.";
    if (!wantsTime && wantsDate) return 'Today is $date.';
    // Covers (time-only) and the (neither) fallback — reaching this tool at all means the
    // router matched a time or date phrase, so defaulting to time is safe.
    return "It's $time.";
  }

  /// `intl` throws for a locale whose date symbols have not been loaded via
  /// `initializeDateFormatting`. Only `en_US` is compiled in by default, so a device set to,
  /// say, `de_DE` would crash a date/time answer in an app that never initialised locale data.
  /// Falling back is strictly better than that: the answer stays correct, only its formatting
  /// is less local.
  static String _format(
    DateFormat Function() preferred,
    DateFormat Function() fallback,
    DateTime value,
  ) {
    try {
      return preferred().format(value);
    } catch (_) {
      return fallback().format(value);
    }
  }
}
