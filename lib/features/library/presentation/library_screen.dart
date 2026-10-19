import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_panel.dart';
import 'package:media_downloader/features/library/domain/library_filter.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
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

    final List<Widget> content;
    if (list == null) {
      content = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: items.hasError
                ? Text(l10n.failureUnknown)
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.list(
            children: [
              if (active.isNotEmpty && !filter.searching) ...[
                SectionLabel(
                  l10n.libraryInProgress,
                  trailing: l10n.libraryActiveCount(active.length),
                ),
                for (final download in active) ...[
                  ActiveDownloadTile(
                    key: ValueKey(download.id),
                    download: download,
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 18),
              ],
              if (shown!.isEmpty && list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(
                    l10n.libraryNoMatches,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final (day, group) in _byDay(shown)) ...[
                SectionLabel(_dayLabel(context, day)),
                for (final item in group) ...[
                  LibraryTile(key: ValueKey(item.id), item: item),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ];
    }

    return Scaffold(
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          if (filter.searching)
            const SliverAppBar(pinned: true, title: _SearchField())
          else
            SliverAppBar.large(
              title: Text(
                l10n.navLibrary,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                if (list?.isNotEmpty ?? false)
                  IconButton(
                    tooltip: l10n.librarySearch,
                    icon: const Icon(Icons.search_rounded),
                    onPressed: ref
                        .read(libraryFilterStateProvider.notifier)
                        .openSearch,
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ...content,
        ],
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

class _SearchField extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(libraryFilterStateProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: TextField(
            autofocus: true,
            onChanged: controller.search,
            textInputAction: TextInputAction.search,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration.collapsed(
              hintText: l10n.librarySearchHint,
            ),
          ),
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

    void select(VoidCallback change) {
      unawaited(HapticFeedback.selectionClick());
      change();
    }

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _Chip(
            label: l10n.libraryFilterAll,
            selected: filter.type == null,
            onTap: () => select(() => controller.showType(null)),
          ),
          for (final type in OutputType.values)
            _Chip(
              label: type.label(l10n),
              selected: filter.type == type,
              onTap: () => select(() => controller.showType(type)),
            ),
          if (sites.length > 1) ...[
            Center(
              child: Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                color: scheme.outlineVariant,
              ),
            ),
            for (final site in sites)
              _Chip(
                label: site.label(l10n),
                avatar: Icon(site.icon, color: site.brandColor),
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
        ],
      ),
    );
  }
}
