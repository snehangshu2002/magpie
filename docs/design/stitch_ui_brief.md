# Magpie: UI brief for Google Stitch

This brief describes the whole v1 UI, screen by screen. Use it to generate
designs in Google Stitch, then let Claude Code read those designs over MCP
and build them in Flutter.

It covers only v1 scope (see `CLAUDE.md`). Items marked **later** are
listed so the layout leaves room for them. Do not design them yet.

---

## 1. Workflow

```
Stitch (design)  ──MCP──▶  Claude Code (reads screens)  ──▶  Flutter widgets
     ▲                                                          │
     └──────────── screenshots of the real app ◀────────────────┘
```

1. Create one Stitch project called **Magpie**, in **Mobile** mode.
2. Paste the **design system prompt** (section 3) first. It sets the look
   for every screen after it.
3. Generate the screens in section 5, one prompt per screen, in order.
   Refine each one with short follow-up edits ("make the download button
   full width") instead of rewriting the prompt.
4. Connect Stitch to Claude Code (section 2) and ask Claude Code to build
   one screen at a time (section 7).

### Stitch tips

- One screen per prompt. Long multi-screen prompts give generic results.
- Name screens exactly as in section 5 (e.g. `01 Download – Empty`) so
  Claude Code can find them with `list_screens`.
- Use **Generate variants** on the Download screens. They matter most.
- Use fictional titles and abstract thumbnails (gradients, shapes,
  illustrations). Never real videos, creators or copyrighted artwork.

---

## 2. Connect Stitch to Claude Code (MCP)

Stitch has a remote MCP endpoint at `https://stitch.googleapis.com/mcp`,
authenticated with an API key.

1. In Stitch, open **Settings → API keys** and create a key. It is shown
   only once.
2. Put it in your shell environment, never in this repo:
   ```bash
   export STITCH_API_KEY="paste-key-here"
   ```
3. Register the server for your user (not the project, so the key is not
   written into the repo's `.mcp.json`):
   ```bash
   claude mcp add --transport http --scope user stitch https://stitch.googleapis.com/mcp --header "X-Goog-Api-Key: $STITCH_API_KEY"
   ```
4. Check it:
   ```bash
   claude mcp list
   ```
5. Restart the Claude Code session. Tools such as `list_projects`,
   `list_screens`, `get_screen`, `generate_screen_from_text`, `edit_screens`
   and `generate_variants` should appear. Names can change between
   releases; trust what your session lists.

Alternative without an API key: the community proxy
`npx @_davideast/stitch-mcp proxy` after `gcloud auth login`. Use the API
key route unless it doesn't work for your account.

---

## 3. Design system prompt (paste first)

> Design system for **Magpie**, an Android app (Material 3) that saves
> videos, music and photos from links people share from YouTube,
> Instagram, X, Reddit, TikTok and other sites. Personality: calm,
> precise, quietly premium, like a well-made utility. The logo is a
> minimalist ivory bird silhouette (long tail, raised wing) on a sage
> green square; the whole UI takes its palette from it. No mascots, no
> gradients, no ads, no clutter.
>
> **Colour:** brand sage `#84947E` and ivory `#EFEBE2`. Light theme:
> background ivory `#F7F4EE`, cards `#EFEBE2`, primary deep sage
> `#56664F` (sage `#84947E` is too light for text on ivory), on-primary
> ivory, text `#1F241D`, muted text `#5F665B`. Dark theme: background
> `#121511`, cards `#1C211B`, primary sage `#A9B8A2`, on-primary
> `#1F241D`, text `#EFEBE2`. Success uses primary; error a muted brick
> red `#B3261E` (dark `#F2B8B5`). Layer surfaces by tone, not shadows.
>
> **Shape:** continuous (squircle) corners. Cards 24 px, input fields
> 20 px, chips and buttons fully rounded (pill), bottom sheets 28 px top
> corners. No drop shadows; separate layers with tone.
>
> **Type:** Roboto Flex (Material default). Large titles bold with tight
> letter spacing (−2%); body text regular, comfortable line height. Use
> tabular numbers for sizes, percentages and durations.
>
> **Layout:** 16 px screen margins, 8 px spacing grid, generous whitespace.
> Large collapsing app bar titles. Bottom navigation with three tabs:
> Download, Library, Settings. Touch targets at least 48 px.
>
> **Brand badges:** small rounded-square badges with the site's logo in
> its brand colour (YouTube red, Instagram gradient, X black, Reddit
> orange, TikTok, Facebook blue, Vimeo, SoundCloud orange). Neutral globe
> icon for other websites.
>
> **Motion intent (for developers):** springs without bounce, content
> grows out of the element that triggered it, translucent bars that
> content scrolls under.

---

## 4. Navigation map

```
App shell (bottom nav)
├── Download  (tab 1, opens here; Share sheet also lands here)
│   ├── Empty / paste
│   ├── Link recognized
│   ├── Fetching formats
│   ├── Ready: preview + options + Download bar
│   │   └── All formats (expanded list)
│   ├── Downloading → Saved / Failed
│   └── Errors (unsupported link, network, playlist)
├── Library   (tab 2)
│   ├── In progress section + saved items
│   ├── Filters (type, site)
│   ├── Item actions sheet (open, share, delete)
│   ├── Multi-select + delete confirm
│   └── Empty state
└── Settings  (tab 3)
    ├── Downloads (default quality, audio-first sites, folder by site)
    ├── Engine (yt-dlp version, update, channel)
    ├── App updates (check, update available sheet)
    └── About (version, licenses, source code)
```

---

## 5. Screen prompts

Prepend nothing: the design system above applies. Strings in quotes are
the app's real copy (from `lib/l10n/app_en.arb`). Keep them.

### 01 Download – Empty

> Download tab, first open. Large title "Download". Under it, muted text
> "Save videos, music and photos from the apps you use." A large rounded
> link field with placeholder "Paste a link", a link icon on the left and
> a pill "Paste" button inside the field on the right. Below, a section
> "Works with" showing a wrapped grid of brand badges with names
> (YouTube, YouTube Music, Instagram, X, Reddit, Facebook, TikTok, Vimeo,
> SoundCloud) and a muted line "…and 1,000+ other sites". At the bottom of
> the content, a subtle tip card: "Tip: in any app, tap Share and choose
> Magpie." with a share icon. Bottom navigation with Download selected.

### 02 Download – Link recognized

> Same screen after a link was pasted. The link field shows a shortened
> URL, the left icon became the YouTube brand badge, the "Paste" button
> became a clear (×) icon, and a filled pill button "Get formats" appears
> to the right of / below the field. Under the field a small status line
> with a check: "YouTube · Short". The "Works with" grid is still visible
> but faded.

### 03 Download – Fetching formats

> After tapping "Get formats". The link field stays at the top. Below it,
> a skeleton media card: thumbnail placeholder 16:9 with shimmer, two
> shimmer text lines, the platform badge. Small text "Getting formats…".
> On first use, show instead "Preparing the download engine. This takes a
> few seconds the first time." with a thin indeterminate progress line.

### 04 Download – Ready (the key screen)

> Formats loaded for a video. Under the link field:
> **Preview card** (24 px corners): 16:9 abstract thumbnail with a
> duration chip "4:12" bottom-right, title "Sunset timelapse over the
> harbour" (2 lines max), and a meta row with the YouTube badge, channel
> "Example Channel", and "12 formats".
> **"Save as"** label, then a segmented button: Video | Audio | Image
> (Image disabled when unavailable).
> **Options list**: rows with a radio-style selection mark on the left,
> the quality as the main label ("1080p", "720p", "480p"), secondary line
> "60 fps · MP4 · 84.2 MB". The top row is selected and has a small tinted
> "Recommended" tag and a muted reason "Best quality up to 1080p".
> A text row "Show all 12" with a chevron.
> A muted footer line with a folder icon: "Saves to Download/Magpie/YouTube".
> **Download bar** pinned above the bottom navigation, translucent
> surface with blur, containing one full-width pill primary button
> "Download · 84.2 MB" with a download icon. The list scrolls under it.

### 05 Download – Ready, Audio selected

> Same as 04 with "Audio" selected. Options show "Best audio · M4A ·
> 3.9 MB", "Opus · 3.4 MB". Reason under the recommended row: "Suggested
> for music links" when the source is YouTube Music or SoundCloud.
> Thumbnail is square artwork for music.

### 06 Download – All formats

> Options list expanded after "Show all 12": a longer list grouped by
> resolution, each row with codec and size, some showing "Size unknown".
> Row "Show fewer" at the end. Download bar still pinned.

### 07 Download – Downloading

> The Download bar has turned into progress: a thick rounded progress
> bar filling the button area in primary sage, text "Downloading ·
> 42%" on the left, speed "2.3 MB/s · 1 min left" on the right, and a
> small circular "×" cancel button labelled "Cancel download". The rest
> of the screen stays usable but options are disabled (dimmed).
> Variant: "Waiting to start…" (queued, indeterminate) and "Finishing
> up…" (merging/saving, indeterminate shimmer).

### 08 Download – Saved

> Download finished. Above the button, a small notice row in primary sage with a
> check-circle icon: "Saved to Download/Magpie/YouTube". The button area
> shows two pill buttons: "Open" (filled) and "Share" (tonal). A subtle
> "Download another" text button. Celebrate quietly: no confetti.

### 09 Download – Errors

> Three variants of the area under the link field:
> (a) Unsupported link: inline status under the field in error colour
> "This link isn't supported."
> (b) Network error card: icon, "Network error. Check your connection and
> try again." and a tonal "Retry" button.
> (c) Playlist link: neutral info status "Playlists aren't supported yet.
> Open a single video and share that instead." and "Get formats" hidden.
> Also show the Download bar's failure notice: red error icon + "Couldn't
> save the file." above a "Retry" button.

### 10 Library – Items

> Library tab. Large title "Library" with a search icon and a select
> icon in the app bar. A horizontal row of filter chips: All, Video,
> Audio, Image, and site chips with brand badges (YouTube, Instagram, X…).
> **In progress** section at the top: compact rows with a small
> thumbnail, title, thin progress bar and "42% · 2.3 MB/s", and a cancel
> icon. **Saved** section below, grouped by date ("Today", "Yesterday",
> "Earlier"): rows with a 16:9 thumbnail (square for audio), title, meta
> line "YouTube · 1080p · 84.2 MB", a duration chip, and a "⋮" overflow
> button. Failed items show a red "Failed · Retry" line.

### 11 Library – Grid view

> Same tab in grid mode (toggle in the app bar): 2-column grid of rounded
> thumbnails with duration chips, a small platform badge in the corner
> and the title under each tile. Audio tiles show artwork with a music
> note.

### 12 Library – Item actions sheet

> Bottom sheet (28 px top corners, drag handle) opened from "⋮" or a long
> press. Header: thumbnail, title, "YouTube · 1080p · MP4 · 84.2 MB",
> "Saved to Download/Magpie/YouTube", date. Actions as large rows with
> icons: "Open", "Share", "Open source link", "Copy link", and a
> destructive "Delete" in red at the bottom.

### 13 Library – Select & delete

> Multi-select mode: the app bar becomes "3 selected" with close (×),
> select-all and delete icons. Selected rows show a filled check mark.
> A confirmation dialog: title "Delete 3 files?", body "They'll be removed
> from your device.", buttons "Cancel" and red "Delete".

### 14 Library – Empty

> Library with nothing saved. Centred, the Magpie logo bird silhouette
> in pale sage, large and soft (no new illustration).
> Text "Nothing downloaded yet." and a tonal button "Paste a link" that
> jumps to the Download tab.

### 15 Settings

> Settings tab, large title "Settings", grouped rounded sections:
> **Downloads**: "Default video quality" (value "1080p", opens a picker),
> "Prefer audio for music sites" (switch, on), "Save location"
> (value "Download/Magpie", subtitle "Grouped by site", read-only info
> row with folder icon).
> **Download engine**: "yt-dlp version" with value "2026.10.10" and a
> trailing "Update" tonal pill; "Update channel" (Stable / Nightly).
> **App**: "Check for updates" with current version "1.0.0"; "Theme"
> (System, Light, Dark) is **later**, leave it out.
> **About**: "Source code on GitHub", "Open-source licenses",
> a muted footer "Magpie is free and open source. Respect creators and
> only save what you have the right to."

### 16 Settings – Default quality picker

> Bottom sheet with radio list: "Best available", "2160p (4K)", "1440p",
> "1080p" (selected), "720p", "480p", "Data saver (360p)". Helper text:
> "Magpie picks the closest quality when this one isn't available."

### 17 Settings – Engine update states

> The yt-dlp row in three states: (a) checking, with a small spinner and
> "Checking…"; (b) "Updated to 2026.10.18" with a sage check; (c) "Already
> up to date". Errors use "The download engine ran into a problem." with
> "Retry".

### 18 App update available

> Bottom sheet: "Magpie 1.1.0 is available", short release notes as a
> bullet list, size "32 MB", buttons "Update" (filled) and "Later".
> Second state: download progress bar, then "Install" button. Note under
> it: "Android will ask you to allow installs from Magpie."

### 19 Notification (reference only)

> Android system notification, for visual reference: Magpie icon,
> title "Sunset timelapse over the harbour", text "Downloading · 42% ·
> 1 min left", progress bar, action "Cancel". Saved variant: "Saved to
> Download/Magpie/YouTube" with actions "Open" and "Share".
> (Built natively in Kotlin; Stitch is only for the look.)

### 20 First run (optional)

> One-time welcome before the Download tab. Large title "Meet Magpie",
> three short rows with icons: "Share a link from any app", "Pick the
> quality you want", "Find it in your gallery and Files". A note
> "Magpie asks for notification access to show download progress."
> Primary button "Get started".

---

## 6. Component inventory

Stitch screens should reuse these; Claude Code maps them to existing or
new widgets.

| Component | Used in | Flutter (existing / planned) |
|---|---|---|
| Link field (paste / clear / submit) | 01–03 | `intake/.../link_field.dart` |
| Link status line | 02, 09 | `intake/.../link_status.dart` |
| Brand badge | everywhere | `core/widgets/platform_badge.dart` |
| Supported sites grid | 01 | `intake/.../supported_platforms.dart` |
| Media preview card + skeleton | 03, 04 | `download/.../media_preview_card.dart` |
| Output type segmented button | 04, 05 | `download/.../download_panel.dart` |
| Option row + Recommended tag | 04–06 | `_OptionTile`, `_RecommendedTag` |
| Download bar (button → progress → saved) | 04, 07–09 | `download/.../download_bar.dart` |
| Library row / grid tile | 10, 11 | planned `library/presentation/widgets/` |
| Item actions sheet | 12 | planned |
| Settings section + rows | 15–17 | planned in `settings/presentation/` |
| Update sheet | 18 | planned in `updater/presentation/` |

States every screen needs: loading, empty, error (with retry), and the
large-text / dark-theme versions.

---

## 7. Prompts for Claude Code (after MCP is connected)

Build one screen at a time:

> Use the Stitch MCP to read screen "04 Download – Ready" from the Magpie
> project. Rebuild it in Flutter following CLAUDE.md: map its colours to
> the existing `ColorScheme` (do not hard-code hex values), shapes to
> `AppTheme.shape`, motion to `AppMotion`, and text to `l10n` (add any new
> strings to `app_en.arb`). Reuse `DownloadPanel`, `DownloadBar` and
> `MediaPreviewCard` rather than replacing them. Don't copy Stitch's HTML
> or Tailwind structure, only its layout and hierarchy. Show me the diff
> before touching other screens.

Theme first, before any screen:

> Read the Magpie design system from Stitch (colours, type, radii) and
> update `lib/core/theme/app_theme.dart` to match. Keep the seed-based
> Material 3 scheme and only override what differs.

Ground rules to repeat if Claude Code drifts:

- Stitch is the reference for look; `CLAUDE.md` is the rule for code.
- No new dependencies without asking (no Google Fonts package unless
  agreed; Roboto is the system font).
- Keep the existing state logic (Riverpod providers) untouched when
  restyling.
- Placeholder thumbnails only; no real media URLs.
