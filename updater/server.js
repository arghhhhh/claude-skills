#!/usr/bin/env node
// claude-skills updater — local web UI over install.sh.
//
//   node updater/server.js [--profile NAME] [--no-open]
//
// Serves updater/index.html on 127.0.0.1 (random port) and drives install.sh:
// --preview-update / --changelog for the "what's new" view, --update / install
// for Apply. When the repo is behind origin/main, the preview runs from a
// temporary `git worktree` of origin/main, so nothing is applied before Apply
// (authored skills are symlinks into the repo, so a pull IS an update for them).
//
// Every /api call needs the per-run token embedded in the page, and the Host
// header must be our own address: other local web pages can't drive it.
'use strict';

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn, execFileSync } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const TOKEN = crypto.randomBytes(16).toString('hex');
const argv = process.argv.slice(2);
const DEFAULT_PROFILE = argValue('--profile') || 'basic';
const NO_OPEN = argv.includes('--no-open');

function argValue(flag) {
  const i = argv.indexOf(flag);
  return i >= 0 ? argv[i + 1] : undefined;
}

// ─── Process helpers ────────────────────────────────────────────────────────

// Git Bash on Windows. Never plain `bash`: on Windows that can resolve to
// System32\bash.exe (WSL), which would run the installer against the distro.
function findBash() {
  if (process.platform !== 'win32') return 'bash';
  const cands = [];
  try {
    const gitExe = execFileSync('where', ['git'], { encoding: 'utf8' }).split(/\r?\n/)[0].trim();
    let d = path.dirname(gitExe); // ...\Git\cmd, ...\Git\bin or ...\Git\mingw64\bin
    for (let i = 0; i < 3; i++) { cands.push(path.join(d, 'bin', 'bash.exe')); d = path.dirname(d); }
  } catch (e) { /* git not on PATH; fall through to the usual locations */ }
  cands.push('C:\\Program Files\\Git\\bin\\bash.exe',
             'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
             path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Git', 'bin', 'bash.exe'));
  const hit = cands.find(c => fs.existsSync(c) && !/\\system32\\/i.test(c));
  if (!hit) throw new Error('Git Bash not found. Install Git for Windows.');
  return hit;
}
const BASH = findBash();

const fwd = p => p.replace(/\\/g, '/');

function run(cmd, args, { cwd = REPO, onLine } = {}) {
  return new Promise(resolve => {
    const child = spawn(cmd, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    let out = '', err = '', buf = '';
    const feed = chunk => {
      if (!onLine) return;
      buf += chunk;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) { onLine(buf.slice(0, i).replace(/\r$/, '')); buf = buf.slice(i + 1); }
    };
    child.stdout.on('data', d => { out += d; feed(String(d)); });
    child.stderr.on('data', d => { err += d; feed(String(d)); });
    child.on('error', e => resolve({ code: -1, out, err: err + e.message }));
    child.on('close', code => { if (onLine && buf) onLine(buf); resolve({ code, out, err }); });
  });
}

const git = (args, cwd = REPO) => run('git', args, { cwd });
const installSh = (args, dir = REPO, onLine) =>
  run(BASH, [fwd(path.join(dir, 'install.sh')), ...args], { cwd: dir, onLine });
const lines = s => s.replace(/\r/g, '').split('\n').filter(Boolean);

// ─── State ──────────────────────────────────────────────────────────────────

function readManifests(dir) {
  const out = {};
  const root = path.join(dir, 'skill-groups');
  for (const g of fs.existsSync(root) ? fs.readdirSync(root) : []) {
    const f = path.join(root, g, 'manifest.json');
    if (!fs.existsSync(f)) continue;
    try { out[g] = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { out[g] = { description: '(invalid manifest.json)' }; }
  }
  return out;
}

function readProfiles(dir) {
  const root = path.join(dir, 'profiles');
  const out = {};
  for (const f of fs.existsSync(root) ? fs.readdirSync(root).filter(f => f.endsWith('.json')) : []) {
    try { const p = JSON.parse(fs.readFileSync(path.join(root, f), 'utf8')); out[p.name || f.slice(0, -5)] = p; } catch (e) { /* skip */ }
  }
  return out;
}

async function computeState() {
  const fetch = await git(['fetch', '--quiet', 'origin']);
  const rev = async args => (await git(args)).out.trim();
  const head = await rev(['rev-parse', 'HEAD']);
  const remote = await rev(['rev-parse', '--verify', '-q', 'origin/main']);
  const behind = remote ? Number(await rev(['rev-list', '--count', 'HEAD..origin/main'])) : 0;
  const ahead = remote ? Number(await rev(['rev-list', '--count', 'origin/main..HEAD'])) : 0;
  const dirty = lines((await git(['status', '--porcelain', '--untracked-files=no'])).out);

  let previewDir = REPO, worktree = null;
  if (behind > 0) {
    await git(['worktree', 'prune']);
    worktree = path.join(os.tmpdir(), 'claude-skills-preview-' + crypto.randomBytes(4).toString('hex'));
    const wt = await git(['worktree', 'add', '--detach', worktree, 'origin/main']);
    if (wt.code !== 0) throw new Error('git worktree add failed: ' + wt.err.trim());
    previewDir = worktree;
  }

  try {
    const [preview, changelog] = await Promise.all([
      installSh(['--preview-update'], previewDir),
      installSh(['--changelog', '--to', remote ? 'origin/main' : 'HEAD'], previewDir),
    ]);
    const now = readManifests(REPO), next = readManifests(previewDir);
    const profiles = readProfiles(previewDir);

    const groups = {};
    const G = name => groups[name] || (groups[name] = {
      name, installed: false, isNew: false, newItems: [], newEnv: [], commits: [], noRev: false,
    });
    const migrations = [];
    for (const l of lines(preview.out)) {
      let m;
      if ((m = l.match(/^UPDATE (\S+)$/))) G(m[1]).installed = true;
      else if ((m = l.match(/^NEW-ITEM (\S+) (\S+) (\S+)$/))) { G(m[1]).installed = true; G(m[1]).newItems.push({ kind: m[2], name: m[3] }); }
      else if ((m = l.match(/^NEW-ENV (\S+) (\S+)$/))) { G(m[1]).installed = true; G(m[1]).newEnv.push(m[2]); }
      else if ((m = l.match(/^NEW-GROUP (\S+)$/))) G(m[1]).isNew = true;
      else if ((m = l.match(/^MIGRATION (\S+) ?(.*)$/))) {
        const file = (fs.readdirSync(path.join(previewDir, 'migrations')).find(f => f.startsWith(m[1] + '-')) || '');
        migrations.push({ id: m[1], title: m[2], file: fwd(path.join(REPO, 'migrations', file)) });
      }
    }
    const installer = { commits: [], noRev: false };
    for (const l of lines(changelog.out)) {
      let m;
      if ((m = l.match(/^LOG (\S+) (\S+) (.*)$/))) (m[1] === '_installer' ? installer : G(m[1])).commits.push({ sha: m[2], subject: m[3] });
      else if ((m = l.match(/^NO-REV (\S+)$/))) (m[1] === '_installer' ? installer : G(m[1])).noRev = true;
    }

    // Commits the pull would bring in, attributed to groups by path. Covers
    // groups with no recorded rev yet, and is a subset of --changelog otherwise.
    if (behind > 0) {
      const log = await git(['log', '--format=@@%h %s', '--name-only', 'HEAD..origin/main']);
      const incoming = {}; // owner -> Map(sha -> commit)
      let cur = null;
      for (const l of lines(log.out)) {
        if (l.startsWith('@@')) { const sp = l.indexOf(' '); cur = { sha: l.slice(2, sp), subject: l.slice(sp + 1) }; continue; }
        if (!cur) continue;
        const m = l.match(/^skill-groups\/([^/]+)\//) || l.match(/^shared\/claude-md\/([^/]+)\.md$/);
        const owner = m ? m[1] : /^(install\.sh$|shared\/|scripts\/|profiles\/|migrations\/)/.test(l) ? '_installer' : null;
        if (owner) (incoming[owner] = incoming[owner] || new Map()).set(cur.sha, cur);
      }
      for (const [owner, commits] of Object.entries(incoming)) {
        const target = owner === '_installer' ? installer : G(owner);
        const have = new Set(target.commits.map(c => c.sha));
        for (const c of commits.values()) if (!have.has(c.sha)) target.commits.push(c);
      }
    }

    for (const name of Object.keys(next)) G(name);
    for (const g of Object.values(groups)) {
      const mNext = next[g.name] || {}, mNow = now[g.name] || {};
      g.description = mNext.description || mNow.description || '';
      g.versionNow = mNow.version || null;
      g.versionNext = mNext.version || null;
      g.type = mNext.type || 'authored';
      g.removed = !next[g.name];
      g.changed = g.installed && (g.commits.length > 0 || g.versionNow !== g.versionNext || g.newItems.length > 0 || g.newEnv.length > 0);
      g.needsLook = g.newItems.length > 0 || g.newEnv.length > 0;
    }

    return {
      repo: fwd(REPO), head: head.slice(0, 7), remote: remote.slice(0, 7), behind, ahead, dirty,
      fetchError: fetch.code !== 0 ? (fetch.err.trim() || 'git fetch failed') : null,
      previewError: preview.code !== 0 ? preview.err.trim().split('\n').slice(-3).join('\n') : null,
      groups: Object.values(groups).filter(g => !g.removed).sort((a, b) => a.name.localeCompare(b.name)),
      installer, migrations, profiles, defaultProfile: profiles[DEFAULT_PROFILE] ? DEFAULT_PROFILE : Object.keys(profiles)[0] || null,
      busy: !!(job && !job.done),
    };
  } finally {
    if (worktree) await git(['worktree', 'remove', '--force', worktree]);
  }
}

// ─── Apply job ──────────────────────────────────────────────────────────────

let job = null; // { lines, done, code, failed }

function startApply({ update = [], install = [] }) {
  const valid = new Set(Object.keys(readManifests(REPO)));
  const clean = list => (Array.isArray(list) ? list : []).filter(g => typeof g === 'string' && /^[a-z0-9-]+$/.test(g));
  update = clean(update); install = clean(install);
  job = { lines: [], done: false, code: 0, failed: false };
  const log = l => job.lines.push(l);
  const step = async (title, fn) => {
    log('');
    log('━━ ' + title);
    const r = await fn();
    if (r.code !== 0) { job.failed = true; job.code = r.code; log('✗ exited with code ' + r.code); }
    return r.code === 0;
  };

  (async () => {
    try {
      const behind = Number((await git(['rev-list', '--count', 'HEAD..origin/main'])).out.trim() || 0);
      if (behind > 0) {
        const ok = await step('git pull --ff-only origin main', () =>
          run('git', ['pull', '--ff-only', 'origin', 'main'], { onLine: log }));
        if (!ok) return;
      }
      const known = readManifests(REPO); // post-pull: groups to install may have just arrived
      const bad = [...update, ...install].filter(g => !known[g] && !valid.has(g));
      if (bad.length) { log('✗ unknown group(s): ' + bad.join(', ')); job.failed = true; return; }
      if (update.length) {
        await step('install.sh --update --yes --skills ' + update.join(','), () =>
          installSh(['--update', '--yes', '--skills', update.join(',')], REPO, log));
      }
      if (install.length) {
        await step('install.sh --skills ' + install.join(',') + ' --yes', () =>
          installSh(['--skills', install.join(','), '--yes'], REPO, log));
      }
      if (job.lines.some(l => /^✗ /.test(l))) job.failed = true;
      log('');
      log(job.failed ? '━━ Finished with errors' : '━━ Done. Restart Claude Code to pick up changes.');
    } catch (e) {
      job.failed = true; log('✗ ' + e.message);
    } finally {
      job.done = true;
    }
  })();
}

// ─── Launching an agent ─────────────────────────────────────────────────────

function agentPrompt(kind, id, state) {
  if (kind === 'update') {
    return 'update claude-skills. The claude-skills updater GUI recommended an agent for this one; ' +
           'follow the "Updating claude-skills" procedure in the skill-repo-maintenance skill.';
  }
  if (kind === 'fix') {
    return 'update claude-skills. The claude-skills updater GUI ran the update and it finished with errors; ' +
           'run bash ' + fwd(path.join(REPO, 'install.sh')) + ' --verify, find what failed and fix it.';
  }
  if (kind === 'migration') {
    const m = (state && state.migrations || []).find(x => x.id === id);
    if (!m) return null;
    return 'Apply claude-skills migration ' + m.id + ': read ' + m.file + ' and follow it, then run: bash ' +
           fwd(path.join(REPO, 'install.sh')) + ' --mark-migration ' + m.id;
  }
  return null;
}

// Opens a new terminal running `claude "<prompt>"` in the home directory.
function launchTerminal(prompt) {
  const home = os.homedir();
  if (process.platform === 'win32') {
    // A .ps1 avoids cmd/PowerShell double-quoting. -File still loads the
    // profile, so the claude-skills `claude` wrapper applies.
    const ps1 = path.join(os.tmpdir(), 'claude-skills-agent-' + crypto.randomBytes(4).toString('hex') + '.ps1');
    const q = s => "'" + s.replace(/'/g, "''") + "'";
    fs.writeFileSync(ps1, '\ufeffSet-Location ' + q(home) + '\r\nclaude ' + q(prompt) + '\r\n', 'utf8');
    spawn('cmd.exe', ['/c', 'start', '', 'powershell.exe', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', ps1],
      { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    return true;
  }
  const sh = "cd ~ && claude '" + prompt.replace(/'/g, "'\\''") + "'";
  if (process.platform === 'darwin') {
    const as = 'tell application "Terminal" to do script "' + sh.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
    spawn('osascript', ['-e', as, '-e', 'tell application "Terminal" to activate'], { detached: true, stdio: 'ignore' }).unref();
    return true;
  }
  for (const term of ['x-terminal-emulator', 'gnome-terminal', 'konsole', 'xterm']) {
    try {
      execFileSync('sh', ['-c', 'command -v ' + term], { stdio: 'ignore' });
      const args = term === 'gnome-terminal' ? ['--', 'bash', '-lc', sh + '; exec bash'] : ['-e', 'bash', '-lc', sh + '; exec bash'];
      spawn(term, args, { detached: true, stdio: 'ignore' }).unref();
      return true;
    } catch (e) { /* try the next one */ }
  }
  return false;
}

// ─── HTTP ───────────────────────────────────────────────────────────────────

let lastState = null;
let statePromise = null;
let port = 0;

function send(res, code, body, type = 'application/json') {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
}

function readBody(req) {
  return new Promise(resolve => {
    let s = '';
    req.on('data', d => { s += d; if (s.length > 1e5) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(s || '{}')); } catch (e) { resolve({}); } });
  });
}

const server = http.createServer(async (req, res) => {
  if (req.headers.host !== '127.0.0.1:' + port) return send(res, 403, { error: 'bad host' });
  const url = new URL(req.url, 'http://127.0.0.1');

  if (req.method === 'GET' && url.pathname === '/') {
    const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8').replace('__TOKEN__', TOKEN);
    return send(res, 200, html, 'text/html; charset=utf-8');
  }
  if (!url.pathname.startsWith('/api/')) return send(res, 404, { error: 'not found' });
  if (req.headers['x-token'] !== TOKEN) return send(res, 403, { error: 'bad token' });

  try {
    if (req.method === 'GET' && url.pathname === '/api/state') {
      if (job && !job.done) return send(res, 409, { error: 'an update is running' });
      if (!statePromise) statePromise = computeState().finally(() => { statePromise = null; });
      lastState = await statePromise;
      return send(res, 200, lastState);
    }
    if (req.method === 'POST' && url.pathname === '/api/apply') {
      if (job && !job.done) return send(res, 409, { error: 'an update is already running' });
      if (lastState && lastState.dirty.length && lastState.behind > 0) {
        return send(res, 409, { error: 'The repo has uncommitted changes, so it can\'t be pulled.' });
      }
      startApply(await readBody(req));
      return send(res, 200, { started: true });
    }
    if (req.method === 'GET' && url.pathname === '/api/job') {
      if (!job) return send(res, 200, { lines: [], done: true, failed: false });
      const since = Number(url.searchParams.get('since') || 0);
      return send(res, 200, { lines: job.lines.slice(since), total: job.lines.length, done: job.done, failed: job.failed });
    }
    if (req.method === 'POST' && url.pathname === '/api/launch') {
      const { kind, id } = await readBody(req);
      const prompt = agentPrompt(kind, id, lastState);
      if (!prompt) return send(res, 400, { error: 'unknown agent task' });
      const command = 'claude "' + prompt.replace(/"/g, '\\"') + '"';
      let launched = false;
      try { launched = launchTerminal(prompt); } catch (e) { /* report as not launched */ }
      return send(res, 200, { launched, command });
    }
    if (req.method === 'POST' && url.pathname === '/api/quit') {
      send(res, 200, { bye: true });
      setTimeout(() => process.exit(0), 100);
      return;
    }
    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, 500, { error: e.message });
  }
});

server.listen(0, '127.0.0.1', () => {
  port = server.address().port;
  const url = 'http://127.0.0.1:' + port + '/';
  console.log('claude-skills updater: ' + url);
  console.log('Ctrl+C (or "Close" in the page) to stop.');
  if (NO_OPEN) return;
  const opener = process.platform === 'win32' ? ['cmd.exe', ['/c', 'start', '', url]]
    : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  spawn(opener[0], opener[1], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
});
