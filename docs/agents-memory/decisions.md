# Decisions

Newest first. Format and rules: `README.md` in this directory.

## 2026-10-08 Play intent comes from StreamPlayer's commands, not source states

The play request is set only where the app asks to play or stop
(`StreamPlayer.togglePlayback`, `stop`, `load`). Inferring it from source
callbacks failed: a failed AVPlayer item also emits `.stopped`, in either
order with `.offline`, so a 1.4.1 launch replacement went silent. PR #30.

## 2026-10-07 Releases ship ad-hoc signed until John adds a Developer ID

John chose ad-hoc signing for v1.4 and will add a certificate later, so
release notes must give the first-launch Gatekeeper steps (Open Anyway in
Privacy & Security on macOS 15+, right-click > Open on 13 and 14). Developer
ID plus notarization changes the release steps, not the source. PR #28, v1.4.

## 2026-10-07 The README changelog heading is a codefm.io contract

codefm-website syncs the README's `## Changelog` section, and its parser
(`src/lib/changelog.ts`) sees only `### <version> — <YYYY-MM-DD>` headings
(em dash): a new entry headed otherwise vanishes and the old release stays
"latest". `WhatsNewWindow.swift` has a separate copy to update too. PR #28.
