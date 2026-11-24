-- tests_ui.lua : menu (5 tabs), minimap button, floating indicator, missing-relic alert, talents / spec profiles,
-- text export / import, bindings, schema migration.   Run:  node harness_shikaswap.js tests_ui.lua
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
    UI.confirmId = nil; UI.page = 1; UI.diagLines = {}; UI.shareMsg = nil; UI.profIdx = 1
    UnitClass = function() return "Paladin", "PALADIN" end
    SS.InitDB()
    SS.frame:Hide()
    if SS.mmButton then SS.ApplyDisplay() end
end
local function cmd(s) W.chat = {}; local okc, err = pcall(SlashCmdList["SHIKASWAP"], s); if not okc then print("CMD ERROR " .. s .. ": " .. tostring(err)); FAILS = FAILS + 1 end end
local function pally()
    fresh()
    W.putBag(0, 1, ITEM.Radiance); W.putBag(0, 2, ITEM.Light); W.putBag(0, 3, ITEM.Faithful); W.putBag(0, 4, ITEM.FinalJ)
    W.equip(ITEM.Hope)
end
local function click(w, button)
    this = w; arg1 = button
    local okc, err = pcall(w.scripts.OnClick)
    this = nil; arg1 = nil
    if not okc then FAILS = FAILS + 1; print("CLICK ERROR: " .. tostring(err)) end
end
local function mouseUp(w, button)
    this = w; arg1 = button
    local okc, err = pcall(w.scripts.OnMouseUp)
    this = nil; arg1 = nil
    if not okc then FAILS = FAILS + 1; print("MOUSEUP ERROR: " .. tostring(err)) end
end
local function def(list, id) for i = 1, table.getn(list) do if list[i].id == id then return list[i] end end end
local function btn(id) return def(UI.BUTTONS, id).widget end
local function box(id, value) local w = def(UI.CHECKS, id).widget; w:SetChecked(value); click(w) end
local function rowOf(spell)
    for i = 1, UI.ROWS do if UI.view[(UI.page - 1) * UI.ROWS + i] == spell then return UI.rows[i], i end end
    return nil
end
local function open() if UI.frame and UI.frame:IsShown() then UI.Refresh() else cmd("menu") end return UI.frame end
local function press(spell) CastSpellByName(spell) end
local function rulesOf(spell) local k = SS.lc[string.lower(spell)]; return k and SS.db.rules[k] end
local function hasText(w, sub) return w.text ~= nil and string.find(w.text, sub, 1, true) ~= nil end

-- ============================================================ 1. opening / closing
section("open / close")
pally()
eq(UI.frame, nil, "no frame is created at load or by InitDB")
cmd("menu")
ok(UI.frame ~= nil and UI.frame:IsShown(), "/ssw menu opens the window")
eq(UI.frame.name, "ShikaSwapUIFrame", "window has a global name (needed by UISpecialFrames)")
local inSpecial = false
for i = 1, table.getn(UISpecialFrames) do if UISpecialFrames[i] == "ShikaSwapUIFrame" then inSpecial = true end end
ok(inSpecial, "registered in UISpecialFrames : Escape closes it")
cmd("menu"); ok(not UI.frame:IsShown(), "/ssw menu again closes it")
cmd(""); ok(UI.frame:IsShown(), "bare /ssw opens the menu")
cmd("ui"); ok(not UI.frame:IsShown(), "/ssw ui is an alias")
cmd("config"); ok(UI.frame:IsShown(), "/ssw config is an alias")
UI.frame:Hide()
cmd("help"); ok(W.chatHas("swaps the relic") and W.chatHas("change la relique"), "/ssw help still prints the help")
ok(not UI.frame:IsShown(), "help does not open the menu")
cmd("status"); ok(W.chatHas("combat mode"), "/ssw status still works")
ok(UI.frame.scripts.OnDragStart ~= nil and UI.frame.scripts.OnDragStop ~= nil, "window is draggable")
UI.frame:Show(); UI.frame.left, UI.frame.top = 120, 640
this = UI.frame; UI.frame.scripts.OnDragStop(); this = nil
eq(SS.db.ui.x, 120, "window position saved (x)"); eq(SS.db.ui.y, 640, "window position saved (y)")
eq(UI.frame.moving, false, "StopMovingOrSizing called")
for i = 1, table.getn(UI.BUTTONS) do ok(UI.BUTTONS[i].widget.scripts.OnClick ~= nil, "button has a handler: " .. UI.BUTTONS[i].id) end
-- empty profile : no error
fresh(); ShikaSwapDB = nil; SS.InitDB()
local okc, err = pcall(UI.Open)
ok(okc, "menu opens with an empty profile: " .. tostring(err))
for t = 1, 5 do local o2, e2 = pcall(UI.SetTab, t); ok(o2, "tab " .. t .. " draws with an empty profile: " .. tostring(e2)) end
UI.SetTab(1)
UI.frame:Hide()

-- ============================================================ 2. rules tab
section("rules tab")
pally(); open()
ok(UI.view ~= nil and table.getn(UI.view) > 0, "known catalogue spells listed")
local hasHL, hasSeal = false, false
for i = 1, table.getn(UI.view) do
    if UI.view[i] == "Holy Light" then hasHL = true end
    if UI.view[i] == "Seal of Righteousness" then hasSeal = true end
