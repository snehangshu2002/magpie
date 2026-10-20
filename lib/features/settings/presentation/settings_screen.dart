import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/page_header.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:media_downloader/features/updater/presentation/update_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';
import 'package:simple_icons/simple_icons.dart';

extension AppearanceModeLabel on AppearanceMode {
  String label(AppLocalizations l10n) => switch (this) {
    AppearanceMode.system => l10n.themeSystem,
    AppearanceMode.light => l10n.themeLight,
    AppearanceMode.dark => l10n.themeDark,
  };
}

extension AppFontLabel on AppFont {
  String label(AppLocalizations l10n) => switch (this) {
    AppFont.system => l10n.fontSystem,
    AppFont.sans => l10n.fontSans,
    AppFont.serif => l10n.fontSerif,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    AppFont.system => l10n.fontSystemHint,
    AppFont.sans => l10n.fontSansHint,
    AppFont.serif => l10n.fontSerifHint,
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

    final side = PageLayout.gutter(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            titleSpacing: side,
            title: const BrandTitle(),
            actions: [
              IconButton(
                tooltip: l10n.settingsSourceCode,
                icon: const Icon(SimpleIcons.github, size: 22),
                onPressed: () =>
                    _openUrl(context, ref, 'https://github.com/$projectRepo'),
              ),
              SizedBox(width: side - 8),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 32),
            sliver: SliverList.list(
              children: [
                PageHeader(
                  title: l10n.settingsTitle,
                  subtitle: l10n.settingsHint,
                ),
                SectionLabel(l10n.settingsAppearance),
                _Group(
                  children: [
                    _SettingTile(
                      title: l10n.settingsTheme,
                      value: settings.appearance.label(l10n),
                      onTap: () async {
                        final mode = await _choose(
                          context,
                          title: l10n.settingsTheme,
                          values: AppearanceMode.values,
                          selected: settings.appearance,
                          label: (m) => m.label(l10n),
                        );
                        if (mode != null) {
                          await controller.change(
                            (s) => s.copyWith(appearance: mode),
                          );
                        }
                      },
                    ),
                    _SettingTile(
                      title: l10n.settingsFont,
                      value: settings.font.label(l10n),
                      onTap: () async {
                        final font = await _choose(
                          context,
                          title: l10n.settingsFont,
                          values: AppFont.values,
                          selected: settings.font,
                          label: (f) => f.label(l10n),
                          hint: (f) => f.hint(l10n),
                          // Each choice is shown in its own font.
                          style: (f) => TextStyle(fontFamily: f.family),
                        );
                        if (font != null) {
                          await controller.change(
                            (s) => s.copyWith(font: font),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsDownloads),
                _Group(
                  children: [
                    _SettingTile(
                      title: l10n.settingsDefaultQuality,
                      subtitle: l10n.settingsDefaultQualityHint,
                      value: _maxQualityLabel(l10n, settings.maxQuality),
                      onTap: () async {
                        final quality = await _choose(
                          context,
                          title: l10n.settingsDefaultQuality,
                          values: AppSettings.qualities,
                          selected: settings.maxQuality,
                          label: (q) => _maxQualityLabel(l10n, q),
                          hint: (q) => q == bestAvailableQuality
                              ? l10n.qualityBestHint
                              : null,
                        );
                        if (quality != null) {
                          await controller.change(
                            (s) => s.copyWith(maxQuality: quality),
                          );
                        }
                      },
                    ),
                    MergeSemantics(
                      child: _SettingTile(
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
                    ),
                    _SettingTile(
                      icon: Icons.folder_outlined,
                      title: l10n.settingsSaveLocation,
                      subtitle: l10n.settingsSaveLocationHint(
                        settings.saveFolder,
                      ),
                      onTap: () => _pickSaveFolder(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsUpdates),
                const _Group(children: [_AutoUpdateTile()]),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsAbout),
                _Group(
                  children: [
                    const _VersionTile(),
                    _SettingTile(
                      icon: SimpleIcons.github,
                      title: l10n.settingsDeveloper,
                      subtitle: 'github.com/$projectOwner',
                      onTap: () => _openUrl(
                        context,
                        ref,
                        'https://github.com/$projectOwner',
                      ),
                    ),
                    _SettingTile(
                      icon: Icons.description_outlined,
                      title: l10n.settingsLicenses,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: l10n.appTitle,
                        applicationVersion: ref.read(appVersionProvider).value,
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

  /// Opens the folder picker and says how it went.
  static Future<void> _pickSaveFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final String? message;
    try {
      message = switch (await ref
          .read(settingsProvider.notifier)
          .pickSaveFolder()) {
        SaveFolderPick.changed => l10n.saveFolderChanged(
          ref.read(settingsProvider).value?.saveFolder ?? '',
        ),
        SaveFolderPick.outsideDownload => l10n.saveFolderOutsideDownload,
        SaveFolderPick.cancelled => null,
      };
    } on Failure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message(l10n))));
      return;
    }
    if (message == null) return;
    unawaited(HapticFeedback.selectionClick());
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens [url] in the browser, or says why it couldn't.
  static Future<void> _openUrl(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(updateRepositoryProvider).open(url);
    if (opened case Err(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
    }
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
    String? Function(T)? hint,
    TextStyle? Function(T)? style,
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
                  title: Text(label(value), style: style?.call(value)),
                  subtitle: switch (hint?.call(value)) {
                    final hint? => Text(hint, style: style?.call(value)),
                    null => null,
                  },
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

/// Updates happen by themselves at launch; this only says how the last one
/// went, and offers to try again when it failed.
class _AutoUpdateTile extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final update = ref.watch(engineAutoUpdateProvider);

    return _SettingTile(
      icon: Icons.autorenew_rounded,
      title: l10n.settingsAutoUpdate,
      subtitle: switch (update) {
        AsyncLoading() => l10n.settingsAutoUpdateChecking,
        AsyncError() => l10n.settingsAutoUpdateFailed,
        _ => l10n.settingsAutoUpdateDone,
      },
      trailing: switch (update) {
        AsyncLoading() => SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
            semanticsLabel: l10n.loading,
          ),
        ),
        AsyncError() => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
          ),
          onPressed: () {
            unawaited(HapticFeedback.lightImpact());
            ref.invalidate(engineAutoUpdateProvider);
          },
          child: Text(l10n.retry),
        ),
        _ => Icon(Icons.check_circle_rounded, color: scheme.primary),
      },
    );
  }
}

/// The installed version; blank until the platform answers.
class _VersionTile extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _SettingTile(
      icon: Icons.info_outline_rounded,
      title: context.l10n.settingsVersion,
      trailing: Text(
        ref.watch(appVersionProvider).value ?? '',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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

/// "1080p", or "Best available" for no cap.
String _maxQualityLabel(AppLocalizations l10n, int quality) =>
    quality == bestAvailableQuality
    ? l10n.qualityBest
    : l10n.qualityLabel(quality);
