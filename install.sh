#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-skills installer v2
# Cross-platform (macOS, Linux, Windows via Git Bash/WSL)
# Installs, updates, and syncs skill groups: software + skills + agents → ~/.claude/
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_GROUPS_DIR="$SCRIPT_DIR/skill-groups"
SHARED_DIR="$SCRIPT_DIR/shared"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
CONFIG_FILE="$CLAUDE_DIR/skills-config.sh"
META_DIR="$CLAUDE_DIR/.skills-meta"
BACKUP_DIR="$CLAUDE_DIR/.skill-backups"
CANONICAL_DIR="$HOME/.claude/.skill-repos/claude-skills"

# Counters for final report
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; DIM=''; NC=''
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

# ─── Canonical repo location ─────────────────────────────────────────────────

ensure_canonical_location() {
  # Already in canonical location
  if [ "$SCRIPT_DIR" = "$CANONICAL_DIR" ]; then
    return 0
  fi

  # Check if path is ephemeral (tmp, temp, etc.)
  local is_ephemeral=false
  case "$SCRIPT_DIR" in
    /tmp/*|/var/tmp/*|*/Temp/*|*/temp/*) is_ephemeral=true ;;
  esac

  if [ "$is_ephemeral" = "true" ]; then
    warn "Repo is in a temporary directory ($SCRIPT_DIR)"
    warn "Symlinks will break when this directory is cleaned up"
    echo ""
    info "The repo will be copied to: $CANONICAL_DIR"
    read -rp "Proceed? [Y/n]: " answer
    if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
      warn "Continuing from $SCRIPT_DIR — symlinks may break later"
      return 0
    fi
  else
    info "Repo is at: $SCRIPT_DIR"
    info "Canonical location is: $CANONICAL_DIR"
    read -rp "Copy repo to canonical location? [Y/n]: " answer
    if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
      return 0
    fi
  fi

  mkdir -p "$(dirname "$CANONICAL_DIR")"
  if [ -d "$CANONICAL_DIR/.git" ]; then
    # Update existing canonical copy
    info "Updating existing canonical copy..."
    rsync -a --exclude='.git' "$SCRIPT_DIR/" "$CANONICAL_DIR/"
  else
    # Fresh copy
    cp -r "$SCRIPT_DIR" "$CANONICAL_DIR"
  fi
  ok "Copied to $CANONICAL_DIR"

  # Store repo path for future reference
  mkdir -p "$META_DIR"
  echo "$CANONICAL_DIR" > "$META_DIR/repo-path"

  # Re-exec from canonical location, passing all args
  chmod +x "$CANONICAL_DIR/install.sh"
  exec "$CANONICAL_DIR/install.sh" "$@"
}

# ─── Symlink helper (cross-platform) ────────────────────────────────────────

create_symlink() {
  local target="$1"
  local link_path="$2"

  mkdir -p "$(dirname "$link_path")"

  # Handle existing files — back up if not our own symlink
  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    if [ -L "$link_path" ]; then
      local existing_target
      existing_target=$(readlink "$link_path")
      # If it already points to our target, nothing to do
      if [ "$existing_target" = "$target" ]; then
        return 0
      fi
      # If it points somewhere in our repo, safe to overwrite
      case "$existing_target" in
        "$SCRIPT_DIR"/*|"$CANONICAL_DIR"/*|"$CLAUDE_DIR/.skill-repos/"*)
          rm -f "$link_path"
          ;;
        *)
          # Points elsewhere — back it up
          backup_file "$link_path"
          rm -f "$link_path"
          ;;
      esac
    else
      # Real file or directory — back it up
      backup_file "$link_path"
      rm -rf "$link_path"
    fi
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

# ─── Backup helper ───────────────────────────────────────────────────────────

backup_file() {
  local path="$1"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local dest="$BACKUP_DIR/$timestamp"
  mkdir -p "$dest"

  local name
  name=$(basename "$path")
  # Preserve subdirectory structure relative to skills dir
  local rel_dir=""
  case "$path" in
    "$SKILLS_DIR"/*)
      rel_dir=$(dirname "${path#"$SKILLS_DIR"/}")
      [ "$rel_dir" = "." ] && rel_dir=""
      ;;
    "$AGENTS_DIR"/*)
      rel_dir="agents"
      ;;
  esac

  if [ -n "$rel_dir" ]; then
    mkdir -p "$dest/$rel_dir"
    cp -r "$path" "$dest/$rel_dir/$name"
  else
    cp -r "$path" "$dest/$name"
  fi
  info "Backed up existing $(basename "$path") → $dest/"
}

# ─── JSON parser (portable, no jq dependency) ───────────────────────────────

json_get() {
  local json="$1" key="$2"
  echo "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Extract the "check" field from the "install" block (not from prerequisites or methods)
json_get_install_check() {
  local json="$1"
  echo "$json" | tr '\n' ' ' | sed -n 's/.*"install"[[:space:]]*:[[:space:]]*{[[:space:]]*"check"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

json_array() {
  local json="$1" key="$2"
  # Collapse to single line, extract array content between [ and ], split by comma
  echo "$json" | tr '\n' ' ' | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" | tr ',' '\n' | sed 's/[[:space:]]*"//g' | grep -v '^$' || true
}

# Extract prerequisite objects from JSON — returns "name|check|install_hint|required" per line
json_prerequisites() {
  local manifest_file="$1"
  local in_prereqs=false
  local name="" check="" hint="" required="true"
  while IFS= read -r line; do
    if echo "$line" | grep -q '"prerequisites"'; then
      # Handle empty array on same line: "prerequisites": []
      if echo "$line" | grep -q '"prerequisites"[[:space:]]*:[[:space:]]*\[\]'; then
        return
      fi
      in_prereqs=true
      continue
    fi
    if [ "$in_prereqs" = "false" ]; then continue; fi
    if echo "$line" | grep -q '^\s*\]'; then
      if [ -n "$name" ]; then
        echo "$name|$check|$hint|$required"
      fi
      break
    fi
    if echo "$line" | grep -q '^\s*{'; then
      if [ -n "$name" ]; then
        echo "$name|$check|$hint|$required"
      fi
      name=""; check=""; hint=""; required="true"
      continue
    fi
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

# ─── Version helpers ─────────────────────────────────────────────────────────

# Extract version from YAML frontmatter of a skill file
skill_get_version() {
  local file="$1"
  # Handle directory skills — look for SKILL.md
  [ -d "$file" ] && file="$file/SKILL.md"
  # Try .md extension
  [ ! -f "$file" ] && [ -f "${file}.md" ] && file="${file}.md"
  [ -f "$file" ] || { echo "0.0.0"; return; }

  local version
  version=$(sed -n '/^---$/,/^---$/{
    s/^version:[[:space:]]*\(.*\)/\1/p
  }' "$file" | head -1)

  # Strip quotes if present
  version=$(echo "$version" | sed 's/^["'"'"']//;s/["'"'"']$//')

  if [ -z "$version" ]; then
    echo "0.0.0"
  else
    echo "$version"
  fi
}

# Compare semver: returns 0 if equal, 1 if v1 > v2, 2 if v1 < v2
semver_compare() {
  local v1="$1" v2="$2"
  [ "$v1" = "$v2" ] && return 0

  local IFS=.
  local v1_parts=($v1) v2_parts=($v2)
  local i
  for i in 0 1 2; do
    local a="${v1_parts[$i]:-0}" b="${v2_parts[$i]:-0}"
    if [ "$a" -gt "$b" ] 2>/dev/null; then return 1; fi
    if [ "$a" -lt "$b" ] 2>/dev/null; then return 2; fi
  done
  return 0
}

# Check if a local skill differs from its repo counterpart (content-wise)
diff_skill() {
  local local_path="$1" repo_path="$2"

  # If local is a symlink to the repo path, they're identical
  if [ -L "$local_path" ]; then
    local target
    target=$(readlink "$local_path")
    [ "$target" = "$repo_path" ] && return 0
  fi

  if [ -d "$local_path" ]; then
    diff -rq "$local_path" "$repo_path" >/dev/null 2>&1
  else
    diff -q "$local_path" "$repo_path" >/dev/null 2>&1
  fi
}

# Resolve the actual file path for a skill (handles .md extension, directories)
resolve_skill_path() {
  local base="$1"
  if [ -d "$base" ]; then
    echo "$base"
  elif [ -f "$base" ]; then
    echo "$base"
  elif [ -f "${base}.md" ]; then
    echo "${base}.md"
  else
    echo ""
  fi
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
  check_cmd=$(json_get_install_check "$manifest")

  if [ -n "$check_cmd" ] && [ "$check_cmd" != "true" ] && eval "$check_cmd" >/dev/null 2>&1; then
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
      ok "Skill: $skill (v$(skill_get_version "$src"))"
    elif [ -f "$src" ]; then
      create_symlink "$src" "$dest"
      ok "Skill: $skill (v$(skill_get_version "$src"))"
    elif [ -f "$src.md" ]; then
      create_symlink "$src.md" "$dest.md"
      ok "Skill: $skill (v$(skill_get_version "$src.md"))"
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

  local manifest skills
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")
  skills=$(json_array "$manifest" "skills")

  # Collect all files that have placeholders
  local files_with_placeholders=()
  for skill in $skills; do
    local target="$SKILLS_DIR/$skill"
    for f in "$target" "$target.md"; do
      [ -f "$f" ] || continue
      if grep -q '{{' "$f" 2>/dev/null; then
        files_with_placeholders+=("$f")
      fi
    done
    # Check inside directory skills
    if [ -d "$target" ]; then
      while IFS= read -r -d '' f; do
        if grep -q '{{' "$f" 2>/dev/null; then
          files_with_placeholders+=("$f")
        fi
      done < <(find "$target" -name '*.md' -print0 2>/dev/null)
    fi
  done

  # No placeholders — nothing to do
  if [ ${#files_with_placeholders[@]} -eq 0 ]; then
    return 0
  fi

  # No config file — warn and return
  if [ ! -f "$CONFIG_FILE" ]; then
    warn "Some $group skills have {{PLACEHOLDER}} variables that need configuring"
    info "Create $CONFIG_FILE (see config.example.sh) and re-run"
    return 0
  fi

  # Source config and build substitution map
  source "$CONFIG_FILE"

  # Dynamically discover all uppercase variables set in the config file
  local config_vars
  config_vars=$(grep -oE '^[A-Z_]+=' "$CONFIG_FILE" | sed 's/=$//' || true)

  local any_substituted=false
  for f in "${files_with_placeholders[@]}"; do
    # If the file is a symlink, replace with a copy so we don't modify the repo
    if [ -L "$f" ]; then
      local real_target
      real_target=$(readlink "$f")
      rm "$f"
      cp "$real_target" "$f"
    fi

    for var in $config_vars; do
      local val="${!var:-}"
      [ -z "$val" ] && continue
      if grep -q "{{${var}}}" "$f" 2>/dev/null; then
        sed -i'' -e "s|{{${var}}}|${val}|g" "$f"
        any_substituted=true
      fi
    done
  done

  if [ "$any_substituted" = "true" ]; then
    ok "Configured $group placeholders from $CONFIG_FILE"
  fi

  # Check if any placeholders remain
  local remaining=false
  for f in "${files_with_placeholders[@]}"; do
    if grep -q '{{' "$f" 2>/dev/null; then
      remaining=true
      break
    fi
  done
  if [ "$remaining" = "true" ]; then
    warn "Some $group placeholders still unconfigured — update $CONFIG_FILE"
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
    ok "Shared skill: $name (v$(skill_get_version "$skill_file"))"
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

  # 2. Check software installed (using install-specific check command)
  info "Software:"
  local check_cmd
  check_cmd=$(json_get_install_check "$manifest")
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
      if [ -f "$target/SKILL.md" ]; then
        local ver
        ver=$(skill_get_version "$target")
        ok "Skill: $skill (directory, v$ver)"
      else
        fail "Skill: $skill (directory exists but SKILL.md missing)"
      fi
    elif [ -f "$target" ] || [ -f "$target.md" ]; then
      local f="${target}"
      [ -f "$target.md" ] && f="$target.md"
      if [ -s "$f" ]; then
        local ver
        ver=$(skill_get_version "$f")
        ok "Skill: $skill (v$ver)"
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

# ─── Update mode (--update) ─────────────────────────────────────────────────

update_group() {
  local group="$1"
  local manifest
  manifest=$(cat "$SKILL_GROUPS_DIR/$group/manifest.json")

  header "Updating: $group"

  local source_repo
  source_repo=$(json_get "$manifest" "source_repo")

  local skills_source_dir agents_source_dir
  if [ -n "$source_repo" ]; then
    local repo_cache="$CLAUDE_DIR/.skill-repos/$group"
    if [ -d "$repo_cache" ]; then
      info "Pulling latest from $group source repo..."
      (cd "$repo_cache" && git pull --quiet 2>/dev/null) || warn "Could not pull $group source repo"
    else
      info "Cloning $group source repo..."
      mkdir -p "$CLAUDE_DIR/.skill-repos"
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
    local repo_path local_path
    repo_path=$(resolve_skill_path "$skills_source_dir/$skill")
    local_path=$(resolve_skill_path "$SKILLS_DIR/$skill")

    # Skill not in repo
    if [ -z "$repo_path" ]; then
      warn "$skill: not found in repo"
      continue
    fi

    # Skill not installed locally
    if [ -z "$local_path" ]; then
      info "$skill: not installed locally — installing"
      if [ -d "$repo_path" ]; then
        create_symlink "$repo_path" "$SKILLS_DIR/$skill"
      elif [ -f "$repo_path" ]; then
        local dest="$SKILLS_DIR/$skill"
        [[ "$repo_path" == *.md ]] && dest="$SKILLS_DIR/$skill.md"
        create_symlink "$repo_path" "$dest"
      fi
      ok "$skill: installed (v$(skill_get_version "$repo_path"))"
      continue
    fi

    update_skill "$skill" "$local_path" "$repo_path"
  done

  # Update agents
  local agents
  agents=$(json_array "$manifest" "agents")
  for agent in $agents; do
    local repo_agent="$agents_source_dir/$agent.md"
    local local_agent="$AGENTS_DIR/$agent.md"

    # Handle agent renames
    local renames
    renames=$(echo "$manifest" | grep -A10 '"agent_renames"' 2>/dev/null || true)
    local rename_from
    rename_from=$(echo "$renames" | sed -n "s/.*\"\([^\"]*\)\"[[:space:]]*:[[:space:]]*\"$agent.md\".*/\1/p")
    [ -n "$rename_from" ] && repo_agent="$agents_source_dir/$rename_from"

    if [ -f "$repo_agent" ] && [ -f "$local_agent" ]; then
      if ! diff_skill "$local_agent" "$repo_agent"; then
        info "Agent $agent.md has changed in repo — updating"
        backup_file "$local_agent"
        rm -f "$local_agent"
        create_symlink "$repo_agent" "$local_agent"
        ok "Agent: $agent (updated)"
      else
        ok "Agent: $agent (up to date)"
      fi
    elif [ -f "$repo_agent" ]; then
      create_symlink "$repo_agent" "$local_agent"
      ok "Agent: $agent (installed)"
    fi
  done
}

