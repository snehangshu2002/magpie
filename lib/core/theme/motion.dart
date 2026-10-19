import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A spring expressed as a [Curve], so implicit animations (`AnimatedSize`,
/// `AnimatedSwitcher`, `AnimatedScale`, …) can move like a physical object.
///
/// Use it with `duration: curve.response`. A critically damped spring
/// (`bounce: 0`) is ~99% settled after one response time; the remaining
/// fraction is invisible.
class SpringCurve extends Curve {
  new({required this.response, this.bounce = 0})
    : _simulation = SpringSimulation(
        SpringDescription.withDurationAndBounce(
          duration: response,
          bounce: bounce,
        ),
        0,
        1,
        0,
      );

  /// How quickly the value reaches the target; not a fixed duration.
  final Duration response;

  /// 0 settles without overshoot; higher values bounce.
  final double bounce;

  final SpringSimulation _simulation;

  @override
  double transformInternal(double t) => _simulation.x(
    t * response.inMicroseconds / Duration.microsecondsPerSecond,
  );
}

/// App-wide motion values.
abstract final class AppMotion {
  /// Default for UI that appears, grows or moves: no overshoot.
  static final standard = SpringCurve(
    response: const Duration(milliseconds: 350),
  );

  /// Press feedback; quick enough to feel attached to the finger.
  static const press = Duration(milliseconds: 100);

  /// [standard]'s response, or zero when the user turned animations off.
  static Duration durationOf(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : standard.response;
}
