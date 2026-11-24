-- tests_v12.lua : 1.2.0 = Necroladin slot + talent signature, profile bar, dark/gold theme, icons with fallbacks, schema 3 migration.
--   node harness_shikaswap.js tests_v12.lua
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
    SS.stats = {}; SS.ring = {}; SS.ringN = 0; SS.queue = nil; SS.pending = nil; SS.probe = nil; SS.consecFail = 0
    SS.castUntil = nil; SS.chanUntil = nil; SS.bagDirty = true; SS.book = nil; SS.conflict = false; SS.openerAt = nil
    SS.lastSwap = nil; SS.bagIdx = nil; SS.lastSwapCombat = nil; SS.alerted = {}; SS.sink = nil; SS.specPending = nil
    UI.confirmId = nil; UI.page = 1; UI.diagLines = {}; UI.shareMsg = nil; UI.profIdx = 1; UI.texCache = nil
    UnitClass = function() return "Paladin", "PALADIN" end
    SS.InitDB()
    SS.frame:Hide()
    if SS.mmButton then SS.ApplyDisplay() end
end
local function cmd(s) W.chat = {}; local okc, err = pcall(SlashCmdList["SHIKASWAP"], s); if not okc then print("CMD ERROR " .. s .. ": " .. tostring(err)); FAILS = FAILS + 1 end end
local function click(w, button)
    this = w; arg1 = button
    local okc, err = pcall(w.scripts.OnClick)
    this = nil; arg1 = nil
    if not okc then FAILS = FAILS + 1; print("CLICK ERROR: " .. tostring(err)) end
end
local function def(list, id) for i = 1, table.getn(list) do if list[i].id == id then return list[i] end end end
local function btn(id) return def(UI.BUTTONS, id).widget end
local function open() if UI.frame and UI.frame:IsShown() then UI.Refresh() else cmd("menu") end return UI.frame end
local function press(spell) CastSpellByName(spell) end
local function rulesOf(spell) local k = SS.lc[string.lower(spell)]; return k and SS.db.rules[k] end
local function hasText(w, sub) return w.text ~= nil and string.find(w.text, sub, 1, true) ~= nil end
local function talents(h, p, r)
    W.talents = { { name = "Holy", pts = h }, { name = "Protection", pts = p }, { name = "Retribution", pts = r } }
end
local function rowOf(spell)
    for i = 1, UI.ROWS do if UI.view[(UI.page - 1) * UI.ROWS + i] == spell then return UI.rows[i], i end end
    return nil
end

-- ============================================================ 1. Necroladin preset
section("necroladin preset")
fresh()
ok(SS.db.specProfiles.NECRO ~= nil, "the Necroladin slot exists on a new install (preset)")
eq(SS.SPEC_ORDER[4], "NECRO", "4th slot after Holy / Protection / Retribution")
eq(SS.SpecName("NECRO"), "Necroladin", "slot name")
-- the preset equals the user's old LibramSwap profile (read from the real SavedVariables copy)
loadstring(FIXTURES["LibramSwap_SHIKAWA"])()
local old = LibramSwapDB.profiles.necroladin
local rules, off, n = SS.ConvertOldMap(old.map, old.enabledMap)
LibramSwapDB = nil
local pre = SS.NecroPreset()
local cnt = 0
for spell, list in pairs(rules) do
    cnt = cnt + 1
    eq(pre.rules[spell] and pre.rules[spell][1], list[1], "preset relic for " .. spell .. " == old profile")
    if spell ~= "Holy Shock" then eq(pre.off[spell], off[spell], "preset on/off for " .. spell .. " == old profile") end   -- Holy Shock : desactive par defaut depuis 2026-11-19 (voulu)
