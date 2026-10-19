import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/features/library/data/library_repository_impl.dart';
import 'package:media_downloader/features/library/presentation/library_providers.dart';

import '../../../helpers/fake_library_repository.dart';

void main() {
  late FakeLibraryRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeLibraryRepository();
    container = ProviderContainer(
      overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('a burst of storage changes syncs once, after it settles', (
    tester,
  ) async {
    await container.read(librarySyncProvider.future);
    expect(repository.syncs, 1);

    for (var i = 0; i < 5; i++) {
      repository.filesChangedController.add(null);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repository.syncs, 1);

    await tester.pump(librarySyncDebounce);
    expect(repository.syncs, 2);
  });

  testWidgets('coming back to the app syncs', (tester) async {
    await container.read(librarySyncProvider.future);

    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(repository.syncs, 2);
  });
}
