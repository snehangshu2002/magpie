import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';
import 'package:media_downloader/features/library/presentation/widgets/library_tile.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Everything the user has downloaded, newest first.
class LibraryScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = ref.watch(libraryItemsProvider);
    final list = items.value;

    final Widget content;
    if (list == null) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: items.hasError
              ? Text(l10n.failureUnknown)
              : const CircularProgressIndicator(),
        ),
      );
    } else if (list.isEmpty) {
      content = const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyLibrary(),
      );
    } else {
      content = SliverPadding(
        padding: const EdgeInsets.only(bottom: 24),
        sliver: SliverList.builder(
          itemCount: list.length,
          itemBuilder: (context, index) =>
              LibraryTile(key: ValueKey(list[index].id), item: list[index]),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(l10n.navLibrary)),
          content,
        ],
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
          Icon(
            Icons.video_library_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.libraryEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
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
