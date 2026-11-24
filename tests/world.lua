-- world.lua : WoW 1.12 world mock for the ShikaSwap tests (loaded by harness_shikaswap.js).
-- It models what matters for swap logic: bags, relic slot 18, a spellbook with cooldowns + the global cooldown,
-- server latency (the server swaps after `latency`, the client sees it after 2*latency), the in-combat swap GCD
-- (client-side cooldown that arrives AFTER the swap) and the 1.12 rule "event handlers get no arguments".
local G = WORLD_G

W = {
    now = 1000, combat = false, dead = false, cursor = false, locale = "enUS",
    latency = 0.05,
    syncEquip = false,          -- client updates slot 18 synchronously at UseContainerItem
    localGcdOnEquip = false,    -- H2 : client applies the swap GCD at call time (cast in the same frame is refused)
    serverGcdOnEquip = false,   -- H3 : server also rejects casts during the swap GCD
    gcdLen = 1.5,
    cinv = {}, cbags = {}, sinv = {}, sbags = {},   -- client / server views : inv[18], bags[b][s]
    bagSize = { [0] = 16, 0, 0, 0, 0 },
    items = {}, book = {}, spellCd = {}, gcd = { start = 0, dur = 0 },
    ops = {}, log = {}, frames = {}, named = {}, actions = {}, castTime = {},
    weaponTimer = 0, tgt = nil, locked = {}, visible = {},
}
for b = 0, 4 do W.cbags[b] = {}; W.sbags[b] = {} end

local function logf(s) W.log[table.getn(W.log) + 1] = string.format("%.2f %s", W.now, s) end
W.logf = logf
function W.logHas(sub)
    for i = 1, table.getn(W.log) do if string.find(W.log[i], sub, 1, true) then return true end end
    return false
end
function W.logCount(sub)
    local n = 0
    for i = 1, table.getn(W.log) do if string.find(W.log[i], sub, 1, true) then n = n + 1 end end
    return n
end

-- ---------------------------------------------------------------- items
function W.addItem(id, name) W.items[id] = name end
local function link(id)
    if not id then return nil end
    return "|cff0070dd|Hitem:" .. id .. ":0:0:0|h[" .. tostring(W.items[id] or ("Item" .. id)) .. "]|h|r"
end
function W.putBag(b, s, id) W.cbags[b][s] = id; W.sbags[b][s] = id end
function W.equip(id) W.cinv[18] = id; W.sinv[18] = id end
function W.clearBags() for b = 0, 4 do W.cbags[b] = {}; W.sbags[b] = {} end end

GetTime = function() return W.now end
GetNetStats = function() return 0, 0, W.latency * 2000 end   -- round trip in ms
GetLocale = function() return W.locale end
UnitAffectingCombat = function() if W.combat then return 1 end return nil end
UnitClassification = function(u) if u == "target" and W.tgt then if W.tgt.boss == false then return "normal" end return "worldboss" end return nil end
UnitLevel = function(u) if u == "target" and W.tgt and W.tgt.boss == false then return 60 end return -1 end
UnitIsDeadOrGhost = function() if W.dead then return 1 end return nil end
CursorHasItem = function() if W.cursor then return true end return nil end
UnitClass = function() return "Paladin", "PALADIN" end
UnitExists = function(u) if u == "target" and W.tgt then return 1, (W.tgt.guid or "0xB055") end return nil end
UnitName = function(u) if u == "target" and W.tgt then return W.tgt.name or "Boss" end return "Player" end
UnitCanAttack = function() return 1 end
UnitHealth = function() return W.tgt and W.tgt.hp or 0 end
UnitHealthMax = function() return W.tgt and W.tgt.max or 0 end
GetInventoryItemLink = function(u, slot) return link(W.cinv[slot]) end
GetContainerNumSlots = function(b) return W.bagSize[b] or 0 end
GetContainerItemLink = function(b, s) return link(W.cbags[b] and W.cbags[b][s]) end
GetContainerItemInfo = function(b, s)
    local id = W.cbags[b] and W.cbags[b][s]
    if not id then return nil end
    return "tex", 1, W.locked[b * 1000 + s] and 1 or nil, 3, nil
end
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) W.chat = W.chat or {}; W.chat[table.getn(W.chat) + 1] = m end }
function W.chatHas(sub)
    for i = 1, table.getn(W.chat or {}) do if string.find(W.chat[i], sub, 1, true) then return true end end
    return false
