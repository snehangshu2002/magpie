import 'package:media_downloader/features/pdf/data/pdf_repository_impl.dart';
import 'package:media_downloader/features/pdf/domain/pdf_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pdf_providers.g.dart';

/// Pages, name and size of the PDF at [uri], opened with [password] when
/// it has one.
@riverpod
Future<PdfInfo> pdfInfo(Ref ref, String uri, {String? password}) async =>
    (await ref.read(pdfRepositoryProvider).info(uri, password: password))
        .getOrThrow();

/// Page [page] of the PDF at [uri] as a picture [size] pixels across.
@riverpod
Future<PdfPage> pdfPage(
  Ref ref,
  String uri,
  int page, {
  int size = 240,
  String? password,
}) async =>
    (await ref
            .read(pdfRepositoryProvider)
            .page(uri, page, size: size, password: password))
        .getOrThrow();
