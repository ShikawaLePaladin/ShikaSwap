-- ShikaSwap_Share.lua : export / import of the rules as ONE line of text, and the full reset to defaults.
-- Text format (v1), one line, never contains the pipe character (the 1.12 EditBox doubles '|') :
--     SSW1;+Spell=Relic A,Relic B;-Other Spell=Relic C;~<checksum>
--   '+' = rule on, '-' = rule switched off ; the checksum (decimal) covers everything before ";~".
-- Import is strict and atomic : any problem rejects the whole text, the saved rules are touched only after the text passed every check.
-- Nothing here can raise on corrupt input (the parser runs under pcall and every failure is a plain error code).
-- Lua 5.0 : no '#', no string.match, no '...'.

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
local string_find = string.find
local string_gsub = string.gsub
local string_sub = string.sub
local string_lower = string.lower
local getn = table.getn
local tinsert = table.insert

SS.SHARE_MAX_LEN = 6000
SS.SHARE_MAX_RULES = 120
SS.SHARE_MAX_RELICS = 4
SS.SHARE_MAX_NAME = 60

local EN = SS.M.en
local FR = SS.M.fr
EN.share_exported = "Export ready (%s rules). Copy the line below."
FR.share_exported = "Export prêt (%s règles). Copie la ligne ci-dessous."
EN.share_imported = "Import done: %s rules replaced your previous rules (undo with /ssw undo)."
FR.share_imported = "Import terminé : %s règles remplacent les anciennes (annule avec /ssw undo)."
EN.share_ok = "Valid text: %s rules."
FR.share_ok = "Texte valide : %s règles."
EN.share_err_empty = "Nothing to import (empty text)."
FR.share_err_empty = "Rien à importer (texte vide)."
EN.share_err_long = "Text too long."
FR.share_err_long = "Texte trop long."
EN.share_err_chars = "Forbidden character in the text (copy the whole line again, without '|')."
FR.share_err_chars = "Caractère interdit dans le texte (recopie toute la ligne, sans '|')."
EN.share_err_format = "Not a ShikaSwap export (bad format)."
FR.share_err_format = "Ce n'est pas un export ShikaSwap (format incorrect)."
EN.share_err_version = "This export comes from a newer or unknown format version."
FR.share_err_version = "Cet export vient d'une version de format plus récente ou inconnue."
EN.share_err_check = "The text is damaged or incomplete (checksum mismatch)."
FR.share_err_check = "Le texte est abîmé ou incomplet (somme de contrôle incorrecte)."
EN.share_err_relic = "Unknown relic in the text: %s"
FR.share_err_relic = "Relique inconnue dans le texte : %s"
EN.share_err_spell = "Invalid spell name in the text: %s"
FR.share_err_spell = "Nom de sort invalide dans le texte : %s"
EN.share_err_dup = "Spell listed twice: %s"
FR.share_err_dup = "Sort présent deux fois : %s"
EN.share_err_count = "Too many rules or relics in the text."
FR.share_err_count = "Trop de règles ou de reliques dans le texte."
EN.share_err_none = "The text contains no rule."
FR.share_err_none = "Le texte ne contient aucune règle."
EN.defaults_done = "Settings and rules reset to defaults (profiles kept; undo the rules with /ssw undo)."
FR.defaults_done = "Réglages et règles remis par défaut (profils conservés ; annule les règles avec /ssw undo)."
EN.defaults_confirm = "This resets all rules and settings. Type /ssw defaults confirm to do it."
FR.defaults_confirm = "Ceci remet à zéro toutes les règles et réglages. Tape /ssw defaults confirm pour le faire."

