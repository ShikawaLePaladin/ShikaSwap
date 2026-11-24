-- ShikaSwap_Spec.lua : per-specialisation rule sets (Paladin : Holy / Protection / Retribution), talent detection, automatic switch.
-- 1.12 : talent API = GetNumTalentTabs() / GetTalentTabInfo(tab) -> name, icon, pointsSpent, background. Everything is tolerant :
-- an unreadable or tied talent tree gives "unknown" (nil), never an error ; the manual spec is the fallback.
-- Lua 5.0 : no '#', no string.match, no '...'.

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
local string_lower = string.lower
local string_find = string.find
local getn = table.getn
local tinsert = table.insert

SS.SPEC_ORDER = { "HOLY", "PROT", "RET", "NECRO" }   -- NECRO has no talent tab : it is recognised from a recorded talent signature
-- talent tab index -> spec, per class (only classes listed here have per-spec profiles)
SS.SPEC_TABS = { PALADIN = { "HOLY", "PROT", "RET" } }
-- English tab names / background keywords, used to double-check the index (the order is the same on Turtle)
SS.SPEC_NAMES = { holy = "HOLY", protection = "PROT", retribution = "RET" }

local EN = SS.M.en
local FR = SS.M.fr
EN.spec_HOLY = "Holy"
FR.spec_HOLY = "Sacré"
EN.spec_PROT = "Protection"
FR.spec_PROT = "Protection"
EN.spec_RET = "Retribution"
FR.spec_RET = "Vindicte"
EN.spec_NECRO = "Necroladin"
FR.spec_NECRO = "Necroladin"
EN.spec_unknown = "unknown"
FR.spec_unknown = "inconnue"
EN.spec_auto_on = "Automatic spec switch: on"
FR.spec_auto_on = "Bascule automatique de spécialité : activée"
EN.spec_auto_off = "Automatic spec switch: off"
FR.spec_auto_off = "Bascule automatique de spécialité : coupée"
EN.spec_saved = "Rules saved for the %s spec."
FR.spec_saved = "Règles enregistrées pour la spécialité %s."
EN.spec_loaded = "Rules of the %s spec loaded."
FR.spec_loaded = "Règles de la spécialité %s chargées."
EN.spec_none = "No saved rules for the %s spec yet (save yours with /ssw spec save)."
FR.spec_none = "Aucune règle enregistrée pour la spécialité %s (enregistre les tiennes avec /ssw spec save)."
EN.spec_switched = "Spec changed to %s: rules switched."
FR.spec_switched = "Spécialité changée en %s : règles échangées."
EN.spec_kept = "Spec changed to %s: no saved rules yet, current rules kept."
FR.spec_kept = "Spécialité changée en %s : pas encore de règles enregistrées, règles actuelles conservées."
EN.spec_bad = "Spec must be holy, prot, ret or necro."
FR.spec_bad = "La spécialité doit être holy, prot, ret ou necro."
EN.necro_sig_none = "Talent signature not recorded: Necroladin is never chosen automatically (manual choice only)."
FR.necro_sig_none = "Signature de talents non enregistrée : Necroladin n'est jamais choisi automatiquement (choix manuel uniquement)."
EN.necro_sig = "Necroladin signature: %s (tolerance +/-%s per tree)"
FR.necro_sig = "Signature Necroladin : %s (tolérance +/-%s points par arbre)"
EN.necro_captured = "Necroladin signature recorded: %s (tolerance +/-%s per tree)."
FR.necro_captured = "Signature Necroladin enregistrée : %s (tolérance +/-%s points par arbre)."
EN.necro_nocapture = "Cannot read your talents (or no point spent): open the talent window once and try again."
FR.necro_nocapture = "Impossible de lire tes talents (ou aucun point dépensé) : ouvre une fois la fenêtre des talents et réessaie."
EN.necro_cleared = "Necroladin signature forgotten (Necroladin is now manual only)."
FR.necro_cleared = "Signature Necroladin oubliée (Necroladin redevient manuel uniquement)."
EN.necro_tol = "Necroladin tolerance: +/-%s points per tree."
FR.necro_tol = "Tolérance Necroladin : +/-%s points par arbre."
EN.necro_tol_bad = "Tolerance must be a number from 0 to 10."
FR.necro_tol_bad = "La tolérance doit être un nombre de 0 à 10."
EN.spec_reset = "Slot %s reset."
FR.spec_reset = "Emplacement %s réinitialisé."
EN.spec_reset_necro = "Slot Necroladin back to its preset."
FR.spec_reset_necro = "Emplacement Necroladin remis au préréglage."
EN.spec_manual = "Fallback spec (used only if the talents cannot be read): %s"
FR.spec_manual = "Spécialité de secours (utilisée seulement si les talents sont illisibles) : %s"
EN.spec_now = "Spec: %s (%s)   automatic switch: %s"
FR.spec_now = "Spécialité : %s (%s)   bascule automatique : %s"
EN.spec_class = "Per-spec profiles are only available for Paladins."
FR.spec_class = "Les profils par spécialité ne sont disponibles que pour le Paladin."
EN.src_talents = "talents"
FR.src_talents = "talents"
EN.src_manual = "manual"
FR.src_manual = "manuel"
EN.undo_done = "Previous rules restored (run /ssw undo again to come back)."
FR.undo_done = "Anciennes règles restaurées (refais /ssw undo pour revenir)."
EN.undo_none = "Nothing to undo."
FR.undo_none = "Rien à annuler."

