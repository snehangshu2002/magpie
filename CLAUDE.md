# CLAUDE.md

Guidance for Claude (and humans) working in this repository.

## Project overview

An open-source Android app that downloads videos, audio and images from
YouTube, Instagram, X/Twitter, Reddit and other sites supported by yt-dlp,
and saves them straight to the device's shared storage (visible in the file
manager and gallery).

- **Platform:** Android only (no iOS, no Play Store)
- **Distribution:** GitHub Releases (signed APKs); F-Droid later
- **License:** MIT (`LICENSE`) for this repo's code. The APK bundles
  youtubedl-android (GPL-3.0), so the built app as a whole falls under GPL-3.0
  terms: keep the source public and don't add GPL-incompatible dependencies
- **App name / package id:** Magpie (`lib/l10n/app_en.arb` `appTitle` and the
  manifest `android:label`) / `com.snehangshu.magpie`. The Dart package is
  still named `media_downloader` (internal only)
- **minSdk:** 24 (youtubedl-android requirement)

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| UI | Flutter (Dart, null-safe) | Material 3 |
| State | Riverpod (`flutter_riverpod` + codegen) | No setState in feature code |
| Navigation | `go_router` | |
| Local DB | `drift` (SQLite) | Download history and queue |
| Prefs | `shared_preferences` (`SharedPreferencesAsync`) | User settings (`features/settings/data`) |
| Share intake | Kotlin `ShareBridge` (`app/share`) | Links shared from other apps; read by `core/platform/share_channel.dart` |
| Brand logos | `simple_icons` (CC0) | Platform badges via `SourcePlatform.icon`/`brandColor` |
| Wallpaper colours | `dynamic_color` 1.9 (BSD) | Settings → Wallpaper colours; 2.x needs `material_ui`, which Flutter's `ColorScheme` isn't yet |
| Download engine | **yt-dlp via `youtubedl-android`** (Kotlin) | Called through a platform channel |
| Media processing | FFmpeg bundled with `youtubedl-android` | Do NOT add `ffmpeg_kit_flutter` (original project retired) |
| Models / codegen | `freezed` + `json_serializable` + `riverpod_generator` + `drift_dev` via `build_runner` | Generated files are git-ignored |
| Lints | `very_good_analysis` | `public_member_api_docs` off |
| Background work | Kotlin foreground service (`dataSync` type) | Downloads must survive app backgrounding |
| Saving files | Android MediaStore (Kotlin) | No `MANAGE_EXTERNAL_STORAGE` |
| Self-update | GitHub Releases API (`dart:io` `HttpClient`), APK downloaded in the app, Android's installer | `features/updater`; `REQUEST_INSTALL_PACKAGES` + `FileProvider` |

Check pub.dev / Maven for current versions before adding dependencies; do not
guess version numbers.

## Architecture

Feature-first folders, three layers per feature:

