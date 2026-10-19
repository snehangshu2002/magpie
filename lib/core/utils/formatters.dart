import 'package:intl/intl.dart';
import 'package:media_downloader/l10n/app_localizations.dart';

/// Formats a size the way Android's Files app does (powers of 1000),
/// e.g. `48 MB` or `1.2 GB`.
String formatByteSize(int bytes, AppLocalizations l10n) {
  const kilo = 1000;
  const mega = kilo * kilo;
  const giga = mega * kilo;

  String n(double value) =>
      NumberFormat(value < 10 ? '0.#' : '0', l10n.localeName).format(value);

  // Rounding can reach 1000 (999.6 KB); show that in the next unit.
  bool rounds1000(double v) => v >= 999.5;

  if (bytes < mega && !rounds1000(bytes / kilo)) {
    return l10n.sizeKilobytes(n(bytes / kilo));
  }
  if (bytes < giga && !rounds1000(bytes / mega)) {
    return l10n.sizeMegabytes(n(bytes / mega));
  }
  return l10n.sizeGigabytes(n(bytes / giga));
}

/// Formats a media length as `m:ss` or `h:mm:ss`.
String formatDuration(int seconds) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = seconds ~/ 3600;
  final m = seconds % 3600 ~/ 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
