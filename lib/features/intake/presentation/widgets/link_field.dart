import 'package:flutter/material.dart';
import 'package:media_downloader/core/media/source_platform.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/widgets/platform_badge.dart';
import 'package:media_downloader/core/widgets/pressable_scale.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// The link box: the recognized site's logo, the text field, and Paste
/// (when empty) or Clear + Go (when filled).
class LinkField extends StatelessWidget {
  const new({
    required this.controller,
    required this.focusNode,
    required this.platform,
    required this.hasText,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onPaste,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Site recognized from the text so far; null shows a neutral link glyph.
  final SourcePlatform? platform;
  final bool hasText;

  /// False once the link's formats are already showing.
  final bool canSubmit;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final duration = AppMotion.durationOf(context);

    Widget popIn(Widget child, Animation<double> animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
        child: child,
      ),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: AppTheme.shape(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: duration,
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.standard,
              transitionBuilder: popIn,
              child: PlatformBadge(
                key: ValueKey(platform),
                platform: platform,
                size: 44,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmit(),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration.collapsed(
                  hintText: l10n.intakeFieldHint,
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedSize(
              duration: duration,
              curve: AppMotion.standard,
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: AppMotion.standard,
                switchOutCurve: AppMotion.standard,
                transitionBuilder: popIn,
                child: hasText
                    ? Row(
                        key: ValueKey(canSubmit),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: l10n.intakeClear,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: onClear,
                          ),
                          if (canSubmit)
                            IconButton.filled(
                              tooltip: l10n.intakeFetch,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              onPressed: onSubmit,
                            ),
                        ],
                      )
                    : PressableScale(
                        key: const ValueKey('paste'),
                        child: FilledButton.tonalIcon(
                          onPressed: onPaste,
                          icon: const Icon(
                            Icons.content_paste_rounded,
                            size: 18,
                          ),
                          label: Text(l10n.intakePaste),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
