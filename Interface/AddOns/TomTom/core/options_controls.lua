--[[--------------------------------------------------------------------------
--  TomTom by Cladhaire <cladhaire@gmail.com>
--
--  All Rights Reserved
----------------------------------------------------------------------------]]

-- Custom rows for the Blizzard settings list: a color swatch that can carry
-- opacity, and a text row with an optional image. The row templates are in
-- TomTom.xml. The settings pages use these functions; nothing here builds a
-- page.

local addonName, addon = ...

-- Internal helpers that the TomTom files share. Not part of the public API.
addon.private = addon.private or {}
local private = addon.private

--[[--------------------------------------------------------------------------
--  Colors
----------------------------------------------------------------------------]]

-- The profile keeps a color as {r, g, b, a}. A setting value must be a
-- boolean, a number or a string, so the setting keeps "AARRGGBB", the format
-- that CreateColorFromHexString reads.
local function ColorToHex(color)
    local function byte(v) return math.floor((v or 1) * 255 + 0.5) end
    return string.format("%02X%02X%02X%02X", byte(color[4]), byte(color[1]), byte(color[2]), byte(color[3]))
end

local function HexToColor(hex)
    local a, r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)(%x%x)$")
    return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, tonumber(a, 16) / 255 }
end

private.ColorToHex = ColorToHex
private.HexToColor = HexToColor

--[[--------------------------------------------------------------------------
--  Settings
----------------------------------------------------------------------------]]

-- The settings panel resets only the settings in its registry, also from
-- other addons' pages ("Defaults -> All Settings"). A proxy setting made
-- directly from ProxySettingMixin stays out of that registry. Its rows and
-- value-changed callbacks still work, because both find a setting by its
-- variable name in SettingsCallbackRegistry. If the mixin goes away, normal
-- registration in `category` is the fallback.
function private.CreateUnregisteredSetting(category, variable, varType, name, default, getValue, setValue)
    if ProxySettingMixin and CreateAndInitFromMixin then
        return CreateAndInitFromMixin(ProxySettingMixin, name, variable, varType, default, getValue, setValue)
    end
    return Settings.RegisterProxySetting(category, variable, varType, name, default, getValue, setValue)
end

--[[--------------------------------------------------------------------------
--  Color swatch
----------------------------------------------------------------------------]]

TomTomSettingsColorSwatchControlMixin = CreateFromMixins(SettingsColorSwatchControlMixin)

function TomTomSettingsColorSwatchControlMixin:Init(initializer)
    SettingsColorSwatchControlMixin.Init(self, initializer)

    local setting = self:GetSetting()
    local hasOpacity = initializer:GetData().hasOpacity
    local swatch = self.ColorSwatch

    -- Replaces the RGB-only handler that Blizzard's Init just set.
    swatch:SetScript("OnClick", function()
        local previous = setting:GetValue()
        local color = HexToColor(previous)

        -- Without the opacity slider, GetColorAlpha can return the alpha of
        -- an earlier picker session, so the alpha of the value stays.
        local function Apply()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = hasOpacity and ColorPickerFrame:GetColorAlpha() or color[4]
            setting:SetValue(ColorToHex({ r, g, b, a }))
        end

        ColorPickerFrame:SetupColorPickerAndShow({
            swatch = swatch,
            r = color[1], g = color[2], b = color[3],
            opacity = hasOpacity and color[4] or nil,
            hasOpacity = hasOpacity,
            swatchFunc = Apply,
            opacityFunc = hasOpacity and Apply or nil,
            cancelFunc = function()
                setting:SetValue(previous)
            end,
        })
    end)

    self:SetValue(setting:GetValue())
end

function TomTomSettingsColorSwatchControlMixin:SetValue(value)
    local color = HexToColor(value)
    self.ColorSwatch.Color:SetVertexColor(color[1], color[2], color[3])
    self.ColorSwatch.Color:SetAlpha(color[4])
end

-- With hasOpacity, the color picker shows its opacity slider and the alpha
-- goes into the setting value.
function private.CreateColorInitializer(setting, tooltip, hasOpacity)
    local initializer = Settings.CreateControlInitializer("TomTomSettingsColorSwatchControlTemplate", setting, nil, tooltip)
    initializer:GetData().hasOpacity = hasOpacity and true or false
    return initializer
