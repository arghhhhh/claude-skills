#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-skills installer
# Cross-platform (macOS, Linux, Windows via Git Bash/WSL)
# Installs selected skill groups: software + skills + agents → ~/.claude/
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_GROUPS_DIR="$SCRIPT_DIR/skill-groups"
SHARED_DIR="$SCRIPT_DIR/shared"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
CONFIG_FILE="$CLAUDE_DIR/skills-config.sh"

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

  # Ensure parent directory exists
  mkdir -p "$(dirname "$link_path")"

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

json_get() {
  local json="$1" key="$2"
  echo "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

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

# ─── Install prerequisites (mcporter, etc.) ─────────────────────────────────

install_prerequisites() {
  # Check for Node.js / npx (needed for mcporter)
  if ! command -v npx >/dev/null 2>&1; then
    warn "npx not found — MCPorter-based skills (comfyui, blender) need Node.js"
    info "Install Node.js from https://nodejs.org/"
  else
    ok "npx available"
  fi

  # Check for git
  if ! command -v git >/dev/null 2>&1; then
    fail "git is required but not found"
    exit 1
  fi
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

  local methods_json
  methods_json=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  # Try each install method in order
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
      [ "$answer" = "s" ] && return 0  # Don't block skill install
      return 0
    fi
  done

  warn "Could not auto-install $group software — skills will be installed anyway"
  return 0  # Don't block skill install
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
    # Clone source repo to a persistent location
    local repo_cache="$CLAUDE_DIR/.skill-repos/$group"
    mkdir -p "$CLAUDE_DIR/.skill-repos"
    if [ -d "$repo_cache" ]; then
      info "Updating $group source repo..."
      (cd "$repo_cache" && git pull --quiet 2>/dev/null) || true
    else
      info "Cloning $group source repo..."
      git clone --quiet "$source_repo" "$repo_cache" 2>/dev/null
    fi

    # Parse source_paths from manifest
    local skills_path agents_path
    skills_path=$(echo "$manifest" | grep -A1 '"source_paths"' | grep '"skills"' | sed 's/.*: *"//;s/".*//')
    agents_path=$(echo "$manifest" | grep -A2 '"source_paths"' | grep '"agents"' | sed 's/.*: *"//;s/".*//')

    skills_source_dir="$repo_cache/$skills_path"
    agents_source_dir="$repo_cache/$agents_path"
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

    if [ -d "$src" ]; then
      create_symlink "$src" "$dest"
      ok "Skill: $skill"
    elif [ -f "$src" ]; then
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

# ─── Apply template variables to skills ─────────────────────────────────────

configure_skills() {
  local group="$1"

  # Load config if it exists
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  fi

  # Check if any installed skill files have {{PLACEHOLDER}} vars
  local needs_config=false
  local skills
  skills=$(json_array "$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")" "skills")
  for skill in $skills; do
    local target="$SKILLS_DIR/$skill"
    [ -f "$target" ] && grep -q '{{' "$target" 2>/dev/null && needs_config=true
    [ -f "$target.md" ] && grep -q '{{' "$target.md" 2>/dev/null && needs_config=true
  done

  if [ "$needs_config" = "true" ]; then
    warn "Some $group skills have {{PLACEHOLDER}} variables that need configuring"
    info "Edit the skill files in $SKILLS_DIR/ or create $CONFIG_FILE"
    info "See config.example.sh in this repo for the template"
  fi
}

# ─── Append CLAUDE.md snippet ───────────────────────────────────────────────

install_claude_md_snippet() {
  local group="$1"
  local snippet_file="$SHARED_DIR/claude-md/$group.md"

  if [ ! -f "$snippet_file" ]; then
    return 0
  fi

  # Create CLAUDE.md if it doesn't exist
  if [ ! -f "$CLAUDE_MD" ]; then
    echo "# Global Rules" > "$CLAUDE_MD"
    echo "" >> "$CLAUDE_MD"
  fi

  # Check if snippet is already present (by first non-empty line)
  local marker
  marker=$(grep -m1 '^## ' "$snippet_file" 2>/dev/null || head -1 "$snippet_file")
  if grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
    ok "CLAUDE.md: $group snippet already present"
    return 0
  fi

  # Append snippet
  echo "" >> "$CLAUDE_MD"
  echo "---" >> "$CLAUDE_MD"
  echo "" >> "$CLAUDE_MD"
  cat "$snippet_file" >> "$CLAUDE_MD"
  ok "CLAUDE.md: appended $group trigger phrases"
}

# ─── Install shared skills ──────────────────────────────────────────────────

install_shared_skills() {
  local shared_skills_dir="$SHARED_DIR/skills"
  [ -d "$shared_skills_dir" ] || return 0

  mkdir -p "$SKILLS_DIR"
  for skill_file in "$shared_skills_dir"/*.md; do
    [ -f "$skill_file" ] || continue
    local name
    name=$(basename "$skill_file")
    local dest="$SKILLS_DIR/$name"
    create_symlink "$skill_file" "$dest"
    ok "Shared skill: $name"
  done

  # Also install the mcp-setup snippet to CLAUDE.md
  local mcp_snippet="$SHARED_DIR/claude-md/mcp-setup.md"
  if [ -f "$mcp_snippet" ]; then
    local marker
    marker=$(grep -m1 '^## ' "$mcp_snippet" 2>/dev/null || head -1 "$mcp_snippet")
    if ! grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
      echo "" >> "$CLAUDE_MD"
      echo "---" >> "$CLAUDE_MD"
      echo "" >> "$CLAUDE_MD"
      cat "$mcp_snippet" >> "$CLAUDE_MD"
      ok "CLAUDE.md: appended MCP setup snippet"
    fi
  fi

  # Install mcporter snippet
  local mcporter_snippet="$SHARED_DIR/claude-md/mcporter.md"
  if [ -f "$mcporter_snippet" ]; then
    local marker
    marker=$(grep -m1 '^## ' "$mcporter_snippet" 2>/dev/null || head -1 "$mcporter_snippet")
    if ! grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
      echo "" >> "$CLAUDE_MD"
      echo "---" >> "$CLAUDE_MD"
      echo "" >> "$CLAUDE_MD"
      cat "$mcporter_snippet" >> "$CLAUDE_MD"
      ok "CLAUDE.md: appended MCPorter usage snippet"
    fi
  fi
}

# ─── Run smoke test ─────────────────────────────────────────────────────────

run_test() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  local test_cmd
  test_cmd=$(echo "$manifest" | grep -A2 '"test"' | grep '"command"' | sed 's/.*: *"//;s/".*//')

  if [ -z "$test_cmd" ]; then
    return 0
  fi

  info "Testing $group: $test_cmd"
  if eval "$test_cmd" >/dev/null 2>&1; then
    ok "$group smoke test passed"
  else
    warn "$group smoke test failed — software may need manual configuration"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  header "claude-skills installer"
  info "Platform: $PLATFORM"
  info "Target:   $CLAUDE_DIR"
  echo ""

  # Parse arguments
  SELECTED_GROUPS=()
  SKIP_SOFTWARE=false
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skills)
        IFS=',' read -ra SELECTED_GROUPS <<< "$2"
        shift 2
        ;;
      --skip-software)
        SKIP_SOFTWARE=true
        shift
        ;;
      --list)
        list_groups | tr ' ' '\n'
        exit 0
        ;;
      --help|-h)
        echo "Usage: install.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --skills GROUP1,GROUP2   Install specific skill groups"
        echo "  --skip-software          Skip software installation, only install skills"
        echo "  --list                   List available skill groups"
        echo "  --help                   Show this help"
        echo ""
        echo "Examples:"
        echo "  install.sh                          # Interactive selection"
        echo "  install.sh --skills unity-cli       # Install just unity-cli"
        echo "  install.sh --skills unity-cli,blender --skip-software"
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        shift
        ;;
    esac
  done

  # Check prerequisites
  install_prerequisites

  # Interactive selection if no --skills flag
  if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    select_groups
  fi

  if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    fail "No groups selected"
    exit 1
  fi

  # Ensure directories exist
  mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

  echo ""
  header "Installing: ${SELECTED_GROUPS[*]}"

  for group in "${SELECTED_GROUPS[@]}"; do
    if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
      fail "Unknown skill group: $group"
      continue
    fi

    header "── $group ──"

    # Step 1: Install software
    if [ "$SKIP_SOFTWARE" = "false" ]; then
      install_software "$group"
    fi

    # Step 2: Install skills + agents
    install_skills "$group"

    # Step 3: Configure template variables
    configure_skills "$group"

    # Step 4: Append CLAUDE.md snippet
    install_claude_md_snippet "$group"

    # Step 5: Smoke test
    if [ "$SKIP_SOFTWARE" = "false" ]; then
      run_test "$group"
    fi
  done

  # Install shared skills (mcp-setup, etc.)
  header "── shared ──"
  install_shared_skills

  echo ""
  header "Summary"
  info "Skills installed to: $SKILLS_DIR/"
  info "Agents installed to: $AGENTS_DIR/"
  info "CLAUDE.md updated:   $CLAUDE_MD"
  if [ -f "$CONFIG_FILE" ]; then
    info "Config loaded from:  $CONFIG_FILE"
  else
    info "No config file at:   $CONFIG_FILE (see config.example.sh)"
  fi
  echo ""
  ok "Done! Restart Claude Code to pick up new skills."
}

main "$@"
