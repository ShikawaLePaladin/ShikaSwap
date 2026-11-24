-- ShikaSwap_UI.lua : the configuration window (/ssw, /ssw menu). Dark and gold theme (base 1.12 textures only), a profile bar that is always visible,
-- then five tabs : Rules / Settings & display / Profiles / Import-Export / Diagnostic.
-- WoW 1.12 / Lua 5.0 : no '#', no string.match, no '...', handlers read the globals `this` / `arg1` (they receive NO arguments).
-- RULES OF THIS FILE
--   * nothing is created at file load (no frame, no SavedVariables access) : the window is built the first time it is opened,
--     inside a pcall, so a UI problem can never stop a swap or a cast ;
--   * every action calls the SAME functions as the slash commands (SS.SetRuleCmd, SS.SetEnabled, SS.ClearRule, SS.cmds.*, SS.ImportText ...) :
--     no duplicated logic ;
--   * the window is redrawn from the saved data after every change (UI.Refresh), never from its own copy ;
--   * the rule editor is validated for the Paladin (catalogue spells of the class). Other classes keep the commands (/ssw set ...).

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap
SS.UI = SS.UI or {}
local UI = SS.UI

local string_lower = string.lower
local string_format = string.format
local getn = table.getn
local tinsert = table.insert

UI.ROWS = 10           -- spell rows per page
UI.ROW_H = 26
UI.WIDTH = 840
UI.HEIGHT = 530
UI.PANEL_Y = -34       -- the tab panels sit below the profile bar
UI.GOLD = { 1, 0.82, 0 }
UI.PINK = { 0.96, 0.55, 0.73 }
UI.Q_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
UI.TOP = 98            -- y of the first content row
UI.page = 1
UI.profIdx = 1
UI.tab = 1
UI.TABS = { "rules", "settings", "profiles", "share", "diag" }
UI.DIAG_LINES = 15
UI.CONFIRM_SECONDS = 5

-- ---------------------------------------------------------------- texts (EN / FR)
local EN = SS.M.en
local FR = SS.M.fr
EN.ui_title = "ShikaSwap"
FR.ui_title = "ShikaSwap"
EN.ui_version = "v%s"
FR.ui_version = "v%s"
EN.ui_bar_label = "Profile:"
FR.ui_bar_label = "Profil :"
EN.ui_t_bar_HOLY = "Load your saved Holy rules (one click). The lit button is the profile in use. Dimmed = nothing saved yet."
FR.ui_t_bar_HOLY = "Charge tes règles Sacré enregistrées (un clic). Le bouton allumé est le profil en cours. Grisé = rien d'enregistré."
EN.ui_t_bar_PROT = "Load your saved Protection rules (one click). The lit button is the profile in use. Dimmed = nothing saved yet."
FR.ui_t_bar_PROT = "Charge tes règles Protection enregistrées (un clic). Le bouton allumé est le profil en cours. Grisé = rien d'enregistré."
EN.ui_t_bar_RET = "Load your saved Retribution rules (one click). The lit button is the profile in use. Dimmed = nothing saved yet."
FR.ui_t_bar_RET = "Charge tes règles Vindicte enregistrées (un clic). Le bouton allumé est le profil en cours. Grisé = rien d'enregistré."
EN.ui_t_bar_NECRO = "Load the Necroladin rules (preset taken from your old LibramSwap profile, editable). Chosen automatically only after you record your talent signature (Profiles tab)."
FR.ui_t_bar_NECRO = "Charge les règles Necroladin (préréglage repris de ton ancien profil LibramSwap, modifiable). Choisi automatiquement seulement après avoir enregistré ta signature de talents (onglet Profils)."
EN.ui_p_preset = "preset"
FR.ui_p_preset = "préréglage"
EN.ui_p_modified = "edited"
FR.ui_p_modified = "modifié"
EN.ui_p_reset = "Back to preset"
FR.ui_p_reset = "Retour préréglage"
EN.ui_t_reset_slot = "Put the Necroladin slot back to its preset (asks for a second click). Your rules in use are not touched."
FR.ui_t_reset_slot = "Remet l'emplacement Necroladin au préréglage (demande un second clic). Tes règles en cours ne sont pas touchées."
EN.ui_nc_capture = "Save my current talents as Necroladin"
FR.ui_nc_capture = "Enregistrer mes talents actuels comme Necroladin"
EN.ui_t_nc_capture = "Remembers how many points you have in each tree (Holy / Protection / Retribution). Later, a talent distribution close to it is recognised as Necroladin (same as /ssw spec necro capture)."
FR.ui_t_nc_capture = "Mémorise tes points dans chaque arbre (Sacré / Protection / Vindicte). Ensuite, une répartition proche est reconnue comme Necroladin (comme /ssw spec necro capture)."
EN.ui_nc_clear = "Forget the signature"
FR.ui_nc_clear = "Oublier la signature"
EN.ui_t_nc_clear = "Necroladin becomes manual-only again (same as /ssw spec necro clear)."
FR.ui_t_nc_clear = "Necroladin redevient manuel uniquement (comme /ssw spec necro clear)."
EN.ui_nc_tol = "Tolerance +/-%s"
FR.ui_nc_tol = "Tolérance +/-%s"
EN.ui_t_nc_tol = "How many points per tree your talents may differ from the recorded signature and still count as Necroladin (0 to 10, default 2)."
FR.ui_t_nc_tol = "De combien de points par arbre tes talents peuvent s'écarter de la signature enregistrée et compter quand même comme Necroladin (0 à 10, défaut 2)."
EN.ui_tab_rules = "Rules"
FR.ui_tab_rules = "Règles"
EN.ui_tab_settings = "Settings & display"
FR.ui_tab_settings = "Réglages & affichage"
EN.ui_tab_profiles = "Profiles"
FR.ui_tab_profiles = "Profils"
EN.ui_tab_share = "Import / Export"
FR.ui_tab_share = "Import / Export"
EN.ui_tab_diag = "Diagnostic"
FR.ui_tab_diag = "Diagnostic"
EN.ui_h_spell = "Spell"
FR.ui_h_spell = "Sort"
EN.ui_h_r1 = "Relic 1 (first choice)"
FR.ui_h_r1 = "Relique 1 (prioritaire)"
EN.ui_h_r2 = "Relic 2 (if the first is missing)"
FR.ui_h_r2 = "Relique 2 (si la 1re manque)"
EN.ui_none = "(none)"
FR.ui_none = "(aucune)"
EN.ui_eq = "equipped"
FR.ui_eq = "équipée"
EN.ui_bags = "in bags"
FR.ui_bags = "sacs"
EN.ui_miss = "missing"
FR.ui_miss = "absente"
EN.ui_mode = "Combat mode: %s"
FR.ui_mode = "Mode en combat : %s"
EN.ui_import = "Import LibramSwap"
FR.ui_import = "Importer LibramSwap"
EN.ui_auto = "Suggest auto"
FR.ui_auto = "Suggérer auto"
EN.ui_view_known = "Spells: known"
FR.ui_view_known = "Sorts : connus"
EN.ui_view_all = "Spells: all"
FR.ui_view_all = "Sorts : tous"
EN.ui_page = "Page %s/%s"
FR.ui_page = "Page %s/%s"
EN.ui_line = "Equipped: %s   |   mode %s (effective: %s)   |   rules: %s"
FR.ui_line = "Équipée : %s   |   mode %s (effectif : %s)   |   règles : %s"
EN.ui_dormant = "DORMANT: LibramSwap is still loaded"
FR.ui_dormant = "EN VEILLE : LibramSwap est encore chargé"
EN.ui_empty = "No spell to show. Click 'Spells: known' to list every spell of the catalogue."
FR.ui_empty = "Aucun sort à afficher. Clique sur « Sorts : connus » pour lister tout le catalogue."
EN.ui_class_note = "The rule editor is validated for Paladins only. For your class use the commands: /ssw set <spell> = <relic>, /ssw help. The other tabs work for every class."
FR.ui_class_note = "L'éditeur de règles est validé pour le Paladin uniquement. Pour ta classe, utilise les commandes : /ssw set <sort> = <relique>, /ssw help. Les autres onglets fonctionnent pour toutes les classes."
EN.ui_error = "menu error (your spells are not affected): %s"
FR.ui_error = "erreur du menu (tes sorts ne sont pas touchés) : %s"
EN.ui_confirm = "Click again to confirm"
FR.ui_confirm = "Clique encore pour confirmer"
-- settings tab
EN.ui_c_enabled = "ShikaSwap enabled"
FR.ui_c_enabled = "ShikaSwap activé"
EN.ui_c_fallbacks = "Use an equivalent lower relic if the best one is missing"
FR.ui_c_fallbacks = "Utiliser une relique équivalente moins bonne si la meilleure manque"
EN.ui_c_minimap = "Show the minimap button"
FR.ui_c_minimap = "Afficher le bouton de la minimap"
EN.ui_c_indicator = "Show the floating relic indicator"
FR.ui_c_indicator = "Afficher l'indicateur flottant de relique"
EN.ui_c_locked = "Lock the indicator (cannot be dragged)"
FR.ui_c_locked = "Verrouiller l'indicateur (non déplaçable)"
EN.ui_c_alertchat = "Missing relic alert in the chat"
FR.ui_c_alertchat = "Alerte relique manquante dans le chat"
EN.ui_c_alertsound = "Missing relic alert: also play a sound"
FR.ui_c_alertsound = "Alerte relique manquante : jouer aussi un son"
EN.ui_c_autospec = "Switch rules automatically when the talent spec changes"
FR.ui_c_autospec = "Changer les règles automatiquement quand la spécialité change"
EN.ui_lang = "Language: %s"
FR.ui_lang = "Langue : %s"
EN.ui_opener = "Opener relic: %s"
FR.ui_opener = "Relique d'ouverture : %s"
EN.ui_scale = "Indicator size:"
FR.ui_scale = "Taille de l'indicateur :"
EN.ui_reset = "Reset everything to defaults"
FR.ui_reset = "Tout réinitialiser (valeurs par défaut)"
EN.ui_modes_help = "Combat modes:\n  auto = swap and cast in the same instant, and switches to 'wait' by itself if the game refuses (recommended)\n  burst = swap and cast in the same instant\n  wait = swap first, the spell leaves when the 1.5 s swap cooldown is over\n  skip = never swap in combat (only out of combat)"
FR.ui_modes_help = "Modes en combat :\n  auto = échange et sort au même instant, et passe seul sur 'wait' si le jeu refuse (conseillé)\n  burst = échange et sort au même instant\n  wait = échange d'abord, le sort part à la fin de la recharge d'échange de 1,5 s\n  skip = jamais d'échange en combat (seulement hors combat)"
-- profiles tab
EN.ui_p_specs = "Rules per specialisation"
FR.ui_p_specs = "Règles par spécialité"
EN.ui_p_named = "Named profiles"
FR.ui_p_named = "Profils nommés"
EN.ui_p_detected = "Detected spec: %s (%s)"
FR.ui_p_detected = "Spécialité détectée : %s (%s)"
EN.ui_p_saved = "saved"
FR.ui_p_saved = "enregistré"
EN.ui_p_empty = "empty"
FR.ui_p_empty = "vide"
EN.ui_p_current = "<< in use"
FR.ui_p_current = "<< en cours"
EN.ui_p_load = "Load"
FR.ui_p_load = "Charger"
EN.ui_p_save = "Save"
FR.ui_p_save = "Sauver"
EN.ui_p_del = "Delete"
FR.ui_p_del = "Supprimer"
EN.ui_p_manual = "Fallback spec: %s"
FR.ui_p_manual = "Spécialité de secours : %s"
EN.ui_p_nospec = "Per-spec profiles are available for Paladins. Named profiles below work for every class."
FR.ui_p_nospec = "Les profils par spécialité sont disponibles pour le Paladin. Les profils nommés ci-dessous marchent pour toutes les classes."
EN.ui_p_name = "Name of the profile to save (empty = overwrite the selected one):"
FR.ui_p_name = "Nom du profil à enregistrer (vide = écrase le profil choisi) :"
EN.ui_p_noname = "Type a profile name first."
FR.ui_p_noname = "Tape d'abord un nom de profil."
-- share tab
EN.ui_s_help = "EXPORT writes your rules as one line of text: copy it (Ctrl+A then Ctrl+C) and send it to a friend. IMPORT: paste a line here (Ctrl+V) and click Import: it REPLACES your rules (UNDO brings them back). A damaged or foreign text is refused and changes nothing."
FR.ui_s_help = "EXPORTER écrit tes règles sur une seule ligne de texte : copie-la (Ctrl+A puis Ctrl+C) et envoie-la à un ami. IMPORTER : colle une ligne ici (Ctrl+V) puis clique Importer : elle REMPLACE tes règles (ANNULER les ramène). Un texte abîmé ou étranger est refusé et ne change rien."
EN.ui_s_export = "Export my rules"
FR.ui_s_export = "Exporter mes règles"
EN.ui_s_import = "Import (replaces my rules)"
FR.ui_s_import = "Importer (remplace mes règles)"
EN.ui_s_undo = "Undo last bulk change"
FR.ui_s_undo = "Annuler le dernier changement"
EN.ui_s_clear = "Clear box"
FR.ui_s_clear = "Vider"
EN.ui_s_done = "Export ready (%s rules). Select the text and copy it."
FR.ui_s_done = "Export prêt (%s règles). Sélectionne le texte et copie-le."
-- diagnostic tab
EN.ui_d_status = "Status"
FR.ui_d_status = "Statut"
EN.ui_d_log = "Decision log"
FR.ui_d_log = "Journal"
EN.ui_d_check = "Check rules"
FR.ui_d_check = "Vérifier les règles"
EN.ui_d_clear = "Clear view"
FR.ui_d_clear = "Effacer"
EN.ui_d_trace = "Recording: %s"
FR.ui_d_trace = "Enregistrement : %s"
EN.ui_d_debug = "Live debug: %s"
FR.ui_d_debug = "Debug en direct : %s"
EN.ui_d_hint = "The result of /ssw status, /ssw log and /ssw check is shown here. Turn recording on, play a fight, then click Decision log."
FR.ui_d_hint = "Le résultat de /ssw status, /ssw log et /ssw check s'affiche ici. Active l'enregistrement, fais un combat, puis clique Journal."
-- tooltips
EN.ui_t_check = "Rule on/off for this spell (needs a relic first)."
FR.ui_t_check = "Règle active / coupée pour ce sort (choisis d'abord une relique)."
EN.ui_t_label = "Left click: next relic. Right click: previous. Only relics that improve this spell are listed."
FR.ui_t_label = "Clic gauche : relique suivante. Clic droit : précédente. Seules les reliques qui améliorent ce sort sont listées."
EN.ui_t_prev = "Previous"
FR.ui_t_prev = "Précédent"
EN.ui_t_next = "Next"
FR.ui_t_next = "Suivant"
EN.ui_t_mode = "In-combat behaviour: auto, burst, wait, skip (same as /ssw mode). Click to change."
FR.ui_t_mode = "Comportement en combat : auto, burst, wait, skip (comme /ssw mode). Clique pour changer."
EN.ui_t_import = "Read the old LibramSwap settings (same as /ssw import). Shift+click = merge over existing rules (import force)."
FR.ui_t_import = "Lit les réglages de l'ancien LibramSwap (comme /ssw import). Maj+clic = fusionner sur les règles existantes (import force)."
EN.ui_t_auto = "Creates the obvious rules from the relics you own (same as /ssw auto). Wide-effect relics are left to you."
FR.ui_t_auto = "Crée les règles évidentes avec les reliques que tu possèdes (comme /ssw auto). Les reliques à effet large restent à ton choix."
EN.ui_t_view = "Show only the spells you know, or every spell of the catalogue for your class."
FR.ui_t_view = "Affiche seulement les sorts que tu connais, ou tous les sorts du catalogue pour ta classe."
EN.ui_t_reset = "Resets rules and settings (profiles are kept). The rules can be brought back with Undo."
FR.ui_t_reset = "Remet règles et réglages à zéro (les profils sont conservés). Les règles reviennent avec Annuler."
EN.ui_t_opener = "Relic equipped automatically out of combat (after a fight and at login). Click to pick the next spell."
FR.ui_t_opener = "Relique équipée automatiquement hors combat (après un combat et à la connexion). Clique pour passer au sort suivant."
EN.ui_sticky = "Persistent effect: needs to stay equipped."
FR.ui_sticky = "Effet persistant : doit rester équipée."
EN.ui_cond = "Only worth equipping when the target is under 35% health."
FR.ui_cond = "À n'équiper que si la cible a moins de 35 % de vie."
EN.ui_improves = "Improves: %s"
FR.ui_improves = "Améliore : %s"

