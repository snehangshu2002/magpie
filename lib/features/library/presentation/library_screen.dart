import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/router/app_router.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/widgets/page_header.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_panel.dart';
import 'package:media_downloader/features/library/domain/library_filter.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/library/presentation/library_actions.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';
import 'package:media_downloader/features/library/presentation/widgets/active_download_tile.dart';
import 'package:media_downloader/features/library/presentation/widgets/library_tile.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Downloads in progress, then everything saved, newest first and grouped
/// by day.
class LibraryScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = ref.watch(libraryItemsProvider);
    final active = ref.watch(activeDownloadsProvider).value ?? const [];
    final filter = ref.watch(libraryFilterStateProvider);
    final list = items.value;
    final shown = list?.where(filter.matches).toList();
    final selection = ref.watch(librarySelectionProvider);
    // Ids of files deleted meanwhile drop out here.
    final selected = [...?shown?.where((item) => selection.contains(item.id))];
    final selecting = selected.isNotEmpty;
    final side = PageLayout.gutter(context);

    final List<Widget> content;
    if (list == null) {
      content = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: items.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(switch (items.error) {
                        final Failure failure => failure.message(l10n),
                        _ => l10n.failureUnknown,
                      }, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () => ref.invalidate(libraryItemsProvider),
                        child: Text(l10n.retry),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ];
    } else if (list.isEmpty && active.isEmpty) {
      content = const [
        SliverFillRemaining(hasScrollBody: false, child: _EmptyLibrary()),
      ];
    } else {
      content = [
        if (list.isNotEmpty)
          SliverToBoxAdapter(
            child: _Filters(
              filter: filter,
              platforms: {for (final item in list) item.platform},
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 8, side, 24),
          sliver: SliverList.list(
            children: [
              if (active.isNotEmpty && !filter.searching) ...[
                SectionLabel(
                  l10n.libraryInProgress,
                  trailing: l10n.libraryActiveCount(active.length),
                ),
                for (final download in active)
                  _Appear(
                    key: ValueKey(download.id),
                    id: download.id,
                    child: ActiveDownloadTile(download: download),
                  ),
                const SizedBox(height: 18),
              ],
              if (shown!.isEmpty && list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Text(
                        l10n.libraryNoMatches,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: ref
                            .read(libraryFilterStateProvider.notifier)
                            .clear,
                        child: Text(l10n.libraryClearFilters),
                      ),
                    ],
                  ),
                ),
              for (final (day, group) in _byDay(shown)) ...[
                SectionLabel(_dayLabel(context, day)),
                for (final item in group)
                  _Appear(
                    key: ValueKey(item.id),
                    id: item.id,
                    // Only files that just finished; the rest are already
                    // there when the screen opens or scrolls back.
                    animate:
                        DateTime.now().difference(item.savedAt) <
                        const Duration(seconds: 5),
                    child: LibraryTile(item: item, selecting: selecting),
                  ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ];
    }

    // Back ends selecting, then search, before it leaves the screen.
    return PopScope(
      canPop: !selecting && !filter.searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          ref.read(librarySelectionProvider.notifier).clear();
        } else {
          ref.read(libraryFilterStateProvider.notifier).closeSearch();
        }
      },
      child: Scaffold(
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (selecting)
              _SelectionBar(selected: selected, shown: shown!)
            else if (filter.searching)
              const SliverAppBar(pinned: true, title: _SearchField())
            else
              SliverAppBar(
                pinned: true,
                titleSpacing: side,
                title: const BrandTitle(),
                actions: [
                  if (list?.isNotEmpty ?? false)
                    IconButton(
                      tooltip: l10n.librarySearch,
                      icon: const Icon(Icons.search_rounded),
                      onPressed: ref
                          .read(libraryFilterStateProvider.notifier)
                          .openSearch,
                    ),
                  SizedBox(width: side - 8),
                ],
              ),
            if (!selecting && !filter.searching)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                sliver: SliverToBoxAdapter(
                  child: PageHeader(
                    title: l10n.libraryTitle,
                    subtitle: l10n.libraryHint,
                  ),
                ),
              ),
            ...content,
          ],
        ),
      ),
    );
  }

  /// Items grouped by the day they were saved; [items] are newest first.
  static List<(DateTime, List<LibraryItem>)> _byDay(List<LibraryItem> items) {
    final groups = <(DateTime, List<LibraryItem>)>[];
    for (final item in items) {
      final at = item.savedAt;
      final day = DateTime(at.year, at.month, at.day);
      if (groups.isNotEmpty && groups.last.$1 == day) {
        groups.last.$2.add(item);
      } else {
        groups.add((day, [item]));
      }
    }
    return groups;
  }

  static String _dayLabel(BuildContext context, DateTime day) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (day == today) return l10n.libraryToday;
    if (day == yesterday) return l10n.libraryYesterday;
    final material = MaterialLocalizations.of(context);
    return day.year == now.year
        ? material.formatShortMonthDay(day)
        : material.formatMediumDate(day);
  }
}

