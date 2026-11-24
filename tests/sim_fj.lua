-- cost of swapping for an OFF-GCD spell (Judgement -> Libram of Final Judgement, target under 35 %) in a Retribution-like cycle
local SS = ShikaSwap
local function run(skipOffGcd, h2)
    W.reset(); ShikaSwapDB = nil; SS.stats = {}; SS.queue = nil; SS.pending = nil; SS.bagDirty = true; SS.book = nil; SS.lastSwapCombat = nil; SS.InitDB()
    W.nampower = true; W.npWindow = 0.5; W.localGcdOnEquip = h2
    W.setBook({ { name = "Holy Shock", rank = "Rank 4" }, { name = "Crusader Strike", rank = "Rank 5" }, { name = "Judgement", rank = "" }, { name = "Seal of Righteousness", rank = "Rank 8" } })
    W.noGcd = { Judgement = true }; W.realCd = { ["Holy Shock"] = 3.0, ["Crusader Strike"] = 6.0, Judgement = 10.0 }
    SS.SetRule("Judgement", { "Libram of Final Judgement" }); SS.SetRule("Holy Shock", { "Libram of the Radiant Dawn" })
    if SS.db.offGcd ~= nil or skipOffGcd then SS.db.offGcd = skipOffGcd and "skip" or "swap" end
    W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
    W.tgt = { hp = 20, max = 100 }; W.combat = true
    local function idx(n) for i = 1, table.getn(W.book) do if W.book[i].name == n then return i end end end
    local function ready(n, w) local s, d = GetSpellCooldown(idx(n), "spell"); if not s or s == 0 then return true end return s + d - W.now <= w end
    local function real(n) local c = W.spellCd[n]; return not (c and c.start + c.dur > W.now) end
    while W.now < 1000 + 120 do
        W.advance(0.1)
        if real("Judgement") then CastSpellByName("Judgement")
        elseif real("Holy Shock") and ready("Holy Shock", 0.3) then CastSpellByName("Holy Shock")
        elseif real("Crusader Strike") and ready("Crusader Strike", 0.3) then CastSpellByName("Crusader Strike") end
    end
    W.advance(1)
    local g = 0; local fj = 0
    for _, c in ipairs(W.casts) do if c.name ~= "Judgement" then g = g + 1 else if c.relic == ITEM.FinalJ then fj = fj + 1 end end end
    return g, fj, (SS.stats.swapsCombat or 0)
end
for h = 0, 1 do
    local a, fa, sa = run(false, h == 1)
    print(string.format("hypothesis H%d : swap for Judgement : %d GCD casts in 120 s, %d Judgements with Final Judgement, %d swaps", h + 1, a, fa, sa))
    local b, fb, sb = run(true, h == 1)
    print(string.format("hypothesis H%d : skip (off-GCD)     : %d GCD casts in 120 s, %d Judgements with Final Judgement, %d swaps", h + 1, b, fb, sb))
end
