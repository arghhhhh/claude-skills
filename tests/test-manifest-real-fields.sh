#!/usr/bin/env bash
# test-manifest-real-fields.sh
# Contract tests for the manifest fields install.sh ACTUALLY consumes, beyond the
# generic name/version/description/install/test set covered by
# test-manifest-contracts.sh. Traced from install.sh:
#   - mcp_servers            (install_mcp_config, install.sh:1725-1919)
#   - wsl_propagate          (propagate_to_wsl, install.sh:2397-2428)
#   - config_vars            (configure_skills / install_mcp_config prompts)
#   - install.check gating   (install_software, install.sh:1257; group_is_installed:2344)
#   - vendored source block  (vendored_ensure_clone:570-609, validate_vendor_ref:559-566)
#   - legacy source_repo / source_paths back-compat reader (install.sh:1366-1383)
#   - update_policy          (group_update_policy:521-533, update_group:2442)
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework.sh
source "$TESTS_DIR/framework.sh"

echo -e "${BOLD}test-manifest-real-fields${NC}"

jnode() { # jnode <manifest> <js-expr on m, writes to stdout>
  node -e "
    try {
      const m = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      $2
    } catch(e) {}
  " "$1" 2>/dev/null || true
}

for group_dir in "$SKILL_GROUPS_DIR"/*/; do
  group="$(basename "$group_dir")"
  mf="$group_dir/manifest.json"
  [ -f "$mf" ] || continue
  gtype=$(group_type "$group")

  # ── mcp_servers: every entry needs a command; args must be an array; every
  #    {{PLACEHOLDER}} used must have a config_vars entry or config.example.sh
  #    line, otherwise install_mcp_config can never prompt/resolve it. ──
  if grep -q '"mcp_servers"' "$mf" 2>/dev/null; then
    suite "mcp_servers: $group"
    bad=$(jnode "$mf" "
      const out=[];
      for (const [n,c] of Object.entries(m.mcp_servers||{})) {
        if (!c.command) out.push(n+': missing command');
        if (c.args!==undefined && !Array.isArray(c.args)) out.push(n+': args not array');
      }
      process.stdout.write(out.join('\n'));")
    if [ -z "$bad" ]; then ok "all mcp_servers entries have command + array args"; else
      while IFS= read -r l; do fail "$l"; done <<< "$bad"; fi

    # placeholders in mcp_servers must be resolvable: config_vars OR config.example.sh
    phs=$(jnode "$mf" "
      const s=JSON.stringify(m.mcp_servers||{});
      const set=new Set((s.match(/\{\{([A-Z_]+)\}\}/g)||[]).map(x=>x.replace(/[{}]/g,'')));
      process.stdout.write([...set].join(' '));")
    for ph in $phs; do
      in_cv=$(jnode "$mf" "process.stdout.write((m.config_vars||{})['$ph']?'yes':'no');")
      if [ "$in_cv" = "yes" ] || grep -q "$ph" "$REPO_DIR/config.example.sh" 2>/dev/null; then
        ok "{{$ph}} resolvable (config_vars or config.example.sh)"
      else
        fail "{{$ph}} used in mcp_servers but declared nowhere (installer can never prompt for it)"
      fi
    done
  fi

  # ── wsl_propagate: fail-closed contract — a command without a check would
  #    install into distros the user never configured (install.sh:2408-2413).
  #    {{REPO}} is the only substitution propagate_to_wsl performs. ──
  if grep -q '"wsl_propagate"' "$mf" 2>/dev/null; then
    suite "wsl_propagate: $group"
    wcmd=$(jnode "$mf" "process.stdout.write((m.wsl_propagate||{}).command||'');")
    wchk=$(jnode "$mf" "process.stdout.write((m.wsl_propagate||{}).check||'');")
    assert_not_empty "wsl_propagate.command present" "$wcmd"
    if [ -n "$wcmd" ] && [ -z "$wchk" ]; then
      fail "wsl_propagate.command without .check — propagate_to_wsl fails open into fresh distros? No: it fails closed (2410), but the field is then dead config"
    else
      ok "wsl_propagate.check present (fail-closed gate)"
    fi
    case "$wcmd" in
      *'{{REPO}}'*|*'$HOME'*|/*|bash*) ok "command uses {{REPO}}/portable path" ;;
      *) fail "command '$wcmd' has no {{REPO}} or portable root — will break across machines" ;;
    esac
  fi

  # ── config_vars: each entry should have a prompt (used by configure_skills
  #    interactive path, install.sh:1628-1634) and each var actually appears
  #    somewhere (skills, mcp_servers, or install) — else it's dead config. ──
  if grep -q '"config_vars"' "$mf" 2>/dev/null; then
    suite "config_vars: $group"
    vars=$(jnode "$mf" "process.stdout.write(Object.keys(m.config_vars||{}).join(' '));")
    for v in $vars; do
      p=$(jnode "$mf" "process.stdout.write(((m.config_vars||{})['$v']||{}).prompt||'');")
      if [ -n "$p" ]; then ok "$v has prompt"; else fail "$v missing prompt (interactive configure shows generic text)"; fi
      if grep -rq "{{$v}}" "$group_dir" 2>/dev/null; then
        ok "{{$v}} referenced in group content"
      elif grep -rq "$v" "$group_dir" 2>/dev/null || grep -q "$v" "$REPO_DIR/config.example.sh" 2>/dev/null; then
        # Some groups consume config vars as env vars sourced from
        # skills-config.sh (huggingface-downloader, obs-studio) rather than
        # via {{}} substitution — name mention counts as usage.
        ok "$v consumed by name (env-var style, no {{}} substitution)"
      else
        fail "config_var $v declared but never referenced anywhere in $group"
      fi
    done
  fi

  # ── install.check gating: check:"false" means ALWAYS re-run install (used by
  #    context-rotation). For non-tool-only that's fine; for tool-only groups,
  #    group_is_installed/verify need test.command as the real probe
  #    (install.sh:2344-2355, 2110-2123). Also: the installer's legacy
  #    json_get/sed extractors truncate at the first double quote — check and
  #    test.command must not contain double quotes. ──
  suite "install/test gating: $group"
  icheck=$(jnode "$mf" "process.stdout.write(((m.install||{}).check)||'');")
  tcmd=$(jnode "$mf" "process.stdout.write(((m.test||{}).command)||'');")
  if [ "$icheck" = "false" ] && [ -z "$tcmd" ]; then
    fail "install.check=false with no test.command — verify + group_is_installed permanently broken"
  else
    ok "install.check/test.command combination is verify-safe"
  fi
  case "$icheck$tcmd" in
    *'"'*) fail "install.check or test.command contains a double quote — sed extractor truncates at first quote" ;;
    *) ok "no double quotes in check/test.command" ;;
  esac

  # ── vendored source block: repo owner/name form, ref pinned (40-hex SHA or
  #    version tag; bare branch names rejected — mirrors validate_vendor_ref
  #    install.sh:559-566 and vendored_ensure_clone). paths.skills required
  #    (install_skills:1361-1363 builds the source dir from it). ──
  if [ "$gtype" = "vendored" ]; then
    suite "vendored source: $group"
    srepo=$(jnode "$mf" "process.stdout.write((m.source||{}).repo||'');")
    sref=$(jnode "$mf" "process.stdout.write((m.source||{}).ref||'');")
    spaths=$(jnode "$mf" "process.stdout.write(((m.source||{}).paths||{}).skills||'');")
    assert_match "source.repo is owner/name" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' "$srepo"
    case "$sref" in
      main|master|develop|HEAD|trunk|dev)
        fail "source.ref '$sref' is a bare branch name (validate_vendor_ref rejects at install time)" ;;
      *) ok "source.ref not a bare branch name" ;;
    esac
    if echo "$sref" | grep -qE '^[0-9a-f]{40}$'; then
      ok "source.ref is a full 40-char SHA (immutable pin)"
    elif echo "$sref" | grep -qE '^v?[0-9]+\.[0-9]+'; then
      ok "source.ref is a version tag (accepted, weaker than SHA)"
    else
      fail "source.ref '$sref' is neither full SHA nor version tag — pin integrity not verifiable"
    fi
    assert_not_empty "source.paths.skills present" "$spaths"
    case "$spaths" in
      /*|[A-Za-z]:*) fail "source.paths.skills is absolute — must be repo-relative" ;;
      *) ok "source.paths.skills is repo-relative" ;;
    esac
  fi

  # ── legacy source_repo/source_paths back-compat (install.sh:1366-1383): the
  #    reader clones at HEAD with NO pinned ref and NO BAD_BRANCHES guard. Any
  #    manifest still using it silently loses the SHA-pin integrity contract.
  #    Contract: no group may use the legacy fields; migrate to type:vendored. ──
  if grep -q '"source_repo"' "$mf" 2>/dev/null; then
    suite "legacy source_repo: $group"
    fail "uses legacy source_repo (unpinned HEAD clone path install.sh:1366-1383) — migrate to type:vendored with source.ref SHA"
    # Its source_paths.skills must still parse under the fragile grep -A1 reader
    sp=$(grep -A1 '"source_paths"' "$mf" | grep '"skills"' | sed 's/.*: *"//;s/".*//')
    assert_not_empty "legacy source_paths.skills extractable by installer's grep chain" "$sp"
  fi

  # ── update_policy: only pinned|latest are meaningful (group_update_policy
  #    defaults everything else to the string as-is; update_group only tests
  #    'latest'). tool-only groups whose install command references this repo
  #    must be 'latest' or --update never refreshes them. ──
  pol=$(jnode "$mf" "process.stdout.write(m.update_policy||'pinned');")
  case "$pol" in
    pinned|latest) : ;;
    *) suite "update_policy: $group"; fail "update_policy '$pol' is not pinned|latest — treated as pinned silently" ;;
  esac
  if [ "$gtype" = "tool-only" ]; then
    cmd0=$(jnode "$mf" "const ms=((m.install||{}).methods)||[]; process.stdout.write(ms.length?(ms[0].command||''):'');")
    case "$cmd0" in
      *skill-repos/claude-skills*|*'{{REPO}}'*)
        if [ "$pol" != "latest" ]; then
          suite "update_policy: $group"
          fail "tool-only install references this repo but update_policy=$pol — repo changes never reach installs via --update"
        else
          ok "$group: repo-sourced tool-only correctly update_policy=latest"
        fi ;;
    esac
  fi
done

summary
