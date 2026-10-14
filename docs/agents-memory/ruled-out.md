# Ruled out

Newest first. Format and rules: `README.md` in this directory.

## 2026-10-09 A local Renovate run as proof of the SwiftLint custom manager

Renovate 44.115.1 on Node 26 (it wants ^24, logs an error and runs on):
`--platform=local` runs only `extract` or `lookup` (any other `dryRun` becomes
`lookup`), and with no GitHub token the `github-tags` and
`github-release-attachments` lookups end in `github-token-required`. Prove
it with John's token run plus `doAutoReplace` on the update the lookup
returns. PR #56.

## 2026-10-09 A SwiftLint cache path inside the worktree for worker lint runs

Under `codex sandbox` (codex-cli 0.161.0, workspace-write), SwiftLint 0.65.1
fails with `--cache-path` inside the worktree too, hence `--no-cache`
(CLAUDE.md). With it, `--enable-all-rules` output under Codex matched an
unsandboxed run, and in a Claude role tab (Claude Code 2.1.295) held only
violations, so SourceKit works in both worker sandboxes. PRs #55, #56.
