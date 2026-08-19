#!/bin/bash
# Assemble GitHub Release notes for a version: a fixed install/Gatekeeper
# blurb followed by that version's section from CHANGELOG.md.
#
# Usage: scripts/release-notes.sh <version> [CHANGELOG.md] > notes.md
#
# Looks for "## [<version>]" (Keep a Changelog heading, with or without a
# " - date" suffix). If the version has no section yet, falls back to
# "## [Unreleased]" so a release cut before the changelog was rolled over
# still gets its notes. Prints only the install blurb if neither has content.
set -euo pipefail

VERSION="${1:?Usage: scripts/release-notes.sh <version> [CHANGELOG.md]}"
CHANGELOG="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md}"

# Print the body of the "## [<key>]" section: everything after the heading up
# to the next "## " heading, with surrounding blank lines trimmed.
section() {
  local key="$1"
  awk -v key="$key" '
    /^## \[/ { if (on) exit; on = (index($0, "## [" key "]") == 1); next }
    /^\[[^]]+\]: / { if (on) exit; next }   # link-reference block at the end of the file
    on { print }
  ' "$CHANGELOG" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | awk 'NF || started { started=1; print }'
}

BODY=""
if [ -f "$CHANGELOG" ]; then
  BODY="$(section "$VERSION")"
  if [ -z "$BODY" ]; then
    BODY="$(section "Unreleased")"
  fi
fi

cat <<'INSTALL'
## Install

1. Download the `.dmg` below, open it, drag **Wamp** to **Applications**.
2. The app is not notarized, so on first launch macOS will say
   *"Apple could not verify Wamp is free of malware"*. Click **Done**,
   then open **System Settings → Privacy & Security**, scroll down and
   click **Open Anyway**. You only need to do this once.

   Or, from Terminal: `xattr -dr com.apple.quarantine /Applications/Wamp.app`

Requires macOS 26.3 or later, Apple Silicon.

INSTALL

if [ -n "$BODY" ]; then
  echo "## What's changed"
  echo
  echo "$BODY"
  echo
fi