end
SlashCmdList = {}
WorldFrame = {}
UIParent = {}
UISpecialFrames = {}
W.shift = false
W.epoch = 1793000000
time = function() return W.epoch + math.floor(W.now - 1000) end
date = function(f, t) return os.date(f, t or time()) end
IsShiftKeyDown = function() if W.shift then return 1 end return nil end
W.sounds = {}
PlaySound = function(n) W.sounds[table.getn(W.sounds) + 1] = n end
W.talents = nil
GetNumTalentTabs = function() if not W.talents then return 0 end return table.getn(W.talents) end
GetTalentTabInfo = function(i) local t = W.talents and W.talents[i]; if not t then return nil end return t.name, "tex", t.pts, t.bg or "" end
W.itemInfo = {}
W.spellTex = {}
-- GetItemInfo("item:ID:0:0:0") -> name, link, quality, minLevel, type, subType, stack, equipLoc, texture  (nil when the item is not cached)
GetItemInfo = function(x)
    local id = tonumber(x)
    if not id then id = tonumber((string.gsub(tostring(x), "^item:(%d+).*$", "%1"))) end
    local t = id and W.itemInfo[id]
    if not t then return nil end
    return t.name or "x", "link", 3, 1, "Armor", "Librams", 1, "INVTYPE_RELIC", t.tex
end
GetSpellTexture = function(i, bt) return W.spellTex[i] end
GetInventoryItemTexture = function(u, slot) local id = W.cinv[slot]; if not id then return nil end return "Interface/Icons/Item" .. id end
W.cursor_xy = { 0, 0 }
GetCursorPosition = function() return W.cursor_xy[1], W.cursor_xy[2] end

-- ---------------------------------------------------------------- spellbook / cooldowns
function W.setBook(list) W.book = list end
GetSpellName = function(i, bt)
    local e = W.book[i]
    if not e then return nil end
    return e.name, e.rank or ""
end
local function spellRem(name)
    local rem, dur = 0, 0
    local c = W.spellCd[name]
    if c and c.start + c.dur > W.now then rem = c.start + c.dur - W.now; dur = c.dur end
    if rem == 0 and not (W.noGcd and W.noGcd[name]) and W.gcd.start + W.gcd.dur > W.now then rem = W.gcd.start + W.gcd.dur - W.now; dur = W.gcd.dur end
    return rem, dur
end
W.spellRem = spellRem
GetSpellCooldown = function(i, bt)
    local e = W.book[i]
    if not e then return nil end
    local c = W.spellCd[e.name]
    if c and c.start + c.dur > W.now then return c.start, c.dur, 1 end
    if W.noGcd and W.noGcd[e.name] then return 0, 0, 1 end
    if W.gcd.start + W.gcd.dur > W.now then return W.gcd.start, W.gcd.dur, 1 end
    return 0, 0, 1
end

-- ---------------------------------------------------------------- frames
local function newFrame(name, kind)
    local f = { name = name, kind = kind, scripts = {}, events = {}, shown = true, text = nil }
    setmetatable(f, { __index = function(t, k)
        if type(k) == "string" and string.find(k, "^%u") then return function() return t end end
        return nil
    end })
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    f.GetScript = function(self, k) return self.scripts[k] end
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.Show = function(self)
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then local keep = this; this = self; self.scripts.OnShow(); this = keep end
    end
    f.Hide = function(self)
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then local keep = this; this = self; self.scripts.OnHide(); this = keep end
    end
    f.SetChecked = function(self, v) self.checked = v and 1 or nil end
    f.GetChecked = function(self) return self.checked end
    f.Enable = function(self) self.disabled = false end
    f.Disable = function(self) self.disabled = true end
    f.IsEnabled = function(self) if self.disabled then return nil end return 1 end
    f.SetPoint = function(self, ...) self.points = self.points or {}; self.points[table.getn(self.points) + 1] = { ... } end
    f.ClearAllPoints = function(self) self.points = {} end
    f.SetScale = function(self, v) self.scale = v end
    f.GetScale = function(self) return self.scale or 1 end
    f.SetWidth = function(self, v) self.w = v end
    f.SetHeight = function(self, v) self.h = v end
    f.GetWidth = function(self) return self.w end
    f.GetHeight = function(self) return self.h end
    f.SetTexture = function(self, v, g, b, a) self.tex = v; self.texArgs = { v, g, b, a } end
    f.SetTextColor = function(self, r, g, b) self.textColor = { r, g, b } end
    f.SetBackdrop = function(self, t) self.backdrop = t end
    f.SetBackdropBorderColor = function(self, r, g, b, a) self.borderColor = { r, g, b, a } end
    f.SetBackdropColor = function(self, r, g, b, a) self.bgColor = { r, g, b, a } end
    f.GetFontString = function(self) self.fontString = self.fontString or newFrame(nil, "FontString"); return self.fontString end
    f.SetVertexColor = function(self, r, g, b) self.vc = { r, g, b } end
    f.SetAlpha = function(self, v) self.alpha = v end
    f.SetFrameLevel = function(self, v) self.level = v end
    f.StartMoving = function(self) self.moving = true end
    f.StopMovingOrSizing = function(self) self.moving = false end
    f.GetLeft = function(self) return self.left end
    f.GetTop = function(self) return self.top end
    f.GetCenter = function(self) return self.cx, self.cy end
    f.GetEffectiveScale = function(self) return 1 end
    f.ClearFocus = function(self) self.focus = false end
    f.CreateFontString = function(self) local c = newFrame(nil, "FontString"); c.parent = self; return c end
    f.CreateTexture = function(self) local c = newFrame(nil, "Texture"); c.parent = self; return c end
    f.IsShown = function(self) return self.shown and true or nil end
    f.IsVisible = function(self) return self.shown and true or nil end
    f.GetName = function(self) return self.name end
    f.GetText = function(self) return self.text end
    f.SetText = function(self, t) self.text = t end
    return f
