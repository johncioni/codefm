# Decisions

Newest first. Format and rules: `README.md` in this directory.

## 2026-10-08 Sync codefm-website after every app release

Nothing syncs the site's `content/` on its own: someone runs that repo's
`scripts/sync-content.sh` and merges the PR. It lapsed from 1.3.2 to 1.4.4,
leaving a stale changelog and the 19-station catalog. John asked for a sync
after 1.4.4; do one after each release. johncioni/codefm-website#52.

## 2026-10-08 Rebuild after a web-process exit only during an active attempt

Play intent stays set after a station goes offline or the YouTube player
pauses itself, so FM-17's first process-exit rebuild, keyed on intent alone,
could start audio hours later on a station shown offline: it also needs
`.loading` or `.playing`. The silent prefetch fallback is not bound. PR #37.

## 2026-10-08 Follow a channel's /live page only to a live broadcast

A channel's /live page features one of its concurrent streams, and serves an
upload or past stream when nothing is live. The app switches only to a
current broadcast, and a station on a channel with several live streams
needs `"liveFallback": false` in `streams.json`. PRs #36, #37.

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
