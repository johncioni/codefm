# Code FM — Claude Design library

This folder is Code FM's UI mirrored as a **Claude Design** component library. It
is the canonical *design surface*: iterate on the web previews here (with Claude,
in claude.ai/design), then port approved changes into the Swift/AppKit app.

> **Source of truth:** the shipping app is Swift (`../Sources/`). This folder is a
> faithful mirror kept in lockstep with it. Design flows web → Swift; the Swift UI
> and these previews should never drift.

## Layout

```
design/
├─ shared/tokens.css        canonical design tokens (colors, glass, geometry, type)
├─ foundation/              @dsCard group="Foundation"
│  ├─ colors.html           brand palette, status dots, system accents, chrome
│  ├─ typography.html       the type scale, with where each size is used
│  ├─ materials.html        Liquid Glass recipe + inset surfaces + card gradient
│  └─ controls.html         toggle, slider, play button, menu row, pill, badges
└─ components/              @dsCard group="Components"
   ├─ dropdown-panel.html   the Liquid Glass menubar dropdown (primary UI)
   ├─ settings-window.html  Settings (Stream Library / Startup / General)
   ├─ about-window.html     About (spinning vinyl)
   └─ whats-new-window.html What's New (release changelog)
```

Every preview is a **standalone HTML document**: the first line is a
`<!-- @dsCard group="…" name="…" -->` marker (so it renders as a card in the
Design System pane), and each inlines a copy of the `:root` tokens so it renders
without depending on a shared stylesheet resolving. `shared/tokens.css` is the
canonical copy — change a token there first, then update the inlined copies.

No build tooling, no npm — plain static HTML/CSS, matching the app's
fully-self-contained rule.

## Where the values come from

Distilled from the Swift source, verified against headless renders and the
reference screenshots in `../docs/images/`:

| Preview            | Swift source                        |
| ------------------ | ----------------------------------- |
| dropdown-panel     | `Sources/LiquidGlassMenuPanel.swift`|
| settings-window    | `Sources/SettingsWindow.swift`, `HotkeyRecorderView.swift`, `Resources/streams.json` |
| about-window       | `Sources/AboutWindow.swift`         |
| whats-new-window   | `Sources/WhatsNewWindow.swift`      |

## Preview locally

```bash
# any of the files — just open in a browser
open design/components/dropdown-panel.html

# or render to PNG (needs Chrome); backdrop-filter needs --headless=new
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=480,560 --screenshot=/tmp/dropdown.png \
  "file://$PWD/design/components/dropdown-panel.html"
```

## The iteration loop

1. **Design** — change a component visually here, with Claude, in claude.ai/design.
2. **Sync up** — Claude pushes the edited HTML to the `codefm-ui` Design project
   via the `DesignSync` tool (`list_projects` → `finalize_plan` → `write_files`).
3. **Port** — Claude translates the approved change into the Swift/AppKit code and
   rebuilds (`./Scripts/build-app.sh`).
4. **Verify** — check the rebuilt app matches the preview.

The `design/` folder and `Sources/` change together in the same commits, so the
mirror stays versioned with the code.

## Notes on fidelity

- The Liquid Glass frosting uses `backdrop-filter` to approximate
  `NSVisualEffectView(.popover, .behindWindow)` + the white wash. On a real
  desktop the app blurs the actual wallpaper; the previews blur a representative
  backdrop.
- Row icons are hand-drawn SVG approximations of the app's SF Symbols — close in
  weight and silhouette, not the literal system glyphs.
- The app icon is embedded as an inline data URI (downscaled from
  `Resources/AppIcon.png`).
