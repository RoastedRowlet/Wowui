-- EXBoss is the sole SavedVariables owner for its business state and all
-- display-module DB tables consumed through ExwindCore's rendering contracts.
_G.EXBOSS12S2 = type(_G.EXBOSS12S2) == "table" and _G.EXBOSS12S2 or {}

local tools = _G.ExwindTools
if not tools or type(tools.RegisterAddonModuleStorage) ~= "function" then
    error("EXBoss storage requires ExwindCore module DB routing", 2)
end

tools:RegisterAddonModuleStorage("EXBOSS", _G.EXBOSS12S2, false, { "ExBoss." })

-- Convert before any display module merges its defaults.  The old general
-- choice is the sole first-load authority; module enabled leaves are retained.
_G.ExBoss = _G.ExBoss or {}
ExBoss.DisplayPolicy = ExBoss.DisplayPolicy or {}
function ExBoss.DisplayPolicy.InitializeTimelineBars(general)
    if type(general.timelineBars) == "table"
        and type(general.timelineBars.bun) == "boolean"
        and type(general.timelineBars.timer) == "boolean" then return end
    if general.timelineBars ~= nil then
        if general.legacyTimelineBars == nil then
            general.legacyTimelineBars = general.timelineBars
        else
            general.legacyTimelineBars = {
                timelineBars = general.timelineBars,
                previous = general.legacyTimelineBars,
            }
        end
    end
    local mode = tostring(general.barDisplayMode or ""):lower()
    if mode ~= "bun" and mode ~= "timer" and mode ~= "both" and mode ~= "none" then
        mode = "bun"
    end
    general.timelineBars = {
        bun = mode == "bun" or mode == "both",
        timer = mode == "timer" or mode == "both",
    }
end

local root = _G.EXBOSS12S2
root.ui = root.ui or {}
root.ui.general = root.ui.general or {}
ExBoss.DisplayPolicy.InitializeTimelineBars(root.ui.general)

