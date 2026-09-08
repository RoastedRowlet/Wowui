local addonName, addonTable = ...
local ExwindTools = addonTable or _G.ExwindTools
if not ExwindTools then
    return
end

local LibStub = _G.LibStub

ExwindTools.Media = ExwindTools.Media or {}

local BORDER_PRESET_SIZES = {
    ["EX_Default"] = 1,
}

local BORDER_PRESETS = {
    { name = "EX_Default", path = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_Default.tga" },
    { name = "EX_WhiteBorder", path = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_WhiteBorder.tga" },
}

-- LibSharedMedia only exposes border/background/statusbar texture classes.  The
-- statusbar entries below intentionally provide distinct white assets for
-- foreground and generic material consumers, while retaining stable EX names
-- for profile storage.
local MEDIA_PRESETS = {
    border = BORDER_PRESETS,
    statusbar = {
        { name = "EX_WhiteForeground", path = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_WhiteForeground.tga" },
        { name = "EX_WhiteTexture", path = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_WhiteTexture.tga" },
    },
    background = {
        { name = "EX_WhiteBackground", path = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_WhiteBackground.tga" },
    },
}

ExwindTools.Media.BorderPresetSizes = BORDER_PRESET_SIZES
ExwindTools.Media.BorderPresets = BORDER_PRESETS

function ExwindTools.GetBorderPresetSize(textureName)
    return BORDER_PRESET_SIZES[tostring(textureName or "")]
end

local function RegisterMediaPresets()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not lsm or ExwindTools.Media._mediaPresetsRegistered then
        return
    end

    for mediaType, presets in pairs(MEDIA_PRESETS) do
        for _, preset in ipairs(presets) do
            lsm:Register(mediaType, preset.name, preset.path)
        end
    end

    ExwindTools.Media._mediaPresetsRegistered = true
end

RegisterMediaPresets()
