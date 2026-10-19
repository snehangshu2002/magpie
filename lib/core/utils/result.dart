import 'package:media_downloader/core/errors/failure.dart';

/// Return type of repository methods: a value or a typed [Failure].
sealed class Result<T> {
  const new();

  /// Returns the value or throws the [Failure]. Use in Riverpod providers,
  /// where the failure then surfaces as `AsyncError`.
  T getOrThrow() => switch (this) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
}

final class Ok<T> extends Result<T> {
  const new(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const new(this.failure);

  final Failure failure;
}
