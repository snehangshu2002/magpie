import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/app.dart';

void main() {
  runApp(
    // No automatic retries: providers here call yt-dlp and the network, where
    // re-running a failed call rarely helps. Screens offer a retry instead.
    ProviderScope(retry: (_, _) => null, child: const App()),
  );
}
