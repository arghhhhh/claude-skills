#!/usr/bin/env node
// Open, update and close one GitHub issue per upstream pin that is behind.
// Run by .github/workflows/upstream-check.yml; needs the gh CLI and GH_TOKEN.
//
//   node scripts/upstream-issues.js [--dry-run]
//
// Each issue carries a hidden "upstream-key" marker, so its title can change
// as upstream moves while it stays the same issue. When a pin catches up (or
// its tool is removed from a manifest), the issue is closed.
'use strict';
const { execFileSync } = require('child_process');
const path = require('path');

const LABEL = 'upstream';
const DRY = process.argv.includes('--dry-run');
const CHECK = path.join(__dirname, 'check-upstream.js');

function gh(args, input) {
  if (DRY && !['issue list', 'label list'].includes(args.slice(0, 2).join(' '))) {
    console.log('[dry-run] gh ' + args.map(a => (a.length > 60 ? a.slice(0, 57) + '...' : a)).join(' '));
    return '';
  }
  return execFileSync('gh', args, { encoding: 'utf8', input, stdio: ['pipe', 'pipe', 'inherit'] });
}

const short = (e, v) => (e.type === 'git' ? String(v).slice(0, 7) : String(v).replace(/^v/, ''));

function title(r) {
  return `[upstream] ${r.group}: ${r.tool} ${short(r, r.pin)} → ${short(r, r.latest)}`;
}

function body(r) {
  const key = `${r.group}/${r.tool}`;
  const where = r.group === '_installer' ? 'shared/upstream.json' : `skill-groups/${r.group}/manifest.json`;
  const field = r.tool === 'source' ? 'source.ref (and any install command that uses the same commit)' : `upstream["${r.tool}"].pin`;
  const kind = r.installs === false
    ? 'Tracking only: install.sh doesn\'t install this tool, so only the skill text needs checking.'
    : r.enforced === false
      ? 'Not enforced: users already get the newest version, so the skill text may be out of date.'
      : 'Pinned: install.sh installs exactly this version. Users keep the old version until the pin is bumped.';
  const prompt = `In claude-skills, bump ${key} from ${r.pin} to ${r.latest}. ` +
    `Read what changed (${r.url}), update ${field} in ${where}, update the skill text if commands, flags or tools changed, ` +
    `run tests/run-tests.sh, bump the group version, then commit and push.`;
  return [
    `**${key}** is pinned to \`${r.pin}\`; upstream is at \`${r.latest}\`.`,
    '',
    `- What changed: ${r.url}`,
    `- Source: \`${r.type}\` ${r.repo || r.package || r.url || r.id}`,
    `- ${kind}`,
    r.note ? `- Note: ${r.note}` : null,
    '',
    'To have an agent do the bump, run this in the repo:',
    '',
    '```',
    `claude "${prompt.replace(/"/g, '\\"')}"`,
    '```',
    '',
    `<!-- upstream-key: ${key} -->`,
    `<!-- upstream-latest: ${r.latest} -->`,
  ].filter(l => l !== null).join('\n');
}

function main() {
  const results = JSON.parse(execFileSync(process.execPath, [CHECK, '--json'], { encoding: 'utf8', maxBuffer: 1 << 24 }));

  if (!gh(['label', 'list', '--search', LABEL, '--json', 'name']).includes(`"${LABEL}"`)) {
    gh(['label', 'create', LABEL, '--color', 'C2410C', '--description', 'A pinned upstream tool has a newer version']);
  }
  const open = JSON.parse(gh(['issue', 'list', '--label', LABEL, '--state', 'open', '--limit', '500', '--json', 'number,title,body']) || '[]');
  const byKey = new Map();
  for (const i of open) {
    const m = (i.body || '').match(/<!-- upstream-key: (\S+) -->/);
    if (m) byKey.set(m[1], i);
  }

  const seen = new Set();
  const errors = [];
  let opened = 0, updated = 0, closed = 0;
  for (const r of results) {
    const key = `${r.group}/${r.tool}`;
    seen.add(key);
    if (r.error) { errors.push(`${key}: ${r.error}`); continue; }
    const issue = byKey.get(key);
    if (r.behind) {
      if (!issue) {
        gh(['issue', 'create', '--title', title(r), '--label', LABEL, '--body-file', '-'], body(r));
        opened++;
      } else if (!issue.body.includes(`<!-- upstream-latest: ${r.latest} -->`) || issue.title !== title(r)) {
        gh(['issue', 'edit', String(issue.number), '--title', title(r), '--body-file', '-'], body(r));
        gh(['issue', 'comment', String(issue.number), '--body', `Upstream moved to \`${r.latest}\`.`]);
        updated++;
      }
    } else if (issue) {
      gh(['issue', 'close', String(issue.number), '--comment', `Pin is now \`${r.pin}\`, which matches upstream.`]);
      closed++;
    }
  }
  for (const [key, issue] of byKey) {
    if (!seen.has(key)) {
      gh(['issue', 'close', String(issue.number), '--comment', `${key} is no longer pinned in the repo.`]);
      closed++;
    }
  }

  const behind = results.filter(r => r.behind).length;
  console.log(`${results.length} pins checked, ${behind} behind: ${opened} opened, ${updated} updated, ${closed} closed`);
  if (errors.length) {
    // Lookups fail now and then (rate limits, a renamed repo); report but don't fail the run.
    console.log(`::warning::${errors.length} upstream lookups failed`);
    for (const e of errors) console.log('  ' + e);
  }
}

main();
