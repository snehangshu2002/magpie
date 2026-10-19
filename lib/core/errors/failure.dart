import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

/// Typed error passed across layers instead of exceptions.
///
/// The UI shows `failure.message(l10n)` (see `failure_message.dart`);
/// [detail] is diagnostic text for logs and is never shown to users.
@freezed
sealed class Failure with _$Failure implements Exception {
  const factory Failure.unsupportedUrl({String? detail}) =
      UnsupportedUrlFailure;
  const factory Failure.network({String? detail}) = NetworkFailure;
  const factory Failure.engine({String? detail}) = EngineFailure;
  const factory Failure.storage({String? detail}) = StorageFailure;
  const factory Failure.cancelled() = CancelledFailure;
  const factory Failure.unknown({String? detail}) = UnknownFailure;
}
