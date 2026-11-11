import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/widgets/page_header.dart';
import 'package:media_downloader/features/image_edit/presentation/image_edit_sheet.dart';
import 'package:media_downloader/features/updater/presentation/update_providers.dart';
import 'package:media_downloader/features/updater/presentation/update_sheet.dart';
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
    ref
      ..listen(sharedTextProvider, (_, next) {
        if (next.hasValue) shell.goBranch(0);
      })
      // An image shared from another app: straight to resizing it.
      ..listen(sharedImageProvider, (_, next) {
        if (next case AsyncData(value: final uri)) {
          unawaited(showImageEditSheetFor(context, [uri]));
        }
      })
      // Checked once per launch, so this asks at most once.
      ..listen(appUpdateProvider, (_, next) {
        if (next.value case final update?) {
          unawaited(showUpdateSheet(context, ref, update));
        }
      });

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: shell,
      // A floating pill: the page colour shows around it.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            PageLayout.gutter(context),
            0,
            PageLayout.gutter(context),
            12,
          ),
          child: Material(
            color: scheme.surfaceContainerHigh,
            clipBehavior: Clip.antiAlias,
            shape: StadiumBorder(
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            // The pill already clears the system bars. (This context is
            // above the Scaffold, so it still has the status bar's inset.)
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: NavigationBar(
                height: 68,
                backgroundColor: Colors.transparent,
                selectedIndex: shell.currentIndex,
                onDestinationSelected: (index) => shell.goBranch(
                  index,
                  initialLocation: index == shell.currentIndex,
                ),
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: l10n.navHome,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.handyman_outlined),
                    selectedIcon: const Icon(Icons.handyman),
                    label: l10n.navTools,
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
          ),
        ),
      ),
    );
  }
}

/// The branches side by side: a left or right swipe moves to the next
/// section with the page under the finger. A tap on the navigation bar jumps
/// and cross-fades instead, since it can skip a section.
class BranchPager extends StatefulWidget {
  const new({required this.shell, required this.children, super.key});

  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  State<BranchPager> createState() => _BranchPagerState();
}

class _BranchPagerState extends State<BranchPager>
    with SingleTickerProviderStateMixin {
  late final _pages = PageController(initialPage: widget.shell.currentIndex);
  late final _fade = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(BranchPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.shell.currentIndex;
    // A swipe already shows the page; anything else (a tap, a shared link)
    // fades it in. The jump waits for the frame, hidden by the fade.
    if (!_pages.hasClients || _pages.page?.round() == index) return;
    _fade
      ..duration = AppMotion.durationOf(context)
      ..value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      _pages.jumpToPage(widget.shell.currentIndex);
      _fade.forward();
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _fade, curve: AppMotion.standard),
    child: PageView(
      controller: _pages,
      onPageChanged: (index) {
        if (index == widget.shell.currentIndex) return;
        // The keyboard belongs to the page being left.
        FocusManager.instance.primaryFocus?.unfocus();
        unawaited(HapticFeedback.selectionClick());
        widget.shell.goBranch(index);
      },
      children: widget.children,
    ),
  );
}
