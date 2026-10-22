import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_downloader/features/download/data/web_image.dart';
import 'package:media_downloader/features/download/domain/download_args.dart';
import 'package:media_downloader/features/settings/domain/app_settings.dart';
import 'package:media_downloader/features/settings/presentation/settings_providers.dart';

/// The image at [url] loaded through the user's proxy, IPv4 and browser
/// identity settings; [cacheWidth] decodes it at that width.
ImageProvider webImageOf(WidgetRef ref, String url, {int? cacheWidth}) =>
    ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      WebImage(
        url,
        options: networkArgs(
          ref.watch(settingsProvider).value ?? const AppSettings(),
        ),
      ),
    );
