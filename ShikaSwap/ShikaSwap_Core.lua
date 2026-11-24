-- ShikaSwap_Core.lua : settings, relic/bag/spell lookups, swap decision (Plan), execution (Run), cast queue.
-- WoW 1.12 / Lua 5.0 : no '#', no string.match/gmatch, no '...', no '%' operator, no _G.
-- Everything lives in the single global table ShikaSwap (functions are fields -> very few upvalues per function).
--
-- SERVER FACTS this logic is built on (read in the Sunreach core source copy, Player.cpp, 2026-09-29):
--   * relics (libram/idol/totem, INVTYPE_RELIC) go to slot 18 (ranged) and CAN be swapped in combat;
--   * a relic/weapon swap IN COMBAT sends the client a 1.5 s "Combat Swap" global cooldown (spell 6119, GCD category 133)
--     only when the previous swap is older than 1.5 s; OUT of combat a swap is free;
--   * that cooldown is only SENT to the client (the server GCD manager is not touched by the swap).
-- What the client really does with it (can the swap and the cast leave in the same frame?) is NOT verifiable offline:
-- hence the self-measuring modes burst / wait / auto (see README).

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap

SS.version = "1.3.0"
SS.SLOT = 18               -- relic slot (server FindEquipSlot: INVTYPE_RELIC -> EQUIPMENT_SLOT_RANGED)
SS.GCD_MAX = 1.6           -- a cooldown longer than this is a real cooldown, not the global one
SS.EPS = 0.01              -- "ready" tolerance (s)
SS.PENDING_WINDOW = 1.5    -- how long a swap we sent is considered "in transit" (s)
SS.TICK = 0.03             -- queue polling period (s), only while something is queued
SS.stats = {}
SS.attempts = 0   -- number of cast attempts seen by the hooks (any spell)
SS.ring = {}
SS.ringN = 0
SS.RING_MAX = 40
SS.BLOCKERS = { "MerchantFrame", "BankFrame", "TradeFrame", "SendMailFrame", "MailFrame", "AuctionFrame", "GuildBankFrame" }

local string_find = string.find
local string_lower = string.lower
local string_gsub = string.gsub
local string_format = string.format
local tinsert = table.insert
local getn = table.getn

SS.SCHEMA = 4            -- saved-variable schema : 1 = rules/profiles/mode, 2 = + minimap, indicator, alert, specs, ui, 3 = + Necroladin slot, talent signature, 4 = + persistent trace, off-GCD policy

SS.DEFAULTS = {
    enabled = true,
    debug = false,
    trace = false,
    lang = "auto",       -- auto | en | fr
    combat = "auto",     -- auto | burst | wait | skip
    fallbacks = true,    -- use equivalent lower relics of the same effect group when the preferred one is missing
    queueTimeout = 3.0,  -- seconds a queued cast may wait
    opener = nil,        -- spell name whose relic is equipped out of combat (after a fight / at login)
    autoSpec = false,    -- switch the rules automatically when the talent spec changes (Paladin)
    execBoss = true,     -- the execute relic (Final Judgement, cond tgt35hold) is used on BOSSES only (skull / worldboss target)
    offGcd = "swap",     -- in combat, swap for a spell that has NO global cooldown (Judgement) : "swap" (default) | "skip"
}

-- Spells of the catalogue that do not use the global cooldown (Nampower log: "BeginCast ... NO Gcd" for Judgement(20271) only,
-- Spell.dbc 20271 StartRecoveryTime/Category = 0/0 ; see tools/check_offgcd.js). A swap in combat starts a 1.5 s GCD-category cooldown,
-- which these spells never have: swapping FOR one of them is a pure loss of time, and pressing one of them must not cancel a queued GCD cast.
SS.OFFGCD = { ["judgement"] = true }
function SS.IsOffGcd(name)
    return type(name) == "string" and SS.OFFGCD[string.lower(name)] == true
end

-- Necroladin preset : the player's old LibramSwap profile "necroladin" (tests/fixtures/LibramSwap_SHIKAWA.lua, profiles.necroladin).
-- { spell, relic, active }. Nothing here is invented : names and on/off flags are copied from that profile.
SS.NECRO_MAP = {
    { "Holy Shock", "Libram of the Radiant Dawn", false },   -- desactive par defaut (2026-11-19) : le swap de libram Holy Shock parasite le GCD de rotation
    { "Seal of the Crusader", "Libram of Fervor", true },
    { "Judgement", "Libram of Final Judgement", false },
    { "Seal of Righteousness", "Libram of Final Judgement", false },
    { "Holy Strike", "Libram of the Eternal Tower", false },
    { "Consecration", "Libram of the Faithful", false },
    { "Holy Light", "Libram of Radiance", false },
    { "Flash of Light", "Libram of Light", false },
    { "Cleanse", "Libram of Grace", false },
    { "Holy Shield", "Libram of the Dreamguard", false },
    { "Hand of Freedom", "Libram of the Resolute", false },
}

-- a fresh { rules, off } copy of the preset
function SS.NecroPreset()
    local rules, off = {}, {}
    for i = 1, getn(SS.NECRO_MAP) do
        local e = SS.NECRO_MAP[i]
        rules[e[1]] = { e[2] }
        if not e[3] then off[e[1]] = true end
    end
    return { rules = rules, off = off }
end

function SS.IsSpecToken(v)
    return v == "HOLY" or v == "PROT" or v == "RET" or v == "NECRO"
end

