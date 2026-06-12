#!/usr/bin/env bash
# claude-skills post-merge hook
#
# Fires after `git pull` (or any `git merge`). If the merge brought in changes
# to any skill-groups/<g>/manifest.json, prints a reminder per affected group.
# Silent otherwise.
#
# Installed by install.sh to .git/hooks/post-merge (idempotent).

set -euo pipefail

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  YELLOW='\033[1;33m'; DIM='\033[2m'; NC='\033[0m'
else
  YELLOW=''; DIM=''; NC=''
fi

# Find all manifest files that changed in this merge
changed_manifests=$(git diff --name-only ORIG_HEAD HEAD 2>/dev/null | \
  grep -E '^skill-groups/[^/]+/manifest\.json$' || true)

[ -z "$changed_manifests" ] && exit 0

echo ""
echo -e "${YELLOW}⚠ claude-skills:${NC} manifest changes pulled — local install may be stale"
while IFS= read -r m; do
  group=$(echo "$m" | sed -E 's#^skill-groups/([^/]+)/manifest\.json$#\1#')
  echo -e "  ${YELLOW}→${NC} ${group}  ${DIM}(run: bash install.sh --skills ${group})${NC}"
done <<< "$changed_manifests"
echo -e "  ${DIM}or update everything at once: bash install.sh --update${NC}"
echo ""
