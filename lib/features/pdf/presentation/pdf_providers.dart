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
