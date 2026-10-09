#!/usr/bin/env bash
# Build the pinned unity-cli with cargo, then sync the managed binary.
# Usage: build.sh <rev>
#
# `cargo install --force` replaces ~/.cargo/bin/unity-cli(.exe). On Windows that
# fails ("failed to move ... cargo-installXXXX") while anything runs from that
# file, typically `unity-cli unityd serve`. Stop the daemon first; if the exe is
# still locked (another session, an MCP), rename it aside, which Windows allows
# for a running exe, and put it back if the build fails.
set -u
export UNITY_CLI_NO_AUTO_UPDATE=1
rev="${1:?usage: build.sh <rev>}"
here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.cargo/bin"

exe=""
[ -f "$bin/unity-cli.exe" ] && exe="$bin/unity-cli.exe"
[ -z "$exe" ] && [ -f "$bin/unity-cli" ] && exe="$bin/unity-cli"

aside=""
if [ -n "$exe" ]; then
  "$exe" unityd stop >/dev/null 2>&1 || true
  rm -f "$exe".old-* 2>/dev/null || true
  case "$exe" in
    *.exe)
      locked=true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        if ( : >> "$exe" ) 2>/dev/null; then locked=false; break; fi
        sleep 0.5
      done
      if [ "$locked" = "true" ]; then
        aside="$exe.old-$$"
        mv -f "$exe" "$aside" && echo "build: $exe is in use; moved it aside to $aside" || aside=""
      fi
      ;;
  esac
fi

if ! cargo install --git https://github.com/akiojin/unity-cli.git --force --rev "$rev"; then
  if [ -n "$aside" ] && [ ! -f "$exe" ]; then mv -f "$aside" "$exe"; fi
  exit 1
fi

bash "$here/sync-managed.sh"
