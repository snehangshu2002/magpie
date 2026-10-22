import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/core/theme/motion.dart';
import 'package:media_downloader/core/widgets/page_header.dart';
import 'package:media_downloader/features/download/domain/download_option.dart';
import 'package:media_downloader/features/download/presentation/media_providers.dart';
import 'package:media_downloader/features/download/presentation/start_download.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_bar.dart';
import 'package:media_downloader/features/download/presentation/widgets/download_panel.dart';
import 'package:media_downloader/features/download/presentation/widgets/media_preview_card.dart';
import 'package:media_downloader/features/intake/domain/detected_link.dart';
import 'package:media_downloader/features/intake/presentation/intake_controller.dart';
import 'package:media_downloader/features/intake/presentation/widgets/link_field.dart';
import 'package:media_downloader/features/intake/presentation/widgets/link_status.dart';
import 'package:media_downloader/features/intake/presentation/widgets/supported_platforms.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';
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
  void _keepEndInView(double bottomInset, Duration duration) {
    final grew = bottomInset > _bottomInset;
    _bottomInset = bottomInset;
    if (!grew || !_scroll.hasClients) return;
    final position = _scroll.position;
    final atEnd =
        position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1;
    if (!atEnd) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (duration == Duration.zero) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: duration, curve: AppMotion.standard);
      }
    });
  }

  /// Runs a user-initiated [action] and confirms with a light tap when it
  /// started showing a link. Shared links change state without this.
  void _commit(void Function() action) {
    final before = ref.read(intakeControllerProvider).submitted;
    action();
    final after = ref.read(intakeControllerProvider).submitted;
    if (after != null && after != before) {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted) _commit(() => _controller.pasteFromClipboard(data?.text));
  }

  Future<void> _downloadRightAway(Uri url, MediaPreview preview) async {
    // The Download bar, which follows the download, isn't built yet; without
    // a listener the starter would be disposed mid-start and lose it.
    final keep = ref.listenManual(downloadStarterProvider(url), (_, _) {});
    try {
      final settings = await ref.read(settingsProvider.future);
      final idle = ref.read(downloadStarterProvider(url)).value == null;
      if (!settings.downloadRightAway || !idle || !mounted) return;
      await startDownload(
        context,
        ref,
        url: url,
        preview: preview,
        option:
            ref.read(selectedDownloadOptionProvider(url)) ??
            preview.options.recommended,
      );
    } finally {
      // Let go once the bar, built in the next frame, listens instead.
      WidgetsBinding.instance.addPostFrameCallback((_) => keep.close());
    }
  }

  /// Outgoing children stay in the stack while they fade; they must not
  /// take taps.
  static Widget _layout(Widget? current, List<Widget> previous) => Stack(
    alignment: Alignment.topCenter,
    children: [
      for (final child in previous) IgnorePointer(child: child),
      ?current,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(intakeControllerProvider);
    final submitted = state.submitted;
    final previewProvider = submitted == null
        ? null
        : submitted.kind == LinkKind.playlist
        ? playlistPreviewProvider(submitted.uri, submitted.platform)
        : mediaPreviewProvider(submitted.uri, submitted.platform);
    final preview = previewProvider == null ? null : ref.watch(previewProvider);
    final duration = AppMotion.durationOf(context);

    // "Download right away": start the suggested choice once the link is read.
    if (previewProvider != null) {
      ref.listen(previewProvider, (previous, next) {
        if (next case AsyncData(:final value, isLoading: false)
            when previous?.value == null) {
          unawaited(_downloadRightAway(submitted!.uri, value));
        }
      });
    }

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
        if (next != null && next != previous && _focus.hasFocus) {
          _focus.unfocus();
        }
      })
      // A link recognized while typing (not set at once by Paste or Share).
      ..listen(intakeControllerProvider, (previous, next) {
        if (previous?.detected == null &&
            next.detected != null &&
            next.submitted == null) {
          unawaited(HapticFeedback.selectionClick());
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
          onRetry: () => ref.invalidate(previewProvider!),
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
          alignment: Alignment.bottomCenter,
          child: FadeTransition(opacity: animation, child: child),
        ),
        layoutBuilder: _layout,
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
          _keepEndInView(bottomInset, duration);
          final side = PageLayout.gutter(context);
          return CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverAppBar(
                pinned: true,
                titleSpacing: side,
                title: const BrandTitle(),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 12, side, 0),
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
                          : PageHeader(
                              title: l10n.intakeTitle,
                              subtitle: l10n.intakeHint,
                            ),
                    ),
                    LinkField(
                      controller: _text,
                      focusNode: _focus,
                      platform: state.detected?.platform,
                      hasText: state.input.isNotEmpty,
                      // Nothing to fetch for a link whose formats already show.
                      canSubmit:
                          submitted == null ||
                          state.detected?.uri != submitted.uri,
                      onChanged: _controller.edit,
                      onSubmit: () => _commit(_controller.submit),
                      onPaste: _paste,
                      onClear: _controller.clear,
                    ),
                    LinkStatus(
                      input: state.input,
                      detected: state.detected,
                      notice: state.notice,
                    ),
                    const SizedBox(height: 8),
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
                        layoutBuilder: _layout,
                        child: results,
                      ),
                    ),
                  ],
                ),
              ),
              // The share tip rests at the bottom of a tall screen rather
              // than leaving the lower half empty; it steps aside for results.
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, bottomInset + 24),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: AppMotion.standard,
                      switchOutCurve: AppMotion.standard,
                      child: submitted == null
                          ? const Padding(
                              key: ValueKey('tip'),
                              padding: EdgeInsets.only(top: 28),
                              child: ShareTip(),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
