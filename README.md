# AlbumMark

AlbumMark is a macOS menu bar companion app for Apple Music. It watches the current Apple Music playback session, calculates how far you are through the current album, and stores unfinished albums locally so you can resume them later.

## How To Use

Download the latest compiled build from the [AlbumMark releases page](https://github.com/Le-826/AlbumMark/releases/latest). Unzip the app, move `AlbumMark.app` to Applications if you want, then open it and grant the Apple Music and Music.app Automation permissions when macOS asks.

For the most reliable album tracking and resume behavior, add the album to your Apple Music library first, then start playback from the album in your library. This helps Music.app expose stable album, track count, track order, and library identifiers. Streaming a track directly from search, recommendations, or the iTunes Store-style source can sometimes hide full album context, which may make AlbumMark fall back to less precise progress tracking or prevent album-queue resume.

## What It Does

- Lives in the macOS menu bar.
- Uses a compact AlbumMark status item and shows album progress in the popover.
- Displays a compact SwiftUI popover with:
  - Now Playing
  - Continue Albums
  - Settings via the gear button
- Reads Music.app playback details through the app's Apple Events scripting interface.
- Uses MusicKit authorization and catalog metadata where available for artwork, album identifiers, and catalog track durations.
- Calculates album progress from full album track durations when MusicKit exposes them.
- Falls back to track number, total track count, and current track progress when full album durations are unavailable.
- Saves unfinished album records to JSON in Application Support.
- Hides albums above the configured completed threshold, defaulting to 95%.
- Provides compact play and remove controls for saved album progress.

## Current Limitations

AlbumMark is a companion app, not an Apple Music plugin. It cannot change Apple Music's own UI or directly inspect every internal Music.app state.

The macOS SDK used for this MVP marks `SystemMusicPlayer` unavailable for native macOS apps. Because of that, AlbumMark reads the active Music.app playback session through Apple Events and uses MusicKit for permission flow and catalog enrichment where possible. This keeps AlbumMark as a separate companion app rather than pretending to be an Apple Music plugin.

MusicKit catalog album relationship data is not guaranteed for every item. Local files, radio stations, playlist shuffle, unavailable catalog items, or incomplete metadata can force AlbumMark to use fallback progress estimates or skip saving.

The Resume action is best-effort. In Release builds with a provisioned MusicKit capability, AlbumMark tries MusicKit catalog playback first for catalog albums. In local Debug builds, AlbumMark uses Music.app Apple Events and can only resume tracks that Music.app can resolve from its library/search metadata. If Music.app cannot find the saved track, AlbumMark reports that failure instead of falling back to the currently playing album. The older Apple Music URL playback fallback was removed because it introduced delay and could hand playback back to the current album.

Music.app Automation permission is separate from Apple Music permission. macOS may prompt the first time AlbumMark asks Music.app for the current track.

Launch at login uses `SMAppService.mainApp`. It requires a signed app bundle and may need user approval in System Settings.

## Requirements

- macOS 14.0 or later.
- Xcode 26.3 or compatible Xcode with macOS 14+ SDK support.
- Apple Music permission, requested by the app on first use.
- Music.app Automation permission, requested by macOS when AlbumMark reads or resumes playback.
- For real MusicKit authorization outside local experimentation, enable the MusicKit capability for the app identifier in your Apple developer account.

## Compile From Source

1. Open `AlbumMark.xcodeproj` in Xcode.
2. Select the `AlbumMark` scheme.
3. In Signing & Capabilities, set your Team if you want full MusicKit authorization with a provisioned app identifier.
4. Build and run.
5. Click the AlbumMark menu bar item and grant Apple Music access.
6. Start playing an album in Apple Music.
7. If macOS asks whether AlbumMark can control Music, allow it.

For command-line verification:

```bash
xcodebuild -project AlbumMark.xcodeproj -scheme AlbumMark -configuration Debug build
```

The Debug configuration is set up for local development without an Apple Developer provisioning profile. It uses `AlbumMarkDebug.entitlements`, omits the restricted MusicKit entitlement, and relies on Music.app Automation for playback metadata. Release keeps `AlbumMark.entitlements` with the MusicKit entitlement and should be signed with a real Apple Developer team/profile.

Run the deterministic logic tests with:

```bash
swiftc -parse-as-library \
  AlbumMark/Models/PlaybackState.swift \
  AlbumMark/Models/AlbumTrackInfo.swift \
  AlbumMark/Models/NowPlayingSnapshot.swift \
  AlbumMark/Models/AlbumProgressResult.swift \
  AlbumMark/Models/AlbumProgressRecord.swift \
  AlbumMark/Music/TimeFormatter.swift \
  AlbumMark/Music/AlbumProgressCalculator.swift \
  AlbumMark/Music/MusicAppBridge.swift \
  AlbumMark/Persistence/AlbumProgressStore.swift \
  AlbumMarkTests/LogicTestRunner.swift \
  -framework AppKit \
  -o /tmp/AlbumMarkLogicTests && /tmp/AlbumMarkLogicTests
```

## Persistence

Album progress is stored locally as Codable JSON:

```text
~/Library/Application Support/AlbumMark/progress-records.json
```

No cloud sync is included in the MVP.

## Architecture

- `AlbumMarkApp`: SwiftUI app entry point and app delegate bootstrap.
- `MenuBarController`: AppKit status item and popover host.
- `MusicPlayerObserver`: MusicKit authorization, current playback capture, periodic observation, catalog enrichment, and resume actions.
- `MusicAppBridge`: Native macOS bridge to Music.app playback metadata and resume controls via Apple Events.
- `AlbumProgressCalculator`: Pure album progress calculation and fallback logic.
- `AlbumProgressStore`: Codable JSON persistence for unfinished albums.
- `NowPlayingView`: Current playback and authorization UI.
- `AlbumProgressCardView`: Continue Albums card UI.
- `SettingsView`: Completed threshold, save interval, and launch-at-login controls.

## Future Roadmap

- iOS companion player.
- iCloud sync.
- Smart album history.
- Listening streaks.
- Finish later queue.
- Stats by artist and genre.
- Exportable listening journal.
- Last.fm integration.
- Widgets and Live Activity if feasible later.
