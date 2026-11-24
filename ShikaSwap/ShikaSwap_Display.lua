-- ShikaSwap_Display.lua : minimap button (+ quick menu), floating relic indicator with the combat-swap countdown,
-- missing-relic alert, and their slash commands (/ssw minimap | indicator | alert).
-- Nothing is created at file load : frames are built on PLAYER_LOGIN (saved variables are loaded by then), each build under pcall.
-- 1.12 / Lua 5.0 : no '#', no string.match, no '...', handlers read `this` / `arg1` / `event`.

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
local string_find = string.find
local string_lower = string.lower
local string_format = string.format
local getn = table.getn
local tinsert = table.insert

SS.SWAP_CD = 1.5                    -- combat swap cooldown (server rule, see Core)
SS.MM_RADIUS = 78
SS.MM_DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Book_11"
SS.IND_DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local EN = SS.M.en
local FR = SS.M.fr
EN.d_state_active = "active"
FR.d_state_active = "actif"
EN.d_state_off = "disabled"
FR.d_state_off = "désactivé"
EN.d_state_dormant = "DORMANT (LibramSwap detected)"
FR.d_state_dormant = "EN VEILLE (LibramSwap détecté)"
EN.d_tip_state = "State: %s"
FR.d_tip_state = "État : %s"
EN.d_tip_mode = "Combat mode: %s (effective: %s)"
FR.d_tip_mode = "Mode en combat : %s (effectif : %s)"
EN.d_tip_relic = "Equipped relic: %s"
FR.d_tip_relic = "Relique équipée : %s"
EN.d_tip_spec = "Spec: %s"
FR.d_tip_spec = "Spécialité : %s"
EN.d_tip_hint = "Left click: menu   Right click: quick menu   Drag: move"
FR.d_tip_hint = "Clic gauche : menu   Clic droit : menu rapide   Glisser : déplacer"
EN.d_ind_hint = "Drag to move (unless locked). Settings: /ssw menu, Settings tab."
FR.d_ind_hint = "Glisse pour déplacer (sauf si verrouillé). Réglages : /ssw menu, onglet Réglages."
EN.d_q_toggle_on = "Enable ShikaSwap"
FR.d_q_toggle_on = "Activer ShikaSwap"
EN.d_q_toggle_off = "Disable ShikaSwap"
FR.d_q_toggle_off = "Désactiver ShikaSwap"
EN.d_q_mode = "Combat mode: %s (next)"
FR.d_q_mode = "Mode en combat : %s (suivant)"
EN.d_q_spec = "Rules: %s"
FR.d_q_spec = "Règles : %s"
EN.d_q_ind_show = "Show relic indicator"
FR.d_q_ind_show = "Afficher l'indicateur de relique"
EN.d_q_ind_hide = "Hide relic indicator"
FR.d_q_ind_hide = "Masquer l'indicateur de relique"
EN.d_q_menu = "Open the menu"
FR.d_q_menu = "Ouvrir le menu"
EN.alert_missing = "Missing relic for %s: none of [%s] is in your bags or equipped."
FR.alert_missing = "Relique manquante pour %s : aucune de [%s] n'est dans tes sacs ni équipée."
EN.alert_test = "This is how a missing-relic alert looks."
FR.alert_test = "Voici à quoi ressemble l'alerte de relique manquante."
EN.d_usage_ind = "Usage: /ssw indicator on|off|lock|unlock|scale <0.5-2.5>|reset"
FR.d_usage_ind = "Usage : /ssw indicator on|off|lock|unlock|scale <0.5-2.5>|reset"
EN.d_usage_alert = "Usage: /ssw alert chat on|off | sound on|off | test"
FR.d_usage_alert = "Usage : /ssw alert chat on|off | sound on|off | test"
EN.d_scale = "Indicator scale: %s"
FR.d_scale = "Échelle de l'indicateur : %s"

-- ---------------------------------------------------------------- shared helpers
-- "active" | "off" | "dormant"
function SS.StateKey()
    if SS.conflict then return "dormant" end
    if SS.db and not SS.db.enabled then return "off" end
    return "active"
