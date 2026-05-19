# Code FM — Design Spec

**Date:** 2026-05-19
**Author:** John Cioni (with Claude)
**Status:** Approved for implementation planning

## 1. Summary

Fork the Code FM macOS menubar app into a new project, **Code FM**, that expands beyond a single hardcoded YouTube lo-fi stream into a curated catalog of 10–15 high-quality lo-fi and adjacent focus streams. Add a stream selector (menubar submenu + Settings window), a "Random" mode (pick once per session), and a user-configurable default startup stream. Move per-stream attribution out of the About dialog and into the new Settings window's Stream Library. The existing Code FM project and repo remain untouched so it can ship standalone in the future.

The Claude mascot icon is preserved. Tagline remains "Music for thinking and building".

## 2. Project layout & coexistence

| | Code FM (untouched) | Code FM (new) |
|---|---|---|
| Repo directory | `/Users/johnc/codefm-client` | `/Users/johnc/codefm` |
| GitHub repo | `apparelmagic-johnc/codefm-client` | `apparelmagic-johnc/codefm` (**public**) |
| App display name | Code FM | Code FM |
| Bundle ID | (current) | `com.johncioni.codefm` |
| `UserDefaults` suite | default | `com.johncioni.codefm` (isolated) |
| Login item identifier | (current) | `com.johncioni.codefm.LoginHelper` (or matching SMAppService name) |
| Carbon global hotkey signature | (current) | distinct four-char `OSType` so both apps can register hotkeys simultaneously |
| Menubar icon | Claude mascot | Claude mascot (kept) |
| Tagline | "Music for thinking and building" | "Music for thinking and building" |

Both apps install side-by-side, run simultaneously, have independent preferences, login-item state, hotkeys, and menubar slots. Nothing in Code FM references the Code FM bundle, defaults suite, or login item.

## 3. Stream catalog (ship at v1.0)

Ten streams across five sub-genres. Sources verified for URL stability (research notes captured in §11).

### Lo-fi hip hop
1. **Lofi Girl — Beats to Relax/Study** — YouTube `jfKfPfyJRdk`
2. **Lofi Girl — Jazz Lofi** — YouTube `HuFYqnbVbzY`
3. **College Music — 24/7 Live Radio** — YouTube `gmv54pfxk0Q`

### Jazzhop
4. **Chillhop Radio — Jazzy & Lo-fi** — YouTube `5yx6BWlEVcY`

### Synthwave
5. **Lofi Girl — Synthwave Radio** — YouTube `4xDzrJKXOOY`

### Ambient / focus (SomaFM, ad-free, multi-decade URL stability)
6. **SomaFM — Groove Salad** — PLS `https://somafm.com/groovesalad256.pls`
7. **SomaFM — Drone Zone** — PLS `https://somafm.com/dronezone256.pls`
8. **SomaFM — Mission Control** — PLS `https://somafm.com/missioncontrol.pls`
9. **SomaFM — DEF CON Radio** — PLS `https://somafm.com/defcon.pls`

### Brand / first-party
10. **Code FM** — YouTube `AUQKjgKQF7w` (channel `@claude`) *(default startup stream)*

**Default startup stream on fresh install:** Code FM (`claude-fm`). Reinforces the brand alignment with the Claude mascot icon on first launch.

**Sub-genre order in menu:** Lo-fi → Jazzhop → Synthwave → Ambient → Brand.

## 4. Stream catalog data model

### 4.1 Storage

A JSON file `streams.json` is the source of truth.

- **Bundled fallback:** `Resources/streams.json` shipped inside the `.app`.
- **Remote override:** `https://raw.githubusercontent.com/apparelmagic-johnc/codefm/main/Resources/streams.json`.
- **Cache:** `~/Library/Application Support/Code FM/streams.json` (cached copy of last successful remote fetch).

Precedence at launch: **cache (if fresh, <24h) → remote (5s timeout) → cache (any age) → bundled**.

A successful remote fetch overwrites cache and is used immediately. Stale cache (>24h) triggers a remote refresh attempt but the app does not block on it — current cached/bundled streams remain available.

### 4.2 Schema

