-- ShikaSwap_Cmd.lua : slash commands (/shikaswap, /ssw), EN+FR texts, status/debug, profiles, read-only import of LibramSwap settings.
-- Lua 5.0 : no '...', no string.match, no '#'.

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
local string_find = string.find
local string_lower = string.lower
local string_gsub = string.gsub
local string_format = string.format
local tinsert = table.insert
local getn = table.getn

-- ---------------------------------------------------------------- texts (EN / FR)
local EN = SS.M.en
local FR = SS.M.fr

EN.loaded = "v%s loaded. Type /shikaswap help."
FR.loaded = "v%s chargé. Tape /shikaswap help."
EN.conflict = "Old LibramSwap addon detected: ShikaSwap stays DORMANT (no double swaps). Use /shikaswap import, then disable LibramSwap and /reload."
FR.conflict = "Ancien addon LibramSwap détecté : ShikaSwap reste en VEILLE (pas de double échange). Fais /shikaswap import, puis désactive LibramSwap et /reload."
EN.learned_wait = "Burst cast was refused twice: switching to 'wait' mode automatically (change with /shikaswap mode)."
FR.learned_wait = "Le cast en rafale a été refusé 2 fois : passage automatique en mode 'wait' (change avec /shikaswap mode)."
EN.help = {
    "|cFFFFFF00ShikaSwap|r : swaps the relic (libram/idol/totem) before the spell that needs it.",
    "/shikaswap (or /ssw alone) or /ssw menu: opens the configuration window   |   status | list | check | bags | suggest | auto",
    "/shikaswap set <spell> = <relic>[, <relic2>]   (first available relic wins)   |   clear <spell>",
    "/shikaswap disable <spell> | enable <spell>   |   on | off (whole addon)",
    "/shikaswap mode auto|burst|wait|skip   (in-combat behaviour, see README)",
    "/shikaswap next <spell>   (macro: swap now for that spell)   |   opener <spell|off>",
    "/shikaswap profile list|save|load|del <name>   |   import [force]",
    "/shikaswap debug on|off   |   trace on|off   |   log   |   probe   |   reset   |   lang en|fr|auto",
    "/shikaswap spec [save|load holy|prot|ret|necro | necro capture|clear|tol <n>|reset | reset <spec> | auto on|off | manual holy|prot|ret|necro|off]   |   undo   |   export   |   importtext <text>   |   defaults confirm",
    "/shikaswap minimap [on|off|reset]   |   indicator on|off|lock|unlock|scale <n>|reset   |   alert chat|sound on|off | test",
}
FR.help = {
    "|cFFFFFF00ShikaSwap|r : change la relique (libram/idole/totem) avant le sort qui en a besoin.",
    "/shikaswap (ou /ssw seul) ou /ssw menu : ouvre la fenêtre de configuration   |   status | list | check | bags | suggest | auto",
    "/shikaswap set <sort> = <relique>[, <relique2>]   (la 1re disponible gagne)   |   clear <sort>",
    "/shikaswap disable <sort> | enable <sort>   |   on | off (tout l'addon)",
    "/shikaswap mode auto|burst|wait|skip   (comportement en combat, voir README)",
    "/shikaswap next <sort>   (macro : change maintenant pour ce sort)   |   opener <sort|off>",
    "/shikaswap profile list|save|load|del <nom>   |   import [force]",
    "/shikaswap debug on|off   |   trace on|off   |   log   |   probe   |   reset   |   lang en|fr|auto",
    "/shikaswap spec [save|load holy|prot|ret|necro | necro capture|clear|tol <n>|reset | reset <spec> | auto on|off | manual holy|prot|ret|necro|off]   |   undo   |   export   |   importtext <texte>   |   defaults confirm",
    "/shikaswap minimap [on|off|reset]   |   indicator on|off|lock|unlock|scale <n>|reset   |   alert chat|sound on|off | test",
}
EN.unknown = "Unknown command '%s'. /shikaswap help"
FR.unknown = "Commande inconnue '%s'. /shikaswap help"
EN.on = "ShikaSwap enabled."
FR.on = "ShikaSwap activé."
EN.off = "ShikaSwap disabled."
FR.off = "ShikaSwap désactivé."
EN.rule_set = "Rule saved: %s -> %s"
FR.rule_set = "Règle enregistrée : %s -> %s"
EN.rule_cleared = "Rule removed: %s"
FR.rule_cleared = "Règle supprimée : %s"
EN.rule_none = "No rule for '%s'."
FR.rule_none = "Aucune règle pour '%s'."
EN.no_rules = "No rule yet. Use /shikaswap suggest, /shikaswap auto or /shikaswap set."
FR.no_rules = "Aucune règle. Utilise /shikaswap suggest, /shikaswap auto ou /shikaswap set."
EN.usage_set = "Usage: /shikaswap set Holy Light = Libram of Radiance"
FR.usage_set = "Usage : /shikaswap set Holy Light = Libram of Radiance"
EN.warn_unknown_relic = "warning: '%s' is not in the catalogue (name must match exactly)"
FR.warn_unknown_relic = "attention : '%s' n'est pas dans le catalogue (le nom doit être exact)"
EN.warn_no_effect = "warning: %s does not improve %s according to the server data"
FR.warn_no_effect = "attention : %s n'améliore pas %s d'après les données du serveur"
EN.warn_other_class = "warning: %s is a %s relic"
FR.warn_other_class = "attention : %s est une relique de %s"
EN.mode_set = "In-combat mode: %s"
FR.mode_set = "Mode en combat : %s"
EN.mode_bad = "Mode must be auto, burst, wait or skip."
FR.mode_bad = "Le mode doit être auto, burst, wait ou skip."
EN.imported = "Imported from LibramSwap: %s rules, %s skipped, %s profiles."
FR.imported = "Importé depuis LibramSwap : %s règles, %s ignorées, %s profils."
EN.import_none = "No LibramSwap data found in memory (the old addon must be enabled for ONE session)."
FR.import_none = "Aucune donnée LibramSwap en mémoire (l'ancien addon doit être activé pendant UNE session)."
EN.import_have = "Rules already exist; use /shikaswap import force to merge (existing rules are kept unless the same spell)."
FR.import_have = "Des règles existent déjà ; /shikaswap import force pour fusionner."
EN.profile_saved = "Profile '%s' saved."
FR.profile_saved = "Profil '%s' enregistré."
EN.profile_loaded = "Profile '%s' loaded."
FR.profile_loaded = "Profil '%s' chargé."
EN.profile_deleted = "Profile '%s' deleted."
FR.profile_deleted = "Profil '%s' supprimé."
EN.profile_none = "No such profile: %s"
FR.profile_none = "Profil introuvable : %s"
EN.flag_on = "%s: on"
FR.flag_on = "%s : activé"
EN.flag_off = "%s: off"
FR.flag_off = "%s : désactivé"
EN.preswap_ok = "Swapped to %s."
FR.preswap_ok = "Échange vers %s."
EN.preswap_fail = "No swap: %s"
FR.preswap_fail = "Pas d'échange : %s"
EN.opener_set = "Opener spell: %s"
FR.opener_set = "Sort d'ouverture : %s"
EN.opener_off = "Opener disabled."
FR.opener_off = "Ouverture désactivée."
EN.reset_done = "Counters and learned mode reset."
FR.reset_done = "Compteurs et mode appris remis à zéro."
EN.check_ok = "No problem found in the rules."
FR.check_ok = "Aucun problème trouvé dans les règles."
EN.probe_combat = "probe only works out of combat."
FR.probe_combat = "probe ne fonctionne qu'hors combat."
EN.probe_none = "probe needs a relic from the catalogue in your bags that is not equipped."
FR.probe_none = "probe a besoin d'une relique du catalogue dans tes sacs, non équipée."
EN.probe_sent = "probe: equipping %s ... slot changed immediately: %s"
FR.probe_sent = "probe : équipement de %s ... slot changé immédiatement : %s"
EN.probe_done = "probe: server/client confirmation after %s ms (immediate update: %s)"
FR.probe_done = "probe : confirmation après %s ms (mise à jour immédiate : %s)"
EN.nothing = "(nothing)"
FR.nothing = "(rien)"

