#!/usr/bin/env bash
# Copy the cargo-installed pinned build over unity-cli's *managed* binary
# (~/.unity/tools/unity-cli/<rid>/), which is what `unityd` actually runs and
# what upstream auto-update overwrites. Installing only to ~/.cargo/bin leaves
# the daemon on whatever build was there before.
set -u
export UNITY_CLI_NO_AUTO_UPDATE=1

exe=unity-cli
[ -f "$HOME/.cargo/bin/unity-cli.exe" ] && exe=unity-cli.exe
src="$HOME/.cargo/bin/$exe"
[ -f "$src" ] || { echo "sync-managed: $src not found" >&2; exit 1; }

shopt -s nullglob
dirs=("$HOME"/.unity/tools/unity-cli/*/)
if [ ${#dirs[@]} -eq 0 ]; then
  echo "sync-managed: no managed binary yet — nothing to sync"
  exit 0
fi

# The running daemon holds the managed exe open (Windows can't overwrite it).
# #270's on-demand start brings it back on the next remote call.
"$src" unityd stop >/dev/null 2>&1 || true

version=$("$src" --version | awk '{print $2}')
for d in "${dirs[@]}"; do
  cp -f "$src" "$d$exe"
  printf '%s\n' "$version" > "${d}VERSION"
  echo "sync-managed: $d$exe <- $src ($version)"
done
