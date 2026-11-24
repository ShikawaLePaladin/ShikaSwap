-- tests_v13.lua : 1.3.0 = persistent swap trace (ShikaSwapDB.trace_log), off-GCD policy (Judgement), queue not cancelled by off-GCD presses,
-- `check` warnings, schema 4 migration, menu additions.   node harness_shikaswap.js tests_v13.lua
local FAILS, PASSES = 0, 0
local function ok(cond, msg)
    if cond then PASSES = PASSES + 1 else FAILS = FAILS + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
    if a == b then PASSES = PASSES + 1 else FAILS = FAILS + 1; print("FAIL: " .. msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
end
local function section(s) print("-- " .. s) end

local SS = ShikaSwap
local UI = SS.UI

local function fresh()
    W.reset()
    ShikaSwapDB = nil
    SS.stats = {}; SS.ring = {}; SS.ringN = 0; SS.queue = nil; SS.pending = nil; SS.probe = nil; SS.consecFail = 0; SS.verify = nil
    SS.castUntil = nil; SS.chanUntil = nil; SS.bagDirty = true; SS.book = nil; SS.conflict = false; SS.openerAt = nil
    SS.lastSwap = nil; SS.bagIdx = nil; SS.lastSwapCombat = nil; SS.alerted = {}; SS.sink = nil; SS.specPending = nil; SS.tlKey = nil
    UI.confirmId = nil; UI.page = 1; UI.diagLines = {}
    UnitClass = function() return "Paladin", "PALADIN" end
    SS.InitDB()
    SS.frame:Hide()
    W.setBook({ { name = "Holy Shock", rank = "Rank 4" }, { name = "Seal of the Crusader", rank = "Rank 6" }, { name = "Seal of Righteousness", rank = "Rank 8" },
        { name = "Crusader Strike", rank = "Rank 5" }, { name = "Judgement", rank = "" }, { name = "Consecration", rank = "Rank 1" } })
    W.noGcd = { Judgement = true }
end
local function cmd(s) W.chat = {}; local okc, err = pcall(SlashCmdList["SHIKASWAP"], s); if not okc then print("CMD ERROR " .. s .. ": " .. tostring(err)); FAILS = FAILS + 1 end end
local function necro()
    fresh()
    local p = SS.NecroPreset(); SS.ApplyRules(p.rules, p.off)
    SS.db.off["Holy Shock"] = nil   -- Holy Shock est desactive par defaut dans le preset (2026-11-19) : ces scenarios le veulent actif
    W.putBag(0, 1, ITEM.RadiantDawn); W.putBag(0, 2, ITEM.Fervor); W.putBag(0, 3, ITEM.FinalJ)
    W.equip(ITEM.RadiantDawn)
end
local function press(s) CastSpellByName(s) end
local function lines() return SS.TraceLines() end
local function count(tag)
    local n = 0
    local l = lines()
    for i = 1, table.getn(l) do if string.find(l[i], " " .. tag .. " ", 1, true) then n = n + 1 end end
    return n
end
local function has(sub)
    local l = lines()
    for i = 1, table.getn(l) do if string.find(l[i], sub, 1, true) then return l[i] end end
    return nil
end
local function click(w, b) this = w; arg1 = b; local okc, err = pcall(w.scripts.OnClick); this = nil; arg1 = nil; if not okc then FAILS = FAILS + 1; print("CLICK ERROR " .. tostring(err)) end end
local function def(list, id) for i = 1, table.getn(list) do if list[i].id == id then return list[i] end end end

-- ============================================================ 1. trace : activation
section("trace activation")
fresh()
ok(SS.db.traceUntil and math.abs(SS.db.traceUntil - (time() + 604800)) < 5, "armed for one week on a new install")
ok(SS.TraceActive(), "active by default")
W.now = W.now + 8 * 86400; ok(not SS.TraceActive(), "silent after the week")
local n0 = table.getn(lines()); SS.TL("X", "after the week"); eq(table.getn(lines()), n0, "nothing written when silent")
cmd("trace on"); ok(SS.TraceActive() and SS.db.trace == true, "/ssw trace on = until switched off"); ok(W.chatHas("ON"), "message")
W.now = W.now + 30 * 86400; ok(SS.TraceActive(), "still on a month later")
cmd("trace off"); ok(not SS.TraceActive() and SS.db.trace == false, "/ssw trace off"); eq(SS.db.traceUntil, 0, "week cancelled")
cmd("trace week"); ok(SS.TraceActive(), "/ssw trace week re-arms"); ok(W.chatHas("one week"), "message with the end date")
cmd("trace"); ok(W.chatHas("Persistent trace"), "status")
SS.TL("T", "one line"); ok(table.getn(lines()) == 1, "one line stored"); cmd("trace clear"); eq(table.getn(lines()), 0, "/ssw trace clear"); ok(W.chatHas("cleared"), "message")
cmd("tracelog"); ok(W.chatHas("empty"), "empty log message")
-- the in-memory ring (log) still follows db.trace as before
fresh(); SS.db.trace = true; SS.Dbg("hello"); eq(SS.ringN, 1, "in-memory debug ring unchanged")

-- ============================================================ 2. ring buffer and merging
section("trace ring")
fresh()
for i = 1, 250 do SS.TL("T", "line number ", i) end
local l = lines()
eq(table.getn(l), 100, "ring keeps 100 lines")
ok(string.find(l[1], "line number 151", 1, true), "oldest line is 151"); ok(string.find(l[100], "line number 250", 1, true), "newest line is 250")
eq(table.getn(SS.db.trace_log), 100, "stored as a plain array in the saved variable"); ok(SS.db.trace_n >= 1 and SS.db.trace_n <= 100, "write pointer")
for i = 1, 100 do if type(SS.db.trace_log[i]) ~= "string" then FAILS = FAILS + 1; print("FAIL: non string line " .. i) end end
fresh(); SS.TL("T", "same"); SS.TL("T", "same"); SS.TL("T", "same")
eq(table.getn(lines()), 1, "identical lines within 2 s are merged"); ok(string.find(lines()[1], "(x3)", 1, true), "with a counter")
W.advance(3); SS.TL("T", "same"); eq(table.getn(lines()), 2, "a later identical line is a new line")
SS.TL("T", "other"); SS.TL("T", "same"); eq(table.getn(lines()), 4, "interleaved lines are not merged")
ok(string.find(lines()[1], "^%d%d:%d%d:%d%d g=%d+%.%d%d%d T same"), "line format : time of day, GetTime, tag, text")
eq(string.len(string.rep("x", 400)), 400, "sanity"); SS.TL("T", string.rep("x", 400)); ok(string.len(lines()[table.getn(lines())]) < 260, "long lines are cut")
local gt = GetTime; GetTime = function() error("boom") end; ok(pcall(SS.TL, "T", "x"), "a failing clock never raises"); GetTime = gt
local dt = date; date = function() error("boom") end; ok(pcall(SS.TL, "T", "y"), "a failing date() never raises"); date = dt
ok(SS.TraceRaw ~= nil, "raw writer exists")

-- ============================================================ 3. what a swap leaves in the trace
section("trace of a swap")
necro(); SS.db.combat = "burst"
cmd("trace clear")
W.fire("PLAYER_REGEN_DISABLED"); W.combat = true
press("Seal of the Crusader"); W.advance(1.0)
ok(has("COMBAT start relic=Libram of the Radiant Dawn"), "combat start with the relic worn")
local pl = has("PLAN spell=Seal of the Crusader src=byname act=swap"); ok(pl ~= nil, "decision line")
ok(has("EQUIP spell=Seal of the Crusader want=Libram of Fervor before=Libram of the Radiant Dawn bag=0/2 combat=1"), "EQUIP: spell, wanted relic, relic before, bag slot, combat")
ok(has("ctx want=Libram of Fervor eq=Libram of the Radiant Dawn combat=1 gcdRem=0.00 mode=burst"), "context line: mode and GCD remaining")
ok(has("CAST spell=Seal of the Crusader sent in the same frame"), "cast line")
local cf = has("CONFIRM equipped=Libram of Fervor"); ok(cf ~= nil, "server confirmation"); ok(cf and string.find(cf, "ms after the swap", 1, true), "with the delay")
ok(has("VERIFY-OK spell=Seal of the Crusader wanted=Libram of Fervor equipped=Libram of Fervor"), "verification 0.7 s after the cast")
local order = {}
for i = 1, table.getn(lines()) do
    local s = lines()[i]
    if string.find(s, " EQUIP ", 1, true) then order.equip = i end
    if string.find(s, " CAST ", 1, true) then order.cast = i end
    if string.find(s, " CONFIRM ", 1, true) then order.confirm = i end
    if string.find(s, " VERIFY-OK ", 1, true) then order.verify = i end
end
ok(order.equip < order.cast and order.cast < order.confirm and order.confirm < order.verify, "events are in the order EQUIP, CAST, CONFIRM, VERIFY")
W.fire("PLAYER_REGEN_ENABLED"); ok(has("COMBAT end"), "combat end")
-- already equipped : nothing written
local before = table.getn(lines()); W.advance(2); press("Seal of the Crusader"); W.advance(0.3)
eq(table.getn(lines()), before, "'already equipped' decisions are not written")
-- out of combat swap
W.combat = false; cmd("trace clear"); press("Holy Shock"); W.advance(1)
ok(has("EQUIP spell=Holy Shock want=Libram of the Radiant Dawn before=Libram of Fervor bag=0/1 combat=0"), "free swap traced with combat=0")
-- verification failure : the client never gets the relic
necro(); SS.db.combat = "burst"; cmd("trace clear"); W.combat = true
local ucs = UseContainerItem; UseContainerItem = function() end
press("Seal of the Crusader"); W.advance(1.0)
ok(has("VERIFY-BAD spell=Seal of the Crusader wanted=Libram of Fervor equipped=Libram of the Radiant Dawn"), "VERIFY-BAD when the relic did not change")
W.advance(2); press("Seal of the Crusader")
ok(has("UNCONFIRMED wanted=Libram of Fervor equipped=Libram of the Radiant Dawn"), "UNCONFIRMED swap noticed at the next decision")
UseContainerItem = ucs
-- decisions that block a swap are written
necro(); cmd("trace clear"); W.combat = true; W.showWindow("MerchantFrame"); press("Seal of the Crusader")
ok(has("PASS spell=Seal of the Crusader src=byname act=pass why=window open: MerchantFrame"), "PASS with the reason"); W.hideWindow("MerchantFrame")
W.cursor = true; press("Seal of the Crusader"); ok(has("why=item on cursor"), "cursor"); W.cursor = false
W.dead = true; press("Seal of the Crusader"); ok(has("why=dead"), "dead"); W.dead = false
SS.db.combat = "skip"; press("Seal of the Crusader"); ok(has("why=combat mode skip"), "mode skip"); SS.db.combat = "burst"
W.combat = false; SS.db.off["Seal of the Crusader"] = true; local nn = table.getn(lines()); press("Seal of the Crusader"); eq(table.getn(lines()), nn, "'rule switched off' not written"); SS.db.off["Seal of the Crusader"] = nil
-- bag slot changed under us
necro(); cmd("trace clear"); W.combat = true; SS.bagDirty = false; SS.bagIdx = nil; SS.ScanBags(); W.cbags[0][2] = nil; W.sbags[0][2] = nil
press("Seal of the Crusader"); W.advance(0.5)
ok(has("PASS spell=Seal of the Crusader") or has("EQUIP-REFUSED"), "missing relic is traced")
-- internal error
necro(); cmd("trace clear"); local rs = SS.BuildSnapshot; SS.BuildSnapshot = function() error("boom") end; press("Holy Shock"); SS.BuildSnapshot = rs
ok(has("ERROR spell=Holy Shock"), "internal error traced"); eq(W.castCount("Holy Shock"), 1, "cast still leaves"); SS.lastError = nil
-- session line
fresh(); W.fire("PLAYER_LOGIN"); ok(has("SESSION login v" .. SS.version), "session line at login"); ok(has("offgcd=swap"), "with the settings")

-- ============================================================ 4. deferral, queue and off-GCD presses
section("deferral")
necro(); SS.db.combat = "burst"; cmd("trace clear"); W.combat = true; W.realCd = {}
-- Fervor is worn, the GCD is running : Holy Shock must wait for the GCD then swap + cast
W.cinv[18] = ITEM.Fervor; W.sinv[18] = ITEM.Fervor; W.cbags[0][2] = ITEM.RadiantDawn; W.sbags[0][2] = ITEM.RadiantDawn; SS.bagDirty = true
press("Crusader Strike"); W.advance(0.4)
press("Holy Shock"); eq(W.castCount("Holy Shock"), 0, "Holy Shock deferred during the GCD")
ok(has("DEFER spell=Holy Shock until the GCD ends"), "DEFER line")
W.advance(1.5)
local df = has("DEFER-FIRE spell=Holy Shock waited"); ok(df ~= nil, "DEFER-FIRE line"); eq(W.castCount("Holy Shock"), 1, "Holy Shock cast once the GCD ended")
eq(W.casts[table.getn(W.casts)].name, "Holy Shock", "last cast"); W.advance(0.3); eq(W.casts[table.getn(W.casts)].relic, ITEM.RadiantDawn, "with the right relic on the server")
ok(has("EQUIP spell=Holy Shock want=Libram of the Radiant Dawn before=Libram of Fervor"), "EQUIP after the deferral")
-- a spell WITHOUT GCD (Judgement) does not cancel the queued cast
W.advance(2); W.cinv[18] = ITEM.Fervor; W.sinv[18] = ITEM.Fervor; W.cbags[0][1] = ITEM.RadiantDawn; W.sbags[0][1] = ITEM.RadiantDawn; SS.bagDirty = true
SS.db.rules["Judgement"] = { "Libram of Final Judgement" }; SS.db.off["Judgement"] = true; SS.RebuildIndex()
W.casts = {}; cmd("trace clear")
press("Crusader Strike"); W.advance(0.4); W.spellCd = {}
press("Holy Shock"); ok(SS.queue ~= nil, "Holy Shock queued")
press("Judgement"); ok(SS.queue ~= nil and SS.queue.spell == "Holy Shock", "Judgement (no GCD) leaves the queued Holy Shock alone")
W.advance(1.5); eq(W.castCount("Holy Shock"), 1, "the queued Holy Shock still leaves"); eq(W.castCount("Judgement"), 1, "and Judgement was cast on top")
ok(not has("QCLEAR spell=Holy Shock"), "no QCLEAR line")
-- a spell with a GCD does cancel it (the player moved on) and says why
W.advance(2); W.cinv[18] = ITEM.Fervor; W.sinv[18] = ITEM.Fervor; W.cbags[0][1] = ITEM.RadiantDawn; W.sbags[0][1] = ITEM.RadiantDawn; SS.bagDirty = true; W.spellCd = {}
cmd("trace clear"); press("Crusader Strike"); W.advance(0.4); press("Holy Shock"); press("Consecration")
ok(SS.queue == nil, "a GCD spell pressed meanwhile cancels the queue"); ok(has("QCLEAR spell=Holy Shock kind=swapcast"), "QCLEAR traced"); ok(has("another spell was pressed (Consecration)") or has("superseded by Consecration"), "with the reason")
-- hooks for CastSpell / UseAction keep their own behaviour
ok(SS.IsOffGcd("Judgement") and SS.IsOffGcd("judgement") and not SS.IsOffGcd("Holy Shock") and not SS.IsOffGcd(nil), "IsOffGcd")
-- the same press by book index and by action button
necro(); W.combat = true; W.cinv[18] = ITEM.Fervor; W.sinv[18] = ITEM.Fervor; W.cbags[0][2] = ITEM.RadiantDawn; W.sbags[0][2] = ITEM.RadiantDawn; SS.bagDirty = true
press("Crusader Strike"); W.advance(0.4); press("Holy Shock")
CastSpell(5, "spell")   -- Judgement is book entry 5 : off-GCD, the queue stays
ok(SS.queue ~= nil, "CastSpell(Judgement) does not cancel the queue either")

-- ============================================================ 5. off-GCD policy
section("off-GCD policy")
necro(); SS.db.combat = "burst"; SS.db.rules["Judgement"] = { "Libram of Final Judgement" }; SS.db.off["Judgement"] = nil; SS.RebuildIndex()
eq(SS.db.offGcd, "swap", "default unchanged : swap")
W.tgt = { hp = 20, max = 100 }; W.combat = true; cmd("trace clear")
press("Judgement"); W.advance(0.3); eq(W.sinv[18], ITEM.FinalJ, "default : Judgement swaps to Final Judgement (target under 35 %)")
necro(); SS.db.rules["Judgement"] = { "Libram of Final Judgement" }; SS.db.off["Judgement"] = nil; SS.RebuildIndex(); W.tgt = { hp = 20, max = 100 }; W.combat = true
cmd("offgcd skip"); eq(SS.db.offGcd, "skip", "option set"); ok(W.chatHas("skip"), "message")
cmd("trace clear"); press("Judgement"); W.advance(0.3)
eq(W.sinv[18], ITEM.RadiantDawn, "skip : no swap in combat for Judgement"); eq(W.castCount("Judgement"), 1, "Judgement still cast")
ok(has("why=off-GCD spell: no swap in combat"), "reason traced")
W.combat = false; press("Judgement"); W.advance(0.3); eq(W.sinv[18], ITEM.FinalJ, "skip : out of combat the swap is free and still happens")
necro(); SS.db.offGcd = "skip"; SS.db.rules["Judgement"] = { "Libram of Final Judgement" }; SS.db.off["Judgement"] = nil; SS.RebuildIndex(); W.tgt = { hp = 20, max = 100 }; W.combat = true
cmd("next Judgement"); W.advance(0.3); eq(W.sinv[18], ITEM.FinalJ, "an explicit /ssw next Judgement still swaps")
-- other GCD spells are never affected
necro(); SS.db.offGcd = "skip"; W.combat = true; press("Seal of the Crusader"); W.advance(0.3); eq(W.sinv[18], ITEM.Fervor, "skip does not touch spells that use the GCD")
cmd("offgcd swap"); eq(SS.db.offGcd, "swap", "back to swap"); cmd("offgcd bogus"); ok(W.chatHas("Usage"), "usage"); eq(SS.db.offGcd, "swap", "unchanged by a bad argument")
-- an off-GCD spell that needs its own swap replaces the queued GCD cast
necro(); SS.db.combat = "burst"; SS.db.rules["Judgement"] = { "Libram of Final Judgement" }; SS.db.off["Judgement"] = nil; SS.RebuildIndex(); W.tgt = { hp = 20, max = 100 }; W.combat = true
W.cinv[18] = ITEM.Fervor; W.sinv[18] = ITEM.Fervor; W.cbags[0][2] = ITEM.RadiantDawn; W.sbags[0][2] = ITEM.RadiantDawn; SS.bagDirty = true; cmd("trace clear")
press("Crusader Strike"); W.advance(0.4); press("Holy Shock"); press("Judgement")
ok(SS.queue == nil, "Judgement that needs a swap supersedes the queued Holy Shock (default behaviour)"); ok(has("superseded by Judgement"), "traced")
-- menu
necro(); cmd("menu"); UI.SetTab(2); local box = def(UI.CHECKS, "offgcd").widget
box:SetChecked(1); click(box); eq(SS.db.offGcd, "skip", "menu check box = /ssw offgcd skip"); box:SetChecked(nil); click(box); eq(SS.db.offGcd, "swap", "and back")
ok(SS.M.en.ui_t_offgcd ~= nil and SS.M.fr.ui_t_offgcd ~= nil, "texts")
UI.SetTab(5)
local tl = def(UI.BUTTONS, "dtl").widget; ok(string.find(tl.text, "ON", 1, true), "trace button shows ON (armed)")
click(tl); eq(SS.TraceActive(), false, "trace button switches it off"); ok(string.find(tl.text, "OFF", 1, true), "label follows"); click(tl); eq(SS.TraceActive(), true, "and on")
SS.TL("T", "visible in the menu"); click(def(UI.BUTTONS, "dtlshow").widget); ok(string.find(UI.tabs[5].out.text, "visible in the menu", 1, true), "show button prints the stored trace in the view")
click(def(UI.BUTTONS, "dtlclear").widget); ok(table.getn(lines()) > 0, "clear needs a second click"); click(def(UI.BUTTONS, "dtlclear").widget); eq(table.getn(lines()), 0, "second click clears")
for _, id in ipairs({ "dtl", "dtlshow", "dtlclear" }) do ok(SS.M.en[def(UI.BUTTONS, id).tip] ~= nil and SS.M.fr[def(UI.BUTTONS, id).tip] ~= nil, "tooltip text for " .. id) end
UI.frame:Hide()

-- ============================================================ 6. check : warnings
section("check")
necro(); SS.db.off["Judgement"] = nil; SS.db.off["Seal of Righteousness"] = nil; SS.RebuildIndex()
cmd("check"); ok(W.chatHas("Libram of Fervor") and W.chatHas("Judgement of the Crusader"), "Fervor + active Judgement rule is flagged")
ok(W.chatHas("does not improve Seal of Righteousness") or W.chatHas("Libram of Final Judgement"), "the absurd Seal of Righteousness -> Final Judgement rule is still flagged")
necro(); cmd("check"); ok(not W.chatHas("Judgement of the Crusader loses"), "no Fervor warning while the Judgement rule is off")
necro(); SS.db.rules["Holy Strike"] = { "Libram of the Eternal Tower" }; SS.db.off["Holy Strike"] = nil; SS.RebuildIndex(); cmd("check")
ok(W.chatHas("Libram of the Eternal Tower also improves Crusader Strike"), "hint : Eternal Tower also improves Crusader Strike")
SS.db.lang = "fr"; cmd("check"); ok(W.chatHas("améliore aussi Crusader Strike"), "hint in French"); SS.db.lang = "auto"

-- ============================================================ 7. schema 3 -> 4
section("migration 1.2.0 -> 1.3.0")
local v120 = { version = 3, enabled = true, combat = "burst", rules = { ["Holy Shock"] = { "Libram of the Radiant Dawn" } }, off = {}, autoSpec = true, lastSpec = "NECRO",
    necroTol = 3, necroSig = { HOLY = 31, PROT = 8, RET = 11 }, specProfiles = { NECRO = { rules = { Judgement = { "Libram of Final Judgement" } }, off = { Judgement = true } } },
    minimap = { show = true, angle = 10 }, indicator = { show = true, locked = false, scale = 1.2 }, alert = { chat = true, sound = false }, ui = { tab = 3 }, trace = false, queueTimeout = 3 }
ShikaSwapDB = v120; SS.InitDB()
eq(SS.db.version, 4, "schema 4"); eq(SS.db.combat, "burst", "mode kept"); eq(SS.db.necroTol, 3, "tolerance kept"); eq(SS.db.necroSig.HOLY, 31, "signature kept")
ok(SS.db.specProfiles.NECRO.rules.Judgement ~= nil, "edited Necroladin slot kept"); eq(SS.db.lastSpec, "NECRO", "last spec kept"); eq(SS.db.ui.tab, 3, "window state kept")
eq(SS.db.offGcd, "swap", "off-GCD policy defaults to the old behaviour"); ok(SS.TraceActive() and math.abs(SS.db.traceUntil - (time() + 604800)) < 5, "trace armed for one week")
eq(table.getn(SS.TraceLines()), 0, "empty trace"); eq(SS.db.trace_n, 0, "pointer")
ShikaSwapDB = { version = 4, offGcd = "weird", traceUntil = "x", trace_n = 500, trace_log = { "a", 5, {}, "b", [150] = "far" } }; SS.InitDB()
eq(SS.db.offGcd, "swap", "bad policy reset"); ok(type(SS.db.traceUntil) == "number", "bad traceUntil re-armed"); eq(SS.db.trace_n, 0, "pointer out of range reset")
eq(SS.db.trace_log[1], "a", "valid lines kept"); eq(SS.db.trace_log[2], nil, "non string line dropped"); eq(SS.db.trace_log[4], "b", "valid line kept"); eq(SS.db.trace_log[150], nil, "entry outside the ring dropped")
ok(pcall(SS.TraceLines), "reading a log with holes is safe")
ShikaSwapDB = { version = 4, trace_log = "garbage" }; SS.InitDB(); eq(type(SS.db.trace_log), "table", "garbage log replaced")
ShikaSwapDB = { version = 4, traceUntil = 0 }; SS.InitDB(); ok(not SS.TraceActive(), "a deliberately silenced trace stays silent after a reload")
-- defaults reset keeps the trace settings choice but the policy goes back
necro(); SS.db.offGcd = "skip"; SS.ResetSettings(); eq(SS.db.offGcd, "swap", "reset restores the default policy")

-- ============================================================ 8. the Necroladin cycle with the trace on (integration)
section("integration")
for _, mode in ipairs({ "auto", "burst", "wait" }) do
    necro(); SS.db.combat = mode; W.nampower = true; W.npWindow = 0.5
    W.setBook({ { name = "Holy Shock", rank = "Rank 4" }, { name = "Seal of the Crusader", rank = "Rank 6" }, { name = "Seal of Righteousness", rank = "Rank 8" },
        { name = "Crusader Strike", rank = "Rank 5" }, { name = "Judgement", rank = "" } })
    W.realCd = { ["Holy Shock"] = 3.0, ["Crusader Strike"] = 6.0, Judgement = 10.0 }
    cmd("trace clear"); W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
    local seal, lastSotc, nC = "SoR", -99, 0
    local function idx(name) for i = 1, table.getn(W.book) do if W.book[i].name == name then return i end end end
    local function ready(name, w) local s, d = GetSpellCooldown(idx(name), "spell"); if not s or s == 0 then return true end return s + d - W.now <= w end
    local function real(name) local c = W.spellCd[name]; return not (c and c.start + c.dur > W.now) end
    while W.now < 1000 + 40 do
        W.advance(0.1)
        for i = nC + 1, table.getn(W.casts) do
            local c = W.casts[i]
            if c.name == "Seal of the Crusader" then seal = "SotC"; lastSotc = c.at elseif c.name == "Seal of Righteousness" then seal = "SoR" elseif c.name == "Judgement" and seal == "SotC" then seal = "none" end
        end
        nC = table.getn(W.casts)
        if seal == "SoR" and W.now - lastSotc >= 12 and ready("Seal of the Crusader", 0.3) then press("Seal of the Crusader")
        elseif seal == "SotC" and real("Judgement") then press("Judgement")
        elseif seal == "none" and ready("Seal of Righteousness", 0.3) then press("Seal of Righteousness")
        elseif real("Holy Shock") and ready("Holy Shock", 0.3) then press("Holy Shock")
        elseif real("Crusader Strike") and ready("Crusader Strike", 0.3) then press("Crusader Strike") end
    end
    W.advance(2)
    local bad = 0
    for _, c in ipairs(W.casts) do
        if c.name == "Holy Shock" and c.relic ~= ITEM.RadiantDawn then bad = bad + 1 end
        if c.name == "Seal of the Crusader" and c.relic ~= ITEM.Fervor then bad = bad + 1 end
    end
    eq(bad, 0, mode .. " : every Holy Shock / Seal of the Crusader left with the right libram")
    local swaps = (SS.stats.swapsCombat or 0) + (SS.stats.swapsFree or 0)
    ok(table.getn(lines()) < 100, mode .. " : the 40 s fit in the ring (" .. table.getn(lines()) .. " lines)")
    ok(swaps >= 5, mode .. " : the cycle really swaps (" .. swaps .. ")")
    eq(count("EQUIP"), swaps, mode .. " : one EQUIP line per swap")
    eq(count("CONFIRM"), swaps, mode .. " : every swap confirmed by the server")
    eq(count("VERIFY-BAD"), 0, mode .. " : no failed verification")
    eq(count("UNCONFIRMED"), 0, mode .. " : no unconfirmed swap")
    ok(table.getn(lines()) <= 100, mode .. " : trace stays within 100 lines")
end

-- ============================================================ 9. persistent counters
section("counters")
necro(); W.combat = true; W.showWindow("MerchantFrame"); press("Seal of the Crusader"); W.hideWindow("MerchantFrame")
eq(SS.db.counts["pass: window open"], 1, "the reason why a swap did not happen is counted in the saved variables (variable part removed)")
SS.db.combat = "burst"; press("Seal of the Crusader"); W.advance(2); eq(SS.db.counts.swapsCombat, 1, "swaps counted for all sessions")
SS.stats = {}; eq(SS.db.counts.swapsCombat, 1, "session reset does not erase the stored counters"); cmd("status"); cmd("reset"); eq(next(SS.db.counts), nil, "/ssw reset clears them")
necro(); W.combat = true; W.cursor = true; press("Seal of the Crusader"); W.cursor = false; cmd("status"); ok(W.chatHas("no swap because: pass: item on cursor") == false and W.chatHas("no swap because: item on cursor=1"), "/ssw status lists the reasons")
ShikaSwapDB = { version = 4, counts = { ok = 3, bad = "x", [5] = 1, neg = -2 } }; SS.InitDB(); eq(SS.db.counts.ok, 3, "valid counter kept"); eq(SS.db.counts.bad, nil, "garbage counter dropped"); eq(SS.db.counts.neg, nil, "negative counter dropped")

print(string.format("RESULT: %d passed, %d failed", PASSES, FAILS))
if FAILS > 0 then error("TESTS FAILED: " .. FAILS) end
