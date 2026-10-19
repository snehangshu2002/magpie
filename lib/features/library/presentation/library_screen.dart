import 'package:flutter/material.dart';
import 'package:media_downloader/l10n/l10n.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navLibrary)),
      body: Center(child: Text(l10n.libraryEmpty)),
    );
  }
}
