import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/app.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled fonts are under the OFL, which asks for its text to ship with them.
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [
      ('Inter', 'Inter-OFL.txt'),
      ('Source Serif 4', 'SourceSerif4-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$file'));
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
