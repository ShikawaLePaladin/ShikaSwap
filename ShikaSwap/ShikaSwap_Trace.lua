-- ShikaSwap_Trace.lua : persistent diagnostic trace of every swap decision (ring of 100 lines in ShikaSwapDB.trace_log).
-- The saved variable file (WTF\Account\<account>\SavedVariables\ShikaSwap.lua) is written by the client at /reload or logout,
-- so the log can be read there afterwards without any help from the player.
--   * ON by default for one week after the first start of this version (db.traceUntil), then silent ; /ssw trace on = until /ssw trace off.
--   * one line per event : time of day, GetTime(), tag, details. Identical consecutive lines within 2 s are merged ("(xN)").
-- Lua 5.0 : no '#', no string.match, no '...'.

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
local string_format = string.format
local getn = table.getn
local tinsert = table.insert

SS.TRACE_MAX = 100
SS.TRACE_WEEK = 7 * 24 * 3600

-- plans that happen all the time and say nothing (the relic is already right / the rule is off) are not written
local QUIET = { ["already equipped"] = true, ["rule switched off"] = true, ["disabled"] = true }

local EN = SS.M.en
local FR = SS.M.fr
EN.tr_on = "Persistent trace: ON (until /ssw trace off). %s lines stored."
FR.tr_on = "Trace persistante : ACTIVE (jusqu'à /ssw trace off). %s lignes enregistrées."
EN.tr_week = "Persistent trace: ON for one week (until %s). %s lines stored."
FR.tr_week = "Trace persistante : ACTIVE pendant une semaine (jusqu'au %s). %s lignes enregistrées."
EN.tr_off = "Persistent trace: OFF. %s lines stored (read them with /ssw tracelog)."
FR.tr_off = "Trace persistante : COUPÉE. %s lignes enregistrées (à relire avec /ssw tracelog)."
EN.tr_cleared = "Persistent trace cleared."
FR.tr_cleared = "Trace persistante effacée."
EN.tr_empty = "The persistent trace is empty."
FR.tr_empty = "La trace persistante est vide."
EN.tr_flush = "The file ShikaSwap.lua in SavedVariables is written by the game at /reload or logout."
FR.tr_flush = "Le fichier ShikaSwap.lua des SavedVariables est écrit par le jeu au /reload ou à la déconnexion."

function SS.TraceActive()
    local db = SS.db
    if not db then return false end
    if db.trace then return true end
    local u = db.traceUntil
    if type(u) == "number" and time and time() < u then return true end
    return false
end

local function Stamp()
    local d = "--:--:--"
    if date then
        local ok, v = pcall(date, "%H:%M:%S")
        if ok and type(v) == "string" then d = v end
    end
    return d .. " g=" .. string_format("%.3f", GetTime())
end

-- store one line in the ring
function SS.TraceRaw(line)
    local db = SS.db
    if type(db.trace_log) ~= "table" then db.trace_log = {} end
    local n = (tonumber(db.trace_n) or 0) + 1
    if n > SS.TRACE_MAX then n = 1 end
    db.trace_n = n
    db.trace_log[n] = line
end

-- TL(tag, a, b, ...) : up to 16 pieces, concatenated. Never raises (a diagnostic must not be able to hurt a cast).
function SS.TL(tag, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)
    if not SS.TraceActive() then return end
    local ok, err = pcall(SS.TLInner, tag, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)
    if not ok then SS.traceError = tostring(err) end
end

function SS.TLInner(tag, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)
    local parts = { a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p }
    local s = ""
    for x = 1, 16 do
        if parts[x] ~= nil then s = s .. tostring(parts[x]) end
    end
    if string.len(s) > 220 then s = string.sub(s, 1, 220) end
    local now = GetTime()
    local key = tag .. " " .. s
    if SS.tlKey == key and SS.tlAt and (now - SS.tlAt) < 2 and SS.db.trace_log and SS.db.trace_log[SS.db.trace_n or 0] then
        SS.tlRep = (SS.tlRep or 1) + 1
        SS.db.trace_log[SS.db.trace_n] = SS.tlBase .. " (x" .. SS.tlRep .. ")"
        SS.tlAt = now
        return
    end
    local line = Stamp() .. " " .. tag .. " " .. s
    SS.TraceRaw(line)
    SS.tlKey, SS.tlAt, SS.tlRep, SS.tlBase = key, now, 1, line
end

