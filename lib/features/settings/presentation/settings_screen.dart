import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/errors/failure_message.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/utils/formatters.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/core/widgets/page_header.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/download/domain/download_args.dart';
import 'package:media_downloader/features/download/domain/suggest_download_options.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/features/updater/data/update_repository_impl.dart';
import 'package:media_downloader/features/updater/domain/app_update.dart';
import 'package:media_downloader/features/updater/presentation/update_providers.dart';
import 'package:media_downloader/features/updater/presentation/update_sheet.dart';
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
                    _switch(
                      controller,
                      title: l10n.settingsWallpaperColors,
                      subtitle: l10n.settingsWallpaperColorsHint,
                      value: settings.wallpaperColors,
                      update: (s, v) => s.copyWith(wallpaperColors: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsPureBlack,
                      subtitle: l10n.settingsPureBlackHint,
                      value: settings.pureBlack,
                      update: (s, v) => s.copyWith(pureBlack: v),
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
                    _SettingTile(
                      icon: Icons.library_music_outlined,
                      title: l10n.settingsAudioLocation,
                      subtitle: settings.audioFolder.isEmpty
                          ? l10n.settingsAudioLocationSame
                          : l10n.settingsSaveLocationHint(settings.audioFolder),
                      onTap: () async {
                        final separate = await _choose(
                          context,
                          title: l10n.settingsAudioLocation,
                          values: const [false, true],
                          selected: settings.audioFolder.isNotEmpty,
                          label: (v) => v
                              ? l10n.settingsAudioLocationPick
                              : l10n.settingsAudioLocationSame,
                        );
                        if (separate == null || !context.mounted) return;
                        if (separate) {
                          await _pickSaveFolder(context, ref, audio: true);
                        } else {
                          await controller.change(
                            (s) => s.copyWith(audioFolder: ''),
                          );
                        }
                      },
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsRightAway,
                      subtitle: l10n.settingsRightAwayHint,
                      value: settings.downloadRightAway,
                      update: (s, v) => s.copyWith(downloadRightAway: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsMobileData,
                      subtitle: l10n.settingsMobileDataHint,
                      value: settings.askOnMobileData,
                      update: (s, v) => s.copyWith(askOnMobileData: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsSkipDownloaded,
                      subtitle: l10n.settingsSkipDownloadedHint,
                      value: settings.skipDownloaded,
                      update: (s, v) => s.copyWith(skipDownloaded: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsKeepHistory,
                      subtitle: l10n.settingsKeepHistoryHint,
                      value: settings.keepHistory,
                      update: (s, v) => s.copyWith(keepHistory: v),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsFiles),
                _Group(
                  children: [
                    _SettingTile(
                      title: l10n.settingsAudioFormat,
                      subtitle: l10n.settingsAudioFormatHint,
                      value: settings.audioFormat.label(l10n),
                      onTap: () async {
                        final format = await _choose(
                          context,
                          title: l10n.settingsAudioFormat,
                          values: AudioFormat.values,
                          selected: settings.audioFormat,
                          label: (f) => f.label(l10n),
                        );
                        if (format != null) {
                          await controller.change(
                            (s) => s.copyWith(audioFormat: format),
                          );
                        }
                      },
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsCoverArt,
                      subtitle: l10n.settingsCoverArtHint,
                      value: settings.embedThumbnail,
                      update: (s, v) => s.copyWith(embedThumbnail: v),
                    ),
                    if (settings.embedThumbnail)
                      _switch(
                        controller,
                        title: l10n.settingsSquareCover,
                        subtitle: l10n.settingsSquareCoverHint,
                        value: settings.squareCover,
                        update: (s, v) => s.copyWith(squareCover: v),
                      ),
                    _switch(
                      controller,
                      title: l10n.settingsMetadata,
                      subtitle: l10n.settingsMetadataHint,
                      value: settings.embedMetadata,
                      update: (s, v) => s.copyWith(embedMetadata: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsSubtitles,
                      subtitle: l10n.settingsSubtitlesHint,
                      value: settings.subtitles,
                      update: (s, v) => s.copyWith(subtitles: v),
                    ),
                    if (settings.subtitles) ...[
                      _SettingTile(
                        title: l10n.settingsSubtitleLanguage,
                        value: languageName(settings.subtitleLanguage),
                        onTap: () async {
                          final lang = await _choose(
                            context,
                            title: l10n.settingsSubtitleLanguage,
                            values: AppSettings.subtitleLanguages,
                            selected: settings.subtitleLanguage,
                            label: languageName,
                          );
                          if (lang != null) {
                            await controller.change(
                              (s) => s.copyWith(subtitleLanguage: lang),
                            );
                          }
                        },
                      ),
                      _switch(
                        controller,
                        title: l10n.settingsAutoCaptions,
                        subtitle: l10n.settingsAutoCaptionsHint,
                        value: settings.autoCaptions,
                        update: (s, v) => s.copyWith(autoCaptions: v),
                      ),
                    ],
                    _switch(
                      controller,
                      title: l10n.settingsSkipSponsors,
                      subtitle: l10n.settingsSkipSponsorsHint,
                      value: settings.skipSponsors,
                      update: (s, v) => s.copyWith(skipSponsors: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsMkv,
                      subtitle: l10n.settingsMkvHint,
                      value: settings.saveAsMkv,
                      update: (s, v) => s.copyWith(saveAsMkv: v),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsAccounts),
                const _AccountsGroup(),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsAdvanced),
                _Group(
                  children: [
                    _SettingTile(
                      title: l10n.settingsSpeedLimit,
                      value: _speedLabel(l10n, settings.speedLimitKiB),
                      onTap: () async {
                        final limit = await _choose(
                          context,
                          title: l10n.settingsSpeedLimit,
                          values: AppSettings.speedLimits,
                          selected: settings.speedLimitKiB,
                          label: (k) => _speedLabel(l10n, k),
                        );
                        if (limit != null) {
                          await controller.change(
                            (s) => s.copyWith(speedLimitKiB: limit),
                          );
                        }
                      },
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsParallel,
                      subtitle: l10n.settingsParallelHint,
                      value: settings.parallelPieces,
                      update: (s, v) => s.copyWith(parallelPieces: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsAria2,
                      subtitle: l10n.settingsAria2Hint,
                      value: settings.aria2,
                      update: (s, v) => s.copyWith(aria2: v),
                    ),
                    _textTile(
                      context,
                      controller,
                      title: l10n.settingsProxy,
                      empty: l10n.settingsProxyNone,
                      hint: 'socks5://127.0.0.1:1080',
                      value: settings.proxy,
                      problem: (v) =>
                          isProxyUrl(v) ? null : l10n.settingsProxyInvalid,
                      update: (s, v) => s.copyWith(proxy: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsIpv4,
                      subtitle: l10n.settingsIpv4Hint,
                      value: settings.forceIpv4,
                      update: (s, v) => s.copyWith(forceIpv4: v),
                    ),
                    _textTile(
                      context,
                      controller,
                      title: l10n.settingsUserAgent,
                      empty: l10n.settingsUserAgentDefault,
                      hint: 'Mozilla/5.0 …',
                      value: settings.userAgent,
                      update: (s, v) => s.copyWith(userAgent: v),
                    ),
                    _textTile(
                      context,
                      controller,
                      title: l10n.settingsFileNames,
                      empty: l10n.settingsFileNamesDefault,
                      hint: '%(uploader)s - %(title)s',
                      value: settings.fileNameTemplate,
                      problem: (v) => isFileNameTemplate(v)
                          ? null
                          : l10n.settingsFileNamesInvalid,
                      update: (s, v) => s.copyWith(fileNameTemplate: v),
                    ),
                    _switch(
                      controller,
                      title: l10n.settingsSimpleNames,
                      subtitle: l10n.settingsSimpleNamesHint,
                      value: settings.simpleFileNames,
                      update: (s, v) => s.copyWith(simpleFileNames: v),
                    ),
                    _textTile(
                      context,
                      controller,
                      title: l10n.settingsExtraOptions,
                      empty: l10n.settingsExtraOptionsNone,
                      hint: '--no-part --concurrent-fragments 8',
                      value: settings.extraOptions,
                      problem: (v) => switch (extraOptionsProblem(v)) {
                        null => null,
                        '"' => l10n.settingsExtraOptionsQuote,
                        final option => l10n.settingsExtraOptionsReserved(
                          option,
                        ),
                      },
                      update: (s, v) => s.copyWith(extraOptions: v),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsUpdates),
                const _Group(children: [_AppUpdateTile(), _AutoUpdateTile()]),
                const SizedBox(height: 28),
                SectionLabel(l10n.settingsAbout),
                _Group(
                  children: [
                    _SettingTile(
                      icon: Icons.shield_outlined,
                      title: l10n.settingsPrivacy,
                      subtitle: l10n.settingsPrivacyHint,
                    ),
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

  /// Opens the folder picker and says how it went; with [audio], the folder
  /// is for audio only.
  static Future<void> _pickSaveFolder(
    BuildContext context,
    WidgetRef ref, {
    bool audio = false,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final String? message;
    try {
      message = switch (await ref
          .read(settingsProvider.notifier)
          .pickSaveFolder(audio: audio)) {
        SaveFolderPick.changed => l10n.saveFolderChanged(switch (ref
            .read(settingsProvider)
            .value) {
          final s? => audio ? s.audioFolder : s.saveFolder,
          null => '',
        }),
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

  /// A row with a switch; the whole row toggles it.
  static Widget _switch(
    Settings controller, {
    required String title,
    required bool value,
    // Takes the new value the way Switch.onChanged gives it.
    // ignore: avoid_positional_boolean_parameters
    required AppSettings Function(AppSettings, bool) update,
    String? subtitle,
  }) {
    void toggle({required bool on}) {
      unawaited(HapticFeedback.selectionClick());
      unawaited(controller.change((s) => update(s, on)));
    }

    return MergeSemantics(
      child: _SettingTile(
        title: title,
        subtitle: subtitle,
        trailing: Switch(
          value: value,
          onChanged: (on) => toggle(on: on),
        ),
        onTap: () => toggle(on: !value),
      ),
    );
  }

  /// A row showing free text ([empty] when there's none) that opens an
  /// editor; [problem] checks the text as it is typed.
  static Widget _textTile(
    BuildContext context,
    Settings controller, {
    required String title,
    required String empty,
    required String hint,
    required String value,
    required AppSettings Function(AppSettings, String) update,
    String? Function(String)? problem,
  }) => _SettingTile(
    title: title,
    subtitle: value.isEmpty ? empty : value,
    onTap: () async {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => _TextSettingDialog(
          title: title,
          hint: hint,
          initial: value,
          problem: problem,
        ),
      );
      if (text != null) await controller.change((s) => update(s, text.trim()));
    },
  );

  /// A sheet listing [values]; returns the one tapped, or null.
  static Future<T?> _choose<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T? selected,
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

/// Whether a newer Magpie is out: checks again on tap, and offers the update
/// (the same sheet as at launch) after "Later".
class _AppUpdateTile extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final check = ref.watch(appUpdateProvider);
    final version = ref.watch(appVersionProvider).value;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    );

    // A newer release found here shows the update sheet (AppShell listens).
    void checkAgain() {
      unawaited(HapticFeedback.lightImpact());
      ref.invalidate(appUpdateProvider);
    }

    return _SettingTile(
      icon: Icons.system_update_rounded,
      title: l10n.settingsAppUpdate,
      subtitle: switch (check) {
        AsyncLoading() => l10n.settingsAppUpdateChecking,
        AsyncData(value: final update?) => l10n.settingsAppUpdateAvailable(
          update.version,
        ),
        AsyncError() => l10n.settingsAppUpdateFailed,
        _ =>
          version == null
              ? l10n.settingsAppUpdateLatest
              : l10n.settingsAppUpdateCurrent(version),
      },
      onTap: check is AsyncLoading ? null : checkAgain,
      trailing: switch (check) {
        AsyncLoading() => SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
            semanticsLabel: l10n.loading,
          ),
        ),
        AsyncData(value: final update?) => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
          onPressed: () {
            unawaited(HapticFeedback.lightImpact());
            unawaited(showUpdateSheet(context, ref, update));
          },
          child: Text(l10n.settingsAppUpdateNow),
        ),
        AsyncError() => FilledButton(
          style: buttonStyle,
          onPressed: checkAgain,
          child: Text(l10n.retry),
        ),
        _ => FilledButton(
          style: buttonStyle,
          onPressed: checkAgain,
          child: Text(l10n.settingsAppUpdateCheck),
        ),
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

/// "2 MB/s", or "No limit".
String _speedLabel(AppLocalizations l10n, int kib) => kib == 0
    ? l10n.settingsSpeedLimitOff
    : l10n.perSecond(formatByteSize(kib * 1024, l10n));

/// A language's own name for itself; the code when it isn't listed.
String languageName(String code) => switch (code) {
  'en' => 'English',
  'es' => 'Español',
  'pt' => 'Português',
  'fr' => 'Français',
  'de' => 'Deutsch',
  'it' => 'Italiano',
  'ru' => 'Русский',
  'uk' => 'Українська',
  'pl' => 'Polski',
  'tr' => 'Türkçe',
  'ar' => 'العربية',
  'fa' => 'فارسی',
  'hi' => 'हिन्दी',
  'bn' => 'বাংলা',
  'ur' => 'اردو',
  'id' => 'Bahasa Indonesia',
  'vi' => 'Tiếng Việt',
  'th' => 'ไทย',
  'ja' => '日本語',
  'ko' => '한국어',
  'zh' => '中文',
  _ => code,
};

extension AudioFormatLabel on AudioFormat {
  String label(AppLocalizations l10n) => switch (this) {
    AudioFormat.original => l10n.audioFormatOriginal,
    AudioFormat.mp3 => 'MP3',
    AudioFormat.m4a => 'M4A',
    AudioFormat.opus => 'Opus',
  };
}

/// Sites the user can sign in to, and the page that signs them in.
const Map<SourcePlatform, String> _signInPages = {
  SourcePlatform.youtube: 'https://www.youtube.com/',
  SourcePlatform.instagram: 'https://www.instagram.com/accounts/login/',
  SourcePlatform.x: 'https://x.com/login',
  SourcePlatform.reddit: 'https://www.reddit.com/login/',
  SourcePlatform.facebook: 'https://www.facebook.com/login/',
};

/// The sites signed in to, each with Sign out, and a row to sign in to
/// another.
class _AccountsGroup extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final sites = ref.watch(signedInSitesProvider).value ?? const [];
    final notifier = ref.read(signedInSitesProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
      } on Failure catch (failure) {
        messenger.showSnackBar(SnackBar(content: Text(failure.message(l10n))));
      }
    }

    return _Group(
      children: [
        for (final site in sites)
          _SettingTile(
            icon: Icons.account_circle_outlined,
            title: site,
            subtitle: l10n.settingsSignedIn,
            trailing: TextButton(
              onPressed: () => guard(() => notifier.signOut(site)),
              child: Text(l10n.settingsSignOut),
            ),
          ),
        _SettingTile(
          icon: Icons.login_rounded,
          title: l10n.settingsSignIn,
          subtitle: l10n.settingsSignInHint,
          onTap: () async {
            final platform = await SettingsScreen._choose<SourcePlatform>(
              context,
              title: l10n.settingsSignIn,
              values: _signInPages.keys.toList(),
              selected: null,
              label: (p) => p.label(l10n),
            );
            if (platform == null) return;
            unawaited(HapticFeedback.lightImpact());
            await guard(() => notifier.signIn(_signInPages[platform]!));
          },
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Edits one line of text, saying what's wrong with it as it is typed.
class _TextSettingDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.hint,
    required this.initial,
    this.problem,
  });

  final String title;
  final String hint;
  final String initial;
  final String? Function(String)? problem;

  @override
  State<_TextSettingDialog> createState() => _TextSettingDialogState();
}

class _TextSettingDialogState extends State<_TextSettingDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final problem = widget.problem?.call(_text.text.trim());
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(hintText: widget.hint, errorText: problem),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        if (widget.initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(l10n.settingsClear),
          ),
        FilledButton(
          onPressed: problem == null
              ? () => Navigator.pop(context, _text.text)
              : null,
          child: Text(l10n.settingsSave),
        ),
      ],
    );
  }
}

/// "1080p", or "Best available" for no cap.
String _maxQualityLabel(AppLocalizations l10n, int quality) =>
    quality == bestAvailableQuality
    ? l10n.qualityBest
    : l10n.qualityLabel(quality);