end
eq(cnt, 11, "11 rules in the old profile"); local pc = 0; for _ in pairs(pre.rules) do pc = pc + 1 end; eq(pc, 11, "11 rules in the preset (none added, none lost)")
local active = {}
for spell in pairs(pre.rules) do if not pre.off[spell] then active[table.getn(active) + 1] = spell end end
table.sort(active); eq(table.concat(active, ","), "Seal of the Crusader", "only Seal of the Crusader is active (Holy Shock off by default since 2026-11-19)")
eq(pre.rules["Holy Shock"][1], "Libram of the Radiant Dawn", "Holy Shock -> Radiant Dawn"); eq(pre.rules["Seal of the Crusader"][1], "Libram of Fervor", "Seal of the Crusader -> Fervor")
eq(pre.rules["Judgement"][1], "Libram of Final Judgement", "Judgement kept, off"); eq(pre.rules["Seal of Righteousness"][1], "Libram of Final Judgement", "Seal of Righteousness kept, off")
eq(pre.rules["Holy Strike"][1], "Libram of the Eternal Tower", "Holy Strike kept"); eq(pre.rules["Consecration"][1], "Libram of the Faithful", "Consecration kept"); eq(pre.rules["Holy Light"][1], "Libram of Radiance", "Holy Light kept")
for spell, list in pairs(pre.rules) do ok(SS.Relics()[list[1]] ~= nil, "preset relic exists in the catalogue: " .. list[1]) end
local p1, p2 = SS.NecroPreset(), SS.NecroPreset(); p1.rules["Holy Shock"][1] = "x"; eq(p2.rules["Holy Shock"][1], "Libram of the Radiant Dawn", "each call returns a fresh copy")
-- loading it
fresh(); W.putBag(0, 1, ITEM.RadiantDawn); W.putBag(0, 2, ITEM.Fervor); W.putBag(0, 3, ITEM.Radiance); W.equip(ITEM.Hope)
SS.SetRule("Hammer of Justice", { "Libram of the Justicar" }); SS.db.combat = "wait"
cmd("spec load necro"); ok(W.chatHas("Necroladin"), "load message"); eq(SS.db.lastSpec, "NECRO", "Necroladin is the profile in use")
eq(SS.db.combat, "wait", "loading Necroladin does not change the combat mode (no forced burst)")
eq(rulesOf("Hammer of Justice"), nil, "previous rules replaced"); eq(rulesOf("Holy Shock")[1], "Libram of the Radiant Dawn", "Holy Shock rule loaded")
eq(SS.db.off["Holy Light"], true, "Holy Light present but off"); eq(SS.db.off["Holy Shock"], true, "Holy Shock off by default (2026-11-19)"); SS.db.off["Holy Shock"] = nil
W.fire("PLAYER_REGEN_ENABLED")
press("Holy Shock"); W.advance(0.3); eq(W.sinv[18], ITEM.RadiantDawn, "Holy Shock swaps to Radiant Dawn")
press("Seal of the Crusader"); W.advance(2); eq(W.sinv[18], ITEM.Fervor, "Seal of the Crusader swaps to Fervor")
local uci = W.logCount("UCI"); press("Holy Light"); W.advance(0.3); eq(W.logCount("UCI"), uci, "Holy Light rule is present but off : no swap")
eq(W.castCount("Holy Light"), 1, "and the spell still casts")
cmd("undo"); ok(rulesOf("Hammer of Justice") ~= nil, "undo brings the previous rules back")
-- editable like the other slots, reset = preset
fresh(); SS.SetRule("Holy Strike", { "Libram of the Eternal Tower" }); cmd("spec save necro")
ok(SS.db.specProfiles.NECRO.rules["Holy Strike"] ~= nil and not SS.db.specProfiles.NECRO.rules["Holy Shock"], "slot saved from the current rules (editable)")
eq(SS.SlotIsPreset("NECRO"), false, "slot reports 'edited'")
cmd("spec necro reset"); eq(SS.SlotIsPreset("NECRO"), true, "reset = back to the preset"); ok(SS.db.specProfiles.NECRO.rules["Holy Shock"] ~= nil, "preset content back")
ok(rulesOf("Holy Strike") ~= nil, "slot reset does not touch the rules in use")
SS.db.specProfiles.HOLY = { rules = {}, off = {} }; cmd("spec reset holy"); eq(SS.db.specProfiles.HOLY, nil, "reset of another slot empties it")
cmd("spec reset necro"); ok(W.chatHas("preset"), "reset necro via 'spec reset'")
cmd("spec reset bogus"); ok(W.chatHas("Spec must be"), "bad slot name")
eq(SS.SpecFromText("Necroladin"), "NECRO", "name parsing"); eq(SS.SpecFromText("necro"), "NECRO", "short name")

-- ============================================================ 2. signature capture
section("signature capture")
fresh(); W.talents = nil
cmd("spec necro capture"); ok(W.chatHas("Cannot read your talents"), "capture refused when the talents are unreadable"); eq(SS.db.necroSig, nil, "nothing stored")
talents(0, 0, 0); cmd("spec necro capture"); eq(SS.db.necroSig, nil, "capture refused with no point spent")
talents(5, 0, 41); cmd("spec necro capture")
ok(SS.db.necroSig ~= nil and SS.db.necroSig.HOLY == 5 and SS.db.necroSig.PROT == 0 and SS.db.necroSig.RET == 41, "signature = points per tree")
ok(W.chatHas("signature recorded"), "confirmation message"); ok(string.find(SS.NecroSigText(), "Holy 5 / Protection 0 / Retribution 41", 1, true), "signature text")
eq(SS.db.necroTol, 2, "default tolerance +/-2")
cmd("spec necro tol 3"); eq(SS.db.necroTol, 3, "tolerance set"); cmd("spec necro tol 11"); eq(SS.db.necroTol, 3, "tolerance above 10 refused"); ok(W.chatHas("0 to 10"), "message")
cmd("spec necro tol -1"); eq(SS.db.necroTol, 3, "negative refused"); cmd("spec necro tol abc"); eq(SS.db.necroTol, 3, "non numeric refused"); cmd("spec necro tol 0"); eq(SS.db.necroTol, 0, "0 accepted"); cmd("spec necro tol 2.7"); eq(SS.db.necroTol, 2, "rounded down")
cmd("spec necro"); ok(W.chatHas("Necroladin signature: Holy 5"), "status shows the signature")
cmd("spec"); ok(W.chatHas("Necroladin signature"), "/ssw spec status mentions it")
cmd("spec necro clear"); eq(SS.db.necroSig, nil, "signature forgotten"); cmd("spec necro"); ok(W.chatHas("not recorded"), "status says not recorded")
cmd("spec necro bogus"); ok(W.chatHas("Unknown command"), "unknown sub command")
UnitClass = function() return "Druid", "DRUID" end; talents(5, 5, 5); cmd("spec necro capture"); ok(W.chatHas("Paladins"), "capture refused for another class"); eq(SS.db.necroSig, nil, "nothing stored for another class")
UnitClass = function() return "Paladin", "PALADIN" end
GetTalentTabInfo = function() error("boom") end; ok(pcall(SS.CaptureNecroSig), "capture tolerates a raising talent API"); GetTalentTabInfo = nil
GetTalentTabInfo = function(i) local t = W.talents and W.talents[i]; if not t then return nil end return t.name, "tex", t.pts, t.bg or "" end

