#!/bin/bash
set -euo pipefail

# Orca per-worktree setup hook.
#
# Runs when Orca creates a new worktree for this repo (setup policy:
# run-by-default). Pre-warms the Swift build so a spawned agent lands in a
# compiled checkout that is immediately ready to build and test.
#
# Idempotent — safe to run by hand at any time. Code FM has no external
# dependencies, so this is a compile warm-up only (no package fetch step).

echo "Orca setup: warming Swift build for ${ORCA_WORKSPACE_NAME:-$(basename "$PWD")}..."
swift build
echo "Orca setup: build ready."
