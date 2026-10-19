import 'package:freezed_annotation/freezed_annotation.dart';

part 'stored_file.freezed.dart';
part 'stored_file.g.dart';

/// A saved file that still exists; item of the `queryFiles` reply.
@freezed
abstract class StoredFile with _$StoredFile {
  const factory({
    required String uri,
    String? name,

    /// Bytes; null if the system doesn't know.
    int? size,
    String? mimeType,
  }) = _StoredFile;

  factory fromJson(Map<String, dynamic> json) => _$StoredFileFromJson(json);
}