end
ok(hasHL, "Holy Light listed (in the spellbook)")
ok(not hasSeal, "spells not in the spellbook are hidden by default")
click(btn("view")); eq(SS.db.ui.all, true, "view toggle: all catalogue spells")
hasSeal = false
for i = 1, table.getn(UI.view) do if UI.view[i] == "Seal of Righteousness" then hasSeal = true end end
ok(hasSeal, "all spells listed after the toggle")
click(btn("view")); eq(SS.db.ui.all, nil, "view toggle back")
local row = rowOf("Holy Light")
ok(row ~= nil, "Holy Light has a row")
eq(rulesOf("Holy Light"), nil, "no rule yet")
ok(row.check.disabled == true, "check box disabled without a rule")
ok(row.next[2].disabled and row.prev[2].disabled, "relic 2 selector disabled while relic 1 is empty")
click(row.next[2]); eq(rulesOf("Holy Light"), nil, "slot 2 cannot be set while slot 1 is empty")
-- change relic via the UI == /ssw set
click(row.next[1])
local viaUI = rulesOf("Holy Light")
eq(viaUI and viaUI[1], "Libram of Radiance", "UI next : first valid relic for Holy Light")
local copy = table.concat(viaUI, ",")
fresh(); cmd("set Holy Light = Libram of Radiance")
eq(table.concat(SS.db.rules["Holy Light"], ","), copy, "UI rule == /ssw set rule")
pally(); open(); row = rowOf("Holy Light")
click(row.next[1]); click(row.next[1])
eq(rulesOf("Holy Light")[1], "Libram of Virtue", "second click : next valid relic")
click(row.next[1]); eq(rulesOf("Holy Light"), nil, "wraps to 'none' and the rule is removed (same as /ssw clear)")
click(row.prev[1]); eq(rulesOf("Holy Light")[1], "Libram of Virtue", "previous from none : last relic")
eq(table.concat(UI.Options("Holy Light"), ","), "Libram of Radiance,Libram of Virtue", "options for Holy Light = catalogue relics of the class that improve it")
eq(table.concat(UI.Options("Flash of Light"), ","), "Libram of Divinity,Libram of Light", "options for Flash of Light")
eq(table.getn(UI.Options("Wrath")), 0, "no Druid idol offered to a Paladin")
-- relic 2
row = rowOf("Holy Light")
ok(not row.next[2].disabled, "relic 2 enabled once relic 1 is set")
click(row.next[2])
eq(rulesOf("Holy Light")[1], "Libram of Virtue", "slot 1 untouched"); eq(rulesOf("Holy Light")[2], "Libram of Radiance", "slot 2 gets the first relic that is not slot 1")
click(row.next[2]); eq(rulesOf("Holy Light")[2], nil, "slot 2 cycles to none (never duplicates slot 1)")
-- right click on the label = previous
local lb = row.label[1]
mouseUp(lb, "RightButton"); eq(rulesOf("Holy Light")[1], "Libram of Radiance", "right click on the label : previous")
mouseUp(lb, "LeftButton"); eq(rulesOf("Holy Light")[1], "Libram of Virtue", "left click on the label : next")
-- status text
SS.db.rules["Holy Light"] = nil; SS.RebuildIndex(); UI.Refresh()
click(row.next[1])
ok(hasText(row.label[1].fs, "Libram of Radiance") and hasText(row.label[1].fs, "in bags"), "label shows the relic and 'in bags'")
click(row.next[1])
ok(hasText(row.label[1].fs, "missing"), "relic not owned : 'missing'")
W.cinv[18] = ITEM.Virtue; W.sinv[18] = ITEM.Virtue; SS.bagDirty = true; UI.Refresh()
ok(hasText(row.label[1].fs, "equipped"), "equipped relic : 'equipped'")
W.equip(ITEM.Hope)
-- disable keeps the relic choice
SS.ClearRule("Holy Light"); SS.SetRuleCmd("Holy Light", { "Libram of Radiance" }, true); UI.Refresh()
row.check:SetChecked(nil); click(row.check)
eq(SS.db.off["Holy Light"], true, "check box off = /ssw disable")
row.check:SetChecked(1); click(row.check)
eq(SS.db.off["Holy Light"], nil, "check box on = /ssw enable")
row.check:SetChecked(nil); click(row.check)
click(row.next[1])
eq(SS.db.off["Holy Light"], true, "changing the relic keeps a disabled rule disabled")
eq(row.check.checked, nil, "check box stays unchecked")
press("Holy Light"); eq(W.logCount("UCI"), 0, "a rule switched off in the menu does not swap")
-- refresh after a chat command
cmd("set Holy Light = Libram of Virtue")
ok(hasText(row.label[1].fs, "Libram of Virtue"), "menu refreshes after /ssw set")
cmd("clear Holy Light"); ok(hasText(row.label[1].fs, "none"), "menu refreshes after /ssw clear")
-- the swap really uses what the menu chose
pally(); open(); row = rowOf("Flash of Light")
click(row.next[1]); click(row.next[1])
eq(rulesOf("Flash of Light")[1], "Libram of Light", "picked Libram of Light")
press("Flash of Light"); W.advance(0.3)
eq(W.sinv[18], ITEM.Light, "the cast swaps to the relic chosen in the menu")
-- unknown spells are greyed when 'all' is shown
click(btn("view")); local r2
for p = 1, 6 do
    UI.page = p; UI.Refresh(); r2 = rowOf("Seal of Righteousness")
    if r2 then break end
end
ok(r2 ~= nil, "unknown spell has a row when all spells are shown")
ok(r2 ~= nil and hasText(r2.name, "888888"), "unknown spells greyed")
-- pager
UI.page = 1; UI.Refresh()
local pages = math.ceil(table.getn(UI.view) / UI.ROWS)
ok(pages >= 2, "more than one page with all spells")
this = UI.frame; arg1 = -1; UI.frame.scripts.OnMouseWheel(); this = nil; arg1 = nil
eq(UI.page, 2, "mouse wheel down : next page")
click(btn("view")); eq(UI.page, 1, "toggle resets to page 1")
-- unknown relics in a rule stay visible and survive
fresh(); SS.db.rules["Holy Light"] = { "Libram of Nothing" }; SS.RebuildIndex(); open()
row = rowOf("Holy Light")
ok(hasText(row.label[1].fs, "(?)"), "unknown relic in a rule is shown with (?)")
click(row.next[1]); eq(rulesOf("Holy Light")[1], "Libram of Radiance", "unknown relic -> first valid one")
-- other class : editor not offered, nothing breaks
fresh(); UnitClass = function() return "Druid", "DRUID" end; SS.db.rules["Wrath"] = { "Idol of Acidity" }; SS.RebuildIndex()
open(); UI.Refresh()
eq(table.getn(UI.view), 0, "non-Paladin : rule editor lists nothing")
ok(hasText(UI.tabs[1].empty, "Paladin"), "non-Paladin : explanatory note")
eq(SS.db.rules["Wrath"][1], "Idol of Acidity", "non-Paladin rules untouched")
UnitClass = function() return "Paladin", "PALADIN" end
UI.frame:Hide()

