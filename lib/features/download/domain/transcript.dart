import 'package:media_downloader/core/platform/models/media_info.dart';

/// The words of a WebVTT caption file as plain text: no header, cue
/// timings, numbers or tags, and each line once. YouTube's automatic
/// captions roll, repeating the last line at the start of the next cue.
String transcriptFromVtt(String vtt) {
  final lines = <String>[];
  var inNote = false;
  for (final raw in vtt.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) {
      inNote = false;
      continue;
    }
    if (inNote) continue;
    if (line.startsWith('NOTE') ||
        line.startsWith('STYLE') ||
        line.startsWith('REGION')) {
      inNote = true;
      continue;
    }
    if (line.startsWith('WEBVTT') ||
        line.contains('-->') ||
        RegExp(r'^\d+$').hasMatch(line) ||
        line.startsWith('Kind:') ||
        line.startsWith('Language:')) {
      continue;
    }
    final text = _decode(line.replaceAll(RegExp('<[^>]*>'), '')).trim();
    if (text.isEmpty || (lines.isNotEmpty && lines.last == text)) continue;
    lines.add(text);
  }
  return lines.join('\n');
}

String _decode(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// The track to show first: the uploader's own subtitles before automatic
/// ones, in [languageCode] (the app's language) when there is one.
CaptionTrack? defaultCaption(
  List<CaptionTrack> tracks, {
  String languageCode = 'en',
}) {
  bool inLanguage(CaptionTrack t) =>
      t.lang == languageCode || t.lang.startsWith('$languageCode-');
  final manual = tracks.where((t) => !t.auto);
  return manual.where(inLanguage).firstOrNull ??
      manual.firstOrNull ??
      tracks.where(inLanguage).firstOrNull ??
      tracks.firstOrNull;
}