-- ---------------------------------------------------------------- model (no frames : unit-testable)
function UI.State()
    if not SS.db then SS.InitDB() end
    if type(SS.db.ui) ~= "table" then SS.db.ui = {} end
    return SS.db.ui
end

-- the rule editor is validated for the Paladin
function UI.Supported()
    local cls = SS.PlayerClass()
    return cls == nil or cls == "PALADIN"
end

function UI.IsKnown(spell)
    local book = SS.book or SS.ScanBook()
    return book[string_lower(spell)] ~= nil
end

-- every catalogue spell of the player's class, plus spells that already have a rule (so no rule is ever hidden)
function UI.AllSpells()
    local cls = SS.PlayerClass()
    local seen, list = {}, {}
    for _, info in pairs(SS.Relics()) do
        if not cls or info.class == cls then
            for i = 1, getn(info.spells) do
                local sp = info.spells[i]
                if not seen[string_lower(sp)] then
                    seen[string_lower(sp)] = true
                    tinsert(list, sp)
                end
            end
        end
    end
    for key in pairs(SS.db.rules) do
        if not seen[string_lower(key)] then
            seen[string_lower(key)] = true
            tinsert(list, key)
        end
    end
    table.sort(list)
    return list
end

-- the spells listed in the window (known ones, or all, depending on the toggle) ; rules always show
function UI.View()
    local out = {}
    if not UI.Supported() then return out end
    local all = UI.AllSpells()
    local showAll = UI.State().all
    for i = 1, getn(all) do
        local sp = all[i]
        if showAll or SS.lc[string_lower(sp)] or UI.IsKnown(sp) then tinsert(out, sp) end
    end
    return out
end

-- relics that can be chosen for a spell : catalogue relics of the player's class that improve it
function UI.Options(spell)
    return SS.RelicsForSpell(spell, SS.PlayerClass())
end

-- rule key (or nil) and the list of relics currently stored for a spell
function UI.CurrentList(spell)
    local key = SS.lc[string_lower(spell)]
    local l = key and SS.db.rules[key]
    return key, l or {}
end

-- move relic slot 1 or 2 of a spell to the next (dir=1) / previous (dir=-1) valid relic. Uses the same rule writer as /ssw set.
function UI.Cycle(spell, slot, dir)
    local key, cur = UI.CurrentList(spell)
    if slot == 2 and not cur[1] then return false end
    local opts = UI.Options(spell)
    local n = getn(opts)
    if n == 0 then return false end
    local other = cur[3 - slot]
    local pos = 0                      -- 0 = no relic, 1..n = opts[pos]
    if cur[slot] then
        for i = 1, n do
            if opts[i] == cur[slot] then pos = i end
        end
    end
    local newName
    local tries = 0
    while tries <= n + 1 do
        pos = pos + dir
        if pos > n then pos = 0 end
        if pos < 0 then pos = n end
        if pos > 0 then newName = opts[pos] else newName = nil end
        tries = tries + 1
        if newName == nil or newName ~= other then break end
    end
    local a, b = cur[1], cur[2]
    if slot == 1 then a = newName else b = newName end
    local out = {}
    if a then tinsert(out, a) end
    if b then tinsert(out, b) end
    for i = 3, getn(cur) do tinsert(out, cur[i]) end
    local wasOff = key and SS.db.off[key]
    if getn(out) == 0 then
        if key then SS.ClearRule(key) end
        return true
    end
    SS.SetRuleCmd(key or spell, out, true)
    if wasOff then
        local k2 = SS.lc[string_lower(spell)]
        if k2 then SS.SetEnabled(k2, false, true) end   -- a rule the player switched off stays off
    end
    return true
