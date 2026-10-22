import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

/// Typed error passed across layers instead of exceptions.
///
/// The UI shows `failure.message(l10n)` (see `failure_message.dart`);
/// `detail` is diagnostic text for logs and is never shown to users.
@freezed
sealed class Failure with _$Failure implements Exception {
  const factory unsupportedUrl({String? detail}) = UnsupportedUrlFailure;
  const factory network({String? detail}) = NetworkFailure;
  const factory engine({String? detail}) = EngineFailure;
  const factory storage({String? detail}) = StorageFailure;
  const factory cancelled() = CancelledFailure;

  /// A saved file was moved or deleted outside the app.
  const factory notFound({String? detail}) = NotFoundFailure;

  /// No installed app can open or share the file.
  const factory noApp({String? detail}) = NoAppFailure;

  /// A video couldn't be made small enough for the size asked for.
  const factory tooLarge({String? detail}) = TooLargeFailure;

  /// Re-encoding a saved video failed.
  const factory encode({String? detail}) = EncodeFailure;

  /// The video, or every video of a playlist, was downloaded before ("Skip
  /// videos already downloaded").
  const factory nothingNew() = NothingNewFailure;

  /// The native side doesn't implement the call yet (e.g. a feature that
  /// hasn't shipped in this build).
  const factory unavailable({String? detail}) = UnavailableFailure;
  const factory unknown({String? detail}) = UnknownFailure;
}
