import 'package:flutter/material.dart';
import 'package:media_downloader/l10n/l10n.dart';

class IntakeScreen extends StatelessWidget {
  const IntakeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.intakeHint, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
