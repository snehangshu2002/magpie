import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/features/download/data/media_repository_impl.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Starts saving [option] of [preview]. On mobile data it first asks, when
/// the user wants that ("Ask before using mobile data").
Future<void> startDownload(
  BuildContext context,
  WidgetRef ref, {
  required Uri url,
  required MediaPreview preview,
  required DownloadOption option,
}) async {
  final settings = await ref.read(settingsProvider.future);
  if (settings.askOnMobileData &&
      await ref.read(mediaRepositoryProvider).isNetworkMetered()) {
    if (!context.mounted) return;
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.signal_cellular_alt_rounded),
        title: Text(l10n.mobileDataTitle),
        content: Text(l10n.mobileDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.mobileDataWait),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.mobileDataDownload),
          ),
        ],
      ),
    );
    if (go != true) return;
  }
  await ref.read(downloadStarterProvider(url).notifier).start(preview, option);
}
