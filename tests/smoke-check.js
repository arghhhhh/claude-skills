#!/usr/bin/env node
// smoke-check.js — Quick cross-platform test runner (Node.js, no bash required).
// Covers the critical checks from all bash test suites.
// Run: node tests/smoke-check.js
// From repo root or tests/ directory.
'use strict';

const fs = require('fs');
const path = require('path');

// Resolve repo root relative to this script
const TESTS_DIR = __dirname.endsWith('tests') ? __dirname : path.join(__dirname, 'tests');
const REPO = path.dirname(TESTS_DIR);
const SKILL_GROUPS = path.join(REPO, 'skill-groups');
const SHARED = path.join(REPO, 'shared');

let pass = 0, fail = 0;
const ok  = msg => { console.log('  pass: ' + msg); pass++; };
const err = msg => { console.log('  FAIL: ' + msg); fail++; };

const groups = fs.readdirSync(SKILL_GROUPS).filter(g =>
  fs.existsSync(path.join(SKILL_GROUPS, g, 'manifest.json'))
);

// ─── test-manifest-contracts ────────────────────────────────────────────────
console.log('\n=== test-manifest-contracts === (' + groups.length + ' groups)');

const VALID_TYPES   = ['authored', 'vendored', 'tool-only'];
const BAD_BRANCHES  = ['main','master','develop','HEAD','trunk','dev'];

for (const group of groups) {
  const mf = path.join(SKILL_GROUPS, group, 'manifest.json');
  let m;
  try { m = JSON.parse(fs.readFileSync(mf, 'utf8')); }
  catch(e) { err(group + ': invalid JSON — ' + e.message); continue; }

  const gtype = m.type || 'authored';

  if (!m.name)        err(group + ': missing name');        else ok(group + ': name');
  if (!m.version)     err(group + ': missing version');
  else if (/^\d+\.\d+\.\d+$/.test(m.version)) ok(group + ': version=' + m.version);
  else err(group + ': invalid semver: ' + m.version);
  if (!VALID_TYPES.includes(gtype)) err(group + ': invalid type: ' + gtype); else ok(group + ': type=' + gtype);
  if (!m.install)     err(group + ': missing install block'); else ok(group + ': has install');
  if (!m.test)        err(group + ': missing test block');   else ok(group + ': has test');
  if (!m.description) err(group + ': missing description');  else ok(group + ': has description');

  if (gtype === 'vendored') {
    const src = m.source || {};
    if (!src.repo) err(group + ': vendored missing source.repo'); else ok(group + ': source.repo=' + src.repo);
    if (!src.ref)  err(group + ': vendored missing source.ref');
    else if (BAD_BRANCHES.includes(src.ref)) err(group + ': source.ref is branch name: ' + src.ref);
    else ok(group + ': source.ref=' + src.ref.slice(0, 12) + '…');
    if (!src.paths || !src.paths.skills) err(group + ': vendored missing source.paths.skills');
    else ok(group + ': source.paths.skills=' + src.paths.skills);
  }

  if (gtype === 'tool-only') {
    if (!(m.test || {}).command) err(group + ': tool-only missing test.command (verify depends on it)');
    else ok(group + ': tool-only has test.command');
  }

  // install.check=false + no test.command = verify-broken
  const installCheck = (m.install || {}).check || '';
  const testCmd      = (m.test    || {}).command || '';
  if (installCheck === 'false' && !testCmd) {
    err(group + ': install.check=false but test.command missing — verify always fails');
  }
}

// ─── test-discovery ─────────────────────────────────────────────────────────
console.log('\n=== test-discovery ===');