end
CreateFrame = function(kind, name, parent, tmpl)
    local f = newFrame(name, kind)
    f.parent = parent
    if name then G[name] = f end
    W.frames[table.getn(W.frames) + 1] = f
    if kind == "GameTooltip" and name then
        f.SetOwner = function() end
        f.SetAction = function(self, slot)
            local a = W.actions[slot]
            G[name .. "TextLeft1"].text = a and a.name or nil
            G[name .. "TextRight1"].text = a and a.rank or nil
        end
        G[name .. "TextLeft1"] = newFrame(name .. "TextLeft1")
        G[name .. "TextRight1"] = newFrame(name .. "TextRight1")
    end
    return f
end
Minimap = newFrame("Minimap", "Frame")
Minimap.cx, Minimap.cy = 500, 500
W.tip = {}
W.hyper = {}
GameTooltip = { SetHyperlink = function(self, l) if W.hyperFail then error("bad hyperlink") end W.tip = { owner = (W.tip or {}).owner }; W.hyper[table.getn(W.hyper) + 1] = l; W.tip[1] = "HYPERLINK:" .. l end,
    SetOwner = function(self, o) W.tip = { owner = o } end, SetText = function(self, t) W.tip[table.getn(W.tip) + 1] = t end,
    AddLine = function(self, t) W.tip[table.getn(W.tip) + 1] = t end, Show = function(self) W.tip.shown = true end, Hide = function(self) W.tip.shown = false end }
function W.tipHas(sub)
    for i = 1, table.getn(W.tip) do if string.find(tostring(W.tip[i]), sub, 1, true) then return true end end
    return false
end
-- named UI windows that must block swaps when open
function W.showWindow(name)
    local f = G[name] or newFrame(name)
    f.shown = true
    G[name] = f
end
function W.hideWindow(name) if G[name] then G[name].shown = false end end

-- ---------------------------------------------------------------- events / time
function W.fire(ev, a1, a2)
    event = ev; arg1 = a1; arg2 = a2
    for i = 1, table.getn(W.frames) do
        local f = W.frames[i]
        if f.events[ev] and f.scripts.OnEvent then this = f; f.scripts.OnEvent(); this = nil end   -- NO arguments : 1.12 (only the globals this/event/arg1..)
    end
    event = nil; arg1 = nil; arg2 = nil
end

local function runOps()
    local i = 1
    while i <= table.getn(W.ops) do
        local o = W.ops[i]
        if o.at <= W.now + 1e-9 then
            table.remove(W.ops, i)
            o.fn()
        else
            i = i + 1
        end
    end
end

function W.step(dt)
    W.now = W.now + dt
    runOps()
    for i = 1, table.getn(W.frames) do
        local f = W.frames[i]
        if f.shown and f.scripts.OnUpdate then
            arg1 = dt
            this = f
            f.scripts.OnUpdate()
            this = nil
            arg1 = nil
        end
    end
end
function W.advance(t)
    local n = math.floor(t / 0.01 + 0.5)
    for i = 1, n do W.step(0.01) end
