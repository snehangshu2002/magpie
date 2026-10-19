import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Says a new version is out and offers to download its APK in the browser.
Future<void> showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  AppUpdate update,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(updateRepositoryProvider);
  final download = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.updateAvailableTitle),
      content: Text(l10n.updateAvailableBody(l10n.appTitle, update.version)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.updateLater),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.updateDownload),
        ),
      ],
    ),
  );
  if (download != true) return;
  if (await repository.download(update) case Err(:final failure)) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
  }
}
