-- ShikaSwap_Hooks.lua : cast hooks (CastSpellByName / CastSpell / UseAction), event frame, throttled OnUpdate.
-- 1.12 conventions : event handlers receive NO arguments -> read the globals `event`, `arg1`, `arg2` (this, not `self`).

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
local string_lower = string.lower
local string_find = string.find

-- ---------------------------------------------------------------- action bar -> spell name
-- The tooltip of an action-bar spell button starts with the spell name (left) and its rank (right).
-- returns key, rank, isMacro (key = canonical rule key when the button is a spell that has a rule)
function SS.ActionSpell(slot)
    if not SS.hasRules then return nil end
    local c = SS.actionCache[slot]
    if c ~= nil then return c.key, c.rank, c.macro end
    local key, rank
    local macro = false
    if HasAction and HasAction(slot) then
        local txt = GetActionText and GetActionText(slot)
        if txt and txt ~= "" then
            macro = true
        else
            if not SS.tip then
                SS.tip = CreateFrame("GameTooltip", "ShikaSwapTip", nil, "GameTooltipTemplate")
            end
            SS.tip:SetOwner(WorldFrame, "ANCHOR_NONE")
            SS.tip:SetAction(slot)
            local l = getglobal("ShikaSwapTipTextLeft1")
            local r = getglobal("ShikaSwapTipTextRight1")
            local name = l and l:GetText()
            if name then
                key = SS.lc[string_lower(name)]
                local rt = r and r:GetText()
                if rt and string_find(rt, "^Rank %d+$") then rank = rt end
            end
        end
    end
    SS.actionCache[slot] = { key = key, rank = rank, macro = macro }
    return key, rank, macro
end

-- ---------------------------------------------------------------- hook installation
function SS.Active()
    return SS.db and SS.db.enabled and SS.hasRules and not SS.conflict
end

function SS.InstallHooks()
    if SS.hooked then return end
    SS.hooked = true
    local origByName = CastSpellByName
    local origSpell = CastSpell
    local origAction = UseAction
    SS.orig = { CastSpellByName = origByName, CastSpell = origSpell, UseAction = origAction }

    if origByName then
        CastSpellByName = function(spell, a2, a3)
            SS.attempts = SS.attempts + 1
            if SS.hasRules and SS.db and SS.db.enabled and not SS.conflict and type(spell) == "string" then
                local base, rank = SS.ParseSpell(spell)
                local key = base and SS.lc[string_lower(base)]
                if SS.queue then SS.CancelQueueFor(key, base) end
                if key then
                    return SS.Run(key, rank, function() return origByName(spell, a2, a3) end, "byname")
                end
            end
            return origByName(spell, a2, a3)
        end
    end

    if origSpell then
        CastSpell = function(index, book)
            SS.attempts = SS.attempts + 1
            if SS.hasRules and SS.db and SS.db.enabled and not SS.conflict and (book == nil or book == "spell") then
                local name, rank = GetSpellName(index, "spell")
                local key = name and SS.lc[string_lower(name)]
                if SS.queue then SS.CancelQueueFor(key, name) end
                if key then
                    if rank == "" then rank = nil end
                    return SS.Run(key, rank, function() return origSpell(index, book) end, "book")
                end
            end
            return origSpell(index, book)
        end
    end

    if origAction then
        UseAction = function(slot, a2, a3)
            SS.attempts = SS.attempts + 1
            if SS.hasRules and SS.db and SS.db.enabled and not SS.conflict then
                local key, rank, macro = SS.ActionSpell(slot)
                -- a macro button may re-enter through CastSpellByName : only plain spell/item buttons cancel a queued cast
                if SS.queue and not macro then SS.CancelQueueFor(key) end
                if key then
                    return SS.Run(key, rank, function() return origAction(slot, a2, a3) end, "action")
                end
            end
            return origAction(slot, a2, a3)
        end
    end
end

-- ---------------------------------------------------------------- conflict with the old LibramSwap addon
function SS.DetectConflict()
    local old = (type(LibramSwap_ApplySelection) == "function") or (type(LibramSwap_HasItem) == "function")
    if old and not SS.conflict then
        SS.conflict = true
        SS.Print(SS.T("conflict"))
    elseif not old then
        SS.conflict = false
    end
    return SS.conflict
end

-- ---------------------------------------------------------------- events
local EVENTS = {
    "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "BAG_UPDATE", "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "SPELLCAST_START", "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
    "SPELLCAST_CHANNEL_START", "SPELLCAST_CHANNEL_STOP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
    "UI_ERROR_MESSAGE", "PLAYER_DEAD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
}