-- ============================================================ 3. settings tab
section("settings tab")
pally(); open(); UI.SetTab(2)
eq(UI.tab, 2, "tab 2"); eq(SS.db.ui.tab, 2, "tab remembered in the saved variables")
box("enabled", nil); eq(SS.db.enabled, false, "check: addon off"); box("enabled", 1); eq(SS.db.enabled, true, "check: addon on")
box("fallbacks", nil); eq(SS.db.fallbacks, false, "check: fallbacks off"); box("fallbacks", 1); eq(SS.db.fallbacks, true, "check: fallbacks on")
box("minimap", nil); eq(SS.db.minimap.show, false, "check: minimap off"); box("minimap", 1); eq(SS.db.minimap.show, true, "check: minimap on")
box("indicator", nil); eq(SS.db.indicator.show, false, "check: indicator off"); box("indicator", 1); eq(SS.db.indicator.show, true, "check: indicator on")
box("locked", 1); eq(SS.db.indicator.locked, true, "check: indicator locked"); box("locked", nil); eq(SS.db.indicator.locked, false, "check: unlocked")
box("alertchat", nil); eq(SS.db.alert.chat, false, "check: alert chat off"); box("alertchat", 1); eq(SS.db.alert.chat, true, "alert chat on")
box("alertsound", 1); eq(SS.db.alert.sound, true, "check: alert sound on"); box("alertsound", nil); eq(SS.db.alert.sound, false, "alert sound off")
eq(def(UI.CHECKS, "enabled").widget.checked, 1, "check boxes redrawn from the saved data")
click(btn("smode")); eq(SS.db.combat, "burst", "mode button : auto -> burst")
click(btn("smode")); eq(SS.db.combat, "wait", "-> wait"); click(btn("smode")); eq(SS.db.combat, "skip", "-> skip"); click(btn("smode")); eq(SS.db.combat, "auto", "-> auto")
ok(hasText(btn("smode"), "auto"), "mode button shows the mode")
click(btn("lang")); eq(SS.db.lang, "fr", "language auto -> fr"); click(btn("lang")); eq(SS.db.lang, "en", "-> en"); click(btn("lang")); eq(SS.db.lang, "auto", "-> auto")
SS.SetRule("Holy Light", { "Libram of Radiance" }); SS.SetRule("Flash of Light", { "Libram of Light" }); UI.Refresh()
click(btn("opener")); eq(SS.db.opener, "Flash of Light", "opener cycles through the spells that have a rule")
click(btn("opener")); eq(SS.db.opener, "Holy Light", "opener next"); click(btn("opener")); eq(SS.db.opener, nil, "opener back to none")
click(btn("scaleup")); ok(math.abs(SS.db.indicator.scale - 1.1) < 0.001, "scale +"); click(btn("scaledn")); click(btn("scaledn")); ok(math.abs(SS.db.indicator.scale - 0.9) < 0.001, "scale -")
for i = 1, 20 do click(btn("scaledn")) end; ok(SS.db.indicator.scale >= 0.5, "scale never below 0.5")
for i = 1, 40 do click(btn("scaleup")) end; ok(SS.db.indicator.scale <= 2.5, "scale never above 2.5")
-- reset needs a confirmation
eq(SS.nRules, 2, "2 rules before reset")
click(btn("reset")); eq(SS.nRules, 2, "first click on reset only arms it")
ok(hasText(btn("reset"), "confirm"), "button asks to click again")
W.advance(6); this = UI.frame; UI.frame.scripts.OnUpdate(); this = nil
ok(not hasText(btn("reset"), "confirm"), "the button goes back to its normal text when the confirmation expires")
click(btn("reset")); eq(SS.nRules, 2, "confirmation expired after 5 s : the click only re-arms")
click(btn("reset")); eq(SS.nRules, 0, "second click resets the rules")
eq(SS.db.combat, "auto", "reset restores defaults"); eq(SS.db.indicator.scale, 1.0, "reset restores the indicator scale")
cmd("undo"); eq(SS.nRules, 2, "undo brings the rules back after a reset")
cmd("defaults"); ok(W.chatHas("defaults confirm"), "/ssw defaults asks for the word confirm"); eq(SS.nRules, 2, "nothing reset without confirm")
cmd("defaults confirm"); eq(SS.nRules, 0, "/ssw defaults confirm resets")
UI.frame:Hide()

