import 'package:flutter/material.dart';
import 'package:media_downloader/core/widgets/page_header.dart';
import 'package:media_downloader/core/widgets/section_label.dart';
import 'package:media_downloader/features/tools/presentation/tool_entry.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Every photo and PDF tool, as cards; a tap picks files and opens it.
class ToolsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final side = PageLayout.gutter(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            titleSpacing: side,
            title: const BrandTitle(),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 32),
            sliver: SliverList.list(
              children: [
                PageHeader(title: l10n.toolsTitle, subtitle: l10n.toolsHint),
                SectionLabel(l10n.toolsPhotos),
                const ToolGrid(
                  entries: [ToolEntry.editPhotos, ToolEntry.imagesToPdf],
                ),
                const SizedBox(height: 24),
                SectionLabel(l10n.toolsPdf),
                const ToolGrid(entries: [ToolEntry.merge, ...ToolEntry.forPdf]),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.toolsPrivacy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
