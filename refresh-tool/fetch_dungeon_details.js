#!/usr/bin/env node
// Refresh current dungeon status, level ranges, bosses and notable loot from ForeverDB.
const fs = require("fs");
const path = require("path");
const key = process.env.FOREVERDB_API_KEY;
const output = process.argv[2];
if (!key || !output) throw new Error("Usage: FOREVERDB_API_KEY=... node fetch_dungeon_details.js OUTPUT_LUA");
const base = "https://foreverdb.net/api/v1/";
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function get(p) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const r = await fetch(base + p, { headers: { "X-API-Key": key, Accept: "application/json" } });
    if (r.ok) return r.json();
    if (r.status !== 429 && r.status < 500) throw new Error(`${p}: HTTP ${r.status}`);
    await wait(Math.max(5000, (Number(r.headers.get("retry-after")) || (attempt + 1) * 5) * 1000));
  }
  throw new Error(`${p}: retries exhausted`);
}
function luaKey(k) { return /^\d+$/.test(String(k)) ? `[${k}]` : /^[A-Za-z_][A-Za-z0-9_]*$/.test(String(k)) ? String(k) : `[${JSON.stringify(String(k))}]`; }
function lua(v, depth = 0) {
  if (v == null) return "nil";
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  const pad = " ".repeat(depth), child = " ".repeat(depth + 4);
  if (Array.isArray(v)) return v.length ? `{\n${v.map(x => child + lua(x, depth + 4)).join(",\n")}\n${pad}}` : "{}";
  return Object.keys(v).length ? `{\n${Object.entries(v).map(([k, x]) => child + luaKey(k) + " = " + lua(x, depth + 4)).join(",\n")}\n${pad}}` : "{}";
}
function keyName(s) { return String(s || "").toLowerCase().replace(/^the\s+/, "").replace(/[^a-z0-9]/g, ""); }
(async () => {
  const index = await get("dungeons?limit=100");
  const out = {};
  for (const row of index.data || []) {
    await wait(1050);
    const detail = await get(`dungeons/${row.id}`);
    const d = detail.data || row;
    out[d.id] = {
      name: d.name, kind: d.kind, players: d.players, level: d.level, range: d.levelRange,
      status: d.status, newInForever: !!d.newInForever, bosses: d.bosses || [],
      notableLoot: (d.notableLoot || []).map(x => ({ itemId: x.itemId, name: x.name, why: x.why })),
      url: d.url,
    };
  }
  const script = `-- Generated from ForeverDB.net dungeon details.\nlocal _, LJ = ...\nLJ.Data = LJ.Data or {}\nLJ.Data.ForeverDBDungeons = ${lua(out)}\nlocal function FDBName(s) return tostring(s or ""):lower():gsub("^the%s+", ""):gsub("[^a-z0-9]", "") end\nfor _, inst in ipairs(LJ.Data.Instances or {}) do\n    local ik = FDBName(inst.name)\n    for _, d in pairs(LJ.Data.ForeverDBDungeons) do\n        if FDBName(d.name) == ik then\n            inst.foreverDB = d\n            if d.range then inst.minLevel, inst.maxLevel = d.range[1], d.range[2] end\n            inst.foreverDBStatus = d.status\n            inst.foreverDBURL = d.url\n            inst.notableLoot = d.notableLoot\n            break\n        end\n    end\nend\n`;
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, script, "utf8");
  console.log(JSON.stringify({ build: index.meta?.build, dungeons: Object.keys(out).length, output }));
})().catch(e => { console.error(e.message); process.exit(1); });