for (const group of groups) {
  const mf    = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m     = JSON.parse(fs.readFileSync(mf, 'utf8'));
  const gtype = m.type || 'authored';
  if (gtype !== 'authored') continue;

  for (const skill of (m.skills || [])) {
    const base = path.join(SKILL_GROUPS, group, 'skills', skill);
    if (fs.existsSync(base) || fs.existsSync(base + '.md')) ok(group + '/' + skill + ': exists');
    else err(group + '/' + skill + ': skill file missing at ' + base);
  }
  for (const agent of (m.agents || [])) {
    const ap = path.join(SKILL_GROUPS, group, 'agents', agent + '.md');
    if (fs.existsSync(ap)) ok(group + '/agents/' + agent + '.md: exists');
    else err(group + '/agents/' + agent + '.md: missing');
  }
}

// CLAUDE.md snippet existence
for (const group of groups) {
  const snippet = path.join(SHARED, 'claude-md', group + '.md');
  const mf = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m = JSON.parse(fs.readFileSync(mf, 'utf8'));
  if (fs.existsSync(snippet)) {
    const content = fs.readFileSync(snippet, 'utf8');
    if (content.trim().length < 20) err(group + ': claude-md snippet is suspiciously short');
    else ok(group + ': claude-md snippet present (' + content.length + ' bytes)');
  } else {
    // OK only if manifest has name+description for auto-gen
    if (m.name && m.description) ok(group + ': no snippet — auto-gen eligible (name+description present)');
    else err(group + ': no snippet and manifest lacks name or description');
  }
}

// ─── test-skill-reuse ───────────────────────────────────────────────────────
console.log('\n=== test-skill-reuse ===');

const skillOwners = {};
for (const group of groups) {
  const mf = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m  = JSON.parse(fs.readFileSync(mf, 'utf8'));
  for (const skill of (m.skills || [])) {
    if (skillOwners[skill]) err('DUPLICATE skill ' + skill + ': in ' + skillOwners[skill] + ' and ' + group);
    else { skillOwners[skill] = group; ok('skill ' + skill + ' uniquely in ' + group); }
  }
}

// No orphaned skill files
for (const group of groups) {
  const mf    = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m     = JSON.parse(fs.readFileSync(mf, 'utf8'));
  const gtype = m.type || 'authored';
  if (gtype !== 'authored') continue;

  const skillsDir = path.join(SKILL_GROUPS, group, 'skills');
  if (!fs.existsSync(skillsDir)) continue;

  const declared = new Set(m.skills || []);
  for (const item of fs.readdirSync(skillsDir)) {
    const name = item.endsWith('.md') ? item.slice(0, -3) : item;
    if (declared.has(name)) ok(group + '/' + name + ': declared in manifest');
    else err(group + '/' + name + ': file exists in skills/ but NOT declared in manifest');
  }
}

// shared/claude-md snippets reference known groups
const claudeMdDir = path.join(SHARED, 'claude-md');
if (fs.existsSync(claudeMdDir)) {
  for (const f of fs.readdirSync(claudeMdDir)) {
    if (!f.endsWith('.md')) continue;
    const groupName = f.slice(0, -3);
    if (fs.existsSync(path.join(SKILL_GROUPS, groupName))) ok('claude-md/' + f + ' matches group');
    else err('claude-md/' + f + ' has no group in skill-groups/ (orphaned snippet)');
  }
}

// ─── test-unsupported-targets ───────────────────────────────────────────────
console.log('\n=== test-unsupported-targets ===');

for (const group of groups) {
  const mf    = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m     = JSON.parse(fs.readFileSync(mf, 'utf8'));
  const gtype = m.type || 'authored';

  if (gtype === 'vendored') {
    const ref = (m.source || {}).ref || '';
    if (!ref)                  err(group + ': vendored missing source.ref');
    else if (BAD_BRANCHES.includes(ref)) err(group + ': source.ref is bare branch name: ' + ref);
    else ok(group + ': source.ref is not a bare branch name');
  }

  const methods = (m.install || {}).methods || [];
  for (const method of methods) {
    for (const p of (method.platforms || [])) {
      if (['macos','linux','windows'].includes(p)) ok(group + ': platform ' + p + ' valid');
      else err(group + ': invalid platform value: ' + p);
    }
    if (!method.command && !method.url) {
      err(group + ': install method "' + (method.name||'?') + '" has neither command nor url');
    }
  }

  // prereq.required must be boolean. Prereqs may be plain strings (documentation
  // form, e.g. capcut-cli/ghidra/ilspy) — the installer's json_prerequisites
  // skips those (no .name), so only object-form prereqs are checked here.
  for (const prereq of (m.prerequisites || [])) {
    if (typeof prereq !== 'object' || prereq === null) continue;
    if ('required' in prereq && typeof prereq.required !== 'boolean') {
      err(group + ': prereq.' + prereq.name + '.required is ' + typeof prereq.required + ' (must be boolean)');
    }
  }
}