end
function W.later(dt, fn) W.ops[table.getn(W.ops) + 1] = { at = W.now + dt, fn = fn } end

-- ---------------------------------------------------------------- equip (UseContainerItem)
local function clientSwapView()
    for b = 0, 4 do
        for s = 1, (W.bagSize[b] or 0) do W.cbags[b][s] = W.sbags[b][s] end
    end
    W.cinv[18] = W.sinv[18]
end
UseContainerItem = function(b, s)
    logf("UCI " .. b .. " " .. s)
    if W.visible.MerchantFrame or (G.MerchantFrame and G.MerchantFrame.shown) then logf("SOLD item from bag " .. b .. " " .. s) end
    local inCombat = W.combat
    if W.localGcdOnEquip and inCombat then W.gcd = { start = W.now, dur = W.gcdLen } end
    W.later(W.latency, function()   -- the server handles it
        local id = W.sbags[b] and W.sbags[b][s]
        if not id then logf("SERVER: empty slot " .. b .. " " .. s); return end
        local old = W.sinv[18]
        W.sinv[18] = id
        W.sbags[b][s] = old
        logf("SERVER: equipped " .. tostring(W.items[id]) .. " (old " .. tostring(old and W.items[old]) .. ")")
        local t1 = W.now
        W.later(W.latency, function()   -- the client sees it
            clientSwapView()
            if inCombat and t1 >= W.weaponTimer then
                W.gcd = { start = W.now, dur = W.gcdLen }
                W.weaponTimer = t1 + W.gcdLen
                logf("CLIENT: combat swap GCD")
            end
            W.fire("UNIT_INVENTORY_CHANGED", "player")
            W.fire("BAG_UPDATE", 0)
        end)
        if W.serverGcdOnEquip and inCombat then W.serverGcdUntil = t1 + W.gcdLen end
    end)
    if W.syncEquip then
        local id = W.cbags[b][s]
        if id then
            local old = W.cinv[18]
            W.cinv[18] = id; W.cbags[b][s] = old
        end
    end
end

-- ---------------------------------------------------------------- casting (the ORIGINAL functions)
local origClientCast
function origClientCast(base, rank, src)
    local idx
    for i = 1, table.getn(W.book) do
        if W.book[i].name == base and (not rank or W.book[i].rank == rank) then idx = i end
    end
    if not idx then logf("CAST-UNKNOWN " .. tostring(base)); return end
    local rem = spellRem(base)
    -- Nampower-like spell queue : a cast pressed shortly before its cooldown / GCD ends is held and sent at the end (one slot, last press wins)
    if rem > 0.0001 and W.nampower and rem <= (W.npWindow or 0.5) and not (src and string.find(src, "queued", 1, true)) then
        logf("NP-QUEUED " .. base .. " (" .. string.format("%.2f", rem) .. ")")
        W.npSeq = (W.npSeq or 0) + 1
        local seq = W.npSeq
        W.npPending = { name = base, seq = seq }
        W.later(rem + 0.001, function() if W.npPending and W.npPending.seq == seq then W.npPending = nil; origClientCast(base, rank, "queued") end end)
        return
    end
    if rem > 0.0001 then
        logf("REFUSED " .. base .. " (client cooldown " .. string.format("%.2f", rem) .. ")")
        W.fire("UI_ERROR_MESSAGE", "Spell is not ready yet.")
        return
    end
    if W.serverGcdUntil and W.now < W.serverGcdUntil then
        logf("SERVER-REJECT " .. base)
        W.fire("UI_ERROR_MESSAGE", "Spell is not ready yet.")
        return
    end
    logf("CAST " .. base .. (src and (" [" .. src .. "]") or ""))
    W.casts = W.casts or {}
    local rec = { name = base, at = W.now }
    W.casts[table.getn(W.casts) + 1] = rec
    W.later(W.latency, function() rec.relic = W.sinv[18] end)   -- the server resolves the cast after the equip packet sent before it
    if not (W.noGcd and W.noGcd[base]) then W.gcd = { start = W.now, dur = W.gcdLen } end
    if W.realCd and W.realCd[base] then W.spellCd[base] = { start = W.now, dur = W.realCd[base] } end
    if W.castTime[base] then
        W.fire("SPELLCAST_START", base, W.castTime[base] * 1000)
        W.later(W.castTime[base], function() W.fire("SPELLCAST_STOP") end)
    end
end
function W.castCount(name)
    local n = 0
    for i = 1, table.getn(W.casts or {}) do if W.casts[i].name == name then n = n + 1 end end
    return n
