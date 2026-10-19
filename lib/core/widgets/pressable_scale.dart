import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:media_downloader/core/theme/motion.dart';

/// Shrinks [child] slightly the instant a pointer touches it, so presses
/// feel physical. Feedback starts on pointer-down, not on release, and
/// settles back with the standard spring. With animations disabled the
/// child dips in opacity instead.
class PressableScale extends StatefulWidget {
  const new({
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
    super.key,
  });

  final Widget child;
  final bool enabled;

  /// Scale while pressed; large surfaces look better with a subtler value.
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  var _pressed = false;
  Offset? _downAt;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  void _down(PointerDownEvent e) {
    _downAt = e.position;
    _set(true);
  }

  // A scrollable that claims the drag sends no cancel, so release once the
  // pointer leaves the touch slop.
  void _move(PointerMoveEvent e) {
    final start = _downAt;
    if (start != null && (e.position - start).distance > kTouchSlop) {
      _set(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pressed = widget.enabled && _pressed;
    return Listener(
      onPointerDown: widget.enabled ? _down : null,
      onPointerMove: _move,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: reduce
          ? Opacity(opacity: pressed ? 0.6 : 1, child: widget.child)
          : AnimatedScale(
              scale: pressed ? widget.scale : 1,
              duration: pressed ? AppMotion.press : AppMotion.standard.response,
              curve: pressed ? Curves.easeOut : AppMotion.standard,
              child: widget.child,
            ),
    );
  }
}