end

-- check box of a row : rule on/off. Returns false when the spell has no rule yet.
function UI.ToggleSpell(spell)
    local key = SS.lc[string_lower(spell)]
    if not key then return false end
    SS.SetEnabled(key, SS.db.off[key] and true or false, true)
    return true
end

function UI.RelicText(name)
    if not name then return "|cFF888888" .. SS.T("ui_none") .. "|r" end
    local w = SS.RelicWhere(name)
    local col, tag
    if w == "equipped" then
        col, tag = "|cFF66CCFF", SS.T("ui_eq")
    elseif w == "bags" then
        col, tag = "|cFF66FF66", SS.T("ui_bags")
    else
        col, tag = "|cFFFF6666", SS.T("ui_miss")
    end
    local mark = ""
    if not SS.Relics()[name] then mark = " |cFFFFAA00(?)|r" end
    return col .. name .. "|r |cFFAAAAAA[" .. tag .. "]|r" .. mark
end

-- run a command and collect what it prints (the diagnostic tab shows it instead of the chat)
function UI.Capture(fn, arg)
    local lines = UI.diagLines or {}
    local saved = SS.sink
    SS.sink = {}
    local ok, err = pcall(fn, arg)
    local got = SS.sink
    SS.sink = saved
    if not ok then tinsert(got, "error: " .. tostring(err)) end
    for i = 1, getn(got) do tinsert(lines, got[i]) end
    while getn(lines) > 300 do table.remove(lines, 1) end
    UI.diagLines = lines
    UI.diagOffset = 0
end

function UI.ClearDiag()
    UI.diagLines = {}
    UI.diagOffset = 0
end

-- the text shown in the diagnostic area (last DIAG_LINES lines, scrolled by diagOffset)
function UI.DiagText()
    local lines = UI.diagLines or {}
    local n = getn(lines)
    local off = UI.diagOffset or 0
    local last = n - off
    if last < 0 then last = 0 end
    local first = last - UI.DIAG_LINES + 1
    if first < 1 then first = 1 end
    local out = {}
    for i = first, last do tinsert(out, lines[i]) end
    return table.concat(out, "\n")
end

function UI.DiagScroll(d)
    local n = getn(UI.diagLines or {})
    local off = (UI.diagOffset or 0) + d
    if off > n - UI.DIAG_LINES then off = n - UI.DIAG_LINES end
    if off < 0 then off = 0 end
    UI.diagOffset = off
end

-- two-click confirmation (no popup dependency) : the first click arms the id for a few seconds, the second one runs it
function UI.ConfirmClick(id, fn)
    local now = GetTime()
    if UI.confirmId == id and UI.confirmUntil and now < UI.confirmUntil then
        UI.confirmId = nil
        fn()
        return true
    end
    UI.confirmId = id
    UI.confirmUntil = now + UI.CONFIRM_SECONDS
    return false
end

function UI.ConfirmActive(id)
    return UI.confirmId == id and UI.confirmUntil ~= nil and GetTime() < UI.confirmUntil
end

-- ---------------------------------------------------------------- data-driven check boxes and buttons
-- check box : { id, tab, x, y, text, tip, get(), set(bool) }
UI.CHECKS = {
    { id = "enabled", tab = 2, x = 28, y = -96, text = "ui_c_enabled", tip = "ui_t_enabled",
      get = function() return SS.db.enabled end,
      set = function(v) if v then SS.cmds.on() else SS.cmds.off() end end },
    { id = "fallbacks", tab = 2, x = 28, y = -126, text = "ui_c_fallbacks", tip = "ui_t_fallbacks",
      get = function() return SS.db.fallbacks end,
      set = function(v) SS.cmds.fallbacks(v and "on" or "off") end },
    { id = "minimap", tab = 2, x = 28, y = -156, text = "ui_c_minimap", tip = "ui_t_minimap",
      get = function() return SS.db.minimap.show end,
      set = function(v) SS.cmds.minimap(v and "on" or "off") end },
    { id = "indicator", tab = 2, x = 28, y = -186, text = "ui_c_indicator", tip = "ui_t_indicator",
      get = function() return SS.db.indicator.show end,
      set = function(v) SS.cmds.indicator(v and "on" or "off") end },
    { id = "locked", tab = 2, x = 28, y = -216, text = "ui_c_locked", tip = "ui_t_locked",
      get = function() return SS.db.indicator.locked end,
      set = function(v) SS.cmds.indicator(v and "lock" or "unlock") end },
    { id = "alertchat", tab = 2, x = 28, y = -246, text = "ui_c_alertchat", tip = "ui_t_alertchat",
      get = function() return SS.db.alert.chat end,
      set = function(v) SS.cmds.alert("chat " .. (v and "on" or "off")) end },
    { id = "alertsound", tab = 2, x = 28, y = -276, text = "ui_c_alertsound", tip = "ui_t_alertsound",
      get = function() return SS.db.alert.sound end,
      set = function(v) SS.cmds.alert("sound " .. (v and "on" or "off")) end },
    { id = "offgcd", tab = 2, x = 28, y = -306, text = "ui_c_offgcd", tip = "ui_t_offgcd",
      get = function() return SS.db.offGcd == "skip" end,
      set = function(v) SS.cmds.offgcd(v and "skip" or "swap") end },
    { id = "autospec", specOnly = true, tab = 3, x = 28, y = -306, text = "ui_c_autospec", tip = "ui_t_autospec",
      get = function() return SS.db.autoSpec end,
      set = function(v) SS.cmds.spec("auto " .. (v and "on" or "off")) end },
}

local SPEC_CMD = { HOLY = "holy", PROT = "prot", RET = "ret", NECRO = "necro" }

local function NextOf(list, cur)
    local idx = 0
    for i = 1, getn(list) do
        if list[i] == cur then idx = i end
    end
    idx = idx + 1
    if idx > getn(list) then idx = 1 end
    return list[idx]
end

-- opener : none, then every spell that has a rule
function UI.NextOpener()
    local list = { "" }
    local keys = SS.SortedKeys(SS.db.rules)
    for i = 1, getn(keys) do tinsert(list, keys[i]) end
    local nxt = NextOf(list, SS.db.opener or "")
    SS.cmds.opener(nxt == "" and "off" or nxt)
end

function UI.NextLang()
    SS.cmds.lang(NextOf({ "auto", "fr", "en" }, SS.db.lang))
end

function UI.NextManualSpec()
    local nxt = NextOf({ "", "HOLY", "PROT", "RET" }, SS.db.specManual or "")
    SS.cmds.spec("manual " .. (nxt == "" and "off" or SPEC_CMD[nxt]))
end

function UI.Scale(d)
    local s = SS.db.indicator.scale + d
    SS.cmds.indicator("scale " .. string_format("%.2f", s))
end

function UI.ProfileNames()
    return SS.SortedKeys(SS.db.profiles)
end

function UI.SelectedProfile()
    local names = UI.ProfileNames()
    if UI.profIdx > getn(names) then UI.profIdx = getn(names) end
    if UI.profIdx < 1 then UI.profIdx = 1 end
    return names[UI.profIdx], names
end

function UI.ProfStep(d)
    local names = UI.ProfileNames()
    UI.profIdx = UI.profIdx + d
    if UI.profIdx > getn(names) then UI.profIdx = 1 end
    if UI.profIdx < 1 then UI.profIdx = getn(names) end
end

function UI.ProfSave()
    local name = string.gsub(UI.profEdit and UI.profEdit:GetText() or "", "^%s*(.-)%s*$", "%1")
    if name == "" then name = UI.SelectedProfile() or "" end
    if name == "" then SS.Print(SS.T("ui_p_noname")) return end
    SS.cmds.profile("save " .. name)
    if UI.profEdit then UI.profEdit:SetText("") end
    local names = UI.ProfileNames()
    for i = 1, getn(names) do
        if names[i] == name then UI.profIdx = i end
    end
end

function UI.ProfLoad()
    local sel = UI.SelectedProfile()
    if not sel then SS.Print(SS.T("nothing")) return end
    SS.cmds.profile("load " .. sel)
end

function UI.ProfDelete()
    local sel = UI.SelectedProfile()
    if sel then SS.cmds.profile("del " .. sel) end
end

function UI.DoExport()
    local text, n = SS.ExportText()
    UI.shareEdit:SetText(text)
    UI.shareMsg = SS.T("ui_s_done", n)
    UI.shareOk = true
end

function UI.DoImport()
    local ok, a, b = SS.ImportText(UI.shareEdit:GetText())
    if ok then
        UI.shareMsg = SS.T("share_imported", a)
        UI.shareOk = true
    else
        UI.shareMsg = SS.ShareErrorText(a, b)
        UI.shareOk = false
    end
    UI.page = 1
end

function UI.DoUndo()
    SS.cmds.undo()
    UI.shareMsg = nil
end

function UI.DoReset()
    SS.ResetSettings()
    SS.Print(SS.T("defaults_done"))
    UI.page = 1
    UI.shareMsg = nil
end

