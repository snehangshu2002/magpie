import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/app.dart';
import 'package:media_downloader/core/errors/failure.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/core/utils/result.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/settings/data/engine_repository_impl.dart';
import 'package:media_downloader/features/settings/domain/engine_repository.dart';

import 'helpers/fake_library_repository.dart';

class _FakeEngineRepository implements EngineRepository {
  new(this.result);

  Result<String> result;

  @override
  Future<Result<String>> initialize() async => result;
}

void main() {
  Future<void> pumpApp(WidgetTester tester, EngineRepository repository) =>
      tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            engineRepositoryProvider.overrideWithValue(repository),
            sharedTextProvider.overrideWith((ref) => const Stream.empty()),
            libraryRepositoryProvider.overrideWithValue(
              FakeLibraryRepository(),
            ),
          ],
          child: const App(),
        ),
      );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('settings shows the yt-dlp version', (tester) async {
    await pumpApp(tester, _FakeEngineRepository(const Ok('2026.01.01')));
    await openSettings(tester);

    expect(find.text('yt-dlp version'), findsOneWidget);
    expect(find.text('2026.01.01'), findsOneWidget);
  });

  testWidgets('settings shows a failure and retries on tap', (tester) async {
    final repository = _FakeEngineRepository(const Err(Failure.network()));
    await pumpApp(tester, repository);
    await openSettings(tester);

    expect(
      find.text('Network error. Check your connection and try again.'),
      findsOneWidget,
    );

    repository.result = const Ok('2026.01.01');
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('2026.01.01'), findsOneWidget);
  });
}
