import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:media_downloader/l10n/l10n.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(engineVersionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(l10n.settingsEngineVersion),
            subtitle: Text(switch (version) {
              AsyncData(:final value) => value,
              AsyncError(error: final Failure failure) => failure.message(l10n),
              AsyncError() => l10n.failureUnknown,
              _ => l10n.loading,
            }),
            trailing: version.hasError
                ? IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: l10n.retry,
                    onPressed: () => ref.invalidate(engineVersionProvider),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