-- button : { id, tab, x, y, w, text(), tip, act(), confirm }
UI.BUTTONS = {
    -- rules tab
    { id = "mode", tab = 1, x = 20, y = -428, w = 190, text = function() return SS.T("ui_mode", SS.db.combat) end, tip = "ui_t_mode",
      act = function() SS.NextMode() end },
    { id = "auto", tab = 1, x = 216, y = -428, w = 130, text = function() return SS.T("ui_auto") end, tip = "ui_t_auto",
      act = function() SS.cmds.auto() end },
    { id = "import", tab = 1, x = 352, y = -428, w = 170, text = function() return SS.T("ui_import") end, tip = "ui_t_import",
      act = function() SS.cmds.import((IsShiftKeyDown and IsShiftKeyDown()) and "force" or "") end },
    { id = "view", tab = 1, x = 528, y = -428, w = 150, text = function() return SS.T(UI.State().all and "ui_view_all" or "ui_view_known") end,
      tip = "ui_t_view", act = function() local st = UI.State() if st.all then st.all = nil else st.all = true end UI.page = 1 end },
    -- settings tab
    { id = "smode", tab = 2, x = 420, y = -96, w = 330, text = function() return SS.T("ui_mode", SS.db.combat) end, tip = "ui_t_mode",
      act = function() SS.NextMode() end },
    { id = "lang", tab = 2, x = 420, y = -126, w = 330, text = function() return SS.T("ui_lang", SS.db.lang) end, tip = "ui_t_lang",
      act = function() UI.NextLang() end },
    { id = "opener", tab = 2, x = 420, y = -156, w = 330, text = function() return SS.T("ui_opener", SS.db.opener or SS.T("ui_none")) end,
      tip = "ui_t_opener", act = function() UI.NextOpener() end },
    { id = "scaledn", tab = 2, x = 600, y = -216, w = 28, text = function() return "-" end, tip = "ui_t_scale", act = function() UI.Scale(-0.1) end },
    { id = "scaleup", tab = 2, x = 692, y = -216, w = 28, text = function() return "+" end, tip = "ui_t_scale", act = function() UI.Scale(0.1) end },
    { id = "reset", tab = 2, x = 28, y = -420, w = 330, text = function() return SS.T("ui_reset") end, tip = "ui_t_reset",
      act = function() UI.DoReset() end, confirm = true },
    -- profiles tab : per spec (Necroladin is the 4th slot)
    { id = "ld_HOLY", specOnly = true, tab = 3, x = 360, y = -134, w = 100, text = function() return SS.T("ui_p_load") end, tip = "ui_t_specload",
      act = function() SS.cmds.spec("load holy") end },
    { id = "sv_HOLY", specOnly = true, tab = 3, x = 466, y = -134, w = 100, text = function() return SS.T("ui_p_save") end, tip = "ui_t_specsave",
      act = function() SS.cmds.spec("save holy") end },
    { id = "ld_PROT", specOnly = true, tab = 3, x = 360, y = -162, w = 100, text = function() return SS.T("ui_p_load") end, tip = "ui_t_specload",
      act = function() SS.cmds.spec("load prot") end },
    { id = "sv_PROT", specOnly = true, tab = 3, x = 466, y = -162, w = 100, text = function() return SS.T("ui_p_save") end, tip = "ui_t_specsave",
      act = function() SS.cmds.spec("save prot") end },
    { id = "ld_RET", specOnly = true, tab = 3, x = 360, y = -190, w = 100, text = function() return SS.T("ui_p_load") end, tip = "ui_t_specload",
      act = function() SS.cmds.spec("load ret") end },
    { id = "sv_RET", specOnly = true, tab = 3, x = 466, y = -190, w = 100, text = function() return SS.T("ui_p_save") end, tip = "ui_t_specsave",
      act = function() SS.cmds.spec("save ret") end },
    { id = "ld_NECRO", specOnly = true, tab = 3, x = 360, y = -218, w = 100, text = function() return SS.T("ui_p_load") end, tip = "ui_t_specload",
      act = function() SS.cmds.spec("load necro") end },
    { id = "sv_NECRO", specOnly = true, tab = 3, x = 466, y = -218, w = 100, text = function() return SS.T("ui_p_save") end, tip = "ui_t_specsave",
      act = function() SS.cmds.spec("save necro") end },
    { id = "rs_NECRO", specOnly = true, tab = 3, x = 572, y = -218, w = 150, text = function() return SS.T("ui_p_reset") end, tip = "ui_t_reset_slot",
      act = function() SS.cmds.spec("necro reset") end, confirm = true },
    { id = "nc_capture", specOnly = true, tab = 3, x = 28, y = -268, w = 400, text = function() return SS.T("ui_nc_capture") end, tip = "ui_t_nc_capture",
      act = function() SS.cmds.spec("necro capture") end },
    { id = "nc_tolm", specOnly = true, tab = 3, x = 440, y = -268, w = 28, text = function() return "-" end, tip = "ui_t_nc_tol",
      act = function() SS.cmds.spec("necro tol " .. math.max(0, (SS.db.necroTol or 2) - 1)) end },
    { id = "nc_tolp", specOnly = true, tab = 3, x = 560, y = -268, w = 28, text = function() return "+" end, tip = "ui_t_nc_tol",
      act = function() SS.cmds.spec("necro tol " .. math.min(10, (SS.db.necroTol or 2) + 1)) end },
    { id = "nc_clear", specOnly = true, tab = 3, x = 600, y = -268, w = 200, text = function() return SS.T("ui_nc_clear") end, tip = "ui_t_nc_clear",
      act = function() SS.cmds.spec("necro clear") end },
    { id = "manual", specOnly = true, tab = 3, x = 28, y = -336, w = 400, text = function() return SS.T("ui_p_manual", SS.SpecName(SS.db.specManual)) end,
      tip = "ui_t_manual", act = function() UI.NextManualSpec() end },
    -- profiles tab : named
    { id = "psave", tab = 3, x = 330, y = -406, w = 100, text = function() return SS.T("ui_p_save") end, tip = "ui_t_psave",
      act = function() UI.ProfSave() end },
    { id = "pprev", tab = 3, x = 28, y = -440, w = 24, text = function() return "<" end, tip = "ui_t_prev", act = function() UI.ProfStep(-1) end },
    { id = "pnext", tab = 3, x = 316, y = -440, w = 24, text = function() return ">" end, tip = "ui_t_next", act = function() UI.ProfStep(1) end },
    { id = "pload", tab = 3, x = 350, y = -440, w = 110, text = function() return SS.T("ui_p_load") end, tip = "ui_t_pload",
      act = function() UI.ProfLoad() end },
    { id = "pdel", tab = 3, x = 466, y = -440, w = 130, text = function() return SS.T("ui_p_del") end, tip = "ui_t_pdel",
      act = function() UI.ProfDelete() end, confirm = true },
    -- share tab
    { id = "export", tab = 4, x = 28, y = -190, w = 180, text = function() return SS.T("ui_s_export") end, tip = "ui_t_export",
      act = function() UI.DoExport() end },
    { id = "doimport", tab = 4, x = 214, y = -190, w = 250, text = function() return SS.T("ui_s_import") end, tip = "ui_t_doimport",
      act = function() UI.DoImport() end, confirm = true },
    { id = "undo", tab = 4, x = 470, y = -190, w = 200, text = function() return SS.T("ui_s_undo") end, tip = "ui_t_undo",
      act = function() UI.DoUndo() end },
    { id = "sclear", tab = 4, x = 676, y = -190, w = 80, text = function() return SS.T("ui_s_clear") end, tip = "ui_t_sclear",
      act = function() UI.shareEdit:SetText("") UI.shareMsg = nil end },
    -- diagnostic tab
    { id = "dstatus", tab = 5, x = 22, y = -92, w = 100, text = function() return SS.T("ui_d_status") end, tip = "ui_t_dstatus",
      act = function() UI.Capture(SS.cmds.status) end },
    { id = "dlog", tab = 5, x = 126, y = -92, w = 110, text = function() return SS.T("ui_d_log") end, tip = "ui_t_dlog",
      act = function() UI.Capture(SS.cmds.log) end },
    { id = "dcheck", tab = 5, x = 240, y = -92, w = 140, text = function() return SS.T("ui_d_check") end, tip = "ui_t_dcheck",
      act = function() UI.Capture(SS.cmds.check) end },
    { id = "dclear", tab = 5, x = 384, y = -92, w = 90, text = function() return SS.T("ui_d_clear") end, tip = "ui_t_dclear",
      act = function() UI.ClearDiag() end },
    { id = "dtrace", tab = 5, x = 478, y = -92, w = 140, text = function() return SS.T("ui_d_trace", SS.db.trace and "ON" or "OFF") end,
      tip = "ui_t_dtrace", act = function() UI.Capture(SS.cmds.trace, SS.db.trace and "off" or "on") end },
    { id = "ddebug", tab = 5, x = 622, y = -92, w = 140, text = function() return SS.T("ui_d_debug", SS.db.debug and "ON" or "OFF") end,
      tip = "ui_t_ddebug", act = function() UI.Capture(SS.cmds.debug, SS.db.debug and "off" or "on") end },
    { id = "dtl", tab = 5, x = 22, y = -420, w = 250, text = function() return SS.T("ui_d_tl", SS.TraceActive() and "ON" or "OFF") end, tip = "ui_t_dtl",
      act = function() UI.Capture(SS.cmds.trace, SS.TraceActive() and "off" or "on") end },
    { id = "dtlshow", tab = 5, x = 278, y = -420, w = 210, text = function() return SS.T("ui_d_tlshow") end, tip = "ui_t_dtlshow",
      act = function() UI.Capture(SS.cmds.tracelog, "60") end },
    { id = "dtlclear", tab = 5, x = 494, y = -420, w = 170, text = function() return SS.T("ui_d_tlclear") end, tip = "ui_t_dtlclear",
      act = function() UI.Capture(SS.cmds.trace, "clear") end, confirm = true },
    { id = "dup", tab = 5, x = 726, y = -420, w = 30, text = function() return "^" end, tip = "ui_t_prev", act = function() UI.DiagScroll(5) end },
    { id = "ddown", tab = 5, x = 726, y = -446, w = 30, text = function() return "v" end, tip = "ui_t_next", act = function() UI.DiagScroll(-5) end },
}

