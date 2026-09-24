# CLAUDE.md

Guidance for any coding agent working in this repository. Codex and other
agents read `AGENTS.md`, which is a symlink to this file — so this is the single
source of truth. Keep it that way.

## Project memory

`docs/agents-memory/` is the durable, cross-agent memory for this repo
(rules: `~/.agents/MODELS.md`, "Project memory"). Read both files before the
first edit. Only the orchestrator writes there, in one reviewed memory PR
per wave.

@docs/agents-memory/decisions.md
@docs/agents-memory/ruled-out.md

## Project snapshot

**Code FM** is a lightweight macOS menubar app that streams the Code FM live
audio broadcast. Native Swift + AppKit, off-screen WebKit player for audio, no
dock icon or windows.

- **Fully self-contained — no external dependencies.** No SPM packages, no
  Homebrew, no npm. `Package.swift` declares only system frameworks (WebKit,
  AVFoundation, ServiceManagement, Carbon).
- Minimum target: macOS 13 (Ventura). Universal (arm64 + x86_64).
- Source layout lives under `Sources/`; see the "Project structure" section of
  `README.md`.

## Build / run / test

Requires Xcode command line tools (`xcode-select --install`).

```bash
swift build                 # compile the executable target
./Scripts/build-app.sh      # compile + assemble + ad-hoc sign → build/Code FM.app
swift test                  # unit tests (see caveat below)
```

- `./Scripts/build-app.sh` produces the runnable bundle at `build/Code FM.app`.
- **`swift test` needs *full* Xcode, not just the Command Line Tools.** On a
  CLT-only machine it fails with `no such module 'XCTest'` — that is an
  environment gap, not a code defect. Install Xcode to run the suite.

## Review loop

Launch recipes, terminal hygiene, and worker supervision live in `~/.agents/ORCHESTRATION.md`; roles, models, effort, and the review loop in `~/.agents/MODELS.md`.

**Required checks:** `ci`, `gitleaks`, `review-evidence`. Local gates before a
PR: `swift build`, `swift test`, and `Scripts/build-app.sh` green.

**Invariant files (ineligible for the docs/test/size skips):** `Package.swift` (system frameworks
only — no SPM deps), `Resources/streams.json` (the catalog; the website syncs
from it), `Resources/Info.plist`, `Resources/CodeFM.entitlements`,
`Sources/LoginItemManager.swift` (ServiceManagement / start-at-login),
`Sources/StreamPlayer.swift` + `Sources/YouTubeStreamSource.swift` (off-screen
WebKit player), `Scripts/build-app.sh` (ad-hoc signing),
`docs/agents-memory/*` (imported into every session).

**Branch protection is strict:** `main` requires the PR branch to be up to
date. On `mergeStateStatus: BEHIND`, run `gh pr update-branch <n>`, wait for
the checks to go green again, then merge; if more commits are needed after
the update, `git pull` in the worktree first — never `--admin`, never a
force-push (decision 2026-08-30).

## Orca

This repo is managed inside **Orca**.

New work branches from the repo default base (`origin/main`); stack on the
current feature branch only when explicitly asked.

Agents update Orca card state at meaningful checkpoints (repro, fix,
validation, handoff, blocker): `orca worktree set --worktree active --comment
"<short status>"` and `--workspace-status`.

## Per-worktree setup

New worktrees run `Scripts/orca-setup.sh` (Orca setup hook, policy
`run-by-default`), which pre-warms `swift build` so a spawned agent lands in a
compiled checkout ready to build and test. The script is idempotent and safe to
run by hand.
