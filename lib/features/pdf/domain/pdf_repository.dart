import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/domain/library_item.dart';
import 'package:media_downloader/features/pdf/domain/pdf_tool.dart';

/// What a PDF says about itself.
typedef PdfInfo = ({int? pages, String? name, int? size, bool protected});

/// The choices a [PdfTool] runs with; only the ones it reads matter.
final class PdfOptions {
  const new({
    this.pages,
    this.degrees = 90,
    this.text = '',
    this.place = TextPlace.bottomCenter,
    this.fontSize = 12,
    this.opacity = 1,
    this.diagonal = false,
    this.password,
    this.compression = PdfCompression.medium,
    this.a4 = false,
  });

  /// 1-based pages to work on; null is every page.
  final List<int>? pages;
  final int degrees;
  final String text;
  final TextPlace place;
  final double fontSize;
  final double opacity;

  /// Written large across the page, as a watermark.
  final bool diagonal;

  /// To open a protected PDF, or the new one for [PdfTool.protect].
  final String? password;
  final PdfCompression compression;

  /// Photos on A4 pages rather than pages the photo's size.
  final bool a4;
}

/// Edits PDFs and makes them from photos. Results join the Library.
abstract interface class PdfRepository {
  /// Lets the user pick PDFs, or photos when [images], one or [multiple];
  /// their content URIs, none if they backed out.
  Future<Result<List<String>>> pick({
    required bool images,
    required bool multiple,
  });

  /// Pages, name and size of the PDF at [uri]; `pages` is null when it
  /// needs a password ([password] is tried).
  Future<Result<PdfInfo>> info(String uri, {String? password});

  /// Runs [tool] over [items] (in order) with [options], saving the result
  /// in [targetDir] as [name]. The files made, in order; empty when
  /// [PdfTool.compress] couldn't make it smaller.
  Future<Result<List<LibraryItem>>> run({
    required PdfTool tool,
    required List<LibraryItem> items,
    required PdfOptions options,
    required String targetDir,
    required String name,
  });
}