-- ============================================================ 4. profiles tab (named + per spec)
section("profiles")
pally(); open(); UI.SetTab(3)
SS.SetRule("Holy Light", { "Libram of Radiance" }); UI.Refresh()
UI.profEdit:SetText("heal"); click(btn("psave"))
ok(SS.db.profiles.heal ~= nil, "profile saved from the menu (same as /ssw profile save)")
eq(UI.profEdit.text, "", "name box emptied")
SS.ClearRule("Holy Light"); click(btn("pload"))
ok(rulesOf("Holy Light") ~= nil, "profile loaded from the menu")
cmd("undo"); eq(rulesOf("Holy Light"), nil, "undo after a profile load")
UI.profEdit:SetText(""); click(btn("psave")); ok(SS.db.profiles.heal ~= nil, "empty name overwrites the selected profile")
click(btn("pdel")); ok(SS.db.profiles.heal ~= nil, "delete needs a second click")
click(btn("pdel")); eq(SS.db.profiles.heal, nil, "second click deletes")
ok(pcall(function() click(btn("pload")) end), "loading with no profile does not error")
-- talent detection
W.talents = { { name = "Holy", pts = 31 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 15 } }
eq(SS.DetectSpec(), "HOLY", "talents: Holy")
W.talents = { { name = "Holy", pts = 5 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 41 } }
eq(SS.DetectSpec(), "RET", "talents: Retribution")
W.talents = { { name = "Holy", pts = 0 }, { name = "Protection", pts = 31 }, { name = "Retribution", pts = 20 } }
eq(SS.DetectSpec(), "PROT", "talents: Protection")
W.talents = { { name = "Sacré", pts = 2 }, { name = "Protection", pts = 1 }, { name = "Vindicte", pts = 40 } }
eq(SS.DetectSpec(), "RET", "talents: localized tab names fall back on the tab index")
W.talents = { { name = "Holy", pts = 10 }, { name = "Protection", pts = 10 }, { name = "Retribution", pts = 3 } }
eq(SS.DetectSpec(), nil, "talents: tie -> unknown")
W.talents = { { name = "Holy", pts = 0 }, { name = "Protection", pts = 0 }, { name = "Retribution", pts = 0 } }
eq(SS.DetectSpec(), nil, "talents: no point spent -> unknown")
W.talents = nil; eq(SS.DetectSpec(), nil, "talents: tree not loaded -> unknown")
local sg, sn = GetNumTalentTabs, GetTalentTabInfo
W.talents = { { name = "Holy", pts = 3 } }
GetTalentTabInfo = function() error("boom") end
eq(SS.DetectSpec(), nil, "talents: API raising -> unknown, no error")
GetTalentTabInfo = sn
GetNumTalentTabs = nil; eq(SS.DetectSpec(), nil, "talents: API missing -> unknown"); GetNumTalentTabs = sg
W.talents = { { name = "Holy", pts = 3 }, { name = "x", pts = "garbage" }, { pts = nil } }
ok(pcall(SS.DetectSpec), "talents: garbage values tolerated")
UnitClass = function() return "Druid", "DRUID" end; W.talents = { { name = "Balance", pts = 30 }, { name = "Feral", pts = 5 }, { name = "Restoration", pts = 5 } }
eq(SS.DetectSpec(), nil, "other classes have no spec detection"); eq(SS.SpecsAvailable(), false, "specs unavailable for Druid")
UnitClass = function() return "Paladin", "PALADIN" end
-- manual fallback
W.talents = nil
eq(SS.CurrentSpec(), nil, "no spec at all")
cmd("spec manual ret"); eq(SS.db.specManual, "RET", "manual fallback set"); local sp, src = SS.CurrentSpec(); eq(sp, "RET", "manual spec used when talents are unreadable"); eq(src, "manual", "source = manual")
W.talents = { { name = "Holy", pts = 31 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 15 } }
sp, src = SS.CurrentSpec(); eq(sp, "HOLY", "detected spec wins over the manual fallback"); eq(src, "talents", "source = talents")
UI.Refresh(); click(btn("manual")); eq(SS.db.specManual, nil, "manual button: RET -> none"); click(btn("manual")); eq(SS.db.specManual, "HOLY", "manual button: none -> HOLY")
cmd("spec manual off"); eq(SS.db.specManual, nil, "manual off")
-- save / load per spec from the menu
fresh(); open(); UI.SetTab(3)
SS.SetRule("Holy Light", { "Libram of Radiance" }); click(btn("sv_HOLY"))
ok(SS.db.specProfiles.HOLY and SS.db.specProfiles.HOLY.rules["Holy Light"], "spec save from the menu")
SS.ClearRule("Holy Light"); SS.SetRule("Judgement", { "Libram of Final Judgement" }); click(btn("sv_RET"))
click(btn("ld_HOLY")); ok(rulesOf("Holy Light") ~= nil and rulesOf("Judgement") == nil, "one click loads the Holy rules")
click(btn("ld_RET")); ok(rulesOf("Judgement") ~= nil and rulesOf("Holy Light") == nil, "one click loads the Ret rules")
W.chat = {}; click(btn("ld_PROT")); ok(W.chatHas("No saved rules"), "loading an empty spec slot says so"); ok(rulesOf("Judgement") ~= nil, "empty slot : rules untouched")
ok(hasText(UI.tabs[3].specState[1], "saved"), "spec rows show saved / empty")
ok(hasText(UI.tabs[3].specState[2], "empty"), "empty slot shown as empty")
-- automatic switch
fresh(); open(); UI.SetTab(3)
W.talents = { { name = "Holy", pts = 31 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 15 } }
SS.SetRule("Holy Light", { "Libram of Radiance" })
box("autospec", 1); eq(SS.db.autoSpec, true, "auto spec check box")
eq(SS.db.lastSpec, "HOLY", "first run : current rules become the Holy rules")
ok(SS.db.specProfiles.HOLY and SS.db.specProfiles.HOLY.rules["Holy Light"], "first run saved the current rules for Holy")
W.talents = { { name = "Holy", pts = 5 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 41 } }
W.chat = {}; W.fire("CHARACTER_POINTS_CHANGED")
eq(SS.db.lastSpec, "RET", "talent change -> RET detected"); ok(W.chatHas("no saved rules yet"), "message on switch without a profile")
ok(rulesOf("Holy Light") ~= nil, "no Ret profile yet : current rules kept")
SS.ClearRule("Holy Light"); SS.SetRule("Judgement", { "Libram of Final Judgement" })
W.talents = { { name = "Holy", pts = 41 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 5 } }
W.fire("CHARACTER_POINTS_CHANGED")
eq(SS.db.lastSpec, "HOLY", "back to Holy")
ok(rulesOf("Holy Light") ~= nil and rulesOf("Judgement") == nil, "Holy rules restored automatically")
ok(SS.db.specProfiles.RET and SS.db.specProfiles.RET.rules["Judgement"], "Ret edits were saved before switching away")
W.talents = { { name = "Holy", pts = 5 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 41 } }
W.combat = true; W.fire("CHARACTER_POINTS_CHANGED")
eq(SS.db.lastSpec, "HOLY", "no switch in combat"); eq(SS.specPending, true, "switch postponed")
W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
eq(SS.db.lastSpec, "RET", "switch done after the fight"); ok(rulesOf("Judgement") ~= nil, "Ret rules loaded")
box("autospec", nil); W.talents = { { name = "Holy", pts = 41 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 5 } }
W.fire("CHARACTER_POINTS_CHANGED"); eq(SS.db.lastSpec, "RET", "auto off : nothing switches")
-- unreadable talents with auto on and a manual fallback
SS.db.autoSpec = true; W.talents = nil; cmd("spec manual holy"); eq(SS.db.lastSpec, "HOLY", "manual fallback drives the auto switch when talents are unreadable")
SS.db.autoSpec = true; GetNumTalentTabs = function() error("x") end
ok(pcall(SS.SpecCheck), "SpecCheck tolerates a raising talent API"); GetNumTalentTabs = sg
W.talents = nil
-- class without specs
UnitClass = function() return "Shaman", "SHAMAN" end; cmd("spec"); ok(W.chatHas("Paladins"), "spec command explains it is Paladin only")
UI.Refresh(); ok(UI.tabs[3].noSpec.text ~= "", "profiles tab explains it for other classes")
UnitClass = function() return "Paladin", "PALADIN" end
UI.frame:Hide()

-- ============================================================ 5. export / import
section("export / import")
pally()
SS.SetRule("Holy Light", { "Libram of Radiance", "Libram of Virtue" }); SS.SetRule("Flash of Light", { "Libram of Light" }); SS.SetRule("Consecration", { "Libram of the Faithful" })
SS.SetEnabled("Consecration", false, true)
local txt, n = SS.ExportText()
eq(n, 3, "3 rules exported"); ok(not string.find(txt, "|", 1, true), "export contains no pipe"); ok(not string.find(txt, "\n", 1, true), "export is one line")
ok(string.find(txt, "^SSW1;"), "format version prefix")
SS.db.rules = {}; SS.db.off = {}; SS.RebuildIndex()
local okI, cnt = SS.ImportText(txt)
ok(okI and cnt == 3, "round trip imports 3 rules")
eq(table.concat(SS.db.rules["Holy Light"], ","), "Libram of Radiance,Libram of Virtue", "relic order kept")
eq(SS.db.off["Consecration"], true, "disabled flag kept")
local function untouched() return SS.nRules == 3 and SS.db.rules["Holy Light"][1] == "Libram of Radiance" end
local function bad(text, key, msg)
    local o, k = SS.ImportText(text)
    ok(not o and k == key, msg .. " (got " .. tostring(k) .. ")")
    ok(untouched(), msg .. ": rules untouched")
