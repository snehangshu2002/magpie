import 'package:flutter/material.dart';
import 'package:media_downloader/core/media/source_platform.dart';
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

    final scheme = theme.colorScheme;

    // A hairline at rest; sage while typing.
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) => TweenAnimationBuilder<double>(
        tween: Tween(end: focusNode.hasFocus ? 1 : 0),
        duration: duration,
        curve: AppMotion.standard,
        child: child,
        builder: (context, t, child) => Material(
          color: scheme.surfaceContainer,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Color.lerp(
                scheme.outlineVariant.withValues(alpha: 0.3),
                scheme.primaryContainer,
                t,
              )!,
              width: 1 + 0.5 * t,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            children: [
              // Fixed slot so the text doesn't shift between icon and badge.
              SizedBox.square(
                dimension: 32,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: AppMotion.standard,
                    switchOutCurve: AppMotion.standard,
                    transitionBuilder: popIn,
                    child: platform == null
                        ? Icon(
                            Icons.link_rounded,
                            key: const ValueKey(null),
                            size: 22,
                            color: scheme.outline,
                          )
                        : PlatformBadge(
                            key: ValueKey(platform),
                            platform: platform,
                            size: 32,
                          ),
                  ),
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
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
                          key: const ValueKey('edit'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PressableScale(
                              child: IconButton(
                                tooltip: l10n.intakeClear,
                                icon: const Icon(Icons.close_rounded),
                                onPressed: onClear,
                              ),
                            ),
                            AnimatedSize(
                              duration: duration,
                              curve: AppMotion.standard,
                              child: AnimatedSwitcher(
                                duration: duration,
                                switchInCurve: AppMotion.standard,
                                switchOutCurve: AppMotion.standard,
                                transitionBuilder: popIn,
                                child: canSubmit
                                    ? PressableScale(
                                        key: const ValueKey('go'),
                                        child: IconButton.filled(
                                          tooltip: l10n.intakeFetch,
                                          style: IconButton.styleFrom(
                                            backgroundColor:
                                                scheme.primaryContainer,
                                            foregroundColor:
                                                scheme.onPrimaryContainer,
                                          ),
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                          ),
                                          onPressed: onSubmit,
                                        ),
                                      )
                                    : const SizedBox(key: ValueKey('nogo')),
                              ),
                            ),
                          ],
                        )
                      : PressableScale(
                          key: const ValueKey('paste'),
                          child: FilledButton.icon(
                            onPressed: onPaste,
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primaryContainer,
                              foregroundColor: scheme.onPrimaryContainer,
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              textStyle: theme.textTheme.labelLarge,
                            ),
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
      ),
    );
  }
}
