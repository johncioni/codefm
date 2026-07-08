# CLAUDE.md

Guidance for any coding agent working in this repository. Codex and other
agents read `AGENTS.md`, which is a symlink to this file — so this is the single
source of truth. Keep it that way.

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

## Orca orchestration & worktrees

This repo is managed inside **Orca**. When work touches Orca-tracked state
(worktrees, spawned agents, terminals), **prefer the `orca` CLI over raw
`git worktree` or ad-hoc shells** so Orca's graph stays consistent. Use plain
shell tools only when Orca state does not matter.

Confirm the runtime is up before orchestration commands:

```bash
orca status --json
orca worktree current --json
```

**Spawning agents / new work**

- Separate checkout with an agent running in it:
  ```bash
  orca worktree create --name <task> --agent <claude|codex> --prompt "<brief>" --json
  ```
- Fresh agent in the *current* checkout (no new checkout):
  ```bash
  orca terminal create --worktree active --command "<agent>" --json
  ```
- **Independent work:** pass `--no-parent` and omit `--base-branch` so Orca uses
  the repo default base (`origin/main`). Only stack on the current feature
  branch when explicitly asked ("branch from current" / stacked work).

**Handoff vs. supervised orchestration**

- **Full handoff** ("hand this off", "give this to another agent/worktree"):
  deliver the prompt with `worktree create` / `terminal send`, report the new
  worktree/terminal, then stop. Do **not** create orchestration tasks for a
  handoff.
- **Supervised multi-agent** (you monitor, wait, coordinate a DAG, gate
  decisions): use `orca orchestration …` (send / check / reply / task-create /
  dispatch / gate-*).

**Checkpoints** — keep the workspace card current at meaningful state changes
(repro, fix, validation, handoff, blocker):

```bash
orca worktree set --worktree active --comment "fix implemented; running build" --json
orca worktree set --worktree active --workspace-status in-review --json
```

**Do not** run `git worktree add` directly — use `orca worktree create` so the
checkout, its terminals, and UI state are tracked. Remove with
`orca worktree rm`, not `git worktree remove`.

## Per-worktree setup

New worktrees run `Scripts/orca-setup.sh` (Orca setup hook, policy
`run-by-default`), which pre-warms `swift build` so a spawned agent lands in a
compiled checkout ready to build and test. The script is idempotent and safe to
run by hand.
