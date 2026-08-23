import 'dart:io';

/// Approximate memory figures for the debug metrics and benchmark surfaces.
///
/// ## What could not be ported
///
/// The Swift original calls `task_info(mach_task_self_, MACH_TASK_BASIC_INFO, …)` and reads
/// `resident_size` — the kernel's own accounting of the process's resident set. Dart cannot
/// make that call: `dart:ffi` could, but nothing outside `lib/llm/` is allowed to import it
/// (see PORTING_CONVENTIONS), and a platform channel would need native code in `ios/` and
/// `android/` that this port does not ship.
///
/// The fallback is `ProcessInfo.currentRss`, which the Dart VM computes from the same OS
/// facilities (`task_info` on Darwin, `/proc/self/statm` on Linux and Android). In practice
/// it tracks the Mach figure closely. Two caveats that make it *not* a drop-in equal:
///
/// * It is the whole process's RSS, so it includes the Dart heap, Flutter's engine and the
///   Skia/Impeller caches — exactly as `resident_size` did. Neither number isolates the
///   model's own allocation, which is why the Swift comment already called it "not an exact
///   how-much-RAM-did-the-model-use figure".
/// * `ProcessInfo.currentRss` returns `0`, not an error, when the VM cannot determine it.
///   That zero is mapped to `null` here so callers keep the Swift optional's semantics.
///
/// [totalPhysicalMemoryBytes] and [availablePhysicalMemoryBytes] have **no iOS
/// implementation at all**. `/proc/meminfo` covers Android and Linux; on iOS and macOS the
/// equivalent needs `sysctl(HW_MEMSIZE)` / `host_statistics64` through a platform channel.
/// They return `null` there rather than guessing, and every caller — the model catalog's
/// memory filter in particular — must treat `null` as "unknown, do not filter".
abstract final class MemoryReporter {
  /// Current resident set size in bytes, or `null` when the platform cannot report it.
  static int? currentResidentMemoryBytes() {
    final rss = ProcessInfo.currentRss;
    return rss > 0 ? rss : null;
  }

  /// Peak resident set size observed for this process, or `null` when unavailable.
  ///
  /// The Swift app had no equivalent — `mach_task_basic_info` exposes it as
  /// `resident_size_max`, but `MemoryReporter` never read it. It is surfaced here because
  /// the benchmark screen's most useful number for a model is its *peak* footprint, not the
  /// footprint at the moment the run happened to finish.
  static int? peakResidentMemoryBytes() {
    final maxRss = ProcessInfo.maxRss;
    return maxRss > 0 ? maxRss : null;
  }

  /// Total physical RAM, or `null` on platforms where it cannot be read without native code.
  static int? totalPhysicalMemoryBytes() => _meminfoValueBytes('MemTotal');

  /// Physical RAM the OS believes is available for a new allocation, or `null`.
  ///
  /// On Android this is `MemAvailable`, which already accounts for reclaimable page cache —
  /// a far better predictor of whether a multi-gigabyte model will load than `MemFree`.
  static int? availablePhysicalMemoryBytes() => _meminfoValueBytes('MemAvailable');

  /// Parses one `/proc/meminfo` row. The file reports kibibytes; the result is bytes.
  ///
  /// Read synchronously and uncached: it is consulted at most once per screen, and caching
  /// an availability figure would defeat the point of asking.
  static int? _meminfoValueBytes(String key) {
    if (!Platform.isAndroid && !Platform.isLinux) {
      return null;
    }
    try {
      final lines = File('/proc/meminfo').readAsLinesSync();
      for (final line in lines) {
        if (!line.startsWith('$key:')) {
          continue;
        }
        final digits = RegExp(r'\d+').firstMatch(line)?.group(0);
        final kibibytes = digits == null ? null : int.tryParse(digits);
        return kibibytes == null ? null : kibibytes * 1024;
      }
      return null;
    } on FileSystemException {
      return null;
    }
  }
}