EN.ui_c_offgcd = "Never swap in combat for Judgement (it has no global cooldown)"
FR.ui_c_offgcd = "Ne jamais échanger en combat pour Judgement (il n'a pas de GCD)"
EN.ui_t_offgcd = "A combat swap starts a 1.5 s cooldown on the global-cooldown category. Judgement has no GCD of its own, so swapping for it only costs time. Same as /ssw offgcd skip. Off by default."
FR.ui_t_offgcd = "Un échange en combat lance une recharge de 1,5 s sur la catégorie du GCD. Judgement n'a pas de GCD, l'échanger pour lui ne fait que perdre du temps. Comme /ssw offgcd skip. Désactivé par défaut."
EN.ui_d_tl = "Persistent trace: %s"
FR.ui_d_tl = "Trace persistante : %s"
EN.ui_d_tlshow = "Show the stored trace"
FR.ui_d_tlshow = "Afficher la trace enregistrée"
EN.ui_d_tlclear = "Clear the trace"
FR.ui_d_tlclear = "Effacer la trace"
EN.ui_t_dtl = "Every swap decision is written (100 lines) into the saved variables, readable in ShikaSwap.lua after /reload. On for one week by default; click for on/off (same as /ssw trace)."
FR.ui_t_dtl = "Chaque décision d'échange est écrite (100 lignes) dans les SavedVariables, lisible dans ShikaSwap.lua après /reload. Active une semaine par défaut ; clique pour activer / couper (comme /ssw trace)."
EN.ui_t_dtlshow = "Shows the last 60 stored trace lines in this view (same as /ssw tracelog 60)."
FR.ui_t_dtlshow = "Affiche les 60 dernières lignes de trace enregistrées dans cette vue (comme /ssw tracelog 60)."
EN.ui_t_dtlclear = "Empties the stored trace (asks for a second click)."
FR.ui_t_dtlclear = "Vide la trace enregistrée (demande un second clic)."
EN.ui_t_enabled = "Whole addon on/off (same as /ssw on, /ssw off)."
FR.ui_t_enabled = "Tout l'addon actif / coupé (comme /ssw on, /ssw off)."
EN.ui_t_fallbacks = "When the best relic is not in your bags, use an equivalent lesser one (Light > Divinity)."
FR.ui_t_fallbacks = "Quand la meilleure relique n'est pas dans tes sacs, utilise une équivalente moins bonne (Light > Divinity)."
EN.ui_t_minimap = "Show or hide the minimap button (same as /ssw minimap)."
FR.ui_t_minimap = "Affiche ou masque le bouton de la minimap (comme /ssw minimap)."
EN.ui_t_indicator = "Floating icon of the equipped relic, with the 1.5 s swap cooldown counting down in combat."
FR.ui_t_indicator = "Icône flottante de la relique équipée, avec le décompte de la recharge d'échange de 1,5 s en combat."
EN.ui_t_locked = "A locked indicator cannot be moved by mistake."
FR.ui_t_locked = "Un indicateur verrouillé ne peut pas être déplacé par erreur."
EN.ui_t_alertchat = "Prints a message when a spell has a rule but none of its relics is in your bags (once per spell and per fight)."
FR.ui_t_alertchat = "Affiche un message quand un sort a une règle mais qu'aucune de ses reliques n'est dans tes sacs (une fois par sort et par combat)."
EN.ui_t_alertsound = "Also plays a warning sound for that alert."
FR.ui_t_alertsound = "Joue aussi un son d'avertissement pour cette alerte."
EN.ui_t_autospec = "Paladin: when your talents change, your rules are saved for the old spec and the rules of the new spec are loaded."
FR.ui_t_autospec = "Paladin : quand tes talents changent, tes règles sont sauvées pour l'ancienne spécialité et celles de la nouvelle sont chargées."
EN.ui_t_lang = "Language of the messages: auto (game language), fr, en (same as /ssw lang)."
FR.ui_t_lang = "Langue des messages : auto (langue du jeu), fr, en (comme /ssw lang)."
EN.ui_t_scale = "Indicator size (same as /ssw indicator scale)."
FR.ui_t_scale = "Taille de l'indicateur (comme /ssw indicator scale)."
EN.ui_t_specload = "Replace your current rules by the saved rules of this spec (Undo available)."
FR.ui_t_specload = "Remplace tes règles actuelles par celles enregistrées pour cette spécialité (Annuler disponible)."
EN.ui_t_specsave = "Save your current rules as the rules of this spec."
FR.ui_t_specsave = "Enregistre tes règles actuelles comme règles de cette spécialité."
EN.ui_t_manual = "Used only when the talents cannot be read. Click to change."
FR.ui_t_manual = "Utilisée seulement si les talents sont illisibles. Clique pour changer."
EN.ui_t_psave = "Save the current rules under that name (same as /ssw profile save)."
FR.ui_t_psave = "Enregistre les règles actuelles sous ce nom (comme /ssw profile save)."
EN.ui_t_pload = "Load the selected profile (same as /ssw profile load). Undo available."
FR.ui_t_pload = "Charge le profil choisi (comme /ssw profile load). Annuler disponible."
EN.ui_t_pdel = "Delete the selected profile (asks for a second click)."
FR.ui_t_pdel = "Supprime le profil choisi (demande un second clic)."
EN.ui_t_export = "Write your rules as one line of text in the box."
FR.ui_t_export = "Écrit tes règles sur une ligne de texte dans la boîte."
EN.ui_t_doimport = "Check the text in the box and replace your rules with it (asks for a second click)."
FR.ui_t_doimport = "Vérifie le texte de la boîte et remplace tes règles par lui (demande un second clic)."
EN.ui_t_undo = "Bring back the rules you had before the last import, reset, profile or spec load."
FR.ui_t_undo = "Ramène les règles d'avant le dernier import, la dernière réinitialisation ou le dernier chargement de profil / spécialité."
EN.ui_t_sclear = "Empty the text box."
FR.ui_t_sclear = "Vide la boîte de texte."
EN.ui_t_dstatus = "Same as /ssw status."
FR.ui_t_dstatus = "Comme /ssw status."
EN.ui_t_dlog = "Same as /ssw log: the last decisions (turn recording on first)."
FR.ui_t_dlog = "Comme /ssw log : les dernières décisions (active d'abord l'enregistrement)."
EN.ui_t_dcheck = "Same as /ssw check: finds mistakes in your rules."
FR.ui_t_dcheck = "Comme /ssw check : cherche les erreurs dans tes règles."
EN.ui_t_dclear = "Empty this view."
FR.ui_t_dclear = "Vide cet affichage."
EN.ui_t_dtrace = "Silent recording of the last 40 decisions (same as /ssw trace)."
FR.ui_t_dtrace = "Enregistrement silencieux des 40 dernières décisions (comme /ssw trace)."
EN.ui_t_ddebug = "Prints every decision live in the chat (same as /ssw debug)."
FR.ui_t_ddebug = "Affiche chaque décision en direct dans le chat (comme /ssw debug)."

-- ---------------------------------------------------------------- small widget helpers (all handlers use `this` / `arg1`)
function UI.Err(err)
    UI.lastError = tostring(err)
    SS.Print("|cFFFF6666" .. SS.T("ui_error", UI.lastError) .. "|r")
end

-- a click handler that can never raise : an error is reported in the chat, nothing else is affected
local function Guard(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then UI.Err(err) end
    end
end

-- ---- icons (every API call is under pcall ; a missing texture only gives the question-mark icon)
function UI.ItemTexture(id)
    if not id or not GetItemInfo then return nil end
    local c = UI.texCache and UI.texCache[id]
    if c then return c end
    local ok, _, _, _, _, _, _, _, _, tex = pcall(GetItemInfo, "item:" .. id .. ":0:0:0")
    if ok and type(tex) == "string" and tex ~= "" then
        if not UI.texCache then UI.texCache = {} end
        UI.texCache[id] = tex
        return tex
    end
    return nil
end

-- is the item known to the client (so that a tooltip needs no server query) ?
function UI.ItemCached(id)
    if not id or not GetItemInfo then return false end
    local ok, name = pcall(GetItemInfo, "item:" .. id .. ":0:0:0")
    return ok and type(name) == "string" and name ~= ""
end

function UI.RelicTextureFallback(name)
    local w = SS.RelicWhere(name)
    if w == "equipped" and GetInventoryItemTexture then return GetInventoryItemTexture("player", SS.SLOT) end
    if w == "bags" and GetContainerItemInfo then
        local b, sl = SS.FindRelic(name)
        if b then return (GetContainerItemInfo(b, sl)) end
    end
    return nil
end

-- icon of a relic : item info texture, else the texture of the copy in the bags / on the character, else the question mark
function UI.RelicTexture(name)
    local info = name and SS.Relics()[name]
    if not info then return UI.Q_ICON end
    local tex = UI.ItemTexture(info.id)
    if not tex then
        local ok, t = pcall(UI.RelicTextureFallback, name)
        if ok and type(t) == "string" and t ~= "" then tex = t end
    end
    return tex or UI.Q_ICON
end

-- icon of a spell : spellbook texture, else the question mark
function UI.SpellTexture(spell)
    local ok, t = pcall(function()
        local book = SS.book or SS.ScanBook()
        local e = book[string_lower(spell)]
        if e and GetSpellTexture then return GetSpellTexture(e.max, "spell") end
        return nil
    end)
    if ok and type(t) == "string" and t ~= "" then return t end
    return UI.Q_ICON
end

-- tooltip of a relic : the real item tooltip when the client already knows the item (SetHyperlink under pcall), else the catalogue data
function UI.RelicTip(w)
    local info = SS.Relics()[w.relic]
    if not info then return false end
    GameTooltip:SetOwner(w, "ANCHOR_RIGHT")
    local full = false
    if GameTooltip.SetHyperlink and UI.ItemCached(info.id) then
        full = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. info.id .. ":0:0:0")
    end
    if not full then
        GameTooltip:SetText(w.relic, 1, 1, 1)
        if info.note then GameTooltip:AddLine(info.note, 0.8, 0.8, 0.8, 1) end
    end
    if info.spells and getn(info.spells) > 0 then
        GameTooltip:AddLine(SS.T("ui_improves", table.concat(info.spells, ", ")), 0.6, 1, 0.6, 1)
    end
    if info.sticky then GameTooltip:AddLine(SS.T("ui_sticky"), 1, 0.8, 0.3, 1) end
    if info.cond then GameTooltip:AddLine(SS.T("ui_cond"), 1, 0.8, 0.3, 1) end
    GameTooltip:AddLine(SS.T("ui_t_label"), 0.5, 0.5, 0.5, 1)
    GameTooltip:Show()
    return true
