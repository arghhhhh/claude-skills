#!/usr/bin/env node
/* gen-image — zero-dependency CLI over image-generation APIs.
 * Providers: Google Gemini ("nano banana" models) and OpenAI (GPT Image models).
 *
 * Usage:
 *   node ~/.claude/skills/gen-image/gen-image.mjs "a glowing flower in a dark room" -o out.png
 *   node ~/.claude/skills/gen-image/gen-image.mjs -m gpt-image-2 -i photo.png -o out.png "edit prompt"
 *
 * Options:
 *   -o, --out <path>       Output file (default ./gen-image-<timestamp>.png)
 *   -m, --model <name>     Model id (default gemini-3-pro-image)
 *                          Gemini: gemini-3-pro-image, gemini-3.1-flash-image, gemini-2.5-flash-image
 *                          OpenAI: gpt-image-2, gpt-image-1 (provider inferred from model name)
 *   --ar <ratio>           Aspect ratio: 1:1, 16:9, 9:16, 4:3, 3:4, 21:9, ... (default 1:1)
 *                          OpenAI: mapped to nearest supported size (square/landscape/portrait)
 *   --size <1K|2K|4K>      Output resolution (Gemini pro models only; ignored elsewhere)
 *   --quality <q>          OpenAI only: low|medium|high|auto (default high)
 *   -i, --input <path>     Reference/edit image; repeatable (style refs, image editing)
 *   --mask <path>          OpenAI only: PNG mask — transparent areas mark the editable region
 *   --prompt-file <path>   Read the prompt from a file instead of argv
 *
 * API key resolution order (first hit wins), per provider:
 *   Gemini: GOOGLE_API_KEY env → GOOGLE_API_KEY= in .env (cwd upward) → ~/.claude/.google-api-key
 *   OpenAI: OPENAI_API_KEY env → OPENAI_API_KEY= in .env (cwd upward) → ~/.claude/.openai-api-key
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, extname, resolve, parse, basename } from 'node:path';
import { homedir } from 'node:os';

function fail(msg) { console.error('error: ' + msg); process.exit(1); }

function readEnvKey(envPath, varName) {
  for (const line of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const m = line.match(new RegExp(`^\\s*${varName}\\s*=\\s*(.+?)\\s*$`));
    if (m) return m[1].replace(/^["']|["']$/g, '');
  }
  return null;
}

function loadKey(varName, keyFileName) {
  if (process.env[varName]) return process.env[varName];
  let dir = process.cwd();
  while (true) {
    const envPath = join(dir, '.env');
    if (existsSync(envPath)) {
      const k = readEnvKey(envPath, varName);
      if (k) return k;
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const keyFile = join(homedir(), '.claude', keyFileName);
  if (existsSync(keyFile)) {
    const k = readFileSync(keyFile, 'utf8').trim();
    if (k) return k;
  }
  fail(`no API key found. Set ${varName} (env var), add it to a .env in the project, or write it to ~/.claude/${keyFileName}`);
}

// ---- args ----
const argv = process.argv.slice(2);
const opts = { model: 'gemini-3-pro-image', ar: '1:1', size: '2K', quality: 'high', inputs: [], mask: null, out: null, promptFile: null };
const positional = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => { if (++i >= argv.length) fail(`missing value for ${a}`); return argv[i]; };
  if (a === '-o' || a === '--out') opts.out = next();
  else if (a === '-m' || a === '--model') opts.model = next();
  else if (a === '--ar') opts.ar = next();
  else if (a === '--size') opts.size = next().toUpperCase();
  else if (a === '--quality') opts.quality = next().toLowerCase();
  else if (a === '-i' || a === '--input') opts.inputs.push(next());
  else if (a === '--mask') opts.mask = next();
  else if (a === '--prompt-file') opts.promptFile = next();
  else if (a === '-h' || a === '--help') { console.log(readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0] + '*/'); process.exit(0); }
  else positional.push(a);
}

const prompt = opts.promptFile ? readFileSync(opts.promptFile, 'utf8') : positional.join(' ');
if (!prompt.trim()) fail('no prompt given (pass it as an argument or via --prompt-file)');

