import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'appearance_channel.g.dart';

/// Tells Android the theme chosen in Settings, so the launch screen drawn
/// before Flutter starts matches it (Android 12+).
class AppearanceChannel {
  new({MethodChannel? methods})
    : _methods = methods ?? const MethodChannel(channelName);

  static const channelName = 'app/appearance';

  final MethodChannel _methods;

  /// [mode] is `system`, `light` or `dark`.
  Future<void> setNightMode(String mode) =>
      _methods.invokeMethod<void>('setNightMode', {'mode': mode});
}

@Riverpod(keepAlive: true)
AppearanceChannel appearanceChannel(Ref ref) => AppearanceChannel();
