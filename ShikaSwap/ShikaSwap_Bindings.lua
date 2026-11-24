-- ShikaSwap_Bindings.lua : key binding labels (Esc > Key Bindings > ShikaSwap) and the actions Bindings.xml calls.
-- The labels are plain globals read by the client when the bindings window opens ; the language follows the game client (frFR / other).
-- Lua 5.0 : no '#', no string.match, no '...'.

ShikaSwap = ShikaSwap or {}
local SS = ShikaSwap

local fr = (GetLocale and GetLocale() == "frFR")
BINDING_HEADER_SHIKASWAP = "ShikaSwap"
BINDING_NAME_SHIKASWAP_MENU = fr and "Ouvrir / fermer le menu" or "Open / close the menu"
BINDING_NAME_SHIKASWAP_TOGGLE = fr and "Activer / désactiver l'addon" or "Enable / disable the addon"
BINDING_NAME_SHIKASWAP_MODE = fr and "Changer le mode en combat" or "Cycle the combat mode"

-- called by Bindings.xml ; never raises (a key press must not produce a Lua error popup)
function SS.Bind(action)
    local ok, err = pcall(function()
        if not SS.db then SS.InitDB() end
        if action == "menu" then
            SS.cmds.menu()
        elseif action == "toggle" then
            if SS.db.enabled then SS.cmds.off() else SS.cmds.on() end
        elseif action == "mode" then
            SS.NextMode()
        end
        if SS.UI and SS.UI.Refresh then SS.UI.Refresh() end
    end)
    if not ok then SS.lastError = "bind: " .. tostring(err) end
end
