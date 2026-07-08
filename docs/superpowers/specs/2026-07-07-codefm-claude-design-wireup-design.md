# FM-3 — Wire CodeFM UI to Claude Design

**Status:** approved (design) · **Date:** 2026-07-07 · **Ticket:** [FM-3](https://linear.app/johncioni/issue/FM-3/wire-up-codefm-ui-to-claude-design)

## Goal

Wire CodeFM's UI to the user's **claude.ai/design** account so that future UI
improvements can be iterated on visually with Claude, then ported back into the
native Swift/AppKit app — a first-class UI design loop.

## Mechanism

CodeFM is a native macOS menubar app (Swift + AppKit). Claude Design projects are
HTML-preview component libraries. So we *create* an HTML representation of the
native UI and keep it in sync with a Claude Design project via the `DesignSync`
tool (paired with the design-sync workflow).

- **Swift stays the shipping source of truth.** The HTML is the canonical *design*
  surface. The two are kept in lockstep and versioned together in this repo.

## Deliverable — local library (`design/`, committed)

```
design/
├─ shared/tokens.css        # design tokens as CSS custom properties
├─ foundation/
│  ├─ colors.html           # @dsCard — palette swatches
│  ├─ typography.html       # type scale
│  ├─ materials.html        # Liquid Glass spec: blur, tint, border, shadow
│  └─ controls.html         # toggle, slider, button styles
├─ components/
│  ├─ dropdown-panel.html   # main Now Playing + volume + toggles menu
│  ├─ settings-window.html
│  ├─ about-window.html
│  └─ whats-new-window.html
└─ README.md                # the iterate → sync → port loop
```

Constraints:

- Each HTML file is self-contained and starts with a
  `<!-- @dsCard group="…" -->` marker so it renders as a card in the Design
  System pane.
- **No npm / no build tooling** — plain static HTML/CSS, honoring the repo's
  fully-self-contained rule.

## Fidelity workflow (how the HTML is made to match)

1. Read exact values from `LiquidGlassMenuPanel.swift`, `SettingsWindow.swift`,
   `AboutWindow.swift`, `WhatsNewWindow.swift` → distill into `tokens.css`.
2. `./Scripts/build-app.sh`, launch, and screenshot each of the four real screens
   (computer-use).
3. Recreate each screen in HTML/CSS from the tokens.
4. Render locally and **diff against the app screenshots**; iterate until faithful.

## Sync & the ongoing loop

- Setup: `list_projects` → reuse or `create_project "codefm-ui"` →
  `finalize_plan` (write paths) → `write_files` from `design/`. The
  `create_project` / `write_files` step triggers a permission prompt; that is
  when the project and its cards first appear in claude.ai/design.
- Iteration (future): change a component visually with Claude → edit local HTML →
  `DesignSync` up → port the change into Swift → rebuild → verify against the app.

## Success criteria

- `codefm-ui` design-system project exists with all four screens + foundation as
  cards.
- `design/` library committed to the repo; one-command syncable.
- Each preview visually matches the running app (verified by screenshot diff).
- `design/README.md` documents the loop so future sessions resume it instantly.

## Out of scope

- Changing any actual CodeFM UI/behavior (this ticket only establishes the loop).
- Automated HTML↔Swift codegen. Porting stays a manual, reviewed step.
