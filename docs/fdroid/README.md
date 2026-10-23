# Releasing on F-Droid

F-Droid builds Magpie from this repository's source on its own servers and
signs the APKs with its own key. You don't upload APKs: you submit a build
recipe (`com.snehangshu.magpie.yml`, next to this file) to
[fdroiddata](https://gitlab.com/fdroid/fdroiddata), and after it's accepted
F-Droid builds each new `v*` tag by itself.

## What the F-Droid build changes

The recipe builds the same code as GitHub releases, with three differences:

- **No self-updater**: `--dart-define=SELF_UPDATE=false` hides "Magpie
  updates" in Settings and skips the launch check (`selfUpdate` in
  `lib/features/updater/presentation/update_providers.dart`), and the recipe
  removes `REQUEST_INSTALL_PACKAGES`. An F-Droid install has F-Droid's
  signature, so a GitHub APK couldn't install over it anyway; F-Droid
  delivers the updates.
- **SQLite built from source**: by default `package:sqlite3` downloads a
  prebuilt library from GitHub during the build, which F-Droid doesn't
  allow. The recipe downloads the official SQLite amalgamation, checks its
  SHA3-256 and sets `hooks: user_defines: sqlite3: source: source` in
  `pubspec.yaml`.
- **Unsigned output**: the recipe deletes the `buildTypes` block so the
  release isn't debug-signed; F-Droid signs it.

yt-dlp still updates itself from GitHub at launch. That's why the recipe
declares the `NonFreeNet` anti-feature, as F-Droid does for Seal.

## Store listing

F-Droid reads the listing from `fastlane/metadata/android/en-US/`:

| File | What it is |
|---|---|
| `title.txt` | App name |
| `short_description.txt` | One line, at most 80 characters |
| `full_description.txt` | Full description (basic HTML) |
| `images/icon.png` | 512 × 512 icon |
| `images/phoneScreenshots/` | Screenshots, in name order |
| `changelogs/default.txt` | "What's new" for the current version, at most 500 characters |

Rewrite `changelogs/default.txt` for every release.

## Version codes

F-Droid reads the version from `pubspec.yaml` at the tag:
`version: 1.2.1+4` means versionName `1.2.1` and base code `4`. Flutter's
`--split-per-abi` adds 1000 × ABI to it: armeabi-v7a `1004`, arm64-v8a
`2004`, x86_64 `4004`. That's the recipe's `VercodeOperation`.

**Bump the `+N` on every release.** The GitHub workflow ignores it (it uses
the run number), but F-Droid only sees a new version when `+N` goes up.

## First submission

1. Bump `pubspec.yaml` to `version: 1.2.1+4`. Commit and push this F-Droid
   setup, then run the Release workflow. It creates the `v1.2.1` tag that
   the recipe builds. (`v1.2.0` and older tags don't contain this setup.)
2. Sign in to GitLab and fork https://gitlab.com/fdroid/fdroiddata.
3. In your fork, create a branch `com.snehangshu.magpie` and copy
   `com.snehangshu.magpie.yml` to `metadata/com.snehangshu.magpie.yml`.
4. Push it and open a merge request against `fdroid/fdroiddata` `master`,
   using the "App inclusion" template. Fill in its checklist: the app is
   MIT-licensed, has no trackers, and you're the author.
5. The merge request's CI checks the YAML (`fdroid lint`) and builds the app
   (`fdroid build`). If a job fails, open its log, fix the recipe in your
   branch and push again. Reviewers often ask for small changes; reply in
   the merge request.
6. Once it's merged, the app appears on f-droid.org within a few days.

To check the recipe locally first (Linux or WSL, with fdroidserver):

```bash
fdroid readmeta && fdroid lint com.snehangshu.magpie && fdroid build -v -l com.snehangshu.magpie
```

## Later releases

Nothing to submit. For each release:

1. Bump `version:` in `pubspec.yaml`, including `+N`.
2. Rewrite `fastlane/metadata/android/en-US/changelogs/default.txt`.
3. Run the Release workflow as usual (it creates the `vX.Y.Z` tag).

F-Droid's update checker finds the new tag and adds builds for it with the
same recipe. It usually shows up on F-Droid 1–7 days later.

When you bump Flutter in `release.yml`, F-Droid picks up the new version
too. If a newer Flutter also changes `flutter.ndkVersion`, update `ndk:` in
`metadata/com.snehangshu.magpie.yml` on fdroiddata (`r28c` =
`28.2.13676358`). When `package:sqlite3` needs a newer SQLite, update the
amalgamation URL and SHA3-256 (from https://sqlite.org/download.html).