update_skill() {
  local skill_name="$1" local_path="$2" repo_path="$3"

  local local_ver repo_ver
  local_ver=$(skill_get_version "$local_path")
  repo_ver=$(skill_get_version "$repo_path")

  # Compare versions
  local cmp=0
  semver_compare "$repo_ver" "$local_ver" && cmp=$? || cmp=$?

  if [ $cmp -eq 1 ]; then
    # Repo is newer
    info "$skill_name: $local_ver → $repo_ver"
    backup_file "$local_path"
    rm -rf "$local_path"
    if [ -d "$repo_path" ]; then
      create_symlink "$repo_path" "$local_path"
    else
      create_symlink "$repo_path" "$local_path"
    fi
    ok "$skill_name: updated to v$repo_ver"

  elif [ $cmp -eq 2 ]; then
    # Local is newer
    if [ "$SYNC_MODE" = "true" ]; then
      warn "$skill_name: local (v$local_ver) is newer than repo (v$repo_ver)"
      read -rp "  Sync local version back to repo? [y/N]: " answer
      if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        sync_skill_to_repo "$local_path" "$repo_path"
        ok "$skill_name: synced v$local_ver back to repo"
      else
        info "$skill_name: keeping local v$local_ver"
      fi
    else
      warn "$skill_name: local (v$local_ver) is newer than repo (v$repo_ver) — use --sync to push back"
    fi

  else
    # Same version — check content
    if ! diff_skill "$local_path" "$repo_path"; then
      warn "$skill_name: same version (v$local_ver) but content differs"
      if [ "$SYNC_MODE" = "true" ]; then
        read -rp "  Keep [l]ocal, use [r]epo, or [s]kip? " answer
        case "$answer" in
          r|R)
            backup_file "$local_path"
            rm -rf "$local_path"
            create_symlink "$repo_path" "$local_path"
            ok "$skill_name: replaced with repo version"
            ;;
          l|L)
            info "$skill_name: keeping local version"
            read -rp "  Copy local version to repo? [y/N]: " sync_answer
            if [ "$sync_answer" = "y" ] || [ "$sync_answer" = "Y" ]; then
              sync_skill_to_repo "$local_path" "$repo_path"
              ok "$skill_name: synced to repo"
            fi
            ;;
          *)
            info "$skill_name: skipped"
            ;;
        esac
      else
        info "  Use --sync to resolve"
      fi
    else
      ok "$skill_name: up to date (v$local_ver)"
    fi
  fi
}

