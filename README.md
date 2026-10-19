# Magpie

An open-source Android app that downloads videos, audio and images from sites
supported by [yt-dlp](https://github.com/yt-dlp/yt-dlp) and saves them to the
device's shared storage.

Built with Flutter; downloads run natively through
[youtubedl-android](https://github.com/yausername/youtubedl-android).

**Status:** early development, not yet usable. See `CLAUDE.md` for the
architecture, the platform channel contract and the v1 scope.

## Requirements

- Flutter stable (Dart 3.13+)
- Android SDK with platform 37, JDK 17
- An Android 7.0+ (API 24) device or emulator

## Getting started

```sh
flutter pub get
dart run build_runner build
flutter run
```

Generated code is not committed, so re-run `dart run build_runner build`
after pulling changes to models, providers or the database.

Checks:

```sh
flutter analyze
flutter test
```

## Release builds

```sh
flutter build apk --release --split-per-abi
```

To sign with your own key, create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Without it, release builds are signed with the debug key and should not be
distributed.

## License

To be decided (must be compatible with yt-dlp and FFmpeg).
