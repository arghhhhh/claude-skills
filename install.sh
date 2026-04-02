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

# Counters for final report
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
fail()  { echo -e "${RED}✗${NC} $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
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

  mkdir -p "$(dirname "$link_path")"

  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    rm -rf "$link_path"
  fi

  if [ "$PLATFORM" = "windows" ]; then
    if ln -s "$target" "$link_path" 2>/dev/null; then
      return 0
    fi
    local win_target win_link
    win_target=$(cygpath -w "$target" 2>/dev/null || echo "$target" | sed 's|/|\\|g')
    win_link=$(cygpath -w "$link_path" 2>/dev/null || echo "$link_path" | sed 's|/|\\|g')
    if [ -d "$target" ]; then
      cmd.exe /c "mklink /J \"$win_link\" \"$win_target\"" >/dev/null 2>&1 && return 0
      cmd.exe /c "mklink /D \"$win_link\" \"$win_target\"" >/dev/null 2>&1 && return 0
    else
      cmd.exe /c "mklink \"$win_link\" \"$win_target\"" >/dev/null 2>&1 && return 0
    fi
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

# Extract prerequisite objects from JSON — returns "name|check|install_hint|required" per line
json_prerequisites() {
  local manifest_file="$1"
  # Use a simple line-by-line parser for the prerequisites array
  local in_prereqs=false
  local name="" check="" hint="" required="true"
  while IFS= read -r line; do
    if echo "$line" | grep -q '"prerequisites"'; then
      in_prereqs=true
      continue
    fi
    if [ "$in_prereqs" = "false" ]; then continue; fi
    # End of prerequisites array
    if echo "$line" | grep -q '^\s*\]'; then
      # Emit last entry if any
      if [ -n "$name" ]; then
        echo "$name|$check|$hint|$required"
      fi
      break
    fi
    # Start of new object
    if echo "$line" | grep -q '^\s*{'; then
      # Emit previous entry
      if [ -n "$name" ]; then
        echo "$name|$check|$hint|$required"
      fi
      name=""; check=""; hint=""; required="true"
      continue
    fi
    # Parse fields
    local val
    val=$(echo "$line" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$val" ] && name="$val"
    val=$(echo "$line" | sed -n 's/.*"check"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$val" ] && check="$val"
    val=$(echo "$line" | sed -n 's/.*"install_hint"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$val" ] && hint="$val"
    val=$(echo "$line" | sed -n 's/.*"required"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')
    [ -n "$val" ] && required="$val"
  done < "$manifest_file"
}

# ─── List available groups ───────────────────────────────────────────────────

list_groups() {
  local groups=()
  for dir in "$SKILL_GROUPS_DIR"/*/; do
    [ -f "$dir/manifest.json" ] || continue
    groups+=("$(basename "$dir")")
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

# ─── Check prerequisites ────────────────────────────────────────────────────

check_prerequisites() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  local all_met=true

  local prereqs
  prereqs=$(json_prerequisites "$manifest_file")

  if [ -z "$prereqs" ]; then
    return 0
  fi

  while IFS='|' read -r name check hint required; do
    [ -z "$name" ] && continue
    if eval "$check" >/dev/null 2>&1; then
      ok "Prerequisite: $name"
    else
      if [ "$required" = "true" ]; then
        fail "Missing required prerequisite: $name"
        info "  $hint"
        all_met=false
      else
        warn "Optional prerequisite missing: $name"
        info "  $hint"
      fi
    fi
  done <<< "$prereqs"

  if [ "$all_met" = "false" ]; then
    return 1
  fi
  return 0
}

# ─── Install prerequisites (global) ─────────────────────────────────────────

install_global_prerequisites() {
  if ! command -v git >/dev/null 2>&1; then
    fail "git is required but not found — install from https://git-scm.com/"
    exit 1
  fi
  ok "git available"
}

# ─── Install software dependency ────────────────────────────────────────────

install_software() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  local check_cmd
  check_cmd=$(json_get "$manifest" "check")

  if [ -n "$check_cmd" ] && eval "$check_cmd" >/dev/null 2>&1; then
    ok "$group software already installed"
    return 0
  fi

  header "Installing $group software..."

  local methods_json
  methods_json=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  for method in cargo pip npm brew go manual binary; do
    local method_cmd
    method_cmd=$(echo "$methods_json" | grep -A5 "\"name\": \"$method\"" | head -6)
    [ -z "$method_cmd" ] && continue

    local cmd prereq url
    cmd=$(echo "$method_cmd" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    prereq=$(echo "$method_cmd" | sed -n 's/.*"check"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    url=$(echo "$method_cmd" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

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
      [ "$answer" = "s" ] && return 0
      return 0
    fi
  done

  warn "Could not auto-install $group software — skills will be installed anyway"
  return 0
}

# ─── Install skills and agents ───────────────────────────────────────────────

install_skills() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

  local source_repo
  source_repo=$(json_get "$manifest" "source_repo")

  local skills_source_dir agents_source_dir
  if [ -n "$source_repo" ]; then
    local repo_cache="$CLAUDE_DIR/.skill-repos/$group"
    mkdir -p "$CLAUDE_DIR/.skill-repos"
    if [ -d "$repo_cache" ]; then
      info "Updating $group source repo..."
      (cd "$repo_cache" && git pull --quiet 2>/dev/null) || true
    else
      info "Cloning $group source repo..."
      git clone --quiet "$source_repo" "$repo_cache" 2>/dev/null
    fi

    local skills_path agents_path
    skills_path=$(echo "$manifest" | grep -A1 '"source_paths"' | grep '"skills"' | sed 's/.*: *"//;s/".*//')
    agents_path=$(echo "$manifest" | grep -A2 '"source_paths"' | grep '"agents"' | sed 's/.*: *"//;s/".*//')

    skills_source_dir="$repo_cache/$skills_path"
    agents_source_dir="$repo_cache/$agents_path"
  else
    skills_source_dir="$SKILL_GROUPS_DIR/$group/skills"
    agents_source_dir="$SKILL_GROUPS_DIR/$group/agents"
  fi

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

  local agents
  agents=$(json_array "$manifest" "agents")
  local renames
  renames=$(echo "$manifest" | grep -A10 '"agent_renames"' 2>/dev/null || true)

  for agent in $agents; do
    local src_file="$agent.md"
    local rename_from
    rename_from=$(echo "$renames" | sed -n "s/.*\"\([^\"]*\)\"[[:space:]]*:[[:space:]]*\"$agent.md\".*/\1/p")
    [ -n "$rename_from" ] && src_file="$rename_from"

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

# ─── Configure template variables ───────────────────────────────────────────

configure_skills() {
  local group="$1"

  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  fi

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

  [ -f "$snippet_file" ] || return 0

  if [ ! -f "$CLAUDE_MD" ]; then
    echo "# Global Rules" > "$CLAUDE_MD"
    echo "" >> "$CLAUDE_MD"
  fi

  local marker
  marker=$(grep -m1 '^## ' "$snippet_file" 2>/dev/null || head -1 "$snippet_file")
  if grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
    ok "CLAUDE.md: $group snippet already present"
    return 0
  fi

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
    create_symlink "$skill_file" "$SKILLS_DIR/$name"
    ok "Shared skill: $name"
  done

  # Append shared claude-md snippets
  for snippet in mcp-setup mcporter; do
    local snippet_file="$SHARED_DIR/claude-md/$snippet.md"
    [ -f "$snippet_file" ] || continue
    if [ ! -f "$CLAUDE_MD" ]; then
      echo "# Global Rules" > "$CLAUDE_MD"
      echo "" >> "$CLAUDE_MD"
    fi
    local marker
    marker=$(grep -m1 '^## ' "$snippet_file" 2>/dev/null || head -1 "$snippet_file")
    if ! grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
      echo "" >> "$CLAUDE_MD"
      echo "---" >> "$CLAUDE_MD"
      echo "" >> "$CLAUDE_MD"
      cat "$snippet_file" >> "$CLAUDE_MD"
      ok "CLAUDE.md: appended $snippet snippet"
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

  [ -z "$test_cmd" ] && return 0

  info "Smoke test: $test_cmd"
  if eval "$test_cmd" >/dev/null 2>&1; then
    ok "$group smoke test passed"
  else
    warn "$group smoke test failed — software may need manual configuration"
  fi
}

# ─── Verify installation (--verify) ─────────────────────────────────────────

verify_group() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  header "Verifying: $group"

  # 1. Check prerequisites
  info "Prerequisites:"
  check_prerequisites "$group" || true

  # 2. Check software installed
  info "Software:"
  local check_cmd
  check_cmd=$(json_get "$manifest" "check")
  if [ -n "$check_cmd" ] && [ "$check_cmd" != "true" ]; then
    if eval "$check_cmd" >/dev/null 2>&1; then
      ok "Software binary found ($check_cmd)"
    else
      fail "Software not found ($check_cmd)"
    fi
  fi

  # 3. Check skills are linked and readable
  info "Skills:"
  local skills
  skills=$(json_array "$manifest" "skills")
  for skill in $skills; do
    local target="$SKILLS_DIR/$skill"
    if [ -d "$target" ]; then
      # Directory skill — check SKILL.md exists inside
      if [ -f "$target/SKILL.md" ]; then
        ok "Skill: $skill (directory, SKILL.md present)"
      else
        fail "Skill: $skill (directory exists but SKILL.md missing)"
      fi
    elif [ -f "$target" ] || [ -f "$target.md" ]; then
      local f="${target}"
      [ -f "$target.md" ] && f="$target.md"
      if [ -s "$f" ]; then
        ok "Skill: $skill (file, non-empty)"
      else
        fail "Skill: $skill (file exists but is empty)"
      fi
    else
      fail "Skill: $skill (not found at $target)"
    fi

    # Check for broken symlinks
    if [ -L "$target" ] && [ ! -e "$target" ]; then
      fail "Skill: $skill (broken symlink → $(readlink "$target"))"
    elif [ -L "${target}.md" ] && [ ! -e "${target}.md" ]; then
      fail "Skill: ${skill}.md (broken symlink → $(readlink "${target}.md"))"
    fi
  done

  # 4. Check agents are linked and readable
  info "Agents:"
  local agents
  agents=$(json_array "$manifest" "agents")
  if [ -z "$agents" ]; then
    info "  (no agents defined)"
  fi
  for agent in $agents; do
    local target="$AGENTS_DIR/$agent.md"
    if [ -f "$target" ] && [ -s "$target" ]; then
      ok "Agent: $agent.md (present, non-empty)"
    elif [ -f "$target" ]; then
      fail "Agent: $agent.md (exists but is empty)"
    else
      fail "Agent: $agent.md (not found)"
    fi
    # Check broken symlink
    if [ -L "$target" ] && [ ! -e "$target" ]; then
      fail "Agent: $agent.md (broken symlink → $(readlink "$target"))"
    fi
  done

  # 5. Check CLAUDE.md has trigger phrases
  info "CLAUDE.md:"
  local snippet_file="$SHARED_DIR/claude-md/$group.md"
  if [ -f "$snippet_file" ] && [ -f "$CLAUDE_MD" ]; then
    local marker
    marker=$(grep -m1 '^## ' "$snippet_file" 2>/dev/null || head -1 "$snippet_file")
    if grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
      ok "Trigger phrases present in CLAUDE.md"
    else
      fail "Trigger phrases missing from CLAUDE.md"
    fi
  elif [ ! -f "$snippet_file" ]; then
    info "  (no CLAUDE.md snippet defined for $group)"
  else
    fail "CLAUDE.md does not exist at $CLAUDE_MD"
  fi

  # 6. Check for unconfigured {{PLACEHOLDER}} vars
  info "Configuration:"
  local has_placeholders=false
  for skill in $skills; do
    local target="$SKILLS_DIR/$skill"
    if [ -f "$target" ] && grep -q '{{' "$target" 2>/dev/null; then
      has_placeholders=true
    fi
    if [ -f "$target.md" ] && grep -q '{{' "$target.md" 2>/dev/null; then
      has_placeholders=true
    fi
    # Check inside directory skills too
    if [ -d "$target" ]; then
      if grep -rq '{{' "$target" 2>/dev/null; then
        has_placeholders=true
      fi
    fi
  done
  if [ "$has_placeholders" = "true" ]; then
    warn "Unconfigured {{PLACEHOLDER}} variables found — edit skill files or create $CONFIG_FILE"
  else
    ok "No unconfigured placeholders"
  fi
}

# ─── Integration test (--test-integration) ──────────────────────────────────

integration_test_group() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  header "Integration test: $group"

  # Check if integration test is defined
  local int_cmd int_desc
  int_cmd=$(echo "$manifest" | grep -A3 '"integration_test"' | grep '"command"' | sed 's/.*: *"//;s/".*//')
  int_desc=$(echo "$manifest" | grep -A3 '"integration_test"' | grep '"description"' | sed 's/.*: *"//;s/".*//')

  if [ -z "$int_cmd" ]; then
    info "No integration test defined for $group"
    return 0
  fi

  info "Requires: $int_desc"
  info "Running: $int_cmd"

  if eval "$int_cmd" >/dev/null 2>&1; then
    ok "$group integration test passed — software is live and responding"
  else
    fail "$group integration test failed"
    info "  Make sure: $int_desc"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  SELECTED_GROUPS=()
  SKIP_SOFTWARE=false
  MODE="install"  # install, verify, test-integration

  # Parse arguments
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
      --verify)
        MODE="verify"
        shift
        ;;
      --test-integration)
        MODE="test-integration"
        shift
        ;;
      --list)
        list_groups | tr ' ' '\n'
        exit 0
        ;;
      --help|-h)
        echo "Usage: install.sh [OPTIONS]"
        echo ""
        echo "Modes:"
        echo "  (default)              Install skill groups (software + skills + agents)"
        echo "  --verify               Check installed groups: symlinks, files, CLAUDE.md, software"
        echo "  --test-integration     Test live connections (Unity running, ComfyUI server, etc.)"
        echo ""
        echo "Options:"
        echo "  --skills GROUP1,GROUP2 Target specific skill groups (default: interactive)"
        echo "  --skip-software        Skip software installation, only install skills/agents"
        echo "  --list                 List available skill groups"
        echo "  --help                 Show this help"
        echo ""
        echo "Examples:"
        echo "  install.sh                                    # Interactive install"
        echo "  install.sh --skills unity-cli                 # Install just unity-cli"
        echo "  install.sh --verify                           # Verify all installed groups"
        echo "  install.sh --verify --skills unity-cli        # Verify just unity-cli"
        echo "  install.sh --test-integration --skills comfyui"
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        shift
        ;;
    esac
  done

  header "claude-skills — $MODE"
  info "Platform: $PLATFORM"
  info "Target:   $CLAUDE_DIR"
  echo ""

  # For verify/test-integration, default to all groups if none specified
  if [ "$MODE" != "install" ] && [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    SELECTED_GROUPS=($(list_groups))
  fi

  # ── Verify mode ──
  if [ "$MODE" = "verify" ]; then
    for group in "${SELECTED_GROUPS[@]}"; do
      if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
        fail "Unknown skill group: $group"
        continue
      fi
      verify_group "$group"
    done

    echo ""
    header "Verification Summary"
    echo -e "  ${GREEN}$PASS_COUNT passed${NC}  ${YELLOW}$WARN_COUNT warnings${NC}  ${RED}$FAIL_COUNT failed${NC}"
    if [ "$FAIL_COUNT" -gt 0 ]; then
      echo ""
      info "Re-run install.sh to fix failed checks"
      exit 1
    fi
    exit 0
  fi

  # ── Integration test mode ──
  if [ "$MODE" = "test-integration" ]; then
    for group in "${SELECTED_GROUPS[@]}"; do
      if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
        fail "Unknown skill group: $group"
        continue
      fi
      integration_test_group "$group"
    done

    echo ""
    header "Integration Test Summary"
    echo -e "  ${GREEN}$PASS_COUNT passed${NC}  ${YELLOW}$WARN_COUNT warnings${NC}  ${RED}$FAIL_COUNT failed${NC}"
    [ "$FAIL_COUNT" -gt 0 ] && exit 1
    exit 0
  fi

  # ── Install mode ──

  install_global_prerequisites

  if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    select_groups
  fi

  if [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    fail "No groups selected"
    exit 1
  fi

  mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

  echo ""
  header "Installing: ${SELECTED_GROUPS[*]}"

  for group in "${SELECTED_GROUPS[@]}"; do
    if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
      fail "Unknown skill group: $group"
      continue
    fi

    header "── $group ──"

    # Step 1: Check prerequisites
    if ! check_prerequisites "$group"; then
      fail "Missing required prerequisites for $group — skipping"
      continue
    fi

    # Step 2: Install software
    if [ "$SKIP_SOFTWARE" = "false" ]; then
      install_software "$group"
    fi

    # Step 3: Install skills + agents
    install_skills "$group"

    # Step 4: Configure template variables
    configure_skills "$group"

    # Step 5: Append CLAUDE.md snippet
    install_claude_md_snippet "$group"

    # Step 6: Smoke test
    if [ "$SKIP_SOFTWARE" = "false" ]; then
      run_test "$group"
    fi
  done

  # Install shared skills
  header "── shared ──"
  install_shared_skills

  echo ""
  header "Install Summary"
  echo -e "  ${GREEN}$PASS_COUNT passed${NC}  ${YELLOW}$WARN_COUNT warnings${NC}  ${RED}$FAIL_COUNT failed${NC}"
  echo ""
  info "Skills:    $SKILLS_DIR/"
  info "Agents:    $AGENTS_DIR/"
  info "CLAUDE.md: $CLAUDE_MD"
  echo ""
  if [ "$FAIL_COUNT" -gt 0 ]; then
    warn "Some steps failed — review the output above"
  fi
  info "Run 'install.sh --verify' to check installation health"
  info "Run 'install.sh --test-integration' to test live connections"
  echo ""
  ok "Done! Restart Claude Code to pick up new skills."
}

main "$@"
