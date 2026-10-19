import 'package:flutter/material.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/features/intake/domain/detected_link.dart';
import 'package:media_downloader/features/intake/presentation/intake_controller.dart';
import 'package:media_downloader/l10n/l10n.dart';

extension LinkKindLabel on LinkKind {
  String label(AppLocalizations l10n) => switch (this) {
    LinkKind.video => l10n.linkKindVideo,
    LinkKind.short => l10n.linkKindShort,
    LinkKind.reel => l10n.linkKindReel,
    LinkKind.post => l10n.linkKindPost,
    LinkKind.story => l10n.linkKindStory,
    LinkKind.track => l10n.linkKindTrack,
    LinkKind.playlist => l10n.linkKindPlaylist,
    LinkKind.unknown => l10n.linkKindUnknown,
  };
}

extension IntakeNoticeMessage on IntakeNotice {
  String message(AppLocalizations l10n) => switch (this) {
    IntakeNotice.invalidLink => l10n.noticeInvalidLink,
    IntakeNotice.clipboardEmpty => l10n.noticeClipboardEmpty,
    IntakeNotice.playlistUnsupported => l10n.noticePlaylistUnsupported,
  };
}

/// One line under the link box that answers "what did you recognize?"
/// as the user types, or explains why the link can't be used. Its height is
/// reserved so content below doesn't move as messages come and go.
class LinkStatus extends StatelessWidget {
  const new({
    required this.input,
    required this.detected,
    required this.notice,
    super.key,
  });

  final String input;
  final DetectedLink? detected;
  final IntakeNotice? notice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.durationOf(context);
    final body = theme.textTheme.bodyMedium;
    final line = MediaQuery.textScalerOf(context)
        .scale((body?.fontSize ?? 14) * (body?.height ?? 1.3));

    // (icon, text, colour, announce): problems and notices are announced;
    // the recognized site and the typing hint stay quiet.
    final status = switch ((notice, detected)) {
      (IntakeNotice.invalidLink, _) => (
        Icons.error_outline_rounded,
        l10n.noticeInvalidLink,
        scheme.error,
        true,
      ),
      (final IntakeNotice active, _) => (
        Icons.warning_amber_rounded,
        active.message(l10n),
        scheme.tertiary,
        true,
      ),
      (_, DetectedLink(kind: LinkKind.playlist)) => (
        Icons.warning_amber_rounded,
        l10n.noticePlaylistUnsupported,
        scheme.tertiary,
        true,
      ),
      (_, final DetectedLink link) => (
        Icons.check_circle_rounded,
        l10n.linkDetected(link.platform.label(l10n), link.kind.label(l10n)),
        scheme.primary,
        false,
      ),
      _ when input.trim().isNotEmpty => (
        null,
        l10n.intakeLinkHint,
        scheme.onSurfaceVariant,
        false,
      ),
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: line < 20 ? 20 : line),
        child: AnimatedSize(
          duration: duration,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: AppMotion.standard,
            switchOutCurve: AppMotion.standard,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: switch (status) {
              null => const SizedBox(
                key: ValueKey('none'),
                width: double.infinity,
              ),
              (final icon, final text, final color, final announce) =>
                Semantics(
                  key: ValueKey(text),
                  liveRegion: announce,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.square(
                        dimension: 20,
                        child: icon == null
                            ? null
                            : Icon(icon, size: 18, color: color),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          text,
                          style: body?.copyWith(
                            color: announce || icon == null
                                ? color
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            },
          ),
        ),
      ),
    );
  }
}