-- ============================================================ 3. recognition priority and tolerance
section("recognition")
fresh()
talents(5, 0, 41)
local sp, src = SS.CurrentSpec(); eq(sp, "RET", "no signature : Retribution (Necroladin is never chosen automatically)")
SS.db.specManual = "NECRO"; sp, src = SS.CurrentSpec(); eq(sp, "RET", "no signature : even a manual NECRO fallback does not override readable talents"); SS.db.specManual = nil
W.talents = nil; SS.db.specManual = "NECRO"; sp, src = SS.CurrentSpec(); eq(sp, "NECRO", "manual fallback can be Necroladin when talents are unreadable"); eq(src, "manual", "source manual"); SS.db.specManual = nil
talents(5, 0, 41); cmd("spec necro capture")
sp, src = SS.CurrentSpec(); eq(sp, "NECRO", "same talents as the signature : Necroladin"); eq(src, "talents", "source talents")
talents(6, 0, 43); eq((SS.CurrentSpec()), "NECRO", "+1 / +2 points : within the default tolerance")
talents(3, 2, 39); eq((SS.CurrentSpec()), "NECRO", "-2 / +2 / -2 : within the tolerance")
talents(8, 0, 41); eq((SS.CurrentSpec()), "RET", "+3 on one tree : outside +/-2 -> back to Retribution")
talents(5, 0, 44); eq((SS.CurrentSpec()), "RET", "+3 on Retribution : outside")
SS.db.necroTol = 3; talents(8, 0, 41); eq((SS.CurrentSpec()), "NECRO", "tolerance 3 : recognised"); SS.db.necroTol = 2
SS.db.necroTol = 0; talents(5, 0, 41); eq((SS.CurrentSpec()), "NECRO", "tolerance 0 : exact match"); talents(6, 0, 41); eq((SS.CurrentSpec()), "RET", "tolerance 0 : one point off"); SS.db.necroTol = 2
-- priority over Holy / Protection / Retribution : a signature that looks like each of them
cmd("spec necro clear"); talents(31, 20, 0); cmd("spec necro capture"); eq((SS.CurrentSpec()), "NECRO", "signature of a Holy-looking build wins over Holy"); talents(31, 20, 0)
local d = SS.DetectSpec(); eq(d, "HOLY", "plain detection still says Holy")
cmd("spec necro clear"); talents(10, 10, 31); cmd("spec necro capture"); talents(10, 10, 31); eq((SS.CurrentSpec()), "NECRO", "wins over Retribution")
talents(20, 20, 20); cmd("spec necro clear"); cmd("spec necro capture"); eq(SS.DetectSpec(), nil, "a three-way tie has no plain spec"); eq((SS.CurrentSpec()), "NECRO", "but the signature still matches a tie")
W.talents = nil; eq((SS.CurrentSpec()), nil, "unreadable talents : no recognition")
GetNumTalentTabs = function() return 2 end; talents(20, 20, 20); eq((SS.CurrentSpec()), nil, "incomplete tree list : never recognised"); GetNumTalentTabs = function() if not W.talents then return 0 end return table.getn(W.talents) end
UnitClass = function() return "Druid", "DRUID" end; talents(20, 20, 20); eq((SS.CurrentSpec()), nil, "other class : nothing"); UnitClass = function() return "Paladin", "PALADIN" end

-- ============================================================ 4. automatic switch with / without a signature
section("auto switch")
fresh(); W.putBag(0, 1, ITEM.RadiantDawn)
talents(5, 0, 41)
SS.SetRule("Judgement", { "Libram of Final Judgement" })
cmd("spec auto on"); eq(SS.db.lastSpec, "RET", "auto on : current spec Retribution, rules adopted")
-- without a signature the auto switch never goes to Necroladin
talents(5, 0, 41); W.fire("CHARACTER_POINTS_CHANGED"); eq(SS.db.lastSpec, "RET", "no signature : stays on Retribution")
cmd("spec load necro"); eq(SS.db.lastSpec, "NECRO", "manual choice of Necroladin")
W.fire("CHARACTER_POINTS_CHANGED"); W.fire("PLAYER_ENTERING_WORLD"); eq(SS.db.lastSpec, "NECRO", "no signature : the automatic switch does not take a manual Necroladin away")
ok(rulesOf("Holy Shock") ~= nil, "Necroladin rules still in use"); ok(SS.db.specProfiles.NECRO.rules["Holy Shock"], "preset slot untouched")
-- with a signature
cmd("spec load ret"); eq(SS.db.lastSpec, "RET", "back to Retribution by hand")
talents(5, 0, 41); cmd("spec necro capture")
W.chat = {}; W.fire("CHARACTER_POINTS_CHANGED")
eq(SS.db.lastSpec, "NECRO", "signature recorded : the automatic switch picks Necroladin"); ok(W.chatHas("rules switched"), "switch message")
ok(rulesOf("Holy Shock") ~= nil and SS.db.off["Holy Light"] == true, "Necroladin rules loaded (Holy Shock active, others kept off)")
-- moving away from the signature
talents(5, 0, 46); W.combat = true; W.fire("CHARACTER_POINTS_CHANGED")
eq(SS.db.lastSpec, "NECRO", "no switch in combat"); eq(SS.specPending, true, "postponed")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); eq(SS.db.lastSpec, "RET", "switch done after the fight (talents no longer match)")
-- coming back is also postponed in combat
talents(5, 0, 41); W.combat = true; W.fire("PLAYER_ENTERING_WORLD"); eq(SS.db.lastSpec, "RET", "no switch in combat (to Necroladin)")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); eq(SS.db.lastSpec, "NECRO", "Necroladin after the fight")
-- edits made under Necroladin are kept when leaving it
SS.SetRule("Holy Strike", { "Libram of the Eternal Tower" })
talents(5, 0, 50); W.fire("CHARACTER_POINTS_CHANGED")
ok(SS.db.specProfiles.NECRO.rules["Holy Strike"] ~= nil, "edits made under Necroladin saved to its slot when leaving")
cmd("spec necro reset"); eq(SS.SlotIsPreset("NECRO"), true, "and the preset can be restored")
-- a raising API never breaks the check
GetNumTalentTabs = function() error("x") end; ok(pcall(SS.SpecCheck), "SpecCheck tolerates a raising API")
GetNumTalentTabs = function() if not W.talents then return 0 end return table.getn(W.talents) end