end

function SS.NextMode()
    local modes = { "auto", "burst", "wait", "skip" }
    local idx = 1
    for i = 1, getn(modes) do
        if modes[i] == SS.db.combat then idx = i end
    end
    idx = idx + 1
    if idx > getn(modes) then idx = 1 end
    SS.cmds.mode(modes[idx])
end

-- remaining seconds of the combat swap cooldown, 0 when none
function SS.SwapCooldownRemaining(now)
    local t = SS.lastSwapCombat
    if not t then return 0 end
    local rem = SS.SWAP_CD - (now - t)
    if rem < 0 then return 0 end
    if rem > SS.SWAP_CD then return SS.SWAP_CD end
    return rem
end

function SS.EquippedRelicName()
    return SS.ItemNameFromLink(GetInventoryItemLink("player", SS.SLOT))
end

function SS.EquippedTexture()
    if GetInventoryItemTexture then return GetInventoryItemTexture("player", SS.SLOT) end
    return nil
end

-- ---------------------------------------------------------------- missing-relic alert (called from Core, pcall-protected)
function SS.AlertMissing(key)
    local al = SS.db and SS.db.alert
    if type(al) ~= "table" or not (al.chat or al.sound) then return false end
    if not SS.alerted then SS.alerted = {} end
    if SS.alerted[key] then return false end          -- once per spell and per combat
    SS.alerted[key] = true
    local list = SS.db.rules[key]
    if al.chat then
        SS.Print("|cFFFFAA00" .. SS.T("alert_missing", key, list and table.concat(list, ", ") or "?") .. "|r")
    end
    if al.sound and PlaySound then pcall(PlaySound, "RaidWarning") end
    SS.Inc("alerts")
    return true
end

-- ---------------------------------------------------------------- minimap button
function SS.MinimapPlace()
    local b = SS.mmButton
    if not b then return end
    local a = SS.db.minimap.angle
    local r = math.rad(a)
    local x = SS.MM_RADIUS * math.cos(r)
    local y = SS.MM_RADIUS * math.sin(r)
    b.offX, b.offY = x, y
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function SS.MinimapSetAngle(a)
    if type(a) ~= "number" then return end
    SS.db.minimap.angle = a
    SS.MinimapPlace()
end

function SS.MinimapIcon()
    local b = SS.mmButton
    if not b then return end
    b.icon:SetTexture(SS.EquippedTexture() or SS.MM_DEFAULT_ICON)
end

function SS.MinimapDragUpdate()
    if not Minimap or not GetCursorPosition then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    if type(mx) ~= "number" or type(px) ~= "number" or type(s) ~= "number" or s == 0 then return end
    SS.MinimapSetAngle(math.deg(math.atan2(py / s - my, px / s - mx)))
end

function SS.TipLines()
    local out = {}
    tinsert(out, "ShikaSwap " .. SS.version)
    tinsert(out, SS.T("d_tip_state", SS.T("d_state_" .. SS.StateKey())))
    tinsert(out, SS.T("d_tip_mode", SS.db.combat, SS.EffectiveMode()))
    tinsert(out, SS.T("d_tip_relic", tostring(SS.EquippedRelicName() or SS.T("ui_none"))))
    if SS.SpecsAvailable and SS.SpecsAvailable() then
        local spec = SS.CurrentSpec()
        tinsert(out, SS.T("d_tip_spec", SS.SpecName(spec)))
    end
    return out
end

function SS.MinimapOnEnter()
    if not GameTooltip then return end
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    local l = SS.TipLines()
    GameTooltip:SetText(l[1], 1, 1, 1)
    for i = 2, getn(l) do GameTooltip:AddLine(l[i], 0.8, 0.9, 1, 1) end
    GameTooltip:AddLine(SS.T("d_tip_hint"), 0.5, 0.5, 0.5, 1)
    GameTooltip:Show()
end