end
local function repl(s, a, b) return (string.gsub(s, a, b)) end
bad("", "share_err_empty", "empty text")
bad(nil, "share_err_empty", "nil")
bad(42, "share_err_empty", "number")
bad("hello world", "share_err_format", "foreign text")
local function sign(body) return body .. ";~" .. SS.ShareChecksum(body) end
bad(sign("SSW2;+Holy Light=Libram of Radiance"), "share_err_version", "newer format version")
bad(string.sub(txt, 1, string.len(txt) - 5), "share_err_check", "truncated")
bad(repl(txt, "Radiance", "Radianco"), "share_err_check", "one letter changed (checksum)")
bad(txt .. "x", "share_err_check", "garbage after the checksum")
bad(sign("SSW1"), "share_err_none", "no rule")
bad(repl(txt, ";", ";;"), "share_err_format", "double separators")
bad(repl(txt, ";", "|"), "share_err_chars", "pipes (doubled by the EditBox)")
bad(sign("SSW1;+Holy Light=Libram of Nothing"), "share_err_relic", "unknown relic")
bad(sign("SSW1;+Wrath=Idol of Acidity"), "share_err_relic", "relic of another class")
bad(sign("SSW1;+Holy Light=Libram of Radiance;+holy light=Libram of Virtue"), "share_err_dup", "same spell twice")
bad(sign("SSW1;+Holy Light=Libram of Radiance,Libram of Virtue,Libram of Light,Libram of Hope,Libram of Truth"), "share_err_count", "too many relics for one spell")
bad(sign("SSW1;Holy Light=Libram of Radiance"), "share_err_format", "missing on/off flag")
bad(sign("SSW1;+Holy Light"), "share_err_format", "missing relics")
bad(sign("SSW1;+" .. string.rep("x", 80) .. "=Libram of Radiance"), "share_err_spell", "spell name too long")
bad(string.rep("a", 7000), "share_err_long", "huge text")
bad("\1\2\3;~;;~~==", "share_err_format", "control characters")
-- fuzz : random garbage and random mutations never raise and never change the rules
local seed = 12345
local function rnd(m) seed = math.mod(seed * 1103515245 + 12345, 2147483648); return math.mod(math.floor(seed / 65536), m) + 1 end
local alphabet = "abcXYZ019;=,+-~ |\n\t:/"
local raised, changed = 0, 0
for i = 1, 400 do
    local len = rnd(60)
    local t = {}
    for j = 1, len do local p = rnd(string.len(alphabet)); t[j] = string.sub(alphabet, p, p) end
    local s = table.concat(t)
    local o = pcall(SS.ImportText, s); if not o then raised = raised + 1 end
    if not untouched() then changed = changed + 1; SS.ImportText(txt) end
end
for i = 1, 300 do   -- mutate a valid export at a random position
    local p = rnd(string.len(txt))
    local c = rnd(string.len(alphabet))
    local s = string.sub(txt, 1, p - 1) .. string.sub(alphabet, c, c) .. string.sub(txt, p + 1)
    local o = pcall(SS.ImportText, s); if not o then raised = raised + 1 end
    if s ~= txt and not untouched() then changed = changed + 1 end
    SS.ImportText(txt)
end
eq(raised, 0, "fuzz: the importer never raises"); eq(changed, 0, "fuzz: damaged text never changes the rules")
-- from the menu
SS.ImportText(txt); open(); UI.SetTab(4)
click(btn("export")); eq(UI.shareEdit.text, txt, "export fills the box"); ok(UI.shareOk, "export message")
SS.ClearRule("Holy Light"); SS.ClearRule("Flash of Light"); SS.ClearRule("Consecration")
click(btn("doimport")); eq(SS.nRules, 0, "import needs a second click")
click(btn("doimport")); eq(SS.nRules, 3, "second click imports")
UI.shareEdit:SetText("garbage"); click(btn("doimport")); click(btn("doimport"))
eq(SS.nRules, 3, "bad text from the menu changes nothing"); ok(UI.shareOk == false and UI.tabs[4].msg.text ~= "", "error shown")
ok(hasText(UI.tabs[4].msg, "Not a ShikaSwap export"), "error message is explicit")
click(btn("sclear")); eq(UI.shareEdit.text, "", "clear box")
click(btn("undo")); eq(SS.nRules, 0, "undo button: back to the rules from before the import")
cmd("export"); ok(W.chatHas("SSW1;"), "/ssw export prints the line")
cmd("importtext " .. txt); ok(W.chatHas("Import done"), "/ssw importtext imports"); cmd("importtext SSW1;nonsense"); ok(W.chatHas("damaged") or W.chatHas("Not a ShikaSwap"), "/ssw importtext refuses garbage")
-- undo after import
fresh(); SS.SetRule("Judgement", { "Libram of Final Judgement" })
SS.ImportText(txt); ok(rulesOf("Judgement") == nil, "import replaced the rules"); cmd("undo"); ok(rulesOf("Judgement") ~= nil, "undo restores the rules before the import")
cmd("undo"); ok(rulesOf("Judgement") == nil, "undo twice = redo")
-- exporting side : a rule the importer would refuse is not exported
fresh(); SS.db.rules["Bad;Spell"] = { "Libram of Light" }; SS.RebuildIndex(); local t2, n2 = SS.ExportText(); eq(n2, 0, "a spell name the importer would refuse is not exported")
UI.frame:Hide()