-- ============================================================ 5. profile bar
section("profile bar")
fresh(); W.fire("PLAYER_LOGIN"); open()
ok(UI.bar ~= nil and table.getn(UI.bar) == 4, "four buttons in the profile bar")
eq(UI.bar[1].spec, "HOLY", "order : Holy"); eq(UI.bar[2].spec, "PROT", "Protection"); eq(UI.bar[3].spec, "RET", "Retribution"); eq(UI.bar[4].spec, "NECRO", "Necroladin")
ok(hasText(UI.bar[1], "Holy") and hasText(UI.bar[4], "Necroladin"), "labels")
ok(UI.bar[1].shown and UI.bar[4].shown, "bar visible whatever the tab")
for t = 1, 5 do UI.SetTab(t); ok(UI.bar[1].shown and UI.frame.barLabel.text ~= "", "bar still visible on tab " .. t) end
UI.SetTab(1)
ok(UI.bar[1].parent == UI.frame and UI.tabs[1].parent == UI.frame, "the bar belongs to the window, not to a tab panel")
-- empty slots are dimmed, preset slot is not
ok(hasText(UI.bar[1], "|cFF8C8C8C"), "empty slot dimmed"); ok(not hasText(UI.bar[4], "|cFF8C8C8C"), "Necroladin (preset) is not dimmed")
-- click loads
W.putBag(0, 1, ITEM.RadiantDawn)
click(UI.bar[4]); eq(SS.db.lastSpec, "NECRO", "click on Necroladin loads it"); ok(rulesOf("Holy Shock") ~= nil, "rules loaded")
ok(hasText(UI.bar[4], "|cFFFFD100"), "profile in use is lit (gold)"); eq(UI.bar[4].glow.shown, true, "glow shown on the active button"); eq(UI.bar[1].glow.shown, false, "no glow on the others")
SS.ApplyRules({}, {}); SS.SetRule("Judgement", { "Libram of Final Judgement" }); cmd("spec save holy")
click(UI.bar[1]); eq(SS.db.lastSpec, "HOLY", "click on Holy loads it"); ok(hasText(UI.bar[1], "|cFFFFD100"), "Holy now lit"); eq(UI.bar[4].glow.shown, false, "Necroladin no longer lit")
ok(rulesOf("Judgement") ~= nil and rulesOf("Holy Shock") == nil, "Holy rules in use")
W.chat = {}; click(UI.bar[2]); ok(W.chatHas("No saved rules"), "empty slot : explained, nothing lost"); ok(rulesOf("Judgement") ~= nil, "rules untouched")
-- tooltips
this = UI.bar[4]; UI.bar[4].scripts.OnEnter(); this = nil; ok(W.tipHas("Necroladin") and W.tipHas("signature"), "tooltip explains Necroladin")
SS.db.lang = "fr"; this = UI.bar[1]; UI.bar[1].scripts.OnEnter(); this = nil; ok(W.tipHas("Charge tes règles Sacré"), "tooltip in French"); SS.db.lang = "auto"
-- quick menu has it too
click(SS.mmButton, "RightButton"); ok(SS.quick.items[6].shown and hasText(SS.quick.items[6], "Necroladin"), "quick menu entry"); click(SS.quick.items[6]); eq(SS.db.lastSpec, "NECRO", "quick menu loads Necroladin")
-- other classes : no bar, nothing breaks
UnitClass = function() return "Warrior", "WARRIOR" end; UI.Refresh()
ok(not UI.bar[1].shown and UI.frame.barLabel.text == "", "no spec bar for other classes")
UnitClass = function() return "Paladin", "PALADIN" end; UI.Refresh(); ok(UI.bar[1].shown, "bar back")