function SS.MinimapOnClick()
    if arg1 == "RightButton" then SS.QuickToggle() else SS.cmds.menu() end
end

function SS.BuildMinimap()
    if SS.mmButton then return SS.mmButton end
    if not Minimap then return nil end
    local b = CreateFrame("Button", "ShikaSwapMinimapButton", Minimap)
    b:SetWidth(32)
    b:SetHeight(32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetWidth(20)
    b.icon:SetHeight(20)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 1)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetWidth(52)
    border:SetHeight(52)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", SS.MinimapOnClick)
    b:SetScript("OnEnter", SS.MinimapOnEnter)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnDragStart", function() this:SetScript("OnUpdate", SS.MinimapDragUpdate) end)
    b:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
    SS.mmButton = b
    SS.MinimapPlace()
    SS.MinimapIcon()
    return b
end

-- ---------------------------------------------------------------- quick menu (right click on the minimap button)
SS.QUICK = { "toggle", "mode", "spec_HOLY", "spec_RET", "spec_PROT", "spec_NECRO", "indicator", "menu" }

function SS.QuickLabel(action)
    if action == "toggle" then return SS.T(SS.db.enabled and "d_q_toggle_off" or "d_q_toggle_on") end
    if action == "mode" then return SS.T("d_q_mode", SS.db.combat) end
    if action == "indicator" then return SS.T(SS.db.indicator.show and "d_q_ind_hide" or "d_q_ind_show") end
    if action == "menu" then return SS.T("d_q_menu") end
    return SS.T("d_q_spec", SS.SpecName(string.sub(action, 6)))
end

function SS.QuickAction(action)
    if action == "toggle" then
        if SS.db.enabled then SS.cmds.off() else SS.cmds.on() end
    elseif action == "mode" then
        SS.NextMode()
    elseif action == "indicator" then
        SS.cmds.indicator(SS.db.indicator.show and "off" or "on")
    elseif action == "menu" then
        SS.cmds.menu()
    elseif string_find(action, "^spec_") then
        SS.cmds.spec("load " .. string.sub(action, 6))
    end
    if SS.UI and SS.UI.Refresh then pcall(SS.UI.Refresh) end
end

function SS.QuickClick()
    local a = this.action
    if SS.quick then SS.quick:Hide() end
    local ok, err = pcall(SS.QuickAction, a)
    if not ok then SS.lastError = "quick: " .. tostring(err) end
end

function SS.QuickUpdate()
    if not MouseIsOver then return end
    if MouseIsOver(this) or (SS.mmButton and MouseIsOver(SS.mmButton)) then
        this.idle = 0
        return
    end
    this.idle = (this.idle or 0) + (arg1 or 0)
    if this.idle > 1.2 then this:Hide() end
end

function SS.BuildQuick()
    if SS.quick then return SS.quick end
    local q = CreateFrame("Frame", "ShikaSwapQuickMenu", UIParent)
    q:SetWidth(230)
    q:SetFrameStrata("DIALOG")
    q:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    q:SetBackdropColor(0, 0, 0, 0.9)
    q:EnableMouse(true)
    q.items = {}
    for i = 1, getn(SS.QUICK) do
        local it = CreateFrame("Button", nil, q, "UIPanelButtonTemplate")
        it:SetWidth(214)
        it:SetHeight(22)
        it:SetPoint("TOPLEFT", q, "TOPLEFT", 8, -8 - (i - 1) * 24)
        it.action = SS.QUICK[i]
        it:SetScript("OnClick", SS.QuickClick)
        q.items[i] = it
    end
    q:SetHeight(16 + getn(SS.QUICK) * 24)
    q:SetScript("OnUpdate", SS.QuickUpdate)
    if UISpecialFrames then tinsert(UISpecialFrames, "ShikaSwapQuickMenu") end
    q:Hide()
    SS.quick = q
    return q
end