-- fresh copies of the nested settings (schema 2)
function SS.SubDefaults()
    return {
        minimap = { show = true, angle = 200 },
        indicator = { show = true, locked = false, scale = 1.0 },
        alert = { chat = true, sound = false },
        ui = {},
        specProfiles = {},
    }
end

local function Bool(v, d)
    if v == true or v == false then return v end
    if v == 1 then return true end
    if v == 0 then return false end
    return d
end

local function Num(v, d, lo, hi)
    if type(v) ~= "number" then return d end
    if v ~= v or v < lo or v > hi then return d end
    return v
end

-- bring ANY saved table (schema 1, missing, partly corrupt) to the current schema. Never raises, never drops the user's rules.
function SS.MigrateDB(db)
    local sub = SS.SubDefaults()
    for k, d in pairs(sub) do
        if type(db[k]) ~= "table" then db[k] = d end
    end
    local mm, ind, al = db.minimap, db.indicator, db.alert
    mm.show = Bool(mm.show, true)
    mm.angle = Num(mm.angle, 200, -720, 720)
    ind.show = Bool(ind.show, true)
    ind.locked = Bool(ind.locked, false)
    ind.scale = Num(ind.scale, 1.0, 0.5, 2.5)
    if ind.x ~= nil and (type(ind.x) ~= "number" or type(ind.y) ~= "number") then ind.x = nil ind.y = nil end
    al.chat = Bool(al.chat, true)
    al.sound = Bool(al.sound, false)
    db.autoSpec = Bool(db.autoSpec, false)
    local keep = {}
    for name, p in pairs(db.specProfiles) do
        if SS.IsSpecToken(name) and type(p) == "table" and type(p.rules) == "table" then
            keep[name] = { rules = p.rules, off = (type(p.off) == "table") and p.off or {} }
        end
    end
    db.specProfiles = keep
    if not keep.NECRO then keep.NECRO = SS.NecroPreset() end        -- schema 3 : the Necroladin slot always exists (preset until edited)
    if not SS.IsSpecToken(db.specManual) then db.specManual = nil end
    if not SS.IsSpecToken(db.lastSpec) then db.lastSpec = nil end
    db.necroTol = math.floor(Num(db.necroTol, 2, 0, 10))
    if db.offGcd ~= "swap" and db.offGcd ~= "skip" then db.offGcd = "swap" end
    if type(db.execBoss) ~= "boolean" then db.execBoss = true end
    if type(db.counts) ~= "table" then db.counts = {} end
    local cc = {}
    for k, v in pairs(db.counts) do
        if type(k) == "string" and type(v) == "number" and v == v and v >= 0 then cc[k] = v end
    end
    db.counts = cc
    -- persistent trace : armed for one week the first time this schema is seen, then silent (until /ssw trace on)
    if type(db.traceUntil) ~= "number" then db.traceUntil = (time and time() or 0) + 604800 end
    if type(db.trace_log) ~= "table" then db.trace_log = {} end
    local tn = tonumber(db.trace_n)
    if not tn or tn < 0 or tn > 100 then tn = 0 end
    db.trace_n = math.floor(tn)
    local cleanLog = {}
    for i = 1, 100 do
        if type(db.trace_log[i]) == "string" then cleanLog[i] = db.trace_log[i] end
    end
    db.trace_log = cleanLog
    local sig = db.necroSig
    if type(sig) == "table" and type(sig.HOLY) == "number" and type(sig.PROT) == "number" and type(sig.RET) == "number"
        and Num(sig.HOLY, nil, 0, 61) and Num(sig.PROT, nil, 0, 61) and Num(sig.RET, nil, 0, 61) and (sig.HOLY + sig.PROT + sig.RET) > 0 then
        db.necroSig = { HOLY = math.floor(sig.HOLY), PROT = math.floor(sig.PROT), RET = math.floor(sig.RET) }
    else
        db.necroSig = nil
    end
    if type(db.version) ~= "number" or db.version < SS.SCHEMA then db.version = SS.SCHEMA end
end

-- ---------------------------------------------------------------- i18n / output
SS.M = SS.M or { en = {}, fr = {} }

function SS.Lang()
    local l = SS.db and SS.db.lang or "auto"
    if l == "fr" or l == "en" then return l end
    if GetLocale and GetLocale() == "frFR" then return "fr" end
    return "en"
end

-- T(key, a, b, c, d): translated text; string.format is only used when arguments are given
function SS.T(key, a, b, c, d)
    local m = SS.M[SS.Lang()]
    local s = (m and m[key]) or SS.M.en[key] or key
    if a == nil then return s end
    return string_format(s, a, b, c, d)
end

function SS.Print(msg)
    if SS.sink then   -- the diagnostic tab of the menu captures command output here instead of the chat
        SS.sink[table.getn(SS.sink) + 1] = tostring(msg)
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF66CCFF[ShikaSwap]|r " .. tostring(msg))
    end
end

-- diagnostic trace hooks (replaced by ShikaSwap_Trace.lua ; harmless when that file is absent)
function SS.TL() end
function SS.TracePlan() end
function SS.TraceArmVerify() end
function SS.TraceVerifyTick() end

-- counters : SS.stats (this session) and ShikaSwapDB.counts (all sessions, readable in the saved variable file)
function SS.Inc(name)
    SS.stats[name] = (SS.stats[name] or 0) + 1
    local c = SS.db and SS.db.counts
    if c then c[name] = (c[name] or 0) + 1 end
end

