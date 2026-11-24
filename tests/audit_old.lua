-- Evidence run : the OLD LibramSwap_fixed.lua inside the same 1.12 world mock (no changes to the old files).
W.reset()
W.putBag(0, 1, ITEM.Radiance); W.equip(ITEM.Light)
print("--- A. saved variables are loaded by the client AFTER the addon code ran")
-- (the client assigns the saved table after the files executed)
LibramSwapDB = { enabled = true, map = { ["Holy Light"] = "Libram of Radiance" }, useDelay = true, combatSmartMode = true, combatSameTickAttempt = true, combatEquipRetry = true }
print("LibramMap entries visible to the runtime:", (function() local n = 0 for _ in pairs(LibramMap) do n = n + 1 end return n end)())
W.fire("PLAYER_LOGIN")   -- 1.12 : handler called with NO arguments
print("after PLAYER_LOGIN, LibramMap entries:", (function() local n = 0 for _ in pairs(LibramMap) do n = n + 1 end return n end)(), " (the OnEvent(self, event, ...) branches never run: 'event' parameter is nil)")
CastSpellByName("Holy Light(Rank 3)")
print("press Holy Light -> equip requests:", W.logCount("UCI"), " casts:", W.castCount("Holy Light"))
print("--- B. once the map is applied (what the config UI does), combat, 1.5 s swap GCD")
W.reset(); W.putBag(0, 1, ITEM.Radiance); W.equip(ITEM.Light)
LibramSwap_ApplySelection("Holy Light", "Libram of Radiance")   -- note: this EQUIPS immediately (out of combat here)
W.advance(0.5)
print("relic after ApplySelection (it equipped on selection):", NAME[W.sinv[18]])
W.clearBags(); W.putBag(0, 1, ITEM.Radiance); W.equip(ITEM.Faithful); W.combat = true; W.log = {}; W.casts = {}; W.gcd = { start = 0, dur = 0 }
local t0 = W.now
CastSpellByName("Holy Light(Rank 3)")
W.advance(3)
for i = 1, table.getn(W.log) do print("  " .. W.log[i]) end
print("casts accepted:", W.castCount("Holy Light"), " refused:", W.logCount("REFUSED"))
print("--- C. same as B but the client updates slot 18 synchronously (W.syncEquip = true)")
W.reset(); W.syncEquip = true
LibramSwap_ApplySelection("Holy Light", "Libram of Radiance")
W.advance(0.5)
W.clearBags(); W.putBag(0, 1, ITEM.Radiance); W.equip(ITEM.Faithful); W.combat = true; W.log = {}; W.casts = {}; W.gcd = { start = 0, dur = 0 }
CastSpellByName("Holy Light(Rank 3)")
W.advance(3)
for i = 1, table.getn(W.log) do print("  " .. W.log[i]) end
print("casts accepted:", W.castCount("Holy Light"), " refused:", W.logCount("REFUSED"))
print("--- D. vendor window open while a spell is cast (no window guard in the old code)")
W.reset(); W.putBag(0, 1, ITEM.Radiance); W.equip(ITEM.Light)
LibramSwap_ApplySelection("Holy Light", "Libram of Radiance")
W.advance(0.5)
W.clearBags(); W.putBag(0, 1, ITEM.Radiance); W.equip(ITEM.Faithful); W.log = {}; W.gcd = { start = 0, dur = 0 }
W.showWindow("MerchantFrame")
CastSpellByName("Holy Light")
W.advance(0.5)
for i = 1, table.getn(W.log) do print("  " .. W.log[i]) end
