import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_info.freezed.dart';
part 'playlist_info.g.dart';

/// Reply to `fetchPlaylist`: the playlist and its items, not looked up one
/// by one.
@freezed
abstract class PlaylistInfo with _$PlaylistInfo {
  const factory({
    required String title,
    required String extractor,
    String? thumbnail,
    @Default(<PlaylistEntry>[]) List<PlaylistEntry> entries,
  }) = _PlaylistInfo;

  factory fromJson(Map<String, dynamic> json) => _$PlaylistInfoFromJson(json);
}

/// One item of a playlist, in order.
@freezed
abstract class PlaylistEntry with _$PlaylistEntry {
  const factory({String? title, int? duration, String? thumbnail}) =
      _PlaylistEntry;

  factory fromJson(Map<String, dynamic> json) => _$PlaylistEntryFromJson(json);
}
