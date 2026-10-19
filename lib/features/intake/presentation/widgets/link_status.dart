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
/// as the user types, or explains why the link can't be used.
class LinkStatus extends StatelessWidget {
  const new({required this.detected, required this.notice, super.key});

  final DetectedLink? detected;
  final IntakeNotice? notice;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.durationOf(context);

    final status = switch ((notice, detected)) {
      (final IntakeNotice active, _) => (
        Icons.error_outline_rounded,
        active.message(l10n),
        true,
      ),
      (_, DetectedLink(kind: LinkKind.playlist)) => (
        Icons.playlist_remove_rounded,
        l10n.noticePlaylistUnsupported,
        true,
      ),
      (_, final DetectedLink link) => (
        null,
        l10n.linkDetected(link.platform.label(l10n), link.kind.label(l10n)),
        false,
      ),
      _ => null,
    };

    return AnimatedSize(
      duration: duration,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppMotion.standard,
        switchOutCurve: AppMotion.standard,
        child: switch (status) {
          null => const SizedBox(key: ValueKey('none'), width: double.infinity),
          (final icon, final text, final isProblem) => Semantics(
            key: ValueKey(text),
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: isProblem
                        ? Icon(icon, size: 18, color: scheme.error)
                        // A quiet "got it"; the text says what.
                        : Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isProblem
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        },
      ),
    );
  }
}
