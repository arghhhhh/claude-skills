#!/usr/bin/env bash

# Re-exec under bash ≥ 4 if launched with macOS's stock bash 3.2.
# Bash 3.2 mis-parses heredoc-in-$()-containing-case (see install_shell_aliases),
# so we hand off to Homebrew's bash when present.
if [ -n "${BASH_VERSINFO[0]:-}" ] && [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ -z "${CLAUDE_SKILLS_BASH_REEXEC:-}" ]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "$candidate" ]; then
      export CLAUDE_SKILLS_BASH_REEXEC=1
      exec "$candidate" "$0" "$@"
    fi
  done
  echo "install.sh requires bash ≥ 4. On macOS: brew install bash" >&2
  exit 1
fi

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# claude-skills installer v2.4 — typed groups (authored / vendored / tool-only)
# Cross-platform (macOS, Linux, Windows via Git Bash/WSL)
# Installs, updates, and syncs skill groups: software + skills + agents + commands → ~/.claude/
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_GROUPS_DIR="$SCRIPT_DIR/skill-groups"
SHARED_DIR="$SCRIPT_DIR/shared"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$CLAUDE_DIR/agents"
COMMANDS_DIR="$CLAUDE_DIR/commands"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
CONFIG_FILE="$CLAUDE_DIR/skills-config.sh"
META_DIR="$CLAUDE_DIR/.skills-meta"
KNOWN_GROUPS_FILE="$META_DIR/known-groups"
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
    if [ "$NON_INTERACTIVE" != "true" ]; then
      read -rp "Proceed? [Y/n]: " answer
      if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
        warn "Continuing from $SCRIPT_DIR — symlinks may break later"
        return 0
      fi
    fi
  else
    info "Repo is at: $SCRIPT_DIR"
    info "Canonical location is: $CANONICAL_DIR"
    if [ "$NON_INTERACTIVE" != "true" ]; then
      read -rp "Copy repo to canonical location? [Y/n]: " answer
      if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
        return 0
      fi
    fi
  fi

  mkdir -p "$(dirname "$CANONICAL_DIR")"
  if [ -d "$CANONICAL_DIR/.git" ]; then
    # Update existing canonical copy (preserve .git)
    info "Updating existing canonical copy..."
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --exclude='.git' "$SCRIPT_DIR/" "$CANONICAL_DIR/"
    else
      # Fallback for Windows/environments without rsync
      find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -r {} "$CANONICAL_DIR/" \;
    fi
  else
    # Fresh copy. If $CANONICAL_DIR exists as a non-git directory (e.g.,
    # a partial copy from an interrupted previous run), `cp -r SRC DST`
    # would copy SRC INSIDE DST, leaving install.sh one level too deep
    # and breaking the re-exec below. Use `cp -r SRC/. DST/` so contents
    # are copied into DST whether it exists or not.
    mkdir -p "$CANONICAL_DIR"
    cp -r "$SCRIPT_DIR/." "$CANONICAL_DIR/"
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
  echo "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1 | tr -d '\r'
}

# Extract the "check" field from the "install" block (not from prerequisites or methods)
json_get_install_check() {
  local json="$1"
  echo "$json" | tr '\n' ' ' | sed -n 's/.*"install"[[:space:]]*:[[:space:]]*{[[:space:]]*"check"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr -d '\r'
}

# Substitute {{VAR}} placeholders in a string using values from $CONFIG_FILE.
# Mirrors the install-time substitution (lines ~1311-1336) so verify and
# integration tests don't fail on literal placeholders when the user has
# actually configured the path. Returns the input unchanged when CONFIG_FILE
# is missing or a variable isn't set.
subst_placeholders() {
  local s="$1"
  [ -f "$CONFIG_FILE" ] || { printf '%s' "$s"; return; }
  # Source in a subshell would lose vars; source here but only read names
  # we know about from the config file.
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  local var val
  for var in $(grep -oE '^[A-Z_]+=' "$CONFIG_FILE" | sed 's/=$//'); do
    val="${!var:-}"
    [ -z "$val" ] && continue
    s="${s//\{\{${var}\}\}/$val}"
  done
  printf '%s' "$s"
}

# Escape a string for safe use on the replacement side of sed `s|...|REPL|`.
# Without this, values containing `|` (delimiter), `&` (full-match backref),
# or `\` (backslash escapes like `\n`/`\1`) corrupt the substitution. Hits
# Windows paths hard: `C:\Users\…` would have `\U` interpreted as an escape.
sed_escape_repl() {
  printf '%s' "$1" | sed 's/[|&\\]/\\&/g'
}

# Source $CONFIG_FILE in a subshell and emit a JSON object of {VAR: value}
# for every uppercase variable defined there. Used to hand placeholder
# values to inline node scripts without parsing skills-config.sh in node
# (the previous regex dropped values containing quotes, spaces, or empty
# strings, and didn't expand $HOME etc.). Bash sources it correctly; node
# just consumes the result.
config_placeholders_json() {
  [ -f "$CONFIG_FILE" ] || { printf '{}'; return; }
  (
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    local var val first=1
    printf '{'
    for var in $(grep -oE '^[A-Z_]+=' "$CONFIG_FILE" | sed 's/=$//'); do
      val="${!var:-}"
      [ -z "$val" ] && continue
      # JSON-escape: backslash, quote, control chars (covers Windows paths)
      val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
      [ $first -eq 1 ] || printf ','
      printf '"%s":"%s"' "$var" "$val"
      first=0
    done
    printf '}'
  )
}

# True if the group's manifest declares any mcp_servers. Used by verify to
# distinguish "the app binary is missing" (MCP still works on other machines,
# config is intact here) from a hard install failure.
group_has_mcp_servers() {
  local group="$1"
  grep -q '"mcp_servers"' "$SKILL_GROUPS_DIR/$group/manifest.json" 2>/dev/null
}

json_array() {
  local json="$1" key="$2"
  # Collapse to single line, extract array content between [ and ], split by comma
  echo "$json" | tr '\n' ' ' | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p" | tr ',' '\n' | sed 's/[[:space:]]*"//g' | tr -d '\r' | grep -v '^$' || true
}

# Extract prerequisite objects from JSON — returns "name|check|install_hint|required|note" per line
# Uses node for reliable JSON parsing to avoid sed/grep issues with field ordering
json_prerequisites() {
  local manifest_file="$1"
  node -e "
    const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const prereqs = m.prerequisites || [];
    for (const p of prereqs) {
      const name = p.name || '';
      const check = p.check || '';
      const hint = p.install_hint || '';
      const required = p.required !== false ? 'true' : 'false';
      const note = p.note || '';
      console.log([name, check, hint, required, note].join('|'));
    }
  " "$manifest_file" 2>/dev/null || true
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
  # Check for top-level version: or nested metadata.version:
  version=$(sed -n '/^---$/,/^---$/{
    s/^version:[[:space:]]*\(.*\)/\1/p
    s/^[[:space:]]*version:[[:space:]]*\(.*\)/\1/p
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

# Stream a placeholder-substituted version of a file to stdout. Mirrors the
# install-time substitution (lines ~1311-1336) so a diff against the
# installed file isn't fooled by resolved {{PLACEHOLDER}} vars.
subst_file_to_stdout() {
  local file="$1"
  # Fast path 1: no config file → no substitutions possible
  if [ ! -f "$CONFIG_FILE" ]; then
    cat "$file"
    return
  fi
  # Fast path 2: file contains no {{UPPER_SNAKE}} tokens → skip sed entirely.
  # This is critical on Git Bash, where sed normalizes CRLF → LF and would
  # silently corrupt diffs against CRLF-encoded installed files.
  if ! grep -Eq '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null; then
    cat "$file"
    return
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  local var val val_esc expr=""
  for var in $(grep -oE '^[A-Z_]+=' "$CONFIG_FILE" | sed 's/=$//'); do
    val="${!var:-}"
    [ -z "$val" ] && continue
    val_esc=$(sed_escape_repl "$val")
    expr="${expr}s|{{${var}}}|${val_esc}|g;"
  done
  if [ -n "$expr" ]; then
    sed -e "$expr" "$file"
  else
    cat "$file"
  fi
}

# Check if a local skill differs from its repo counterpart (content-wise).
# Substitution-aware: compares local against a placeholder-substituted view
# of the repo file, so post-install substitution doesn't appear as drift.
diff_skill() {
  local local_path="$1" repo_path="$2"

  # If local is a symlink to the repo path, they're identical
  if [ -L "$local_path" ]; then
    local target
    target=$(readlink "$local_path")
    [ "$target" = "$repo_path" ] && return 0
  fi

  if [ -d "$local_path" ] && [ -d "$repo_path" ]; then
    # Every repo file must have a content-equal twin in local
    local rel f
    while IFS= read -r -d '' f; do
      rel="${f#$repo_path/}"
      [ -f "$local_path/$rel" ] || return 1
      diff -q "$local_path/$rel" <(subst_file_to_stdout "$f") >/dev/null 2>&1 || return 1
    done < <(find "$repo_path" -type f -print0)
    # And local must not have any extras
    while IFS= read -r -d '' f; do
      rel="${f#$local_path/}"
      [ -f "$repo_path/$rel" ] || return 1
    done < <(find "$local_path" -type f -print0)
    return 0
  elif [ -f "$local_path" ] && [ -f "$repo_path" ]; then
    diff -q "$local_path" <(subst_file_to_stdout "$repo_path") >/dev/null 2>&1
  else
    return 1
  fi
}

# Resolve a per-group content overlay for a skill, if one exists.
# Overlays live at: skill-groups/<group>/overlays/skills/<skill-name>(/SKILL.md|.md)
# and take precedence over the upstream source_repo files.
# Echoes overlay path on success, empty string if no overlay exists.
resolve_skill_overlay() {
  local group="$1" skill="$2"
  local overlay_dir="$SKILL_GROUPS_DIR/$group/overlays/skills"
  if [ -f "$overlay_dir/$skill/SKILL.md" ]; then
    echo "$overlay_dir/$skill"
  elif [ -f "$overlay_dir/$skill.md" ]; then
    echo "$overlay_dir/$skill.md"
  elif [ -f "$overlay_dir/$skill" ]; then
    echo "$overlay_dir/$skill"
  else
    echo ""
  fi
}

# Resolve a per-group content overlay for an agent file (by upstream filename).
# Overlay path: skill-groups/<group>/overlays/agents/<upstream-filename>.md
# `agent_renames` is applied later at symlink-destination time, so the overlay
# filename mirrors the ORIGINAL upstream filename.
resolve_agent_overlay() {
  local group="$1" upstream_filename="$2"
  local overlay_path="$SKILL_GROUPS_DIR/$group/overlays/agents/$upstream_filename"
  if [ -f "$overlay_path" ]; then
    echo "$overlay_path"
  else
    echo ""
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

# ─── Group type dispatch (authored / vendored / tool-only) ──────────────────

# Read the "type" field from a manifest; default to "authored" if absent.
group_type() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  [ -f "$manifest_file" ] || { echo "authored"; return; }
  local t
  t=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      process.stdout.write(m.type || 'authored');
    } catch(e) { process.stdout.write('authored'); }
  " "$manifest_file" 2>/dev/null) || t="authored"
  echo "$t"
}

# Reads a group's "update_policy" manifest field. "latest" means the group's
# install command tracks a moving target (e.g. one of my own tool repos cloned
# at HEAD) and --update should re-run it every time. Default is "pinned":
# update mode leaves installed software alone.
group_update_policy() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  [ -f "$manifest_file" ] || { echo "pinned"; return; }
  local p
  p=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      process.stdout.write(m.update_policy || 'pinned');
    } catch(e) { process.stdout.write('pinned'); }
  " "$manifest_file" 2>/dev/null) || p="pinned"
  echo "$p"
}

