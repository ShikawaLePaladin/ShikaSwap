// Test harness for ShikaSwap: fengari (Lua 5.3) turned into a strict "WoW 1.12 / Lua 5.0" sandbox.
//   node harness_shikaswap.js tests_shikaswap.lua
// - loads the files listed in ShikaSwap.toc, in order (like the game does)  [or FILES=a.lua;b.lua to load other files]
// - removes everything Lua 5.0 does not have (string.match/gmatch, select, table.unpack, _G ...)
// - event / OnUpdate handlers are called WITHOUT arguments (1.12): they must read the globals event/arg1/arg2
// - a Lua-side world mock (bags, relic slot, cooldowns, GCD, server latency) is defined in world.lua
// - tests/fixtures/*.lua are exposed as FIXTURES[name] (raw text of real WTF SavedVariables files, copied read-only)
const fs = require('fs');
const path = require('path');
// fengari lives in the existing luatest folder (shared with the other harnesses)
let fengariPath = 'fengari';
try { require.resolve('fengari'); } catch (e) { fengariPath = 'C:/Temp/ccx/luatest/node_modules/fengari'; }
const { lua, lauxlib, lualib, to_luastring } = require(fengariPath);

const addonDir = process.env.ADDON || path.join(__dirname, '..', 'ShikaSwap');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(code, name) {
  const s = to_luastring(code);
  if (lauxlib.luaL_loadbuffer(L, s, s.length, to_luastring(name)) || lua.lua_pcall(L, 0, 0, 0)) {
    console.log('LUA ERROR in ' + name + ': ' + lua.lua_tojsstring(L, -1));
    process.exit(2);
  }
}

// 1) Lua 5.0 environment
const keepG = process.env.KEEP_G ? 'true' : 'false';
run(`
KEEP_G = ${keepG}
string.gfind = string.gmatch
tinsert = table.insert
tremove = table.remove
table.getn = function(t) local n = 0; while t[n + 1] ~= nil do n = n + 1 end; return n end
local G = _G
WORLD_G = G
getglobal = function(n) return G[n] end
setglobal = function(n, v) G[n] = v end
getfenv = function() return G end
math.mod = math.fmod
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end   -- 5.0 has atan2, 5.3 has atan(y, x)
loadstring = load
-- remove what 5.0 / 1.12 does not have, so a stray use fails the tests
string.match = nil; string.gmatch = nil; select = nil; table.unpack = nil; unpack = nil
if not KEEP_G then _G._G = nil end   -- 1.12 has no reliable _G : the addon must not use it
`, 'lua50');

// 2) world mock, fixtures, then the addon files, then the tests
run(fs.readFileSync(path.join(__dirname, 'world.lua'), 'utf8'), 'world.lua');

let fx = 'FIXTURES = {}\n';
const fdir = path.join(__dirname, 'fixtures');
if (fs.existsSync(fdir)) {
  for (const f of fs.readdirSync(fdir)) {
    fx += 'FIXTURES[' + JSON.stringify(f.replace(/\.lua$/, '')) + '] = [==[' + fs.readFileSync(path.join(fdir, f), 'utf8').replace(/\r/g, '') + ']==]\n';
  }
}
run(fx, 'fixtures');
const bx = path.join(addonDir, 'Bindings.xml');
run('BINDINGS_XML = [==[' + (fs.existsSync(bx) ? fs.readFileSync(bx, 'utf8') : '') + ']==]', 'bindings');

let files, baseDir = addonDir;
if (process.env.FILES) {
  files = process.env.FILES.split(';');
  baseDir = '';
} else {
  const toc = fs.readFileSync(path.join(addonDir, 'ShikaSwap.toc'), 'utf8').split(/\r?\n/);
  files = toc.filter(l => l.trim() && l.trim()[0] !== '#');
}
if (process.env.SNAPSHOT_GLOBALS !== '0') run('WORLD_snapshotGlobals()', 'snap');
for (const f of files) {
  run(fs.readFileSync(path.join(baseDir, f.trim()), 'utf8').replace(/^﻿/, ''), path.basename(f.trim()));
}
run('WORLD_afterLoad()', 'afterload');

const tests = fs.readFileSync(path.resolve(process.argv[2]), 'utf8').replace(/^﻿/, '');
run(tests, path.basename(process.argv[2]));