const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp' };
const mimeOf = (p) => MIME[extname(p).toLowerCase()] ?? fail(`unsupported input image type: ${p}`);

const provider = /^(gpt-image|dall-e)/.test(opts.model) ? 'openai' : 'gemini';
let imageBuf;

if (provider === 'gemini') {
  imageBuf = await runGemini();
} else {
  imageBuf = await runOpenAI();
}

const out = opts.out ?? join(process.cwd(), 'gen-image-' + new Date().toISOString().replace(/[:.]/g, '-') + '.png');
if (dirname(out) !== parse(out).root) mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, imageBuf);
console.log(out);

// ---- Gemini ----
async function runGemini() {
  const parts = [];
  for (const p of opts.inputs) {
    parts.push({ inlineData: { mimeType: mimeOf(p), data: readFileSync(p).toString('base64') } });
  }
  parts.push({ text: prompt });

  const imageConfig = { aspectRatio: opts.ar };
  if (/gemini-3-pro-image|banana-pro/.test(opts.model)) imageConfig.imageSize = opts.size;

  const body = {
    contents: [{ parts }],
    generationConfig: { responseModalities: ['TEXT', 'IMAGE'], imageConfig },
  };

  const key = loadKey('GOOGLE_API_KEY', '.google-api-key');
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${opts.model}:generateContent`;

  console.error(`provider=gemini model=${opts.model} ar=${opts.ar}${imageConfig.imageSize ? ' size=' + imageConfig.imageSize : ''} inputs=${opts.inputs.length}`);
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
    body: JSON.stringify(body),
  });
  if (!res.ok) fail(`HTTP ${res.status}: ${(await res.text()).slice(0, 2000)}`);
  const json = await res.json();

  const outParts = json.candidates?.[0]?.content?.parts ?? [];
  const img = outParts.find((p) => p.inlineData);
  const txt = outParts.filter((p) => p.text).map((p) => p.text).join('\n');
  if (txt) console.error('model says: ' + txt.trim());
  if (!img) fail('no image in response: ' + JSON.stringify(json).slice(0, 1500));
  return Buffer.from(img.inlineData.data, 'base64');
}

// ---- OpenAI ----
function openaiSize(ar) {
  const m = ar.match(/^(\d+):(\d+)$/);
  if (!m) return 'auto';
  const r = Number(m[1]) / Number(m[2]);
  if (r > 1.15) return '1536x1024';
  if (r < 0.87) return '1024x1536';
  return '1024x1024';
}

async function runOpenAI() {
  const key = loadKey('OPENAI_API_KEY', '.openai-api-key');
  const size = openaiSize(opts.ar);
  const edit = opts.inputs.length > 0;
  const url = `https://api.openai.com/v1/images/${edit ? 'edits' : 'generations'}`;
  console.error(`provider=openai model=${opts.model} size=${size} quality=${opts.quality} inputs=${opts.inputs.length}${opts.mask ? ' mask=' + basename(opts.mask) : ''}`);

  let res;
  if (edit) {
    const form = new FormData();
    form.append('model', opts.model);
    form.append('prompt', prompt);
    form.append('size', size);
    form.append('quality', opts.quality);
    for (const p of opts.inputs) {
      form.append('image[]', new Blob([readFileSync(p)], { type: mimeOf(p) }), basename(p));
    }
    if (opts.mask) form.append('mask', new Blob([readFileSync(opts.mask)], { type: mimeOf(opts.mask) }), basename(opts.mask));
    res = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${key}` }, body: form });
  } else {
    res = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: opts.model, prompt, size, quality: opts.quality }),
    });
  }
  if (!res.ok) fail(`HTTP ${res.status}: ${(await res.text()).slice(0, 2000)}`);
  const json = await res.json();
  const d = json.data?.[0];
  if (d?.b64_json) return Buffer.from(d.b64_json, 'base64');
  if (d?.url) {
    const imgRes = await fetch(d.url);
    if (!imgRes.ok) fail(`image download failed: HTTP ${imgRes.status}`);
    return Buffer.from(await imgRes.arrayBuffer());
  }
  fail('no image in response: ' + JSON.stringify(json).slice(0, 1500));
}