-- ============================================================ 6. minimap button
section("minimap")
pally(); W.fire("PLAYER_LOGIN")
local mm = SS.mmButton
ok(mm ~= nil and mm.shown, "button built at login and shown")
eq(mm.name, "ShikaSwapMinimapButton", "named")
eq(mm.parent, Minimap, "child of the minimap")
local pts = mm.points[table.getn(mm.points)]
eq(pts[1], "CENTER", "anchored to the minimap center")
ok(math.abs(mm.offX - SS.MM_RADIUS * math.cos(math.rad(200))) < 0.01, "default angle 200 degrees")
SS.MinimapSetAngle(90); ok(math.abs(mm.offX) < 0.01 and math.abs(mm.offY - SS.MM_RADIUS) < 0.01, "angle 90 = top"); eq(SS.db.minimap.angle, 90, "angle saved")
this = mm; mm.scripts.OnDragStart(); ok(mm.scripts.OnUpdate ~= nil, "drag installs an OnUpdate")
W.cursor_xy = { 600, 500 }; arg1 = 0.01; mm.scripts.OnUpdate(); arg1 = nil
ok(math.abs(SS.db.minimap.angle - 0) < 0.5, "cursor to the right of the minimap = angle 0")
W.cursor_xy = { 500, 400 }; mm.scripts.OnUpdate(); ok(math.abs(SS.db.minimap.angle + 90) < 0.5, "cursor below = -90")
mm.scripts.OnDragStop(); eq(mm.scripts.OnUpdate, nil, "drag stops the OnUpdate"); this = nil
cmd("minimap off"); eq(SS.db.minimap.show, false, "/ssw minimap off"); ok(not mm.shown, "button hidden")
cmd("minimap on"); ok(mm.shown, "button shown again")
cmd("minimap"); ok(not mm.shown, "toggle without argument")
cmd("minimap reset"); ok(mm.shown and SS.db.minimap.angle == 200, "reset puts it back")
this = mm; mm.scripts.OnEnter(); this = nil
ok(W.tipHas("ShikaSwap " .. SS.version) and W.tipHas("active") and W.tipHas("Combat mode"), "tooltip: state and mode"); ok(W.tipHas("Equipped relic"), "tooltip: relic")
SS.conflict = true; local l = SS.TipLines(); ok(string.find(l[2], "DORMANT", 1, true), "tooltip: dormant state"); SS.conflict = false
SS.db.enabled = false; l = SS.TipLines(); ok(string.find(l[2], "disabled", 1, true), "tooltip: disabled state"); SS.db.enabled = true
SS.db.lang = "fr"; l = SS.TipLines(); ok(string.find(l[2], "actif", 1, true), "tooltip in French"); SS.db.lang = "auto"
W.talents = { { name = "Holy", pts = 31 }, { name = "Protection", pts = 5 }, { name = "Retribution", pts = 15 } }
l = SS.TipLines(); ok(string.find(l[table.getn(l)], "Holy", 1, true), "tooltip shows the spec"); W.talents = nil
if UI.frame then UI.frame:Hide() end
click(mm, "LeftButton"); ok(UI.frame:IsShown(), "left click opens the menu")
click(mm, "LeftButton"); ok(not UI.frame:IsShown(), "left click again closes it")
click(mm, "RightButton"); ok(SS.quick ~= nil and SS.quick:IsShown(), "right click opens the quick menu")
local quickEsc = false
for i = 1, table.getn(UISpecialFrames) do if UISpecialFrames[i] == "ShikaSwapQuickMenu" then quickEsc = true end end
ok(quickEsc, "quick menu closes with Escape")
eq(SS.quick.items[3].shown, true, "spec entries shown for a Paladin")
click(SS.quick.items[1]); eq(SS.db.enabled, false, "quick menu: toggle addon"); ok(not SS.quick:IsShown(), "quick menu closes after an action")
click(mm, "RightButton"); ok(hasText(SS.quick.items[1], "Enable"), "label follows the state")
click(SS.quick.items[1]); eq(SS.db.enabled, true, "toggled back")
click(mm, "RightButton"); click(SS.quick.items[2]); eq(SS.db.combat, "burst", "quick menu: mode")
click(mm, "RightButton"); click(SS.quick.items[7]); eq(SS.db.indicator.show, false, "quick menu: indicator hide")
click(mm, "RightButton"); click(SS.quick.items[7]); eq(SS.db.indicator.show, true, "quick menu: indicator show")
SS.db.specProfiles.HOLY = { rules = { ["Holy Light"] = { "Libram of Radiance" } }, off = {} }
click(mm, "RightButton"); click(SS.quick.items[3]); ok(rulesOf("Holy Light") ~= nil, "quick menu: load the Holy rules")
click(mm, "RightButton"); click(SS.quick.items[8]); ok(UI.frame:IsShown(), "quick menu: open the menu"); UI.frame:Hide()
UnitClass = function() return "Shaman", "SHAMAN" end
click(mm, "RightButton"); eq(SS.quick.items[3].shown, false, "spec entries hidden for other classes"); SS.quick:Hide()
UnitClass = function() return "Paladin", "PALADIN" end
click(mm, "RightButton"); MouseIsOver = function() return false end
for i = 1, 20 do W.advance(0.1) end
ok(not SS.quick:IsShown(), "quick menu hides when the mouse leaves"); MouseIsOver = nil
W.equip(ITEM.Light); SS.MinimapIcon(); eq(mm.icon.tex, "Interface/Icons/Item" .. ITEM.Light, "icon = equipped relic texture")
W.cinv[18] = nil; SS.MinimapIcon(); eq(mm.icon.tex, SS.MM_DEFAULT_ICON, "default icon when nothing is equipped")
local sb, si = SS.mmButton, SS.indicator
SS.mmButton = nil; SS.indicator = nil
local cf = CreateFrame; CreateFrame = function() error("no frames today") end
ok(pcall(SS.ApplyDisplay), "ApplyDisplay never raises"); ok(SS.lastError ~= nil, "failure remembered")
CreateFrame = cf; SS.lastError = nil; SS.mmButton = sb; SS.indicator = si; SS.ApplyDisplay()

-- ============================================================ 7. floating indicator
section("indicator")
pally(); W.fire("PLAYER_LOGIN")
local ind = SS.indicator
ok(ind ~= nil and ind.shown, "indicator built and shown")
SS.IndicatorTick(W.now); eq(ind.icon.tex, "Interface/Icons/Item" .. ITEM.Hope, "shows the equipped relic icon")
eq(ind.text.text, "", "no countdown out of combat")
SS.SetRule("Holy Light", { "Libram of Radiance" }); SS.db.combat = "burst"
W.combat = true; press("Holy Light"); W.advance(0.2)
ok(SS.lastSwapCombat ~= nil, "combat swap time recorded")
SS.IndicatorTick(W.now); ok(ind.text.text ~= "" and tonumber(ind.text.text) > 0 and tonumber(ind.text.text) <= 1.5, "countdown shown after a combat swap: " .. tostring(ind.text.text))
local c1 = tonumber(ind.text.text); W.advance(0.5); SS.IndicatorTick(W.now); ok(tonumber(ind.text.text) < c1, "countdown decreases")
ok(ind.icon.vc and ind.icon.vc[1] < 1, "icon dimmed while counting")
W.advance(1.5); SS.IndicatorTick(W.now); eq(ind.text.text, "", "countdown ends"); eq(ind.icon.vc[1], 1, "icon back to normal")
eq(SS.SwapCooldownRemaining(W.now), 0, "remaining 0")
W.combat = false; SS.lastSwapCombat = W.now; W.advance(0.2); ok(ind.text.text ~= "", "OnUpdate keeps the countdown fresh")
SS.lastSwapCombat = nil; W.advance(2); W.equip(ITEM.Hope); SS.bagDirty = true; press("Holy Light"); W.advance(0.3); SS.IndicatorTick(W.now); eq(ind.text.text, "", "swap out of combat is free : no countdown")
this = ind; ind.moving = false; ind.scripts.OnDragStart(); ok(ind.moving, "unlocked : can be dragged")
ind.left, ind.top = 300, 400; ind.scripts.OnDragStop(); eq(SS.db.indicator.x, 300, "position saved"); eq(SS.db.indicator.y, 400, "position saved (y)")
cmd("indicator lock"); eq(SS.db.indicator.locked, true, "locked"); ind.moving = false; ind.scripts.OnDragStart(); eq(ind.moving, false, "locked : cannot be dragged"); this = nil
cmd("indicator unlock"); eq(SS.db.indicator.locked, false, "unlocked")
cmd("indicator scale 2"); eq(SS.db.indicator.scale, 2, "scale 2"); eq(ind.scale, 2, "frame scaled"); ok(math.abs(SS.db.indicator.x - 150) < 0.01, "saved offsets converted so the icon stays put")
cmd("indicator scale 9"); eq(SS.db.indicator.scale, 2.5, "scale clamped to 2.5"); cmd("indicator scale 0.1"); eq(SS.db.indicator.scale, 0.5, "clamped to 0.5")
cmd("indicator scale nonsense"); ok(W.chatHas("Usage"), "bad scale argument")
cmd("indicator reset"); ok(SS.db.indicator.x == nil and SS.db.indicator.scale == 1.0, "reset")
cmd("indicator off"); ok(not ind.shown, "hidden"); eq(SS.db.indicator.show, false, "saved")
local ups = 0; local oldU = ind.scripts.OnUpdate; ind.scripts.OnUpdate = function() ups = ups + 1 end; W.advance(0.5); eq(ups, 0, "a hidden indicator gets no OnUpdate")
ind.scripts.OnUpdate = oldU; cmd("indicator on"); ok(ind.shown, "shown again")
cmd("indicator bogus"); ok(W.chatHas("Usage"), "usage on a bad argument")
this = ind; ind.scripts.OnEnter(); this = nil; ok(W.tipHas("Libram") or W.tipHas("Hope"), "tooltip shows the relic")