local function Trim(s)
    return (string_gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function Checksum(body)
    local sum = 7
    for i = 1, string.len(body) do
        sum = math.mod(sum * 31 + string.byte(body, i), 1000003)
    end
    return sum
end
SS.ShareChecksum = Checksum

-- ---------------------------------------------------------------- export
function SS.ExportText()
    local keys = SS.SortedKeys(SS.db.rules)
    local parts = { "SSW1" }
    local n = 0
    for i = 1, getn(keys) do
        local k = keys[i]
        local l = SS.db.rules[k]
        -- only what the importer would accept
        if string.len(k) <= SS.SHARE_MAX_NAME and not string_find(k, "[%c;=|~,]") and getn(l) <= SS.SHARE_MAX_RELICS then
            tinsert(parts, (SS.db.off[k] and "-" or "+") .. k .. "=" .. table.concat(l, ","))
            n = n + 1
        end
    end
    local body = table.concat(parts, ";")
    return body .. ";~" .. Checksum(body), n
end

-- ---------------------------------------------------------------- import (parse, never raises)
-- returns true, rules, off, count   |   false, errorKey, argument
local function ParseRaw(text)
    if type(text) ~= "string" then return false, "share_err_empty" end
    if string_find(text, "|", 1, true) then return false, "share_err_chars" end
    text = Trim(string_gsub(text, "%c", ""))
    if text == "" then return false, "share_err_empty" end
    if string.len(text) > SS.SHARE_MAX_LEN then return false, "share_err_long" end
    if string_find(text, ";;", 1, true) then return false, "share_err_format" end
    local cut = nil
    local from = 1
    while true do                                   -- last ";~"
        local a = string_find(text, ";~", from, true)
        if not a then break end
        cut = a
        from = a + 1
    end
    if not cut then
        if string_find(text, "^SSW") then return false, "share_err_check" end
        return false, "share_err_format"
    end
    local body = string_sub(text, 1, cut - 1)
    local chk = string_sub(text, cut + 2)
    local head = body
    local semi = string_find(body, ";", 1, true)
    if semi then head = string_sub(body, 1, semi - 1) end
    if head ~= "SSW1" then
        if string_find(head, "^SSW%d+$") then return false, "share_err_version" end
        return false, "share_err_format"
    end
    if not string_find(chk, "^%d+$") or string.len(chk) > 9 or tonumber(chk) ~= Checksum(body) then return false, "share_err_check" end
    local rules, off, seen = {}, {}, {}
    local cls = SS.PlayerClass()
    local n = 0
    local first = true
    for tok in string.gfind(body, "[^;]+") do
        if first then
            first = false
        else
            local _, _, flag, spell, rest = string_find(tok, "^([+-])([^=]+)=(.+)$")
            if not flag then return false, "share_err_format" end
            spell = Trim(spell)
            if spell == "" or string.len(spell) > SS.SHARE_MAX_NAME or string_find(spell, "[%c;=|~,]") then return false, "share_err_spell", spell end
            local ls = string_lower(spell)
            if seen[ls] then return false, "share_err_dup", spell end
            seen[ls] = true
            local list, dedupe = {}, {}
            for r in string.gfind(rest, "[^,]+") do
                local canon = SS.CanonRelic(Trim(r))
                local info = canon and SS.Relics()[canon]
                if not info or (cls and info.class ~= cls) then return false, "share_err_relic", Trim(r) end
                if not dedupe[canon] then
                    dedupe[canon] = true
                    tinsert(list, canon)
                end
            end
            if getn(list) == 0 then return false, "share_err_format" end
            if getn(list) > SS.SHARE_MAX_RELICS then return false, "share_err_count" end
            rules[spell] = list
            if flag == "-" then off[spell] = true end
            n = n + 1
            if n > SS.SHARE_MAX_RULES then return false, "share_err_count" end
        end
    end
    if n == 0 then return false, "share_err_none" end
    return true, rules, off, n
end

function SS.ParseShare(text)
    local ok, a, b, c, d = pcall(ParseRaw, text)
    if not ok then return false, "share_err_format" end
    return a, b, c, d
end

-- validate + apply. Returns true, count | false, errorKey, argument. The saved rules change ONLY on success.
function SS.ImportText(text)
    local ok, rules, off, n = SS.ParseShare(text)
    if not ok then return false, rules, off end
    SS.Backup()
    SS.ApplyRules(rules, off)
    return true, n
end

function SS.ShareErrorText(key, arg)
    if arg ~= nil then return SS.T(key, arg) end
    return SS.T(key)
end

-- ---------------------------------------------------------------- reset
function SS.ResetSettings()
    local db = SS.db
    SS.Backup()
    db.rules = {}
    db.off = {}
    db.combat = "auto"
    db.learned = nil
    db.fallbacks = true
    db.opener = nil
    db.lang = "auto"
    db.debug = false
    db.trace = false
    db.enabled = true
    db.autoSpec = false
    db.offGcd = "swap"
    db.specManual = nil
    db.lastSpec = nil
    local sub = SS.SubDefaults()
    db.minimap = sub.minimap
    db.indicator = sub.indicator
    db.alert = sub.alert
    db.ui = sub.ui
    SS.MigrateDB(db)
    SS.RebuildIndex()
    if SS.ApplyDisplay then pcall(SS.ApplyDisplay) end
end

-- ---------------------------------------------------------------- commands
local C = SS.cmds

function C.export()
    local text, n = SS.ExportText()
    SS.Print(SS.T("share_exported", n))
    SS.Print(text)
end

function C.importtext(rest)
    local ok, a, b = SS.ImportText(rest)
    if ok then SS.Print(SS.T("share_imported", a)) else SS.Print("|cFFFF6666" .. SS.ShareErrorText(a, b) .. "|r") end
end

function C.defaults(rest)
    if string_lower(Trim(rest)) ~= "confirm" then SS.Print(SS.T("defaults_confirm")) return end
    SS.ResetSettings()
    SS.Print(SS.T("defaults_done"))
end
