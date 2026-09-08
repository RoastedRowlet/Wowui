-- ExwindTools is the sole SavedVariables owner for all Tools module settings.
-- Core is loaded first, so binding must happen here, after EXTOOLS12S2 itself
-- has been restored by the client and before any Tools module is executed.
_G.EXTOOLS12S2 = type(_G.EXTOOLS12S2) == "table" and _G.EXTOOLS12S2 or {}

local tools = _G.ExwindTools
if not tools or type(tools.RegisterAddonModuleStorage) ~= "function" then
    error("ExwindTools storage requires ExwindCore module DB routing", 2)
end

tools:RegisterAddonModuleStorage("TOOLS", _G.EXTOOLS12S2, true, {
    "ExTools.", "ExUnitFrame.", "ExClass.", "ExM+", "ExPTR.",
})