-- ============================================================ 6. profiles tab : Necroladin block
section("profiles tab")
fresh(); open(); UI.SetTab(3)
local pt = UI.tabs[3]
ok(hasText(pt.specName[4], "Necroladin"), "4th row is Necroladin"); ok(hasText(pt.specState[4], "preset"), "state : preset")
ok(hasText(pt.necroSig, "not recorded"), "menu says clearly that the signature is not recorded")
SS.db.lang = "fr"; UI.Refresh(); ok(hasText(pt.necroSig, "non enregistrée"), "in French : signature non enregistrée"); SS.db.lang = "auto"; UI.Refresh()
talents(5, 0, 41); click(btn("nc_capture")); ok(SS.db.necroSig ~= nil, "capture button"); ok(hasText(pt.necroSig, "Holy 5"), "signature displayed"); ok(hasText(pt.tolText, "2"), "tolerance displayed")
click(btn("nc_tolp")); eq(SS.db.necroTol, 3, "tolerance +"); click(btn("nc_tolm")); click(btn("nc_tolm")); click(btn("nc_tolm")); eq(SS.db.necroTol, 0, "tolerance - stops at 0")
for i = 1, 14 do click(btn("nc_tolp")) end; eq(SS.db.necroTol, 10, "tolerance + stops at 10"); SS.db.necroTol = 2
SS.SetRule("Cleanse", { "Libram of Grace" }); click(btn("sv_NECRO")); ok(hasText(pt.specState[4], "edited"), "state : edited after a save")
click(btn("rs_NECRO")); eq(SS.SlotIsPreset("NECRO"), false, "reset needs a second click"); ok(hasText(btn("rs_NECRO"), "confirm"), "asks to confirm")
click(btn("rs_NECRO")); eq(SS.SlotIsPreset("NECRO"), true, "second click : back to the preset"); ok(hasText(pt.specState[4], "preset"), "state : preset again")
click(btn("ld_NECRO")); eq(SS.db.lastSpec, "NECRO", "load button"); ok(hasText(pt.specState[4], "in use"), "marked in use")
click(btn("nc_clear")); eq(SS.db.necroSig, nil, "forget button"); ok(hasText(pt.necroSig, "not recorded"), "status back to not recorded")
local ids = { "ld_NECRO", "sv_NECRO", "rs_NECRO", "nc_capture", "nc_tolm", "nc_tolp", "nc_clear" }
for i = 1, 7 do ok(def(UI.BUTTONS, ids[i]) ~= nil and SS.M.en[def(UI.BUTTONS, ids[i]).tip] ~= nil, "button and tooltip text exist: " .. ids[i]) end
UnitClass = function() return "Shaman", "SHAMAN" end; UI.Refresh(); ok(not btn("nc_capture").shown and pt.necroSig.text == "", "Necroladin block hidden for other classes"); UnitClass = function() return "Paladin", "PALADIN" end
UI.frame:Hide()