end

--[[--------------------------------------------------------------------------
--  Text row: wrapped text with an optional image to its left
----------------------------------------------------------------------------]]

local LEFT, RIGHT, PAD, GAP = 37, 20, 6, 10

-- GetExtent runs before the row frame exists, so the height comes from a
-- shown, off-screen font string with the same font and width.
local measureFrame = CreateFrame("Frame", nil, UIParent)
measureFrame:SetSize(1, 1)
measureFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -100, -100)
local measure = measureFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
measure:SetJustifyH("LEFT")

local function GetRowWidth()
    local list = SettingsPanel and SettingsPanel.Container and SettingsPanel.Container.SettingsList
    local width = list and list.ScrollBox and list.ScrollBox:GetWidth() or 0
    -- The list view has 25 px of left padding.
    return width > 0 and (width - 25) or 560
end

local function ResolveRow(data)
    local image = data.imageFunc and data.imageFunc() or data.image
    local text = data.textFunc and data.textFunc() or data.text or ""
    return image, text
end

local function MeasureRow(data, indent)
    local image, text = ResolveRow(data)
    local textWidth = GetRowWidth() - LEFT - indent - RIGHT - (image and (image.width + GAP) or 0)
    measure:SetWidth(textWidth)
    measure:SetText(text)
    local height = math.max(measure:GetStringHeight(), image and image.height or 0)
    return math.ceil(height + PAD * 2)
end

TomTomSettingsTextInitializerMixin = CreateFromMixins(SettingsListElementInitializer)

function TomTomSettingsTextInitializerMixin:GetExtent()
    return MeasureRow(self:GetData(), self:GetIndent())
end

TomTomSettingsTextRowMixin = {}

function TomTomSettingsTextRowMixin:Init(initializer)
    self.initializer = initializer
    self.cbrHandles = self.cbrHandles or Settings.CreateCallbackHandleContainer()

    local data = initializer:GetData()
    for _, variable in ipairs(data.watchVariables or {}) do
        self.cbrHandles:SetOnValueChangedCallback(variable, self.Refresh, self)
    end

    local parent = initializer:GetParentInitializer()
    local parentSetting = parent and parent.GetSetting and parent:GetSetting()
    if parentSetting then
        self.cbrHandles:SetOnValueChangedCallback(parentSetting:GetVariable(), self.Refresh, self)
    end

    self:Refresh()
end

function TomTomSettingsTextRowMixin:Release()
    if self.cbrHandles then
        self.cbrHandles:Unregister()
    end
    self.initializer = nil
end

function TomTomSettingsTextRowMixin:Refresh()
    local initializer = self.initializer
    if not initializer then return end

    local image, text = ResolveRow(initializer:GetData())
    local indent = LEFT + initializer:GetIndent()

    self.Image:ClearAllPoints()
    self.Text:ClearAllPoints()
    if image then
        self.Image:SetTexture(image.texture)
        self.Image:SetTexCoord(unpack(image.coords or { 0, 1, 0, 1 }))
        self.Image:SetSize(image.width, image.height)
        self.Image:SetPoint("TOPLEFT", indent, -PAD)
        self.Image:Show()
        self.Text:SetPoint("TOPLEFT", self.Image, "TOPRIGHT", GAP, 0)
    else
        self.Image:Hide()
        self.Text:SetPoint("TOPLEFT", indent, -PAD)
    end
    self.Text:SetPoint("RIGHT", -RIGHT, 0)
    self.Text:SetText(text)

    local enabled = initializer:EvaluateModifyPredicates()
    self.Text:SetAlpha(enabled and 1 or 0.5)
    self.Image:SetDesaturated(not enabled)
end

-- data: text or textFunc; optional image or imageFunc, which gives
-- {texture, coords, width, height}; optional watchVariables, a list of
-- setting variables that refresh the row when they change.
function private.CreateTextInitializer(data)
    local initializer = CreateFromMixins(TomTomSettingsTextInitializerMixin)
    initializer:Init("TomTomSettingsTextRowTemplate", data)
    return initializer
end
