#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function fail(message) { throw new Error(message); }

function tokens(text) {
  const out = [];
  const re = /\s+|--[^\n]*|('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")|(-?\d+(?:\.\d+)?)|([A-Za-z_][A-Za-z0-9_]*)|([{}\[\]=,;])/gy;
  let at = 0;
  while (at < text.length) {
    re.lastIndex = at;
    const m = re.exec(text);
    if (!m) fail(`unsupported Lua near offset ${at}`);
    at = re.lastIndex;
    if (/^\s|^--/.test(m[0])) continue;
    out.push(m[1] ? ['string', m[1]] : m[2] ? ['number', m[2]] : m[3] ? ['ident', m[3]] : ['sym', m[4]]);
  }
  return out;
}

function unquote(s) {
  if (s[0] === '"') return JSON.parse(s);
  return s.slice(1, -1).replace(/\\n/g, '\n').replace(/\\r/g, '\r').replace(/\\t/g, '\t').replace(/\\([\\'\"])/g, '$1');
}

class Reader {
  constructor(text) { this.t = tokens(text); this.i = 0; }
  peek(v) { return this.i < this.t.length && (v === undefined || this.t[this.i][1] === v); }
  take(v) { if (this.i >= this.t.length) fail('unexpected end of Lua'); const x = this.t[this.i++]; if (v !== undefined && x[1] !== v) fail(`expected ${v}, got ${x[1]}`); return x; }
  value() {
    const [kind, raw] = this.t[this.i];
    if (raw === '{') return this.table();
    this.i++;
    if (kind === 'string') return unquote(raw);
    if (kind === 'number') return raw.includes('.') ? Number(raw) : Number.parseInt(raw, 10);
    if (raw === 'true') return true;
    if (raw === 'false') return false;
    if (raw === 'nil') return null;
    return raw;
  }
  table() {
    this.take('{'); const keyed = {}; const array = [];
    while (!this.peek('}')) {
      if (this.peek('[')) { this.take('['); const k = this.value(); this.take(']'); this.take('='); keyed[k] = this.value(); }
      else if ((this.t[this.i][0] === 'ident' || this.t[this.i][0] === 'string') && this.t[this.i + 1]?.[1] === '=') {
        const kt = this.take(); const k = kt[0] === 'string' ? unquote(kt[1]) : kt[1]; this.take('='); keyed[k] = this.value();
      } else array.push(this.value());
      if (this.peek(',') || this.peek(';')) this.take();
    }
    this.take('}');
    if (Object.keys(keyed).length && array.length) array.forEach((v, i) => keyed[i + 1] = v);
    return Object.keys(keyed).length ? keyed : array;
  }
}

function readSaved(file) {
  const r = new Reader(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  const values = {};
  while (r.i < r.t.length) { const [kind, name] = r.take(); if (kind !== 'ident') fail(`expected top-level variable, got ${name}`); r.take('='); values[name] = r.value(); if (r.peek(';')) r.take(); }
  return values;
}
module.exports = { readSaved, lua };

function idMap(value, field) {
  if (value === undefined) return {};
  if (!value || Array.isArray(value) || typeof value !== 'object') fail(`${field} must be an object keyed by IDs`);
  for (const k of Object.keys(value)) if (!/^\d+$/.test(k) || Number(k) <= 0) fail(`${field} contains invalid ID ${k}`);
  return value;
}

function validateWeb(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) fail('web data must be an object');
  if (!/^\d+\.\d+\.\d+\.\d+$/.test(String(data.build || ''))) fail('web data needs a build like 1.60.1.70755');
  for (const f of ['items', 'item_stats', 'quests', 'world_drops']) if (data[f] !== undefined) idMap(data[f], f);
  for (const f of ['instances', 'dungeon_maps', 'bis_weights']) if (data[f] !== undefined && typeof data[f] !== 'object') fail(`${f} must be an object or array`);
}

function luaKey(k) { return /^\d+$/.test(String(k)) ? `[${k}]` : /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${JSON.stringify(k)}]`; }
function lua(v, depth = 0) {
  if (v === null || v === undefined) return 'nil';
  if (v === true) return 'true'; if (v === false) return 'false';
  if (typeof v === 'number') return String(v); if (typeof v === 'string') return JSON.stringify(v);
  const pad = ' '.repeat(depth), child = ' '.repeat(depth + 4);
  if (Array.isArray(v)) return v.length ? `{\n${v.map(x => child + lua(x, depth + 4)).join(',\n')}\n${pad}}` : '{}';
  const entries = Object.entries(v);
  return entries.length ? `{\n${entries.map(([k, x]) => child + luaKey(k) + ' = ' + lua(x, depth + 4)).join(',\n')}\n${pad}}` : '{}';
}

function arg(name) { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : undefined; }
if (require.main === module) {
const collectFile = arg('--collect-file'), webFile = arg('--web-data'), output = arg('--output');
if (!output || (!collectFile && !webFile)) { console.error('Usage: node refresh_tool.js --collect-file FILE --web-data FILE --output FILE'); process.exit(2); }
try {
  let client = null, web = null;
  if (collectFile) {
    const saved = readSaved(collectFile); const root = saved.LootifiedData || {}; const game = root.gameTexts || {};
    client = game.enUS; if (!client || typeof client !== 'object') fail('LootifiedData.gameTexts.enUS was not found');
  }
  if (webFile) { web = JSON.parse(fs.readFileSync(webFile, 'utf8')); validateWeb(web); }
  const staged = { format: 1, client: client || {}, web: web || {} };
  const text = '-- Generated by Lootified Continued Refresh Tool. Review before applying.\nlocal _, LJ = ...\nLJ.RefreshInput = ' + lua(staged) + '\n\nlocal input = LJ.RefreshInput\nif input and input.web then\n    local web = input.web\n    local function mergeMap(target, source)\n        if type(source) ~= "table" then return end\n        for id, value in pairs(source) do target[tonumber(id) or id] = value end\n    end\n    mergeMap(LJ.Data.Items, web.items)\n    if type(LJ.Data.ItemStats) == "table" then\n        mergeMap(LJ.Data.ItemStats.items, web.item_stats)\n        LJ.Data.ItemStats.build = web.build\n    end\n    mergeMap(LJ.Data.Quests, web.quests)\n    mergeMap(LJ.Data.WorldDrops, web.world_drops)\n    mergeMap(LJ.Data.DungeonMaps, web.dungeon_maps)\n    if type(web.instances) == "table" and #web.instances > 0 then LJ.Data.Instances = web.instances end\n    if type(web.bis_weights) == "table" and next(web.bis_weights) then LJ.Data.BiS = web.bis_weights end\n    LJ.DATA_BUILD = web.build\n    LJ.DATA_CHECKED = os.date("!%Y-%m-%d")\n    LJ.DATA_STATUS = "client collection verified; reviewed Forever overrides installed"\n    LJ.DATA_SOURCES = web.provenance and (web.provenance.sources or web.provenance) or "reviewed Forever data"\nend\n';
  fs.mkdirSync(path.dirname(output), { recursive: true }); fs.writeFileSync(output, text, 'utf8');
  console.log(`Wrote staged Lua input: ${output}`); if (client) console.log('Client collect: loaded English gameTexts data'); if (web) console.log(`Web data: validated build ${web.build}`); console.log('No live addon files were overwritten.');
} catch (e) { console.error(`refresh_tool: error: ${e.message}`); process.exit(2); }
}