# Read a value from a vendored manifest's "source" block via node.
# Args: <group> <path-into-source> e.g. "repo", "ref", "ref_name", "paths.skills", "paths.agents"
vendored_source_get() {
  local group="$1" path="$2"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      const parts = process.argv[2].split('.');
      let v = m.source || {};
      for (const p of parts) { if (v == null) break; v = v[p]; }
      if (v == null) process.stdout.write('');
      else process.stdout.write(String(v));
    } catch(e) { process.stdout.write(''); }
  " "$manifest_file" "$path" 2>/dev/null || true
}

# Slug a "owner/repo" string into a filesystem-safe directory name.
repo_slug() {
  echo "$1" | tr '/' '-' | sed 's/\.git$//'
}

# Validate that source.ref looks like a full SHA or a tag (NOT a branch name).
# Branches like "main", "develop", "master", "HEAD" are rejected.
validate_vendor_ref() {
  local ref="$1"
  case "$ref" in
    main|master|develop|HEAD|trunk|dev) return 1 ;;
  esac
  # Anything else passes — full SHAs (40 hex chars) or tags (semantic versions, etc.)
  [ -n "$ref" ]
}

# Clone (or fetch) the upstream repo for a vendored group, then checkout the pinned ref.
# Echoes the clone directory path on success.
vendored_ensure_clone() {
  local group="$1"
  local repo ref slug clone_dir
  repo=$(vendored_source_get "$group" "repo")
  ref=$(vendored_source_get "$group" "ref")

  if [ -z "$repo" ] || [ -z "$ref" ]; then
    fail "$group: vendored manifest missing source.repo or source.ref"
    return 1
  fi

  if ! validate_vendor_ref "$ref"; then
    fail "$group: source.ref '$ref' looks like a branch name — use a full SHA or tag"
    return 1
  fi

  slug=$(repo_slug "$repo")
  clone_dir="$CLAUDE_DIR/.skill-repos/$slug"
  mkdir -p "$CLAUDE_DIR/.skill-repos"

  local repo_url="https://github.com/${repo}.git"

  if [ ! -d "$clone_dir/.git" ]; then
    info "Cloning $repo into $clone_dir..." >&2
    if ! git clone --quiet "$repo_url" "$clone_dir" 2>/dev/null; then
      fail "$group: failed to clone $repo_url" >&2
      return 1
    fi
  else
    (cd "$clone_dir" && git fetch --quiet origin 2>/dev/null) || warn "$group: fetch failed for $repo" >&2
  fi

  # Checkout the pinned ref (detached HEAD is expected/desired)
  if ! (cd "$clone_dir" && git checkout --quiet "$ref" 2>/dev/null); then
    fail "$group: failed to checkout pinned ref $ref in $clone_dir" >&2
    return 1
  fi

  echo "$clone_dir"
}

# Read vendored overlay metadata (agent renames + presence). Echoes the rename
# target for an agent overlay filename, e.g. "unity.md" for "rename:unity.md".
vendored_agent_rename() {
  local group="$1" upstream_filename="$2"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      const agents = (m.overlays && m.overlays.agents) || {};
      const v = agents[process.argv[2]];
      if (v && typeof v === 'string' && v.startsWith('rename:')) {
        process.stdout.write(v.slice('rename:'.length));
      }
    } catch(e) {}
  " "$manifest_file" "$upstream_filename" 2>/dev/null || true
}

