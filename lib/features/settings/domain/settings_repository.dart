import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';

/// Stored user choices.
abstract interface class SettingsRepository {
  /// The saved settings; defaults for anything never set or unreadable.
  Future<AppSettings> load();

  Future<Result<void>> save(AppSettings settings);

  /// Lets the user choose a folder. Its picker document id
  /// (`primary:Download/Videos`), or null if they backed out.
  Future<Result<String?>> pickFolder();

  /// Sites the user signed in to, so downloads use the account, e.g.
  /// `instagram.com`.
  Future<Result<List<String>>> signedInSites();

  /// Opens a page to sign in at [url]; returns the sites signed in to after.
  Future<Result<List<String>>> signIn(String url);

  /// Forgets the sign-in to [site]; returns the sites still signed in to.
  Future<Result<List<String>>> signOut(String site);
}
