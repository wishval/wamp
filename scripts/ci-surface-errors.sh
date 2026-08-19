#!/bin/bash
# Pull the interesting lines out of an xcodebuild log and surface them where
# they are visible without opening the raw job log: as GitHub Actions error
# annotations (shown on the PR "Checks" tab) and in the job summary.
#
# Usage: scripts/ci-surface-errors.sh <xcodebuild.log>
set -uo pipefail

LOG="${1:?Usage: scripts/ci-surface-errors.sh <xcodebuild.log>}"
[ -f "$LOG" ] || { echo "no log at $LOG"; exit 0; }

PATTERN='error:|fatal error|\*\* (BUILD|TEST) FAILED|Testing failed|failed on |Test Suite .* failed|xcodebuild: error'

# Annotations: cap at 30 so a cascading failure doesn't flood the Checks tab.
grep -E "$PATTERN" "$LOG" | grep -v -E 'warning:' | sort -u | head -30 \
  | while IFS= read -r line; do
      # Collapse long absolute paths to repo-relative for readability.
      echo "::error::${line#"$GITHUB_WORKSPACE"/}"
    done

# Job summary: a bit more context, still bounded.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## xcodebuild failure"
    echo
    echo '```'
    grep -E "$PATTERN" "$LOG" | grep -v -E 'warning:' | sort -u | head -80
    echo
    echo '--- last 60 lines ---'
    tail -n 60 "$LOG"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
