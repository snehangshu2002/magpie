import 'package:flutter/widgets.dart';
import 'package:media_downloader/l10n/app_localizations.dart';

export 'package:media_downloader/l10n/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