end
CastSpellByName = function(spell, a2)
    local _, _, base, rnum = string.find(spell, "^(.-)%s*%(%s*[Rr]ank%s*(%d+)%s*%)%s*$")
    if not base then base = spell end
    origClientCast(base, rnum and ("Rank " .. rnum) or nil, "byname")
end
CastSpell = function(index, bt)
    local e = W.book[index]
    if e then origClientCast(e.name, e.rank, "book") end
end
HasAction = function(slot) return W.actions[slot] and true or nil end
GetActionText = function(slot)
    local a = W.actions[slot]
    if a and a.macro then return a.macro end
    return nil
end
UseAction = function(slot, a2, a3)
    local a = W.actions[slot]
    if not a then return end
    if a.macro then
        if a.run then a.run() end
        return
    end
    origClientCast(a.name, a.rank, "action")
end

-- ---------------------------------------------------------------- globals audit
function WORLD_snapshotGlobals()
    WORLD_BEFORE = {}
    for k in pairs(G) do WORLD_BEFORE[k] = true end
end
function WORLD_afterLoad()
    NEW_GLOBALS = {}
    for k in pairs(G) do
        if not WORLD_BEFORE[k] then NEW_GLOBALS[table.getn(NEW_GLOBALS) + 1] = k end
    end
    table.sort(NEW_GLOBALS)
end

-- ---------------------------------------------------------------- world helpers for the tests
ITEM = { Light = 23006, Divinity = 23201, Radiance = 55470, Virtue = 58139, FinalJ = 58240, Faithful = 61443,
         Farraki = 58093, Hallowed = 33086, Fervor = 23203, Dreamguard = 61203, Justicar = 61337, Resolute = 51804,
         Grace = 22402, RadiantDawn = 33235, EternalTower = 55110, Hope = 22401, Veracity = 51799, Ardour = 33087 }
NAME = { [23006] = "Libram of Light", [23201] = "Libram of Divinity", [55470] = "Libram of Radiance", [58139] = "Libram of Virtue",
         [58240] = "Libram of Final Judgement", [61443] = "Libram of the Faithful", [58093] = "Libram of the Farraki Zealot",
         [33086] = "Libram of Hallowed Ground", [23203] = "Libram of Fervor", [61203] = "Libram of the Dreamguard",
         [61337] = "Libram of the Justicar", [51804] = "Libram of the Resolute", [22402] = "Libram of Grace",
         [33235] = "Libram of the Radiant Dawn", [55110] = "Libram of the Eternal Tower", [22401] = "Libram of Hope",
         [51799] = "Libram of Veracity", [33087] = "Libram of Ardour" }
function W.reset()
    W.now = 1000; W.combat = false; W.dead = false; W.cursor = false
    W.latency = 0.05; W.syncEquip = false; W.localGcdOnEquip = false; W.serverGcdOnEquip = false; W.serverGcdUntil = nil
    W.cinv = {}; W.sinv = {}; W.ops = {}; W.log = {}; W.casts = {}; W.chat = {}
    W.spellCd = {}; W.gcd = { start = 0, dur = 0 }; W.weaponTimer = 0; W.tgt = nil; W.locked = {}; W.realCd = {}
    W.castTime = {}; W.actions = {}; W.visible = {}; W.itemInfo = {}; W.spellTex = {}; W.hyper = {}; W.hyperFail = nil; W.noGcd = nil; W.nampower = nil; W.npPending = nil; W.talents = nil; W.shift = false; W.sounds = {}; W.tip = {}; W.cursor_xy = { 0, 0 }
    W.clearBags()
    if G.MerchantFrame then G.MerchantFrame.shown = false end
    for id, n in pairs(NAME) do W.addItem(id, n) end
    W.setBook({
        { name = "Holy Light", rank = "Rank 1" }, { name = "Holy Light", rank = "Rank 2" }, { name = "Holy Light", rank = "Rank 3" },
        { name = "Flash of Light", rank = "Rank 1" }, { name = "Flash of Light", rank = "Rank 2" },
        { name = "Consecration", rank = "Rank 1" }, { name = "Judgement", rank = "" }, { name = "Holy Shock", rank = "Rank 1" },
        { name = "Cleanse", rank = "" }, { name = "Seal of the Crusader", rank = "Rank 1" }, { name = "Holy Strike", rank = "Rank 1" },
        { name = "Hand of Freedom", rank = "" }, { name = "Seal of Command", rank = "Rank 1" },
    })
end