-- ============================================================ 7. migration 1.1.0 -> 1.2.0 (schema 2 -> 3)
section("migration")
local v110 = {
    version = 2, enabled = true, combat = "burst", fallbacks = false, lang = "fr", opener = "Holy Light", autoSpec = true, lastSpec = "RET", specManual = "HOLY",
    rules = { ["Holy Light"] = { "Libram of Radiance", "Libram of Virtue" }, ["Flash of Light"] = { "Libram of Light" } }, off = { ["Flash of Light"] = true },
    profiles = { heal = { rules = { ["Holy Light"] = { "Libram of Radiance" } }, off = {} } },
    specProfiles = { HOLY = { rules = { ["Holy Light"] = { "Libram of Radiance" } }, off = {} }, RET = { rules = { Judgement = { "Libram of Final Judgement" } }, off = { Judgement = true } } },
    minimap = { show = false, angle = 123 }, indicator = { show = true, locked = true, scale = 1.4, x = 200, y = 300 }, alert = { chat = false, sound = true },
    ui = { x = 50, y = 60, tab = 3, all = true }, backup = { rules = { a = { "b" } }, off = {} },
}
ShikaSwapDB = v110; SS.InitDB()
eq(SS.db.version, SS.SCHEMA, "current schema after migration"); eq(SS.db.combat, "burst", "mode kept"); eq(SS.db.fallbacks, false, "fallbacks kept"); eq(SS.db.lang, "fr", "language kept"); eq(SS.db.opener, "Holy Light", "opener kept")
eq(SS.db.autoSpec, true, "auto spec kept"); eq(SS.db.lastSpec, "RET", "last spec kept"); eq(SS.db.specManual, "HOLY", "manual spec kept")
eq(table.concat(SS.db.rules["Holy Light"], ","), "Libram of Radiance,Libram of Virtue", "rules kept"); eq(SS.db.off["Flash of Light"], true, "off flags kept"); ok(SS.db.profiles.heal ~= nil, "named profile kept")
ok(SS.db.specProfiles.HOLY.rules["Holy Light"] ~= nil and SS.db.specProfiles.RET.off.Judgement == true, "spec profiles kept")
ok(SS.db.minimap.show == false and SS.db.minimap.angle == 123, "minimap kept"); ok(SS.db.indicator.locked == true and SS.db.indicator.scale == 1.4 and SS.db.indicator.x == 200, "indicator kept")
ok(SS.db.alert.chat == false and SS.db.alert.sound == true, "alert kept"); ok(SS.db.ui.tab == 3 and SS.db.ui.x == 50 and SS.db.ui.all == true, "window state kept"); ok(SS.db.backup ~= nil, "undo backup kept")
ok(SS.db.specProfiles.NECRO ~= nil and SS.SlotIsPreset("NECRO"), "Necroladin slot added with the preset"); eq(SS.db.necroTol, 2, "default tolerance added"); eq(SS.db.necroSig, nil, "no signature : Necroladin stays manual-only")
eq(SS.nRules, 2, "rule index rebuilt")
-- idempotent
local before = SS.db.specProfiles.NECRO; SS.InitDB(); ok(SS.db.specProfiles.NECRO == before or SS.SlotIsPreset("NECRO"), "second InitDB changes nothing")
-- a user-edited Necroladin slot is never overwritten by a later migration
SS.db.specProfiles.NECRO = { rules = { Judgement = { "Libram of Final Judgement" } }, off = {} }; SS.db.version = 2; SS.InitDB()
ok(SS.db.specProfiles.NECRO.rules.Judgement ~= nil and not SS.db.specProfiles.NECRO.rules["Holy Shock"], "edited Necroladin slot survives a re-migration")
-- corrupt new fields
local function reload(extra) local d = { rules = {}, version = 2 }; for k, v in pairs(extra) do d[k] = v end; ShikaSwapDB = d; SS.InitDB(); return SS.db end
eq(reload({ necroSig = "bad" }).necroSig, nil, "string signature dropped"); eq(reload({ necroSig = { HOLY = 1, PROT = 2 } }).necroSig, nil, "incomplete signature dropped")
eq(reload({ necroSig = { HOLY = 0, PROT = 0, RET = 0 } }).necroSig, nil, "all-zero signature dropped"); eq(reload({ necroSig = { HOLY = -1, PROT = 0, RET = 5 } }).necroSig, nil, "negative points dropped")
eq(reload({ necroSig = { HOLY = 99, PROT = 0, RET = 5 } }).necroSig, nil, "impossible points dropped"); eq(reload({ necroSig = { HOLY = "5", PROT = 0, RET = 5 } }).necroSig, nil, "string points dropped")
local g = reload({ necroSig = { HOLY = 5.7, PROT = 0, RET = 41, junk = 1 } }).necroSig; ok(g and g.HOLY == 5 and g.RET == 41 and g.junk == nil, "valid signature kept (integers, no junk)")
eq(reload({ necroTol = 99 }).necroTol, 2, "tolerance out of range reset"); eq(reload({ necroTol = "x" }).necroTol, 2, "tolerance garbage reset"); eq(reload({ necroTol = 4.9 }).necroTol, 4, "tolerance floored")
eq(reload({ specManual = "NECRO" }).specManual, "NECRO", "NECRO accepted as manual spec"); eq(reload({ lastSpec = "NECRO" }).lastSpec, "NECRO", "NECRO accepted as last spec"); eq(reload({ lastSpec = "BOGUS" }).lastSpec, nil, "unknown spec dropped")
ok(reload({ specProfiles = { NECRO = "bad" } }).specProfiles.NECRO ~= nil and SS.SlotIsPreset("NECRO"), "corrupt Necroladin slot replaced by the preset")
-- reset to defaults keeps the user's slots and the signature
fresh(); talents(5, 0, 41); cmd("spec necro capture"); SS.db.specProfiles.NECRO = { rules = { Judgement = { "Libram of Final Judgement" } }, off = {} }; SS.db.specProfiles.HOLY = { rules = {}, off = {} }
SS.ResetSettings(); ok(SS.db.necroSig ~= nil and SS.db.specProfiles.NECRO.rules.Judgement ~= nil and SS.db.specProfiles.HOLY ~= nil, "defaults reset keeps spec slots and the signature")

