import 'package:flutter/foundation.dart';
import 'package:media_downloader/features/image_edit/data/image_edit_repository_impl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'image_edit_providers.g.dart';

/// Width and height in pixels of the image at [fileUri], as it is shown.
@riverpod
Future<({int width, int height})> imageProbe(Ref ref, String fileUri) async =>
    (await ref.read(imageEditRepositoryProvider).probe(fileUri)).getOrThrow();

/// A sharper picture of the image at [fileUri] than the Library's, for the
/// sheet's preview; null when there is none.
@riverpod
Future<Uint8List?> imagePreview(Ref ref, String fileUri) =>
    ref.read(imageEditRepositoryProvider).preview(fileUri);
