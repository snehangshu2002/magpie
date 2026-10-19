import 'package:flutter/widgets.dart';
import 'package:media_downloader/core/theme/motion.dart';

/// Shrinks [child] slightly the instant a pointer touches it, so presses
/// feel physical. Feedback starts on pointer-down, not on release.
class PressableScale extends StatefulWidget {
  const new({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  var _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.enabled && !MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: animate ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: AppMotion.press,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