-- ============================================================ 8. icons with fallbacks
section("icons")
fresh(); W.putBag(0, 1, ITEM.Radiance); W.putBag(0, 2, ITEM.Light); W.equip(ITEM.Hope)
SS.SetRule("Holy Light", { "Libram of Radiance", "Libram of Virtue" }); SS.SetRule("Flash of Light", { "Libram of Light" })
open(); UI.SetTab(1)
local row, idx = rowOf("Holy Light")
ok(row.spellIcon ~= nil and row.relicIcon[1] ~= nil and row.relicIcon[2] ~= nil, "each row has a spell icon and two relic icons")
-- spell icon from the spellbook
local bookIdx; for i = 1, table.getn(W.book) do if W.book[i].name == "Holy Light" then bookIdx = i end end
W.spellTex[bookIdx] = "Interface\\Icons\\Spell_Holy_HolyBolt"; UI.Refresh()
eq(row.spellIcon.tex, "Interface\\Icons\\Spell_Holy_HolyBolt", "spell icon = GetSpellTexture of the highest rank in the spellbook")
W.spellTex = {}; UI.Refresh(); eq(row.spellIcon.tex, UI.Q_ICON, "no spell texture : default icon")
local gst = GetSpellTexture; GetSpellTexture = nil; UI.Refresh(); eq(row.spellIcon.tex, UI.Q_ICON, "GetSpellTexture missing : default icon"); GetSpellTexture = function() error("boom") end; UI.Refresh(); eq(row.spellIcon.tex, UI.Q_ICON, "GetSpellTexture raising : default icon"); GetSpellTexture = gst
-- relic icon from the item info
W.itemInfo[55470] = { name = "Libram of Radiance", tex = "Interface\\Icons\\INV_Relics_LibramofGrace" }
UI.texCache = nil; UI.Refresh(); eq(row.relicIcon[1].tex.tex, "Interface\\Icons\\INV_Relics_LibramofGrace", "relic icon = GetItemInfo texture")
-- fallback : texture of the copy in the bags, then the question mark
W.itemInfo = {}; UI.texCache = nil; UI.Refresh(); eq(row.relicIcon[1].tex.tex, "tex", "no item info : texture of the copy found in the bags")
eq(row.relicIcon[2].tex.tex, UI.Q_ICON, "relic not owned and not cached : question mark")
local gii = GetItemInfo; GetItemInfo = function() error("boom") end; UI.texCache = nil; UI.Refresh()
eq(row.relicIcon[2].tex.tex, UI.Q_ICON, "GetItemInfo raising : question mark"); ok(hasText(row.label[1].fs, "Libram of Radiance"), "the row is still drawn"); GetItemInfo = nil; UI.Refresh()
eq(row.relicIcon[2].tex.tex, UI.Q_ICON, "GetItemInfo missing : question mark"); GetItemInfo = gii
W.equip(ITEM.Virtue); SS.bagDirty = true; UI.texCache = nil; UI.Refresh(); eq(row.relicIcon[2].tex.tex, "Interface/Icons/Item" .. ITEM.Virtue, "equipped relic : texture of the equipped item")
W.equip(ITEM.Hope)
eq(UI.RelicTexture("Libram of Nothing"), UI.Q_ICON, "relic outside the catalogue : question mark"); eq(UI.RelicTexture(nil), UI.Q_ICON, "no relic : question mark")
-- a relic slot with no relic shows no icon
SS.ClearRule("Flash of Light"); UI.Refresh(); local rf = rowOf("Flash of Light"); eq(rf.relicIcon[1].tex.shown, false, "empty slot : no icon")
-- an icon call that raises never stops the row from being drawn
row, idx = rowOf("Holy Light"); local sti = row.spellIcon.SetTexture; row.spellIcon.SetTexture = function() error("no texture") end
SS.db.rules["Holy Light"] = { "Libram of Radiance" }; SS.RebuildIndex(); SS.lastError = nil
local okr = pcall(UI.Refresh); ok(okr, "a failing icon does not break the refresh"); ok(hasText(row.label[1].fs, "Libram of Radiance"), "the labels are still drawn"); eq(UI.lastError, nil, "no error reported")
row.spellIcon.SetTexture = sti
-- click through the icon = same as the label
local lbClick = row.relicIcon[1].scripts.OnMouseUp; this = row.relicIcon[1]; arg1 = "LeftButton"; lbClick(); this = nil; arg1 = nil
ok(rulesOf("Holy Light") ~= nil, "clicking a relic icon cycles like the name")
-- tooltips
SS.db.rules["Holy Light"] = { "Libram of Radiance" }; SS.RebuildIndex(); UI.Refresh()
W.hyper = {}; W.itemInfo = {}; this = row.relicIcon[1]; row.relicIcon[1].scripts.OnEnter(); this = nil
eq(table.getn(W.hyper), 0, "item not cached : no hyperlink request (no server query)"); ok(W.tipHas("Libram of Radiance") and W.tipHas("Improves"), "catalogue tooltip instead")
W.itemInfo[55470] = { name = "Libram of Radiance", tex = "t" }; this = row.relicIcon[1]; row.relicIcon[1].scripts.OnEnter(); this = nil
eq(W.hyper[1], "item:55470:0:0:0", "cached item : full item tooltip through SetHyperlink"); ok(W.tipHas("HYPERLINK:item:55470:0:0:0") and W.tipHas("Improves"), "plus the ShikaSwap lines")
W.hyper = {}; W.hyperFail = true; this = row.label[1]; row.label[1].scripts.OnEnter(); this = nil
ok(W.tipHas("Libram of Radiance"), "SetHyperlink raising : falls back to the catalogue tooltip"); W.hyperFail = nil
local gt = GameTooltip; GameTooltip = nil; this = row.label[1]; ok(pcall(row.label[1].scripts.OnEnter), "no GameTooltip : no error"); this = nil; GameTooltip = gt
local sh = GameTooltip.SetHyperlink; GameTooltip.SetHyperlink = nil; this = row.label[1]; ok(pcall(row.label[1].scripts.OnEnter), "no SetHyperlink : no error"); ok(W.tipHas("Libram of Radiance"), "and the catalogue tooltip"); this = nil; GameTooltip.SetHyperlink = sh
-- the window stays usable when every icon API is gone
GetItemInfo = nil; GetSpellTexture = nil; GetInventoryItemTexture = nil
ok(pcall(UI.Refresh), "menu usable without any icon API"); local o1 = pcall(function() click(row.next[1]) end); ok(o1, "and still clickable")
GetItemInfo = gii; GetSpellTexture = gst; GetInventoryItemTexture = function(u, slot) local id = W.cinv[slot]; if not id then return nil end return "Interface/Icons/Item" .. id end
-- nothing but base client textures
local bad = {}
for i = 1, table.getn(W.frames) do
    local f = W.frames[i]
    if type(f.tex) == "string" and f.tex ~= "tex" and not string.find(f.tex, "^Interface[\\/]") then bad[table.getn(bad) + 1] = f.tex end
    if f.backdrop then
        if not string.find(f.backdrop.bgFile, "^Interface[\\/]") or not string.find(f.backdrop.edgeFile, "^Interface[\\/]") then bad[table.getn(bad) + 1] = "backdrop" end
    end
