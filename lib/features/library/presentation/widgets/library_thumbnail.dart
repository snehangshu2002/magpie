import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/platform/models/download_request.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';

/// A preview from the saved file, else yt-dlp's thumbnail, else an icon for
/// the kind of file.
class LibraryThumbnail extends ConsumerWidget {
  const new({
    required this.type,
    this.fileUri,
    this.thumbnailUrl,
    this.width = 112,
    this.height = 63,
    super.key,
  });

  final OutputType type;

  /// The saved file; null while it's still downloading.
  final String? fileUri;
  final String? thumbnailUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fileUri = this.fileUri;
    final local = fileUri == null
        ? const AsyncData<Uint8List?>(null)
        : ref.watch(libraryThumbnailProvider(fileUri));
    final placeholder = Center(
      child: Icon(switch (type) {
        OutputType.video => Icons.movie_outlined,
        OutputType.audio => Icons.music_note_rounded,
        OutputType.image => Icons.image_outlined,
      }, color: scheme.onSurfaceVariant),
    );
    final remote = thumbnailUrl;

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        shape: AppTheme.shape(12),
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerHighest,
        child: AnimatedSwitcher(
          duration: AppMotion.durationOf(context),
          child: switch (local) {
            AsyncData(value: final bytes?) => Image.memory(
              bytes,
              key: const ValueKey('local'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
            AsyncLoading() => const SizedBox.expand(),
            _ when remote != null => Image.network(
              remote,
              key: const ValueKey('remote'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => placeholder,
            ),
            _ => placeholder,
          },
        ),
      ),
    );
  }
}