-- ---------------------------------------------------------------- small helpers
local function Trim(s)
    return (string_gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function SortedKeys(t)
    local k = {}
    for key in pairs(t) do tinsert(k, key) end
    table.sort(k)
    return k
end
SS.SortedKeys = SortedKeys

function SS.PlayerClass()
    if UnitClass then
        local _, token = UnitClass("player")
        return token
    end
    return nil
end

-- canonical spell name : existing rule key, then spellbook, then catalogue, else as typed
function SS.CanonSpell(typed)
    local t = Trim(typed)
    local lt = string_lower(t)
    if SS.lc and SS.lc[lt] then return SS.lc[lt] end
    local book = SS.book or SS.ScanBook()
    if book[lt] then return book[lt].name end
    for _, info in pairs(SS.Relics()) do
        for i = 1, getn(info.spells) do
            if string_lower(info.spells[i]) == lt then return info.spells[i] end
        end
    end
    return t
end

-- where is the relic ? "equipped" | "bags" | "missing"
function SS.RelicWhere(name)
    local snapLink = GetInventoryItemLink("player", SS.SLOT)
    if SS.LinkIsRelic(snapLink, name) then return "equipped" end
    if SS.FindRelic(name) then return "bags" end
    return "missing"
end

-- ---------------------------------------------------------------- import of the old LibramSwap settings (READ ONLY on the source)
-- old map : spell -> "Libram of X" | "__NONE__" | "None" | "Auto" ; old enabledMap : spell -> false means disabled
function SS.ConvertOldMap(map, enabled)
    local rules, off = {}, {}
    local n, skipped = 0, 0
    if type(map) ~= "table" then return rules, off, 0, 0 end
    for spell, relic in pairs(map) do
        if type(spell) == "string" and type(relic) == "string" and relic ~= "" and relic ~= "__NONE__"
            and string_lower(relic) ~= "none" and string_lower(relic) ~= "auto" then
            rules[spell] = { SS.CanonRelic(relic) }
            n = n + 1
            if type(enabled) == "table" and enabled[spell] == false then off[spell] = true end
        else
            skipped = skipped + 1
        end
    end
    return rules, off, n, skipped
end

function SS.ImportLibram(src, force)
    local db = SS.db
    if type(src) ~= "table" then return nil end
    local rules, off, n, skipped = SS.ConvertOldMap(src.map, src.enabledMap)
    for spell, list in pairs(rules) do
        if force or not db.rules[spell] then
            db.rules[spell] = list
            db.off[spell] = off[spell]
        end
    end
    local np = 0
    if type(src.profiles) == "table" then
        for name, p in pairs(src.profiles) do
            if type(name) == "string" and type(p) == "table" and not db.profiles[name] then
                local r, o = SS.ConvertOldMap(p.map, p.enabledMap)
                db.profiles[name] = { rules = r, off = o }
                np = np + 1
            end
        end
    end
    db.imported = true
    SS.RebuildIndex()
    return n, skipped, np
end

function SS.ImportOnFirstRun()
    local db = SS.db
    if db.imported or SS.nRules > 0 then return end
    if type(LibramSwapDB) ~= "table" then return end
    local n, skipped, np = SS.ImportLibram(LibramSwapDB, false)
    if n then SS.Print(SS.T("imported", n, skipped, np)) end
end

-- ---------------------------------------------------------------- commands
SS.cmds = {}
local C = SS.cmds

function C.help()
    local h = SS.M[SS.Lang()].help
    for i = 1, getn(h) do SS.Print(h[i]) end
    -- both languages on purpose : short help in EN and FR
    local o = (SS.Lang() == "fr") and SS.M.en.help or SS.M.fr.help
    SS.Print("---")
    for i = 1, getn(o) do SS.Print(o[i]) end
end

function C.on()
    SS.db.enabled = true
    SS.Print(SS.T("on"))
end

C["off"] = function()
    SS.db.enabled = false
    SS.QueueClear("disabled")
    SS.Print(SS.T("off"))
end

function C.list()
    local keys = SortedKeys(SS.db.rules)
    if getn(keys) == 0 then SS.Print(SS.T("no_rules")) return end
    for i = 1, getn(keys) do
        local k = keys[i]
        local l = SS.db.rules[k]
        local parts = {}
        for j = 1, getn(l) do tinsert(parts, l[j] .. " [" .. SS.RelicWhere(l[j]) .. "]") end
        local flag = SS.db.off[k] and " |cFFFF6666(off)|r" or ""
        SS.Print(k .. " -> " .. table.concat(parts, ", ") .. flag)
    end
end

-- the one place that saves a rule for /shikaswap set AND for the menu (quiet = no chat output)
function SS.SetRuleCmd(spell, list, quiet)
    if not SS.SetRule(spell, list) then return false end
    if not quiet then
        SS.Print(SS.T("rule_set", spell, table.concat(list, ", ")))
        SS.WarnRule(spell, list)
    end
    return true
end

function C.set(rest)
    local _, _, left, right = string_find(rest or "", "^(.-)%s*=%s*(.-)$")
    if not left or Trim(left) == "" or Trim(right) == "" then SS.Print(SS.T("usage_set")) return end
    local spell = SS.CanonSpell(left)
    local list = {}
    for part in string.gfind(right, "[^,]+") do
        local r = Trim(part)
        if r ~= "" then tinsert(list, SS.CanonRelic(r)) end
    end
    if getn(list) == 0 then SS.Print(SS.T("usage_set")) return end
    SS.SetRuleCmd(spell, list, false)
end

-- warnings about a rule against the server data (catalogue)
function SS.WarnRule(spell, list)
    local relics = SS.Relics()
    local cls = SS.PlayerClass()
    local ls = string_lower(spell)
    local out = 0
    for i = 1, getn(list) do
        local info = relics[list[i]]
        if not info then
            SS.Print("|cFFFFAA00" .. SS.T("warn_unknown_relic", list[i]) .. "|r")
            out = out + 1
        else
            local ok = false
            for j = 1, getn(info.spells) do
                if string_lower(info.spells[j]) == ls then ok = true end
            end
            if not ok then
                SS.Print("|cFFFFAA00" .. SS.T("warn_no_effect", list[i], spell) .. "|r")
                out = out + 1
            end
            if cls and info.class ~= cls then
                SS.Print("|cFFFFAA00" .. SS.T("warn_other_class", list[i], info.class) .. "|r")
                out = out + 1
            end
        end
    end
    return out
end

EN.warn_fervor = "warning: Judgement has an active rule (%s): the swap before Judgement removes Libram of Fervor, so the Judgement of the Crusader loses its bonus."
FR.warn_fervor = "attention : Judgement a une règle active (%s) : l'échange avant Judgement retire Libram of Fervor, le Judgement of the Crusader perd donc son bonus."
EN.hint_other = "hint: %s also improves %s (no rule for it)."
FR.hint_other = "astuce : %s améliore aussi %s (aucune règle pour ce sort)."
function C.check()
    local keys = SortedKeys(SS.db.rules)
    local n = 0
    for i = 1, getn(keys) do n = n + SS.WarnRule(keys[i], SS.db.rules[keys[i]]) end
    -- Fervor raises the Judgement of the Crusader : it must still be equipped when Judgement is cast
    local sotc = SS.lc["seal of the crusader"]
    local jud = SS.lc["judgement"]
    if sotc and jud and not SS.db.off[sotc] and not SS.db.off[jud] and SS.db.rules[sotc][1] == "Libram of Fervor" then
        SS.Print("|cFFFFAA00" .. SS.T("warn_fervor", SS.db.rules[jud][1]) .. "|r")
        n = n + 1
    end
    -- a relic that also improves a spell the player has no rule for (only relics with few spells : Hope / Veracity cover whole families)
    local relics = SS.Relics()
    for i = 1, getn(keys) do
        local k = keys[i]
        if not SS.db.off[k] then
            local info = relics[SS.db.rules[k][1]]
            if info and getn(info.spells) <= 3 then
                for j = 1, getn(info.spells) do
                    local sp = info.spells[j]
                    if string_lower(sp) ~= string_lower(k) and not SS.lc[string_lower(sp)] then
                        SS.Print("|cFF88CCFF" .. SS.T("hint_other", SS.db.rules[k][1], sp) .. "|r")
                    end
                end
            end
        end
    end
    if n == 0 then SS.Print(SS.T("check_ok")) end
end

function C.clear(rest)
    local spell = Trim(rest)
    if SS.ClearRule(spell) then
        SS.Print(SS.T("rule_cleared", spell))
    else
        SS.Print(SS.T("rule_none", spell))
    end
end

-- switch a rule on/off (shared by /shikaswap enable|disable and the menu check boxes)
function SS.SetEnabled(key, on, quiet)
    if on then SS.db.off[key] = nil else SS.db.off[key] = true end
    SS.execRule = nil   -- cache des regles execute a recalculer
    if not quiet then SS.Print(SS.T(on and "flag_on" or "flag_off", key)) end
end

function C.disable(rest)
    local key = SS.lc[string_lower(Trim(rest))]
    if not key then SS.Print(SS.T("rule_none", Trim(rest))) return end
    SS.SetEnabled(key, false, false)
end

function C.enable(rest)
    local key = SS.lc[string_lower(Trim(rest))]
    if not key then SS.Print(SS.T("rule_none", Trim(rest))) return end
    SS.SetEnabled(key, true, false)
end

function C.mode(rest)
    local m = string_lower(Trim(rest))
    if m == "auto" or m == "burst" or m == "wait" or m == "skip" then
        SS.db.combat = m
        if m == "auto" then SS.db.learned = nil end
        SS.Print(SS.T("mode_set", m))
    else
        SS.Print(SS.T("mode_bad"))
    end
end

function C.next(rest)
    local ok, info = SS.PreSwap(Trim(rest))
    if ok then SS.Print(SS.T("preswap_ok", info)) else SS.Print(SS.T("preswap_fail", tostring(info))) end
end

function C.opener(rest)
    local s = Trim(rest)
    if s == "" or string_lower(s) == "off" then
        SS.db.opener = nil
        SS.Print(SS.T("opener_off"))
        return
    end
    local spell = SS.CanonSpell(s)
    SS.db.opener = spell
    SS.Print(SS.T("opener_set", spell))
end

local function SetFlag(name, rest)
    local v = string_lower(Trim(rest))
    if v == "on" or v == "1" or v == "true" then
        SS.db[name] = true
        SS.Print(SS.T("flag_on", name))
    elseif v == "off" or v == "0" or v == "false" then
        SS.db[name] = false
        SS.Print(SS.T("flag_off", name))
    else
        SS.Print(name .. ": " .. tostring(SS.db[name]))
    end
end

function C.debug(rest) SetFlag("debug", rest) end
function C.fallbacks(rest)
    SetFlag("fallbacks", rest)
    SS.RebuildIndex()
end

EN.offgcd_set = "Off-GCD spells (Judgement) in combat: %s"
FR.offgcd_set = "Sorts sans GCD (Judgement) en combat : %s"
EN.offgcd_bad = "Usage: /shikaswap offgcd swap|skip   (skip = never swap in combat for Judgement)"
FR.offgcd_bad = "Usage : /shikaswap offgcd swap|skip   (skip = jamais d'échange en combat pour Judgement)"
function C.offgcd(rest)
    local v = string_lower(Trim(rest))
    if v == "swap" or v == "skip" then SS.db.offGcd = v end
    if v == "" or v == "swap" or v == "skip" then SS.Print(SS.T("offgcd_set", SS.db.offGcd)) else SS.Print(SS.T("offgcd_bad")) end
end

EN.execboss_set = "Execute relic (Final Judgement) on bosses only: %s"
FR.execboss_set = "Relic d'exécution (Final Judgement) seulement sur les boss : %s"
EN.execboss_bad = "Usage: /shikaswap execboss on|off   (on = only skull / world-boss targets)"
FR.execboss_bad = "Usage : /shikaswap execboss on|off   (on = seulement les cibles crâne / boss)"
function C.execboss(rest)
    local v = string_lower(Trim(rest))
    if v == "on" then SS.db.execBoss = true elseif v == "off" then SS.db.execBoss = false end
    if v == "" or v == "on" or v == "off" then SS.Print(SS.T("execboss_set", SS.db.execBoss and "on" or "off")) else SS.Print(SS.T("execboss_bad")) end
end

function C.lang(rest)
    local v = string_lower(Trim(rest))
    if v == "en" or v == "fr" or v == "auto" then SS.db.lang = v end
    SS.Print("lang: " .. SS.db.lang)
end

function C.log()
    local n = SS.ringN
    local total = getn(SS.ring)
    if total == 0 then SS.Print(SS.T("nothing")) return end
    -- oldest first
    local start = (total >= SS.RING_MAX) and (n + 1) or 1
    if start > SS.RING_MAX then start = 1 end
    for i = 1, total do
        local idx = start + i - 1
        if idx > SS.RING_MAX then idx = idx - SS.RING_MAX end
        if SS.ring[idx] then SS.Print(SS.ring[idx]) end
    end
end

function C.reset()
    SS.stats = {}
    SS.db.counts = {}
    SS.ring = {}
    SS.ringN = 0
    SS.db.learned = nil
    SS.consecFail = 0
    SS.probe = nil
    SS.Print(SS.T("reset_done"))
end

function C.bags()
    local relics = SS.Relics()
    local names = SortedKeys(relics)
    local any = false
    for i = 1, getn(names) do
        local w = SS.RelicWhere(names[i])
        if w ~= "missing" then
            any = true
            local info = relics[names[i]]
            SS.Print(names[i] .. " [" .. w .. "] -> " .. table.concat(info.spells, ", "))
        end
    end
    if not any then SS.Print(SS.T("nothing")) end
end

-- per spell : the relics you own that improve it (for your class)
function SS.Suggestions()
    local cls = SS.PlayerClass()
    local bySpell = {}
    for name, info in pairs(SS.Relics()) do
        if not cls or info.class == cls then
            if SS.RelicWhere(name) ~= "missing" then
                for i = 1, getn(info.spells) do
                    local sp = info.spells[i]
                    if not bySpell[sp] then bySpell[sp] = {} end
                    tinsert(bySpell[sp], name)
                end
            end
        end
    end
    for _, l in pairs(bySpell) do table.sort(l) end
    return bySpell
end

function C.suggest()
    local bySpell = SS.Suggestions()
    local keys = SortedKeys(bySpell)
    if getn(keys) == 0 then SS.Print(SS.T("nothing")) return end
    for i = 1, getn(keys) do
        local cur = SS.lc[string_lower(keys[i])]
        local mark = cur and " |cFF88FF88(rule)|r" or ""
        SS.Print(keys[i] .. ": " .. table.concat(bySpell[keys[i]], ", ") .. mark)
    end
end

-- auto : conservative. A spell is only auto-assigned when ALL the relics you own for it have at most 2 spells and no "sticky" flag,
-- and there is one clear choice (a single relic, or an equivalence group such as Light > Divinity)
function C.auto()
    local bySpell = SS.Suggestions()
    local relics = SS.Relics()
    local keys = SortedKeys(bySpell)
    local done = 0
    for i = 1, getn(keys) do
        local sp = keys[i]
        if not SS.lc[string_lower(sp)] then
            -- every owned relic for this spell must be "simple" : a persistent or wide-category relic means a real choice for the player
            local cands = {}
            local simple = true
            for j = 1, getn(bySpell[sp]) do
                local info = relics[bySpell[sp][j]]
                if not info.sticky and getn(info.spells) <= 2 then tinsert(cands, bySpell[sp][j]) else simple = false end
            end
            if not simple then cands = {} end
            local pick
            if getn(cands) == 1 then
                pick = { cands[1] }
            elseif getn(cands) > 1 then
                -- several: only if they are all in the same equivalence group (ordered by value)
                local g = relics[cands[1]].eq
                local same = g ~= nil
                for j = 2, getn(cands) do
                    if relics[cands[j]].eq ~= g then same = false end
                end
                if same then
                    table.sort(cands, function(a, b) return relics[a].v > relics[b].v end)
                    pick = { cands[1] }
                end
            end
            if pick then
                SS.SetRule(sp, pick)
                SS.Print(SS.T("rule_set", sp, pick[1]))
                done = done + 1
            end
        end
    end
    if done == 0 then SS.Print(SS.T("nothing")) end
end

function C.import(rest)
    local force = string_lower(Trim(rest)) == "force"
    if type(LibramSwapDB) ~= "table" then SS.Print(SS.T("import_none")) return end
    if SS.nRules > 0 and not force then SS.Print(SS.T("import_have")) return end
    local n, skipped, np = SS.ImportLibram(LibramSwapDB, force)
    SS.Print(SS.T("imported", n, skipped, np))
end

function C.profile(rest)
    local _, _, sub, name = string_find(rest or "", "^(%S*)%s*(.-)$")
    sub = string_lower(sub or "")
    name = Trim(name)
    local p = SS.db.profiles
    if sub == "list" or sub == "" then
        local keys = SortedKeys(p)
        if getn(keys) == 0 then SS.Print(SS.T("nothing")) end
        for i = 1, getn(keys) do SS.Print(keys[i]) end
    elseif sub == "save" and name ~= "" then
        p[name] = { rules = SS.CopyTable(SS.db.rules), off = SS.CopyTable(SS.db.off) }
        SS.Print(SS.T("profile_saved", name))
    elseif sub == "load" and name ~= "" then
        if not p[name] then SS.Print(SS.T("profile_none", name)) return end
        SS.Backup()
        SS.ApplyRules(p[name].rules, p[name].off)
        SS.Print(SS.T("profile_loaded", name))
    elseif (sub == "del" or sub == "delete") and name ~= "" then
        if not p[name] then SS.Print(SS.T("profile_none", name)) return end
        p[name] = nil
        SS.Print(SS.T("profile_deleted", name))
    else
        SS.Print(SS.T("unknown", "profile " .. sub))
    end
end

-- probe : measures, out of combat, whether the client updates slot 18 synchronously after UseContainerItem
-- and how long the server confirmation takes (this decides how reliable the "same frame" burst can be)
function C.probe()
    if SS.InCombat() then SS.Print(SS.T("probe_combat")) return end
    local cur = GetInventoryItemLink("player", SS.SLOT)
    local pick
    for name in pairs(SS.Relics()) do
        if not pick and not SS.LinkIsRelic(cur, name) and SS.FindRelic(name) then pick = name end
    end
    if not pick then SS.Print(SS.T("probe_none")) return end
    local bag, slot = SS.FindRelic(pick)
    local before = SS.ItemIdFromLink(cur)
    UseContainerItem(bag, slot)
    local after = SS.ItemIdFromLink(GetInventoryItemLink("player", SS.SLOT))
    SS.probeEquip = { at = GetTime(), name = pick, sync = (after ~= before) }
    SS.bagDirty = true
    SS.Print(SS.T("probe_sent", pick, SS.probeEquip.sync and "YES" or "no"))
end

function SS.FinishProbe()
    local p = SS.probeEquip
    SS.probeEquip = nil
    SS.Print(SS.T("probe_done", string.format("%.0f", (GetTime() - p.at) * 1000), p.sync and "YES" or "no"))
end

function C.status()
    local db = SS.db
    local s = SS.stats
    local mode = SS.EffectiveMode()
    SS.Print("v" .. SS.version .. "  " .. (db.enabled and "ON" or "OFF") .. (SS.conflict and "  |cFFFF6666DORMANT (LibramSwap detected)|r" or ""))
    SS.Print("combat mode: " .. db.combat .. " (effective: " .. mode .. ")" .. (db.learned and (" learned=" .. db.learned) or ""))
    local link = GetInventoryItemLink("player", SS.SLOT)
    SS.Print("slot " .. SS.SLOT .. ": " .. tostring(SS.ItemNameFromLink(link)) .. "   rules: " .. tostring(SS.nRules) .. "   fallbacks: " .. tostring(db.fallbacks))
    local hooks = {}
    if SS.orig then
        if CastSpellByName ~= SS.orig.CastSpellByName then tinsert(hooks, "CastSpellByName") end
        if CastSpell ~= SS.orig.CastSpell then tinsert(hooks, "CastSpell") end
        if UseAction ~= SS.orig.UseAction then tinsert(hooks, "UseAction") end
    end
    SS.Print("hooks: " .. (getn(hooks) > 0 and table.concat(hooks, ", ") or "NONE (overwritten by another addon?)"))
    local ext = {}
    if type(SUPERWOW_VERSION) ~= "nil" then tinsert(ext, "SuperWoW " .. tostring(SUPERWOW_VERSION)) end
    if type(GetNampowerVersion) == "function" then tinsert(ext, "Nampower") end
    if type(UnitXP) == "function" then tinsert(ext, "UnitXP") end
    SS.Print("extensions: " .. (getn(ext) > 0 and table.concat(ext, ", ") or "none detected") .. "   opener: " .. tostring(db.opener))
    SS.Print(string_format("swaps free=%d combat=%d | burst sent=%d refused=%d | queued=%d cast=%d timeout=%d | swallowed=%d swapErrors=%d errors=%d",
        s.swapsFree or 0, s.swapsCombat or 0, s.burstSent or 0, s.burstFail or 0,
        s.queued or 0, s.queueCasts or 0, s.queueTimeouts or 0, s.pressSwallowed or 0, s.swapErrors or 0, s.errors or 0))
    local passes = {}
    for k, v in pairs(s) do
        if string_find(k, "^pass: ") then tinsert(passes, string.sub(k, 7) .. "=" .. v) end
    end
    table.sort(passes)
    if getn(passes) > 0 then SS.Print("no swap because: " .. table.concat(passes, ", ")) end
    if SS.lastError then SS.Print("last internal error: " .. SS.lastError) end
end

function SS.Command(msg)
    local _, _, cmd, rest = string_find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string_lower(cmd or "")
    if not SS.db then SS.InitDB() end
    if cmd == "" then cmd = C.menu and "menu" or "status" end   -- bare /ssw opens the menu (ShikaSwap_UI.lua)
    local f = C[cmd]
    if f then f(rest) else SS.Print(SS.T("unknown", cmd)) end
    -- keep an open menu in sync with what the command just changed
    if SS.UI and SS.UI.Refresh and cmd ~= "menu" then pcall(SS.UI.Refresh) end
end

SLASH_SHIKASWAP1 = "/shikaswap"
SLASH_SHIKASWAP2 = "/ssw"
SlashCmdList["SHIKASWAP"] = function(msg) SS.Command(msg) end
