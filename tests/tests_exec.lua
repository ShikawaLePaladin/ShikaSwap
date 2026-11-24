-- tests_exec.lua : Libram of Final Judgement = relic d'execute (cond tgt35hold) + verrou jusqu'a la mort de la cible.
--   node tests/harness_shikaswap.js tests/tests_exec.lua
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
    SS.stats = {}; SS.ring = {}; SS.ringN = 0; SS.queue = nil; SS.pending = nil; SS.probe = nil; SS.consecFail = 0; SS.verify = nil
    SS.castUntil = nil; SS.chanUntil = nil; SS.bagDirty = true; SS.book = nil; SS.conflict = false; SS.openerAt = nil
    SS.lastSwap = nil; SS.bagIdx = nil; SS.lastSwapCombat = nil; SS.alerted = {}; SS.sink = nil; SS.specPending = nil; SS.tlKey = nil
    SS.execLock = { guid = nil, name = nil, at = 0 }; SS.execRule = nil
    UnitClass = function() return "Paladin", "PALADIN" end
    SS.InitDB()
    SS.frame:Hide()
    W.setBook({ { name = "Holy Shock", rank = "Rank 4" }, { name = "Seal of the Crusader", rank = "Rank 6" }, { name = "Seal of Righteousness", rank = "Rank 8" },
        { name = "Crusader Strike", rank = "Rank 5" }, { name = "Judgement", rank = "" }, { name = "Consecration", rank = "Rank 1" } })
    W.noGcd = { Judgement = true }
    SS.SetRule("Judgement", { "Libram of Final Judgement" })
    SS.SetRule("Holy Shock", { "Libram of the Radiant Dawn" })
    SS.db.off["Judgement"] = nil; SS.db.off["Holy Shock"] = nil
    SS.db.combat = "burst"
    W.combat = true
end
local function press(s) CastSpellByName(s) end
local function lastRelicOf(spell)
    local r
    for _, c in ipairs(W.casts) do if c.name == spell then r = c.relic end end
    return r
end

section("normal : sous 35 %, Judgement pret -> Final Judgement equipe et verrou pose")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "Final Judgement equipe")
ok(SS.execLock.guid ~= nil, "verrou pose apres l'echange")
eq(lastRelicOf("Judgement"), ITEM.FinalJ, "Judgement lance avec Final Judgement")

section("verrou : aucun autre echange tant que la cible vit (Holy Shock garde le relic)")
W.advance(2)
press("Holy Shock"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "Holy Shock ne retire pas Final Judgement")

section("cible morte : verrou leve, les echanges reprennent")
W.tgt = nil
W.advance(2)
press("Holy Shock"); W.advance(1)
eq(W.sinv[18], ITEM.RadiantDawn, "apres la mort : Holy Shock re-swappe Radiant Dawn")
ok(SS.execLock.guid == nil, "verrou leve")

section("BUG : Judgement en recharge a la 1re pression -> le verrou ne doit PAS etre pose sans relic")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
W.realCd = { Judgement = 8.0 }
W.spellCd["Judgement"] = { start = W.now, dur = 8.0 }
press("Judgement"); W.advance(0.3)
eq(W.sinv[18], ITEM.RadiantDawn, "recharge en cours : pas d'echange")
ok(SS.execLock.guid == nil, "pas de verrou sans relic equipe")
W.advance(9)
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "recharge finie : Final Judgement equipe")
ok(SS.execLock.guid ~= nil, "verrou pose apres l'echange")

section("BUG : relic absent des sacs -> pas de verrou, les autres echanges continuent")
fresh()
W.putBag(0, 1, ITEM.RadiantDawn); W.equip(ITEM.Fervor)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
ok(SS.execLock.guid == nil, "relic absent : pas de verrou")
press("Holy Shock"); W.advance(0.5)
eq(W.sinv[18], ITEM.RadiantDawn, "Holy Shock continue de swapper")

section("BUG : option offgcd=skip -> pas de verrou fantome")
fresh()
SS.db.offGcd = "skip"
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
ok(SS.execLock.guid == nil, "offgcd skip : pas de verrou sans echange")
press("Holy Shock"); W.advance(0.5)
eq(W.sinv[18], ITEM.RadiantDawn, "offgcd skip : Holy Shock reste libre")

section("relic retire a la main pendant le verrou : plus de verrou")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "Final Judgement equipe")
W.equip(ITEM.RadiantDawn); W.putBag(0, 1, ITEM.FinalJ)
SS.bagDirty = true
W.advance(3)
press("Holy Shock"); W.advance(0.5)
press("Judgement"); W.advance(8)
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "re-equipe Final Judgement (pas bloque par un verrou perime)")

section("relic deja equipe avant le combat, cible sous 35 % -> verrou")
fresh()
W.putBag(0, 1, ITEM.RadiantDawn); W.equip(ITEM.FinalJ)
W.tgt = { hp = 25, max = 100 }
press("Judgement"); W.advance(0.5)
ok(SS.execLock.guid ~= nil, "verrou pose sur relic deja equipe")
press("Holy Shock"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "Holy Shock ne retire pas le relic")

section("cible saine : pas d'echange ni de verrou")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 80, max = 100 }
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.RadiantDawn, "cible a 80 % : pas d'echange")
ok(SS.execLock.guid == nil, "pas de verrou")

section("autre cible vivante : verrou leve, les echanges reprennent")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
ok(SS.execLock.guid ~= nil, "verrou pose")
W.tgt = { hp = 90, max = 100, name = "Autre", guid = "0xOTHER" }
W.advance(2)
press("Holy Shock"); W.advance(1)
eq(W.sinv[18], ITEM.RadiantDawn, "autre cible : Holy Shock re-swappe Radiant Dawn")
ok(SS.execLock.guid == nil, "verrou leve (cible changee)")

section("combat fini : verrou leve")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
ok(SS.execLock.guid ~= nil, "verrou pose")
W.combat = false
W.advance(5)
press("Holy Shock"); W.advance(1)
eq(W.sinv[18], ITEM.RadiantDawn, "hors combat : le relic normal revient")
ok(SS.execLock.guid == nil, "verrou leve (combat fini)")

section("cible normale (pas un boss) : pas d'echange ni de verrou (option execboss, par defaut)")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100, boss = false }
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.RadiantDawn, "mob normal a 20 % : Final Judgement non equipe")
ok(SS.execLock.guid == nil, "pas de verrou sur un mob")

section("option execboss=off : les mobs normaux sous 35 % comptent aussi")
fresh()
SS.db.execBoss = false
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100, boss = false }
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "execboss off : Final Judgement equipe sur un mob")

section("boss sous 35 % : echange (comportement d'origine)")
fresh()
W.putBag(0, 1, ITEM.FinalJ); W.putBag(0, 2, ITEM.RadiantDawn); W.equip(ITEM.RadiantDawn)
W.tgt = { hp = 20, max = 100 }
press("Judgement"); W.advance(0.5)
eq(W.sinv[18], ITEM.FinalJ, "boss : Final Judgement equipe")

print("RESULT: " .. PASSES .. " passed, " .. FAILS .. " failed")
if FAILS > 0 then error("TESTS FAILED: " .. FAILS) end
