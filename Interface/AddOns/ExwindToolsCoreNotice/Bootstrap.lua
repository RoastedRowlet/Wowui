local PRODUCT_ADDON = "ExwindTools"
local PRODUCT_NAME = "ExwindTools"
local CORE_ADDON = "ExwindCore"

local function IsProductEnabled()
    return C_AddOns.DoesAddOnExist(PRODUCT_ADDON)
        and C_AddOns.GetAddOnEnableState(PRODUCT_ADDON) > Enum.AddOnEnableState.None
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not C_AddOns.IsAddOnLoaded(CORE_ADDON) and IsProductEnabled() then
        _G.EXWIND_CORE_DEPENDENCY_NOTICE:RegisterProduct(PRODUCT_ADDON, PRODUCT_NAME)
    end
end)