```json
{
  "schemaVersion": 1,
  "defaultStreamId": "claude-fm",
  "streams": [
    {
      "id": "lofigirl-main",
      "displayName": "Lofi Girl — Beats to Relax/Study",
      "subgenre": "lofi",
      "type": "youtube_live",
      "videoId": "jfKfPfyJRdk",
      "channelLiveUrl": "https://www.youtube.com/@LofiGirl/live",
      "attribution": {
        "artist": "Lofi Girl",
        "website": "https://lofigirl.com"
      },
      "description": "The original 24/7 lo-fi study stream.",
      "providerLabel": "YouTube"
    },
    {
      "id": "somafm-groovesalad",
      "displayName": "SomaFM — Groove Salad",
      "subgenre": "ambient",
      "type": "direct_audio",
      "url": "https://somafm.com/groovesalad256.pls",
      "attribution": {
        "artist": "SomaFM",
        "website": "https://somafm.com/groovesalad/"
      },
      "description": "Chilled ambient downtempo, listener-supported, ad-free.",
      "providerLabel": "SomaFM"
    }
  ]
}
```

Required per-stream fields: `id`, `displayName`, `subgenre`, `type`, `attribution.artist`, `attribution.website`, `description`, `providerLabel`.

Type-specific required fields:
- `type: "youtube_live"` — `videoId` (required), `channelLiveUrl` (required for fallback)
- `type: "direct_audio"` — `url` (required; `.pls`, `.m3u`, or direct stream URL)

Permitted `subgenre` values for v1: `"lofi"`, `"jazzhop"`, `"synthwave"`, `"ambient"`, `"brand"`. Unknown values fall through to a generic "Other" group in the UI.

`defaultStreamId` is the fresh-install default. The user's chosen default (stored in `UserDefaults`) takes precedence once set.

### 4.3 Tolerant parsing

