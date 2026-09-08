-- EXBoss is the sole SavedVariables owner for its business state and all
-- display-module DB tables consumed through ExwindCore's rendering contracts.
_G.EXBOSS12S2 = type(_G.EXBOSS12S2) == "table" and _G.EXBOSS12S2 or {}

local tools = _G.ExwindTools
if not tools or type(tools.RegisterAddonModuleStorage) ~= "function" then
    error("EXBoss storage requires ExwindCore module DB routing", 2)
end

tools:RegisterAddonModuleStorage("EXBOSS", _G.EXBOSS12S2, false, { "ExBoss." })

