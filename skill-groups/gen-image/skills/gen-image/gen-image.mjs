#!/usr/bin/env node
/* gen-image — zero-dependency CLI over the Gemini image API ("nano banana" models).
 *
 * Usage:
 *   node ~/.claude/skills/gen-image/gen-image.mjs "a glowing flower in a dark room" -o out.png
 *
 * Options:
 *   -o, --out <path>       Output file (default ./gen-image-<timestamp>.png)
 *   -m, --model <name>     Model id (default gemini-3-pro-image)
 *                          Others: gemini-3.1-flash-image (faster/cheaper), gemini-2.5-flash-image
 *   --ar <ratio>           Aspect ratio: 1:1, 16:9, 9:16, 4:3, 3:4, 21:9, ... (default 1:1)
 *   --size <1K|2K|4K>      Output resolution (pro models only; default 2K)
 *   -i, --input <path>     Reference/edit image; repeatable (style refs, image editing)
 *   --prompt-file <path>   Read the prompt from a file instead of argv
 *
 * API key resolution order (first hit wins):
 *   1. GOOGLE_API_KEY environment variable
 *   2. GOOGLE_API_KEY= line in a .env file, searched from cwd upward to the filesystem root
 *   3. ~/.claude/.google-api-key (file containing just the key)
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join, extname, resolve, parse } from 'node:path';
import { homedir } from 'node:os';

function fail(msg) { console.error('error: ' + msg); process.exit(1); }

function readEnvKey(envPath) {
  for (const line of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*GOOGLE_API_KEY\s*=\s*(.+?)\s*$/);
    if (m) return m[1].replace(/^["']|["']$/g, '');
  }
  return null;
}

function loadKey() {
  if (process.env.GOOGLE_API_KEY) return process.env.GOOGLE_API_KEY;
  let dir = process.cwd();
  while (true) {
    const envPath = join(dir, '.env');
    if (existsSync(envPath)) {
      const k = readEnvKey(envPath);
      if (k) return k;
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const keyFile = join(homedir(), '.claude', '.google-api-key');
  if (existsSync(keyFile)) {
    const k = readFileSync(keyFile, 'utf8').trim();
    if (k) return k;
  }
  fail('no API key found. Set GOOGLE_API_KEY (env var), add it to a .env in the project, or write it to ~/.claude/.google-api-key');
}

// ---- args ----
const argv = process.argv.slice(2);
const opts = { model: 'gemini-3-pro-image', ar: '1:1', size: '2K', inputs: [], out: null, promptFile: null };
const positional = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => { if (++i >= argv.length) fail(`missing value for ${a}`); return argv[i]; };
  if (a === '-o' || a === '--out') opts.out = next();
  else if (a === '-m' || a === '--model') opts.model = next();
  else if (a === '--ar') opts.ar = next();
  else if (a === '--size') opts.size = next().toUpperCase();
  else if (a === '-i' || a === '--input') opts.inputs.push(next());
  else if (a === '--prompt-file') opts.promptFile = next();
  else if (a === '-h' || a === '--help') { console.log(readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0] + '*/'); process.exit(0); }
  else positional.push(a);
}

const prompt = opts.promptFile ? readFileSync(opts.promptFile, 'utf8') : positional.join(' ');
if (!prompt.trim()) fail('no prompt given (pass it as an argument or via --prompt-file)');

const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp' };

const parts = [];
for (const p of opts.inputs) {
  const mime = MIME[extname(p).toLowerCase()];
  if (!mime) fail(`unsupported input image type: ${p}`);
  parts.push({ inlineData: { mimeType: mime, data: readFileSync(p).toString('base64') } });
}
parts.push({ text: prompt });

const imageConfig = { aspectRatio: opts.ar };
if (/gemini-3-pro-image|banana-pro/.test(opts.model)) imageConfig.imageSize = opts.size;

const body = {
  contents: [{ parts }],
  generationConfig: { responseModalities: ['TEXT', 'IMAGE'], imageConfig },
};

const key = loadKey();
const url = `https://generativelanguage.googleapis.com/v1beta/models/${opts.model}:generateContent`;

console.error(`model=${opts.model} ar=${opts.ar}${imageConfig.imageSize ? ' size=' + imageConfig.imageSize : ''} inputs=${opts.inputs.length}`);
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

const out = opts.out ?? join(process.cwd(), 'gen-image-' + new Date().toISOString().replace(/[:.]/g, '-') + '.png');
if (dirname(out) !== parse(out).root) mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, Buffer.from(img.inlineData.data, 'base64'));
console.log(out);