function SS.OnEvent(ev, a1, a2)
    if ev == "ADDON_LOADED" then
        if a1 == "ShikaSwap" then SS.InitDB() end
    elseif ev == "VARIABLES_LOADED" then
        SS.InitDB()
    elseif ev == "PLAYER_LOGIN" then
        SS.InitDB() -- idempotent : re-binds SS.db to the global the client loaded
        SS.DetectConflict()
        SS.bagDirty = true
        SS.book = nil
        if SS.ImportOnFirstRun then SS.ImportOnFirstRun() end
        SS.Print(SS.T("loaded", SS.version))
        SS.TL("SESSION", "login v", SS.version, " mode=", SS.db.combat, " rules=", SS.nRules, " enabled=", SS.db.enabled and 1 or 0, " offgcd=", SS.db.offGcd,
            " nampower=", (type(GetNampowerVersion) == "function") and 1 or 0, " relic=", SS.ItemNameFromLink(GetInventoryItemLink("player", SS.SLOT)))
        if SS.db.opener then SS.ArmOpener(1.5) end
    elseif ev == "PLAYER_ENTERING_WORLD" then
        SS.bagDirty = true
        SS.book = nil
        SS.pending = nil
        SS.castUntil = nil
        SS.chanUntil = nil
        if SS.actionCache then SS.actionCache = {} end
        SS.QueueClear("zoning")
    elseif ev == "BAG_UPDATE" then
        SS.bagDirty = true
    elseif ev == "UNIT_INVENTORY_CHANGED" then
        if a1 == "player" then
            if SS.probeEquip and SS.FinishProbe then SS.FinishProbe() end
            if SS.pending then
                local link = GetInventoryItemLink("player", SS.SLOT)
                if SS.PendingResolved(SS.pending, SS.ItemIdFromLink(link), SS.ItemNameFromLink(link)) then
                    SS.Dbg("swap confirmed by the server after ", string.format("%.0f", (GetTime() - SS.pending.at) * 1000), " ms")
                    SS.TL("CONFIRM", "equipped=", SS.ItemNameFromLink(link), " ", string.format("%.0f", (GetTime() - SS.pending.at) * 1000), "ms after the swap")
                    SS.pending = nil
                end
            end
        end
        SS.bagDirty = true
    elseif ev == "PLAYER_REGEN_ENABLED" then
        SS.TL("COMBAT", "end")
        if SS.db and SS.db.opener then SS.ArmOpener(1.0) end
    elseif ev == "PLAYER_REGEN_DISABLED" then
        SS.TL("COMBAT", "start relic=", SS.ItemNameFromLink(GetInventoryItemLink("player", SS.SLOT)))
    elseif ev == "SPELLCAST_START" then
        local ms = tonumber(a2) or 0
        SS.castUntil = GetTime() + ms / 1000 + 0.2
    elseif ev == "SPELLCAST_CHANNEL_START" then
        local ms = tonumber(a1) or 0
        SS.chanUntil = GetTime() + ms / 1000 + 0.2
    elseif ev == "SPELLCAST_STOP" or ev == "SPELLCAST_FAILED" or ev == "SPELLCAST_INTERRUPTED" then
        SS.castUntil = nil
    elseif ev == "SPELLCAST_CHANNEL_STOP" then
        SS.chanUntil = nil
    elseif ev == "SPELLS_CHANGED" or ev == "LEARNED_SPELL_IN_TAB" then
        SS.book = nil
    elseif ev == "UI_ERROR_MESSAGE" then
        if SS.db then SS.OnErrorMessage(a1) end
    elseif ev == "PLAYER_DEAD" then
        SS.QueueClear("dead")
        SS.pending = nil
    elseif ev == "ACTIONBAR_SLOT_CHANGED" or ev == "ACTIONBAR_PAGE_CHANGED" then
        if SS.actionCache then SS.actionCache = {} end
    end
end

-- opener : equip, out of combat, the relic of a chosen spell (so the first combat cast needs no swap)
function SS.ArmOpener(delay)
    SS.openerAt = GetTime() + delay
    if SS.frame then SS.frame:Show() end
end

function SS.OnUpdate(elapsed)
    SS.acc = (SS.acc or 0) + (elapsed or 0)
    if SS.acc < SS.TICK then return end
    SS.acc = 0
    if SS.queue then SS.QueueTick() end
    if SS.verify then SS.TraceVerifyTick(GetTime()) end
    if SS.openerAt and GetTime() >= SS.openerAt then
        SS.openerAt = nil
        if SS.Active() and SS.db.opener and not SS.InCombat() then
            local ok, why = SS.PreSwap(SS.db.opener)
            SS.Dbg("opener ", SS.db.opener, ": ", tostring(ok), " ", tostring(why))
        end
        if not SS.queue and SS.frame then SS.frame:Hide() end
    end
    if not SS.queue and not SS.openerAt and not SS.verify and SS.frame then SS.frame:Hide() end
end

-- ---------------------------------------------------------------- boot (file load)
SS.frame = CreateFrame("Frame")
for i = 1, table.getn(EVENTS) do
    SS.frame:RegisterEvent(EVENTS[i])
end
SS.frame:SetScript("OnEvent", function() SS.OnEvent(event, arg1, arg2) end)
SS.frame:SetScript("OnUpdate", function() SS.OnUpdate(arg1) end)
SS.frame:Hide() -- a hidden frame gets no OnUpdate : the throttled loop only runs while something is queued

SS.InstallHooks()
