#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-skills installer
# Cross-platform (macOS, Linux, Windows via Git Bash/WSL)
# Installs selected skill groups: software + skills + agents → ~/.claude/
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_GROUPS_DIR="$SCRIPT_DIR/skill-groups"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
fail()  { echo -e "${RED}✗${NC} $*"; }
header() { echo -e "\n${BOLD}$*${NC}"; }

# ─── Platform detection ──────────────────────────────────────────────────────

detect_platform() {
  case "$(uname -s)" in
    Darwin*)  echo "macos" ;;
    Linux*)   echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)        echo "unknown" ;;
  esac
}

PLATFORM=$(detect_platform)

# ─── Symlink helper (cross-platform) ────────────────────────────────────────

create_symlink() {
  local target="$1"
  local link_path="$2"

  # Remove existing (file, symlink, or directory)
  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    rm -rf "$link_path"
  fi

  if [ "$PLATFORM" = "windows" ]; then
    # On Windows Git Bash, try ln -s first (works with Developer Mode enabled)
    if ln -s "$target" "$link_path" 2>/dev/null; then
      return 0
    fi
    # Fallback: use cmd.exe mklink
    local win_target win_link
    win_target=$(cygpath -w "$target" 2>/dev/null || echo "$target" | sed 's|/|\\|g')
    win_link=$(cygpath -w "$link_path" 2>/dev/null || echo "$link_path" | sed 's|/|\\|g')
    if [ -d "$target" ]; then
      cmd.exe /c "mklink /J \"$win_link\" \"$win_target\"" >/dev/null 2>&1 && return 0
      cmd.exe /c "mklink /D \"$win_link\" \"$win_target\"" >/dev/null 2>&1 && return 0
    else
      cmd.exe /c "mklink \"$win_link\" \"$win_target\"" >/dev/null 2>&1 && return 0
    fi
    # Last resort: copy
    warn "Symlink failed for $link_path — falling back to copy"
    cp -r "$target" "$link_path"
  else
    ln -s "$target" "$link_path"
  fi
}

# ─── JSON parser (portable, no jq dependency) ───────────────────────────────