function SS.QuickRefresh()
    local q = SS.quick
    local specs = SS.SpecsAvailable and SS.SpecsAvailable()
    local y = 0
    for i = 1, getn(SS.QUICK) do
        local it = q.items[i]
        local a = SS.QUICK[i]
        if string_find(a, "^spec_") and not specs then
            it:Hide()
        else
            it:Show()
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", q, "TOPLEFT", 8, -8 - y * 24)
            it:SetText(SS.QuickLabel(a))
            y = y + 1
        end
    end
    q:SetHeight(16 + y * 24)
end

function SS.QuickToggle()
    local ok, err = pcall(function()
        local q = SS.BuildQuick()
        if q:IsShown() then
            q:Hide()
            return
        end
        SS.QuickRefresh()
        q.idle = 0
        q:ClearAllPoints()
        if SS.mmButton then q:SetPoint("TOPRIGHT", SS.mmButton, "BOTTOMRIGHT", 0, 0) else q:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
        q:Show()
    end)
    if not ok then SS.lastError = "quick: " .. tostring(err) end
end

-- ---------------------------------------------------------------- floating indicator
function SS.IndicatorPlace()
    local f = SS.indicator
    if not f then return end
    local ind = SS.db.indicator
    f:ClearAllPoints()
    if type(ind.x) == "number" and type(ind.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ind.x, ind.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

function SS.IndicatorSetScale(s)
    local ind = SS.db.indicator
    local old = ind.scale
    if type(s) ~= "number" then return false end
    if s < 0.5 then s = 0.5 end
    if s > 2.5 then s = 2.5 end
    -- keep the icon where it is on the screen : the saved offsets are expressed in the frame's own scale
    if type(ind.x) == "number" and type(ind.y) == "number" and old > 0 then
        ind.x = ind.x * old / s
        ind.y = ind.y * old / s
    end
    ind.scale = s
    if SS.indicator then
        SS.indicator:SetScale(s)
        SS.IndicatorPlace()
    end
    return true
end

function SS.IndicatorUpdate()
    local f = SS.indicator
    if not f then return end
    f.acc = (f.acc or 0) + (arg1 or 0)
    if f.acc < 0.05 then return end
    f.acc = 0
    SS.IndicatorTick(GetTime())
end

-- one redraw of the indicator (separate from the OnUpdate throttle so tests can drive it)
function SS.IndicatorTick(now)
    local f = SS.indicator
    if not f then return end
    local tex = SS.EquippedTexture()
    if tex ~= f.curTex then
        f.curTex = tex
        f.icon:SetTexture(tex or SS.IND_DEFAULT_ICON)
    end
    local rem = SS.SwapCooldownRemaining(now)
    if rem > 0 then
        f.text:SetText(string_format("%.1f", rem))
        f.icon:SetVertexColor(0.45, 0.45, 0.45)
    else
        f.text:SetText("")
        f.icon:SetVertexColor(1, 1, 1)
    end
    f.cdShown = rem > 0
end

function SS.IndicatorOnEnter()
    if not GameTooltip then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(tostring(SS.EquippedRelicName() or SS.T("ui_none")), 1, 1, 1)
    GameTooltip:AddLine(SS.T("d_ind_hint"), 0.6, 0.6, 0.6, 1)
    GameTooltip:Show()
end

function SS.IndicatorDragStop()
    this:StopMovingOrSizing()
    local l, t = this:GetLeft(), this:GetTop()
    if type(l) == "number" and type(t) == "number" then
        SS.db.indicator.x = l
        SS.db.indicator.y = t
    end
end

function SS.BuildIndicator()
    if SS.indicator then return SS.indicator end
    local f = CreateFrame("Frame", "ShikaSwapIndicator", UIParent)
    f:SetWidth(44)
    f:SetHeight(44)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() if not SS.db.indicator.locked then this:StartMoving() end end)
    f:SetScript("OnDragStop", SS.IndicatorDragStop)
    f:SetScript("OnEnter", SS.IndicatorOnEnter)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetWidth(34)
    f.icon:SetHeight(34)
    f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:SetScript("OnUpdate", SS.IndicatorUpdate)
    SS.indicator = f
    f:SetScale(SS.db.indicator.scale)
    SS.IndicatorPlace()
    return f
