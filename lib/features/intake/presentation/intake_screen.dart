import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/theme/app_theme.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_bar.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_panel.dart';
import 'package:media_downloader/features/download/presentation/widgets/media_preview_card.dart';
import 'package:media_downloader/features/intake/domain/detected_link.dart';
import 'package:media_downloader/features/intake/presentation/intake_controller.dart';
import 'package:media_downloader/features/intake/presentation/widgets/link_field.dart';
import 'package:media_downloader/features/intake/presentation/widgets/link_status.dart';
import 'package:media_downloader/features/intake/presentation/widgets/supported_platforms.dart';
import 'package:media_downloader/l10n/l10n.dart';

/// Paste or share a link, see what it is, and pick what to save.
class IntakeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  double _bottomInset = 0;

  IntakeController get _controller =>
      ref.read(intakeControllerProvider.notifier);

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The Download bar grows when it shows a message. If the list was
  /// scrolled to its end, keep the end in view rather than under the bar.
  void _keepEndInView(double bottomInset) {
    final grew = bottomInset > _bottomInset;
    _bottomInset = bottomInset;
    if (!grew || !_scroll.hasClients) return;
    final position = _scroll.position;
    final atEnd =
        position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1;
    if (!atEnd) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted) _controller.pasteFromClipboard(data?.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(intakeControllerProvider);
    final submitted = state.submitted;
    final preview = submitted == null
        ? null
        : ref.watch(mediaPreviewProvider(submitted.uri, submitted.platform));
    final duration = AppMotion.durationOf(context);

    // Paste and Share change the text from outside the field.
    ref
      ..listen(intakeControllerProvider.select((s) => s.input), (_, input) {
        if (_text.text != input) {
          _text.value = TextEditingValue(
            text: input,
            selection: TextSelection.collapsed(offset: input.length),
          );
        }
      })
      ..listen(intakeControllerProvider.select((s) => s.submitted), (
        previous,
        next,
      ) {
        if (next != null && next != previous) {
          unawaited(HapticFeedback.lightImpact());
          _focus.unfocus();
        }
      });

    final Widget results;
    if (submitted == null) {
      results = const SupportedPlatforms(key: ValueKey('empty'));
    } else {
      final url = submitted.uri;
      results = switch (preview!) {
        AsyncValue(isLoading: true) || AsyncLoading() => LoadingPreview(
          key: ValueKey(('loading', url)),
          platform: submitted.platform,
        ),
        AsyncData(:final value) => DownloadPanel(
          key: ValueKey(('ready', url)),
          url: url,
          preview: value,
        ),
        AsyncError(:final error) => PreviewError(
          key: ValueKey(('error', url)),
          error: error,
          onRetry: () =>
              ref.invalidate(mediaPreviewProvider(url, submitted.platform)),
        ),
      };
    }
    final ready = switch (preview) {
      AsyncData(:final value, isLoading: false) => value,
      _ => null,
    };

    return Scaffold(
      // Content scrolls under the translucent Download bar.
      extendBody: true,
      bottomNavigationBar: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppMotion.standard,
        switchOutCurve: AppMotion.standard,
        transitionBuilder: (child, animation) => SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: ready == null
            ? const SizedBox(width: double.infinity)
            : DownloadBar(
                key: ValueKey(submitted!.uri),
                url: submitted.uri,
                preview: ready,
              ),
      ),
      // Builder: the bottom padding must come from inside the Scaffold, where
      // it includes the Download bar's height.
      body: Builder(
        builder: (context) {
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          _keepEndInView(bottomInset);
          return CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              const SliverAppBar(
                pinned: true,
                titleSpacing: 16,
                title: _BrandTitle(),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 24),
                sliver: SliverList.list(
                  children: [
                    // The introduction steps aside once there's a link to
                    // work on, giving the results the room.
                    AnimatedSize(
                      duration: duration,
                      curve: AppMotion.standard,
                      alignment: Alignment.topCenter,
                      child: submitted != null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      l10n.navDownload,
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l10n.intakeHint,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    LinkField(
                      controller: _text,
                      focusNode: _focus,
                      platform: state.detected?.platform,
                      hasText: state.input.isNotEmpty,
                      // Nothing to fetch for a playlist (the status explains
                      // why) or for a link whose formats already show.
                      canSubmit:
                          state.detected?.kind != LinkKind.playlist &&
                          (submitted == null ||
                              state.detected?.uri != submitted.uri),
                      onChanged: _controller.edit,
                      onSubmit: _controller.submit,
                      onPaste: _paste,
                      onClear: _controller.clear,
                    ),
                    LinkStatus(detected: state.detected, notice: state.notice),
                    const SizedBox(height: 20),
                    // Results grow down out of the link box and collapse back
                    // into it along the same path.
                    AnimatedSize(
                      duration: duration,
                      curve: AppMotion.standard,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: AppMotion.standard,
                        switchOutCurve: AppMotion.standard,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, -0.03),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, ?current],
                        ),
                        child: results,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The app's mark and name.
class _BrandTitle extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ClipPath(
          clipper: ShapeBorderClipper(shape: AppTheme.shape(10)),
          child: Image.asset(
            'assets/images/logo.png',
            width: 32,
            height: 32,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          context.l10n.appTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
