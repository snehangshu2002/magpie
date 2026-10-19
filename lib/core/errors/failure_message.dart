import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/l10n/app_localizations.dart';

extension FailureMessage on Failure {
  String message(AppLocalizations l10n) => switch (this) {
    UnsupportedUrlFailure() => l10n.failureUnsupportedUrl,
    NetworkFailure() => l10n.failureNetwork,
    EngineFailure() => l10n.failureEngine,
    StorageFailure() => l10n.failureStorage,
    CancelledFailure() => l10n.failureCancelled,
    NotFoundFailure() => l10n.failureNotFound,
    NoAppFailure() => l10n.failureNoApp,
    UnavailableFailure() => l10n.failureUnavailable,
    UnknownFailure() => l10n.failureUnknown,
  };
}