end

function UI.OnEnter()
    if not GameTooltip then return end
    local w = this
    if w.relic and UI.RelicTip(w) then return end
    if w.tipKey then
        GameTooltip:SetOwner(w, "ANCHOR_RIGHT")
        GameTooltip:SetText(SS.T(w.tipKey), 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end
end

function UI.OnLeave()
    if GameTooltip then GameTooltip:Hide() end
end

function UI.MakeButton(parent, w, h, text, tipKey, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(h)
    b:SetText(text)
    b.tipKey = tipKey
    b:SetScript("OnClick", Guard(fn))
    b:SetScript("OnEnter", UI.OnEnter)
    b:SetScript("OnLeave", UI.OnLeave)
    return b
end

function UI.MakeText(parent, font, justify, w)
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH(justify)
    return fs
end

local function Place(w, parent, x, y)
    w:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

-- ---- theme helpers (decoration only : each one is under pcall and returns nil on failure, the menu works without them)
function UI.Color(w, c)
    if w and w.SetTextColor then pcall(w.SetTextColor, w, c[1], c[2], c[3]) end
end

-- inline colour code (survives the button hover states, unlike SetTextColor on a button)
function UI.Tint(text, c)
    return string_format("|cFF%02X%02X%02X%s|r", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), text)
end

-- a solid colour rectangle, no texture file : SetTexture(r, g, b, a)
function UI.Solid(parent, layer, w, h, c, a, point, rel, relPoint, x, y)
    local ok, t = pcall(function()
        local tx = parent:CreateTexture(nil, layer)
        tx:SetWidth(w)
        tx:SetHeight(h)
        tx:SetTexture(c[1], c[2], c[3], a)
        tx:SetPoint(point, rel, relPoint, x, y)
        return tx
    end)
    if ok then return t end
    return nil
end

function UI.SetSolid(tx, c, a)
    if tx then pcall(tx.SetTexture, tx, c[1], c[2], c[3], a or 1) end
end

function UI.ShowIf(tx, on)
    if not tx then return end
    if on then tx:Show() else tx:Hide() end
end

-- ---------------------------------------------------------------- click handlers (read `this`)
function UI.RowSpell(row)
    local v = UI.view
    if not v then return nil end
    return v[(UI.page - 1) * UI.ROWS + row]
end

function UI.OnCheck()
    local sp = UI.RowSpell(this.row)
    if sp then UI.ToggleSpell(sp) end
    UI.Refresh()
end

function UI.OnArrow()
    local sp = UI.RowSpell(this.row)
    if sp then UI.Cycle(sp, this.slot, this.dir) end
    UI.Refresh()
end

function UI.OnLabelClick()
    local sp = UI.RowSpell(this.row)
    local dir = 1
    if arg1 == "RightButton" then dir = -1 end
    if sp then UI.Cycle(sp, this.slot, dir) end
    UI.Refresh()
end

-- generic check box of the CHECKS table
function UI.OnDefCheck()
    local d = this.def
    d.set(this:GetChecked() and true or false)
    UI.Refresh()
end

-- generic button of the BUTTONS table
function UI.OnDefButton()
    local d = this.def
    if d.confirm then UI.ConfirmClick(d.id, d.act) else d.act() end
    UI.Refresh()
end

function UI.OnTab()
    UI.SetTab(this.tabIndex)
end

function UI.OnPage()
    UI.page = UI.page + this.dir
    UI.Refresh()
end

function UI.OnWheel()
    if UI.tab == 5 then
        UI.DiagScroll((arg1 and arg1 > 0) and 3 or -3)
    elseif UI.tab == 1 then
        UI.page = UI.page + ((arg1 and arg1 > 0) and -1 or 1)
    end
    UI.Refresh()
end

function UI.OnDragStop()
    this:StopMovingOrSizing()
    local l, t = this:GetLeft(), this:GetTop()
    if type(l) == "number" and type(t) == "number" then
        local st = UI.State()
        st.x = l
        st.y = t
    end
end

-- ---------------------------------------------------------------- building the window
function UI.BuildRow(parent, i)
    local row = {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(UI.WIDTH - 40)
    f:SetHeight(UI.ROW_H)
    Place(f, parent, 20, -(UI.TOP + (i - 1) * UI.ROW_H))
    row.frame = f

    local cb = CreateFrame("CheckButton", "ShikaSwapUICheck" .. i, f, "UICheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    cb.row = i
    cb.tipKey = "ui_t_check"
    cb:SetScript("OnClick", Guard(UI.OnCheck))
    cb:SetScript("OnEnter", UI.OnEnter)
    cb:SetScript("OnLeave", UI.OnLeave)
    row.check = cb

    -- spell icon + name
    row.spellIcon = f:CreateTexture(nil, "ARTWORK")
    row.spellIcon:SetWidth(20)
    row.spellIcon:SetHeight(20)
    row.spellIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -3)
    row.name = UI.MakeText(f, "GameFontNormalSmall", "LEFT", 146)
    row.name:SetPoint("TOPLEFT", f, "TOPLEFT", 52, -7)

    row.prev, row.next, row.label, row.relicIcon = {}, {}, {}, {}
    for s = 1, 2 do
        local x = 206 + (s - 1) * 296
        local pv = UI.MakeButton(f, 20, 20, "<", "ui_t_prev", UI.OnArrow)
        pv:SetPoint("TOPLEFT", f, "TOPLEFT", x, -2)
        pv.row, pv.slot, pv.dir = i, s, -1
        row.prev[s] = pv

        -- relic icon (hover = the item tooltip, click = next / previous like the name)
        local ic = CreateFrame("Frame", nil, f)
        ic:SetWidth(20)
        ic:SetHeight(20)
        ic:SetPoint("TOPLEFT", f, "TOPLEFT", x + 24, -3)
        ic:EnableMouse(true)
        ic.row, ic.slot = i, s
        ic:SetScript("OnMouseUp", Guard(UI.OnLabelClick))
        ic:SetScript("OnEnter", UI.OnEnter)
        ic:SetScript("OnLeave", UI.OnLeave)
        ic.tex = ic:CreateTexture(nil, "ARTWORK")
        ic.tex:SetAllPoints(ic)
        row.relicIcon[s] = ic

        local lb = CreateFrame("Frame", nil, f)
        lb:SetWidth(214)
        lb:SetHeight(22)
        lb:SetPoint("TOPLEFT", f, "TOPLEFT", x + 48, -2)
        lb:EnableMouse(true)
        lb.row, lb.slot = i, s
        lb:SetScript("OnMouseUp", Guard(UI.OnLabelClick))
        lb:SetScript("OnEnter", UI.OnEnter)
        lb:SetScript("OnLeave", UI.OnLeave)
        lb.fs = UI.MakeText(lb, "GameFontHighlightSmall", "LEFT", 214)
        lb.fs:SetPoint("LEFT", lb, "LEFT", 4, 0)
        row.label[s] = lb

        local nx = UI.MakeButton(f, 20, 20, ">", "ui_t_next", UI.OnArrow)
        nx:SetPoint("TOPLEFT", f, "TOPLEFT", x + 266, -2)
        nx.row, nx.slot, nx.dir = i, s, 1
        row.next[s] = nx
    end
    return row
end

function UI.BuildRulesTab(t)
    UI.rows = {}
    t.h1 = UI.MakeText(t, "GameFontNormalSmall", "LEFT", 130)
    Place(t.h1, t, 72, -80)
    t.h2 = UI.MakeText(t, "GameFontNormalSmall", "LEFT", 250)
    Place(t.h2, t, 250, -80)
    t.h3 = UI.MakeText(t, "GameFontNormalSmall", "LEFT", 250)
    Place(t.h3, t, 546, -80)
    UI.Color(t.h1, UI.PINK)
    UI.Color(t.h2, UI.PINK)
    UI.Color(t.h3, UI.PINK)
    for i = 1, UI.ROWS do
        UI.rows[i] = UI.BuildRow(t, i)
    end
    t.empty = UI.MakeText(t, "GameFontHighlight", "CENTER", UI.WIDTH - 100)
    Place(t.empty, t, 50, -170)
    local y = UI.TOP + UI.ROWS * UI.ROW_H + 8
    local pp = UI.MakeButton(t, 22, 20, "<", "ui_t_prev", UI.OnPage)
    Place(pp, t, 20, -y)
    pp.dir = -1
    t.pageText = UI.MakeText(t, "GameFontHighlightSmall", "CENTER", 90)
    t.pageText:SetPoint("LEFT", pp, "RIGHT", 4, 0)
    local pn = UI.MakeButton(t, 22, 20, ">", "ui_t_next", UI.OnPage)
    pn:SetPoint("LEFT", pp, "RIGHT", 98, 0)
    pn.dir = 1
    t.line = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", UI.WIDTH - 220)
    Place(t.line, t, 180, -(y + 4))
end

function UI.BuildSettingsTab(t)
    t.scaleLabel = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 170)
    Place(t.scaleLabel, t, 420, -222)
    t.scaleValue = UI.MakeText(t, "GameFontNormal", "CENTER", 60)
    Place(t.scaleValue, t, 630, -222)
    t.modesHelp = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 720)
    t.modesHelp:SetJustifyV("TOP")
    t.modesHelp:SetHeight(100)
    Place(t.modesHelp, t, 30, -310)
