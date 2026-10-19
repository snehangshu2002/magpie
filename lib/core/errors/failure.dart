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
  const factory unknown({String? detail}) = UnknownFailure;
}