# Extracts a simple string value from JSON: json_get '{"key":"val"}' "key" → val
json_get() {
  local json="$1" key="$2"
  echo "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Extracts a simple array of strings: json_array '{"k":["a","b"]}' "k" → a\nb
json_array() {
  local json="$1" key="$2"
  echo "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\[//p" | sed 's/\].*//' | tr ',' '\n' | sed 's/[[:space:]]*"//g' | grep -v '^$'
}

# ─── List available groups ───────────────────────────────────────────────────

list_groups() {
  local groups=()
  for dir in "$SKILL_GROUPS_DIR"/*/; do
    [ -f "$dir/manifest.json" ] || continue
    local name
    name=$(basename "$dir")
    groups+=("$name")
  done
  echo "${groups[@]}"
}

# ─── Interactive selection ───────────────────────────────────────────────────

select_groups() {
  local available
  available=($(list_groups))

  header "Available skill groups:"
  echo ""
  for i in "${!available[@]}"; do
    local manifest
    manifest=$(cat "$SKILL_GROUPS_DIR/${available[$i]}/manifest.json")
    local desc
    desc=$(json_get "$manifest" "description")
    printf "  ${BOLD}%d)${NC} %-15s %s\n" $((i+1)) "${available[$i]}" "$desc"
  done
  echo ""
  printf "  ${BOLD}a)${NC} All\n"
  echo ""

  read -rp "Select groups to install (e.g. 1,3 or a): " selection

  if [ "$selection" = "a" ] || [ "$selection" = "A" ]; then
    SELECTED_GROUPS=("${available[@]}")
    return
  fi

  SELECTED_GROUPS=()
  IFS=',' read -ra indices <<< "$selection"
  for idx in "${indices[@]}"; do
    idx=$(echo "$idx" | tr -d ' ')
    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#available[@]}" ]; then
      SELECTED_GROUPS+=("${available[$((idx-1))]}")
    else
      warn "Skipping invalid selection: $idx"
    fi
  done
}

# ─── Install software dependency ────────────────────────────────────────────

install_software() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  local check_cmd
  check_cmd=$(json_get "$manifest" "check")

  # Check if already installed
  if [ -n "$check_cmd" ] && eval "$check_cmd" >/dev/null 2>&1; then
    ok "$group software already installed ($check_cmd)"
    return 0
  fi

  header "Installing $group software..."

  # Try each install method
  local methods_json
  methods_json=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  # Parse install methods — try cargo first, then pip, then manual
  for method in cargo pip npm brew manual binary; do
    local method_cmd
    method_cmd=$(echo "$methods_json" | grep -A5 "\"name\": \"$method\"" | head -6)
    [ -z "$method_cmd" ] && continue

    local cmd
    cmd=$(echo "$method_cmd" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    local prereq
    prereq=$(echo "$method_cmd" | sed -n 's/.*"check"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    local url
    url=$(echo "$method_cmd" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    # Skip if method has a prereq that's not met
    if [ -n "$prereq" ] && ! eval "$prereq" >/dev/null 2>&1; then
      info "Skipping $method install (prerequisite not met: $prereq)"
      continue
    fi

    if [ -n "$cmd" ]; then
      info "Installing via $method: $cmd"
      if eval "$cmd"; then
        ok "Installed $group via $method"
        return 0
      else
        warn "$method install failed, trying next method..."
      fi
    elif [ -n "$url" ]; then
      warn "$group requires manual installation"
      info "Download from: $url"
      read -rp "Press Enter after installing, or 's' to skip: " answer
      [ "$answer" = "s" ] && return 1
      return 0
    fi
  done

  fail "Could not install $group software"
  return 1
}

# ─── Install skills and agents ───────────────────────────────────────────────

install_skills() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

  # Check if skills come from a source repo or are bundled locally
  local source_repo
  source_repo=$(json_get "$manifest" "source_repo")

  local skills_source_dir agents_source_dir
  if [ -n "$source_repo" ]; then
    # Clone source repo to temp location
    local tmp_repo="/tmp/claude-skills-src-$group"
    if [ -d "$tmp_repo" ]; then
      info "Updating $group source repo..."
      (cd "$tmp_repo" && git pull --quiet 2>/dev/null) || true
    else
      info "Cloning $group source repo..."
      git clone --quiet "$source_repo" "$tmp_repo" 2>/dev/null
    fi

    local skills_path agents_path
    skills_path=$(echo "$manifest" | sed -n 's/.*"skills"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    agents_path=$(echo "$manifest" | sed -n 's/.*"agents"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

    # source_paths parsing
    skills_path=$(echo "$manifest" | grep -A1 '"source_paths"' | grep '"skills"' | sed 's/.*: *"//;s/".*//' )
    agents_path=$(echo "$manifest" | grep -A2 '"source_paths"' | grep '"agents"' | sed 's/.*: *"//;s/".*//' )

    skills_source_dir="$tmp_repo/$skills_path"
    agents_source_dir="$tmp_repo/$agents_path"
  else
    # Skills are bundled in this repo
    skills_source_dir="$SKILL_GROUPS_DIR/$group/skills"
    agents_source_dir="$SKILL_GROUPS_DIR/$group/agents"
  fi

  # Install skills
  local skills
  skills=$(json_array "$manifest" "skills")
  for skill in $skills; do
    local src="$skills_source_dir/$skill"
    local dest="$SKILLS_DIR/$skill"

    if [ -e "$src" ] || [ -d "$src" ]; then
      create_symlink "$src" "$dest"
      ok "Skill: $skill"
    elif [ -f "$src.md" ]; then
      create_symlink "$src.md" "$dest.md"
      ok "Skill: $skill"
    else
      warn "Skill not found: $skill (looked in $src)"
    fi
  done

  # Install agents
  local agents
  agents=$(json_array "$manifest" "agents")

  # Check for agent renames
  local renames
  renames=$(echo "$manifest" | grep -A10 '"agent_renames"' 2>/dev/null || true)

  for agent in $agents; do
    local src_file="$agent.md"

    # Check if there's a rename mapping (source file has different name)
    local rename_from
    rename_from=$(echo "$renames" | sed -n "s/.*\"\([^\"]*\)\"[[:space:]]*:[[:space:]]*\"$agent.md\".*/\1/p")
    if [ -n "$rename_from" ]; then
      src_file="$rename_from"
    fi

    local src="$agents_source_dir/$src_file"
    local dest="$AGENTS_DIR/$agent.md"

    if [ -f "$src" ]; then
      create_symlink "$src" "$dest"
      ok "Agent: $agent"
    else
      warn "Agent not found: $agent (looked in $src)"
    fi
  done
}

# ─── Run smoke test ─────────────────────────────────────────────────────────

run_test() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  local test_cmd
  test_cmd=$(echo "$manifest" | grep -A2 '"test"' | grep '"command"' | sed 's/.*: *"//;s/".*//')

  if [ -z "$test_cmd" ]; then
    warn "No test defined for $group"
    return 0
  fi

  info "Testing $group: $test_cmd"
  if eval "$test_cmd" >/dev/null 2>&1; then
    ok "$group smoke test passed"
  else
    warn "$group smoke test failed — software may not be fully configured"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  header "claude-skills installer"
  info "Platform: $PLATFORM"
  info "Target: $CLAUDE_DIR"
  echo ""

  # Parse arguments
  SELECTED_GROUPS=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skills)
        IFS=',' read -ra SELECTED_GROUPS <<< "$2"
        shift 2
        ;;
      --list)
        list_groups | tr ' ' '\n'
        exit 0
        ;;
      --help|-h)
        echo "Usage: install.sh [--skills group1,group2] [--list] [--help]"
        echo ""
        echo "Options:"
        echo "  --skills   Comma-separated list of skill groups to install"
        echo "  --list     List available skill groups"
        echo "  --help     Show this help"
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        shift
        ;;
    esac
  done

  # Interactive selection if no --skills flag
  if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    select_groups
  fi

  if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    fail "No groups selected"
    exit 1
  fi

  echo ""
  header "Installing: ${SELECTED_GROUPS[*]}"

  for group in "${SELECTED_GROUPS[@]}"; do
    if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
      fail "Unknown skill group: $group"
      continue
    fi

    header "── $group ──"

    # Step 1: Install software
    if ! install_software "$group"; then
      warn "Skipping $group skills (software not installed)"
      continue
    fi

    # Step 2: Install skills + agents
    install_skills "$group"

    # Step 3: Smoke test
    run_test "$group"
  done

  echo ""
  ok "Done! Restart Claude Code to pick up new skills."
}

main "$@"
