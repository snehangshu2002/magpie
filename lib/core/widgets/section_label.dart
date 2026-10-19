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
    final label = theme.textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            // Screen readers get the original casing, not shouting capitals.
            child: Semantics(
              header: true,
              label: text,
              child: ExcludeSemantics(
                child: Text(
                  text.toUpperCase(),
                  style: label?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: (label.fontSize ?? 12) * 0.067,
                  ),
                ),
              ),
            ),
          ),
          if (trailing case final trailing?)
            Text(
              trailing,
              style: label?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