# Generate a default CLAUDE.md snippet for a group when no
# shared/claude-md/<group>.md exists. Echoes the snippet to stdout.
# Builds trigger phrases from the group name, declared skills, and agents
# so Claude has multiple handles to recognize when to load the skill.
generate_default_snippet() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  local payload
  payload=$(node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      const desc = m.description || '';
      const skills = Array.isArray(m.skills) ? m.skills : [];
      const agents = Array.isArray(m.agents) ? m.agents : [];
      // Trigger phrases: group name + skill names + agent names, deduped
      const phrases = Array.from(new Set([m.name || '', ...skills, ...agents].filter(Boolean)));
      // Pointer: prefer the first skill if any, else mention the agent
      let pointer = '';
      if (skills.length) pointer = \`read \\\`~/.claude/skills/\${skills[0]}/SKILL.md\\\`\`;
      if (agents.length) pointer = pointer
        ? \`\${pointer} or invoke the \\\`\${agents[0]}\\\` agent\`
        : \`invoke the \\\`\${agents[0]}\\\` agent\`;
      console.log(JSON.stringify({ desc, phrases, pointer }));
    } catch(e) { console.log('{}'); }
  " "$manifest_file" 2>/dev/null) || payload='{}'

  local desc phrases pointer
  desc=$(echo "$payload" | node -e "let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{try{process.stdout.write(JSON.parse(s).desc||'')}catch(e){}})" 2>/dev/null)
  phrases=$(echo "$payload" | node -e "let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{try{const p=JSON.parse(s).phrases||[];process.stdout.write(p.map(x=>'\"'+x+'\"').join(', '))}catch(e){}})" 2>/dev/null)
  pointer=$(echo "$payload" | node -e "let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{try{process.stdout.write(JSON.parse(s).pointer||'')}catch(e){}})" 2>/dev/null)

  [ -z "$phrases" ] && phrases="\"$group\""
  local use_line="When this matches the user's request"
  [ -n "$pointer" ] && use_line="$use_line, $pointer"
  use_line="$use_line."

  cat <<EOF
## $group

$desc

$use_line

Trigger phrases: $phrases
EOF
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

  if [ "$NON_INTERACTIVE" = "true" ]; then
    info "Non-interactive mode: installing all groups"
    SELECTED_GROUPS=("${available[@]}")
    return
  fi

  header "Available skill groups:"
  echo ""
  for i in "${!available[@]}"; do
    local manifest
    manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/${available[$i]}/manifest.json")
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

  while IFS='|' read -r name check hint required note; do
    [ -z "$name" ] && continue
    if eval "$check" </dev/null >/dev/null 2>&1; then
      ok "Prerequisite: $name"
    else
      if [ "$required" = "true" ]; then
        fail "Missing required prerequisite: $name"
        [ -n "$note" ] && info "  ($note)"
        info "  $hint"
        # Suggest brew install on macOS for common tools
        if [ "$PLATFORM" = "macos" ] && command -v brew >/dev/null 2>&1; then
          case "$name" in
            go)    info "  Quick install: brew install go" ;;
            cargo) info "  Quick install: brew install rust" ;;
            uvx)   info "  Quick install: brew install uv" ;;
            node|npx) info "  Quick install: brew install node" ;;
          esac
        fi
        all_met=false
      else
        warn "Optional prerequisite missing: $name"
        [ -n "$note" ] && info "  ($note)"
        info "  $hint"
        if [ "$PLATFORM" = "macos" ] && command -v brew >/dev/null 2>&1; then
          case "$name" in
            go)    info "  Quick install: brew install go" ;;
            cargo) info "  Quick install: brew install rust" ;;
            uvx)   info "  Quick install: brew install uv" ;;
            node|npx) info "  Quick install: brew install node" ;;
            pip)   info "  Quick install: brew install python" ;;
          esac
        fi
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

  if ! command -v node >/dev/null 2>&1; then
    fail "node is required but not found — install from https://nodejs.org/"
    if [ "$PLATFORM" = "macos" ] && command -v brew >/dev/null 2>&1; then
      info "Quick install: brew install node"
    fi
    exit 1
  fi
  ok "node available"
}

# ─── Install shell aliases ──────────────────────────────────────────────────

install_shell_aliases() {
  # Adds a wrapper around `claude` that expands short flags:
  #   --dsp → --dangerously-skip-permissions
  #   --chr → --chrome
  #   --res → --continue
  # Idempotent: re-running replaces the managed block between BEGIN/END markers.
  local marker_begin="# >>> claude-skills aliases >>>"
  local marker_end="# <<< claude-skills aliases <<<"
  local block
  block=$(cat <<'EOF'
# >>> claude-skills aliases >>>
# Managed by claude-skills installer — do not edit between markers.
# Wrapper around `claude` that expands short flags (any position, combinable):
#   --dsp  → --dangerously-skip-permissions
#   --chr  → --chrome (Claude in Chrome)
#   --res  → --continue (resume most recent conversation in this directory)
claude() {
  local args=()
  for a in "$@"; do
    case "$a" in
      --dsp) args+=(--dangerously-skip-permissions) ;;
      --chr) args+=(--chrome) ;;
      --res) args+=(--continue) ;;
      *)     args+=("$a") ;;
    esac
  done
  command claude "${args[@]}"
}
# <<< claude-skills aliases <<<
EOF
)

  local targets=("$HOME/.bashrc")
  # macOS defaults to zsh; also target zsh anywhere a .zshrc exists.
  if [ "$PLATFORM" = "macos" ] || [ -f "$HOME/.zshrc" ]; then
    targets+=("$HOME/.zshrc")
  fi

  for rc in "${targets[@]}"; do
    [ -f "$rc" ] || touch "$rc"

    local existed_already=false
    if grep -qF "$marker_begin" "$rc"; then
      existed_already=true
      local tmp
      tmp=$(mktemp)
      awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin { skipping=1; next }
        skipping && $0 == end { skipping=0; next }
        !skipping { print }
      ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    fi

    # Ensure a trailing newline before appending the block.
    if [ -s "$rc" ] && [ "$(tail -c1 "$rc" 2>/dev/null | od -An -c | tr -d ' ')" != "\n" ]; then
      printf '\n' >> "$rc"
    fi
    printf '%s\n' "$block" >> "$rc"

    if [ "$existed_already" = "true" ]; then
      ok "Refreshed claude shell-alias wrapper in $rc"
    else
      ok "Installed claude shell-alias wrapper in $rc (restart shell to pick up)"
    fi
  done

  # PowerShell profile (Windows only)
  if [ "$PLATFORM" = "windows" ]; then
    install_powershell_aliases
  fi
}

install_powershell_aliases() {
  local ps_marker_begin="# >>> claude-skills aliases >>>"
  local ps_marker_end="# <<< claude-skills aliases <<<"
  local ps_block
  ps_block=$(cat <<'EOF'
# >>> claude-skills aliases >>>
# Managed by claude-skills installer — do not edit between markers.
# Wrapper around `claude` that expands short flags (any position, combinable):
#   --dsp  → --dangerously-skip-permissions
#   --chr  → --chrome (Claude in Chrome)
#   --res  → --continue (resume most recent conversation in this directory)
function claude {
    $exe = (Get-Command -CommandType Application -Name claude -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $exe) { Write-Error 'claude executable not found on PATH'; return }
    $mapped = foreach ($a in $args) {
        switch ($a) {
            '--dsp' { '--dangerously-skip-permissions' }
            '--chr' { '--chrome' }
            '--res' { '--continue' }
            default { $a }
        }
    }
    & $exe @mapped
}
# <<< claude-skills aliases <<<
EOF
)

  # Target both Windows PowerShell 5.1 and PowerShell 7+ profile paths.
  local ps_targets=(
    "$HOME/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
    "$HOME/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
  )

  for ps in "${ps_targets[@]}"; do
    mkdir -p "$(dirname "$ps")"
    [ -f "$ps" ] || touch "$ps"

    local existed_already=false
    if grep -qF "$ps_marker_begin" "$ps"; then
      existed_already=true
      local tmp
      tmp=$(mktemp)
      awk -v begin="$ps_marker_begin" -v end="$ps_marker_end" '
        $0 == begin { skipping=1; next }
        skipping && $0 == end { skipping=0; next }
        !skipping { print }
      ' "$ps" > "$tmp" && mv "$tmp" "$ps"
    fi

    if [ -s "$ps" ] && [ "$(tail -c1 "$ps" 2>/dev/null | od -An -c | tr -d ' ')" != "\n" ]; then
      printf '\n' >> "$ps"
    fi
    printf '%s\n' "$ps_block" >> "$ps"

    if [ "$existed_already" = "true" ]; then
      ok "Refreshed claude shell-alias wrapper in $ps"
    else
      ok "Installed claude shell-alias wrapper in $ps (restart shell to pick up)"
      info "If PowerShell execution policy blocks the profile, run once as user:"
      info "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    fi
  done
}

# ─── Per-group shell aliases ────────────────────────────────────────────────

# claude-code-sessions: install a `cs` shell function that runs the TUI and
# evals the resume command it prints to stdout. Idempotent — replaces the
# managed block between BEGIN/END markers.
install_sessions_aliases() {
  local marker_begin="# >>> claude-code-sessions cs() wrapper >>>"
  local marker_end="# <<< claude-code-sessions cs() wrapper <<<"

  # ─── bash / zsh ───
  local bash_block
  bash_block=$(cat <<'EOF'
# >>> claude-code-sessions cs() wrapper >>>
# Managed by claude-skills installer — do not edit between markers.
# Runs the session picker TUI; on selection, the binary prints a `claude …`
# command to stdout which this function evals to resume the session.
cs() {
  local exe="$HOME/.local/share/claude-code-sessions/claude-code-sessions.exe"
  [ -x "$exe" ] || exe="$HOME/.local/share/claude-code-sessions/claude-code-sessions"
  local cmd
  cmd=$("$exe") && [ -n "$cmd" ] && eval "$cmd"
}
# <<< claude-code-sessions cs() wrapper <<<
EOF
)

  local targets=("$HOME/.bashrc")
  if [ "$PLATFORM" = "macos" ] || [ -f "$HOME/.zshrc" ]; then
    targets+=("$HOME/.zshrc")
  fi

  for rc in "${targets[@]}"; do
    [ -f "$rc" ] || touch "$rc"
    local existed_already=false
    if grep -qF "$marker_begin" "$rc"; then
      existed_already=true
      local tmp
      tmp=$(mktemp)
      awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin { skipping=1; next }
        skipping && $0 == end { skipping=0; next }
        !skipping { print }
      ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    fi
    if [ -s "$rc" ] && [ "$(tail -c1 "$rc" 2>/dev/null | od -An -c | tr -d ' ')" != "\n" ]; then
      printf '\n' >> "$rc"
    fi
    printf '%s\n' "$bash_block" >> "$rc"
    if [ "$existed_already" = "true" ]; then
      ok "Refreshed cs() wrapper in $rc"
    else
      ok "Installed cs() wrapper in $rc (restart shell to pick up)"
    fi
  done

  # ─── PowerShell (Windows only) ───
  if [ "$PLATFORM" = "windows" ]; then
    local ps_block
    ps_block=$(cat <<'EOF'
# >>> claude-code-sessions cs() wrapper >>>
# Managed by claude-skills installer — do not edit between markers.
function cs {
    $exe = Join-Path $HOME '.local\share\claude-code-sessions\claude-code-sessions.exe'
    if (-not (Test-Path $exe)) {
        $alt = Join-Path $HOME '.local\share\claude-code-sessions\claude-code-sessions'
        if (Test-Path $alt) { $exe = $alt }
    }
    $cmd = & $exe
    if ($cmd) { Invoke-Expression $cmd }
}
# <<< claude-code-sessions cs() wrapper <<<
EOF
)
    local ps_targets=(
      "$HOME/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
      "$HOME/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
    )
    for ps in "${ps_targets[@]}"; do
      mkdir -p "$(dirname "$ps")"
      [ -f "$ps" ] || touch "$ps"
      local existed_already=false
      if grep -qF "$marker_begin" "$ps"; then
        existed_already=true
        local tmp
        tmp=$(mktemp)
        awk -v begin="$marker_begin" -v end="$marker_end" '
          $0 == begin { skipping=1; next }
          skipping && $0 == end { skipping=0; next }
          !skipping { print }
        ' "$ps" > "$tmp" && mv "$tmp" "$ps"
      fi
      if [ -s "$ps" ] && [ "$(tail -c1 "$ps" 2>/dev/null | od -An -c | tr -d ' ')" != "\n" ]; then
        printf '\n' >> "$ps"
      fi
      printf '%s\n' "$ps_block" >> "$ps"
      if [ "$existed_already" = "true" ]; then
        ok "Refreshed cs() wrapper in $ps"
      else
        ok "Installed cs() wrapper in $ps (restart shell to pick up)"
      fi
    done
  fi
}

# NOTE: the `lh` long-horizon launcher is NOT installed here. The
# context-rotation group owns it exclusively via its install/wire.sh (step 5),
# which is the group's real installer (the manifest install method runs wire.sh
# on every install). Keeping a second `lh` writer here caused duplicate,
# divergent lh() blocks in ~/.bashrc — so this hook was removed. See
# skill-groups/context-rotation/install/wire.sh for the canonical lh.

# gitbash-clipboard-cd: install the cdh clipboard-history helper plus the cdc/cdh
# bash functions that cd into folder paths copied from Windows Explorer (cdc =
# current clipboard, cdh = most recent directory in clipboard history). Windows
# Git Bash only — they rely on /dev/clipboard and WinRT. Idempotent — rewrites the
# helper and replaces the managed .bashrc block between BEGIN/END markers.
install_gitbash_clipboard_cd_aliases() {
  [ "$PLATFORM" = "windows" ] || return 0

  # cdh's clipboard-history reader. Inlined here (like the cs() PowerShell
  # wrapper above) rather than shipped as a repo payload. Rewritten every run.
  local helper_dir="$HOME/.local/share/gitbash-clipboard-cd"
  mkdir -p "$helper_dir"
  cat > "$helper_dir/cdh-cliphist.ps1" <<'PS1EOF'
$ErrorActionPreference = "Stop"
[Windows.ApplicationModel.DataTransfer.Clipboard,Windows.ApplicationModel.DataTransfer,ContentType=WindowsRuntime] | Out-Null
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1" } | Select-Object -First 1
function Await($op, $t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
$res = Await ([Windows.ApplicationModel.DataTransfer.Clipboard]::GetHistoryItemsAsync()) ([Windows.ApplicationModel.DataTransfer.ClipboardHistoryItemsResult])
foreach ($it in $res.Items) {
  try {
    $txt = Await ($it.Content.GetTextAsync()) ([string])
    if (-not $txt) { continue }
    $c = $txt.Trim().Trim('"')
    if ($c -match "[\r\n]") { continue }
    if (Test-Path -LiteralPath $c -PathType Container) { [Console]::Out.Write($c); exit 0 }
  } catch {}
}
exit 1
PS1EOF

  local marker_begin="# >>> gitbash-clipboard-cd (cdc/cdh) >>>"
  local marker_end="# <<< gitbash-clipboard-cd (cdc/cdh) <<<"
  local block
  block=$(cat <<'EOF'
# >>> gitbash-clipboard-cd (cdc/cdh) >>>
# Managed by claude-skills installer — do not edit between markers.
# cdc: cd into the folder path currently on the Windows clipboard.
# cdh: cd into the most recent existing directory in Windows clipboard history.
cdc() {
  local p
  p="$(cat /dev/clipboard)"
  p="${p//$'\r'/}"; p="${p//$'\n'/}"
  p="${p%\"}"; p="${p#\"}"
  cd "$(printf '%s' "$p" | tr '\134' '/')"
}
cdh() {
  local p
  p="$(powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.local/share/gitbash-clipboard-cd/cdh-cliphist.ps1" 2>/dev/null)"
  p="${p//$'\r'/}"; p="${p//$'\n'/}"
  if [ -z "$p" ]; then
    echo "cdh: no directory path found in clipboard history" >&2
    return 1
  fi
  cd "$(printf '%s' "$p" | tr '\134' '/')"
}
# <<< gitbash-clipboard-cd (cdc/cdh) <<<
EOF
)

  local rc="$HOME/.bashrc"
  [ -f "$rc" ] || touch "$rc"
  local existed_already=false
  if grep -qF "$marker_begin" "$rc"; then
    existed_already=true
    local tmp
    tmp=$(mktemp)
    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin { skipping=1; next }
      skipping && $0 == end { skipping=0; next }
      !skipping { print }
    ' "$rc" > "$tmp" && mv "$tmp" "$rc"
  fi
  if [ -s "$rc" ] && [ "$(tail -c1 "$rc" 2>/dev/null | od -An -c | tr -d ' ')" != "\n" ]; then
    printf '\n' >> "$rc"
  fi
  printf '%s\n' "$block" >> "$rc"
  if [ "$existed_already" = "true" ]; then
    ok "Refreshed cdc/cdh functions in $rc"
  else
    ok "Installed cdc/cdh functions in $rc (restart shell to pick up)"
  fi
}

# wsl-clipboard-cd: install the cdw bash function that cd's into a Windows folder
# path copied from Explorer, auto-converting it to WSL form (C:\a\b -> /mnt/c/a/b).
# WSL only — runs inside the Linux side and reads the Windows clipboard via
# powershell.exe interop. Idempotent — replaces the managed .bashrc/.zshrc block
# between BEGIN/END markers. No-op on native Linux (nothing to convert) and on
# macOS/Windows Git Bash.
install_wsl_clipboard_cd_aliases() {
  [ "$PLATFORM" = "linux" ] || return 0
  grep -qi microsoft /proc/version 2>/dev/null || return 0   # WSL only

  local marker_begin="# >>> wsl-clipboard-cd (cdw) >>>"
  local marker_end="# <<< wsl-clipboard-cd (cdw) <<<"
  local block
  block=$(cat <<'EOF'
# >>> wsl-clipboard-cd (cdw) >>>
# Managed by claude-skills installer — do not edit between markers.
# cdw: cd into the Windows folder path on the clipboard, converted to WSL form
# (C:\Users\me -> /mnt/c/Users/me). Strips "Copy as path" quotes and CRs.
cdw() {
  local p
  p="$(powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null)"
  [ -n "$p" ] || p="$(/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null)"
  p="${p//$'\r'/}"; p="${p//$'\n'/}"
  p="${p%\"}"; p="${p#\"}"
  # Backslashes -> forward slashes via tr (octal 134 = \). Avoids the ambiguous
  # ${p//\\//} form, which mis-parses in bash. Same idiom cdc/cdh use.
  p="$(printf '%s' "$p" | tr '\134' '/')"
  case "$p" in
    [A-Za-z]:/*)
      local drive="${p%%:*}" rest="${p#*:}"
      p="/mnt/${drive,,}${rest}"
      ;;
  esac
  if [ -z "$p" ]; then
    echo "cdw: clipboard is empty" >&2
    return 1
  fi
  if [ -d "$p" ]; then
    cd "$p"
  else
    echo "cdw: not a directory: $p" >&2
    return 1
  fi
}
# <<< wsl-clipboard-cd (cdw) <<<
EOF
)

  local targets=("$HOME/.bashrc")
  [ -f "$HOME/.zshrc" ] && targets+=("$HOME/.zshrc")

  for rc in "${targets[@]}"; do
    [ -f "$rc" ] || touch "$rc"
    local existed_already=false
    if grep -qF "$marker_begin" "$rc"; then
      existed_already=true
      local tmp
      tmp=$(mktemp)
      awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin { skipping=1; next }
        skipping && $0 == end { skipping=0; next }
        !skipping { print }
      ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    fi
    if [ -s "$rc" ] && [ "$(tail -c1 "$rc" 2>/dev/null | od -An -c | tr -d ' ')" != "\n" ]; then
      printf '\n' >> "$rc"
    fi
    printf '%s\n' "$block" >> "$rc"
    if [ "$existed_already" = "true" ]; then
      ok "Refreshed cdw function in $rc"
    else
      ok "Installed cdw function in $rc (restart shell to pick up)"
    fi
  done
}

# Dispatcher: per-group shell-alias hooks. Called from the per-group install loop.
install_group_shell_aliases() {
  case "$1" in
    claude-code-sessions) install_sessions_aliases ;;
    gitbash-clipboard-cd) install_gitbash_clipboard_cd_aliases ;;
    wsl-clipboard-cd)     install_wsl_clipboard_cd_aliases ;;
  esac
}

# ─── Install repo git hooks ─────────────────────────────────────────────────

# Copy scripts/post-merge-hook.sh into the canonical repo's .git/hooks/post-merge
# so future `git pull`s of claude-skills warn when vendored manifests change.
# Idempotent — overwrites if source is newer.
install_git_hooks() {
  local src="$SCRIPT_DIR/scripts/post-merge-hook.sh"
  local hooks_dir="$CANONICAL_DIR/.git/hooks"
  local dest="$hooks_dir/post-merge"

  [ -f "$src" ] || return 0
  [ -d "$hooks_dir" ] || return 0

  if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then
    cp "$src" "$dest"
    chmod +x "$dest"
    ok "Installed claude-skills git post-merge hook"
  fi
}

# ─── Install software dependency ────────────────────────────────────────────

install_software() {
  local group="$1" force="${2:-}"
  local manifest
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")

  local check_cmd
  check_cmd=$(json_get_install_check "$manifest")

  # "force" re-runs the install method even when the check passes — used by
  # update mode for groups with update_policy "latest", whose install commands
  # are idempotent pull-or-clone + rebuild.
  if [ "$force" != "force" ] && [ -n "$check_cmd" ] && [ "$check_cmd" != "true" ] && eval "$check_cmd" </dev/null >/dev/null 2>&1; then
    ok "$group software already installed"
    return 0
  fi

  header "Installing $group software..."

  # Use node for reliable JSON parsing of install methods
  local methods_list
  methods_list=$(node -e "
    const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const methods = (m.install && m.install.methods) || [];
    const SEP = '\x1f';  // ASCII Unit Separator — safe delimiter (never appears in commands)
    for (const method of methods) {
      const name = method.name || '';
      const cmd = method.command || '';
      const check = method.check || '';
      const url = method.url || '';
      const platforms = (method.platforms || []).join(',');
      console.log([name, cmd, check, url, platforms].join(SEP));
    }
  " "$SKILL_GROUPS_DIR/$group/manifest.json" 2>/dev/null) || true

  if [ -z "$methods_list" ]; then
    warn "No install methods defined for $group"
    return 0
  fi

  local IFS_SEP=$'\x1f'
  while IFS="$IFS_SEP" read -r method cmd prereq url platforms; do
    [ -z "$method" ] && continue

    # Skip methods not for this platform
    if [ -n "$platforms" ]; then
      if ! echo "$platforms" | grep -q "$PLATFORM"; then
        continue
      fi
    fi

    if [ -n "$prereq" ] && ! eval "$prereq" >/dev/null 2>&1; then
      info "Skipping $method install (prerequisite not met: $prereq)"
      continue
    fi

    if [ -n "$cmd" ]; then
      info "Installing via $method: $cmd"
      if eval "$cmd"; then
        # Add tool-specific bin dirs to PATH for subsequent commands
        case "$method" in
          go)    export PATH="$HOME/go/bin:$PATH" ;;
          cargo) export PATH="$HOME/.cargo/bin:$PATH" ;;
        esac
        ok "Installed $group via $method"
        return 0
      else
        warn "$method install failed, trying next method..."
      fi
    elif [ -n "$url" ]; then
      warn "$group requires manual installation"
      info "Download from: $url"
      if [ "$NON_INTERACTIVE" = "true" ]; then
        info "Non-interactive mode: skipping manual install"
        INSTALL_SKIPPED=true
        return 0
      fi
      read -rp "Press Enter after installing, or 's' to skip: " answer
      if [ "$answer" = "s" ]; then
        INSTALL_SKIPPED=true
      fi
      return 0
    fi
  done <<< "$methods_list"

  warn "Could not auto-install $group software — skills will be installed anyway"
  return 0
}

# ─── Install skills and agents ───────────────────────────────────────────────

install_skills() {
  local group="$1"
  local manifest
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")

  local gtype
  gtype=$(group_type "$group")

  # Tool-only groups install software only — no symlinks
  if [ "$gtype" = "tool-only" ]; then
    info "$group: tool-only group — no skills to symlink"
    return 0
  fi

  mkdir -p "$SKILLS_DIR" "$AGENTS_DIR" "$COMMANDS_DIR"

  local skills_source_dir agents_source_dir commands_source_dir

  # Commands always live in the local skill-group dir (no vendored equivalent).
  commands_source_dir="$SKILL_GROUPS_DIR/$group/commands"

  if [ "$gtype" = "vendored" ]; then
    local clone_dir
    clone_dir=$(vendored_ensure_clone "$group") || return 1
    local skills_path agents_path
    skills_path=$(vendored_source_get "$group" "paths.skills")
    agents_path=$(vendored_source_get "$group" "paths.agents")
    skills_source_dir="$clone_dir/$skills_path"
    [ -n "$agents_path" ] && agents_source_dir="$clone_dir/$agents_path"
  else
    # Backwards-compat: legacy authored manifest with source_repo (pre-vendored schema)
    local source_repo
    source_repo=$(json_get "$manifest" "source_repo")
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
  fi

  local skills
  skills=$(json_array "$manifest" "skills")
  for skill in $skills; do
    local src="$skills_source_dir/$skill"
    local dest="$SKILLS_DIR/$skill"

    # Per-group content overlay takes precedence over source_repo
    local overlay
    overlay=$(resolve_skill_overlay "$group" "$skill")
    if [ -n "$overlay" ]; then
      if [ -d "$overlay" ]; then
        create_symlink "$overlay" "$dest"
        ok "Skill: $skill (v$(skill_get_version "$overlay")) [overlay]"
      else
        # File overlay (single-file skill)
        local odest="$dest"
        [[ "$overlay" == *.md ]] && odest="$dest.md"
        create_symlink "$overlay" "$odest"
        ok "Skill: $skill (v$(skill_get_version "$overlay")) [overlay]"
      fi
      continue
    fi

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

  # For vendored groups, build a reverse rename map from overlays.agents
  # ("upstream-filename.md" -> "rename:new-name.md"). For authored/legacy
  # groups, fall back to the old "agent_renames" map.
  local renames
  renames=$(echo "$manifest" | grep -A10 '"agent_renames"' 2>/dev/null || true)

  for agent in $agents; do
    local src_file="$agent.md"

    if [ "$gtype" = "vendored" ]; then
      # Look for an upstream filename whose overlays.agents value is "rename:<agent>.md"
      local mapped
      mapped=$(node -e "
        try {
          const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
          const agents = (m.overlays && m.overlays.agents) || {};
          for (const [up, v] of Object.entries(agents)) {
            if (typeof v === 'string' && v === 'rename:' + process.argv[2] + '.md') {
              process.stdout.write(up); break;
            }
          }
        } catch(e) {}
      " "$SKILL_GROUPS_DIR/$group/manifest.json" "$agent" 2>/dev/null) || true
      [ -n "$mapped" ] && src_file="$mapped"
    else
      local rename_from
      rename_from=$(echo "$renames" | sed -n "s/.*\"\([^\"]*\)\"[[:space:]]*:[[:space:]]*\"$agent.md\".*/\1/p")
      [ -n "$rename_from" ] && src_file="$rename_from"
    fi

    local src="$agents_source_dir/$src_file"
    local dest="$AGENTS_DIR/$agent.md"

    # Per-group agent overlay (keyed by upstream filename, before rename)
    local agent_overlay
    agent_overlay=$(resolve_agent_overlay "$group" "$src_file")
    if [ -n "$agent_overlay" ]; then
      create_symlink "$agent_overlay" "$dest"
      ok "Agent: $agent [overlay]"
      continue
    fi

    if [ -f "$src" ]; then
      create_symlink "$src" "$dest"
      ok "Agent: $agent"
    else
      warn "Agent not found: $agent (looked in $src)"
    fi
  done

  # Slash commands: symlink skill-groups/<g>/commands/*.md → ~/.claude/commands/
  local commands
  commands=$(json_array "$manifest" "commands")
  for cmd in $commands; do
    local src="$commands_source_dir/$cmd.md"
    local dest="$COMMANDS_DIR/$cmd.md"
    if [ -f "$src" ]; then
      create_symlink "$src" "$dest"
      ok "Command: /$cmd"
    else
      warn "Command not found: /$cmd (looked in $src)"
    fi
  done
}

# ─── Orphan sweep: prune managed symlinks no longer listed in any manifest ──

# Removes symlinks in $target_dir that point into our managed area
# ($CLAUDE_DIR/.skill-repos/) but no longer correspond to any entry in any
# manifest's $manifest_key array. If $shared_subdir is provided, names found
# in $SHARED_DIR/$shared_subdir/ are also kept (shared skills aren't in any
# manifest's array but ship with the repo).
#
# Safety: only touches symlinks pointing inside $CLAUDE_DIR/.skill-repos/.
# Regular files (hand-authored) and symlinks pointing elsewhere are left alone.
#
# Args: <target_dir> <manifest_key> <label> [shared_subdir]
sweep_orphans_in() {
  local target_dir="$1"
  local manifest_key="$2"
  local label="$3"
  local shared_subdir="${4:-}"

  [ -d "$target_dir" ] || return 0

  local shared_path=""
  [ -n "$shared_subdir" ] && shared_path="$SHARED_DIR/$shared_subdir"

  # Build the keep-set via node. If the node call fails for any reason
  # (node missing, manifest unreadable, future regression), we must NOT
  # fall through with an empty keep_set — that would make every managed
  # symlink in $target_dir look like an orphan and delete them all. Track
  # node's exit status separately and abort the sweep on failure.
  local keep_set node_ok=true
  keep_set=$(node -e "
    const fs = require('fs');
    const path = require('path');
    const dir = process.argv[1];
    const key = process.argv[2];
    const sharedDir = process.argv[3] || '';
    const keep = new Set();
    for (const g of fs.readdirSync(dir)) {
      const m = path.join(dir, g, 'manifest.json');
      if (!fs.existsSync(m)) continue;
      try {
        const j = JSON.parse(fs.readFileSync(m, 'utf8'));
        for (const c of (j[key] || [])) keep.add(String(c).replace(/\.md$/, ''));
      } catch(e) {}
    }
    if (sharedDir && fs.existsSync(sharedDir)) {
      for (const e of fs.readdirSync(sharedDir)) {
        keep.add(e.replace(/\.md$/, ''));
      }
    }
    process.stdout.write([...keep].join('\n'));
  " "$SKILL_GROUPS_DIR" "$manifest_key" "$shared_path" 2>/dev/null) || node_ok=false

  if [ "$node_ok" != "true" ]; then
    warn "Orphan sweep skipped for $target_dir: failed to compute keep set"
    return 0
  fi

  local removed=0
  while IFS= read -r -d '' entry; do
    [ -L "$entry" ] || continue
    local target
    target=$(readlink "$entry")
    case "$target" in
      "$CLAUDE_DIR/.skill-repos/"*) ;;
      *) continue ;;
    esac
    local base
    base=$(basename "$entry")
    base="${base%.md}"
    if ! grep -qFx "$base" <<< "$keep_set"; then
      rm -f "$entry"
      info "Removed orphan $label: $base (no longer in any manifest)"
      removed=$((removed + 1))
    fi
  done < <(find "$target_dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

  if [ "$removed" -gt 0 ]; then
    ok "Pruned $removed orphan $label symlink(s)"
  fi
}

# Sweep all three managed dirs. Run at the end of install/update modes.
sweep_orphans() {
  sweep_orphans_in "$COMMANDS_DIR" "commands" "command" ""
  sweep_orphans_in "$AGENTS_DIR"   "agents"   "agent"   ""
  sweep_orphans_in "$SKILLS_DIR"   "skills"   "skill"   "skills"
}

# ─── Configure template variables ───────────────────────────────────────────

configure_skills() {
  local group="$1"

  local manifest skills
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")
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

  # No config file — prompt if interactive, warn if not
  if [ ! -f "$CONFIG_FILE" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      warn "Some $group skills have {{PLACEHOLDER}} variables — skills will NOT work until configured"
      info "To fix: cp $SCRIPT_DIR/config.example.sh $CONFIG_FILE"
      info "Then edit $CONFIG_FILE with your machine-specific paths and re-run the installer"
      return 0
    fi

    # Try to prompt using config_vars from the manifest
    local config_vars_json
    config_vars_json=$(node -e "
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      const cv = m.config_vars || {};
      for (const [k, v] of Object.entries(cv)) {
        console.log(k + '|' + (v.prompt || 'Value for ' + k));
      }
    " "$SKILL_GROUPS_DIR/$group/manifest.json" 2>/dev/null) || true

    if [ -n "$config_vars_json" ]; then
      info "Some $group skills need paths configured."
      info "Enter values below (or press Enter to skip and configure later)"
      echo ""

      # Create config file
      cp "$SCRIPT_DIR/config.example.sh" "$CONFIG_FILE" 2>/dev/null || echo "# claude-skills configuration" > "$CONFIG_FILE"

      local any_set=false
      while IFS='|' read -r vname vprompt; do
        [ -z "$vname" ] && continue
        read -rp "  $vprompt: " value
        if [ -n "$value" ]; then
          if grep -q "^${vname}=" "$CONFIG_FILE" 2>/dev/null; then
            sed -i'' -e "s|^${vname}=.*|${vname}=\"${value}\"|" "$CONFIG_FILE"
          else
            echo "${vname}=\"${value}\"" >> "$CONFIG_FILE"
          fi
          any_set=true
        fi
      done <<< "$config_vars_json"

      if [ "$any_set" = "true" ]; then
        ok "Config saved to $CONFIG_FILE — re-running configuration"
        # Fall through to apply the config
      else
        warn "Some $group skills have {{PLACEHOLDER}} variables — configure later in $CONFIG_FILE"
        return 0
      fi
    else
      warn "Some $group skills have {{PLACEHOLDER}} variables — skills will NOT work until configured"
      info "To fix: cp $SCRIPT_DIR/config.example.sh $CONFIG_FILE"
      info "Then edit $CONFIG_FILE with your machine-specific paths and re-run the installer"
      return 0
    fi
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
        # Escape sed metacharacters in the value before splicing into the
        # replacement side. Without this, Windows paths with backslashes
        # (`C:\Users\...`) or values containing `|`/`&` corrupt the output.
        local val_esc
        val_esc=$(sed_escape_repl "$val")
        sed -i'' -e "s|{{${var}}}|${val_esc}|g" "$f"
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
    warn "Some $group placeholders still unconfigured — these skills will NOT work until configured"
    info "Update $CONFIG_FILE with the missing values and re-run the installer"
  fi
}

# ─── Install MCP server configs ─────────────────────────────────────────────

install_mcp_config() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"

  # Quick check — skip if no mcp_servers in manifest
  if ! grep -q '"mcp_servers"' "$manifest_file" 2>/dev/null; then
    return 0
  fi

  local mcporter_config="$HOME/.mcporter/mcporter.json"
  local claude_mcp_config="$CLAUDE_DIR/.mcp.json"
  mkdir -p "$HOME/.mcporter"

  # Bash sources skills-config.sh (correct semantics — handles quotes,
  # spaces, $HOME expansion, empty strings) and passes the placeholder
  # map to node as a JSON env var. The previous approach re-parsed the
  # file in node with a regex that silently dropped any value containing
  # quotes, spaces, or empty strings.
  local placeholders_json
  placeholders_json=$(config_placeholders_json)

  # Single node script: read manifest, resolve paths, substitute placeholders, merge configs
  local output
  output=$(CLAUDE_SKILLS_PLACEHOLDERS="$placeholders_json" node -e "
    const fs = require('fs');
    const { execSync } = require('child_process');

    const manifest = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    const servers = manifest.mcp_servers;
    if (!servers) process.exit(0);

    const isWindows = !!process.env.MSYSTEM || process.platform === 'win32';

    // Placeholder map built by bash (see config_placeholders_json).
    let vars = {};
    try { vars = JSON.parse(process.env.CLAUDE_SKILLS_PLACEHOLDERS || '{}'); } catch(e) {}

    function subst(s) {
      return s.replace(/\{\{([A-Z_]+)\}\}/g, (_, k) => vars[k] || '{{' + k + '}}');
    }

    function resolveCmd(cmd) {
      if (cmd.includes('{{') || cmd.startsWith('/') || /^[A-Za-z]:/.test(cmd)) return cmd;
      // Try command -v first (uses current PATH)
      try {
        const r = execSync('command -v ' + cmd, { encoding: 'utf8', stdio: ['pipe','pipe','pipe'] }).trim();
        if (r) {
          if (isWindows) {
            try { return execSync('cygpath -w \"' + r + '\"', { encoding: 'utf8', stdio: ['pipe','pipe','pipe'] }).trim(); }
            catch(e) { return r; }
          }
          return r;
        }
      } catch(e) {}
      // On Windows, check common install locations for tools not yet on PATH
      if (isWindows) {
        const home = process.env.HOME || process.env.USERPROFILE || '';
        const candidates = [
          home + '/.local/bin/' + cmd,
          home + '/.local/bin/' + cmd + '.exe',
          home + '/.cargo/bin/' + cmd + '.exe',
          '/c/Program Files/GitHub CLI/' + cmd + '.exe',
        ];
        for (const p of candidates) {
          try {
            fs.accessSync(p, fs.constants.X_OK);
            try { return execSync('cygpath -w \"' + p + '\"', { encoding: 'utf8', stdio: ['pipe','pipe','pipe'] }).trim(); }
            catch(e) { return p; }
          } catch(e) {}
        }
      }
      return cmd;
    }

    function mergeInto(cfgPath, entries) {
      let cfg = {};
      try { cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); } catch(e) {}
      if (!cfg.mcpServers) cfg.mcpServers = {};
      let changed = false;
      for (const [name, entry] of Object.entries(entries)) {
        // Update if missing or if content differs (e.g. placeholder was resolved)
        const existing = JSON.stringify(cfg.mcpServers[name] || null);
        const incoming = JSON.stringify(entry);
        if (existing !== incoming) { cfg.mcpServers[name] = entry; changed = true; }
      }
      if (changed) fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + '\n');
    }

    // Collect names of missing config vars for the MISSING_VARS output
    const missingVars = new Set();

    const ready = {};
    for (const [name, config] of Object.entries(servers)) {
      const e = JSON.parse(JSON.stringify(config));
      e.command = subst(e.command);
      if (e.args) e.args = e.args.map(subst);
      const serialized = JSON.stringify(e);
      if (serialized.includes('{{')) {
        // Extract which vars are missing
        const matches = serialized.match(/\{\{([A-Z_]+)\}\}/g) || [];
        matches.forEach(m => missingVars.add(m.replace(/[{}]/g, '')));
        console.log('PLACEHOLDER:' + name);
        continue;
      }
      e.command = resolveCmd(e.command);
      ready[name] = e;
      console.log('OK:' + name);
    }

    if (missingVars.size > 0) {
      // Output config_vars info so the caller can prompt for them
      const configVars = manifest.config_vars || {};
      for (const varName of missingVars) {
        const info = configVars[varName];
        if (info) {
          console.log('MISSING_VAR:' + varName + ':' + (info.prompt || 'Value for ' + varName));
        } else {
          console.log('MISSING_VAR:' + varName + ':Value for ' + varName);
        }
      }
    }

    if (Object.keys(ready).length > 0) {
      mergeInto(process.argv[2], ready);
      mergeInto(process.argv[3], ready);
    }
  " "$manifest_file" "$mcporter_config" "$claude_mcp_config" 2>/dev/null) || true

  local has_missing_vars=false
  local missing_var_names=()
  local missing_var_prompts=()

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      OK:*)
        ok "MCP config: ${line#OK:} (added to mcporter + claude configs)"
        ;;
      PLACEHOLDER:*)
        warn "MCP config: ${line#PLACEHOLDER:} has unconfigured placeholders"
        ;;
      MISSING_VAR:*)
        has_missing_vars=true
        local var_info="${line#MISSING_VAR:}"
        local var_name="${var_info%%:*}"
        local var_prompt="${var_info#*:}"
        missing_var_names+=("$var_name")
        missing_var_prompts+=("$var_prompt")
        ;;
    esac
  done <<< "$output"

  # If there are missing vars, prompt the user (interactive) or show instructions (non-interactive)
  if [ "$has_missing_vars" = "true" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      warn "Missing config vars for $group MCP server — set these in $CONFIG_FILE:"
      for i in "${!missing_var_names[@]}"; do
        info "  ${missing_var_names[$i]}: ${missing_var_prompts[$i]}"
      done
    else
      info "The $group MCP server needs some paths configured."
      info "Enter values below (or press Enter to skip and configure later in $CONFIG_FILE)"
      echo ""

      local any_set=false
      # Ensure config file exists
      if [ ! -f "$CONFIG_FILE" ]; then
        cp "$SCRIPT_DIR/config.example.sh" "$CONFIG_FILE" 2>/dev/null || echo "# claude-skills configuration" > "$CONFIG_FILE"
      fi

      for i in "${!missing_var_names[@]}"; do
        local vname="${missing_var_names[$i]}"
        local vprompt="${missing_var_prompts[$i]}"
        read -rp "  $vprompt: " value
        if [ -n "$value" ]; then
          # Write/update the var in the config file
          if grep -q "^${vname}=" "$CONFIG_FILE" 2>/dev/null; then
            sed -i'' -e "s|^${vname}=.*|${vname}=\"${value}\"|" "$CONFIG_FILE"
          else
            echo "${vname}=\"${value}\"" >> "$CONFIG_FILE"
          fi
          any_set=true
        fi
      done

      # Re-run MCP config if any values were set
      if [ "$any_set" = "true" ]; then
        ok "Config saved to $CONFIG_FILE"
        info "Re-running MCP config for $group..."
        install_mcp_config "$group"
        return
      fi
    fi
  fi
}

# ─── Append CLAUDE.md snippet ───────────────────────────────────────────────

install_claude_md_snippet() {
  local group="$1"
  local snippet_file="$SHARED_DIR/claude-md/$group.md"
  local gtype
  gtype=$(group_type "$group")

  # Curated snippet wins; otherwise generate a default from the manifest so
  # Claude has trigger phrases for every group that ships skills/agents.
  # tool-only groups have no skills to load, so they're left alone.
  local snippet_content=""
  if [ -f "$snippet_file" ]; then
    snippet_content=$(cat "$snippet_file")
  elif [ "$gtype" = "tool-only" ]; then
    return 0
  else
    snippet_content=$(generate_default_snippet "$group")
  fi

  if [ ! -f "$CLAUDE_MD" ]; then
    echo "# Global Rules" > "$CLAUDE_MD"
    echo "" >> "$CLAUDE_MD"
  fi

  local marker
  marker=$(echo "$snippet_content" | grep -m1 '^## ' || echo "$snippet_content" | head -1)
  if grep -qF "$marker" "$CLAUDE_MD" 2>/dev/null; then
    ok "CLAUDE.md: $group snippet already present"
    return 0
  fi

  echo "" >> "$CLAUDE_MD"
  echo "---" >> "$CLAUDE_MD"
  echo "" >> "$CLAUDE_MD"
  echo "$snippet_content" >> "$CLAUDE_MD"
  ok "CLAUDE.md: appended $group trigger phrases"
}

# ─── Install shared skills ──────────────────────────────────────────────────

install_shared_skills() {
  local shared_skills_dir="$SHARED_DIR/skills"
  [ -d "$shared_skills_dir" ] || return 0

  mkdir -p "$SKILLS_DIR"
  # Install shared .md files
  for skill_file in "$shared_skills_dir"/*.md; do
    [ -f "$skill_file" ] || continue
    local name
    name=$(basename "$skill_file")
    create_symlink "$skill_file" "$SKILLS_DIR/$name"
    ok "Shared skill: $name (v$(skill_get_version "$skill_file"))"
  done
  # Install shared directory skills (contain SKILL.md + references)
  for skill_dir in "$shared_skills_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    local name
    name=$(basename "$skill_dir")
    local version_file="$skill_dir/SKILL.md"
    create_symlink "$skill_dir" "$SKILLS_DIR/$name"
    if [ -f "$version_file" ]; then
      ok "Shared skill: $name (v$(skill_get_version "$version_file"))"
    else
      ok "Shared skill: $name"
    fi
  done

  # Append shared claude-md snippets
  for snippet in mcporter skill-repo-maintenance; do
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
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")

  local test_cmd
  test_cmd=$(echo "$manifest" | grep -A2 '"test"' | grep '"command"' | sed 's/.*: *"//;s/".*//')

  [ -z "$test_cmd" ] && return 0

  info "Smoke test: $test_cmd"
  if eval "$test_cmd" </dev/null >/dev/null 2>&1; then
    ok "$group smoke test passed"
  else
    warn "$group smoke test failed — software may need manual configuration"
  fi
}

# ─── Show post-install hints ────────────────────────────────────────────────

show_post_install_hints() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"

  # Use node to extract hints array (clean JSON parsing)
  local hints
  hints=$(node -e "
    const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    if (m.post_install_hints) m.post_install_hints.forEach(h => console.log(h));
  " "$manifest_file" 2>/dev/null) || true

  if [ -n "$hints" ]; then
    echo ""
    while IFS= read -r line; do
      info "$line"
    done <<< "$hints"
    echo ""
  fi
}

# ─── Verify installation (--verify) ─────────────────────────────────────────

verify_group() {
  local group="$1"
  local manifest
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")
  local gtype
  gtype=$(group_type "$group")

  header "Verifying: $group ($gtype)"

  # Vendored: confirm pinned SHA is checked out + overlay paths still valid
  if [ "$gtype" = "vendored" ]; then
    info "Vendored source:"
    local repo ref slug clone_dir
    repo=$(vendored_source_get "$group" "repo")
    ref=$(vendored_source_get "$group" "ref")
    slug=$(repo_slug "$repo")
    clone_dir="$CLAUDE_DIR/.skill-repos/$slug"
    if [ ! -d "$clone_dir/.git" ]; then
      fail "Source clone missing: $clone_dir (run install.sh --skills $group)"
    else
      local head
      head=$(cd "$clone_dir" && git rev-parse HEAD 2>/dev/null)
      if [ "$head" = "$ref" ] || [ "${head#$ref}" != "$head" ] || [ "${ref#$head}" != "$ref" ]; then
        ok "Pinned ref $ref is checked out"
      else
        # Try resolving ref (tag) to a SHA for comparison
        local resolved
        resolved=$(cd "$clone_dir" && git rev-parse "$ref" 2>/dev/null) || resolved=""
        if [ -n "$resolved" ] && [ "$resolved" = "$head" ]; then
          ok "Pinned ref $ref ($resolved) is checked out"
        else
          fail "Pinned ref $ref not checked out (HEAD=$head)"
        fi
      fi
    fi

    # Check overlay paths still exist in upstream
    local overlay_dir="$SKILL_GROUPS_DIR/$group/overlays/skills"
    if [ -d "$overlay_dir" ]; then
      local skills_path
      skills_path=$(vendored_source_get "$group" "paths.skills")
      while IFS= read -r ovsk; do
        [ -z "$ovsk" ] && continue
        local upstream_skill="$clone_dir/$skills_path/$ovsk"
        if [ -d "$upstream_skill" ] || [ -f "$upstream_skill" ] || [ -f "${upstream_skill}.md" ]; then
          ok "Overlay $ovsk maps to upstream"
        else
          fail "Overlay $ovsk has no matching upstream path ($upstream_skill)"
        fi
      done < <(ls -1 "$overlay_dir" 2>/dev/null)
    fi
  fi

  # Tool-only: only software check + test
  if [ "$gtype" = "tool-only" ]; then
    info "Software:"
    local check_cmd
    check_cmd=$(json_get_install_check "$manifest")
    if [ -n "$check_cmd" ] && [ "$check_cmd" != "true" ]; then
      if eval "$check_cmd" </dev/null >/dev/null 2>&1; then
        ok "Software check passed ($check_cmd)"
      else
        fail "Software check failed ($check_cmd)"
      fi
    fi
    return 0
  fi

  # 1. Check prerequisites
  info "Prerequisites:"
  check_prerequisites "$group" || true

  # 2. Check software installed (using install-specific check command).
  # Substitute {{PLACEHOLDER}} vars from skills-config.sh so paths like
  # {{HOUDINI_MCP_DIR}}/server.py resolve to the actual configured path
  # before we run the check.
  info "Software:"
  local check_cmd raw_check_cmd
  raw_check_cmd=$(json_get_install_check "$manifest")
  check_cmd=$(subst_placeholders "$raw_check_cmd")
  if [ -n "$check_cmd" ] && [ "$check_cmd" != "true" ]; then
    if eval "$check_cmd" </dev/null >/dev/null 2>&1; then
      ok "Software binary found ($check_cmd)"
    elif group_has_mcp_servers "$group"; then
      # MCP-style groups (blender, houdini, ...) keep their MCP server
      # config intact even when the underlying app isn't on PATH. The MCP
      # will fail at runtime if used, but this isn't a broken install — so
      # warn instead of failing the verify summary.
      warn "App binary not on PATH ($check_cmd) — MCP server is configured but will fail at runtime until resolved"
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

  # 4b. Check slash commands are linked
  info "Commands:"
  local commands
  commands=$(json_array "$manifest" "commands")
  if [ -z "$commands" ]; then
    info "  (no commands defined)"
  fi
  for cmd in $commands; do
    local target="$COMMANDS_DIR/$cmd.md"
    if [ -f "$target" ] && [ -s "$target" ]; then
      ok "Command: /$cmd (present, non-empty)"
    elif [ -f "$target" ]; then
      fail "Command: /$cmd (exists but is empty)"
    else
      fail "Command: /$cmd (not found at $target)"
    fi
    if [ -L "$target" ] && [ ! -e "$target" ]; then
      fail "Command: /$cmd (broken symlink → $(readlink "$target"))"
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

  # 6. Check for unconfigured {{PLACEHOLDER}} vars.
  # Match only the install-time substitution shape ({{UPPER_SNAKE}}) so
  # skill files that document lowercase tokens like {{customer_name}} —
  # e.g. officecli explaining what NOT to render — don't trip the check.
  info "Configuration:"
  local has_placeholders=false
  local ph_pattern='\{\{[A-Z_]+\}\}'
  for skill in $skills; do
    local target="$SKILLS_DIR/$skill"
    if [ -f "$target" ] && grep -Eq "$ph_pattern" "$target" 2>/dev/null; then
      has_placeholders=true
    fi
    if [ -f "$target.md" ] && grep -Eq "$ph_pattern" "$target.md" 2>/dev/null; then
      has_placeholders=true
    fi
    if [ -d "$target" ]; then
      if grep -rEq "$ph_pattern" "$target" 2>/dev/null; then
        has_placeholders=true
      fi
    fi
  done
  if [ "$has_placeholders" = "true" ]; then
    warn "Unconfigured {{PLACEHOLDER}} variables found — edit skill files or create $CONFIG_FILE"
  else
    ok "No unconfigured placeholders"
  fi

  # 7. Check MCP server configs
  if grep -q '"mcp_servers"' "$SKILL_GROUPS_DIR/$group/manifest.json" 2>/dev/null; then
    info "MCP configs:"
    local mcporter_config="$HOME/.mcporter/mcporter.json"
    local claude_mcp_config="$CLAUDE_DIR/.mcp.json"
    # Extract server names from manifest
    local server_names
    server_names=$(node -e "
      const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      if (m.mcp_servers) Object.keys(m.mcp_servers).forEach(n => console.log(n));
    " "$SKILL_GROUPS_DIR/$group/manifest.json" 2>/dev/null) || true
    for sname in $server_names; do
      local in_mcporter=false in_claude=false
      grep -q "\"$sname\"" "$mcporter_config" 2>/dev/null && in_mcporter=true
      grep -q "\"$sname\"" "$claude_mcp_config" 2>/dev/null && in_claude=true
      if [ "$in_mcporter" = "true" ] && [ "$in_claude" = "true" ]; then
        ok "MCP server '$sname' configured in mcporter + claude"
      elif [ "$in_mcporter" = "true" ]; then
        warn "MCP server '$sname' in mcporter but missing from $claude_mcp_config"
      elif [ "$in_claude" = "true" ]; then
        warn "MCP server '$sname' in claude but missing from $mcporter_config"
      else
        fail "MCP server '$sname' not configured — re-run installer"
      fi
    done
  fi
}

# ─── Integration test (--test-integration) ──────────────────────────────────

integration_test_group() {
  local group="$1"
  local manifest
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")

  header "Integration test: $group"

  local int_cmd int_desc
  int_cmd=$(echo "$manifest" | grep -A3 '"integration_test"' | grep '"command"' | sed 's/.*: *"//;s/".*//')
  int_desc=$(echo "$manifest" | grep -A3 '"integration_test"' | grep '"description"' | sed 's/.*: *"//;s/".*//')
  int_cmd=$(subst_placeholders "$int_cmd")

  if [ -z "$int_cmd" ]; then
    info "No integration test defined for $group"
    return 0
  fi

  info "Requires: $int_desc"
  info "Running: $int_cmd"

  if eval "$int_cmd" </dev/null >/dev/null 2>&1; then
    ok "$group integration test passed — software is live and responding"
  else
    fail "$group integration test failed"
    info "  Make sure: $int_desc"
  fi
}

# ─── Update mode (--update) ─────────────────────────────────────────────────

# Returns 0 if the group already has a local footprint: any declared skill or
# agent symlinked, or — for tool-only groups — its install check passes. Update
# mode uses this to refresh only installed groups and to spot genuinely-new ones.
group_is_installed() {
  local group="$1" manifest gtype
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")
  gtype=$(group_type "$group")

  if [ "$gtype" = "tool-only" ]; then
    local chk
    chk=$(json_get_install_check "$manifest")
    [ -n "$chk" ] && eval "$chk" </dev/null >/dev/null 2>&1
    return
  fi

  local skill agent cmd
  for skill in $(json_array "$manifest" "skills"); do
    [ -n "$(resolve_skill_path "$SKILLS_DIR/$skill")" ] && return 0
  done
  for agent in $(json_array "$manifest" "agents"); do
    [ -e "$AGENTS_DIR/$agent.md" ] && return 0
  done
  # Some groups ship only slash commands (e.g. claude-conversation-transfer)
  for cmd in $(json_array "$manifest" "commands"); do
    [ -e "$COMMANDS_DIR/$cmd.md" ] && return 0
  done
  return 1
}

update_group() {
  local group="$1"
  local manifest
  manifest=$(tr -d '\r' < "$SKILL_GROUPS_DIR/$group/manifest.json")
  local gtype
  gtype=$(group_type "$group")

  header "Updating: $group"

  # Groups with update_policy "latest" track a moving target (my own tool
  # repos cloned at HEAD) — re-run their idempotent install command so the
  # binary is rebuilt from the latest upstream on every --update.
  if [ "$(group_update_policy "$group")" = "latest" ]; then
    if [ "$SKIP_SOFTWARE" = "false" ]; then
      info "$group: update_policy latest — refreshing software"
      install_software "$group" force
      run_test "$group"
    else
      info "$group: update_policy latest, but --skip-software given — not refreshing"
    fi
  fi

  # Tool-only groups have nothing to symlink/update at the skill level
  if [ "$gtype" = "tool-only" ]; then
    [ "$(group_update_policy "$group")" = "latest" ] || info "$group: tool-only — nothing to update"
    return 0
  fi

  local skills_source_dir agents_source_dir

  if [ "$gtype" = "vendored" ]; then
    local clone_dir
    clone_dir=$(vendored_ensure_clone "$group") || return 1
    local skills_path agents_path
    skills_path=$(vendored_source_get "$group" "paths.skills")
    agents_path=$(vendored_source_get "$group" "paths.agents")
    skills_source_dir="$clone_dir/$skills_path"
    [ -n "$agents_path" ] && agents_source_dir="$clone_dir/$agents_path"
  else
    local source_repo
    source_repo=$(json_get "$manifest" "source_repo")
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
  fi

  local skills
  skills=$(json_array "$manifest" "skills")

  for skill in $skills; do
    local repo_path local_path
    # Per-group content overlay takes precedence
    local overlay
    overlay=$(resolve_skill_overlay "$group" "$skill")
    if [ -n "$overlay" ]; then
      repo_path="$overlay"
    else
      repo_path=$(resolve_skill_path "$skills_source_dir/$skill")
    fi
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
    local upstream_filename="$agent.md"
    [ -n "$rename_from" ] && upstream_filename="$rename_from"
    repo_agent="$agents_source_dir/$upstream_filename"

    # Per-group agent overlay (keyed by upstream filename)
    local agent_overlay
    agent_overlay=$(resolve_agent_overlay "$group" "$upstream_filename")
    [ -n "$agent_overlay" ] && repo_agent="$agent_overlay"

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

  # Ensure CLAUDE.md trigger phrases are present. install_claude_md_snippet is
  # idempotent — it no-ops when the snippet's header is already in CLAUDE.md —
  # so it's safe to call on every update and catches groups that were added
  # after the last fresh install.
  install_claude_md_snippet "$group"

  # Update slash commands: symlink skill-groups/<g>/commands/*.md → ~/.claude/commands/
  # Commands always live in the local skill-group dir (no vendored equivalent).
  local commands_source_dir="$SKILL_GROUPS_DIR/$group/commands"
  local commands
  commands=$(json_array "$manifest" "commands")
  for cmd in $commands; do
    local repo_cmd="$commands_source_dir/$cmd.md"
    local local_cmd="$COMMANDS_DIR/$cmd.md"

    if [ ! -f "$repo_cmd" ]; then
      warn "Command not found in repo: /$cmd (looked in $repo_cmd)"
      continue
    fi

    mkdir -p "$COMMANDS_DIR"

    if [ -f "$local_cmd" ]; then
      if ! diff_skill "$local_cmd" "$repo_cmd"; then
        info "Command /$cmd has changed in repo — updating"
        backup_file "$local_cmd"
        rm -f "$local_cmd"
        create_symlink "$repo_cmd" "$local_cmd"
        ok "Command: /$cmd (updated)"
      else
        ok "Command: /$cmd (up to date)"
      fi
    else
      create_symlink "$repo_cmd" "$local_cmd"
      ok "Command: /$cmd (installed)"
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
      local answer=""
      if [ "$NON_INTERACTIVE" != "true" ]; then
        read -rp "  Sync local version back to repo? [y/N]: " answer
      fi
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
        if [ "$NON_INTERACTIVE" = "true" ]; then
          info "$skill_name: skipped (non-interactive)"
        else
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
        fi
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
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$local_path/" "$repo_path/"
    else
      rm -rf "$repo_path"
      cp -r "$local_path" "$repo_path"
    fi
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
    manifest=$(tr -d '\r' < "$group_dir/manifest.json")

    local gtype
    gtype=$(group_type "$group")
    [ "$gtype" = "tool-only" ] && continue

    local skills_source_dir
    if [ "$gtype" = "vendored" ]; then
      local repo slug
      repo=$(vendored_source_get "$group" "repo")
      slug=$(repo_slug "$repo")
      local skills_path
      skills_path=$(vendored_source_get "$group" "paths.skills")
      skills_source_dir="$CLAUDE_DIR/.skill-repos/$slug/$skills_path"
    else
      local source_repo
      source_repo=$(json_get "$manifest" "source_repo")
      if [ -n "$source_repo" ]; then
        local repo_cache="$CLAUDE_DIR/.skill-repos/$group"
        local skills_path
        skills_path=$(echo "$manifest" | grep -A1 '"source_paths"' | grep '"skills"' | sed 's/.*: *"//;s/".*//')
        skills_source_dir="$repo_cache/$skills_path"
      else
        skills_source_dir="$SKILL_GROUPS_DIR/$group/skills"
      fi
    fi

    local skills
    skills=$(json_array "$manifest" "skills")
    for skill in $skills; do
      local repo_path local_path local_ver repo_ver status
      # Per-group overlay takes precedence over source_repo
      local overlay
      overlay=$(resolve_skill_overlay "$group" "$skill")
      if [ -n "$overlay" ]; then
        repo_path="$overlay"
      else
        repo_path=$(resolve_skill_path "$skills_source_dir/$skill")
      fi
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
    manifest=$(tr -d '\r' < "$group_dir/manifest.json")
    all_managed_skills="$all_managed_skills $(json_array "$manifest" "skills")"
  done

  local found_unmanaged=false
  for item in "$SKILLS_DIR"/*; do
    [ -e "$item" ] || continue
    local name
    name=$(basename "$item" .md)
    # Skip if it's managed
    local is_managed=false
    for managed in $all_managed_skills; do
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

# ─── Vendor status (--vendor-status) ────────────────────────────────────────

show_vendor_status() {
  header "Vendored groups"
  echo ""
  printf "  ${BOLD}%-20s %-12s %-12s %s${NC}\n" "Group" "Pinned" "Upstream" "Delta"
  printf "  %-20s %-12s %-12s %s\n" "────────────────────" "────────────" "────────────" "──────────────────"

  for group_dir in "$SKILL_GROUPS_DIR"/*/; do
    [ -f "$group_dir/manifest.json" ] || continue
    local group
    group=$(basename "$group_dir")
    local gtype
    gtype=$(group_type "$group")
    [ "$gtype" = "vendored" ] || continue

    local repo ref slug clone_dir
    repo=$(vendored_source_get "$group" "repo")
    ref=$(vendored_source_get "$group" "ref")
    slug=$(repo_slug "$repo")
    clone_dir="$CLAUDE_DIR/.skill-repos/$slug"

    local upstream_head="-" delta="-" head_short="-" ref_short
    ref_short="${ref:0:10}"
    if [ -d "$clone_dir/.git" ]; then
      (cd "$clone_dir" && git fetch --quiet origin 2>/dev/null) || true
      upstream_head=$(cd "$clone_dir" && git rev-parse origin/HEAD 2>/dev/null || git rev-parse origin/main 2>/dev/null || echo "-")
      head_short="${upstream_head:0:10}"
      if [ "$upstream_head" != "-" ]; then
        local resolved
        resolved=$(cd "$clone_dir" && git rev-parse "$ref" 2>/dev/null) || resolved="$ref"
        local count
        count=$(cd "$clone_dir" && git rev-list --count "$resolved..$upstream_head" 2>/dev/null) || count="?"
        if [ "$count" = "0" ]; then
          delta="up to date"
        else
          delta="$count commits behind"
        fi
      fi
    else
      delta="(not cloned)"
    fi
    printf "  %-20s %-12s %-12s %s\n" "$group" "$ref_short" "$head_short" "$delta"
    info "    repo: $repo"
  done
  echo ""
}

# ─── Bump vendor (--bump-vendor <group>) ────────────────────────────────────

bump_vendor() {
  local group="$1"
  local manifest_file="$SKILL_GROUPS_DIR/$group/manifest.json"
  if [ ! -f "$manifest_file" ]; then
    fail "Unknown group: $group"
    return 1
  fi
  local gtype
  gtype=$(group_type "$group")
  if [ "$gtype" != "vendored" ]; then
    fail "$group is type=$gtype, not vendored"
    return 1
  fi

  local repo ref slug clone_dir
  repo=$(vendored_source_get "$group" "repo")
  ref=$(vendored_source_get "$group" "ref")
  slug=$(repo_slug "$repo")
  clone_dir="$CLAUDE_DIR/.skill-repos/$slug"

  if [ ! -d "$clone_dir/.git" ]; then
    info "Cloning $repo for first-time bump..."
    git clone --quiet "https://github.com/${repo}.git" "$clone_dir" || { fail "Clone failed"; return 1; }
  fi

  (cd "$clone_dir" && git fetch --quiet origin) || warn "Fetch failed"

  local upstream_head resolved
  upstream_head=$(cd "$clone_dir" && git rev-parse origin/HEAD 2>/dev/null || git rev-parse origin/main 2>/dev/null)
  resolved=$(cd "$clone_dir" && git rev-parse "$ref" 2>/dev/null) || resolved="$ref"

  if [ "$resolved" = "$upstream_head" ]; then
    ok "$group: already at upstream HEAD ($upstream_head)"
    return 0
  fi

  header "Commits in $repo since $ref"
  (cd "$clone_dir" && git log --oneline "$resolved..$upstream_head") || true
  echo ""

  if [ "$NON_INTERACTIVE" = "true" ]; then
    info "Non-interactive: would bump $group $ref → $upstream_head"
    return 0
  fi

  read -rp "Bump pinned ref to $upstream_head? [y/N]: " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    info "Aborted"
    return 0
  fi

  # Targeted in-place edit: replace only the ref string. Avoids the full
  # JSON.parse → stringify round-trip, which would reflow inline arrays and
  # other formatting choices and produce noisy diffs on every bump.
  node -e "
    const fs = require('fs');
    const p = process.argv[1];
    const oldRef = process.argv[2];
    const newRef = process.argv[3];
    const text = fs.readFileSync(p, 'utf8');
    const re = new RegExp('(\"ref\"\\\\s*:\\\\s*\")' + oldRef.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\$&') + '(\")');
    const out = text.replace(re, '\$1' + newRef + '\$2');
    if (out === text) {
      // Fallback: manifest may have had no ref or a non-matching one — fall
      // back to a structural rewrite so the bump still succeeds.
      const m = JSON.parse(text);
      if (!m.source) m.source = {};
      m.source.ref = newRef;
      fs.writeFileSync(p, JSON.stringify(m, null, 2) + '\n');
      process.stderr.write('warn: ref string not found inline; rewrote manifest structurally\n');
    } else {
      fs.writeFileSync(p, out);
    }
  " "$manifest_file" "$ref" "$upstream_head"

  (cd "$clone_dir" && git checkout --quiet "$upstream_head") || warn "Failed to checkout new ref locally"

  ok "$group: bumped $ref → $upstream_head in manifest"
  info "Review the diff and commit: git -C $SCRIPT_DIR add skill-groups/$group/manifest.json && git commit"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  SELECTED_GROUPS=()
  SKIP_SOFTWARE=false
  SYNC_MODE=false
  NON_INTERACTIVE=false
  INSTALL_SKIPPED=false
  MODE="install"  # install, verify, test-integration, update, status, vendor-status, bump-vendor
  BUMP_GROUP=""

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
      --yes|-y)
        NON_INTERACTIVE=true
        shift
        ;;
      --status)
        MODE="status"
        shift
        ;;
      --vendor-status)
        MODE="vendor-status"
        shift
        ;;
      --bump-vendor)
        MODE="bump-vendor"
        BUMP_GROUP="${2:-}"
        if [ -z "$BUMP_GROUP" ]; then
          fail "--bump-vendor requires a group name"
          exit 1
        fi
        shift 2
        ;;
      --check-drift)
        MODE="check-drift"
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
        echo "  --update               Update only ALREADY-INSTALLED groups; prompts before adding new ones"
        echo "  --update --sync        Also sync newer local skills back to repo"
        echo "  --status               Show version table for all skills"
        echo "  --vendor-status        Show pinned vs upstream SHA for vendored groups"
        echo "  --bump-vendor GROUP    Bump pinned ref of a vendored group to upstream HEAD"
        echo "  --check-drift          Diff live MCP server tools vs what skill docs reference"
        echo ""
        echo "Options:"
        echo "  --skills GROUP1,GROUP2 Target specific skill groups (default: interactive)"
        echo "  --skip-software        Skip software installation, only install skills/agents"
        echo "  --yes, -y              Non-interactive mode (auto-accept prompts, skip manual installs)"
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
        echo "  install.sh --check-drift                      # Drift-check all mcp-backed groups"
        echo "  install.sh --check-drift --skills blender     # Drift-check just blender"
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

  # ── Drift-check mode (runs before the default-all expansion so the drift
  #     script can do its own filtering to mcp-backed groups) ──
  if [ "$MODE" = "check-drift" ]; then
    drift_script="$SCRIPT_DIR/scripts/check-mcp-drift.sh"
    if [ ! -f "$drift_script" ]; then
      fail "Missing $drift_script"
      exit 1
    fi
    if [ ${#SELECTED_GROUPS[@]} -gt 0 ]; then
      bash "$drift_script" "${SELECTED_GROUPS[@]}"
    else
      bash "$drift_script"
    fi
    exit $?
  fi

  # For non-install modes, default to all groups if none specified
  if [ "$MODE" != "install" ] && [ ${#SELECTED_GROUPS[@]} -eq 0 ]; then
    SELECTED_GROUPS=($(list_groups))
  fi

  # ── Status mode ──
  if [ "$MODE" = "status" ]; then
    show_status
    exit 0
  fi

  # ── Vendor status mode ──
  if [ "$MODE" = "vendor-status" ]; then
    show_vendor_status
    exit 0
  fi

  # ── Bump vendor mode ──
  if [ "$MODE" = "bump-vendor" ]; then
    bump_vendor "$BUMP_GROUP"
    exit $?
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
    install_shell_aliases
    install_git_hooks

    # Update refreshes only groups already installed locally — it never silently
    # adds new ones. Groups present in the repo but not installed are surfaced as
    # "new" and offered. A ledger ($KNOWN_GROUPS_FILE) records groups already shown
    # so declined ones aren't re-offered every run. On the first update after this
    # feature lands the ledger is absent, so we seed it with all current groups and
    # offer nothing — only groups added *later* count as new.
    local ledger_seeded=true
    [ -f "$KNOWN_GROUPS_FILE" ] || ledger_seeded=false

    local update_targets=() new_groups=()
    for group in "${SELECTED_GROUPS[@]}"; do
      if [ ! -f "$SKILL_GROUPS_DIR/$group/manifest.json" ]; then
        fail "Unknown skill group: $group"
        continue
      fi
      if group_is_installed "$group"; then
        update_targets+=("$group")
      elif [ "$ledger_seeded" = true ] && ! grep -qxF "$group" "$KNOWN_GROUPS_FILE" 2>/dev/null; then
        new_groups+=("$group")
      fi
    done

    for group in "${update_targets[@]}"; do
      update_group "$group"
    done

    # Prune managed symlinks no longer in any manifest
    sweep_orphans

    # Surface genuinely-new groups and offer to install them.
    local chosen_new=()
    if [ ${#new_groups[@]} -gt 0 ]; then
      echo ""
      header "New skill group(s) available in the repo:"
      for g in "${new_groups[@]}"; do
        local gdesc
        gdesc=$(json_get "$(tr -d '\r' < "$SKILL_GROUPS_DIR/$g/manifest.json")" "description")
        printf "  ${BOLD}%s${NC} — %s\n" "$g" "$gdesc"
      done
      echo ""
      if [ "$NON_INTERACTIVE" = true ]; then
        info "Non-interactive: not installing. Add any later with: install.sh --skills <group>"
      else
        local sel
        read -rp "Install any now? (comma-separated names, 'a' for all, Enter to skip): " sel
        if [ "$sel" = a ] || [ "$sel" = A ]; then
          chosen_new=("${new_groups[@]}")
        elif [ -n "$sel" ]; then
          local pick g
          IFS=',' read -ra _picks <<< "$sel"
          for pick in "${_picks[@]}"; do
            pick=$(echo "$pick" | tr -d ' ')
            for g in "${new_groups[@]}"; do
              [ "$pick" = "$g" ] && chosen_new+=("$g")
            done
          done
        fi
      fi
    fi

    # Record all current repo groups as known so declined ones aren't re-offered.
    mkdir -p "$META_DIR"
    printf '%s\n' $(list_groups) > "$KNOWN_GROUPS_FILE"

    echo ""
    header "Update Summary"
    echo -e "  ${GREEN}$PASS_COUNT passed${NC}  ${YELLOW}$WARN_COUNT warnings${NC}  ${RED}$FAIL_COUNT failed${NC}"
    if [ "$SYNC_MODE" = "true" ] && [ "$WARN_COUNT" -gt 0 ]; then
      echo ""
      info "Don't forget to commit and push repo changes if you synced skills back"
    fi

    # Full install for any newly-chosen groups (reuse the standard install path).
    if [ ${#chosen_new[@]} -gt 0 ]; then
      echo ""
      header "Installing newly selected group(s): ${chosen_new[*]}"
      local joined
      joined=$(IFS=,; echo "${chosen_new[*]}")
      "$SCRIPT_DIR/install.sh" --skills "$joined"
    fi
    exit 0
  fi

  # ── Install mode ──

  install_global_prerequisites
  install_shell_aliases
  install_git_hooks

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

    # Reset per-group install state
    INSTALL_SKIPPED=false

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

    # Step 5: Install MCP server configs
    install_mcp_config "$group"

    # Step 6: Append CLAUDE.md snippet
    install_claude_md_snippet "$group"

    # Step 7: Smoke test (skip if software install was skipped)
    if [ "$SKIP_SOFTWARE" = "false" ] && [ "$INSTALL_SKIPPED" != "true" ]; then
      run_test "$group"
    elif [ "$INSTALL_SKIPPED" = "true" ]; then
      info "Smoke test: skipped (software install was skipped)"
    fi

    # Step 8: Per-group shell aliases (e.g. cs() for claude-code-sessions)
    install_group_shell_aliases "$group"

    # Step 8: Show post-install hints
    show_post_install_hints "$group"
  done

  # Install shared skills
  header "── shared ──"
  install_shared_skills

  # Prune managed symlinks (commands, agents, skills) no longer in any manifest
  sweep_orphans

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