-- ============================================================ 8. missing relic alert
section("alert")
pally(); SS.SetRule("Consecration", { "Libram of Hallowed Ground" }); SS.SetRule("Holy Light", { "Libram of Virtue" }); SS.SetRule("Cleanse", { "Libram of Grace" })
W.combat = true; W.fire("PLAYER_REGEN_DISABLED"); W.chat = {}
press("Consecration")
ok(W.chatHas("Missing relic for Consecration"), "alert in the chat"); eq(W.castCount("Consecration"), 1, "the cast still leaves")
W.chat = {}; W.advance(2); press("Consecration"); ok(not W.chatHas("Missing relic"), "no spam: once per spell and per combat")
press("Holy Light"); ok(W.chatHas("Missing relic for Holy Light"), "another spell alerts on its own")
W.chat = {}; W.combat = false; W.fire("PLAYER_REGEN_ENABLED"); W.combat = true; W.fire("PLAYER_REGEN_DISABLED"); W.advance(2); press("Consecration")
ok(W.chatHas("Missing relic for Consecration"), "alerts again in the next combat")
SS.db.alert.chat = false; W.chat = {}; W.fire("PLAYER_REGEN_DISABLED"); W.advance(2); press("Consecration"); ok(not W.chatHas("Missing relic"), "chat alert can be turned off")
SS.db.alert.sound = true; W.fire("PLAYER_REGEN_DISABLED"); W.advance(2); press("Consecration"); eq(table.getn(W.sounds), 1, "optional sound played once")
W.advance(2); press("Consecration"); eq(table.getn(W.sounds), 1, "sound not repeated")
SS.db.alert.chat, SS.db.alert.sound = true, false
W.fire("PLAYER_REGEN_DISABLED"); W.chat = {}; W.advance(2); press("Cleanse"); ok(W.chatHas("Missing relic for Cleanse"), "Grace not owned -> alert")
W.putBag(0, 9, ITEM.Grace); SS.bagDirty = true; W.fire("PLAYER_REGEN_DISABLED"); W.chat = {}; W.advance(2); press("Cleanse"); ok(not W.chatHas("Missing relic"), "relic present : no alert")
SS.db.off["Consecration"] = true; W.fire("PLAYER_REGEN_DISABLED"); W.chat = {}; W.advance(2); press("Consecration"); ok(not W.chatHas("Missing relic"), "rule switched off : no alert")
SS.db.off["Consecration"] = nil; SS.db.enabled = false; W.chat = {}; W.fire("PLAYER_REGEN_DISABLED"); press("Consecration"); ok(not W.chatHas("Missing relic"), "addon off : no alert")
SS.db.enabled = true
cmd("alert test"); ok(W.chatHas("how a missing-relic alert looks"), "/ssw alert test")
cmd("alert chat off"); eq(SS.db.alert.chat, false, "alert chat off"); cmd("alert sound on"); eq(SS.db.alert.sound, true, "alert sound on"); cmd("alert chat maybe"); ok(W.chatHas("Usage"), "usage")
fresh(); SS.SetRule("Consecration", { "Libram of Hallowed Ground" }); local ra = SS.AlertMissing; SS.AlertMissing = function() error("boom") end
W.combat = true; press("Consecration"); eq(W.castCount("Consecration"), 1, "alert error : cast still leaves"); eq(SS.stats.errors, nil, "alert error is contained"); SS.AlertMissing = ra

-- ============================================================ 9. bindings
section("bindings")
fresh()
ok(type(BINDING_HEADER_SHIKASWAP) == "string", "header label")
ok(type(BINDING_NAME_SHIKASWAP_MENU) == "string" and type(BINDING_NAME_SHIKASWAP_TOGGLE) == "string" and type(BINDING_NAME_SHIKASWAP_MODE) == "string", "binding labels defined")
local names = { "SHIKASWAP_MENU", "SHIKASWAP_TOGGLE", "SHIKASWAP_MODE" }
for i = 1, 3 do
    local nm = names[i]
    ok(string.find(BINDINGS_XML, '<Binding name="' .. nm .. '"', 1, true), "Bindings.xml declares " .. nm)
    ok(type(getglobal("BINDING_NAME_" .. nm)) == "string", "label exists for " .. nm)
end
ok(string.find(BINDINGS_XML, 'header="SHIKASWAP"', 1, true), "Bindings.xml header")
ok(string.find(BINDINGS_XML, 'ShikaSwap.Bind("menu")', 1, true) and string.find(BINDINGS_XML, 'ShikaSwap.Bind("toggle")', 1, true) and string.find(BINDINGS_XML, 'ShikaSwap.Bind("mode")', 1, true), "XML bodies call SS.Bind")
ok(not string.find(BINDINGS_XML, "|", 1, true), "no pipe in the XML")
SS.Bind("menu"); ok(UI.frame:IsShown(), "key: open the menu"); SS.Bind("menu"); ok(not UI.frame:IsShown(), "key: close the menu")
SS.Bind("toggle"); eq(SS.db.enabled, false, "key: disable"); SS.Bind("toggle"); eq(SS.db.enabled, true, "key: enable")
SS.Bind("mode"); eq(SS.db.combat, "burst", "key: next mode"); SS.Bind("mode"); eq(SS.db.combat, "wait", "key: next mode again")
ok(pcall(SS.Bind, "nonsense"), "unknown action ignored"); ok(pcall(SS.Bind, nil), "nil action ignored")
local ops = SS.cmds.menu; SS.cmds.menu = function() error("boom") end; ok(pcall(SS.Bind, "menu"), "a failing action never raises into the key handler"); SS.cmds.menu = ops
ShikaSwapDB = nil; SS.db = nil; ok(pcall(SS.Bind, "toggle"), "binding before the db exists is safe")
SS.InitDB()

-- ============================================================ 10. diagnostics tab
section("diagnostic")
pally(); open(); UI.SetTab(5)
ok(hasText(UI.tabs[5].out, "combat mode"), "status shown when the tab opens")
W.chat = {}; click(btn("dstatus")); eq(table.getn(W.chat), 0, "diagnostic output is not sent to the chat")
ok(SS.sink == nil, "capture sink released")
click(btn("dtrace")); eq(SS.db.trace, true, "trace on from the tab"); ok(hasText(btn("dtrace"), "ON"), "button shows ON")
SS.SetRule("Holy Light", { "Libram of Radiance" }); press("Holy Light"); click(btn("dlog"))
ok(hasText(UI.tabs[5].out, "Holy Light"), "decision log shown")
click(btn("dcheck")); ok(hasText(UI.tabs[5].out, "Holy Light") or hasText(UI.tabs[5].out, "No problem"), "check output shown")
click(btn("ddebug")); eq(SS.db.debug, true, "debug on"); click(btn("ddebug")); eq(SS.db.debug, false, "debug off")
click(btn("dclear")); eq(UI.tabs[5].out.text, "", "clear")
for i = 1, 40 do UI.Capture(SS.cmds.status) end
ok(table.getn(UI.diagLines) <= 300, "diagnostic buffer capped")
click(btn("dup")); ok(UI.diagOffset > 0, "scroll up")
UI.Capture(function() error("boom") end); ok(string.find(table.concat(UI.diagLines, "\n"), "error: ", 1, true), "error captured in the view")
ok(SS.sink == nil, "sink released after an error")

