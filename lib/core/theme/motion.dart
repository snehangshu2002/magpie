import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A spring expressed as a [Curve], so implicit animations (`AnimatedSize`,
/// `AnimatedSwitcher`, `AnimatedScale`, …) can move like a physical object.
///
/// Use it with `duration: curve.response`. The raw spring is only ~98.6%
/// settled after one response time, so the curve is rescaled to land exactly
/// on 1 there instead of snapping on the last frame.
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

  /// The spring's value after one [response]; divides the curve to reach 1.
  late final double _end = _simulation.x(
    response.inMicroseconds / Duration.microsecondsPerSecond,
  );

  @override
  double transformInternal(double t) =>
      _simulation.x(
        t * response.inMicroseconds / Duration.microsecondsPerSecond,
      ) /
      _end;
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
