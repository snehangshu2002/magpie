import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_downloader/core/platform/share_channel.dart';
import 'package:media_downloader/features/intake/domain/detect_link.dart';
import 'package:media_downloader/features/intake/domain/detected_link.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'intake_controller.freezed.dart';
part 'intake_controller.g.dart';

/// A problem with what the user entered, shown under the link box.
enum IntakeNotice { invalidLink, clipboardEmpty }

@freezed
abstract class IntakeState with _$IntakeState {
  const factory({
    @Default('') String input,

    /// Recognized on every keystroke, before anything is fetched.
    DetectedLink? detected,

    /// The link whose formats are shown. Set only by an explicit action
    /// (Paste, Share, Go) so typing never starts yt-dlp.
    DetectedLink? submitted,
    IntakeNotice? notice,
  }) = _IntakeState;
}

/// State of the link box on the Download screen.
@Riverpod(keepAlive: true)
class IntakeController extends _$IntakeController {
  @override
  IntakeState build() {
    ref.listen(sharedTextProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        _take(value, IntakeNotice.invalidLink);
      }
    });
    return const IntakeState();
  }

  void edit(String input) {
    final detected = detectLink(input);
    final submitted = state.submitted;
    state = IntakeState(
      input: input,
      detected: detected,
      submitted: submitted != null && detected?.uri == submitted.uri
          ? submitted
          : null,
    );
  }

  /// Fills the box from the clipboard and fetches at once: pasting a link
  /// is already a clear intent.
  void pasteFromClipboard(String? text) =>
      _take(text ?? '', IntakeNotice.clipboardEmpty);

  void submit() {
    final detected = state.detected;
    if (detected == null) {
      if (state.input.trim().isNotEmpty) {
        state = state.copyWith(notice: IntakeNotice.invalidLink);
      }
    } else {
      state = state.copyWith(submitted: detected, notice: null);
    }
  }

  void clear() => state = const IntakeState();

  void _take(String text, IntakeNotice noLink) {
    final detected = detectLink(text);
    if (detected == null) {
      state = state.copyWith(notice: noLink);
      return;
    }
    // Shared text often wraps the link in a sentence; keep just the link.
    edit(detected.uri.toString());
    submit();
  }
}