-- Dbg: pieces are concatenated ONLY when debug/trace is on (no garbage on the hot path)
function SS.Dbg(a, b, c, d, e, f, g, h)
    local db = SS.db
    if not db or not (db.debug or db.trace) then return end
    local s = tostring(a)
    if b ~= nil then s = s .. tostring(b) end
    if c ~= nil then s = s .. tostring(c) end
    if d ~= nil then s = s .. tostring(d) end
    if e ~= nil then s = s .. tostring(e) end
    if f ~= nil then s = s .. tostring(f) end
    if g ~= nil then s = s .. tostring(g) end
    if h ~= nil then s = s .. tostring(h) end
    local n = SS.ringN + 1
    if n > SS.RING_MAX then n = 1 end
    SS.ringN = n
    SS.ring[n] = string_format("%.2f %s", GetTime(), s)
    if db.debug then SS.Print("|cFFAAAAAA" .. s .. "|r") end
end

-- ---------------------------------------------------------------- saved variables
local function CleanList(v)
    if type(v) == "string" then return { v } end
    if type(v) ~= "table" then return nil end
    local out = {}
    for i = 1, getn(v) do
        if type(v[i]) == "string" and v[i] ~= "" then tinsert(out, v[i]) end
    end
    if getn(out) == 0 then return nil end
    return out
end

