import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/app.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled fonts (OFL) and the native downloader (GPL, PSF, Unlicense) ask
  // for their licence text to ship with the app; Dart packages are listed
  // automatically.
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in [
      ('Inter', 'fonts/Inter-OFL.txt'),
      ('Source Serif 4', 'fonts/SourceSerif4-OFL.txt'),
      ('youtubedl-android', 'licenses/GPL-3.0.txt'),
      // Built by Termux with --enable-gpl --enable-version3.
      ('FFmpeg', 'licenses/GPL-3.0.txt'),
      ('yt-dlp', 'licenses/yt-dlp-Unlicense.txt'),
      ('Python', 'licenses/Python-PSF.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/$file'));
    }
  });

  // No automatic retries: providers here call yt-dlp and the network, where
  // re-running a failed call rarely helps. Screens offer a retry instead.
  final container = ProviderContainer(retry: (_, _) => null);
  // The chosen theme and font apply from the first frame instead of
  // switching after it; the launch screen stays up meanwhile. Never hold it
  // for long: past the timeout the defaults show until settings load.
  await container
      .read(settingsProvider.future)
      .timeout(
        const Duration(seconds: 2),
        onTimeout: () => const AppSettings(),
      );
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
