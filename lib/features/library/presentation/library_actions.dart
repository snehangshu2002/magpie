import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Shares [items] together; reports a failure in a snack bar. True if the
/// share sheet opened.
Future<bool> shareLibraryItems(
  BuildContext context,
  WidgetRef ref,
  List<LibraryItem> items,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(libraryRepositoryProvider).share(items);
  if (result case Err(:final failure)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.message(l10n))));
    return false;
  }
  return true;
}

/// Asks before deleting [items], then deletes them and says how it went.
/// True if the user went ahead.
Future<bool> deleteLibraryItems(
  BuildContext context,
  WidgetRef ref,
  List<LibraryItem> items,
) async {
  final l10n = context.l10n;
  final scheme = Theme.of(context).colorScheme;
  // The tiles go away once the files are deleted; keep what's needed after.
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(libraryRepositoryProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.libraryDeleteManyTitle(items.length)),
      content: Text(
        items.length == 1
            ? l10n.libraryDeleteBody(items.single.title)
            : l10n.libraryDeleteManyBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          child: Text(l10n.libraryDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  unawaited(HapticFeedback.mediumImpact());
  switch (await repository.delete(items)) {
    // None deleted: the user declined the system's prompt, which said so.
    case Ok(value: 0):
      break;
    case Ok(value: final count):
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              items.length == 1
                  ? l10n.libraryDeletedItem(items.single.title)
                  : l10n.libraryDeletedCount(count),
            ),
          ),
        );
    case Err(:final failure):
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message(l10n))));
  }
  return true;
}
