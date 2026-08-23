import 'package:intl/intl.dart';

/// Formats byte counts the way `ByteCountFormatter` with `countStyle = .file` does.
///
/// There is no Flutter equivalent, so this is a deliberate reimplementation of Apple's
/// observable behaviour rather than a generic humaniser:
///
/// * **Base 1000**, not 1024 — `.file` on iOS reports 1 KB as 1000 bytes.
/// * **Adaptive precision** — bytes and KB get no decimals, MB one, GB and above two. This
///   is what produces `"639.4 MB"` and `"1.28 GB"` for the sizes quoted in the model UI.
/// * **`"Zero KB"` for zero.** A genuine `ByteCountFormatter` quirk, kept because the
///   download and model-manager screens show it and the Swift screenshots have it.
/// * Locale-aware decimal separator via [NumberFormat], matching the formatter's behaviour
///   in non-English locales.
///
/// Values below 1000 bytes are rendered in bytes with a singular/plural unit, again as
/// `ByteCountFormatter` does (`"1 byte"`, `"512 bytes"`).
abstract final class FileSizeFormatter {
  static const List<String> _units = ['bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];

  /// Fractional digits per unit index, mirroring `ByteCountFormatter.isAdaptive == true`.
  static const List<int> _fractionDigits = [0, 0, 1, 2, 2, 2];

  static String string({required int bytes}) {
    if (bytes == 0) {
      return 'Zero KB';
    }

    final negative = bytes < 0;
    var magnitude = bytes.abs().toDouble();
    var unitIndex = 0;

    while (unitIndex < _units.length - 1) {
      final digits = _fractionDigits[unitIndex];
      // Promote before rendering, not after: 999_999 bytes rounds to 1000.0 KB at one
      // decimal, and "1000 KB" is not what the Apple formatter prints — "1 MB" is.
      final rounded = _roundTo(magnitude, digits);
      if (rounded < 1000) {
        break;
      }
      magnitude /= 1000;
      unitIndex += 1;
    }

    final digits = _fractionDigits[unitIndex];
    final rendered = _decimalFormat(digits).format(_roundTo(magnitude, digits));

    var unit = _units[unitIndex];
    if (unitIndex == 0 && magnitude == 1) {
      unit = 'byte';
    }

    return '${negative ? '-' : ''}$rendered $unit';
  }

  static double _roundTo(double value, int digits) {
    if (digits == 0) {
      return value.roundToDouble();
    }
    final factor = _pow10(digits);
    return (value * factor).roundToDouble() / factor;
  }

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// Cached per digit count. `NumberFormat` construction parses a pattern, and this runs
  /// once per row of the model list.
  static final Map<int, NumberFormat> _formatters = {};

  static NumberFormat _decimalFormat(int digits) => _formatters.putIfAbsent(
        digits,
        () => NumberFormat.decimalPatternDigits(decimalDigits: digits),
      );
}
