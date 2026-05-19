# CodeFM — macOS Menubar Audio Player

## Overview

A native macOS menubar app that plays the CodeFM YouTube live stream (audio only). Ultra-minimal: left-click toggles playback, right-click shows a quit menu. No dock icon, no main window.

**Stream URL:** https://www.youtube.com/live/YmQ7jRgf4f0

## Architecture

Three components in a native Swift (AppKit) app:

### AppDelegate
- Entry point. Configures the app as menubar-only (`LSUIElement = true` — no dock icon, no main window).
- Creates and owns the StatusBarController.

### StatusBarController
- Owns an `NSStatusItem` in the system menubar.
- Sets the icon based on player state using SF Symbols as template images (`isTemplate = true`).
- Left-click: toggles playback (play/pause).
- Right-click: shows an `NSMenu` with a single "Quit" item.

### StreamPlayer
- Manages audio extraction and playback.
- Runs `yt-dlp -f bestaudio --get-url` as a background `Process` to extract the direct audio stream URL from YouTube.
- Creates an `AVPlayerItem` from the extracted URL and plays it via `AVPlayer`.
- Observes player status and rate via KVO to detect errors, stalls, and playback state changes.
- Reports state changes back to the StatusBarController via a callback or delegate.

## Player States

Four states with corresponding icons:

| State | Icon (SF Symbol) | Trigger |
|-------|-----------------|---------|
| **Stopped** | `play.circle.fill` | App launch, user pauses |
| **Loading** | `play.circle.fill` (unchanged) | User clicks play, yt-dlp resolving |
| **Playing** | `pause.circle.fill` | AVPlayer begins playback |
| **Offline** | `play.circle.fill` at reduced opacity | yt-dlp fails or AVPlayer reports error |

### State Transitions

```
App launches → STOPPED
STOPPED + left-click → LOADING
LOADING + URL resolved → PLAYING
PLAYING + left-click → STOPPED
PLAYING + stream error → OFFLINE
OFFLINE + left-click → LOADING (retry)
LOADING + yt-dlp fails → OFFLINE
```

## Icons

- **SF Symbols** rendered as native menubar template images.
- Filled circle variants (`play.circle.fill`, `pause.circle.fill`) — solid circle with the play/pause shape cut out (inverted).
- `isTemplate = true` so macOS automatically handles light/dark mode adaptation.
- Offline state uses the same `play.circle.fill` icon at ~30% opacity to indicate unavailability.

## Playback Details

- **Audio extraction:** `yt-dlp -f bestaudio --get-url <youtube-url>` returns a direct audio stream URL. Runs as a `Process` on a background thread.
- **Playback engine:** `AVPlayer` with the extracted URL. Audio-only — no video rendering.
- **URL expiry:** YouTube stream URLs expire. Each play action re-extracts the URL via yt-dlp (~1-2 seconds). No caching of URLs between sessions.
- **Offline detection:** Non-zero yt-dlp exit code or AVPlayer error status triggers the offline state. User can retry by clicking.

## yt-dlp Bundling

- The `yt-dlp` binary is bundled in the app's `Resources` folder.
- Located at runtime via `Bundle.main.path(forResource: "yt-dlp", ofType: nil)`.
- No Homebrew or external installation required.

## Project Structure

```
CodeFM/
├── CodeFM.xcodeproj
├── CodeFM/
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   ├── StreamPlayer.swift
│   ├── PlayerState.swift
│   ├── Info.plist
│   └── Assets.xcassets
└── Resources/
    └── yt-dlp
```

## Build Configuration

- **Language:** Swift
- **Framework:** AppKit (not SwiftUI — simpler for a menubar-only app with no UI)
- **Minimum target:** macOS 13 (Ventura)
- **LSUIElement:** `true` (no dock icon, no application menu)
- **Signing:** Unsigned for personal use. Right-click → Open on first launch. Developer ID signing can be added later for distribution.

## Interaction Model

- **Left-click** on menubar icon: toggle play/pause.
- **Right-click** on menubar icon: show menu with "Quit CodeFM" item.
- **No other UI.** No windows, no preferences, no popups, no notifications.

## Non-Goals

- Volume control (use system volume)
- Now-playing display
- Launch at login (manual launch only for v1)
- Video playback
- Multiple stream support
- Preferences UI
- Auto-update mechanism