- Malformed top-level JSON → use prior precedence step (cache or bundled).
- Individual stream entry missing required fields or has unknown `type` → log warning, skip that entry, continue parsing the rest.
- Unknown `subgenre` → keep the stream, render under "Other".
- `schemaVersion` mismatch (file version > app's known version) → log warning, attempt to parse anyway; ignore unknown top-level fields.

## 5. Player architecture

### 5.1 Components

```
StreamPlayer (coordinator, in StreamPlayer.swift)
├─ currentStream: Stream?
├─ currentSource: StreamSource?
├─ state: PlayerState  (re-uses existing PlayerState.swift)
├─ load(stream:)   — disposes old source, instantiates new one for stream.type
├─ play() / pause() / setVolume(_:)  — forwards to currentSource
└─ publishes state changes to StatusBarController & LiquidGlassMenuPanel
```

### 5.2 `StreamSource` protocol

New file `Sources/StreamSource.swift`:

```swift
protocol StreamSource: AnyObject {
    var state: PlayerState { get }
    var stateChangeHandler: ((PlayerState) -> Void)? { get set }
    func play()
    func pause()
    func setVolume(_ volume: Float)
    func dispose()
}
```

### 5.3 Implementations

**`YouTubeStreamSource.swift`** — owns a `WKWebView` configured with the YouTube iframe API. Mostly a verbatim move of the WebKit-handling code currently in `StreamPlayer.swift`. Initialized with a `Stream` of `type: youtube_live`. Tries `videoId` first; on iframe error events (`UNPLAYABLE`, embed-blocked, 404), reloads using `channelLiveUrl` (which auto-redirects to whatever's currently live for that channel). If both fail, transitions state to `.error` and exposes a user-readable failure reason.

**`DirectAudioStreamSource.swift`** — owns an `AVPlayer` + `AVPlayerItem`. Initialized with a `Stream` of `type: direct_audio`. If the URL ends in `.pls` or `.m3u`, performs an HTTP GET, parses the first `File1=` entry (PLS) or first non-comment URL line (M3U), and hands the resolved URL to `AVPlayer`. KVO on `timeControlStatus` maps to `PlayerState` (`.playing`, `.paused`, `.buffering`, `.error`).

### 5.4 Switching streams

`StreamPlayer.load(stream:)` calls `dispose()` on any existing `currentSource`, creates the appropriate concrete source, and starts playback if the player was already in `.playing` state.

## 6. UI — menubar dropdown

Lives in the existing `LiquidGlassMenuPanel.swift`. Existing rows (transport, settings entry) stay.

**New "Stream" row** between transport and existing controls:
- Shows current stream's `displayName` and a small `subgenre` pill
- Clicking opens a submenu

**Submenu structure:**
```
🎲  Random — <currently picked stream name>
──────────
Lo-fi
   Lofi Girl — Beats to Relax/Study  ✓
   Lofi Girl — Jazz Lofi
   College Music — 24/7 Live Radio
Jazzhop
   Chillhop Radio — Jazzy & Lo-fi
Synthwave
   Lofi Girl — Synthwave Radio
Ambient
   SomaFM — Groove Salad
   SomaFM — Drone Zone
   SomaFM — Mission Control
   SomaFM — DEF CON Radio
Brand
   Code FM
──────────
Open Stream Library…
```

A checkmark indicates the active stream. Selecting any stream loads it and starts playback. Selecting "Random" enters Random mode (§7). Selecting "Open Stream Library…" opens the Settings window.

## 7. Random mode

- **Trigger:** user selects "Random" from the submenu, or the user's default startup stream is `"random"` and the app launches.
- **Behavior:** uniformly random pick from the full catalog; the picked stream becomes `currentStream` for the rest of the session.
- **Display:** menu shows "Random — <picked name>" so the user can see what was chosen.
- **Pause/Play:** resumes the same picked stream.
- **Reroll triggers:** quitting and reopening the app; selecting "Random" again from the menu.
- **Exit:** selecting any specific stream from the submenu exits Random mode for the rest of the session; `currentStream` becomes the manually-picked stream. The user's saved default startup stream setting (§8.2) is independent and is not changed by this action.

## 8. UI — Settings window

New file `Sources/SettingsWindow.swift`. Native `NSWindow`, single pane, opened from the menubar dropdown ("Open Stream Library…") and from the About dialog's footer link.

### 8.1 Stream Library section (top)

Scrollable vertical list of streams, grouped by sub-genre with section headers. Each row:

```
[▶︎]  Stream display name                     [provider badge]
      sub-genre pill  •  one-line description
      Artist Name — artist-website-link.com   [☆ Set as default]
```

- `[▶︎]` Play Now button — loads the stream and starts playback
- Provider badge (e.g. "YouTube" or "SomaFM") — sets expectation about ad presence
- `[☆ Set as default]` — sets this stream as the default startup stream
- The current default row shows a filled star (★)
- Clicking the artist website opens in the user's default browser

### 8.2 Startup section (middle)

- Toggle: **"Play a random stream on launch"** — when on, default startup stream is `"random"` (overrides any specific default in §8.1). When off, restores the most recent non-random default.

### 8.3 General section (bottom)

Consolidates existing scattered settings into one window:
- Global hotkey recorder (currently in `HotkeyRecorderWindow.swift` — move into this window)
- Login item toggle ("Launch at login")
- Play at start toggle (existing)

The standalone `HotkeyRecorderWindow.swift` is removed; its UI moves into this section.

## 9. About dialog change

Existing About dialog (`AboutWindow.swift`) keeps the vinyl, version, "What's New" button, and recent redesign.

**Removed:** the "Stream Source" section (with its current Claude-FM-specific attribution).

**Added (small footer line):** "Stream sources & credits in Settings → Stream Library" with a small button/link that opens the Settings window scrolled to the Stream Library section.

No other changes to About.

## 10. Repo split execution plan

Mechanical, scriptable steps. To be executed once at the start of implementation.

1. **Copy:** `cp -R /Users/johnc/codefm-client /Users/johnc/codefm`
2. **Strip state:** `cd /Users/johnc/codefm && rm -rf .git .build build .superpowers/cache`
3. **Rename pass** (search-and-replace across all non-binary files):
   - `Code FM` → `Code FM` (human-readable strings)
   - `codefm` → `codefm` (paths, identifiers, package names)
   - `CodeFM` → `CodeFM` (Swift types, Package.swift product, entitlements basename)
   - Bundle ID string in `Info.plist`
   - Carbon hotkey four-char signature in `HotkeyManager.swift`
   - SMAppService login helper identifier in `LoginItemManager.swift`
   - `UserDefaults` suite: introduce `UserDefaults(suiteName: "com.johncioni.codefm")` and replace any `UserDefaults.standard` access in the existing code with this suite, so settings are fully isolated from Code FM
4. **File renames:** `CodeFM.entitlements` → `CodeFM.entitlements`; any other Claude-FM-named files.
5. **README rewrite:** new project description, new repo URL, new app name.
6. **Init git:** `git init && git add . && git commit -m "Initial commit: forked from codefm-client@<sha>"` (record the source SHA in the commit message for provenance).
7. **Create remote:** `gh repo create apparelmagic-johnc/codefm --public --source=. --push`.
8. **Verify build:** clean universal build of both apps; install both; confirm:
   - Both menubar icons appear
   - Each has its own settings store
   - Hotkeys do not collide
   - Login items are independent
9. Only after the rename/build smoke passes, begin implementing the catalog/Settings/player work on the new `codefm` repo.

The Code FM repo is never touched.

## 11. Error handling

| Failure | Detection | Response |
|---|---|---|
| YouTube `videoId` no longer plays | iframe error event (`UNPLAYABLE`, embed-blocked, 404) | Auto-retry once with `channelLiveUrl`. If still fails, mark stream as `.error`, surface "Stream temporarily unavailable — try another" in the menu, disable Play for that stream until user picks another. |
| Direct audio URL fails | `AVPlayer.status == .failed` | Same UX as above. No auto-retry (PLS provides server rotation server-side). |
| PLS/M3U parse failure | HTTP GET fails or no valid `File1=` line | Treat as stream failure (above). |
| Remote `streams.json` fetch fails | timeout / non-200 / parse error | Silent fallback to cache → bundled. No user-visible error. |
| Default stream ID not present in current catalog | catalog load time | Log warning, fall back to first stream in catalog. |
| Bundled `streams.json` is malformed (developer error) | catalog load time | Hard fail at startup with an alert ("Code FM is missing its stream catalog — please reinstall"). This is a build-time bug, not a runtime condition. |

## 12. Testing

**Unit tests (`Tests/CodeFMTests/`):**
- `StreamCatalogTests` — valid JSON parses; missing required fields skipped; unknown stream type skipped; unknown subgenre renders as "Other"; schemaVersion mismatch is tolerated; remote fetch precedence (cache → remote → bundled) honored.
- `RandomPickerTests` — over N=1000 trials, every stream in the catalog gets picked at least once; no stream picked >2× expected frequency.
- `DefaultStreamResolverTests` — user-set default takes precedence over `defaultStreamId`; falls back to catalog[0] if user-set ID is no longer present.

**Manual smoke pass (pre-release checklist):**
- Fresh install on a Mac with no prior preferences — confirm Lofi Girl plays
- Play each of the 10 streams; verify audio quality and pause/resume on each
- Toggle Random; confirm picked stream is shown; pause/resume same stream; quit + reopen rerolls
- Set a default; quit; reopen; confirm correct stream starts
- Toggle "Play random on launch"; quit; reopen; confirm a random stream starts
- Install Code FM and Code FM simultaneously; confirm both menubar icons appear; confirm distinct hotkeys; confirm independent settings windows
- Open Stream Library → click artist website on each row → confirm browser opens correct URL
- Open About → click "Stream sources & credits in Settings" → confirm Settings window opens

**Not in scope:** automated UI / e2e tests (the existing project has no such harness; adding one is out of scope for this fork).

## 13. Out of scope (anti-requirements)

- No user-added custom streams in v1 (no "+ Add Stream" UI). Catalog is curator-controlled.
- No per-stream volume memory. Volume is global to the app.
- No multi-stream queueing or playlist behavior.
- No download / offline support.
- No analytics / telemetry of any kind.
- No streams that require login or paid subscription.
- No automatic catalog mutation by the app (only the developer commits to `streams.json`).
- No backwards-compat shims for migrating Code FM users' settings into Code FM (deliberate — they're fully separate apps).

## 14. Open items (non-blocking)

- 3–5 alternate streams to include in `streams.json` but not display in v1 (for swap-in if a primary URL goes stale). Pick during implementation from the v1 research candidates not in the top 10.

## 15. Sources & research notes

Stream selections and URL-stability evidence are summarized inline in §3 and §11. Full research transcript (10–15 candidates evaluated, including those rejected) was produced during brainstorming on 2026-05-19 by a Claude subagent. Key findings:

- **Lofi Girl** has rotated its main video ID exactly once (Jul 2022 false DMCA); the `@LofiGirl/live` channel URL auto-redirects to the current live ID. Hence the dual `videoId` + `channelLiveUrl` data model.
- **SomaFM** PLS endpoints have been stable for 15+ years. PLS is preferred over raw `ice5.somafm.com/...` URLs because PLS files contain rotating server lists updated server-side.
- **Code FM** (`@claude/AUQKjgKQF7w`) is a first-party Anthropic stream launched January 2026 — institutional backing, short track record (~4 months).
- **Rejected:** NRW Radio (flaky beta endpoint), "the bootleg boy 2" / Dreamhop / Homework Radio (history of outages and ID rotation after copyright strikes), independent jazz/classical Icecast streams (no first-party, multi-year-stable endpoints found).