end

function UI.BuildProfilesTab(t)
    t.h1 = UI.MakeText(t, "GameFontNormal", "LEFT", 400)
    Place(t.h1, t, 28, -84)
    UI.Color(t.h1, UI.GOLD)
    t.detected = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 500)
    Place(t.detected, t, 28, -108)
    UI.Color(t.detected, UI.PINK)
    t.specName, t.specState = {}, {}
    for i = 1, getn(SS.SPEC_ORDER) do
        t.specName[i] = UI.MakeText(t, "GameFontHighlight", "LEFT", 130)
        Place(t.specName[i], t, 40, -(138 + (i - 1) * 28))
        t.specState[i] = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 170)
        Place(t.specState[i], t, 180, -(139 + (i - 1) * 28))
    end
    t.noSpec = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 700)
    Place(t.noSpec, t, 28, -132)
    -- Necroladin signature status and tolerance
    t.necroSig = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 770)
    Place(t.necroSig, t, 28, -248)
    t.tolText = UI.MakeText(t, "GameFontNormalSmall", "CENTER", 84)
    Place(t.tolText, t, 472, -273)
    t.h2 = UI.MakeText(t, "GameFontNormal", "LEFT", 400)
    Place(t.h2, t, 28, -376)
    UI.Color(t.h2, UI.GOLD)
    t.nameHint = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 700)
    Place(t.nameHint, t, 28, -394)
    local eb = CreateFrame("EditBox", "ShikaSwapUIProfileName", t, "InputBoxTemplate")
    eb:SetWidth(280)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(30)
    Place(eb, t, 36, -408)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    UI.profEdit = eb
    t.selText = UI.MakeText(t, "GameFontNormal", "CENTER", 250)
    Place(t.selText, t, 58, -444)
end

function UI.BuildShareTab(t)
    t.help = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 720)
    t.help:SetJustifyV("TOP")
    t.help:SetHeight(60)
    Place(t.help, t, 28, -84)
    local eb = CreateFrame("EditBox", "ShikaSwapUIShareBox", t, "InputBoxTemplate")
    eb:SetWidth(700)
    eb:SetHeight(24)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(SS.SHARE_MAX_LEN)
    Place(eb, t, 36, -156)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    UI.shareEdit = eb
    t.msg = UI.MakeText(t, "GameFontHighlight", "LEFT", 720)
    Place(t.msg, t, 28, -236)
end

function UI.BuildDiagTab(t)
    t.hint = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 720)
    Place(t.hint, t, 28, -122)
    t.out = UI.MakeText(t, "GameFontHighlightSmall", "LEFT", 690)
    t.out:SetJustifyV("TOP")
    t.out:SetHeight(UI.DIAG_LINES * 12 + 10)
    Place(t.out, t, 28, -150)
end

function UI.BuildWidgets(f)
    for i = 1, getn(UI.CHECKS) do
        local d = UI.CHECKS[i]
        local parent = UI.tabs[d.tab]
        local cb = CreateFrame("CheckButton", "ShikaSwapUIChk_" .. d.id, parent, "UICheckButtonTemplate")
        cb:SetWidth(24)
        cb:SetHeight(24)
        Place(cb, parent, d.x, d.y)
        cb.def = d
        cb.tipKey = d.tip
        cb:SetScript("OnClick", Guard(UI.OnDefCheck))
        cb:SetScript("OnEnter", UI.OnEnter)
        cb:SetScript("OnLeave", UI.OnLeave)
        cb.label = UI.MakeText(parent, "GameFontHighlightSmall", "LEFT", 340)
        cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        d.widget = cb
    end
    for i = 1, getn(UI.BUTTONS) do
        local d = UI.BUTTONS[i]
        local parent = UI.tabs[d.tab]
        local b = UI.MakeButton(parent, d.w, 24, "", d.tip, UI.OnDefButton)
        Place(b, parent, d.x, d.y)
        b.def = d
        d.widget = b
    end
end

function UI.OnBar()
    SS.cmds.spec("load " .. SPEC_CMD[this.spec])
    UI.Refresh()
end

-- title (gold), version (pink), state pill, separators
function UI.BuildHeader(f)
    f.title = UI.MakeText(f, "GameFontNormalLarge", "LEFT", 120)
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -14)
    UI.Color(f.title, UI.GOLD)
    f.version = UI.MakeText(f, "GameFontHighlightSmall", "LEFT", 60)
    f.version:SetPoint("LEFT", f.title, "RIGHT", 6, -2)
    UI.Color(f.version, UI.PINK)
    f.stateText = UI.MakeText(f, "GameFontHighlightSmall", "LEFT", 300)
    f.stateText:SetPoint("LEFT", f.version, "RIGHT", 36, 0)
    f.pill = UI.Solid(f, "OVERLAY", 10, 10, { 0.6, 0.6, 0.6 }, 1, "LEFT", f.version, "RIGHT", 18, 0)
    f.sep1 = UI.Solid(f, "ARTWORK", UI.WIDTH - 40, 1, UI.GOLD, 0.35, "TOPLEFT", f, "TOPLEFT", 20, -74)
    f.sep2 = UI.Solid(f, "ARTWORK", UI.WIDTH - 40, 1, UI.GOLD, 0.35, "TOPLEFT", f, "TOPLEFT", 20, -108)
end

-- profile bar, always visible : one button per spec slot, the profile in use is lit
function UI.BuildBar(f)
    f.barLabel = UI.MakeText(f, "GameFontNormalSmall", "LEFT", 60)
    Place(f.barLabel, f, 24, -52)
    UI.Color(f.barLabel, UI.PINK)
    UI.bar = {}
    for i = 1, getn(SS.SPEC_ORDER) do
        local sp = SS.SPEC_ORDER[i]
        local b = UI.MakeButton(f, 132, 22, "", "ui_t_bar_" .. sp, UI.OnBar)
        Place(b, f, 84 + (i - 1) * 138, -46)
        b.spec = sp
        b.glow = UI.Solid(b, "OVERLAY", 116, 3, UI.PINK, 1, "BOTTOM", b, "BOTTOM", 0, 3)
        UI.bar[i] = b
    end
end