// ─── test-idempotency: overlay mapping ──────────────────────────────────────
console.log('\n=== test-idempotency (overlay mapping) ===');

for (const group of groups) {
  const mf    = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m     = JSON.parse(fs.readFileSync(mf, 'utf8'));
  const gtype = m.type || 'authored';
  if (gtype !== 'vendored') continue;

  for (const sk of Object.keys((m.overlays || {}).skills || {})) {
    const op = path.join(SKILL_GROUPS, group, 'overlays', 'skills', sk);
    if (fs.existsSync(op) || fs.existsSync(op + '.md')) ok(group + ': overlay ' + sk + ' has file');
    else err(group + ': overlay ' + sk + ' declared in manifest but file missing');
  }
  for (const ag of Object.keys((m.overlays || {}).agents || {})) {
    const op = path.join(SKILL_GROUPS, group, 'overlays', 'agents', ag);
    if (fs.existsSync(op)) ok(group + ': agent overlay ' + ag + ' exists');
    else err(group + ': agent overlay ' + ag + ' declared but missing');
  }

  // update_policy check: tool-only groups that reference this repo need "latest"
  const gtype2 = m.type || 'authored';
  if (gtype2 === 'tool-only') {
    const methods = (m.install || {}).methods || [];
    const cmd = methods.length ? (methods[0].command || '') : '';
    const policy = m.update_policy || 'pinned';
    const refsRepo = /skill-repos\/claude-skills|{{REPO}}/.test(cmd);
    if (refsRepo && policy !== 'latest') {
      err(group + ': tool-only install references this repo but update_policy="' + policy + '" (should be "latest")');
    }
  }
}

// ─── test-mcp-parity ────────────────────────────────────────────────────────
console.log('\n=== test-mcp-parity ===');

const configExample = path.join(REPO, 'config.example.sh');
const configContent = fs.existsSync(configExample) ? fs.readFileSync(configExample, 'utf8') : '';

for (const group of groups) {
  const mf = path.join(SKILL_GROUPS, group, 'manifest.json');
  const m  = JSON.parse(fs.readFileSync(mf, 'utf8'));
  if (!m.mcp_servers) continue;

  for (const [server, cfg] of Object.entries(m.mcp_servers)) {
    if (!cfg.command) err(group + '/' + server + ': mcp_servers entry missing command');
    else ok(group + '/' + server + ': mcp_servers has command=' + cfg.command);

    if (cfg.args !== undefined && !Array.isArray(cfg.args)) {
      err(group + '/' + server + ': mcp_servers.args must be an array');
    } else {
      ok(group + '/' + server + ': args type ok');
    }

    // Check {{PLACEHOLDER}} variables are in config.example.sh
    const serverJson = JSON.stringify(cfg);
    const placeholders = [...serverJson.matchAll(/\{\{([A-Z_]+)\}\}/g)].map(m => m[1]);
    for (const ph of placeholders) {
      if (configContent.includes(ph)) ok(group + ': {{' + ph + '}} documented in config.example.sh');
      else err(group + ': {{' + ph + '}} used in mcp_servers but not in config.example.sh');
    }
  }
}

// ─── FINAL RESULTS ──────────────────────────────────────────────────────────
console.log('\n=== FINAL RESULTS ===');
console.log(pass + ' passed, ' + fail + ' failed');

if (fail > 0) {
  console.log('\nSome checks failed. Review output above for details.');
  process.exit(1);
}
