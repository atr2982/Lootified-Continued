#!/usr/bin/env node
// Import current top-level BiS picks from the Forever-specific WoW Forever Forge pages.
const fs = require("fs");
const path = require("path");
const root = "https://wowforeverforge.com";
const headers = { "User-Agent": "Lootified-Continued-refresh/1.0" };
async function page(url) { const r = await fetch(root + url, { headers }); if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`); return r.text(); }
function luaKey(k) { return /^[A-Za-z_][A-Za-z0-9_]*$/.test(String(k)) ? String(k) : `[${JSON.stringify(String(k))}]`; }
function lua(v, depth = 0) {
  if (v == null) return "nil"; if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  const pad = " ".repeat(depth), child = " ".repeat(depth + 4);
  if (Array.isArray(v)) return v.length ? `{\n${v.map(x => child + lua(x, depth + 4)).join(",\n")}\n${pad}}` : "{}";
  return Object.keys(v).length ? `{\n${Object.entries(v).map(([k, x]) => child + luaKey(k) + " = " + lua(x, depth + 4)).join(",\n")}\n${pad}}` : "{}";
}
function slot(s) {
  return ({ head:"HEAD", neck:"NECK", shoulder:"SHOULDER", back:"BACK", chest:"CHEST", wrist:"WRIST", hands:"HANDS", waist:"WAIST", legs:"LEGS", feet:"FEET", "main-hand":"MAINHAND", "off-hand":"OFFHAND", ranged:"RANGED", "trinket-1":"TRINKET1", "trinket-2":"TRINKET2" })[s];
}
(async () => {
  const index = await page("/bis/");
  const links = [...index.matchAll(/href="\/([a-z-]+)\/([a-z-]+)\/" aria-label="([^"]+)"/g)]
    .map(m => ({ className: m[1], specName: m[2], label: m[3] }))
    .filter((x, i, a) => a.findIndex(y => y.className === x.className && y.specName === x.specName) === i);
  const specs = {};
  for (const link of links) {
    const html = await page(`/${link.className}/${link.specName}/`);
    const picks = {};
    for (const m of html.matchAll(/<li[^>]*data-slot="([^"]+)"[^>]*class="[^"]*is-best[^"]*"[^>]*data-card="[^"]*"[^>]*data-item="(\d+)"/g)) {
      const s = slot(m[1]); if (s && !picks[s]) picks[s] = Number(m[2]);
    }
    specs[`${link.className}:${link.specName}`] = { className: link.className, specName: link.specName, label: link.label, url: `${root}/${link.className}/${link.specName}/`, picks };
  }
  const script = `-- Generated from current Forever-specific BiS pages at wowforeverforge.com.\nlocal _, LJ = ...\nLJ.Data = LJ.Data or {}\nLJ.Data.WebBiS = ${lua(specs)}\nlocal function FDBSpec(s) return string.lower(s or ""):gsub("[^a-z0-9]", "") end\nfor key, web in pairs(LJ.Data.WebBiS) do\n    local classKey, specKey = key:match("^([^:]+):(.+)$")\n    local class = string.upper(classKey or "")\n    local specName = FDBSpec(specKey)\n    local list = LJ.Data.BiS[class]\n    if list then\n        for _, spec in ipairs(list) do\n            if FDBSpec(spec.key) == specName or FDBSpec(spec.name) == specName then\n                spec.webBiS = web\n                for slot, id in pairs(web.picks or {}) do\n                    if spec.slots and spec.slots[slot] then\n                        local seen = false\n                        for _, old in ipairs(spec.slots[slot]) do if old.id == id then seen = true break end end\n                        if not seen then table.insert(spec.slots[slot], 1, { id = id, src = "WoW Forever Forge (current Forever guide)" }) end\n                    end\n                end\n            end\n        end\n    end\nend\nLJ.BIS_WEB_SOURCE = "https://wowforeverforge.com/bis/"\n`;
  fs.mkdirSync(path.dirname(process.argv[2]), { recursive: true }); fs.writeFileSync(process.argv[2], script, "utf8");
  console.log(JSON.stringify({ specs: Object.keys(specs).length, picks: Object.values(specs).reduce((n, s) => n + Object.keys(s.picks).length, 0), output: process.argv[2] }));
})().catch(e => { console.error(e.message); process.exit(1); });
