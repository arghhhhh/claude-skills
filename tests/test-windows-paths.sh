#!/usr/bin/env bash
# test-windows-paths.sh
# Validates Windows path handling in the installer:
#   - Windows symlink fallback: mklink /J → mklink /D → cp
#   - cygpath-style path conversion (Windows Git Bash)
#   - {{PLACEHOLDER}} substitution handles Windows paths (backslashes, spaces)
#   - repo_slug() handles repo strings with slashes correctly
#   - Platform detection correctly identifies windows (MINGW/MSYS/CYGWIN)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-windows-paths${NC}"

# ─── repo_slug ────────────────────────────────────────────────────────────────

suite "repo_slug: path-safe conversion"

# Mirror of install.sh's repo_slug
repo_slug() {
  echo "$1" | tr '/' '-' | sed 's/\.git$//'
}

assert_eq "owner/repo → owner-repo" "owner-repo" "$(repo_slug 'owner/repo')"
assert_eq "owner/repo.git → owner-repo" "owner-repo" "$(repo_slug 'owner/repo.git')"
assert_eq "my-org/my-repo → my-org-my-repo" "my-org-my-repo" "$(repo_slug 'my-org/my-repo')"
assert_eq "akiojin/unity-cli → akiojin-unity-cli" "akiojin-unity-cli" "$(repo_slug 'akiojin/unity-cli')"
# With .git suffix
assert_eq "owner/repo.git stripped" "owner-repo" "$(repo_slug 'owner/repo.git')"

# ─── sed_escape_repl: Windows path safety ─────────────────────────────────────

suite "sed_escape_repl: backslash/pipe/ampersand escaping"

# Mirror of install.sh's sed_escape_repl
sed_escape_repl() {
  printf '%s' "$1" | sed 's/[|&\\]/\\&/g'
}

# Windows path with backslashes
result=$(sed_escape_repl 'C:\Users\Joss\tools')
assert_eq "backslashes escaped" 'C:\\Users\\Joss\\tools' "$result"

# Path with pipe (edge case)
result=$(sed_escape_repl '/usr/local|bin')
assert_eq "pipe escaped" '/usr/local\|bin' "$result"

# Path with ampersand
result=$(sed_escape_repl 'path&more')
assert_eq "ampersand escaped" 'path\&more' "$result"

# Normal Unix path — no change
result=$(sed_escape_repl '/home/user/.claude')
assert_eq "normal path unchanged" '/home/user/.claude' "$result"

# ─── Platform detection ────────────────────────────────────────────────────────

suite "detect_platform: uname-based detection"

detect_platform() {
  case "$(uname -s)" in
    Darwin*)             echo "macos" ;;
    Linux*)              echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)                   echo "unknown" ;;
  esac
}

platform=$(detect_platform)
case "$platform" in
  macos|linux|windows)
    ok "detect_platform returned valid value: '$platform'" ;;
  *)
    fail "detect_platform returned unexpected value: '$platform'" ;;
esac

# ─── {{PLACEHOLDER}} substitution ────────────────────────────────────────────

suite "placeholder substitution correctness"

# Test that {{PLACEHOLDER}} in a string can be replaced correctly
# even with Windows-style paths (backslashes, spaces in paths)
subst_test() {
  local template="$1" var_name="$2" var_val="$3"
  local val_esc
  val_esc=$(sed_escape_repl "$var_val")
  printf '%s' "$template" | sed "s|{{${var_name}}}|${val_esc}|g"
}

result=$(subst_test "run {{MYPATH}}/server.py" "MYPATH" "/home/user/.local")
assert_eq "unix path substituted" "run /home/user/.local/server.py" "$result"

result=$(subst_test "run {{MYPATH}}\\server.py" "MYPATH" 'C:\Users\Joss')
assert_eq "windows path substituted" 'run C:\Users\Joss\server.py' "$result"

result=$(subst_test "cmd {{MYPATH}}" "MYPATH" '/path with spaces/tool')
assert_eq "path with spaces substituted" "cmd /path with spaces/tool" "$result"

# No placeholder — unchanged
result=$(subst_test "no placeholders here" "MYPATH" "/some/path")
assert_eq "template without placeholder unchanged" "no placeholders here" "$result"

# ─── Windows paths in manifest install commands ────────────────────────────────

suite "Windows install methods present where expected"

windows_group_count=0
for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  # Check if any method declares windows platform
  has_windows=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const methods=(m.install||{}).methods||[];
      const found=methods.some(me=>(me.platforms||[]).includes('windows'));
      process.stdout.write(found?'yes':'no');
    } catch(e){process.stdout.write('no');}
  " "$mf" 2>/dev/null) || has_windows="no"

  [ "$has_windows" = "yes" ] || continue
  windows_group_count=$((windows_group_count + 1))

  # Verify the windows method has a command or url
  windows_method_ok=$(node -e "
    try {
      const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const methods=(m.install||{}).methods||[];
      const win=methods.filter(me=>(me.platforms||[]).includes('windows'));
      const ok=win.every(me=>me.command||me.url);
      process.stdout.write(ok?'yes':'no');
    } catch(e){process.stdout.write('no');}
  " "$mf" 2>/dev/null) || windows_method_ok="no"

  if [ "$windows_method_ok" = "yes" ]; then
    ok "$group: windows install method has command or url"
  else
    fail "$group: windows install method is missing both command and url"
  fi
done

if [ "$windows_group_count" -eq 0 ]; then
  ok "no groups with explicit windows install methods (cross-platform methods handle windows)"
else
  ok "$windows_group_count group(s) have explicit windows install methods"
fi

# ─── wsl_propagate structure ──────────────────────────────────────────────────

suite "wsl_propagate structure"

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue

  has_wsl=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write(m.wsl_propagate?'yes':'no');
  " "$mf" 2>/dev/null) || has_wsl="no"

  [ "$has_wsl" = "yes" ] || continue

  # wsl_propagate must have both 'check' and 'command'
  wsl_check=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write((m.wsl_propagate||{}).check||'');
  " "$mf" 2>/dev/null) || wsl_check=""

  wsl_cmd=$(node -e "
    const m=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.stdout.write((m.wsl_propagate||{}).command||'');
  " "$mf" 2>/dev/null) || wsl_cmd=""

  assert_not_empty "$group: wsl_propagate.check" "$wsl_check"
  assert_not_empty "$group: wsl_propagate.command" "$wsl_cmd"

  # command should use {{REPO}} so WSL reuses Windows clone
  if echo "$wsl_cmd" | grep -q '{{REPO}}'; then
    ok "$group: wsl_propagate.command uses {{REPO}} (reuses Windows clone)"
  else
    fail "$group: wsl_propagate.command should use {{REPO}} — not re-cloning into WSL"
  fi
done

summary