-- ============================================================ 11. languages
section("languages")
pally(); open()
SS.db.lang = "fr"; UI.SetTab(1); UI.Refresh()
ok(hasText(UI.tabButtons[2], "Réglages"), "tab names in French"); ok(hasText(UI.tabs[1].h2, "prioritaire"), "headers in French")
UI.SetTab(2); ok(hasText(def(UI.CHECKS, "minimap").widget.label, "Afficher"), "settings in French")
SS.db.lang = "en"; UI.Refresh(); ok(hasText(def(UI.CHECKS, "minimap").widget.label, "Show"), "settings in English")
local missing = {}
for k in pairs(SS.M.en) do if SS.M.fr[k] == nil then missing[table.getn(missing) + 1] = k end end
for k in pairs(SS.M.fr) do if SS.M.en[k] == nil then missing[table.getn(missing) + 1] = k end end
eq(table.concat(missing, ","), "", "every text exists in EN and FR")
local function uses(k) return SS.M.en[k] ~= nil end
for i = 1, table.getn(UI.CHECKS) do ok(uses(UI.CHECKS[i].text) and uses(UI.CHECKS[i].tip), "texts for check " .. UI.CHECKS[i].id) end
for i = 1, table.getn(UI.BUTTONS) do ok(uses(UI.BUTTONS[i].tip), "tooltip text for button " .. UI.BUTTONS[i].id) end
SS.db.lang = "auto"
UI.frame:Hide()

-- ============================================================ 12. saved variables : schema, migration, persistence
section("schema")
ShikaSwapDB = { version = 1, rules = { ["Holy Light"] = { "Libram of Radiance" } }, off = { ["Holy Light"] = true }, combat = "wait", profiles = { a = { rules = {}, off = {} } } }
SS.InitDB()
eq(SS.db.version, SS.SCHEMA, "schema 1 migrated to the current schema"); eq(SS.db.rules["Holy Light"][1], "Libram of Radiance", "rules kept"); eq(SS.db.off["Holy Light"], true, "disabled flags kept")
eq(SS.db.combat, "wait", "mode kept"); ok(SS.db.profiles.a ~= nil, "profiles kept")
ok(SS.db.minimap.show == true and SS.db.minimap.angle == 200, "minimap defaults added"); ok(SS.db.indicator.show and SS.db.indicator.scale == 1.0 and not SS.db.indicator.locked, "indicator defaults")
ok(SS.db.alert.chat == true and SS.db.alert.sound == false, "alert defaults"); eq(SS.db.autoSpec, false, "autoSpec default"); ok(type(SS.db.specProfiles) == "table" and type(SS.db.ui) == "table", "tables added")
ShikaSwapDB = { version = 2, minimap = "bad", indicator = { show = "yes", scale = 99, locked = 5, x = "a", y = 3 }, alert = { chat = nil, sound = "x" },
    specProfiles = { HOLY = { rules = { a = { "b" } } }, JUNK = { rules = {} }, RET = "bad" }, specManual = "nope", lastSpec = 5, autoSpec = "yes", ui = 7 }
SS.InitDB()
ok(SS.db.minimap.show == true, "corrupt minimap table replaced"); eq(SS.db.indicator.scale, 1.0, "out-of-range scale reset"); eq(SS.db.indicator.show, true, "bad boolean -> default")
eq(SS.db.indicator.x, nil, "half-valid position dropped"); eq(SS.db.alert.chat, true, "missing boolean -> default"); eq(SS.db.alert.sound, false, "bad boolean -> default")
ok(SS.db.specProfiles.HOLY ~= nil and SS.db.specProfiles.JUNK == nil and SS.db.specProfiles.RET == nil, "invalid spec profiles dropped"); eq(SS.db.specManual, nil, "bad manual spec dropped")
eq(SS.db.lastSpec, nil, "bad last spec dropped"); eq(SS.db.autoSpec, false, "bad autoSpec -> false"); eq(type(SS.db.ui), "table", "bad ui table replaced")
ShikaSwapDB = { version = 7, rules = {} }; SS.InitDB(); eq(SS.db.version, 7, "a newer schema number is never lowered")
ShikaSwapDB = { minimap = { angle = 0 / 0 } }; SS.InitDB(); eq(SS.db.minimap.angle, 200, "NaN angle replaced")
pally(); open(); UI.SetTab(2)
box("minimap", nil); box("alertsound", 1); click(btn("lang")); cmd("indicator scale 1.7"); SS.NextMode()
local saved = ShikaSwapDB
ok(saved.minimap.show == false and saved.alert.sound == true and saved.lang == "fr" and saved.indicator.scale == 1.7 and saved.combat == "burst", "all menu settings are stored in the saved variable table")
ShikaSwapDB = saved; SS.InitDB(); W.fire("PLAYER_LOGIN")
ok(not SS.mmButton.shown, "after a reload the minimap button stays hidden"); eq(SS.indicator.scale, 1.7, "after a reload the indicator keeps its size")
cmd("lang auto")
UI.frame:Hide()

-- ============================================================ 13. regression with the display layer on
section("regression")
pally(); W.fire("PLAYER_LOGIN"); SS.SetRule("Holy Light", { "Libram of Radiance" })
press("Holy Light"); W.advance(0.3); eq(W.sinv[18], ITEM.Radiance, "swap still works with menu, minimap and indicator loaded"); eq(W.castCount("Holy Light"), 1, "cast leaves")
eq(SS.stats.errors, nil, "no internal error")
fresh(); SS.SetRule("Holy Light", { "Libram of Radiance" }); UI.frame = nil
local cf2 = CreateFrame; CreateFrame = function() error("ui broken") end
cmd("menu"); ok(W.chatHas("menu error"), "build failure reported, not raised"); CreateFrame = cf2
press("Holy Light"); W.advance(0.3); eq(W.castCount("Holy Light"), 1, "cast unaffected by a broken menu")
cmd("menu"); ok(UI.frame ~= nil and UI.frame:IsShown(), "menu works again once frames can be created")

print(string.format("RESULT: %d passed, %d failed", PASSES, FAILS))
if FAILS > 0 then error("TESTS FAILED: " .. FAILS) end
