#!/usr/bin/env node
// Compare each manifest's upstream pins with the latest upstream versions.
//
//   node scripts/check-upstream.js [--json] [--group NAME]
//   node scripts/check-upstream.js --latest TYPE KEY=VALUE...   (look up one source)
//
// Manifest field (see "Pinning upstream tools" in the skill-repo-maintenance skill):
//   "upstream": {
//     "<tool>": { "type": "npm", "package": "capcut-cli", "pin": "1.4.0" }
//   }
// Types: github-release {repo}, git {url, branch?}, npm {package, registry?},
// pypi {package}, jsr {package}, winget {id}.
// "installs": false marks a tool the installer doesn't install itself; it is
// tracked only so the skill text gets reviewed when the tool changes.
//
// Exit code 0 whether or not anything is behind; 1 only when the script fails.
// Set GITHUB_TOKEN to lift GitHub's 60-requests-an-hour anonymous limit.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const GROUPS = path.join(REPO, 'skill-groups');

async function getJson(url, headers = {}) {
  const res = await fetch(url, { headers: { 'user-agent': 'claude-skills-upstream-check', ...headers } });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

function ghHeaders() {
  const h = { accept: 'application/vnd.github+json' };
  if (process.env.GITHUB_TOKEN) h.authorization = 'Bearer ' + process.env.GITHUB_TOKEN;
  return h;
}

// Numeric-aware version compare: "1.10.0" > "1.9.2", "v2" == "2".
function cmpVersion(a, b) {
  const pa = String(a).replace(/^v/i, '').split(/[.\-+_]/);
  const pb = String(b).replace(/^v/i, '').split(/[.\-+_]/);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] ?? '', y = pb[i] ?? '';
    const nx = /^\d+$/.test(x), ny = /^\d+$/.test(y);
    if (nx && ny) { if (+x !== +y) return +x - +y; continue; }
    if (x === y) continue;
    if (x === '') return 1;  // 1.0 > 1.0-rc1
    if (y === '') return -1;
    return x < y ? -1 : 1;
  }
  return 0;
}

const resolvers = {
  async 'github-release'(e) {
    const r = await getJson(`https://api.github.com/repos/${e.repo}/releases/latest`, ghHeaders());
    return { latest: r.tag_name, url: r.html_url };
  },
  async git(e) {
    const ref = e.branch ? `refs/heads/${e.branch}` : 'HEAD';
    const out = execFileSync('git', ['ls-remote', e.url, ref], { encoding: 'utf8', timeout: 60000 });
    const sha = out.split(/\s+/)[0];
    if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error(`git ls-remote ${e.url} ${ref}: no ref`);
    const gh = e.url.match(/github\.com\/([^/]+\/[^/.]+)/);
    return { latest: sha, url: gh ? `https://github.com/${gh[1]}/compare/${e.pin}...${sha}` : e.url };
  },
  async npm(e) {
    const reg = (e.registry || 'https://registry.npmjs.org').replace(/\/$/, '');
    const r = await getJson(`${reg}/${e.package.replace('/', '%2f')}`);
    if (!e.registry) return { latest: r['dist-tags'].latest, url: `https://www.npmjs.com/package/${e.package}` };
    // Other registries (Unity's) don't keep dist-tags.latest current: take the highest stable version.
    const stable = Object.keys(r.versions).filter(v => /^\d+(\.\d+)*$/.test(v)).sort(cmpVersion);
    return { latest: stable[stable.length - 1], url: `${reg}/${e.package}` };
  },
  async pypi(e) {
    const r = await getJson(`https://pypi.org/pypi/${e.package}/json`);
    return { latest: r.info.version, url: `https://pypi.org/project/${e.package}/#history` };
  },
  async jsr(e) {
    const r = await getJson(`https://jsr.io/${e.package}/meta.json`);
    return { latest: r.latest, url: `https://jsr.io/${e.package}` };
  },
  async winget(e) {
    const dir = `manifests/${e.id[0].toLowerCase()}/${e.id.replace(/\./g, '/')}`;
    const r = await getJson(`https://api.github.com/repos/microsoft/winget-pkgs/contents/${dir}`, ghHeaders());
    // Version folders only; a package id can also have sub-package folders (e.g. ".Beta").
    const vers = r.filter(x => x.type === 'dir' && /^\d/.test(x.name)).map(x => x.name).sort(cmpVersion);
    if (!vers.length) throw new Error(`winget ${e.id}: no versions`);
    return { latest: vers[vers.length - 1], url: `https://github.com/microsoft/winget-pkgs/tree/master/${dir}` };
  },
};

function isBehind(e, latest) {
  if (e.type === 'git') return !latest.startsWith(e.pin) && !e.pin.startsWith(latest);
  return cmpVersion(latest, e.pin) > 0;
}

// Every pin: each manifest's "upstream", each vendored group's source.ref (as
// tool "source"), and installer-wide tools in shared/upstream.json (group "_installer").
function loadEntries(only) {
  const entries = [];
  if (!only || only === '_installer') {
    const shared = JSON.parse(fs.readFileSync(path.join(REPO, 'shared', 'upstream.json'), 'utf8'));
    for (const [tool, e] of Object.entries(shared)) entries.push({ group: '_installer', tool, ...e });
  }
  for (const g of fs.readdirSync(GROUPS).sort()) {
    if (only && g !== only) continue;
    const f = path.join(GROUPS, g, 'manifest.json');
    if (!fs.existsSync(f)) continue;
    const m = JSON.parse(fs.readFileSync(f, 'utf8'));
    for (const [tool, e] of Object.entries(m.upstream || {})) entries.push({ group: g, tool, ...e });
    if (m.type === 'vendored' && m.source && m.source.repo) {
      const branch = String(m.source.ref_name || '').split('@')[0] || undefined;
      entries.push({
        group: g, tool: 'source', type: 'git', url: `https://github.com/${m.source.repo}.git`,
        branch, pin: m.source.ref, note: 'Vendored skills: bump source.ref, then re-check overlays and the skills allow-list.',
      });
    }
  }
  return entries;
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--latest') {
    const e = { type: args[1] };
    for (const kv of args.slice(2)) { const i = kv.indexOf('='); e[kv.slice(0, i)] = kv.slice(i + 1); }
    const r = await resolvers[e.type](e);
    console.log(r.latest);
    return;
  }
  const json = args.includes('--json');
  const gi = args.indexOf('--group');
  const entries = loadEntries(gi >= 0 ? args[gi + 1] : null);

  // A few at a time: GitHub's API dislikes bursts.
  const results = [];
  for (let i = 0; i < entries.length; i += 6) {
    results.push(...await Promise.all(entries.slice(i, i + 6).map(async e => {
      const fn = resolvers[e.type];
      if (!fn) return { ...e, error: `unknown type ${e.type}` };
      try {
        const r = await fn(e);
        return { ...e, latest: r.latest, url: r.url, behind: isBehind(e, r.latest) };
      } catch (err) {
        return { ...e, error: err.message };
      }
    })));
  }

  if (json) { console.log(JSON.stringify(results, null, 2)); return; }
  for (const r of results) {
    const id = `${r.group}/${r.tool}`;
    if (r.error) console.log(`ERROR   ${id}  ${r.error}`);
    else if (r.behind) console.log(`BEHIND  ${id}  ${r.pin} -> ${r.latest}  ${r.url}`);
    else console.log(`OK      ${id}  ${r.pin}`);
  }
}

module.exports = { cmpVersion, resolvers };
if (require.main === module) main().catch(e => { console.error(e.message); process.exit(1); });