function SS.InitDB()
    if type(ShikaSwapDB) ~= "table" then ShikaSwapDB = {} end
    local db = ShikaSwapDB
    SS.db = db
    if type(db.rules) ~= "table" then db.rules = {} end
    if type(db.off) ~= "table" then db.off = {} end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    for k, v in pairs(SS.DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    local m = db.combat
    if m ~= "auto" and m ~= "burst" and m ~= "wait" and m ~= "skip" then db.combat = "auto" end
    if type(db.queueTimeout) ~= "number" or db.queueTimeout < 0.5 or db.queueTimeout > 10 then db.queueTimeout = 3.0 end
    if db.lang ~= "fr" and db.lang ~= "en" then db.lang = "auto" end
    -- sanitize rules : { ["Spell"] = { "Relic A", "Relic B" } }
    local clean = {}
    for spell, v in pairs(db.rules) do
        local l = CleanList(v)
        if type(spell) == "string" and l then clean[spell] = l end
    end
    db.rules = clean
    for k, v in pairs(db.off) do
        if v ~= true then db.off[k] = nil end
    end
    SS.MigrateDB(db)
    SS.RebuildIndex()
    return db
end

-- indexes derived from the rules (lower-case spell lookup, candidate cache)
function SS.RebuildIndex()
    SS.lc = {}
    SS.cand = {}
    SS.actionCache = {}
    local n = 0
    local rules = SS.db and SS.db.rules or {}
    for spell in pairs(rules) do
        SS.lc[string_lower(spell)] = spell
        n = n + 1
    end
    SS.nRules = n
    SS.hasRules = n > 0
    -- equivalence groups from the catalogue (same effect, different value) : eq -> names sorted by value desc
    if not SS.eqGroups then
        local g = {}
        local relics = ShikaSwapData and ShikaSwapData.relics or {}
        for name, info in pairs(relics) do
            if info.eq then
                if not g[info.eq] then g[info.eq] = {} end
                tinsert(g[info.eq], name)
            end
        end
        for _, list in pairs(g) do
            table.sort(list, function(a, b) return relics[a].v > relics[b].v end)
        end
        SS.eqGroups = g
    end
end

-- ---------------------------------------------------------------- parsing / item helpers
-- "Holy Light(Rank 3)" -> "Holy Light", "Rank 3" ; "Holy Light" -> "Holy Light", nil
function SS.ParseSpell(spec)
    if type(spec) ~= "string" then return nil end
    local _, _, base, rnum = string_find(spec, "^(.-)%s*%(%s*[Rr][Aa][Nn][Kk]%s*(%d+)%s*%)%s*$")
    if base then return base, "Rank " .. rnum end
    local b = (string_gsub(spec, "^%s*(.-)%s*$", "%1"))
    return b, nil
end

function SS.ItemIdFromLink(link)
    if not link then return nil end
    local _, _, id = string_find(link, "item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

function SS.ItemNameFromLink(link)
    if not link then return nil end
    local _, _, n = string_find(link, "%[(.-)%]")
    return n
end

function SS.Relics()
    return (ShikaSwapData and ShikaSwapData.relics) or {}
end

-- case-insensitive canonical relic name from the catalogue ("libram of light" -> "Libram of Light")
function SS.CanonRelic(typed)
    if type(typed) ~= "string" then return nil end
    local t = (string_gsub(typed, "^%s*(.-)%s*$", "%1"))
    local relics = SS.Relics()
    if relics[t] then return t end
    local lt = string_lower(t)
    for name in pairs(relics) do
        if string_lower(name) == lt then return name end
    end
    return t
end

-- ---------------------------------------------------------------- spell book / cooldown
function SS.ScanBook()
    local book = {}
    local i = 1
    while i < 1500 do
        local name, rank = GetSpellName(i, "spell")
        if not name then break end
        local key = string_lower(name)
        local e = book[key]
        if not e then
            e = { ranks = {}, name = name }
            book[key] = e
        end
        e.max = i
        if rank and rank ~= "" then e.ranks[rank] = i end
        i = i + 1
    end
    SS.book = book
    return book
end

-- returns remaining (s), duration (s), known (bool)
function SS.SpellState(spell, rank, now)
    local book = SS.book or SS.ScanBook()
    local e = book[string_lower(spell)]
    if not e then return 0, 0, false end
    local idx = (rank and e.ranks[rank]) or e.max
    local start, dur, en = GetSpellCooldown(idx, "spell")
    if not start or en == 0 then return 0, 0, true end
    if start == 0 or not dur or dur == 0 then return 0, 0, true end
    local rem = start + dur - now
    if rem < 0 then rem = 0 end
    return rem, dur, true
end

-- ---------------------------------------------------------------- bags
function SS.ScanBags()
    local idx = {}
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local code = bag * 1000 + slot
                local id = SS.ItemIdFromLink(link)
                if id and not idx[id] then idx[id] = code end
                local nm = SS.ItemNameFromLink(link)
                if nm and not idx[nm] then idx[nm] = code end
            end
        end
    end
    SS.bagIdx = idx
    SS.bagDirty = false
    return idx
end

-- returns bag, slot of the relic in the bags (or nil)
function SS.FindRelic(name)
    if SS.bagDirty or not SS.bagIdx then SS.ScanBags() end
    local info = SS.Relics()[name]
    local code = (info and SS.bagIdx[info.id]) or SS.bagIdx[name]
    if not code then return nil end
    local bag = math.floor(code / 1000)
    return bag, code - bag * 1000
end

function SS.LinkIsRelic(link, name)
    if not link then return false end
    local info = SS.Relics()[name]
    if info then return SS.ItemIdFromLink(link) == info.id end
    return SS.ItemNameFromLink(link) == name
end

-- ---------------------------------------------------------------- state probes
function SS.InCombat()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return false
end

function SS.BlockingFrame()
    local list = SS.BLOCKERS
    for i = 1, getn(list) do
        local f = getglobal(list[i])
        if f and f.IsVisible and f:IsVisible() then return list[i] end
    end
    return nil
end

function SS.IsCasting(now)
    if SS.castUntil and now < SS.castUntil then return true end
    if SS.chanUntil and now < SS.chanUntil then return true end
    return false
end

-- Identifiant stable de la cible (SuperWoW guid ; repli nom). Sert au verrou execute.
-- Cible = boss : classification "worldboss" ou niveau ?? (crane, UnitLevel = -1).
function SS.TargetIsBoss()
    if not UnitExists("target") then return false end
    local cl = UnitClassification and UnitClassification("target")
    if cl == "worldboss" then return true end
    local lv = UnitLevel and UnitLevel("target")
    return lv == -1
end

function SS.TargetGuid()
    if UnitExists("target") then
        local _, guid = UnitExists("target")
        if guid and guid ~= "" then return guid end
        return "n:" .. tostring(UnitName("target"))
    end
    return nil
end

function SS.TargetHpPct()
    if not UnitExists("target") then return nil end
    if UnitCanAttack and not UnitCanAttack("player", "target") then return nil end
    local mx = UnitHealthMax("target")
    if not mx or mx <= 0 then return nil end
    return UnitHealth("target") / mx * 100
end

function SS.PendingResolved(p, eqId, eqName)
    if eqId and p.id and eqId == p.id then return true end
    if eqName and eqName == p.relic then return true end
    return false
end

-- snapshot of everything Plan needs (Plan itself touches no WoW API -> unit-testable with plain tables)
function SS.BuildSnapshot(spell, rank)
    local now = GetTime()
    local s = { now = now }
    s.combat = SS.InCombat()
    s.dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
    s.cursor = (CursorHasItem and CursorHasItem()) and true or false
    s.blocked = SS.BlockingFrame()
    s.casting = SS.IsCasting(now)
    local link = GetInventoryItemLink("player", SS.SLOT)
    s.eqId = SS.ItemIdFromLink(link)
    s.eqName = SS.ItemNameFromLink(link)
    local p = SS.pending
    if p then
        if (now - p.at) > SS.PENDING_WINDOW or SS.PendingResolved(p, s.eqId, s.eqName) then
            if not SS.PendingResolved(p, s.eqId, s.eqName) then
                SS.TL("UNCONFIRMED", "wanted=", p.relic, " equipped=", s.eqName, " after ", string_format("%.0f", (now - p.at) * 1000), "ms")
            end
            SS.pending = nil
            p = nil
        end
    end
    if p then
        s.pendRelic = p.relic
        s.pendAge = now - p.at
    end
    local rem, dur, known = SS.SpellState(spell, rank, now)
    s.rem = rem
    s.dur = dur
    s.known = known
    s.tgtHp = SS.TargetHpPct()
    s.tgtExists = UnitExists("target") and true or false
    s.tgtDead = (s.tgtExists and UnitIsDeadOrGhost and UnitIsDeadOrGhost("target")) and true or false
    s.tgtGuid = SS.TargetGuid()
    s.tgtBoss = SS.TargetIsBoss()
    s.execBoss = SS.db.execBoss ~= false
    s.find = SS.FindRelic
    return s
end

-- ---------------------------------------------------------------- decision
-- ordered candidate relics for a rule key (user list, then catalogue equivalents when fallbacks are on)
function SS.Candidates(key)
    local c = SS.cand[key]
    if c then return c end
    local list = SS.db.rules[key]
    if type(list) ~= "table" then return nil end
    local out = {}
    local seen = {}
    for i = 1, getn(list) do
        if not seen[list[i]] then
            seen[list[i]] = true
            tinsert(out, list[i])
        end
    end
    if SS.db.fallbacks then
        local relics = SS.Relics()
        for i = 1, getn(list) do
            local info = relics[list[i]]
            if info and info.eq and SS.eqGroups[info.eq] then
                local g = SS.eqGroups[info.eq]
                for j = 1, getn(g) do
                    local o = relics[g[j]]
                    if not seen[g[j]] and o.v < info.v then
                        seen[g[j]] = true
                        tinsert(out, g[j])
                    end
                end
            end
        end
    end
    SS.cand[key] = out
    return out
end

-- EXECUTE LOCK : quand un relic "tgt35hold" a ete equipe (cible sous 35 % PV), il RESTE equipe jusqu'a la
-- mort de la cible verrouillee. Pendant le verrou : plus AUCUN swap (Holy Shock garde le boost execute au lieu de
-- re-swapper son propre libram, Judgement profite du Final Judgement), et l'ouverture d'une autre cible saine ne
-- retire PAS le relic (retour au swap normal a la mort du boss verrouille).
SS.execLock = { guid = nil, name = nil, at = 0 }   -- verrou execute actif (guid de la cible sous 35 %)
-- Le relic equipe (ou en cours d'echange) est-il un relic d'execute (cond tgt35hold) ?
function SS.ExecRelicOn(snap)
    local relics = SS.Relics()
    if snap.pendRelic then
        local pi = relics[snap.pendRelic]
        if pi and pi.cond == "tgt35hold" then return true end
    end
    if snap.eqId then
        for _, info in pairs(relics) do
            if info.cond == "tgt35hold" and info.id == snap.eqId then return true end
        end
    end
    return false
end

-- Le verrou ne vaut que s'il tient VRAIMENT un relic d'execute : il est pose APRES l'echange (DoEquip / relic deja en place), jamais a
-- l'evaluation d'une condition (sinon un Plan refuse - Judgement en recharge, relic absent des sacs, sort hors GCD... - le posait sans
-- relic et bloquait tout echange jusqu'a la mort de la cible). Leve : cible morte / absente, ou relic d'execute plus equipe.
function SS.ExecLockActive(snap)
    local L = SS.execLock
    if not L.guid then return false end
    if snap and (snap.tgtExists == false or snap.tgtDead) then
        SS.TL("EXEC-UNLOCK", "target dead or gone: execute lock released (", string_format("%.1f", GetTime() - L.at), "s)")
        SS.execLock = { guid = nil, name = nil, at = 0 }
        return false
    end
    -- autre cible (vivante) : le verrou ne concerne plus que l'ancienne, sinon le relic restait equipe sur tout le reste du combat
    if snap and snap.tgtGuid and snap.tgtGuid ~= L.guid then
        SS.TL("EXEC-UNLOCK", "target changed: execute lock released")
        SS.execLock = { guid = nil, name = nil, at = 0 }
        return false
    end
    -- combat fini (plus de cible a achever) : verrou leve apres 3 s
    if snap and snap.combat == false and (GetTime() - L.at) > 3 then
        SS.TL("EXEC-UNLOCK", "combat ended: execute lock released")
        SS.execLock = { guid = nil, name = nil, at = 0 }
        return false
    end
    if snap and snap.now and not SS.ExecRelicOn(snap) then
        SS.TL("EXEC-UNLOCK", "execute relic no longer equipped: lock released")
        SS.execLock = { guid = nil, name = nil, at = 0 }
        return false
    end
    return true
end

-- Pose le verrou sur la cible courante (appele quand un relic d'execute VIENT d'etre equipe ou l'est deja, cible sous 35 %).
function SS.ExecEngage()
    if not UnitExists("target") then return end
    SS.execLock = { guid = SS.TargetGuid(), name = UnitName("target") or "?", at = GetTime() }
    SS.TL("EXEC-LOCK", "execute lock engaged on ", SS.execLock.name)
end

-- Une regle active mene-t-elle a un relic d'execute (cond tgt35hold) ? (mis en cache, invalide par RebuildIndex)
function SS.HasExecRule()
    if SS.execRule == nil then
        SS.execRule = false
        local relics = SS.Relics()
        for key, list in pairs(SS.db.rules) do
            if not SS.db.off[key] and type(list) == "table" then
                for i = 1, getn(list) do
                    local info = relics[list[i]]
                    if info and info.cond == "tgt35hold" then SS.execRule = true end
                end
            end
        end
    end
    return SS.execRule
end

function SS.CondOK(cond, snap)
    if cond == "tgt35" then return snap.tgtHp ~= nil and snap.tgtHp < 35 end
    if cond == "tgt35hold" then
        -- execute : sous 35 % PV, ou verrou deja pose (le relic reste equipe jusqu'a la mort de la cible) ; aucun effet de bord ici
        if SS.ExecLockActive(snap) then return true end
        if snap.execBoss and not snap.tgtBoss then return false end      -- option execboss : seulement les boss
        return snap.tgtHp ~= nil and snap.tgtHp < 35
    end
    return true
end

function SS.IsEquippedName(snap, name)
    local info = SS.Relics()[name]
    if info then
        if snap.eqId == info.id then return true end
    elseif snap.eqName == name then
        return true
    end
    return snap.pendRelic == name
end

function SS.EffectiveMode()
    local m = SS.db.combat
    if m == "auto" then
        if SS.db.learned == "wait" then return "wait" end
        return "burst"
    end
    return m
end

local function PASS(why)
    return { act = "pass", why = why }
end

-- Plan(key, snap) -> { act = "pass"|"swap"|"defer", relic, bag, slot, cast = "now"|"queue", why }
function SS.Plan(key, snap, modeOverride)
    local db = SS.db
    if not db.enabled then return PASS("disabled") end
    if db.off[key] then return PASS("rule switched off") end
    -- EXECUTE LOCK actif : le relic execute reste en place, AUCUN autre swap (le GCD de swap ne parasite plus la rotation).
    -- Ne s'applique que si une regle tgt35hold existe et est active : sinon le verrou n'a rien a tenir.
    if SS.ExecLockActive(snap) and SS.HasExecRule() then
        return PASS("execute lock: relic held until target dies")
    end
    local cands = SS.Candidates(key)
    if not cands then return PASS("no rule") end
    local want, bag, slot
    local condFail = false
    for i = 1, getn(cands) do
        local name = cands[i]
        local info = SS.Relics()[name]
        if info and info.cond and not SS.CondOK(info.cond, snap) then
            condFail = true
        elseif SS.IsEquippedName(snap, name) then
            return PASS("already equipped")
        else
            local b, s = snap.find(name)
            if b then
                want, bag, slot = name, b, s
                break
            end
        end
    end
    if not want then
        if condFail then return PASS("condition not met") end
        return { act = "pass", why = "no candidate in bags", missing = true }
    end
    if snap.dead then return PASS("dead") end
    if snap.cursor then return PASS("item on cursor") end
    if snap.blocked then return PASS("window open: " .. snap.blocked) end
    if snap.casting then return PASS("casting") end
    if snap.pendRelic then return PASS("swap in transit") end
    if not snap.known then return PASS("spell not in spellbook") end
    if snap.rem > SS.EPS and snap.dur > SS.GCD_MAX then return PASS("spell on cooldown") end
    local plan = { act = "swap", relic = want, bag = bag, slot = slot, cast = "now", why = "ok" }
    if not snap.combat then
        plan.why = "out of combat (swap is free)"
        return plan
    end
    local mode = modeOverride or SS.EffectiveMode()
    if mode == "skip" then return PASS("combat mode skip") end
    -- a combat swap locks the GCD category for 1.5 s ; a spell without GCD (Judgement) would pay that lock for nothing
    if not modeOverride and db.offGcd == "skip" and SS.IsOffGcd(key) then return PASS("off-GCD spell: no swap in combat (option offgcd)") end
    local g = snap.rem
    if mode == "burst" then
        if g > SS.EPS then
            plan.act = "defer"
            plan.why = "burst: wait for the global cooldown then swap+cast"
        else
            plan.why = "burst: swap+cast in the same frame"
        end
        return plan
    end
    -- wait : swap now (overlaps the running GCD), cast when ready
    plan.cast = "queue"
    plan.why = "wait: swap now, cast when ready"
    return plan
end

-- ---------------------------------------------------------------- execution
function SS.DoEquip(plan)
    if CursorHasItem and CursorHasItem() then
        SS.TL("EQUIP-REFUSED", "item on cursor, wanted=", plan.relic)
        return false
    end
    if GetContainerItemInfo then
        local _, _, locked = GetContainerItemInfo(plan.bag, plan.slot)
        if locked then
            SS.Dbg("equip skipped: bag slot locked")
            SS.TL("EQUIP-REFUSED", "bag slot locked, wanted=", plan.relic)
            return false
        end
    end
    local link = GetContainerItemLink(plan.bag, plan.slot)
    if not SS.LinkIsRelic(link, plan.relic) then
        SS.bagDirty = true
        SS.Dbg("equip skipped: bag slot no longer holds ", plan.relic)
        SS.TL("EQUIP-REFUSED", "bag slot no longer holds ", plan.relic)
        return false
    end
    local info = SS.Relics()[plan.relic]
    local before = SS.ItemNameFromLink(GetInventoryItemLink("player", SS.SLOT))
    SS.TL("EQUIP", "spell=", plan.spell, " want=", plan.relic, " before=", before, " bag=", plan.bag, "/", plan.slot, " combat=", SS.InCombat() and 1 or 0)
    UseContainerItem(plan.bag, plan.slot)
    SS.pending = { relic = plan.relic, id = info and info.id or nil, at = GetTime() }
    SS.lastSwap = SS.pending.at
    if info and info.cond == "tgt35hold" then SS.ExecEngage() end
    SS.bagDirty = true
    if SS.InCombat() then
        SS.Inc("swapsCombat")
        SS.lastSwapCombat = SS.pending.at   -- the combat swap cooldown (1.5 s) is counted from here by the floating indicator
    else
        SS.Inc("swapsFree")
    end
    SS.Dbg("EQUIP ", plan.relic, " from bag ", plan.bag, " slot ", plan.slot)
    return true
end

-- Run(key, rank, castFn, src): the one entry point used by every hook. castFn() performs the ORIGINAL cast.
-- FAIL-OPEN : whatever goes wrong inside the swap logic, the player's cast must still leave.
function SS.Run(key, rank, castFn, src, forced)
    local called = false
    local wrapped = function()
        called = true
        return castFn()
    end
    local ok, err = pcall(SS.RunInner, key, rank, wrapped, src, forced)
    if ok then return end
    SS.Inc("errors")
    SS.TL("ERROR", "spell=", key, " ", tostring(err))
    if not SS.lastError then SS.Print("|cFFFF6666internal error (cast not blocked): " .. tostring(err) .. "|r") end
    SS.lastError = tostring(err)
    if not called then return castFn() end
end

function SS.RunInner(key, rank, castFn, src, forced)
    local q = SS.queue
    if q and not forced then
        if q.spell == key then
            q.expire = GetTime() + SS.db.queueTimeout
            q.castFn = castFn   -- the most recent press wins (e.g. a heal macro aimed at another target)
            SS.Inc("pressSwallowed")
            return
        end
        -- a spell without GCD (Judgement) is cast on top of the GCD : it does not replace the queued GCD cast
        if not SS.IsOffGcd(key) then SS.QueueClear("superseded by " .. key) end
    end
    local snap = SS.BuildSnapshot(key, rank)
    local plan = SS.Plan(key, snap)
    plan.spell = key
    SS.Dbg("[", src, "] ", key, " -> ", plan.act, " : ", plan.why)
    SS.TracePlan(key, snap, plan, src)
    if plan.act == "pass" and plan.why == "already equipped" and not SS.execLock.guid and snap.tgtHp ~= nil and snap.tgtHp < 35 and (snap.tgtBoss or not snap.execBoss) and SS.ExecRelicOn(snap) then
        SS.ExecEngage()
    end
    if plan.act == "pass" and plan.why ~= "already equipped" and plan.why ~= "rule switched off" and plan.why ~= "disabled" then
        -- why a swap did not happen (reason without the variable part after ':'), kept in the saved variables
        local _, _, reason = string_find(plan.why, "^([^:]+)")
        SS.Inc("pass: " .. (reason or plan.why))
    end
    if plan.act ~= "pass" and SS.queue and not forced and SS.queue.spell ~= key then
        SS.QueueClear("superseded by " .. key)   -- an off-GCD spell that needs its own swap does replace the queue
    end
    if plan.act == "pass" then
        if plan.missing and SS.AlertMissing then pcall(SS.AlertMissing, key) end
        return castFn()
    end
    if plan.act == "defer" then
        SS.Enqueue({ kind = "swapcast", spell = key, rank = rank, castFn = castFn, src = src })
        SS.TL("DEFER", "spell=", key, " until the GCD ends (", string_format("%.2f", snap.rem or 0), "s left)")
        return
    end
    if not SS.DoEquip(plan) then return castFn() end
    if plan.cast == "now" then
        if snap.combat then SS.NoteBurst(key, castFn) end
        local t0 = GetTime()
        local r1, r2 = castFn()
        SS.TL("CAST", "spell=", key, " sent in the same frame as the swap (", string_format("%.0f", (GetTime() - t0) * 1000), "ms in the call)")
        SS.TraceArmVerify(key, plan.relic, GetTime())
        return r1, r2
    end
    -- the combat-swap GCD only reaches the client one round trip after the swap : do not trust "ready" before that
    SS.Enqueue({ kind = "cast", spell = key, rank = rank, castFn = castFn, src = src, relic = plan.relic,
        swapAt = GetTime(), grace = 0.25 + SS.Latency() })
end

-- ---------------------------------------------------------------- queue (throttled OnUpdate, only while non-empty)
-- round-trip time in seconds (GetNetStats 3rd value is in ms) ; 0.15 s when unknown
function SS.Latency()
    if GetNetStats then
        local _, _, ms = GetNetStats()
        if type(ms) == "number" and ms >= 0 then return ms / 1000 end
    end
    return 0.15
end

function SS.Enqueue(q)
    q.at = GetTime()
    q.expire = q.at + SS.db.queueTimeout
    SS.queue = q
    SS.Inc("queued")
    if SS.frame then SS.frame:Show() end
end

function SS.QueueClear(why)
    if SS.queue then
        SS.Dbg("queue cleared: ", why)
        SS.TL("QCLEAR", "spell=", SS.queue.spell, " kind=", SS.queue.kind, " waited ", string_format("%.0f", (GetTime() - (SS.queue.at or GetTime())) * 1000), "ms : ", why)
    end
    SS.queue = nil
    if SS.frame and not SS.openerAt and not SS.verify then SS.frame:Hide() end
end

-- the player moved on to another spell : a queued cast must not fire later behind their back
function SS.CancelQueueFor(key, name)
    local q = SS.queue
    if not q or q.spell == key then return end
    if SS.IsOffGcd(key) or SS.IsOffGcd(name) then return end   -- Judgement is cast on top of the GCD : it does not cancel the queued cast
    SS.QueueClear("another spell was pressed (" .. tostring(key or name) .. ")")
end

function SS.QueueTick()
    local q = SS.queue
    if not q then return end
    local now = GetTime()
    if now > q.expire then
        SS.Inc("queueTimeouts")
        SS.QueueClear("timeout for " .. q.spell)
        return
    end
    local rem = SS.SpellState(q.spell, q.rank, now)
    if rem > SS.EPS then
        q.seen = true
        return
    end
    if q.swapAt and not q.seen and (now - q.swapAt) < q.grace then return end
    local f = q.castFn
    local kind = q.kind
    SS.queue = nil
    if not SS.openerAt and SS.frame and not SS.verify then SS.frame:Hide() end
    if kind == "swapcast" then
        SS.TL("DEFER-FIRE", "spell=", q.spell, " waited ", string_format("%.0f", (now - q.at) * 1000), "ms for the GCD")
        SS.Run(q.spell, q.rank, f, q.src, true)
    else
        SS.Inc("queueCasts")
        SS.TL("QCAST", "spell=", q.spell, " kind=", kind, " ", q.swapAt and (string_format("%.0f", (now - q.swapAt) * 1000) .. "ms after the swap") or "retry")
        f()
        if q.relic then SS.TraceArmVerify(q.spell, q.relic, GetTime()) end
    end
end

-- ---------------------------------------------------------------- burst self-measurement
local function NotReadyText(msg)
    if type(msg) ~= "string" then return false end
    local l = string_lower(msg)
    local g = { ERR_SPELL_COOLDOWN, SPELL_FAILED_NOT_READY, ERR_ABILITY_COOLDOWN }
    for i = 1, 3 do
        if type(g[i]) == "string" and string_lower(g[i]) == l then return true end
    end
    if string_find(l, "not ready", 1, true) or string_find(l, "cooldown", 1, true) or string_find(l, "recovered", 1, true) then
        return true
    end
    return false
end
SS.NotReadyText = NotReadyText

function SS.NoteBurst(key, castFn)
    local p = SS.probe
    if p and not p.failed then
        SS.Inc("burstOk")
        SS.consecFail = 0
    end
    SS.Inc("burstSent")
    SS.probe = { at = GetTime(), spell = key, castFn = castFn, failed = false, attempts = SS.attempts }
end

-- called from UI_ERROR_MESSAGE
function SS.OnErrorMessage(msg)
    local now = GetTime()
    local p = SS.probe
    -- only blame the burst when it was the LAST cast attempt of the player (other key presses give the same message)
    if p and not p.failed and (now - p.at) < 0.8 and p.attempts == SS.attempts and NotReadyText(msg) then
        p.failed = true
        SS.Inc("burstFail")
        SS.consecFail = (SS.consecFail or 0) + 1
        SS.Dbg("burst cast refused (", msg, "), consecutive=", SS.consecFail)
        SS.TL("BURST-REFUSED", "spell=", p.spell, " msg=", msg, " ", string_format("%.0f", (now - p.at) * 1000), "ms after the cast, consecutive=", SS.consecFail)
        if SS.consecFail >= 2 and SS.db.combat == "auto" and SS.db.learned ~= "wait" then
            SS.db.learned = "wait"
            SS.Print(SS.T("learned_wait"))
        end
        -- do not lose the key press: retry once when the spell becomes ready
        if p.castFn and not SS.queue then
            SS.Enqueue({ kind = "cast", spell = p.spell, castFn = p.castFn, src = "retry" })
        end
        return
    end
    if SS.lastSwap and (now - SS.lastSwap) < 1.0 and msg then
        SS.Inc("swapErrors")
        SS.Dbg("error right after a swap: ", msg)
        SS.TL("UIERR", "msg=", msg, " ", string_format("%.0f", (now - SS.lastSwap) * 1000), "ms after a swap")
    end
end

-- ---------------------------------------------------------------- explicit pre-swap (macro "next", opener)
-- Equip the relic that spell needs, now. Out of combat it is free ; in combat the user accepts the swap GCD.
function SS.PreSwap(spell)
    local key = SS.lc[string_lower(spell or "")]
    if not key then return false, "no rule for " .. tostring(spell) end
    local snap = SS.BuildSnapshot(key, nil)
    snap.rem = 0 -- a pre-swap does not care about the spell's own cooldown state
    snap.dur = 0
    snap.known = true
    -- explicit request : swap immediately whatever the combat mode (no deferral)
    local plan = SS.Plan(key, snap, "burst")
    if plan.act == "defer" then plan.act = "swap" end
    if plan.act ~= "swap" then return false, plan.why end
    if not SS.DoEquip(plan) then return false, "equip refused" end
    return true, plan.relic
end

-- ---------------------------------------------------------------- rules editing
function SS.SetRule(spell, list)
    SS.execRule = nil   -- cache a recalculer
    local l = CleanList(list)
    if not l then return false end
    SS.db.rules[spell] = l
    SS.db.off[spell] = nil
    SS.RebuildIndex()
    return true
end

function SS.ClearRule(spell)
    SS.execRule = nil
    local key = SS.lc[string_lower(spell or "")]
    if not key then return false end
    SS.db.rules[key] = nil
    SS.db.off[key] = nil
    SS.RebuildIndex()
    return true
end

-- relic names (catalogue) that improve a spell, for the player's class token ("PALADIN" ...)
function SS.RelicsForSpell(spell, class)
    local out = {}
    local ls = string_lower(spell)
    for name, info in pairs(SS.Relics()) do
        if not class or info.class == class then
            for i = 1, getn(info.spells) do
                if string_lower(info.spells[i]) == ls then tinsert(out, name) break end
            end
        end
    end
    table.sort(out)
    return out
end

-- replace the whole rule set (sanitised copy). Used by profiles, spec profiles, import, undo, so they all behave the same.
function SS.ApplyRules(rules, off)
    local r, o = {}, {}
    if type(rules) == "table" then
        for spell, v in pairs(rules) do
            local l = CleanList(v)
            if type(spell) == "string" and l then r[spell] = SS.CopyTable(l) end
        end
    end
    if type(off) == "table" then
        for spell, v in pairs(off) do
            if v == true and r[spell] then o[spell] = true end
        end
    end
    SS.db.rules = r
    SS.db.off = o
    SS.RebuildIndex()
end

-- keep one level of undo before any bulk change (profile load, spec switch, import, reset)
function SS.Backup()
    SS.db.backup = { rules = SS.CopyTable(SS.db.rules), off = SS.CopyTable(SS.db.off) }
end

function SS.CopyTable(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = SS.CopyTable(v) end
    return o
end
