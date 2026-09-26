#!/usr/bin/env bash
# Create (or verify) a ComfyUI project folder under <easy-install-root>/Projects.
#
# Layout: the REAL folder is <workspace>/output/Projects (inside ComfyUI's output
# tree, so ComfyUI's path-containment check passes). <root>/Projects is a
# junction/symlink pointing at it so the user browses projects at the top level.
#
# Usage: comfy-project-init.sh <project-name> [input-file ...]
#   workspace is read from COMFYUI_WORKSPACE (env, or ~/.claude/skills-config.sh)
#   project-name  = kebab-case name; created if missing
#   input-file    = optional files to MOVE into <project>/input/
# Prints the absolute project path on the last line.
set -euo pipefail

name="${1:?project name}"; shift
if [ -z "${COMFYUI_WORKSPACE:-}" ] && [ -f "$HOME/.claude/skills-config.sh" ]; then
  # shellcheck disable=SC1090
  . "$HOME/.claude/skills-config.sh"
fi
ws="${COMFYUI_WORKSPACE:?COMFYUI_WORKSPACE not set (run install.sh --configure comfyui)}"
ws="${ws%/}"
root="$(dirname "$ws")"
real="$ws/output/Projects"
link="$root/Projects"

mkdir -p "$real"

if [ ! -e "$link" ]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      w_link="$(cygpath -w "$link")"; w_real="$(cygpath -w "$real")"
      cmd //c "mklink /J \"$w_link\" \"$w_real\"" >/dev/null ;;
    *) ln -s "$real" "$link" ;;
  esac
  echo "created junction: $link -> $real"
elif [ ! -d "$link" ]; then
  echo "ERROR: $link exists but is not a directory/junction" >&2; exit 1
fi

proj="$real/$name"
mkdir -p "$proj/input" "$proj/work" "$proj/output" "$proj/workflows"

for f in "$@"; do
  [ -f "$f" ] || { echo "skip (not a file): $f" >&2; continue; }
  mv -n "$f" "$proj/input/"
  echo "moved: $f -> input/$(basename "$f")"
done

[ -f "$proj/NOTES.md" ] || printf '# %s\n\nCreated: %s\n\n## Task\n\n## Runs\n\n## Deliverables\n' "$name" "$(date +%F)" > "$proj/NOTES.md"

echo "$link/$name"