# ─── Sync skill back to repo ────────────────────────────────────────────────

sync_skill_to_repo() {
  local local_path="$1" repo_path="$2"

  # If local is a symlink to repo, no sync needed
  if [ -L "$local_path" ]; then
    local target
    target=$(readlink "$local_path")
    if [ "$target" = "$repo_path" ]; then
      info "Symlink already points to repo — no sync needed"
      return 0
    fi
    # Resolve symlink for copy
    local_path=$(readlink "$local_path")
  fi

  if [ -d "$local_path" ]; then
    # Directory skill — sync contents
    rsync -a --delete "$local_path/" "$repo_path/"
  else
    cp "$local_path" "$repo_path"
  fi
  info "Copied to repo. Run 'cd $(dirname "$repo_path") && git add -A && git commit && git push' to share."
}

# ─── Status mode (--status) ─────────────────────────────────────────────────

show_status() {
  header "Skill Status"
  echo ""
  printf "  ${BOLD}%-30s %-10s %-10s %s${NC}\n" "Skill" "Local" "Repo" "Status"
  printf "  %-30s %-10s %-10s %s\n" "──────────────────────────────" "──────────" "──────────" "──────────────"

  for group_dir in "$SKILL_GROUPS_DIR"/*/; do
    [ -f "$group_dir/manifest.json" ] || continue
    local group
    group=$(basename "$group_dir")
    local manifest
    manifest=$(cat "$group_dir/manifest.json")

    local source_repo
    source_repo=$(json_get "$manifest" "source_repo")
    local skills_source_dir
    if [ -n "$source_repo" ]; then
      local repo_cache="$CLAUDE_DIR/.skill-repos/$group"
      local skills_path
      skills_path=$(echo "$manifest" | grep -A1 '"source_paths"' | grep '"skills"' | sed 's/.*: *"//;s/".*//')
      skills_source_dir="$repo_cache/$skills_path"
    else
      skills_source_dir="$SKILL_GROUPS_DIR/$group/skills"
    fi

    local skills
    skills=$(json_array "$manifest" "skills")
    for skill in $skills; do
      local repo_path local_path local_ver repo_ver status
      repo_path=$(resolve_skill_path "$skills_source_dir/$skill")
      local_path=$(resolve_skill_path "$SKILLS_DIR/$skill")

      repo_ver=$(skill_get_version "$repo_path")
      [ "$repo_ver" = "0.0.0" ] && repo_ver="-"

      if [ -z "$local_path" ]; then
        local_ver="-"
        status="${RED}not installed${NC}"
      else
        local_ver=$(skill_get_version "$local_path")
        [ "$local_ver" = "0.0.0" ] && local_ver="-"

        if [ "$local_ver" = "-" ] && [ "$repo_ver" = "-" ]; then
          status="${YELLOW}unversioned${NC}"
        elif [ "$local_ver" = "-" ]; then
          status="${YELLOW}local unversioned${NC}"
        elif [ "$repo_ver" = "-" ]; then
          status="${YELLOW}repo unversioned${NC}"
        else
          local cmp=0
          semver_compare "$repo_ver" "$local_ver" && cmp=$? || cmp=$?
          if [ $cmp -eq 0 ]; then
            if [ -n "$repo_path" ] && ! diff_skill "$local_path" "$repo_path"; then
              status="${YELLOW}content differs${NC}"
            else
              status="${GREEN}up to date${NC}"
            fi
          elif [ $cmp -eq 1 ]; then
            status="${BLUE}update available${NC}"
          else
            status="${YELLOW}local newer${NC}"
          fi
        fi
      fi

      printf "  %-30s %-10s %-10s " "$group/$skill" "$local_ver" "$repo_ver"
      echo -e "$status"
    done
  done

  # Show locally installed skills not managed by any group
  echo ""
  header "Unmanaged Skills"
  local all_managed_skills=""
  for group_dir in "$SKILL_GROUPS_DIR"/*/; do
    [ -f "$group_dir/manifest.json" ] || continue
    local manifest
    manifest=$(cat "$group_dir/manifest.json")
    all_managed_skills="$all_managed_skills $(json_array "$manifest" "skills")"
  done

  local found_unmanaged=false
  for item in "$SKILLS_DIR"/*; do
    [ -e "$item" ] || continue
    local name
    name=$(basename "$item" .md)
    # Skip if it's managed
    local is_managed=false
    for managed in $all_managed_skills mcp-setup; do
      if [ "$name" = "$managed" ] || [ "$name" = "$(basename "$managed")" ]; then
        is_managed=true
        break
      fi
    done
    if [ "$is_managed" = "false" ]; then
      found_unmanaged=true
      local ver
      ver=$(skill_get_version "$item")
      [ "$ver" = "0.0.0" ] && ver="-"
      printf "  %-30s v%-10s %s\n" "$name" "$ver" "${DIM}(not from repo)${NC}"
    fi
  done
  if [ "$found_unmanaged" = "false" ]; then
    info "  (none)"
  fi
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  SELECTED_GROUPS=()
  SKIP_SOFTWARE=false
  SYNC_MODE=false
  MODE="install"  # install, verify, test-integration, update, status

  # Save original args for re-exec
  local original_args=("$@")

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
      --update)
        MODE="update"
        shift
        ;;
      --sync)
        SYNC_MODE=true
        shift
        ;;
      --status)
        MODE="status"
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
        echo "  --update               Update installed skills from repo (newer repo → local)"
        echo "  --update --sync        Also sync newer local skills back to repo"
        echo "  --status               Show version table for all skills"
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
        echo "  install.sh --update                           # Update all groups from repo"
        echo "  install.sh --update --sync                    # Bidirectional sync"
        echo "  install.sh --status                           # Version overview"
        echo "  install.sh --test-integration --skills comfyui"
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        shift
        ;;
    esac
  done

  # ── Ensure canonical repo location (for install/update modes) ──
  if [ "$MODE" = "install" ] || [ "$MODE" = "update" ]; then
    ensure_canonical_location "${original_args[@]}"
  fi

  header "claude-skills — $MODE"
  info "Platform: $PLATFORM"
  info "Target:   $CLAUDE_DIR"
  info "Repo:     $SCRIPT_DIR"
  echo ""

  # For non-install modes, default to all groups if none specified
  if [ "$MODE" != "install" ] && [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    SELECTED_GROUPS=($(list_groups))
  fi

  # ── Status mode ──
  if [ "$MODE" = "status" ]; then
    show_status
    exit 0
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

  # ── Update mode ──
  if [ "$MODE" = "update" ]; then
    for group in "${SELECTED_GROUPS[@]}"; do
      if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
        fail "Unknown skill group: $group"
        continue
      fi
      update_group "$group"
    done

    echo ""
    header "Update Summary"
    echo -e "  ${GREEN}$PASS_COUNT passed${NC}  ${YELLOW}$WARN_COUNT warnings${NC}  ${RED}$FAIL_COUNT failed${NC}"
    if [ "$SYNC_MODE" = "true" ] && [ "$WARN_COUNT" -gt 0 ]; then
      echo ""
      info "Don't forget to commit and push repo changes if you synced skills back"
    fi
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

    # Step 1: Check prerequisites (fail message already emitted inside)
    if ! check_prerequisites "$group"; then
      info "Skipping $group due to missing prerequisites"
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
  info "Run 'install.sh --status' to see version overview"
  info "Run 'install.sh --test-integration' to test live connections"
  echo ""
  ok "Done! Restart Claude Code to pick up new skills."
}

main "$@"