/// Replaces the title while files are selected: how many, and what can be
/// done with all of them at once.
class _SelectionBar extends ConsumerWidget {
  const new({required this.selected, required this.shown});

  final List<LibraryItem> selected;
  final List<LibraryItem> shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selection = ref.read(librarySelectionProvider.notifier);
    return SliverAppBar(
      pinned: true,
      leading: IconButton(
        tooltip: l10n.libraryEndSelection,
        icon: const Icon(Icons.close_rounded),
        onPressed: selection.clear,
      ),
      title: Text(
        l10n.librarySelected(selected.length),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      actions: [
        if (selected.length < shown.length)
          IconButton(
            tooltip: l10n.librarySelectAll,
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () {
              unawaited(HapticFeedback.selectionClick());
              selection.selectAll([for (final item in shown) item.id]);
            },
          ),
        IconButton(
          tooltip: l10n.libraryShare,
          icon: const Icon(Icons.share_outlined),
          onPressed: () async {
            if (await shareLibraryItems(context, ref, selected)) {
              selection.clear();
            }
          },
        ),
        IconButton(
          tooltip: l10n.libraryDelete,
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (await deleteLibraryItems(context, ref, selected)) {
              selection.clear();
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = ref.read(libraryFilterStateProvider.notifier);
    final hasText = ref.watch(
      libraryFilterStateProvider.select((f) => f.query?.isNotEmpty ?? false),
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            autofocus: true,
            onChanged: controller.search,
            textInputAction: TextInputAction.search,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration.collapsed(
              hintText: l10n.librarySearchHint,
            ),
          ),
        ),
        if (hasText)
          IconButton(
            tooltip: l10n.libraryClearSearch,
            icon: const Icon(Icons.backspace_outlined),
            onPressed: () {
              _text.clear();
              controller.search('');
            },
          ),
        IconButton(
          tooltip: l10n.librarySearchClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: controller.closeSearch,
        ),
      ],
    );
  }
}

/// Kind of file, then site, as one scrolling row of chips.
class _Filters extends ConsumerWidget {
  const new({required this.filter, required this.platforms});

  final LibraryFilter filter;
  final Set<SourcePlatform> platforms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(libraryFilterStateProvider.notifier);
    // Sites in their usual order rather than by first download.
    final sites = [
      for (final platform in SourcePlatform.values)
        if (platforms.contains(platform)) platform,
    ];

    void select(VoidCallback change, {bool changes = true}) {
      if (changes) unawaited(HapticFeedback.selectionClick());
      change();
    }

    return SizedBox(
      height: (56 * MediaQuery.textScalerOf(context).scale(1)).clamp(56, 96),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: PageLayout.gutter(context),
          vertical: 8,
        ),
        children: [
          _Chip(
            label: l10n.libraryFilterAll,
            selected: filter.type == null,
            onTap: () => select(
              () => controller.showType(null),
              changes: filter.type != null,
            ),
          ),
          for (final type in OutputType.values)
            _Chip(
              label: type.label(l10n),
              selected: filter.type == type,
              onTap: () => select(
                () => controller.showType(type),
                changes: filter.type != type,
              ),
            ),
          if (sites.length > 1) ...[
            Center(
              child: Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            for (final site in sites)
              _Chip(
                label: site.label(l10n),
                avatar: PlatformBadge(platform: site, size: 22),
                selected: filter.platform == site,
                onTap: () => select(() => controller.toggleSite(site)),
              ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        avatar: selected ? null : avatar,
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        color: WidgetStatePropertyAll(
          selected ? scheme.primaryContainer : scheme.surfaceContainer,
        ),
        labelStyle: TextStyle(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.secondaryContainer,
            ),
            child: Icon(
              Icons.video_library_outlined,
              size: 32,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.libraryEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.libraryEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () => context.go(AppRoutes.intake),
            child: Text(l10n.libraryEmptyAction),
          ),
        ],
      ),
    );
  }
}

/// Fades and grows its child in the first time [id] is built, so a finished
/// download or a new file doesn't pop into the list. Removal is not animated.
class _Appear extends StatefulWidget {
  const new({
    required this.id,
    required this.child,
    this.animate = true,
    super.key,
  });

  final String id;
  final Widget child;
  final bool animate;

  // Scrolling rebuilds off-screen rows; only a first appearance animates.
  static final _seen = <String>{};

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> {
  late final bool _animate = widget.animate && _Appear._seen.add(widget.id);

  @override
  Widget build(BuildContext context) {
    final child = Column(children: [widget.child, const SizedBox(height: 10)]);
    if (!_animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.durationOf(context),
      curve: AppMotion.standard,
      builder: (context, value, child) => Align(
        alignment: Alignment.topCenter,
        heightFactor: value.clamp(0, 1),
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: child,
    );
  }
}
