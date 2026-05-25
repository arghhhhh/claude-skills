#!/usr/bin/env node
// notch-node-info.js — fetch and parse a Notch node doc page.
//
// Usage:
//   node notch-node-info.js <node-name-or-substring>     # search index, fetch best match
//   node notch-node-info.js --url <full-url>             # fetch arbitrary URL
//   node notch-node-info.js --list                       # list every node in index
//   node notch-node-info.js --grep <pattern>             # search index by name
//
// Output is structured text the agent can read to learn a node's:
//   - inferred CreateNode("Group::Name") string
//   - every property grouped by category (Transform, Attributes, Time, ...)
//   - input connectors with typical input types
//
// The Category.PropertyName naming convention is the one Notch JS uses:
//   node.SetFloat("Attributes.Brightness", 1.0);

const fs = require('fs');
const path = require('path');
const https = require('https');

const INDEX_PATH = path.join(__dirname, 'notch-node-index.json');

function loadIndex() {
    if (!fs.existsSync(INDEX_PATH)) {
        console.error('Missing ' + INDEX_PATH + '. Re-extract from _home.html.');
        process.exit(1);
    }
    return JSON.parse(fs.readFileSync(INDEX_PATH, 'utf8'));
}

function fetch(url) {
    return new Promise((resolve, reject) => {
        https.get(url, res => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                return resolve(fetch(res.headers.location));
            }
            if (res.statusCode !== 200) return reject(new Error('HTTP ' + res.statusCode));
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => resolve(data));
        }).on('error', reject);
    });
}

function htmlToText(html) {
    let body = html
        .replace(/<script[\s\S]*?<\/script>/g, '')
        .replace(/<style[\s\S]*?<\/style>/g, '')
        .replace(/<\/(p|li|tr|h[1-6])>/g, '\n')
        .replace(/<br\s*\/?>/g, '\n')
        .replace(/<(th|td)[^>]*>/g, ' | ')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&#39;/g, "'").replace(/&quot;/g, '"')
        .replace(/&rsquo;/g, "'").replace(/&ldquo;/g, '"').replace(/&rdquo;/g, '"')
        .replace(/&#8227;/g, '>')
        .replace(/\n{3,}/g, '\n\n')
        .replace(/[ \t]+/g, ' ');
    return body;
}

function extractArticle(html) {
    // The article content sits late in the file, after big nav HTML.
    // The "Updated:" line marks the start of the actual article.
    const text = htmlToText(html);
    const idx = text.indexOf('Updated:');
    if (idx < 0) return text;
    return text.slice(idx);
}

function parseProperties(article) {
    // Split into "category" sections. The doc structure is:
    //   <section heading>
    //   These properties control ...
    //   | | Parameter | Details
    //   | <PropName> | <description>
    //   ...
    // We capture each section heading and the property names that follow it.
    // Categories are ARBITRARY per node: Transform/Attributes/Time/Parent Transform
    // are common, but also Colours (Colour Ramp), Rendering (Gradient), BSDF/BRDF
    // (materials), Lines, FX, Misc, Shader. Detect section headings dynamically.
    const lines = article.split('\n').map(l => l.trim());
    const sections = [];
    let cur = null;
    let pendingHeading = null;

    function looksLikeHeading(line) {
        if (!line || line.length > 40) return false;
        if (line.indexOf('|') >= 0) return false;
        if (line.indexOf(':') >= 0) return false;
        if (line.indexOf('.') >= 0) return false;
        if (/^[#\-*]/.test(line)) return false;
        if (!/^[A-Z][A-Za-z0-9 \-]+$/.test(line)) return false;
        if (line === 'Parameters' || line === 'Method' || line === 'Inputs') return false;
        return true;
    }

    for (let i = 0; i < lines.length; i++) {
        const L = lines[i];

        // Table header row triggers section start with the most recent heading.
        if (L.indexOf('Parameter | Details') >= 0) {
            if (pendingHeading) {
                cur = { name: pendingHeading, properties: [] };
                sections.push(cur);
                pendingHeading = null;
            }
            continue;
        }
        if (L === 'Inputs') {
            cur = { name: 'INPUTS', properties: [] };
            sections.push(cur);
            pendingHeading = null;
            continue;
        }
        if (L.indexOf('Name | Description') >= 0) continue;

        if (looksLikeHeading(L)) {
            pendingHeading = L;
            continue;
        }

        if (cur && L.startsWith('| ')) {
            const m = L.match(/^\|\s*([^|]+?)\s*(?:\||$)/);
            if (m && m[1] && m[1] !== 'Parameter' && m[1] !== 'Name') {
                cur.properties.push(m[1].trim());
            }
        }
    }
    return sections;
}

function findInIndex(index, query) {
    const q = query.toLowerCase();
    // exact
    let hit = index.find(r => r.name.toLowerCase() === q);
    if (hit) return hit;
    // startsWith
    hit = index.find(r => r.name.toLowerCase().startsWith(q));
    if (hit) return hit;
    // contains
    hit = index.find(r => r.name.toLowerCase().includes(q));
    return hit;
}

async function describeUrl(url, indexEntry) {
    const html = await fetch(url);
    const article = extractArticle(html);
    const sections = parseProperties(article);

    console.log('# ' + (indexEntry ? indexEntry.name : '(unknown node)'));
    console.log('URL: ' + url);
    if (indexEntry) {
        console.log('Inferred CreateNode: "' + indexEntry.createNodeGuess + '"' +
                    (indexEntry.verified ? '  [VERIFIED]' : '  [unverified - probe to confirm]'));
        console.log('Group path: ' + indexEntry.groupPath.join(' > '));
    }
    console.log();

    if (sections.length === 0) {
        console.log('(No structured properties parsed. Raw article excerpt:)\n');
        console.log(article.slice(0, 2000));
        return;
    }

    for (const s of sections) {
        if (s.name === 'INPUTS') {
            console.log('## Inputs (use with AddInput)');
            for (const p of s.properties) console.log('  - ' + p);
        } else {
            console.log('## ' + s.name + ' (use as "' + s.name + '.<Property>" in Set*)');
            for (const p of s.properties) console.log('  - ' + s.name + '.' + p);
        }
        console.log();
    }
}

async function main() {
    const args = process.argv.slice(2);
    if (args.length === 0) {
        console.log('Usage:');
        console.log('  node notch-node-info.js <name-or-substring>');
        console.log('  node notch-node-info.js --url <url>');
        console.log('  node notch-node-info.js --list');
        console.log('  node notch-node-info.js --grep <pattern>');
        process.exit(0);
    }

    if (args[0] === '--list') {
        const idx = loadIndex();
        for (const r of idx) console.log(r.createNodeGuess + '  ->  ' + r.url);
        return;
    }

    if (args[0] === '--grep') {
        const idx = loadIndex();
        const pat = new RegExp(args[1], 'i');
        for (const r of idx) {
            if (pat.test(r.name) || pat.test(r.path)) {
                console.log(r.createNodeGuess + '  ->  ' + r.url);
            }
        }
        return;
    }

    if (args[0] === '--url') {
        await describeUrl(args[1], null);
        return;
    }

    const idx = loadIndex();
    const hit = findInIndex(idx, args.join(' '));
    if (!hit) { console.error('No node matching "' + args.join(' ') + '"'); process.exit(1); }
    await describeUrl(hit.url, hit);
}

main().catch(e => { console.error(e); process.exit(1); });