end

-- ---------------------------------------------------------------- apply the saved display settings (login, menu, commands, reset)
function SS.ApplyDisplay()
    if not SS.db then return end
    local mm, ind = SS.db.minimap, SS.db.indicator
    local ok, err = pcall(function()
        local b = SS.BuildMinimap()
        if b then
            SS.MinimapPlace()
            SS.MinimapIcon()
            if mm.show then b:Show() else b:Hide() end
        end
    end)
    if not ok then SS.lastError = "minimap: " .. tostring(err) end
    ok, err = pcall(function()
        local f = SS.BuildIndicator()
        f:SetScale(ind.scale)
        SS.IndicatorPlace()
        if ind.show then
            f:Show()
            SS.IndicatorTick(GetTime())
        else
            f:Hide()
        end
    end)
    if not ok then SS.lastError = "indicator: " .. tostring(err) end
end

-- ---------------------------------------------------------------- commands
local C = SS.cmds
local function Arg(rest)
    local _, _, a, b = string_find(rest or "", "^%s*(%S*)%s*(.-)%s*$")
    return string_lower(a or ""), b or ""
end

local function OnOff(v)
    if v == "on" or v == "1" or v == "true" then return true end
    if v == "off" or v == "0" or v == "false" then return false end
    return nil
end

function C.minimap(rest)
    local a = Arg(rest)
    if a == "reset" then
        SS.db.minimap.angle = 200
        SS.db.minimap.show = true
    else
        local v = OnOff(a)
        if v == nil then v = not SS.db.minimap.show end
        SS.db.minimap.show = v
    end
    SS.ApplyDisplay()
    SS.Print(SS.T(SS.db.minimap.show and "flag_on" or "flag_off", "minimap"))
end

function C.indicator(rest)
    local a, b = Arg(rest)
    local ind = SS.db.indicator
    if a == "lock" then
        ind.locked = true
    elseif a == "unlock" then
        ind.locked = false
    elseif a == "scale" then
        local n = tonumber(b)
        if not n then SS.Print(SS.T("d_usage_ind")) return end
        SS.IndicatorSetScale(n)
        SS.Print(SS.T("d_scale", string_format("%.2f", SS.db.indicator.scale)))
        return
    elseif a == "reset" then
        ind.x, ind.y = nil, nil
        ind.scale = 1.0
        ind.show = true
    elseif a == "" then
        ind.show = not ind.show
    else
        local v = OnOff(a)
        if v == nil then SS.Print(SS.T("d_usage_ind")) return end
        ind.show = v
    end
    SS.ApplyDisplay()
    SS.Print(SS.T(ind.show and "flag_on" or "flag_off", "indicator") .. (ind.locked and " (locked)" or ""))
end

function C.alert(rest)
    local a, b = Arg(rest)
    local al = SS.db.alert
    if a == "chat" or a == "sound" then
        local v = OnOff(string_lower(b))
        if v == nil then SS.Print(SS.T("d_usage_alert")) return end
        al[a] = v
        SS.Print(SS.T(v and "flag_on" or "flag_off", "alert " .. a))
    elseif a == "test" then
        SS.Print("|cFFFFAA00" .. SS.T("alert_test") .. "|r")
        if al.sound and PlaySound then pcall(PlaySound, "RaidWarning") end
    else
        SS.Print(SS.T("d_usage_alert"))
    end
end

-- ---------------------------------------------------------------- events
SS.displayFrame = CreateFrame("Frame")
SS.displayFrame:RegisterEvent("PLAYER_LOGIN")
SS.displayFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
SS.displayFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
SS.displayFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
SS.displayFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_DISABLED" then
        SS.alerted = {}
        return
    end
    if not SS.db then return end
    if event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" and SS.mmButton then pcall(SS.MinimapIcon) end
        return
    end
    SS.ApplyDisplay()
end)
