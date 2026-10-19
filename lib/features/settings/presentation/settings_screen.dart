import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/platform/models/engine_update_result.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/download/domain/save_location.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

extension EngineReleaseChannelLabel on EngineReleaseChannel {
  String label(AppLocalizations l10n) => switch (this) {
    EngineReleaseChannel.stable => l10n.channelStable,
    EngineReleaseChannel.nightly => l10n.channelNightly,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    EngineReleaseChannel.stable => l10n.channelStableHint,
    EngineReleaseChannel.nightly => l10n.channelNightlyHint,
  };
}

class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final controller = ref.read(settingsProvider.notifier);

    ref.listen(engineUpdaterProvider, (_, next) {
      final message = switch (next) {
        AsyncData(
          value: EngineUpdateResult(
            status: EngineUpdateStatus.done,
            :final version,
          ),
        ) =>
          l10n.settingsEngineUpdated(version),
        AsyncData(
          value: EngineUpdateResult(status: EngineUpdateStatus.alreadyUpToDate),
        ) =>
          l10n.settingsEngineUpToDate,
        AsyncError(error: final Failure failure) => failure.message(l10n),
        AsyncError() => l10n.failureUnknown,
        _ => null,
      };
      if (message != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(
              l10n.navSettings,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.list(
              children: [
                SectionLabel(l10n.settingsDownloads),
                _Group(
                  children: [
                    _SettingTile(
                      title: l10n.settingsDefaultQuality,
                      subtitle: l10n.settingsDefaultQualityHint,
                      value: l10n.qualityLabel(settings.maxQuality),
                      onTap: () async {
                        final quality = await _choose(
                          context,
                          title: l10n.settingsDefaultQuality,
                          values: AppSettings.qualities,
                          selected: settings.maxQuality,
                          label: l10n.qualityLabel,
                        );
                        if (quality != null) {
                          await controller.change(
                            (s) => s.copyWith(maxQuality: quality),
                          );
                        }
                      },
                    ),
                    _SettingTile(
                      title: l10n.settingsPreferAudio,
                      subtitle: l10n.settingsPreferAudioHint,
                      trailing: Switch(
                        value: settings.preferAudioForMusic,
                        onChanged: (value) => _toggleAudio(controller, value),
                      ),
                      onTap: () => _toggleAudio(
                        controller,
                        !settings.preferAudioForMusic,
                      ),
                    ),
                    _SettingTile(
                      icon: Icons.folder_outlined,
                      title: l10n.settingsSaveLocation,
                      subtitle: l10n.settingsSaveLocationPath(saveRoot),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsEngine),
                _Group(
                  children: [
                    const _EngineVersionTile(),
                    _SettingTile(
                      title: l10n.settingsUpdateChannel,
                      subtitle: l10n.settingsUpdateChannelHint,
                      value: settings.engineChannel.label(l10n),
                      onTap: () async {
                        final channel = await _choose(
                          context,
                          title: l10n.settingsUpdateChannel,
                          values: EngineReleaseChannel.values,
                          selected: settings.engineChannel,
                          label: (c) => c.label(l10n),
                          hint: (c) => c.hint(l10n),
                        );
                        if (channel != null) {
                          await controller.change(
                            (s) => s.copyWith(engineChannel: channel),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsAbout),
                _Group(
                  children: [
                    _SettingTile(
                      icon: Icons.description_outlined,
                      title: l10n.settingsLicenses,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: l10n.appTitle,
                        applicationIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: ClipPath(
                            clipper: ShapeBorderClipper(
                              shape: AppTheme.shape(14),
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: 56,
                              height: 56,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.secondaryContainer,
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      size: 22,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    l10n.settingsFooter(l10n.appTitle),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _toggleAudio(Settings controller, bool value) {
    unawaited(HapticFeedback.selectionClick());
    unawaited(controller.change((s) => s.copyWith(preferAudioForMusic: value)));
  }

  /// A sheet listing [values]; returns the one tapped, or null.
  static Future<T?> _choose<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    String Function(T)? hint,
  }) => showModalBottomSheet<T>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              for (final value in values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  selected: value == selected,
                  title: Text(label(value)),
                  subtitle: hint == null ? null : Text(hint(value)),
                  trailing: value == selected
                      ? Icon(Icons.check_rounded, color: scheme.primary)
                      : null,
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    Navigator.pop(context, value);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The installed yt-dlp version, with a button to update it.
class _EngineVersionTile extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(engineVersionProvider);
    final updating = ref.watch(engineUpdaterProvider).isLoading;
    final scheme = Theme.of(context).colorScheme;

    return _SettingTile(
      title: l10n.settingsEngineVersion,
      subtitle: switch (version) {
        AsyncData(:final value) => value ?? l10n.settingsEngineBundled,
        AsyncError(error: final Failure failure) => failure.message(l10n),
        AsyncError() => l10n.failureUnknown,
        _ => l10n.loading,
      },
      trailing: version.hasError
          ? IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.retry,
              onPressed: () => ref.invalidate(engineVersionProvider),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
              ),
              // Stays enabled while updating so it keeps its colour; the
              // spinner says it's busy.
              onPressed: version.hasValue
                  ? () {
                      if (updating) return;
                      unawaited(HapticFeedback.lightImpact());
                      unawaited(ref.read(engineUpdaterProvider.notifier).run());
                    }
                  : null,
              icon: updating
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimaryContainer,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(l10n.settingsEngineUpdate),
            ),
    );
  }
}

/// Rounded card holding related settings, divided by hairlines.
class _Group extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainer,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// The current choice, shown before a chevron.
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = this.subtitle;
    final value = this.value;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        child: Row(
          children: [
            if (icon case final icon?) ...[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                ),
                child: Icon(icon, size: 22, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (value != null) ...[
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ] else if (trailing case final trailing?)
              trailing
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
