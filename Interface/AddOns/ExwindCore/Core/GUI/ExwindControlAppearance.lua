-- Compatibility facade for the former opt-in appearance layer.
-- The shared modern painter and palette now live in ExwindGUI.lua and are the
-- default for every normal constructor. These aliases intentionally reuse the
-- same constructors and pools; there is no showcase-only or flat-only skin.
local UI = _G.ExwindTools and _G.ExwindTools.UI
if not UI then return end

local modernAPI = setmetatable({ _requestedAppearance = "modern" }, { __index = UI })
for _, suffix in ipairs({
    "Button", "PicButton", "EditBox", "Dropdown", "MultiSelectDropdown",
    "LSMDropdown", "LSMTextureDropdown", "LSMSoundDropdown", "Checkbox",
    "Slider", "Header", "ColorButton",
}) do
    local original = UI["Create" .. suffix]
    if type(original) == "function" then
        UI["Create" .. suffix] = function(self, parent, ...)
            local frame = original(self, parent, ...)
            return UI:ApplyControlAppearance(frame)
        end
        UI["CreateFlat" .. suffix] = function(_, parent, ...)
            return UI["Create" .. suffix](modernAPI, parent, ...)
        end
        UI["CreateModern" .. suffix] = UI["CreateFlat" .. suffix]
    end
end