function SS.SpecName(spec)
    if not spec then return SS.T("spec_unknown") end
    return SS.T("spec_" .. spec)
end

function SS.SpecsAvailable()
    local cls = SS.PlayerClass()
    return cls ~= nil and SS.SPEC_TABS[cls] ~= nil
end

-- reads the talent trees. Returns best, pointsBySpec : best = the spec of the tree with the most points (nil if unreadable,
-- no point spent or tie), pointsBySpec = { HOLY = n, PROT = n, RET = n } (nil when the API is missing / unreadable)
function SS.ScanTalents()
    local cls = SS.PlayerClass()
    local tabs = cls and SS.SPEC_TABS[cls]
    if not tabs then return nil, nil end
    if type(GetNumTalentTabs) ~= "function" or type(GetTalentTabInfo) ~= "function" then return nil, nil end
    local ok, n = pcall(GetNumTalentTabs)
    if not ok or type(n) ~= "number" or n < 1 or n > getn(tabs) then return nil, nil end
    local best, bestPts, second = nil, 0, 0
    local by = {}
    for i = 1, n do
        local ok2, name, _, pts, bg = pcall(GetTalentTabInfo, i)
        if ok2 then
            pts = tonumber(pts) or 0
            -- prefer the English tab name / background path when it is recognisable, else the tab index
            local spec = tabs[i]
            local probe = string_lower(tostring(name or "") .. " " .. tostring(bg or ""))
            for word, sp in pairs(SS.SPEC_NAMES) do
                if string_find(probe, word, 1, true) then spec = sp end
            end
            if spec then by[spec] = pts end
            if spec and pts > bestPts then
                second = bestPts
                best, bestPts = spec, pts
            elseif pts > second then
                second = pts
            end
        end
    end
    if not best or bestPts <= 0 or bestPts == second then best = nil end
    return best, by
end

function SS.DetectSpec()
    local best = SS.ScanTalents()
    return best
end

-- true when the current talent points are within the tolerance of the recorded Necroladin signature, tree by tree
function SS.NecroMatches(by)
    local sig = SS.db and SS.db.necroSig
    if type(sig) ~= "table" or type(by) ~= "table" then return false end
    local tol = SS.db.necroTol or 2
    local order = { "HOLY", "PROT", "RET" }
    for i = 1, 3 do
        local k = order[i]
        if type(by[k]) ~= "number" or type(sig[k]) ~= "number" then return false end
        if math.abs(by[k] - sig[k]) > tol then return false end
    end
    return true
end

function SS.NecroSigText(sig)
    sig = sig or (SS.db and SS.db.necroSig)
    if type(sig) ~= "table" then return nil end
    return SS.SpecName("HOLY") .. " " .. tostring(sig.HOLY) .. " / " .. SS.SpecName("PROT") .. " " .. tostring(sig.PROT) .. " / " .. SS.SpecName("RET") .. " " .. tostring(sig.RET)
end

-- records the CURRENT talent distribution as the Necroladin signature. Returns true | false, errorKey
function SS.CaptureNecroSig()
    local _, by = SS.ScanTalents()
    if type(by) ~= "table" or type(by.HOLY) ~= "number" or type(by.PROT) ~= "number" or type(by.RET) ~= "number" then return false, "necro_nocapture" end
    if by.HOLY + by.PROT + by.RET <= 0 then return false, "necro_nocapture" end
    SS.db.necroSig = { HOLY = by.HOLY, PROT = by.PROT, RET = by.RET }
    return true
