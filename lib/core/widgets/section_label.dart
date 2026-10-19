import 'package:flutter/material.dart';

/// Small uppercase heading above a group of items, e.g. "TODAY".
class SectionLabel extends StatelessWidget {
  const new(this.text, {this.trailing, super.key});

  final String text;

  /// Short note at the end of the line, e.g. "1 active".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          if (trailing case final trailing?)
            Text(
              trailing,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