-- the stored lines, oldest first
function SS.TraceLines()
    local out = {}
    local log = SS.db and SS.db.trace_log
    if type(log) ~= "table" then return out end
    local n = tonumber(SS.db.trace_n) or 0
    local full = log[SS.TRACE_MAX] ~= nil
    local first, last
    if full then first = n + 1 last = n + SS.TRACE_MAX else first = 1 last = n end
    for i = first, last do
        local idx = i
        if idx > SS.TRACE_MAX then idx = idx - SS.TRACE_MAX end
        if log[idx] then tinsert(out, log[idx]) end
    end
    return out
end

function SS.TraceClear()
    SS.db.trace_log = {}
    SS.db.trace_n = 0
    SS.tlKey = nil
end

-- ---------------------------------------------------------------- event helpers called from the swap code
local function B(v) return v and 1 or 0 end

-- one line per decision that matters (swap / defer / pass for a reason other than "all is well")
function SS.TracePlan(key, snap, plan, src)
    if not SS.TraceActive() then return end
    if plan.act == "pass" and QUIET[plan.why] then return end
    SS.TL(plan.act == "pass" and "PASS" or "PLAN", "spell=", key, " src=", src, " act=", plan.act, " why=", plan.why)
    -- context on the same line would be too long : second line only for decisions that act
    if plan.act ~= "pass" then
        SS.TL("  ctx", "want=", plan.relic, " eq=", snap.eqName, " combat=", B(snap.combat), " gcdRem=", string_format("%.2f", snap.rem or 0), " mode=", SS.EffectiveMode())
    end
end

-- verification a short time after a swap+cast : is the wanted relic really equipped now ?
function SS.TraceArmVerify(spell, relic, castAt)
    if not SS.TraceActive() then return end
    SS.verify = { at = GetTime() + 0.7, spell = spell, relic = relic, castAt = castAt }
    if SS.frame then SS.frame:Show() end
end

function SS.TraceVerifyTick(now)
    local v = SS.verify
    if not v or now < v.at then return end
    SS.verify = nil
    local name = SS.ItemNameFromLink(GetInventoryItemLink("player", SS.SLOT))
    local ok = (name == v.relic)
    SS.TL(ok and "VERIFY-OK" or "VERIFY-BAD", "spell=", v.spell, " wanted=", v.relic, " equipped=", name, " ", string_format("%.0f", (now - v.castAt) * 1000), "ms after the cast")
end

-- ---------------------------------------------------------------- commands : /ssw trace ..., /ssw tracelog [n]
local C = SS.cmds

local function Trim(x)
    return (string.gsub(x or "", "^%s*(.-)%s*$", "%1"))
end

-- /ssw trace            : status of the persistent trace
-- /ssw trace on|off     : on = until switched off (also records the in-memory debug ring) ; off = silent
-- /ssw trace week       : re-arm one week ; /ssw trace clear : empty the stored lines
function C.trace(rest)
    local v = string.lower(Trim(rest))
    local db = SS.db
    local n = getn(SS.TraceLines())
    if v == "on" or v == "1" or v == "true" then
        db.trace = true
        SS.Print(SS.T("tr_on", n))
    elseif v == "off" or v == "0" or v == "false" then
        db.trace = false
        db.traceUntil = 0
        SS.Print(SS.T("tr_off", n))
    elseif v == "week" then
        db.trace = false
        db.traceUntil = (time and time() or 0) + SS.TRACE_WEEK
        SS.Print(SS.T("tr_week", date and date("%Y-%m-%d", db.traceUntil) or "?", n))
    elseif v == "clear" then
        SS.TraceClear()
        SS.Print(SS.T("tr_cleared"))
    elseif db.trace then
        SS.Print(SS.T("tr_on", n))
    elseif SS.TraceActive() then
        SS.Print(SS.T("tr_week", date and date("%Y-%m-%d", db.traceUntil) or "?", n))
    else
        SS.Print(SS.T("tr_off", n))
    end
end

function C.tracelog(rest)
    local n = tonumber(rest) or 25
    local lines = SS.TraceLines()
    if getn(lines) == 0 then SS.Print(SS.T("tr_empty")) return end
    local first = getn(lines) - n + 1
    if first < 1 then first = 1 end
    for i = first, getn(lines) do SS.Print("|cFFAAAAAA" .. lines[i] .. "|r") end
    SS.Print(SS.T("tr_flush"))
end