end

function SS.ClearNecroSig()
    SS.db.necroSig = nil
end

function SS.SetNecroTol(n)
    n = tonumber(n)
    if not n or n ~= n or n < 0 or n > 10 then return false end
    SS.db.necroTol = math.floor(n)
    return true
end

-- canonical text of a slot, to tell "preset" from "edited"
local function CanonSlot(p)
    if type(p) ~= "table" or type(p.rules) ~= "table" then return "" end
    local keys = SS.SortedKeys(p.rules)
    local out = {}
    for i = 1, getn(keys) do
        local k = keys[i]
        local off = (type(p.off) == "table" and p.off[k]) and "-" or "+"
        tinsert(out, off .. k .. "=" .. table.concat(p.rules[k], ","))
    end
    return table.concat(out, ";")
end

function SS.SlotIsPreset(spec)
    if spec ~= "NECRO" then return false end
    return CanonSlot(SS.db.specProfiles.NECRO) == CanonSlot(SS.NecroPreset())
end

-- slot reset : Necroladin goes back to its preset, the other slots are emptied. The rules in use are not touched.
function SS.ResetSpecSlot(spec)
    if not SS.IsSpecToken(spec) then return false end
    if spec == "NECRO" then
        SS.db.specProfiles.NECRO = SS.NecroPreset()
    else
        SS.db.specProfiles[spec] = nil
    end
    return true
end

-- the spec used by the profiles : talents first, the manual fallback second. Returns spec, source
function SS.CurrentSpec()
    local d, by = SS.ScanTalents()
    if SS.NecroMatches(by) then return "NECRO", "talents" end   -- a recorded signature wins over Holy / Protection / Retribution
    if d then return d, "talents" end
    if SS.db and SS.db.specManual then return SS.db.specManual, "manual" end
    return nil, nil
end

function SS.SpecFromText(t)
    local s = string_lower(t or "")
    if s == "holy" or s == "sacre" or s == "sacré" or s == "heal" then return "HOLY" end
    if s == "prot" or s == "protection" or s == "tank" then return "PROT" end
    if s == "ret" or s == "retribution" or s == "vindicte" or s == "dps" then return "RET" end
    if s == "necro" or s == "necroladin" then return "NECRO" end
    return nil
end

function SS.SaveSpec(spec)
    if not SS.SpecsAvailable() or not spec then return false end
    SS.db.specProfiles[spec] = { rules = SS.CopyTable(SS.db.rules), off = SS.CopyTable(SS.db.off) }
    return true
end

function SS.LoadSpec(spec)
    local p = spec and SS.db.specProfiles[spec]
    if not p then return false end
    SS.Backup()
    SS.ApplyRules(p.rules, p.off)
    SS.db.lastSpec = spec
    return true
end

-- called on talent / login / zone events when the automatic switch is on. Never switches in combat.
function SS.SpecCheck()
    if not SS.db or not SS.db.autoSpec or not SS.SpecsAvailable() then return false end
    if SS.InCombat() then
        SS.specPending = true
        return false
    end
    SS.specPending = nil
    local spec = SS.CurrentSpec()
    if not spec or spec == SS.db.lastSpec then return false end
    -- Necroladin chosen by hand and no signature recorded : it is manual-only, the automatic switch does not take it away
    if SS.db.lastSpec == "NECRO" and not SS.db.necroSig then return false end
    local prev = SS.db.lastSpec
    if not prev then
        -- first run : the rules in place belong to the current spec ; do not overwrite an existing profile
        SS.db.lastSpec = spec
        if not SS.db.specProfiles[spec] then SS.SaveSpec(spec) end
        return false
    end
    SS.SaveSpec(prev)                      -- keep the edits made under the previous spec
    if SS.db.specProfiles[spec] then
        SS.LoadSpec(spec)
        SS.Print(SS.T("spec_switched", SS.SpecName(spec)))
    else
        SS.db.lastSpec = spec
        SS.Print(SS.T("spec_kept", SS.SpecName(spec)))
    end
    return true
end

-- ---------------------------------------------------------------- commands
local C = SS.cmds