- **presentation/** – widgets, screens, Riverpod providers/notifiers
- **domain/** – entities, repository interfaces, use cases (pure Dart, no Flutter imports)
- **data/** – repository implementations, data sources (platform channel, drift, HTTP)

Dependency rule: presentation → domain ← data. Domain never imports data or Flutter.

Dependency injection: a repository's provider lives in `data/` next to its
implementation and is typed as the domain interface
(`EngineRepository engineRepository(Ref ref) => EngineRepositoryImpl(...)`).
Presentation reads that provider but never refers to `*Impl` classes; tests
override it with a fake. Repositories return `Result<T>`
(`lib/core/utils/result.dart`); providers call `getOrThrow()` so the `Failure`
surfaces as `AsyncError`, and screens show it with `failure.message(l10n)`.

Riverpod's automatic retry is disabled in `main.dart`; screens offer an
explicit retry (`ref.invalidate`).

`features/settings` (yt-dlp version) is the reference slice that goes through
every layer down to Kotlin; copy its shape for new features.

All native work (yt-dlp, FFmpeg, MediaStore, foreground service, APK install)
lives in Kotlin under `android/app/src/main/kotlin/...` and is reached ONLY
through `lib/core/platform/`. Feature code never creates MethodChannels itself.

## Folder structure

Items marked *(planned)* do not exist yet; create them with their feature.

```
lib/
  main.dart                    # ProviderScope root
  app.dart                     # MaterialApp.router, theme, l10n
  core/
    platform/
      engine_channel.dart      # MethodChannel + EventChannel wrapper
      share_channel.dart       # app/share events + sharedTextProvider
      appearance_channel.dart  # app/appearance: chosen theme -> Android (launch screen)
      updater_channel.dart     # app/updater: installed version + ABIs, open a URL
      storage_channel.dart     # app/storage: query, thumbnail, open, share, delete saved files; app/storage/changes
      channel_json.dart        # jsonMap(): channel maps -> Map<String, dynamic>
      models/                  # freezed DTOs mirroring native payloads
    media/source_platform.dart # SourcePlatform: host/extractor -> site, folder name
    db/app_database.dart       # drift database: download_records (schema v3: + video_key)
    router/                    # go_router config + bottom-nav AppShell; BranchPager swipes between sections
    theme/                     # AppTheme (sage palette, superellipse shapes, tracking), motion.dart (SpringCurve)
    widgets/                   # shared widgets: PlatformBadge, PressableScale, SectionLabel
    errors/                    # Failure union, native error mapping, l10n messages
    utils/                     # result.dart (Result<T> = Ok | Err), formatters.dart, network_options.dart (applyNetworkOptions: Settings' proxy/IPv4/user agent on an HttpClient)
  features/
    intake/                    # link box, platform detection (detectLink), share/paste intake
    download/                  # fetchInfo preview, full-size photos yt-dlp misses (X, image links), suggested options, format picker, playlists (playlist_options), trim (ClipSelection), Settings -> yt-dlp args (download_args), download progress
    library/                   # in-progress + saved files (drift + app/storage), filters/search, open/share/fit for sharing/copy link/delete, long-press multi-select (share/delete), sync
    fit/                       # "Fit for sharing": smaller copies of saved videos under a size (planFit), sheet from the Library's file menu
    settings/                  # appearance (theme, font, colour (`ThemeColor` swatches), wallpaper colours, pure black), downloads, saved files (audio format, cover art, subtitles, SponsorBlock, MKV), accounts (sign-ins), advanced (speed limit, proxy, file names, extra options), updates, about
    updater/                   # GitHub releases/latest check at launch, update bottom sheet (AppShell): size, what's new, Update/Later
  l10n/                        # app_en.arb + l10n.dart (context.l10n)
assets/images/logo.png         # app mark (256px) shown in the Download header and licenses page
assets/licenses/               # GPL-3.0 (youtubedl-android, FFmpeg), yt-dlp Unlicense, Python PSF; shown on the licenses page via main.dart
assets/fonts/                  # Inter + Source Serif 4 (OFL): static 400/500/600/700, subset to Latin/Greek/Cyrillic; licenses registered in main.dart
android/app/src/main/kotlin/com/snehangshu/magpie/
  MainActivity.kt              # wires the bridges; implements ActivityHost
  ActivityHost.kt              # permissions, system confirmations, launching intents
  engine/YtDlpBridge.kt        # method handlers, forwards DownloadEvents to the progress channel
  engine/Engine.kt             # shared lazy yt-dlp/FFmpeg init
  engine/EngineErrors.kt       # native error codes
  engine/DownloadService.kt    # dataSync foreground service: runs yt-dlp (and fitVideo jobs), max 2 at once
  engine/VideoFitter.kt        # runs the bundled FFmpeg (libffmpeg.so) to re-encode a video under a byte target
  engine/ImageFetcher.kt       # plain HTTP download of the photos of an `images` job
  engine/SavedFiles.kt         # picks, orders and names the files of a post or playlist run (JVM-tested)
  engine/Cookies.kt            # sign-ins as a Netscape cookie file (noBackupFilesDir/cookies.txt), passed as --cookies
  engine/SignInActivity.kt     # WebView page where the user signs in to a site; Done saves its cookies
  engine/DownloadNotifications.kt # progress + saved/failed notifications
  engine/DownloadEvents.kt     # SharedFlow of progress payloads
  engine/DownloadResults.kt    # final events kept in SharedPreferences until Dart takes them
  storage/MediaStoreSaver.kt   # copies the finished file into Download/ (MediaStore, legacy dir < API 29)
  storage/StorageBridge.kt     # app/storage handlers
  share/ShareBridge.kt         # app/share: SEND text, kept until Dart listens
  AppearanceBridge.kt          # app/appearance: UiModeManager.setApplicationNightMode (API 31+)
  updater/UpdaterBridge.kt     # app/updater handlers
test/                          # mirrors lib/
integration_test/              # (planned)
```

## Platform channel contract

Channel names: `app/engine` (methods) and `app/engine/progress` (events).

| Method | Args | Returns |
|---|---|---|
| `init` | – | `{ytDlpVersion?}` (null until the first `updateEngine`) |
| `fetchInfo` | `{url, options}` | `{id?, title, thumbnail, duration, extractor, formats: [...], entries?, description?, captions: [...]}` |
| `fetchPlaylist` | `{url, options}` | `{title, extractor, thumbnail?, entries: [{title?, duration?, thumbnail?}]}` (`-J --flat-playlist`) |
| `fetchTranscript` | `{url, lang, auto, options}` | `{text, ext}`: the caption track as WebVTT (`--skip-download`; `NOT_FOUND` if no file) |
| `startDownload` | `{id, url, formatId, targetDir, title?, items?, imageUrls?, options, playlist, archive, fileName?}` | `{id}` |
| `fitVideo` | `{id, uri, targetDir, name, targetBytes, durationMs, videoKbps, audioKbps, maxShortSide, title?}` | `{id}` |
| `cancelDownload` | `{id}` | `bool` (false if not queued/running) |
| `updateEngine` | `{channel: "stable"\|"nightly"}` | `{status, version}` |
| `takeFinishedDownloads` | – | `[progress event]` (final events since last call, each returned once) |
| `networkStatus` | – | `{metered}` (`ConnectivityManager.isActiveNetworkMetered`) |
| `signIn` | `{url}` | `[site]` signed in to afterwards: opens `SignInActivity` at `url`; Done saves that site's WebView cookies |
| `signedInSites` | – | `[site]`, e.g. `instagram.com` |
| `signOut` | `{site}` | `[site]` still signed in to (drops the site's lines; the WebView forgets all cookies) |

`options` (every method that reaches a site) are extra yt-dlp arguments
Dart builds from Settings and native appends unread (`addCommands`):
`networkArgs` (proxy, `-4`, user agent) for lookups, `downloadArgs` for
downloads (also speed limit `-r`, `-N 4`, `--restrict-filenames`,
`-x --audio-format`, `--merge-output-format mkv`, `--embed-subs` (with
`--ignore-errors`, so a subtitle YouTube refuses with 429 doesn't fail the
video),
`--embed-metadata`, `--embed-thumbnail` only for containers FFmpeg can tag
(`_coverArtExts`), SponsorBlock, `--download-sections` for a clip, `-S
res:<q>` for a playlist's quality, and the user's extra options, which may
not set `-o`/`-P`/`-a`). Posts and photos get no media processing. The
photo paths that bypass yt-dlp read the same arguments: `WebPhotoSource`
(`fetchPhotos`/`fetchImage` take `options: networkArgs`, applied by
`applyNetworkOptions`) uses `--proxy` (plain `http://` proxies only;
HttpClient can't do SOCKS or TLS to a proxy, so those lookups go direct),
`-4` and `--user-agent`, and so do the thumbnails the app shows (preview
card, post items, Library), loaded as `WebImage` via `webImageOf`
instead of `Image.network`, and the app update check and APK download
(`UpdateRepository.check`/`download` take `options`); `ImageFetcher` (`images` jobs) uses `--proxy`
(HTTP or SOCKS, no credentials) and `--user-agent` but not `-4`
(HttpURLConnection has no DNS hook). Native
adds `--cookies` to every yt-dlp run when the user signed in to a site
(yt-dlp sends each site only its own cookies), as a per-run copy of
`noBackupFilesDir/cookies.txt` deleted afterwards: yt-dlp writes cookies
back when it ends, which would undo a sign-in or sign-out made meanwhile.
`playlist: true` saves `url` as a playlist with the `formatId` selector
(`--yes-playlist --ignore-errors`, `items` → `-I`): every video that saved
is kept, in order, named by its own title; `targetDir` is
`<folder>/<Platform>/<playlist title>`. `archive` (playlists only) adds
`--download-archive` with a per-job copy of `noBackupFilesDir/archive.txt`,
keyed by site and video id; its new lines are added to the shared file
only once the files are saved (`keepArchive`), since yt-dlp records a video
before it is saved and a cancel or failure would otherwise skip it forever; a playlist with nothing new fails with `NOTHING_NEW`. yt-dlp's
archive never forgets a video, even once its file is deleted, so single
videos are checked against the Library instead: the record's `videoKey`
(`<extractor> <id>`, `videoKeyOf`) of a saved row means `Failure.nothingNew`
before anything is sent; deleting the file allows it again. `fileName` is a yt-dlp output template for the name
(default `%(title).150B`, no `/`).

`formats` items: `{formatId, ext, width?, height?, fps?, vcodec?, acodec?,
fileSize?, note?}`. `description` is yt-dlp's `description` (a YouTube
description, an Instagram/Facebook caption, a post's text), null when
blank. `captions` items `{lang, name?, auto}`: every uploader subtitle plus
automatic captions only in the video's own language (`<lang>-orig`, else
`language`), never the machine translations. The Download screen shows the
text (`PostTextCard`: Description / Caption / Post text, copy, show more)
and, with captions, a Transcript sheet (`transcriptFromVtt`, language chips,
copy, save as `<title> (transcript).txt` via `saveText`). A format with no
codecs or size but a video container (`mp4`, `webm`, …) counts as
video with sound. `vcodec`/`acodec` are `"none"` for audio-only/video-only
streams (yt-dlp convention); `fileSize` is bytes, exact or approximate.
`duration` is seconds, null when unknown. `extractor` is yt-dlp's raw
extractor name (e.g. `youtube`); Dart maps it to a folder name
(`SourcePlatform.fromExtractor`). `fetchInfo` runs `yt-dlp -J --no-playlist
--ignore-no-formats-error`, so a post with several items (Instagram
carousel) comes back with `entries: [{thumbnail?, duration?, formats}]` in
order and empty top-level `formats`. An item (or a single result) without
formats is a photo whose image is its `thumbnail`; Dart counts it only where
`SourcePlatform.hasPhotoPosts` (Instagram).

`startDownload` `formatId` is a yt-dlp `-f` selector chosen by Dart: a single
format id (`18`), or `video+audio` ids to merge (`137+140`); or `post`
(`postSelector`) to save every item of the link: videos as `bv*+ba/b`, photos
from `--write-thumbnail`, renamed by content (`imageExtensionOf`; Instagram
serves JPEGs named `.heic`) to `<title> <n>.<ext>`. Only "No video formats
found" errors are tolerated in a `post` run. `items` (1-based, ascending,
`post` only) saves just those items of the post (`-I 1,3,5`), each named
`<title> <place>.<ext>`; Dart offers them from a multi-select picker when a
post has several items (`DownloadOptions.postItems`, indexed by place in
`entries`; picking none or all of them sends the whole post, `items` null).
`images` (`photosSelector`) saves `imageUrls` by plain HTTP (`ImageFetcher`,
no yt-dlp), named `<title>[ <n>].<ext>` by content like a post's items
(`items`, when given, is each URL's place in the post). Dart finds those
full-size URLs itself (`WebPhotoSource` in `features/download/data`), for
photos yt-dlp leaves out: X photos via the public syndication endpoint
(`cdn.syndication.twimg.com/tweet-result`, `syndicationToken`) at
`name=orig`; and links that are an image themselves (HEAD
`image/*`; `pbs.twimg.com` and `preview.redd.it` links upgraded to the
original). `mediaPreview` runs that lookup next to `fetchInfo` (an image
link skips yt-dlp; an `UNSUPPORTED_URL` link is probed as an image) and
`suggestDownloadOptions(photos:)` offers the photos alone, with the item
picker when there are several, or as the image choice next to a video.
`targetDir` is
`<saveFolder>/<Platform>`, where `saveFolder` is the user's choice under
`Download/` (default `Download/Magpie`; `saveDirFor` in `features/download/domain`).
`title` is shown in the notification and names a `post`'s files. Dart generates `id` and listens
for its progress before calling `startDownload`.
`updateEngine` `status` ∈ `done | alreadyUpToDate`.

A download started while "Keep a history" is off isn't recorded in drift,
so it never shows in the Library. Audio goes to `audioFolder` when set.

`fitVideo` re-encodes the saved video at content URI `uri` into an
H.264/AAC MP4 of at most `targetBytes`, saved as `<targetDir>/<name>.mp4`
like a download. Dart decides the settings (`planFit` in
`features/fit/domain`): `videoKbps`, `audioKbps` (0 drops audio) and
`maxShortSide` (the copy's shorter side; never upscaled); FFmpeg also caps
the frame rate at 30. It runs in `DownloadService` as a job with `formatId`
`fit` and `url` = the source URI: same progress events (`running` with
`percent` from FFmpeg's `out_time_us`, `merging` while saving), same final
events and `takeFinishedDownloads`, and `cancelDownload` kills FFmpeg. The
Library records it as a download row (`formatId` `fit`, `url` = the original
link), so it shows as in progress and then as a saved file. A single-pass
encode can overshoot, so a result over `targetBytes` is encoded again at a
proportionally lower video bitrate (3 tries in all, never below 80 kbps);
still too big → `TOO_LARGE`.

FFmpeg is youtubedl-android's: `<nativeLibraryDir>/libffmpeg.so`, run with
`LD_LIBRARY_PATH` = `noBackupFilesDir/youtubedl-android/packages/{python,ffmpeg}/usr/lib`
(what youtubedl-android sets for yt-dlp). `Engine.ensureInitialized` must run
first, since it unpacks those libraries. The input is copied into the job's
work dir first, since FFmpeg can't read content URIs.

Progress events: `{id, percent, etaSeconds?, speed?, state, filePath?, filePaths?, error?}`
where `state` ∈ `queued | running | merging | saved | failed | cancelled`,
`speed` is yt-dlp's formatted rate (e.g. `2.31MiB/s`), `filePath` is the
MediaStore content URI once `saved` (`filePaths` lists every file, in order,
when a `post` saved several; the Library adds a row `<id>-<n>` for each extra
one), and `error` is an error code when `failed`.
`percent` is 0–100 over the whole download (a `video+audio` selector counts
each stream as half). `merging` also covers copying into shared storage.
Events are throttled to ~4/s per download and dropped while Dart isn't
listening.

Every final event (`saved | failed | cancelled`) is also kept natively until
`takeFinishedDownloads`; the Library calls it on launch and after each final
event, so downloads that finish while the UI is gone are still recorded.

Second channel, `app/storage` (saved files, by content URI):

| Method | Args | Returns |
|---|---|---|
| `queryFiles` | `{uris: [..]}` | `[{uri, name?, size?, mimeType?}]` for those that still exist (MediaStore row present, not in the trash (`IS_TRASHED`, API 30+), and the file opens) |
| `thumbnail` | `{uri, size}` | JPEG bytes or null (API 29+ only) |
| `openFile` | `{uri, mimeType?}` | – (`NOT_FOUND`, `NO_APP`) |
| `shareFiles` | `{uris: [..], mimeType?, title?}` | – (`NOT_FOUND` if none exist, `NO_APP`). Missing ones are left out; one file → `ACTION_SEND`, several → `ACTION_SEND_MULTIPLE`; Dart picks one MIME type for all (`sharedMimeType`) |
| `deleteFiles` | `{uris: [..]}` | `[uri]` now gone. Files the app no longer owns need consent: one system prompt for all on API 30+, one each on API 29; declined ones are left out |
| `probeVideo` | `{uri}` | `{durationMs?, width?, height?, hasAudio}` via `MediaMetadataRetriever`; width/height before rotation. `NOT_FOUND` if gone, `STORAGE` if unreadable |
| `saveText` | `{name, text, targetDir}` | content URI of `<targetDir>/<name>.txt` (saved like a download; asks for `WRITE_EXTERNAL_STORAGE` below API 29, `STORAGE` if denied) |
| `pickFolder` | – | tree document id (`primary:Download/Clips`) or null if backed out (`NO_APP`). Opens `ACTION_OPEN_DOCUMENT_TREE` at Download; Dart accepts only folders in `Download/` on `primary` (`saveFolderFromTreeId`), since files are saved through the Downloads collection |

Events on `app/storage/changes`: `null` whenever MediaStore changes (a
`ContentObserver` on `MediaStore.Files` external, registered while Dart
listens). The Library debounces them (`librarySyncDebounce`) and re-syncs,
and also syncs on app resume, so files deleted in the gallery or a file
manager drop out of the Library.

Errors are sent as `PlatformException` with `code` ∈ `UNSUPPORTED_URL |
NETWORK | ENGINE | STORAGE | CANCELLED | NOT_FOUND | NO_APP | TOO_LARGE |
ENCODE | NOTHING_NEW | UNKNOWN` (`TOO_LARGE`: `fitVideo` couldn't get under the target;
`ENCODE`: FFmpeg failed; an `images` job's HTTP errors are `NETWORK`,
404/410 `NOT_FOUND`, a reply that isn't an image `UNSUPPORTED_URL`) (`EngineErrors.kt` ↔
`NativeErrorCode` in `lib/core/errors/platform_failure.dart`). Any other code
becomes `Failure.unknown`. A method with no native handler
(`MissingPluginException`) becomes `Failure.unavailable`.

Third channel, `app/share` (events only): the `EXTRA_TEXT` of each
`ACTION_SEND` intent (launch or `onNewIntent`). A share that arrives before
Dart listens is kept (latest only) and sent on listen, so shares made while
the app is still starting are not lost. Intents replayed from Recents
(`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) or a recreated activity are ignored.

Fourth channel, `app/appearance`: `setNightMode {mode: system|light|dark}`
→ `UiModeManager.setApplicationNightMode` (API 31+, no-op below), sent by
`appearanceSyncProvider` at launch and on each theme change, so Android
draws the launch screen in the app's theme. No theme flash on startup:
`main.dart` loads settings before `runApp` (2 s cap), and the launch screen
and window background use the app's page colour (`@color/launch_background`,
light/night; `windowSplashScreenBackground` on API 31+).

Fifth channel, `app/updater`: `appInfo` → `{version, abis}` (`versionName`,
`Build.SUPPORTED_ABIS`); `openUrl {url}` → `ACTION_VIEW` (`NO_APP`);
`prepareApk {name}` → path in `cacheDir/updates/` to download to (older
APKs there deleted); `installApk {path, sha256?}` → checks the file's SHA-256
(`NETWORK` on mismatch, file deleted) and opens Android's installer
(`ACTION_VIEW`, `FileProvider` authority `<applicationId>.updates`,
`res/xml/update_paths.xml`), which asks the user to confirm and, the first
time, to allow installs from Magpie. Once per
launch `appUpdateProvider` reads
`api.github.com/repos/snehangshu2002/magpie/releases/latest`; if its
`tag_name` is newer (`isNewerVersion`), AppShell shows a bottom sheet with
the APK size, the `body`'s bullets (`releaseNoteLines`) and the date; its
"Update" downloads the asset `magpie-<version>-<abi>.apk` for the first
matching ABI (`apkFor`) inside the app (`updateDownloadProvider`: progress,
Cancel; closing the sheet stops it), then `installApk` with the asset's
`digest` (`sha256:<hex>`); no matching APK → the release page in the
browser. The "Release notes" chip opens the release page. Settings →
Updates has a "Magpie updates" row (`_AppUpdateTile`): up to date + Check
(re-runs `appUpdateProvider`, so a find shows the sheet), or after "Later"
"Magpie <version> is ready to install" + Update now (the same sheet).

Native methods initialize yt-dlp lazily, so `init` is only needed to warm up
and read the version. youtubedl-android records a version only when
`updateEngine` installs one, so on a fresh install `ytDlpVersion` is null
(the build bundled with the app).
The bundled build goes stale fast (Instagram needs yt-dlp ≥ 2026.07), so
Dart calls `updateEngine` (stable) once per launch (`engineAutoUpdateProvider`) and
`mediaPreview` waits up to 20 s for it. There is no manual update or channel
choice: Settings only shows the update's status in plain words, with a retry
when it failed. Natively, updates run one at a time
(`Engine.update`), and every channel error is logged under `YtDlpBridge`.
`startDownload` first asks for `POST_NOTIFICATIONS` (API 33+; downloads run
without it) and, below API 29, `WRITE_EXTERNAL_STORAGE` (denied → `STORAGE`). yt-dlp writes into
`noBackupFilesDir/downloads/<id>/`; the file is then copied into shared
storage and the temp dir deleted.

Any change to this contract must be made on both the Dart and Kotlin sides
in the same commit, and documented here.

## v1 scope

1. Receive a link via the Share sheet or paste it manually
2. Fetch info and show formats (video quality, audio-only, image)
3. Download in a foreground service with a progress notification
4. Save to `Download/<folder>/<Platform>/` via MediaStore (folder picked in Settings)
5. History screen: open, share, delete
6. Settings: theme (system/light/dark), font, default quality (up to
   "Best available", `bestAvailableQuality`: no cap), save folder,
   automatic yt-dlp updates; plain words everywhere (a test checks that
   "yt-dlp" appears nowhere on screen), technical options only under Advanced
7. App self-update check against GitHub Releases

**Later (not v1):** clipboard watcher, multiple languages, SD card saving,
several audio tracks in one video.
(Shipped since: Fit for sharing (`features/fit`); playlists, trim, audio
conversion, cover art/metadata/subtitle embedding, SponsorBlock, sign-ins
(cookies), wallpaper colours and the advanced download settings, after
Seal.)
Do not build later items unless asked.

## Conventions

- Dart: `very_good_analysis` (see `analysis_options.yaml`); `dart format` before commit
- Dart 3.13 constructor syntax is enforced by the `unnecessary_type_name_in_constructor`
  lint: write `const new({super.key})`, `factory fromJson(...)`,
  `const factory network(...)` instead of repeating the class name
  (`dart fix --apply` converts). freezed, drift and riverpod codegen accept it.
- Files `snake_case.dart`, classes `PascalCase`, providers end in `Provider`
- Use `freezed` for immutable models and unions; `Result`/`Either`-style returns
  from repositories instead of throwing across layers
- Map every native error to a typed `Failure` with a user-readable message
- No hard-coded strings in UI; use `l10n`
- UI motion and feel (from the `apple-design` skill): animate with
  `AppMotion.standard` (critically damped `SpringCurve`) and
  `AppMotion.durationOf(context)`, which is zero when the system disables
  animations; use `AppTheme.shape(r)` (superellipse) for rounded surfaces;
  haptics only on meaningful moments (link recognized, selection, commit);
  validate input inline as the user types
- Visual design follows the Stitch project "Magpie Media Downloader App"
  (calm sage, Material 3). Sage is the default `ThemeColor`; the other
  colours grow a scheme from their seed (`AppTheme.scheme`). Read colours from `Theme.of(context).colorScheme`,
  never hard-code them; `AppTheme` holds the palette (light: Stitch's exact
  colours; dark: its "deep peat" notes). Patterns in use:
  - depth from tone, not shadow: page `surface`, cards `surfaceContainer`,
    sheets `surfaceContainerHigh`, hairlines `outlineVariant` at ~30–60%
  - cards 24 radius, link box 20, nested thumbnails 12–16; buttons, chips,
    segmented controls and progress bars are full pills (`StadiumBorder`)
  - primary filled actions use `primary` (Download, selected segment); the
    softer sage actions (Paste, Update, selected chip) use `primaryContainer`
  - section headings are `SectionLabel` (uppercase, sage); grouped rows sit
    in one card with inset dividers (Settings, option lists)
  - numbers that change or line up (sizes, %, speed, fps) use
    `FontFeature.tabularFigures()`
  - platform logos come from `simple_icons` via `PlatformBadge`; never the
    Stitch placeholder glyphs
  - no non-functional controls: leave out a design's button until the
    feature behind it exists (e.g. pause)
- Kotlin: coroutines for background work; never block the main thread
- Keep native code thin: it executes, Dart decides

## Commands

```
flutter pub get                  # also regenerates lib/l10n/app_localizations*.dart
dart run build_runner build      # or `watch`; build_runner 2.16+ dropped --delete-conflicting-outputs
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest)   # Kotlin JVM tests; results in build/app/test-results
flutter run
flutter build apk --release --split-per-abi
```

Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/app_localizations*.dart`)
are not committed; run the first two commands after cloning or pulling.

## Android build setup

- AGP 9.2.1 / Gradle 9.4.1 / compileSdk 37: once required by `receive_sharing_intent`
  1.9 (since replaced by `ShareBridge`); kept. Flutter's own template default is AGP 9.1 / API 36.
- `packaging.jniLibs.useLegacyPackaging = true`: yt-dlp's Python and FFmpeg are
  executed from `nativeLibraryDir`, so native libs must be extracted on install.
  `*.zip.so` files are excluded from stripping (they are zip archives).
- `android/app/proguard-rules.pro` keeps `com.yausername.**`, Jackson and
  `org.apache.commons.compress.**`, which youtubedl-android uses reflectively;
  it ships no consumer rules. Without commons-compress, release builds crash on
  launch while unzipping Python ("class X is not a concrete class").
- Release signing reads `android/key.properties` (git-ignored); without it,
  release builds are signed with the debug key and must not be published.
- Declared for downloads: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`,
  `POST_NOTIFICATIONS`, `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`) and the
  `DownloadService` `<service android:foregroundServiceType="dataSync">`.
  `DownloadService.onTimeout` handles Android 15's daily dataSync limit.
- Also declared: `FOREGROUND_SERVICE_MEDIA_PROCESSING`; `DownloadService` is
  `dataSync|mediaProcessing` and on API 35+ calls `startForeground` with both
  types, since re-encoding (`fitVideo`) is media processing. Tested on an
  Android 15 tablet: `dumpsys` still reports only `dataSync` (`types=0x1`),
  so in practice copies run under the dataSync budget; cause not yet known.
- Also declared: `REQUEST_INSTALL_PACKAGES` and a `FileProvider`
  (`<applicationId>.updates`) for in-app updates.
- Also declared: `ACCESS_NETWORK_STATE` (`networkStatus`, "Ask before using
  mobile data") and `SignInActivity` (not exported).
- `androidx.core` is declared explicitly for NotificationCompat/ServiceCompat.


## Releases

`.github/workflows/release.yml` runs only by hand (Actions → Release → Run
workflow, or `gh workflow run release.yml`) on the chosen branch. The version
comes from `pubspec.yaml` (`version: 1.2.0+N`; bump it before releasing): the
run stops early if release `v1.2.0` already exists. It tests, builds split
APKs with `--build-name` from pubspec and `--build-number` = the run number
(so the `+N` is ignored and versionCode always grows), renames them
`magpie-<version>-<abi>.apk` and publishes release `v<version>` (the tag is
created at that commit).
The optional `notes` input (points separated by `;` or a spaced ` - `,
since the Actions form is one line) becomes the release body as `- ` lines, which the update sheet
lists under "What's new"; without notes it shows only the version and size. It needs repository secrets
`KEYSTORE_BASE64` (`base64 -w0 release.jks`), `KEYSTORE_PASSWORD`,
`KEY_ALIAS`, `KEY_PASSWORD`, and fails without them rather than publish a
debug-signed APK.

## Code navigation (knowledge graph)

This repo is indexed by `codebase-memory-mcp` (MCP server `codebase-memory-mcp`,
project `home-snehangshu-Documents-media_downloader`). Use the graph first to
find files, symbols and call paths; fall back to Grep/Read only for what the
graph can't answer.

Before searching:
- At session start (or after compaction) call `index_status` to confirm the
  project is indexed and fresh

Finding code:
- Symbols by name: `search_graph(name_pattern=".*Download.*")` (paginate with
  `offset` while `has_more`)
- Read source: `get_code_snippet(qualified_name=...)`; file overview:
  `get_file_outline`
- Callers / callees: `trace_path(function_name=..., direction="both")`
- Layer overview: `get_architecture`; ad-hoc relations: `query_graph` (Cypher)
- Plain text (strings, l10n keys, arb entries): `search_code` or Grep
- Before relying on a result, call `check_index_coverage` with the paths
  involved; for partial/excluded ranges, Read the source instead

Not in the graph (use Read/Grep): generated `*.g.dart`, `*.freezed.dart`,
`lib/l10n/app_localizations*.dart` and other git-ignored files. freezed model files (`lib/core/platform/models/`) parse only
partly (Dart 3.13 `const factory new(...)`), so verify their constructors with Read.

After completing a code change:
1. `detect_changes()` to see which symbols the diff touches and check the
   impact on callers before finishing
2. `index_repository(repo_path="/home/snehangshu/Documents/media_downloader")`
   to update the graph (the file watcher also re-indexes, but run it
   explicitly so the next query sees the change)
3. `index_status` to confirm the new generation is indexed

## Rules for Claude

- Read this file and the relevant feature folder before editing
- Make small, focused changes; explain any new dependency before adding it
- Never commit signing keys, keystores, `key.properties` or tokens
- No AI attribution in git: do not add `Co-Authored-By: Claude ...` trailers,
  "Generated with Claude Code" lines or any other Claude/AI watermark to
  commit messages, PR descriptions or code
- Never put real copyrighted media URLs in tests, docs, screenshots or the README;
  use mocked responses or clearly public-domain/test content
- Never add code that bypasses DRM, paywalls or private-account protections
- Do not request `MANAGE_EXTERNAL_STORAGE`; use MediaStore
- Target Android 14+ foreground service rules (declare the service type and permission)
- When unsure about an API, package version or Android behavior, check docs first
  rather than guessing
- Update this file when architecture, the channel contract or v1 scope changes

## Open decisions

- Final list of "extra features" for v2
