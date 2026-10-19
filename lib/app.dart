import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/router/app_router.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/features/settings/presentation/engine_version_provider.dart';
import 'package:media_downloader/l10n/l10n.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start preparing yt-dlp at launch; the first run after install unpacks
    // the bundled Python and takes a few seconds.
    ref.listen(engineVersionProvider, (_, _) {});

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(appRouterProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