function C.spec(rest)
    local _, _, sub, arg = string_find(rest or "", "^(%S*)%s*(.-)%s*$")
    sub = string_lower(sub or "")
    arg = arg or ""
    if not SS.SpecsAvailable() then SS.Print(SS.T("spec_class")) return end
    if sub == "" or sub == "status" then
        local spec, src = SS.CurrentSpec()
        SS.Print(SS.T("spec_now", SS.SpecName(spec), src and SS.T("src_" .. src) or "?", SS.db.autoSpec and "on" or "off"))
        if SS.db.necroSig then SS.Print(SS.T("necro_sig", SS.NecroSigText(), SS.db.necroTol)) else SS.Print(SS.T("necro_sig_none")) end
    elseif sub == "necro" then
        local _, _, nsub, narg = string_find(arg, "^(%S*)%s*(.-)%s*$")
        nsub = string_lower(nsub or "")
        if nsub == "capture" then
            local ok, key = SS.CaptureNecroSig()
            if ok then SS.Print(SS.T("necro_captured", SS.NecroSigText(), SS.db.necroTol)) else SS.Print(SS.T(key)) end
        elseif nsub == "clear" then
            SS.ClearNecroSig()
            SS.Print(SS.T("necro_cleared"))
        elseif nsub == "tol" then
            if SS.SetNecroTol(narg) then SS.Print(SS.T("necro_tol", SS.db.necroTol)) else SS.Print(SS.T("necro_tol_bad")) end
        elseif nsub == "reset" then
            SS.ResetSpecSlot("NECRO")
            SS.Print(SS.T("spec_reset_necro"))
        elseif nsub == "" or nsub == "status" then
            if SS.db.necroSig then SS.Print(SS.T("necro_sig", SS.NecroSigText(), SS.db.necroTol)) else SS.Print(SS.T("necro_sig_none")) end
        else
            SS.Print(SS.T("unknown", "spec necro " .. nsub))
        end
    elseif sub == "reset" then
        local spec = SS.SpecFromText(arg)
        if not spec then SS.Print(SS.T("spec_bad")) return end
        SS.ResetSpecSlot(spec)
        SS.Print(spec == "NECRO" and SS.T("spec_reset_necro") or SS.T("spec_reset", SS.SpecName(spec)))
    elseif sub == "auto" then
        local v = string_lower(arg)
        if v == "on" or v == "1" then SS.db.autoSpec = true elseif v == "off" or v == "0" then SS.db.autoSpec = false end
        SS.Print(SS.T(SS.db.autoSpec and "spec_auto_on" or "spec_auto_off"))
        if SS.db.autoSpec then SS.SpecCheck() end
    elseif sub == "save" or sub == "load" then
        local spec = SS.SpecFromText(arg)
        if arg == "" then spec = SS.CurrentSpec() end
        if not spec then SS.Print(SS.T("spec_bad")) return end
        if sub == "save" then
            SS.SaveSpec(spec)
            SS.db.lastSpec = spec
            SS.Print(SS.T("spec_saved", SS.SpecName(spec)))
        elseif SS.LoadSpec(spec) then
            SS.Print(SS.T("spec_loaded", SS.SpecName(spec)))
        else
            SS.Print(SS.T("spec_none", SS.SpecName(spec)))
        end
    elseif sub == "manual" then
        local v = string_lower(arg)
        if v == "off" or v == "none" or v == "" then
            SS.db.specManual = nil
            SS.Print(SS.T("spec_manual", SS.SpecName(nil)))
        else
            local spec = SS.SpecFromText(arg)
            if not spec then SS.Print(SS.T("spec_bad")) return end
            SS.db.specManual = spec
            SS.Print(SS.T("spec_manual", SS.SpecName(spec)))
        end
        if SS.db.autoSpec then SS.SpecCheck() end
    else
        SS.Print(SS.T("unknown", "spec " .. sub))
    end
end

function C.undo()
    local b = SS.db.backup
    if type(b) ~= "table" then SS.Print(SS.T("undo_none")) return end
    local cur = { rules = SS.CopyTable(SS.db.rules), off = SS.CopyTable(SS.db.off) }
    SS.ApplyRules(b.rules, b.off)
    SS.db.backup = cur
    SS.Print(SS.T("undo_done"))
end

-- ---------------------------------------------------------------- events (own frame : no change to the main event frame)
SS.specFrame = CreateFrame("Frame")
SS.specFrame:RegisterEvent("PLAYER_LOGIN")
SS.specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
SS.specFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
SS.specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
SS.specFrame:SetScript("OnEvent", function()
    if not SS.db then return end
    if event == "PLAYER_REGEN_ENABLED" and not SS.specPending then return end
    local ok, err = pcall(SS.SpecCheck)
    if not ok then SS.lastError = "spec: " .. tostring(err) end
end)
