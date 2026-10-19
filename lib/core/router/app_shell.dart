import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Bottom navigation around the top-level branches of the router.
class AppShell extends ConsumerWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    // A link shared from another app opens the Download tab, where the
    // intake controller has already picked it up.
    ref.listen(sharedTextProvider, (_, next) {
      if (next.hasValue) shell.goBranch(0);
    });

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Peers cross-fade (no slide); the key restarts the fade per tab while
      // the IndexedStack keeps each tab's state.
      body: TweenAnimationBuilder<double>(
        key: ValueKey(shell.currentIndex),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.durationOf(context),
        curve: AppMotion.standard,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: shell,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.download_outlined),
              selectedIcon: const Icon(Icons.download),
              label: l10n.navDownload,
            ),
            NavigationDestination(
              icon: const Icon(Icons.video_library_outlined),
              selectedIcon: const Icon(Icons.video_library),
              label: l10n.navLibrary,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: l10n.navSettings,
            ),
          ],
        ),
      ),
    );
  }
}