function UI.Build()
    if UI.frame then return UI.frame end
    if not SS.db then SS.InitDB() end
    local f = CreateFrame("Frame", "ShikaSwapUIFrame", UIParent)
    f:SetWidth(UI.WIDTH)
    f:SetHeight(UI.HEIGHT)
    f:SetFrameStrata("DIALOG")
    -- dark translucent background, thin gold border (base 1.12 textures only)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    pcall(f.SetBackdropColor, f, 0.04, 0.04, 0.07, 0.95)
    pcall(f.SetBackdropBorderColor, f, UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.9)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", Guard(UI.OnDragStop))
    f:SetScript("OnMouseWheel", Guard(UI.OnWheel))
    local st = UI.State()
    if type(st.x) == "number" and type(st.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.x, st.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    UI.BuildHeader(f)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    UI.BuildBar(f)

    -- tab buttons and tab panels (panels sit under the profile bar ; children use panel coordinates)
    UI.tabButtons, UI.tabs = {}, {}
    for i = 1, getn(UI.TABS) do
        local b = UI.MakeButton(f, 154, 24, "", nil, UI.OnTab)
        Place(b, f, 22 + (i - 1) * 156, -80)
        b.tabIndex = i
        b.glow = UI.Solid(b, "OVERLAY", 146, 3, UI.GOLD, 1, "BOTTOM", b, "BOTTOM", 0, 2)
        UI.tabButtons[i] = b
        local t = CreateFrame("Frame", nil, f)
        t:SetWidth(UI.WIDTH)
        t:SetHeight(UI.HEIGHT + UI.PANEL_Y)
        Place(t, f, 0, UI.PANEL_Y)
        t:Hide()
        UI.tabs[i] = t
    end
    UI.BuildRulesTab(UI.tabs[1])
    UI.BuildSettingsTab(UI.tabs[2])
    UI.BuildProfilesTab(UI.tabs[3])
    UI.BuildShareTab(UI.tabs[4])
    UI.BuildDiagTab(UI.tabs[5])
    UI.BuildWidgets(f)

    -- bags / equipment / spells change while the window is open : redraw (throttled) only while it is visible
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("UNIT_INVENTORY_CHANGED")
    f:RegisterEvent("SPELLS_CHANGED")
    f:RegisterEvent("CHARACTER_POINTS_CHANGED")
    f:SetScript("OnEvent", function() UI.dirty = true end)
    f:SetScript("OnShow", Guard(UI.Refresh))
    f:SetScript("OnUpdate", function()
        UI.acc = (UI.acc or 0) + (arg1 or 0)
        if UI.acc < 0.3 then return end
        UI.acc = 0
        if UI.confirmId and UI.confirmUntil and GetTime() >= UI.confirmUntil then
            UI.confirmId = nil
            UI.dirty = true
        end
        if UI.dirty then
            UI.dirty = false
            UI.Refresh()
        end
    end)

    UI.frame = f
    if UISpecialFrames then tinsert(UISpecialFrames, "ShikaSwapUIFrame") end   -- Escape closes the window
    local want = st.tab
    if type(want) ~= "number" or want < 1 or want > getn(UI.TABS) then want = 1 end
    UI.tab = want
    UI.tabs[want]:Show()
    f:Hide()
    return f
end

-- ---------------------------------------------------------------- redraw
-- spell icon and chosen relic icons of one row
function UI.RowIcons(r, sp, cur)
    r.spellIcon:SetTexture(UI.SpellTexture(sp))
    for s = 1, 2 do
        local ic = r.relicIcon[s]
        if cur[s] then
            ic.tex:SetTexture(UI.RelicTexture(cur[s]))
            ic.tex:Show()
        else
            ic.tex:Hide()
        end
    end
end

function UI.RefreshRules(t)
    local view = UI.View()
    UI.view = view
    local pages = math.ceil(getn(view) / UI.ROWS)
    if pages < 1 then pages = 1 end
    if UI.page > pages then UI.page = pages end
    if UI.page < 1 then UI.page = 1 end
    t.h1:SetText(SS.T("ui_h_spell"))
    t.h2:SetText(SS.T("ui_h_r1"))
    t.h3:SetText(SS.T("ui_h_r2"))
    for i = 1, UI.ROWS do
        local r = UI.rows[i]
        local sp = view[(UI.page - 1) * UI.ROWS + i]
        if sp then
            local key, cur = UI.CurrentList(sp)
            local known = UI.IsKnown(sp)
            r.name:SetText((known and "|cFFFFFFFF" or "|cFF888888") .. sp .. "|r")
            r.check:SetChecked((key and not SS.db.off[key]) and 1 or nil)
            if key then r.check:Enable() else r.check:Disable() end
            pcall(UI.RowIcons, r, sp, cur)
            for s = 1, 2 do
                local lb = r.label[s]
                lb.relic = cur[s]
                r.relicIcon[s].relic = cur[s]
                lb.fs:SetText(UI.RelicText(cur[s]))
                if s == 2 and not cur[1] then
                    r.prev[s]:Disable()
                    r.next[s]:Disable()
                else
                    r.prev[s]:Enable()
                    r.next[s]:Enable()
                end
            end
            r.frame:Show()
        else
            r.frame:Hide()
        end
    end
    if not UI.Supported() then
        t.empty:SetText(SS.T("ui_class_note"))
    elseif getn(view) == 0 then
        t.empty:SetText(SS.T("ui_empty"))
    else
        t.empty:SetText("")
    end
    t.pageText:SetText(SS.T("ui_page", UI.page, pages))
    local line = SS.T("ui_line", tostring(SS.EquippedRelicName() or SS.T("ui_none")), SS.db.combat, SS.EffectiveMode(), tostring(SS.nRules))
    if SS.conflict then line = "|cFFFF6666" .. SS.T("ui_dormant") .. "|r   " .. line end
    t.line:SetText(line)
end

function UI.RefreshSettings(t)
    t.scaleLabel:SetText(SS.T("ui_scale"))
    t.scaleValue:SetText(string_format("%.1f", SS.db.indicator.scale))
    t.modesHelp:SetText(SS.T("ui_modes_help"))
end

function UI.RefreshProfiles(t)
    t.h1:SetText(SS.T("ui_p_specs"))
    t.h2:SetText(SS.T("ui_p_named"))
    t.nameHint:SetText(SS.T("ui_p_name"))
    local avail = SS.SpecsAvailable()
    if avail then
        local spec, src = SS.CurrentSpec()
        t.detected:SetText(SS.T("ui_p_detected", SS.SpecName(spec), src and SS.T("src_" .. src) or "?"))
        t.noSpec:SetText("")
    else
        t.detected:SetText("")
        t.noSpec:SetText(SS.T("ui_p_nospec"))
    end
    for i = 1, getn(SS.SPEC_ORDER) do
        local sp = SS.SPEC_ORDER[i]
        if avail then
            t.specName[i]:SetText(SS.SpecName(sp))
            local txt
            if sp == "NECRO" then
                txt = SS.T(SS.SlotIsPreset("NECRO") and "ui_p_preset" or "ui_p_modified")
            else
                txt = SS.db.specProfiles[sp] and SS.T("ui_p_saved") or SS.T("ui_p_empty")
            end
            if SS.db.lastSpec == sp then txt = txt .. "  " .. SS.T("ui_p_current") end
            t.specState[i]:SetText(txt)
        else
            t.specName[i]:SetText("")
            t.specState[i]:SetText("")
        end
    end
    if avail and SS.db.necroSig then
        t.necroSig:SetText("|cFF66FF66" .. SS.T("necro_sig", SS.NecroSigText(), SS.db.necroTol) .. "|r")
    elseif avail then
        t.necroSig:SetText("|cFFFFAA00" .. SS.T("necro_sig_none") .. "|r")
    else
        t.necroSig:SetText("")
    end
    t.tolText:SetText(avail and SS.T("ui_nc_tol", SS.db.necroTol) or "")
    local sel = UI.SelectedProfile()
    t.selText:SetText(sel or SS.T("nothing"))
end

function UI.RefreshShare(t)
    t.help:SetText(SS.T("ui_s_help"))
    if UI.shareMsg then
        t.msg:SetText((UI.shareOk and "|cFF66FF66" or "|cFFFF6666") .. UI.shareMsg .. "|r")
    else
        t.msg:SetText("")
    end
end

function UI.RefreshDiag(t)
    t.hint:SetText(SS.T("ui_d_hint"))
    t.out:SetText(UI.DiagText())
end

-- header (title, version, state pill), profile bar (profile in use lit), tab highlight
function UI.RefreshChrome(f)
    f.title:SetText(SS.T("ui_title"))
    f.version:SetText(SS.T("ui_version", SS.version))
    local key = SS.StateKey()
    f.stateText:SetText(SS.T("d_state_" .. key))
    if key == "active" then
        UI.SetSolid(f.pill, { 0.2, 0.9, 0.3 })
        UI.Color(f.stateText, { 0.5, 1, 0.55 })
    elseif key == "off" then
        UI.SetSolid(f.pill, { 0.9, 0.2, 0.2 })
        UI.Color(f.stateText, { 1, 0.45, 0.45 })
    else
        UI.SetSolid(f.pill, { 0.6, 0.6, 0.6 })
        UI.Color(f.stateText, { 0.75, 0.75, 0.75 })
    end
    local avail = SS.SpecsAvailable()
    f.barLabel:SetText(avail and SS.T("ui_bar_label") or "")
    for i = 1, getn(UI.bar) do
        local b = UI.bar[i]
        local sp = b.spec
        if avail then
            b:Show()
            local name = SS.SpecName(sp)
            if SS.db.lastSpec == sp then
                b:SetText(UI.Tint(name, UI.GOLD))
                UI.ShowIf(b.glow, true)
            elseif SS.db.specProfiles[sp] then
                b:SetText(name)
                UI.ShowIf(b.glow, false)
            else
                b:SetText(UI.Tint(name, { 0.55, 0.55, 0.55 }))
                UI.ShowIf(b.glow, false)
            end
        else
            b:Hide()
        end
    end
    for i = 1, getn(UI.TABS) do
        local b = UI.tabButtons[i]
        local name = SS.T("ui_tab_" .. UI.TABS[i])
        if i == UI.tab then
            b:SetText(UI.Tint(name, UI.GOLD))
            UI.tabs[i]:Show()
        else
            b:SetText(name)
            UI.tabs[i]:Hide()
        end
        UI.ShowIf(b.glow, i == UI.tab)
    end
end

function UI.RefreshInner()
    local f = UI.frame
    UI.RefreshChrome(f)
    local avail = SS.SpecsAvailable()
    for i = 1, getn(UI.CHECKS) do
        local d = UI.CHECKS[i]
        d.widget:SetChecked(d.get() and 1 or nil)
        d.widget.label:SetText(SS.T(d.text))
        if d.specOnly then
            if avail then d.widget:Show() else d.widget:Hide() end
            if avail then d.widget.label:Show() else d.widget.label:Hide() end
        end
    end
    for i = 1, getn(UI.BUTTONS) do
        local d = UI.BUTTONS[i]
        if d.specOnly then
            if avail then d.widget:Show() else d.widget:Hide() end
        end
        local txt = d.text()
        if d.confirm and UI.ConfirmActive(d.id) then txt = "|cFFFFFF00" .. SS.T("ui_confirm") .. "|r" end
        d.widget:SetText(txt)
    end
    local t = UI.tabs[UI.tab]
    if UI.tab == 1 then
        UI.RefreshRules(t)
    elseif UI.tab == 2 then
        UI.RefreshSettings(t)
    elseif UI.tab == 3 then
        UI.RefreshProfiles(t)
    elseif UI.tab == 4 then
        UI.RefreshShare(t)
    else
        UI.RefreshDiag(t)
    end
end

function UI.Refresh()
    local f = UI.frame
    if not f or not f:IsShown() then return end
    local ok, err = pcall(UI.RefreshInner)
    if not ok then UI.Err(err) end
end

function UI.SetTab(n)
    if type(n) ~= "number" or n < 1 or n > getn(UI.TABS) then return end
    UI.tab = n
    UI.State().tab = n
    UI.confirmId = nil
    if n == 5 and getn(UI.diagLines or {}) == 0 then UI.Capture(SS.cmds.status) end
    UI.Refresh()
end

-- ---------------------------------------------------------------- open / close
function UI.Open()
    if not SS.db then SS.InitDB() end
    local f = UI.Build()
    f:Show()
    UI.Refresh()
end

function UI.Toggle()
    if UI.frame and UI.frame:IsShown() then
        UI.frame:Hide()
    else
        UI.Open()
    end
end

-- /ssw, /ssw menu : never raises, a UI failure only prints a message (casting and swapping do not depend on the window)
local function CmdMenu(rest)
    local ok, err = pcall(UI.Toggle)
    if not ok then
        if UI.frame then UI.frame:Hide() end
        UI.frame = nil
        UI.Err(err)
    end
end
SS.cmds.menu = CmdMenu
SS.cmds.ui = CmdMenu
SS.cmds.config = CmdMenu
