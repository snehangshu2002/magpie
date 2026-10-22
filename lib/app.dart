import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/router/app_router.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
import 'package:media_downloader/l10n/l10n.dart';

class App extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start preparing yt-dlp at launch; the first run after install unpacks
    // the bundled Python and takes a few seconds.
    ref
      ..listen(engineVersionProvider, (_, _) {})
      ..listen(engineAutoUpdateProvider, (_, _) {})
      ..listen(appearanceSyncProvider, (_, _) {})
      // Records downloads that finished while the app was closed.
      ..listen(librarySyncProvider, (_, _) {});

    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final fontFamily = settings.font.family;
    final seed = switch (settings.themeColor.seed) {
      final argb? => Color(argb),
      null => null,
    };

    // Wallpaper colours exist on Android 12+; elsewhere both are null.
    return DynamicColorBuilder(
      builder: (lightWallpaper, darkWallpaper) => MaterialApp.router(
        onGenerateTitle: (context) => context.l10n.appTitle,
        theme: AppTheme.light(
          fontFamily: fontFamily,
          wallpaper: settings.wallpaperColors ? lightWallpaper : null,
          seed: seed,
        ),
        darkTheme: AppTheme.dark(
          fontFamily: fontFamily,
          wallpaper: settings.wallpaperColors ? darkWallpaper : null,
          seed: seed,
          pureBlack: settings.pureBlack,
        ),
        themeMode: switch (settings.appearance) {
          AppearanceMode.system => ThemeMode.system,
          AppearanceMode.light => ThemeMode.light,
          AppearanceMode.dark => ThemeMode.dark,
        },
        themeAnimationCurve: AppMotion.standard,
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : AppMotion.standard.response,
        routerConfig: ref.watch(appRouterProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
