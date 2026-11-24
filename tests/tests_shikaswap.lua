-- tests_shikaswap.lua : run with  node harness_shikaswap.js tests_shikaswap.lua
-- Covers: load/globals, catalogue (rule table), Plan decisions, GCD/timing (burst/wait/defer/queue), combat+bag edge cases,
-- hooks (byname / book / action bar), commands, migration from LibramSwap, saved-variable robustness.
local FAILS, PASSES = 0, 0
local function ok(cond, msg)
    if cond then PASSES = PASSES + 1 else FAILS = FAILS + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
    if a == b then PASSES = PASSES + 1 else FAILS = FAILS + 1; print("FAIL: " .. msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end
local function section(s) print("-- " .. s) end

local SS = ShikaSwap

local function fresh()
    W.reset()
    ShikaSwapDB = nil
    SS.stats = {}; SS.ring = {}; SS.ringN = 0; SS.queue = nil; SS.pending = nil; SS.probe = nil; SS.consecFail = 0
    SS.castUntil = nil; SS.chanUntil = nil; SS.bagDirty = true; SS.book = nil; SS.conflict = false; SS.openerAt = nil
    SS.lastSwap = nil; SS.bagIdx = nil
    SS.InitDB()
    SS.frame:Hide()
end
local function pally()
    fresh()
    SS.SetRule("Holy Light", { "Libram of Radiance" })
    SS.SetRule("Flash of Light", { "Libram of Light" })
    SS.SetRule("Consecration", { "Libram of the Faithful" })
    SS.SetRule("Judgement", { "Libram of Final Judgement" })
    W.putBag(0, 1, ITEM.Radiance); W.putBag(0, 2, ITEM.Light); W.putBag(0, 3, ITEM.Faithful); W.putBag(0, 4, ITEM.FinalJ)
    W.equip(ITEM.Hope)
end
local function press(spell) CastSpellByName(spell) end
local function relicNow() return W.sinv[18] end

-- ============================================================ 1. load / globals
section("load")
ok(NEW_GLOBALS ~= nil, "globals audit available")
local allowed = { NEW_GLOBALS = true, ShikaSwap = true, ShikaSwapData = true, SLASH_SHIKASWAP1 = true, SLASH_SHIKASWAP2 = true,
    BINDING_HEADER_SHIKASWAP = true, BINDING_NAME_SHIKASWAP_MENU = true, BINDING_NAME_SHIKASWAP_TOGGLE = true, BINDING_NAME_SHIKASWAP_MODE = true }
local leaked = {}
for i = 1, table.getn(NEW_GLOBALS) do if not allowed[NEW_GLOBALS[i]] then leaked[table.getn(leaked) + 1] = NEW_GLOBALS[i] end end
eq(table.concat(leaked, ","), "", "no leaked globals at load")
ok(ShikaSwapDB == nil, "saved variables are NOT touched at file load (the client loads them afterwards)")
ok(type(SlashCmdList["SHIKASWAP"]) == "function", "slash handler registered")
eq(SLASH_SHIKASWAP1, "/shikaswap", "slash 1")
eq(SLASH_SHIKASWAP2, "/ssw", "slash 2")
ok(SS.hooked and SS.orig and CastSpellByName ~= SS.orig.CastSpellByName, "CastSpellByName hooked")
ok(CastSpell ~= SS.orig.CastSpell and UseAction ~= SS.orig.UseAction, "CastSpell / UseAction hooked")
eq(SS.frame.shown, false, "frame hidden at load : no OnUpdate when idle")
ok(SS.frame.events["BAG_UPDATE"] and SS.frame.events["UNIT_INVENTORY_CHANGED"], "events registered")
ok(not SS.frame.events["PLAYER_EQUIPMENT_CHANGED"], "no 2.x-only event used")

-- handlers receive no arguments in 1.12 : ADDON_LOADED must initialise the DB through the globals
W.reset()
W.fire("ADDON_LOADED", "SomeOtherAddon")
ok(ShikaSwapDB == nil, "other addons' ADDON_LOADED ignored")
W.fire("ADDON_LOADED", "ShikaSwap")
ok(type(ShikaSwapDB) == "table" and ShikaSwapDB.combat == "auto" and ShikaSwapDB.enabled == true, "DB created with defaults on ADDON_LOADED (handler reads globals)")

-- ============================================================ 2. catalogue (rule table)
section("catalogue")
local R = ShikaSwapData.relics
local n = 0
for name, info in pairs(R) do
    n = n + 1
    ok(type(info.id) == "number" and type(info.spells) == "table" and (info.class == "PALADIN" or info.class == "DRUID" or info.class == "SHAMAN"), "entry well formed: " .. name)
end
eq(n, 64, "64 relics (20 librams + 22 idols + 22 totems from the server DB, Test Relic excluded)")
eq(ShikaSwapData.slot, 18, "relic slot 18")
eq(R["Libram of Light"].id, 23006, "Libram of Light id")
eq(R["Libram of Light"].spells[1], "Flash of Light", "Libram of Light -> Flash of Light")
eq(R["Libram of Final Judgement"].cond, "tgt35hold", "Final Judgement has the <35% execute-hold condition")
eq(R["Libram of Hallowed Ground"].spells[1], "Consecration", "Hallowed Ground -> Consecration")
ok(R["Libram of the Faithful"].sticky and R["Libram of the Farraki Zealot"].sticky, "Consecration auras are flagged sticky")
ok(R["Test Relic"] == nil, "Test Relic excluded")
local old18 = { "Libram of the Faithful", "Libram of the Farraki Zealot", "Libram of Radiance", "Libram of Light", "Libram of Grace",
    "Libram of the Dreamguard", "Libram of the Justicar", "Libram of the Resolute", "Libram of the Eternal Tower", "Libram of Final Judgement",
    "Libram of Hope", "Libram of Fervor", "Libram of Truth", "Libram of Veracity", "Libram of Divinity", "Libram of the Radiant Dawn",
    "Libram of Ardour", "Libram of Hallowed Ground" }
local missing = {}
for i = 1, table.getn(old18) do if not R[old18[i]] then missing[table.getn(missing) + 1] = old18[i] end end
eq(table.concat(missing, ","), "", "all 18 librams of the old LibramSwap list exist in the catalogue")
ok(R["Libram of Virtue"] and R["Libram of the Exorciser"], "2 librams the old addon did not list are present")
fresh()
eq(SS.eqGroups.fol_heal[1], "Libram of Light", "equivalence group: Light before Divinity")
eq(SS.eqGroups.fol_heal[2], "Libram of Divinity", "equivalence group second")
local ls = SS.RelicsForSpell("Consecration", "PALADIN")
eq(table.concat(ls, ","), "Libram of Hallowed Ground,Libram of the Faithful,Libram of the Farraki Zealot", "relics for Consecration")
eq(table.getn(SS.RelicsForSpell("Hex")), 2, "Hex: Ancient Rites + Bad Mojo")

-- ============================================================ 3. parsing / helpers
section("parsing")
local b, r = SS.ParseSpell("Holy Light(Rank 3)")
eq(b, "Holy Light", "base"); eq(r, "Rank 3", "rank")
b, r = SS.ParseSpell("  Judgement ")
eq(b, "Judgement", "trim"); eq(r, nil, "no rank")
b, r = SS.ParseSpell("Flash of Light (rank 2)")
eq(b, "Flash of Light", "space before paren"); eq(r, "Rank 2", "case-insensitive rank")
eq(SS.ParseSpell(nil), nil, "nil spell")
eq(SS.ItemIdFromLink("|cff|Hitem:23006:0:0:0|h[Libram of Light]|h|r"), 23006, "id from link")
eq(SS.ItemNameFromLink("|cff|Hitem:23006:0:0:0|h[Libram of Light]|h|r"), "Libram of Light", "name from link")
eq(SS.CanonRelic("libram of LIGHT"), "Libram of Light", "canonical relic name")
ok(not SS.LinkIsRelic("|Hitem:99999:0:0:0|h[Libram of Light Fake]|h", "Libram of Light"), "matching is by id, not by substring")

-- ============================================================ 4. Plan (pure decisions on a snapshot table)
section("plan")
local function snap(o)
    local s = { now = 1000, combat = false, dead = false, cursor = false, blocked = nil, casting = false, eqId = nil, eqName = nil,
        rem = 0, dur = 0, known = true, tgtHp = nil, find = function(name) if name == "Libram of Radiance" then return 0, 1 end return nil end }
    for k, v in pairs(o or {}) do s[k] = v end
    return s
end
fresh()
SS.SetRule("Holy Light", { "Libram of Radiance" })
local p = SS.Plan("Holy Light", snap())
eq(p.act, "swap", "out of combat -> swap"); eq(p.cast, "now", "cast now"); eq(p.bag, 0, "bag"); eq(p.slot, 1, "slot")
eq(SS.Plan("Holy Light", snap({ eqId = 55470 })).act, "pass", "already equipped -> pass")
eq(SS.Plan("Holy Light", snap({ pendRelic = "Libram of Radiance", pendAge = 0.1 })).why, "already equipped", "in transit counts as equipped")
eq(SS.Plan("Holy Light", snap({ pendRelic = "Libram of Light", pendAge = 0.1 })).why, "swap in transit", "a different swap in transit blocks")
eq(SS.Plan("Holy Light", snap({ dead = true })).why, "dead", "dead")
eq(SS.Plan("Holy Light", snap({ cursor = true })).why, "item on cursor", "cursor")
eq(SS.Plan("Holy Light", snap({ blocked = "MerchantFrame" })).act, "pass", "merchant window")
eq(SS.Plan("Holy Light", snap({ casting = true })).why, "casting", "casting")
eq(SS.Plan("Holy Light", snap({ known = false })).why, "spell not in spellbook", "unknown spell")
eq(SS.Plan("Holy Light", snap({ rem = 12, dur = 15 })).why, "spell on cooldown", "real cooldown")
eq(SS.Plan("Holy Light", snap({ find = function() return nil end })).why, "no candidate in bags", "relic missing from bags")
eq(SS.Plan("Nothing", snap()).why, "no rule", "no rule")
-- combat
p = SS.Plan("Holy Light", snap({ combat = true }))
eq(p.act, "swap", "combat burst: swap now when GCD is free"); eq(p.cast, "now", "burst casts in the same frame")
p = SS.Plan("Holy Light", snap({ combat = true, rem = 0.8, dur = 1.5 }))
eq(p.act, "defer", "combat burst during GCD: defer (no GCD extension)")
SS.db.combat = "wait"
p = SS.Plan("Holy Light", snap({ combat = true, rem = 0.8, dur = 1.5 }))
eq(p.act, "swap", "wait mode: swap now"); eq(p.cast, "queue", "wait mode: cast queued")
SS.db.combat = "skip"
eq(SS.Plan("Holy Light", snap({ combat = true })).why, "combat mode skip", "skip mode in combat")
eq(SS.Plan("Holy Light", snap({ combat = false })).act, "swap", "skip mode still swaps out of combat (free)")
SS.db.combat = "auto"; SS.db.learned = "wait"
eq(SS.Plan("Holy Light", snap({ combat = true })).cast, "queue", "auto + learned wait")
SS.db.learned = nil
SS.db.off["Holy Light"] = true
eq(SS.Plan("Holy Light", snap()).why, "rule switched off", "rule off")
SS.db.off["Holy Light"] = nil
SS.db.enabled = false
eq(SS.Plan("Holy Light", snap()).why, "disabled", "addon off")
SS.db.enabled = true
-- condition (Final Judgement : only below 35 percent)
SS.SetRule("Judgement", { "Libram of Final Judgement" })
local function fj(o) o = o or {}; o.find = function(name) if name == "Libram of Final Judgement" then return 0, 4 end end; return snap(o) end
eq(SS.Plan("Judgement", fj({ tgtHp = 20 })).act, "swap", "FJ: target at 20 percent -> swap")
eq(SS.Plan("Judgement", fj({ tgtHp = 50 })).why, "condition not met", "FJ: target at 50 percent -> no swap")
eq(SS.Plan("Judgement", fj({ tgtHp = 35 })).act, "pass", "FJ: exactly 35 is not below 35")
eq(SS.Plan("Judgement", fj({})).act, "pass", "FJ: no target -> no swap")
-- fallbacks (Light > Divinity)
SS.SetRule("Flash of Light", { "Libram of Light" })
local function fol(have, o) o = o or {}; o.find = function(name) return have[name] and 0 or nil, have[name] end; return snap(o) end
eq(SS.Plan("Flash of Light", fol({ ["Libram of Divinity"] = 2 })).relic, "Libram of Divinity", "Light missing -> Divinity")
eq(SS.Plan("Flash of Light", fol({ ["Libram of Divinity"] = 2, ["Libram of Light"] = 3 })).relic, "Libram of Light", "both -> Light")
eq(SS.Plan("Flash of Light", fol({ ["Libram of Light"] = 3 }, { eqId = 23201 })).relic, "Libram of Light", "Divinity equipped but Light in bags -> Light")
eq(SS.Plan("Flash of Light", fol({}, { eqId = 23201 })).why, "already equipped", "Light missing, Divinity equipped -> stay")
SS.db.fallbacks = false; SS.RebuildIndex()
eq(SS.Plan("Flash of Light", fol({ ["Libram of Divinity"] = 2 })).why, "no candidate in bags", "fallbacks off")
SS.db.fallbacks = true; SS.RebuildIndex()
-- ordered list
SS.SetRule("Holy Light", { "Libram of Virtue", "Libram of Radiance" })
local function hl(have, o) o = o or {}; o.find = function(name) return have[name] and 0 or nil, have[name] end; return snap(o) end
eq(SS.Plan("Holy Light", hl({ ["Libram of Radiance"] = 1 })).relic, "Libram of Radiance", "ordered list: first AVAILABLE wins")
eq(SS.Plan("Holy Light", hl({ ["Libram of Radiance"] = 1, ["Libram of Virtue"] = 2 })).relic, "Libram of Virtue", "ordered list: preferred first")

-- ============================================================ 5. end to end : out of combat
section("out of combat")
pally()
press("Holy Light(Rank 3)")
eq(W.logCount("UCI 0 1"), 1, "OOC: one equip request")
eq(W.castCount("Holy Light"), 1, "OOC: the cast leaves in the same frame (swap is free out of combat)")
W.advance(0.5)
eq(relicNow(), ITEM.Radiance, "OOC: Radiance equipped on the server")
eq(W.casts[1].relic, ITEM.Radiance, "OOC: the cast was resolved with Radiance (equip packet precedes the cast)")
eq(W.cbags[0][1], ITEM.Hope, "OOC: the old relic took the bag slot (swap in place, works with full bags)")
eq(SS.stats.swapsFree, 1, "stat swapsFree")
press("Holy Light(Rank 3)")
W.advance(2)
eq(W.logCount("UCI"), 1, "no re-equip when already equipped")
-- bags completely full
pally()
for s = 5, 16 do W.putBag(0, s, 900000 + s) end
press("Holy Light")
W.advance(0.5)
eq(relicNow(), ITEM.Radiance, "swap works with completely full bags")
-- missing relic
pally(); W.clearBags()
press("Holy Light")
eq(W.logCount("UCI"), 0, "relic missing: no equip attempt")
eq(W.castCount("Holy Light"), 1, "relic missing: the cast still goes through")

-- ============================================================ 6. end to end : combat, GCD
section("combat burst (hypothesis H1: swap GCD reaches the client after the cast left)")
pally(); W.combat = true; W.equip(ITEM.Light)
press("Holy Light")
eq(W.logCount("UCI 0 1"), 1, "burst: equip")
eq(W.castCount("Holy Light"), 1, "burst: cast accepted in the same frame")
eq(W.logCount("REFUSED"), 0, "burst: nothing refused")
W.advance(2)
eq(W.casts[1].relic, ITEM.Radiance, "burst: the cast saw the new relic")
ok(W.logHas("CLIENT: combat swap GCD"), "the swap GCD reached the client afterwards")
eq(SS.stats.burstSent, 1, "burstSent")
press("Flash of Light")   -- swap again, GCD is over
W.advance(2)
eq(W.castCount("Flash of Light"), 1, "burst: second swap+cast")
eq(relicNow(), ITEM.Light, "burst: relic is Light")
eq(SS.stats.burstOk, 1, "burstOk counted once the next burst starts")
eq(SS.db.learned, nil, "nothing learned while burst works")

section("combat burst during the GCD (defer, no extension)")
pally(); W.combat = true; W.equip(ITEM.Light)
W.gcd = { start = W.now, dur = 1.5 }   -- previous spell just cast
W.advance(0.7)
press("Holy Light")
eq(W.logCount("UCI"), 0, "defer: nothing happens during the running GCD")
W.advance(0.6)
eq(W.logCount("UCI"), 0, "defer: still waiting")
W.advance(0.4)
eq(W.logCount("UCI 0 1"), 1, "defer: swap when the GCD ends")
eq(W.castCount("Holy Light"), 1, "defer: cast in the same frame as the swap")
ok(W.casts[1].at - (1000 + 1.5) < 0.1, "defer: cast within 0.1 s of the GCD end")
eq(W.logCount("REFUSED"), 0, "defer: nothing refused")

section("hypothesis H2 : client applies the swap GCD immediately -> auto mode learns 'wait'")
pally(); W.combat = true; W.localGcdOnEquip = true; W.equip(ITEM.Light)
press("Holy Light")
eq(W.logCount("UCI 0 1"), 1, "H2: swap sent")
eq(W.castCount("Holy Light"), 0, "H2: cast refused by the client")
eq(W.logCount("REFUSED"), 1, "H2: refusal logged")
eq(SS.stats.burstFail, 1, "burstFail counted")
ok(SS.queue ~= nil and SS.queue.kind == "cast", "H2: the key press is retried (queued)")
W.advance(2)
eq(W.castCount("Holy Light"), 1, "H2: the retry fired once the GCD was over")
-- second failure -> learned wait
W.advance(2)
press("Flash of Light"); W.advance(2)
eq(SS.stats.burstFail, 2, "second refusal")
eq(SS.db.learned, "wait", "auto mode learned 'wait' after 2 consecutive refusals")
ok(W.chatHas("wait"), "player told about the automatic switch")
press("Holy Light"); W.advance(0.2)
local refusedBefore = W.logCount("REFUSED")
W.advance(2)
eq(W.logCount("REFUSED"), refusedBefore, "wait mode : no new refusal")
eq(W.castCount("Holy Light"), 2, "wait mode: cast delivered after the GCD")

section("wait mode with a spamming player")
pally(); W.combat = true; W.equip(ITEM.Light); SS.db.combat = "wait"
local t0 = W.now
press("Holy Light")
for i = 1, 13 do W.advance(0.1); press("Holy Light") end   -- 1.3 s of key spam while the queued cast waits for the GCD
eq(W.castCount("Holy Light"), 0, "wait/spam: nothing cast before the swap GCD is over")
eq(W.logCount("REFUSED"), 0, "wait/spam: no 'not ready' spam (presses swallowed while queued)")
ok(SS.stats.pressSwallowed >= 10, "presses swallowed counted")
W.advance(1)
eq(W.logCount("UCI"), 1, "wait/spam: a single equip")
eq(W.castCount("Holy Light"), 1, "wait/spam: a single cast")
local dt = W.casts[1].at - t0
ok(dt >= 1.5 and dt < 1.8, "wait: cast about 1.5 s + latency after the swap (" .. string.format("%.2f", dt) .. ")")

section("queue : supersede, timeout, cleanup")
pally(); W.combat = true; W.equip(ITEM.Light); SS.db.combat = "wait"
press("Holy Light"); W.advance(0.2)
press("Flash of Light")
eq(SS.queue.spell, "Flash of Light", "a different spell supersedes the queued one")
W.advance(3)
eq(W.castCount("Holy Light"), 0, "superseded cast dropped")
pally(); W.combat = true; W.equip(ITEM.Light); SS.db.combat = "wait"
press("Holy Light"); W.advance(0.2)
W.spellCd["Holy Light"] = { start = W.now, dur = 100 }  -- never ready
W.advance(3.5)
eq(SS.stats.queueTimeouts, 1, "queue timeout")
eq(SS.queue, nil, "queue empty after timeout")
eq(SS.frame.shown, false, "frame hidden again after the queue is empty")
eq(W.castCount("Holy Light"), 0, "no late cast after timeout")
pally(); W.combat = true; SS.db.combat = "wait"; W.equip(ITEM.Light)
press("Holy Light"); W.advance(0.1)
W.fire("PLAYER_DEAD")
eq(SS.queue, nil, "death clears the queue")

section("burst attribution / latest intent")
pally(); W.combat = true; W.equip(ITEM.Light)
press("Holy Light"); W.advance(0.1)
CastSpellByName("Holy Shock")      -- another key during the GCD : the client refuses it, that is NOT a burst failure
eq(W.logCount("REFUSED"), 1, "the unrelated press was refused by the client")
eq(SS.stats.burstFail, nil, "an unrelated 'not ready' is not blamed on the burst")
eq(SS.db.learned, nil, "nothing learned from unrelated refusals")
pally(); W.combat = true; W.equip(ITEM.Light); SS.db.combat = "wait"
local got
SS.Run("Holy Light", nil, function() got = "A" end, "t")
W.advance(0.2)
SS.Run("Holy Light", nil, function() got = "B" end, "t")
W.advance(2)
eq(got, "B", "while queued, the most recent press is the one that fires")
pally(); W.combat = true; W.equip(ITEM.Light)
SlashCmdList["SHIKASWAP"]("mode skip")
SlashCmdList["SHIKASWAP"]("next Holy Light")
eq(SS.db.combat, "skip", "'next' does not modify the saved combat mode")

section("a queued cast never fires behind the player's back")
pally(); W.combat = true; W.equip(ITEM.Light); SS.db.combat = "wait"
press("Holy Light"); W.advance(0.2)
CastSpellByName("Holy Shock")     -- unruled spell : the player moved on
eq(SS.queue, nil, "pressing another (unruled) spell cancels the queued cast")
W.advance(3)
eq(W.castCount("Holy Light"), 0, "cancelled cast did not fire later")
pally(); W.combat = true; W.equip(ITEM.Light); SS.db.combat = "wait"
W.actions[6] = { macro = "MyHeal", run = function() CastSpellByName("Holy Light") end }
W.actions[8] = { name = "Holy Shock", rank = "Rank 1" }
SS.actionCache = {}
UseAction(6); W.advance(0.2)
UseAction(6)                      -- same macro again while queued : must NOT cancel
ok(SS.queue ~= nil and SS.queue.spell == "Holy Light", "macro button repeated : queue kept")
UseAction(8)                      -- a plain spell button : cancels
eq(SS.queue, nil, "plain action button cancels the queue")

-- ============================================================ 7. safety states
section("forbidden states")
pally(); W.showWindow("MerchantFrame")
press("Holy Light")
eq(W.logCount("UCI"), 0, "merchant open: no UseContainerItem")
eq(W.logCount("SOLD"), 0, "merchant open: nothing sold")
W.hideWindow("MerchantFrame")
for _, win in ipairs({ "BankFrame", "TradeFrame", "SendMailFrame", "AuctionFrame" }) do
    pally(); W.showWindow(win); press("Holy Light")
    eq(W.logCount("UCI"), 0, win .. " open: no swap")
    W.hideWindow(win)
end
pally(); W.cursor = true; press("Holy Light")
eq(W.logCount("UCI"), 0, "item on cursor: no swap")
pally(); W.dead = true; press("Holy Light")
eq(W.logCount("UCI"), 0, "dead: no swap")
pally(); W.fire("SPELLCAST_START", "Holy Light", 2500); press("Flash of Light")
eq(W.logCount("UCI"), 0, "casting: no swap")
W.advance(2.6)
W.fire("SPELLCAST_STOP")
press("Flash of Light")
eq(W.logCount("UCI"), 1, "after the cast: swap allowed")
pally(); W.locked[1] = true; press("Holy Light")
eq(W.logCount("UCI"), 0, "locked bag slot: no swap")
pally(); W.fire("SPELLCAST_CHANNEL_START", 3000, "Something"); press("Holy Light")
eq(W.logCount("UCI"), 0, "channeling: no swap")
W.fire("SPELLCAST_CHANNEL_STOP"); press("Holy Light")
eq(W.logCount("UCI"), 1, "after the channel: swap allowed")

section("latency race (the old addon could re-equip the relic that had just been swapped out)")
pally(); W.latency = 0.4; W.equip(ITEM.Hope)
press("Holy Light")                 -- Radiance (bag 0/1) goes in, Hope takes bag 0/1 on the server later
W.advance(0.1)
press("Flash of Light")             -- Light is in bag 0/2 : another swap while the first is in transit
eq(W.logCount("UCI"), 1, "second swap blocked while the first is in transit")
W.advance(1.5)
eq(relicNow(), ITEM.Radiance, "first swap completed")
press("Flash of Light")
W.advance(1.5)
eq(relicNow(), ITEM.Light, "second swap done afterwards")
eq(W.sbags[0][1], ITEM.Hope, "Hope back in bag 0/1")
eq(W.sbags[0][2], ITEM.Radiance, "Radiance back in bag 0/2")
eq(W.logCount("SERVER: empty"), 0, "never targeted an empty slot")

-- ============================================================ 8. hooks : book / action bar / macros
section("hooks")
pally()
local idx
for i = 1, table.getn(W.book) do if W.book[i].name == "Holy Light" and W.book[i].rank == "Rank 3" then idx = i end end
CastSpell(idx, "spell")
eq(W.logCount("UCI 0 1"), 1, "CastSpell(index) is intercepted")
eq(W.castCount("Holy Light"), 1, "CastSpell cast forwarded")
pally()
local function bar()
    W.actions[5] = { name = "Holy Light", rank = "Rank 3" }
    W.actions[6] = { macro = "MyHeal", run = function() CastSpellByName("Holy Light") end }
    W.actions[7] = { name = "Greater Heal", rank = "Rank 1" }
    SS.actionCache = {}
end
bar()
UseAction(5)
eq(W.logCount("UCI 0 1"), 1, "action-bar spell button is intercepted (the old addon missed these)")
pally(); bar()
UseAction(6)
eq(W.logCount("UCI 0 1"), 1, "macro on the bar: intercepted once through its /cast")
eq(W.castCount("Holy Light"), 1, "macro cast once")
pally(); bar()
UseAction(7)
eq(W.logCount("UCI"), 0, "unrelated action ignored")
-- case-insensitive names
pally(); press("holy light")
eq(W.logCount("UCI 0 1"), 1, "lower-case spell name matches")
-- no rules at all : pure pass-through and no API traffic
fresh(); W.putBag(0, 1, ITEM.Radiance)
local calls = 0
local oldCont = GetContainerItemLink
GetContainerItemLink = function(b, s) calls = calls + 1; return oldCont(b, s) end
press("Holy Light")
eq(calls, 0, "no rules : zero bag API calls")
eq(W.castCount("Holy Light"), 1, "no rules : cast passes through")
GetContainerItemLink = oldCont
-- when already equipped, repeated casts do not rescan bags
pally(); W.equip(ITEM.Radiance); press("Holy Light"); W.advance(2)
calls = 0
GetContainerItemLink = function(b, s) calls = calls + 1; return oldCont(b, s) end
for i = 1, 5 do press("Holy Light"); W.advance(1.6) end
eq(calls, 0, "equipped relic : no bag rescans while casting")
GetContainerItemLink = oldCont

section("conflict with the old addon")
pally()
LibramSwap_ApplySelection = function() end
W.fire("PLAYER_LOGIN")
ok(SS.conflict, "old LibramSwap detected")
press("Holy Light")
eq(W.logCount("UCI"), 0, "dormant : no swap")
eq(W.castCount("Holy Light"), 1, "dormant : cast passes")
LibramSwap_ApplySelection = nil
W.fire("PLAYER_LOGIN")
ok(not SS.conflict, "conflict cleared when the old addon is gone")

section("opener / next")
pally(); SS.db.opener = "Flash of Light"
W.fire("PLAYER_REGEN_ENABLED")
eq(SS.frame.shown, true, "opener arms the throttled loop")
W.advance(1.2)
eq(W.logCount("UCI 0 2"), 1, "opener equips Light out of combat")
eq(SS.frame.shown, false, "loop stopped afterwards")
pally(); W.combat = true; SS.db.combat = "skip"
SlashCmdList["SHIKASWAP"]("next Holy Light")
eq(W.logCount("UCI 0 1"), 1, "'next' swaps in combat even in skip mode (explicit)")
pally(); W.dead = true
SlashCmdList["SHIKASWAP"]("next Holy Light")
eq(W.logCount("UCI"), 0, "'next' still respects forbidden states")

-- ============================================================ 9. commands
section("commands")
fresh()
W.putBag(0, 1, ITEM.Radiance); W.putBag(0, 2, ITEM.Light); W.putBag(0, 3, ITEM.Divinity); W.putBag(0, 4, ITEM.EternalTower)
local function cmd(s) W.chat = {}; local okc, err = pcall(SlashCmdList["SHIKASWAP"], s); if not okc then print("CMD ERROR " .. s .. ": " .. tostring(err)); FAILS = FAILS + 1 end end
cmd("set holy light = libram of radiance")
eq(SS.db.rules["Holy Light"][1], "Libram of Radiance", "set canonicalises spell and relic names")
cmd("set Seal of Righteousness = Libram of Final Judgement")
ok(W.chatHas("does not improve"), "warns when a relic does not improve the spell (the user's real mistake in his old settings)")
cmd("set Judgement = Libram of Nothing, Libram of Final Judgement")
ok(W.chatHas("not in the catalogue"), "warns about unknown relic names")
eq(table.getn(SS.db.rules["Judgement"]), 2, "two relics stored")
cmd("set Holy Light")
ok(W.chatHas("Usage"), "usage on malformed set")
cmd("list"); ok(W.chatHas("Holy Light -> Libram of Radiance [bags]"), "list shows where each relic is")
cmd("disable Holy Light"); eq(SS.db.off["Holy Light"], true, "disable")
cmd("enable Holy Light"); eq(SS.db.off["Holy Light"], nil, "enable")
cmd("clear Judgement"); eq(SS.db.rules["Judgement"], nil, "clear")
cmd("check"); ok(W.chatHas("does not improve"), "check reports problems")
cmd("mode burst"); eq(SS.db.combat, "burst", "mode burst")
cmd("mode wait"); eq(SS.db.combat, "wait", "mode wait")
cmd("mode nonsense"); ok(W.chatHas("auto, burst, wait or skip"), "bad mode refused"); eq(SS.db.combat, "wait", "mode unchanged")
SS.db.learned = "wait"; cmd("mode auto"); eq(SS.db.learned, nil, "mode auto forgets the learned state")
cmd("off"); eq(SS.db.enabled, false, "off"); cmd("on"); eq(SS.db.enabled, true, "on")
cmd("suggest"); ok(W.chatHas("Flash of Light: Libram of Divinity, Libram of Light"), "suggest lists owned relics per spell")
cmd("bags"); ok(W.chatHas("Libram of Light [bags]"), "bags lists relics")
fresh(); W.putBag(0, 1, ITEM.Radiance); W.putBag(0, 2, ITEM.Light); W.putBag(0, 3, ITEM.Divinity); W.putBag(0, 4, ITEM.EternalTower); W.putBag(0, 5, ITEM.Hope)
cmd("auto")
eq(SS.db.rules["Flash of Light"] and SS.db.rules["Flash of Light"][1], "Libram of Light", "auto: Flash of Light -> best of its equivalence group")
ok(SS.db.rules["Holy Strike"] == nil or SS.db.rules["Holy Strike"][1] ~= nil, "auto is conservative")
eq(SS.db.rules["Seal of Command"], nil, "auto never maps wide-category relics (Hope covers every seal)")
cmd("debug on"); eq(SS.db.debug, true, "debug on")
press("Flash of Light"); cmd("log"); ok(W.chatHas("Flash of Light"), "log shows decisions")
cmd("debug off"); cmd("trace on"); W.chat = {}; press("Holy Light"); eq(table.getn(W.chat or {}), 0, "trace records silently")
cmd("log"); ok(table.getn(W.chat) > 0, "trace log readable")
cmd("status"); ok(W.chatHas("hooks: CastSpellByName, CastSpell, UseAction"), "status shows hooks")
cmd("reset"); eq(SS.stats.swapsFree, nil, "reset clears counters")
cmd("profile save heal"); cmd("profile list"); ok(W.chatHas("heal"), "profile saved")
cmd("clear Flash of Light"); cmd("profile load heal"); ok(SS.db.rules["Flash of Light"] ~= nil, "profile loaded")
cmd("profile del heal"); eq(SS.db.profiles.heal, nil, "profile deleted")
cmd("profile load heal"); ok(W.chatHas("No such profile"), "missing profile message")
cmd("nonsense"); ok(W.chatHas("Unknown command"), "unknown command")
cmd("help"); ok(W.chatHas("swaps the relic") and W.chatHas("change la relique"), "help prints EN and FR")
cmd("lang fr"); cmd("on"); ok(W.chatHas("activé"), "French messages")
cmd("lang en")
W.locale = "frFR"; SS.db.lang = "auto"; cmd("on"); ok(W.chatHas("activé"), "locale frFR picks French")
W.locale = "enUS"
cmd("opener Flash of Light"); eq(SS.db.opener, "Flash of Light", "opener set"); cmd("opener off"); eq(SS.db.opener, nil, "opener off")
cmd("status")
ok(W.chatHas("combat mode"), "status command shows status")

section("auto is conservative")
fresh(); W.putBag(0, 1, ITEM.Hallowed); W.putBag(0, 2, ITEM.Faithful)
cmd("auto")
eq(SS.db.rules["Consecration"], nil, "auto does not pick Hallowed Ground when a sticky Consecration libram is also owned (real choice)")
fresh(); W.putBag(0, 1, ITEM.Hallowed)
cmd("auto")
eq(SS.db.rules["Consecration"] and SS.db.rules["Consecration"][1], "Libram of Hallowed Ground", "auto picks the only Consecration libram when it is the only one")

section("probe")
pally(); W.equip(ITEM.Hope)
cmd("probe")
ok(W.chatHas("slot changed immediately: no"), "probe reports an asynchronous client")
W.advance(0.5)
ok(W.chatHas("confirmation after"), "probe reports the confirmation delay")
eq(relicNow() ~= ITEM.Hope, true, "probe really swapped")
pally(); W.syncEquip = true; W.equip(ITEM.Hope)
cmd("probe"); ok(W.chatHas("slot changed immediately: YES"), "probe detects a synchronous client")
pally(); W.combat = true; cmd("probe"); ok(W.chatHas("only works out of combat"), "probe refuses in combat"); eq(W.logCount("UCI"), 0, "no swap by probe in combat")

-- ============================================================ 10. migration from LibramSwap (read-only)
section("migration")
local function dump(t, seen)
    if type(t) ~= "table" then return tostring(t) end
    local keys = {}
    for k in pairs(t) do keys[table.getn(keys) + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for i = 1, table.getn(keys) do
        local v
        for k, val in pairs(t) do if tostring(k) == keys[i] then v = val end end
        parts[i] = keys[i] .. "=" .. dump(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
fresh()
loadstring(FIXTURES["LibramSwap_SHIKAWA"])()
ok(type(LibramSwapDB) == "table", "fixture loaded (copy of the real WTF file)")
local before = dump(LibramSwapDB)
W.fire("PLAYER_LOGIN")   -- first run : automatic import
eq(dump(LibramSwapDB), before, "LibramSwapDB untouched by the import (read-only)")
eq(SS.nRules, 11, "11 rules imported from the active map")
eq(SS.db.rules["Seal of the Crusader"][1], "Libram of Fervor", "Seal of the Crusader -> Fervor")
eq(SS.db.rules["Flash of Light"][1], "Libram of Light", "Flash of Light -> Light")
eq(SS.db.off["Judgement"], true, "enabledMap=false imported as 'off'")
eq(SS.db.off["Holy Shock"], nil, "enabledMap=true stays active")
eq(SS.db.off["Holy Light"], true, "Holy Light was disabled in his profile")
ok(SS.db.imported, "import flagged")
local np = 0
for name in pairs(SS.db.profiles) do np = np + 1 end
eq(np, 5, "5 profiles imported (tank, test, Dps, Heal, necroladin)")
eq(SS.db.profiles["tank"].rules["Hammer of Justice"], nil, "__NONE__ entries are not imported")
eq(SS.db.profiles["necroladin"].off["Judgement"], true, "profile enabledMap imported")
ok(W.chatHas("Imported from LibramSwap: 11 rules"), "player told")
cmd("check")
ok(W.chatHas("Seal of Righteousness"), "check flags his Seal of Righteousness -> Final Judgement mistake")
-- second login does not import again
SS.db.rules = {}; SS.RebuildIndex(); SS.db.imported = true
W.fire("PLAYER_LOGIN")
eq(SS.nRules, 0, "no re-import once flagged")
cmd("import"); ok(SS.nRules == 11, "manual import works")
cmd("import"); ok(W.chatHas("already exist"), "manual import refuses to overwrite without force")
-- empty / missing / garbage
fresh(); loadstring(FIXTURES["LibramSwap_EMPTY"])()
W.fire("PLAYER_LOGIN"); eq(SS.nRules, 0, "empty old DB imports nothing")
LibramSwapDB = nil; fresh(); cmd("import"); ok(W.chatHas("No LibramSwap data"), "no old addon in memory")
LibramSwapDB = { map = { A = 5, B = "Libram of Light", C = "__NONE__", D = "Auto", [7] = "x" }, enabledMap = "bad", profiles = { p1 = "bad", p2 = { map = "bad" } } }
fresh(); cmd("import")
eq(SS.nRules, 1, "garbage old DB: only the valid entry imported")
LibramSwapDB = nil

-- ============================================================ 11. saved variable robustness
section("saved variables")
ShikaSwapDB = "garbage"; SS.InitDB(); ok(type(ShikaSwapDB) == "table" and ShikaSwapDB.combat == "auto", "non-table DB replaced")
ShikaSwapDB = { rules = { ["Holy Light"] = "Libram of Radiance", ["Bad"] = 42, ["Worse"] = { 1, 2 }, ["Empty"] = {} }, off = { x = "no" }, combat = "turbo", queueTimeout = -4, lang = "klingon", profiles = 7 }
SS.InitDB()
eq(SS.db.rules["Holy Light"][1], "Libram of Radiance", "string rule promoted to a list")
eq(SS.db.rules["Bad"], nil, "number rule dropped"); eq(SS.db.rules["Worse"], nil, "non-string list dropped"); eq(SS.db.rules["Empty"], nil, "empty list dropped")
eq(SS.db.combat, "auto", "bad mode reset"); eq(SS.db.queueTimeout, 3.0, "bad timeout reset"); eq(SS.db.lang, "auto", "bad lang reset")
eq(type(SS.db.profiles), "table", "bad profiles reset"); eq(SS.db.off.x, nil, "bad off flag dropped")

section("fail-open and SV re-binding")
pally()
local realSnap = SS.BuildSnapshot
SS.BuildSnapshot = function() error("boom") end
press("Holy Light")
SS.BuildSnapshot = realSnap
eq(W.castCount("Holy Light"), 1, "internal error : the cast still leaves (fail-open)")
eq(SS.stats.errors, 1, "error counted")
ok(SS.lastError ~= nil, "error remembered for /ssw status")
SS.lastError = nil
-- the client assigns the real saved table AFTER ADDON_LOADED/VARIABLES_LOADED may have created one
ShikaSwapDB = nil
W.fire("ADDON_LOADED", "ShikaSwap")
local early = ShikaSwapDB
ShikaSwapDB = { rules = { ["Holy Light"] = { "Libram of Radiance" } }, combat = "wait" }   -- what the client loads
W.fire("VARIABLES_LOADED")
ok(SS.db == ShikaSwapDB and SS.db ~= early, "VARIABLES_LOADED re-binds to the loaded table")
eq(SS.db.combat, "wait", "saved value kept")
ShikaSwapDB = { rules = { ["Flash of Light"] = { "Libram of Light" } } }
W.fire("PLAYER_LOGIN")
ok(SS.db == ShikaSwapDB and SS.hasRules and SS.lc["flash of light"], "PLAYER_LOGIN re-binds too")

-- ============================================================ 12. API-absence tolerance
section("optional APIs absent")
pally()
local saved = { GetContainerItemInfo = GetContainerItemInfo, UnitCanAttack = UnitCanAttack, CursorHasItem = CursorHasItem, HasAction = HasAction, UnitClass = UnitClass }
GetContainerItemInfo = nil; UnitCanAttack = nil; CursorHasItem = nil
local okp, err = pcall(press, "Holy Light")
ok(okp, "no error when GetContainerItemInfo / UnitCanAttack / CursorHasItem are missing: " .. tostring(err))
eq(W.logCount("UCI 0 1"), 1, "still swaps")
GetContainerItemInfo = saved.GetContainerItemInfo; UnitCanAttack = saved.UnitCanAttack; CursorHasItem = saved.CursorHasItem
okp, err = pcall(function() SS.OnEvent("UI_ERROR_MESSAGE", nil) end)
ok(okp, "nil error message tolerated")
okp, err = pcall(function() SS.OnEvent("SPELLCAST_START", nil, nil) end)
ok(okp, "SPELLCAST_START without args tolerated")

print(string.format("RESULT: %d passed, %d failed", PASSES, FAILS))
if FAILS > 0 then error("TESTS FAILED: " .. FAILS) end
