-- sim_necro.lua : the Necroladin cycle (Holy Shock <-> Seal of the Crusader, Judgement off-GCD, Seal of Righteousness, Crusader Strike)
-- driven like ShikiwaRotation does (one key, CastSpellByName every 100 ms, press allowed when the GCD ends within 0.3 s),
-- with a Nampower-like spell queue in the mock client. Counts how often a spell leaves with the wrong relic.
--   node harness_shikaswap.js sim_necro.lua      (SIM_MODE=auto|burst|wait|skip, SIM_NP=1|0, SIM_SECONDS=120)
local SS = ShikaSwap
local function fresh()
    W.reset(); ShikaSwapDB = nil
    SS.stats = {}; SS.ring = {}; SS.ringN = 0; SS.queue = nil; SS.pending = nil; SS.probe = nil; SS.consecFail = 0
    SS.castUntil = nil; SS.chanUntil = nil; SS.bagDirty = true; SS.book = nil; SS.conflict = false; SS.openerAt = nil
    SS.lastSwap = nil; SS.bagIdx = nil; SS.lastSwapCombat = nil; SS.alerted = {}
    SS.InitDB(); SS.frame:Hide()
end
local function run(opts)
    fresh()
    W.nampower = opts.np; W.npWindow = 0.5
    W.setBook({ { name = "Holy Shock", rank = "Rank 4" }, { name = "Seal of the Crusader", rank = "Rank 6" }, { name = "Seal of Righteousness", rank = "Rank 8" },
        { name = "Crusader Strike", rank = "Rank 5" }, { name = "Judgement", rank = "" }, { name = "Consecration", rank = "Rank 1" } })
    W.noGcd = { Judgement = true }
    W.realCd = { ["Holy Shock"] = 3.0, ["Crusader Strike"] = 6.0, Judgement = 10.0 }
    SS.db.combat = opts.mode or "auto"
    local p = SS.NecroPreset(); SS.ApplyRules(p.rules, p.off)
    W.putBag(0, 1, ITEM.RadiantDawn); W.putBag(0, 2, ITEM.Fervor); W.putBag(0, 3, ITEM.Radiance)
    W.equip(ITEM.RadiantDawn)
    W.combat = true; W.fire("PLAYER_REGEN_DISABLED")
    local last = { sotc = -99, seal = "SoR" }
    local function idx(name) for i = 1, table.getn(W.book) do if W.book[i].name == name then return i end end end
    local function ready(name, window)
        local start, dur = GetSpellCooldown(idx(name), "spell")
        if not start or start == 0 then return true end
        return (start + dur - W.now) <= window
    end
    local function realReady(name) local c = W.spellCd[name]; return not (c and c.start + c.dur > W.now) end
    local n = 0
    while W.now < 1000 + (opts.seconds or 120) do
        W.advance(0.1)
        local t = W.now
        local seal = last.seal
        -- bookkeeping from what the client really cast
        for i = (last.n or 0) + 1, table.getn(W.casts) do
            local c = W.casts[i]
            if c.name == "Seal of the Crusader" then last.seal = "SotC"; last.sotc = c.at
            elseif c.name == "Seal of Righteousness" then last.seal = "SoR"
            elseif c.name == "Judgement" and last.seal == "SotC" then last.seal = "none" end
        end
        last.n = table.getn(W.casts)
        seal = last.seal
        if seal == "SoR" and (t - last.sotc) >= 12 and ready("Seal of the Crusader", 0.3) then
            CastSpellByName("Seal of the Crusader")
        elseif seal == "SotC" and realReady("Judgement") then
            CastSpellByName("Judgement")
        elseif seal == "none" and ready("Seal of Righteousness", 0.3) then
            CastSpellByName("Seal of Righteousness")
        elseif realReady("Holy Shock") and ready("Holy Shock", 0.3) then
            CastSpellByName("Holy Shock")
        elseif realReady("Crusader Strike") and ready("Crusader Strike", 0.3) then
            CastSpellByName("Crusader Strike")
        end
    end
    W.advance(1)
    local res = { hsOK = 0, hsBad = 0, sotcOK = 0, sotcBad = 0, hs = 0, sotc = 0, swaps = (SS.stats.swapsCombat or 0) + (SS.stats.swapsFree or 0) }
    local want = { ["Holy Shock"] = W.sinv, }
    for _, c in ipairs(W.casts) do
        if c.name == "Holy Shock" then res.hs = res.hs + 1; if c.relic == ITEM.RadiantDawn then res.hsOK = res.hsOK + 1 else res.hsBad = res.hsBad + 1 end end
        if c.name == "Seal of the Crusader" then res.sotc = res.sotc + 1; if c.relic == ITEM.Fervor then res.sotcOK = res.sotcOK + 1 else res.sotcBad = res.sotcBad + 1 end end
    end
    res.casts = table.getn(W.casts)
    res.queueCancel = W.logCount("queue cleared")
    res.refused = W.logCount("REFUSED")
    res.stats = SS.stats
    return res
end
function SIM(opts) return run(opts) end

if SIM_AUTO ~= false then
    local modes = { "auto", "burst", "wait", "skip" }
    for np = 0, 1 do
        for i = 1, 4 do
            local r = run({ mode = modes[i], np = (np == 1), seconds = 150 })
            print(string.format("np=%d mode=%-5s casts=%3d HS %d/%d right libram, SotC %d/%d, swaps=%d, refused=%d, swallowed=%s timeouts=%s queued=%s burstFail=%s",
                np, modes[i], r.casts, r.hsOK, r.hs, r.sotcOK, r.sotc, r.swaps, r.refused, tostring(r.stats.pressSwallowed), tostring(r.stats.queueTimeouts), tostring(r.stats.queued), tostring(r.stats.burstFail)))
        end
    end
end
