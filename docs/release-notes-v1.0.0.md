# Code FM 1.0.0

*Draft — edit before publishing to GitHub Releases.*

Code FM is a tiny macOS menubar app that streams curated lo-fi and ambient radio
for thinking and building. It's a fork of [Claude FM](https://github.com/anthropics/claudefm-client)
expanded into a multi-stream player with a built-in library, random mode, a
configurable default stream, and a global play/pause hotkey.

## Highlights

- **19 streams** across 5 sub-genres — lo-fi, jazzhop, synthwave, ambient, brand
- **Tiny menubar footprint** — Liquid Glass dropdown panel with Now Playing,
  volume, stream picker, and per-app settings
- **Random mode** — 🎲 picks a stream from the catalog, or "Play random on
  launch" rerolls each time you open the app
- **Pick your default** — star any stream in Settings → Stream Library; Code FM
  resumes there next launch
- **Global hotkey** — record any modified shortcut (⌘⇧F8 by default) and toggle
  play/pause from anywhere
- **Stream health monitoring** — at launch we quietly probe every stream;
  unavailable ones are hidden from the menu and random picker, and dimmed in
  Settings. Streams that recover during a session reappear automatically.
- **Live-stream recovery** — when a YouTube videoId rotates or is terminated,
  Code FM falls back to the channel's current live broadcast without
  interrupting the session
- **Coexists with Claude FM** — independent bundle id, UserDefaults suite, and
  hotkey scope; both apps can run side by side
- **Cross-Mac universal binary** — runs on Apple Silicon and Intel
  (macOS 13 Ventura and later)

## Sub-genre lineup

| Sub-genre | Streams |
|---|---|
| Lo-fi | Lofi Girl (main + piano), The Bootleg Boy, Lofi Geek |
| Jazzhop | Lofi Girl (jazz), Chillhop Radio, SomaFM Sonic Universe |
| Synthwave | Lofi Girl (synthwave), The 80s Guy (darksynth), SomaFM Underground 80s |
| Ambient | SomaFM Groove Salad, Drone Zone, Mission Control, DEF CON, Deep Space One, Space Station Soma |
| Brand | Claude FM, Pixar LoFi (Soul's Half Note Jazz Club), Monstercat Silk |

Stream sources and credits are listed in **Settings → Stream Library** — each
row links to the artist's website. Lofi Girl, Chillhop, The Bootleg Boy, Lofi
Geek, and The 80s Guy stream on YouTube; SomaFM stations stream directly over
HTTP via `.pls` playlists. The catalog ships with the app and is refreshed
in the background from this repository so future tweaks reach existing
installs without a new download.

## Install

1. Download `Code FM.app.zip` from the assets below
2. Unzip and drag **Code FM.app** to `/Applications`
3. Launch — the Claude mascot appears in the menubar; right-click for the panel

If macOS Gatekeeper complains the first time, control-click the app in Finder
and choose **Open** (the .app is ad-hoc signed, not notarized).

## Build from source

```bash
git clone https://github.com/apparelmagic-johnc/codefm.git
cd codefm
./Scripts/build-app.sh
cp -r build/Code\ FM.app /Applications/
```

Requires Xcode-installed Swift toolchain. Tests:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Credits

- All music belongs to the streaming artists listed in Settings → Stream
  Library; Code FM is just a player.
- Forked from [Claude FM](https://github.com/anthropics/claudefm-client) by
  Anthropic.
- Built by [John Cioni](https://github.com/johncioni) in West Palm Beach.

## Known limitations

- macOS 13 (Ventura) and later only
- Ad-hoc signed; first launch needs the right-click → Open dance
- Catalog is curated, not user-editable in-app (drop a PR on this repo to
  propose additions)