end
eq(table.concat(bad, ","), "", "every texture path is a base client path (no custom file)")
UI.frame:Hide()

-- ============================================================ 9. theme
section("theme")
fresh(); W.fire("PLAYER_LOGIN"); open()
local f = UI.frame
ok(f.backdrop ~= nil and string.find(f.backdrop.bgFile, "UI-Tooltip-Background", 1, true), "dark background texture : base tooltip background")
ok(string.find(f.backdrop.edgeFile, "UI-Tooltip-Border", 1, true), "thin border : base tooltip border")
ok(f.borderColor and f.borderColor[1] == 1 and f.borderColor[2] == 0.82 and f.borderColor[3] == 0, "border tinted gold (1, 0.82, 0)")
ok(f.bgColor and f.bgColor[4] >= 0.85 and f.bgColor[4] < 1 and f.bgColor[1] < 0.15, "dark, slightly translucent background")
eq(f.title.text, "ShikaSwap", "title"); ok(f.title.textColor and f.title.textColor[1] == 1 and f.title.textColor[2] == 0.82 and f.title.textColor[3] == 0, "title in gold")
ok(f.version.textColor and f.version.textColor[1] == 0.96 and f.version.textColor[2] == 0.55 and f.version.textColor[3] == 0.73, "version in paladin pink")
eq(f.version.text, "v" .. SS.version, "version text"); ok(SS.version == "1.2.0" or SS.version == "1.3.0", "version number")
-- state pill
local function pill() return f.pill.texArgs end
local pa = pill(); ok(pa[2] > pa[1] and pa[2] > 0.7, "active : green pill"); ok(hasText(f.stateText, "active"), "active text")
SS.db.enabled = false; UI.Refresh(); pa = pill(); ok(pa[1] > 0.7 and pa[2] < 0.4, "disabled : red pill"); ok(hasText(f.stateText, "disabled"), "disabled text")
SS.db.enabled = true; SS.conflict = true; UI.Refresh(); pa = pill(); ok(math.abs(pa[1] - pa[2]) < 0.01 and math.abs(pa[2] - pa[3]) < 0.01, "dormant : grey pill"); ok(hasText(f.stateText, "DORMANT"), "dormant text")
SS.conflict = false; UI.Refresh(); pa = pill(); ok(pa[2] > pa[1], "back to green")
SS.db.lang = "fr"; SS.db.enabled = false; UI.Refresh(); ok(hasText(f.stateText, "désactivé"), "state text in French"); SS.db.lang = "auto"; SS.db.enabled = true
-- tabs : active one lit
for t = 1, 5 do
    UI.SetTab(t)
    for i = 1, 5 do
        local b = UI.tabButtons[i]
        eq(b.glow.shown, i == t, "tab " .. i .. " glow when tab " .. t .. " is active")
        eq(hasText(b, "|cFFFFD100"), i == t, "tab " .. i .. " gold text when tab " .. t .. " is active")
        eq(UI.tabs[i].shown, i == t, "panel " .. i .. " visibility")
    end
end
UI.SetTab(1)
-- separators and pill use solid colours, not texture files
ok(f.sep1 ~= nil and f.sep1.texArgs[1] == 1 and f.sep1.texArgs[2] == 0.82 and f.sep1.texArgs[4] < 1, "thin translucent gold separator"); eq(f.sep1.h, 1, "1 px high")
eq(type(f.pill.texArgs[1]), "number", "solid colour, no file")
-- decoration helpers alone are safe
local cf = CreateFrame
CreateFrame = function(kind, name, parent, tmpl) local fr = cf(kind, name, parent, tmpl); fr.CreateTexture = function() error("x") end; return fr end
local tmp = CreateFrame("Frame", nil, nil); eq(UI.Solid(tmp, "OVERLAY", 1, 1, UI.GOLD, 1, "TOPLEFT", tmp, "TOPLEFT", 0, 0), nil, "Solid returns nil when the texture cannot be created"); CreateFrame = cf
ok(pcall(UI.SetSolid, nil, UI.GOLD, 1), "SetSolid(nil) safe"); ok(pcall(UI.ShowIf, nil, true), "ShowIf(nil) safe"); ok(pcall(UI.Color, nil, UI.GOLD), "Color(nil) safe")
eq(UI.Tint("x", UI.GOLD), "|cFFFFD100x|r", "Tint builds a 1.12 colour code"); eq(UI.Tint("x", UI.PINK), "|cFFF58CBAx|r", "paladin pink")
eq(UI.WIDTH, 840, "window width"); ok(UI.HEIGHT >= 520, "window height")
-- the indicator scale setting is still there
UI.SetTab(2); click(btn("scaleup")); ok(SS.db.indicator.scale > 1, "indicator size setting kept")

-- ============================================================ 10. help / commands text
section("commands")
fresh(); cmd("help")
ok(W.chatHas("spec [save|load holy|prot|ret"), "help lists the spec command")
local missing = {}
for k in pairs(SS.M.en) do if SS.M.fr[k] == nil then missing[table.getn(missing) + 1] = k end end
for k in pairs(SS.M.fr) do if SS.M.en[k] == nil then missing[table.getn(missing) + 1] = k end end
eq(table.concat(missing, ","), "", "every text exists in EN and FR")

print(string.format("RESULT: %d passed, %d failed", PASSES, FAILS))
if FAILS > 0 then error("TESTS FAILED: " .. FAILS) end
