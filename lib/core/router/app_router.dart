import 'package:go_router/go_router.dart';
import 'package:media_downloader/core/router/app_shell.dart';
import 'package:media_downloader/features/intake/presentation/intake_screen.dart';
import 'package:media_downloader/features/library/presentation/library_screen.dart';
import 'package:media_downloader/features/settings/presentation/settings_screen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

abstract final class AppRoutes {
  static const intake = '/';
  static const library = '/library';
  static const settings = '/settings';
}

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.intake,
    // An unknown location (e.g. a stray deep link) lands on the Download tab.
    onException: (context, state, router) => router.go(AppRoutes.intake),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.intake,
                builder: (context, state) => const IntakeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.library,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
