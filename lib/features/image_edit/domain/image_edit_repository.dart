import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/image_edit/domain/image_plan.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';

/// Makes resized, compressed or converted copies of images.
abstract interface class ImageEditRepository {
  /// Lets the user pick images on the phone; their content URIs, none if
  /// they backed out.
  Future<Result<List<String>>> pick();

  /// Width and height in pixels of the image at [fileUri], as it is shown.
  Future<Result<({int width, int height})>> probe(String fileUri);

  /// Saves a copy of [item] in [targetDir] as [name], [width] x [height]
  /// pixels in [format] at [quality] (1-100), no bigger than [targetBytes]
  /// when given. First it is turned [rotate] degrees clockwise and cut to
  /// [crop] (in the turned image's pixels). The copy joins the Library and
  /// is returned.
  Future<Result<LibraryItem>> edit({
    required String id,
    required LibraryItem item,
    required String targetDir,
    required String name,
    required ImageFormat format,
    required int width,
    required int height,
    required int quality,
    int? targetBytes,
    int rotate = 0,
    ImageCrop? crop,
  });
}
