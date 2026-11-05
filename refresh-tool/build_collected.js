#!/usr/bin/env node
// Regenerate compact runtime overrides from a completed English Forever collect.
const fs = require('fs');
const {readSaved, lua} = require('./refresh_tool');
const [,, savedPath, outputPath] = process.argv;
if (!savedPath || !outputPath) throw Error('Usage: node build_collected.js SAVED_VARIABLES OUTPUT_LUA');
const g = readSaved(savedPath).LootifiedData?.gameTexts?.enUS;
if (!g || g.format !== 7 || !/^\d+\.\d+\.\d+\.\d+$/.test(g.build)) throw Error('Expected completed format 7 English collection');
const compact = (v) => Number.isFinite(Number(v)) ? String(Number(Number(v).toFixed(4))) : String(v);
const stats = {}, weapons = {}, skills = {}, names = {}, quest = {};
for (const [id, data] of Object.entries(g.itemData || {})) {
  if (!data || !data[1] || typeof data[1] !== 'string' || data[1].includes('|')) continue;
  const s = data.s && !Array.isArray(data.s) ? Object.entries(data.s).filter(([key,val]) => /^[A-Za-z][A-Za-z0-9_]*$/.test(key) && Number.isFinite(Number(val))).map(([key,val]) => `${key}=${compact(val)}`).join(',') : '';
  stats[id] = [data[1], data[2] || 0, data[3] || 0, data[4] || 0, data[5] || 0, data[6] || 0, s].join('|');
  if (Array.isArray(data.w) && data.w.length === 3) weapons[id] = data.w.map(compact).join('|');
  if (Array.isArray(data.k) && data.k.length === 2) skills[id] = data.k.map(compact).join('|');
}
for (const [id, name] of Object.entries(g.items || {})) if (typeof name === 'string' && name.length && !name.includes('|')) names[id] = name;
for (const [id, title] of Object.entries(g.quests || {})) {
  if (typeof title !== 'string' || !title.length) continue;
  const fact = (g.questFacts?.[id] || '').split('|');
  const reward = (g.questRewards?.[id] || '').split('|');
  const lines = g.questLines?.[id];
  const row = { name: title };
  if (/^\d+$/.test(fact[0]) && +fact[0] > 0) row.level = +fact[0];
  // XP depends on the collecting character's level, so keep curated base XP.
  if (/^\d+$/.test(reward[1])) row.money = +reward[1];
  if (Array.isArray(lines) && typeof lines[2] === 'string' && lines[2].trim()) row.obj = lines[2];
  const choices = (reward[3] || '').split(',').map(x => +x.split(':')[0]).filter(Number.isInteger).filter(x => x > 0);
  if (choices.length) row.choice = choices;
  const items = (reward[2] || '').split(',').map(x => +x.split(':')[0]).filter(Number.isInteger).filter(x => x > 0);
  if (items.length) row.reward = items;
  quest[id] = row;
}
const payload = {build:g.build, items:stats, weapons, skills, names, quests:quest};
const script = `-- Generated from a completed Forever client collect, build ${g.build}.\nlocal _, LJ = ...\nlocal c = ${lua(payload)}\nlocal data = LJ.Data\nlocal shipped = data.ItemStats\nfor id, value in pairs(c.items) do shipped.items[id] = value end\nshipped.weapons = shipped.weapons or {}\nfor id, value in pairs(c.weapons) do shipped.weapons[id] = value end\nshipped.skills = shipped.skills or {}\nfor id, value in pairs(c.skills) do shipped.skills[id] = value end\nshipped.build = c.build\nfor id, name in pairs(c.names) do\n    local prior = data.Items[id]\n    if type(prior) == "string" then\n        local _, tail = prior:match("^(.-)(|.*)$")\n        if tail then data.Items[id] = name .. tail end\n    end\nend\nlocal function Unique(list)\n    local out, seen = {}, {}\n    for _, itemID in ipairs(list or {}) do\n        if itemID and not seen[itemID] then seen[itemID] = true; out[#out + 1] = itemID end\n    end\n    return out\nend\nlocal function Without(list, excluded)\n    local out = {}\n    for _, itemID in ipairs(list or {}) do\n        if not excluded[itemID] then out[#out + 1] = itemID end\n    end\n    return out\nend\nfor id, fresh in pairs(c.quests) do\n    local q = data.Quests[id]\n    if q then\n        q.name = fresh.name\n        if fresh.level then q.level = fresh.level end\n        if fresh.xp then q.xp = fresh.xp end\n        if fresh.money then q.money = fresh.money end\n        if fresh.obj then q.obj = fresh.obj end\n        if fresh.choice then q.choice = Unique(fresh.choice) end\n        if fresh.reward then\n            local choice = {}\n            for _, itemID in ipairs(q.choice or {}) do choice[itemID] = true end\n            q.reward = Without(Unique(fresh.reward), choice)\n            if #q.reward == 0 then q.reward = nil end\n        end\n    end\nend\nLJ.COLLECT_BUILD = c.build\nLJ.COLLECT_COUNTS = { items = ${Object.keys(stats).length}, quests = ${Object.keys(quest).length}, npcs = ${Object.keys(g.npcs || {}).length} }\n`;
fs.writeFileSync(outputPath, script);
console.log(JSON.stringify({build:g.build, items:Object.keys(stats).length, weapons:Object.keys(weapons).length, quests:Object.keys(quest).length, npcs:Object.keys(g.npcs||{}).length, bytes:Buffer.byteLength(script)}));
