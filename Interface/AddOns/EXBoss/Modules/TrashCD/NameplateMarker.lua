---@diagnostic disable: undefined-global, undefined-field

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}
local ExwindTools = _G.ExwindTools
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

local Mod = ExBoss.TrashCD.NameplateMarker or {}
ExBoss.TrashCD.NameplateMarker = Mod
ExBoss.Trash.NameplateMarker = Mod
local BorderUtil = ExBoss.BorderUtil

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if LSM and LSM.Register and not LSM:IsValid("border", "Square Full White") then
    LSM:Register("border", "Square Full White", "Interface\\Buttons\\WHITE8X8")
end

local OFFSET_Y = 18
local FONT_PATH = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ICON_SIZE = 25
local ICON_GAP = 2
local ICON_CENTER_GAP = 8
local ICON_PREWARM_COUNT = 15
local NAMEPLATE_ICON_POOL = "ExBoss_TrashCDNameplateIcon"
local READY_BORDER_DEFAULT = { enabled = true, r = 0.20, g = 0.85, b = 0.20, a = 1 }
local framesByUnit = {}

local cachedAddonType = nil

local function GetNameplateAddonType()
    if cachedAddonType then return cachedAddonType end
    local function loaded(name)
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
            return C_AddOns.IsAddOnLoaded(name) == true
        end
        return IsAddOnLoaded and IsAddOnLoaded(name) == true
    end
    if loaded("Platynator") then
        cachedAddonType = "platynator"
    elseif loaded("EllesmereUINameplates") then
        cachedAddonType = "ellesmere"
    elseif loaded("PlateColor") then
        cachedAddonType = "platecolor"
    elseif loaded("Plater") then
        cachedAddonType = "plater"
    else
        cachedAddonType = "default"
    end
    return cachedAddonType
end

local function GetBorderTexturePath(name)
    local key = tostring(name or "")
    if key == "" or key == "None" then
        return nil
    end
    if LSM and type(LSM.Fetch) == "function" then
        local path = LSM:Fetch("border", key, true)
        if path and path ~= "" then
            return path
        end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

local function ApplyIconBorder(icon, cfg, ready, readyCfg)
    local border = icon and icon.border
    if not border then
        return
    end
    local texture = cfg and cfg.show == true and GetBorderTexturePath(cfg.texture) or nil
    if not texture then
        border:Hide()
        return
    end
    local padding = tonumber(cfg.padding) or 0
    local size = math.max(1, tonumber(cfg.size) or 1)
    border:SetFrameLevel(icon:GetFrameLevel() + 1)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -padding, padding)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", padding, -padding)
    if issecretvalue and (issecretvalue(border:GetWidth()) or issecretvalue(border:GetHeight())) then
        if border.SetBackdrop then
            border:SetBackdrop(nil)
        end
        border:Hide()
        return
    end
    border:SetBackdrop({
        edgeFile = texture,
        edgeSize = size,
    })
    if ready == true and type(readyCfg) == "table" and readyCfg.enabled == true then
        border:SetBackdropBorderColor(readyCfg.r or 0, readyCfg.g or 0, readyCfg.b or 0, readyCfg.a or 1)
    else
        border:SetBackdropBorderColor(cfg.r or 0, cfg.g or 0, cfg.b or 0, cfg.a or 1)
    end
    border:Show()
end

local function GetStore()
    return ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Store or nil
end

local function GetIconLayout(runtimeSettings)
    local Store = GetStore()
    local enabled = true
    local reverse = false
    local width = ICON_SIZE
    local height = ICON_SIZE
    local offsetX, offsetY = 6, 0
    if Store and type(Store.GetNameplateIconLayout) == "function" then
        enabled, width, height, offsetX, offsetY, reverse = Store.GetNameplateIconLayout(runtimeSettings)
    else
        if Store and type(Store.GetNameplateIconSize) == "function" then
            width = tonumber(Store.GetNameplateIconSize(runtimeSettings)) or width
            height = width
        end
        if Store and type(Store.GetNameplateOffset) == "function" then
            offsetX, offsetY = Store.GetNameplateOffset(runtimeSettings)
        end
    end
    width = math.max(10, math.min(300, tonumber(width) or ICON_SIZE))
    height = math.max(10, math.min(300, tonumber(height) or width))
    offsetX = math.max(-1000, math.min(1000, tonumber(offsetX) or 6))
    offsetY = math.max(-1000, math.min(1000, tonumber(offsetY) or 0))
    return enabled ~= false, width, height, offsetX, offsetY, reverse == true
end

local function GetIconSpacing(runtimeSettings)
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconSpacing) == "function" then
        return Store.GetNameplateIconSpacing(runtimeSettings)
    end
    return ICON_GAP
end

local function GetIconHideAboveSeconds(runtimeSettings)
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconHideAboveSeconds) == "function" then
        return Store.GetNameplateIconHideAboveSeconds(runtimeSettings)
    end
    return 0
end

local function GetBorderConfig(runtimeSettings)
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconBorder) == "function" then
        return Store.GetNameplateIconBorder(runtimeSettings)
    end
    return {
        show = true,
        texture = "EX_WhiteBorder",
        size = 1,
        padding = 0,
        r = 0, g = 0, b = 0, a = 1,
    }
end

local function GetReadyBorderConfig(runtimeSettings)
    local Store = GetStore()
    if Store and type(Store.GetNameplateReadyBorder) == "function" then
        return Store.GetNameplateReadyBorder(runtimeSettings)
    end
    return READY_BORDER_DEFAULT
end

local function GetTextLayout(runtimeSettings)
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconTextLayout) == "function" then
        return Store.GetNameplateIconTextLayout(runtimeSettings)
    end
    return {
        r = 1, g = 1, b = 1, a = 1,
        size = 15,
        font = "",
        outline = "OUTLINE",
        x = 0, y = 0,
        shadow = true,
        shadowX = 1,
        shadowY = -1,
    }
end

local function GetIconStrata(runtimeSettings)
    local Store = GetStore()
    if Store and type(Store.GetNameplateIconStrata) == "function" then
        return Store.GetNameplateIconStrata(runtimeSettings)
    end
    return "DIALOG"
end

local function ApplyFrameStrata(frame, strata)
    if not frame then
        return
    end
    local value = tostring(strata or "DIALOG"):upper()
    frame:SetFrameStrata(value)
    if frame.SetFixedFrameStrata then
        frame:SetFixedFrameStrata(true)
    end
end

local function GetNameplate(unit)
    local api = _G.C_NamePlate
    if type(api) == "table" and type(api.GetNamePlateForUnit) == "function" then
        local plate = api.GetNamePlateForUnit(unit)
        if plate then
            return plate
        end
    end
    local driver = _G.NamePlateDriverFrame
    if driver and type(driver.GetNamePlateForUnit) == "function" then
        local plate = driver:GetNamePlateForUnit(unit)
        if plate then
            return plate
        end
    end
    return nil
end

local function IsUsableAnchorCandidate(obj, plate)
    if not obj or type(obj.GetObjectType) ~= "function" then
        return false
    end
    if obj.IsForbidden and obj:IsForbidden() then
        return false
    end
    if obj.IsVisible and not obj:IsVisible() then
        return false
    end

    local current = obj
    for _ = 1, 8 do
        if not current or type(current.GetParent) ~= "function" then
            break
        end
        current = current:GetParent()
        if not current then
            break
        end
        if current == plate or current == UIParent or current == WorldFrame then
            return true
        end
        if current.IsForbidden and current:IsForbidden() then
            return false
        end
        if current.IsShown and not current:IsShown() then
            return false
        end
    end

    return true
end

local function ResolvePlateAnchorTarget(plate, unit)
    if type(plate) ~= "table" then
        return nil
    end

    -- Native path is owned by EXCORE.  It returns Blizzard's own full health
    -- bar container, which is the correct geometry for side decorations.
    -- Third-party nameplate add-ons intentionally return no native anchor and
    -- continue through their existing adapter/fallback paths below.
    local EXUI = ExwindTools and ExwindTools.UI
    if EXUI and type(EXUI.GetBlizzardNameplateAnchor) == "function" then
        local native = EXUI:GetBlizzardNameplateAnchor(unit)
        if native and native.plate == plate and native.container then
            return native.container
        end
    end

    local addonType = GetNameplateAddonType()

    if addonType == "platynator" then
        if type(plate.GetChildren) == "function" then
            local children = { plate:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if IsUsableAnchorCandidate(child, plate) and child.widgets and child.AurasManager then
                    if type(child.GetChildren) == "function" then
                        local widgets = { child:GetChildren() }
                        for j = 1, #widgets do
                            local widget = widgets[j]
                            local details = widget and widget.details
                            if IsUsableAnchorCandidate(widget, plate) and type(details) == "table" and details.kind == "health" and widget.statusBar then
                                return widget
                            end
                        end
                    end
                    return child
                end
            end
        end

    elseif addonType == "plater" then
        -- Plater maintains this frame itself after every nameplate layout pass:
        -- it is parented and edge-anchored to the live health bar.  Prefer it
        -- over a guessed child so side icons follow Plater's exact bar bounds.
        local anchor = plate.PlaterAnchorFrame
        if IsUsableAnchorCandidate(anchor, plate) then
            return anchor
        end

    elseif addonType == "ellesmere" then
        if type(plate.GetChildren) == "function" then
            local children = { plate:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if child.health and child.unit and IsUsableAnchorCandidate(child.health, plate) then
                    return child.health
                end
            end
        end

    elseif addonType == "platecolor" or addonType == "default" then
        local unitFrame = plate.UnitFrame or plate.unitFrame
        if unitFrame and unitFrame.HealthBarsContainer and IsUsableAnchorCandidate(unitFrame, plate) then
            return unitFrame
        end
    end

    local candidates = {
        plate.unitFrame and plate.unitFrame.healthBar,
        plate.UnitFrame and plate.UnitFrame.healthBar,
        plate.unitFrame and plate.unitFrame.HealthBar,
        plate.UnitFrame and plate.UnitFrame.HealthBar,
        plate.unitFrame,
        plate.UnitFrame,
    }

    for i = 1, #candidates do
        local obj = candidates[i]
        if IsUsableAnchorCandidate(obj, plate) then
            return obj
        end
    end

    return plate
end

local function AnchorUnitFrameToPlate(frame, plate, unit)
    if not (frame and plate) then
        return
    end
    local anchorTarget
    if frame._anchorPlate == plate then
        anchorTarget = frame._anchorTarget
    else
        anchorTarget = ResolvePlateAnchorTarget(plate, unit) or plate
        frame._anchorPlate = plate
        frame._anchorTarget = anchorTarget
    end
    frame:ClearAllPoints()
    if type(frame.SetAllPoints) == "function" then
        frame:SetAllPoints(anchorTarget)
    else
        local width = type(anchorTarget.GetWidth) == "function" and anchorTarget:GetWidth() or nil
        local height = type(anchorTarget.GetHeight) == "function" and anchorTarget:GetHeight() or nil
        if issecretvalue and issecretvalue(width) then
            width = nil
        else
            width = tonumber(width)
        end
        if issecretvalue and issecretvalue(height) then
            height = nil
        else
            height = tonumber(height)
        end
        frame:SetSize(width and width > 0 and width or 120, height and height > 0 and height or 28)
        frame:SetPoint("CENTER", anchorTarget, "CENTER", 0, 0)
    end
end

local function EnsureUnitFrame(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    local frame = framesByUnit[unit]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetPoint("CENTER")
    ApplyFrameStrata(frame, GetIconStrata())
    frame:SetFrameLevel(6200)
    frame:SetFixedFrameLevel(true)
    frame:SetSize(220, 40)
    frame:EnableMouse(false)
    frame:Hide()

    local textWidget = ExwindTools.UI:CreateTextWidget(frame, "trashCDNameplateLabel")
    local fs = textWidget.text
    fs:SetPoint("BOTTOM", frame, "TOP", 0, OFFSET_Y)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetDrawLayer("OVERLAY", 7)
    if fs.SetFont then
        fs:SetFont(FONT_PATH, 14, "OUTLINE")
    end
    fs:SetText("")
    frame.text = fs
    frame.textWidget = textWidget
    frame.leftIcons = {}
    frame.rightIcons = {}
    framesByUnit[unit] = frame
    return frame
end

local function InitNameplateIconStructure(icon)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:EnableMouse(false)

    -- 专用池保留完整复合结构；底层图标、Cooldown、边框和文字仍全部由
    -- EXUI IconWidget 建立，不在业务模块复制一套控件实现。
    local widget = ExwindTools.UI:CreateIconWidget(icon)
    widget:ClearAllPoints()
    widget:SetAllPoints(icon)
    icon.widget = widget

    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(icon)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.04, 0.04, 0.05, 0.92)
    icon.bg = bg

    icon.border = widget.border
    icon.texture = widget.icon
    icon.icon = widget.icon
    icon.cooldown = widget.cooldown
    icon.textOverlay = widget.textLayer
    icon.countWidget = widget.countdownText
    icon.count = widget.countdownText.text
end

do
    local fac = _G.ExwindFactory
    if fac then
        fac:InitPool(NAMEPLATE_ICON_POOL, "Frame", nil, InitNameplateIconStructure)
    end
end

local function AcquireNameplateIcon(owner)
    local fac = _G.ExwindFactory
    if not fac then return nil end
    local icon = fac:Acquire(NAMEPLATE_ICON_POOL, owner)
    local widget = icon.widget
    widget:ApplyStyle({
        icon = {
            width = ICON_SIZE,
            height = ICON_SIZE,
            showIcon = true,
            showBorder = false,
            showCooldown = false,
        },
    })
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    local strata = GetIconStrata()
    ApplyFrameStrata(icon, strata)
    ApplyFrameStrata(widget, strata)
    icon:SetFrameLevel((owner and owner.GetFrameLevel and owner:GetFrameLevel() or 0) + 1)
    widget:SetFrameLevel(icon:GetFrameLevel())

    local bg = icon.bg
    bg:ClearAllPoints()
    bg:SetAllPoints(icon)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.04, 0.04, 0.05, 0.92)
    bg:Show()

    local border = icon.border
    border:SetFrameLevel(icon:GetFrameLevel() + 1)

    local texture = icon.texture
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", 1, -1)
    texture:SetPoint("BOTTOMRIGHT", -1, 1)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.texture = texture

    local cooldown = icon.cooldown
    cooldown:SetFrameLevel(icon:GetFrameLevel() + 1)
    if cooldown.SetDrawEdge then
        cooldown:SetDrawEdge(true)
    end
    if cooldown.SetDrawSwipe then
        cooldown:SetDrawSwipe(true)
    end
    if cooldown.SetReverse then
        cooldown:SetReverse(false)
    end
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(true)
    end
    cooldown.noCooldownCount = true
    cooldown.noOCC = true
    cooldown:Hide()
    icon.cooldown = cooldown

    -- IconWidget 自带的 countdown TextWidget 是小怪 CD 数字的唯一运行时文字来源。
    icon.textOverlay = widget.textLayer
    icon.countWidget = widget.countdownText
    icon.count = icon.countWidget.text
    icon.countWidget:ClearBounds()
    icon.countWidget:SetAnchor("CENTER", icon.textOverlay, "CENTER", 0, 0)
    icon.countWidget:SetText("")
    icon:Hide()

    return icon
end

local function ReleaseNameplateIcon(icon)
    if not icon then return end
    icon:Hide()
    icon:ClearAllPoints()
    if icon.widget and type(icon.widget.ClearCooldown) == "function" then
        icon.widget:ClearCooldown()
    elseif icon.cooldown then
        if type(icon.cooldown.Clear) == "function" then icon.cooldown:Clear() end
        icon.cooldown:Hide()
    end
    if icon.cooldown then
        icon.cooldown:SetScript("OnCooldownDone", nil)
        if icon.cooldown.SetReverse then icon.cooldown:SetReverse(false) end
    end
    if icon.countWidget then icon.countWidget:SetText("") end
    if icon.border then
        if icon.border.SetBackdrop then icon.border:SetBackdrop(nil) end
        icon.border:Hide()
    end
    if icon.texture then
        icon.texture:SetTexture(nil)
    end
    local fac = _G.ExwindFactory
    if fac then
        fac:Release(NAMEPLATE_ICON_POOL, icon)
    else
        icon:Hide()
    end
end

local function EnsureIconFrame(owner, side, index)
    local pool = side == "left" and owner.leftIcons or owner.rightIcons
    local icon = pool[index]
    if icon then
        return icon
    end

    icon = AcquireNameplateIcon(owner)
    pool[index] = icon
    return icon
end

local function HideUnusedIcons(pool, startIndex)
    for i = #pool, startIndex, -1 do
        local icon = pool[i]
        if icon then
            ReleaseNameplateIcon(icon)
        end
        pool[i] = nil
    end
end

function Mod:GetPrewarmTargetCount()
    local Store = GetStore()
    if Store and type(Store.IsEnabled) == "function" and Store.IsEnabled() ~= true then
        return 0
    end
    local runtimeSettings = Store and type(Store.GetRuntimeSettings) == "function"
        and Store.GetRuntimeSettings() or {}
    local iconsEnabled = GetIconLayout(runtimeSettings)
    return iconsEnabled == true and ICON_PREWARM_COUNT or 0
end

function Mod:AcquirePrewarmObject()
    return AcquireNameplateIcon(UIParent)
end

function Mod:ReleasePrewarmObject(icon)
    ReleaseNameplateIcon(icon)
end

local function FormatRemainingText(remaining, ready)
    if ready == true or (tonumber(remaining) or 0) <= 0.05 then
        return ""
    end
    local seconds = math.ceil(math.max(0, tonumber(remaining) or 0))
    return seconds > 0 and tostring(seconds) or ""
end

local function ApplyCooldown(icon, row, reverse, shown)
    if not (icon and icon.cooldown) then
        return
    end
    if shown == false then
        icon.cooldown:Hide()
        return
    end
    if row.ready == true then
        icon.cooldown:Hide()
        return
    end
    local duration = tonumber(row.duration) or 0
    local remaining = tonumber(row.remaining) or 0
    if duration <= 0 or remaining <= 0 then
        icon.cooldown:Hide()
        return
    end
    if icon.cooldown.SetReverse then
        icon.cooldown:SetReverse(reverse == true)
    end
    local startTime = tonumber(row.startTime)
    if not startTime then
        error("TrashCD nameplate cooldown requires Scheduler startTime", 2)
    end
    if not (C_DurationUtil and type(C_DurationUtil.CreateDuration) == "function") then
        error("TrashCD nameplate cooldown requires C_DurationUtil.CreateDuration", 2)
    end
    if type(icon.cooldown.SetCooldownFromDurationObject) ~= "function" then
        error("TrashCD nameplate cooldown requires Cooldown:SetCooldownFromDurationObject", 2)
    end
    local durationObject = C_DurationUtil.CreateDuration()
    -- Scheduler supplies the original startTime.  Recreating the native object
    -- from this stable end time never restarts the cooldown during a marker
    -- refresh; do not replace it with GetTime() + remaining.
    durationObject:SetTimeFromEnd(startTime + duration, duration, 1)
    icon.cooldown:SetCooldownFromDurationObject(durationObject, true)
    icon.cooldown:Show()
end

local function ApplyRuntimeIconAppearance(icon, layout)
    if not (icon and icon.texture) then return end
    layout = type(layout) == "table" and layout or {}
    local texture = icon.texture
    local cropped = layout.enableCrop ~= false
    local left = cropped and (tonumber(layout.cropLeft) or 0.08) or 0
    local right = cropped and (tonumber(layout.cropRight) or 0.92) or 1
    local top = cropped and (tonumber(layout.cropTop) or 0.08) or 0
    local bottom = cropped and (tonumber(layout.cropBottom) or 0.92) or 1
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetAlpha(math.max(0, math.min(1, tonumber(layout.alpha) or 1)))
    texture:SetDesaturated(layout.desaturated == true)
    texture:SetVertexColor(
        tonumber(layout.colorR) or 1,
        tonumber(layout.colorG) or 1,
        tonumber(layout.colorB) or 1,
        tonumber(layout.colorA) or 1
    )
    if texture.SetBlendMode then texture:SetBlendMode(tostring(layout.blendMode or "BLEND")) end
    if texture.SetRotation then texture:SetRotation(math.rad(tonumber(layout.rotation) or 0)) end
end

local function ApplyTextStyle(icon, layout)
    if not (icon and icon.countWidget) then
        return
    end
    layout = type(layout) == "table" and layout or GetTextLayout()
    local anchor = icon.textOverlay or icon
    icon.countWidget:ClearAllPoints()
    icon.countWidget:SetAnchor("CENTER", anchor, "CENTER", tonumber(layout.x) or 0, tonumber(layout.y) or 0)
    icon.countWidget:ApplyStyle({
        font = layout.font,
        size = tonumber(layout.size) or 11,
        outline = tostring(layout.outline or "OUTLINE"),
        r = tonumber(layout.r) or 1,
        g = tonumber(layout.g) or 1,
        b = tonumber(layout.b) or 1,
        a = tonumber(layout.a) or 1,
        shadow = layout.shadow ~= false,
        shadowX = tonumber(layout.shadowX) or 1,
        shadowY = tonumber(layout.shadowY) or -1,
        wordWrap = false,
        maxLines = 1,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
    })
end

-- 姓名版图标没有全局世界锚点：运行时每一组图标都必须依附对应的真实姓名版。
-- 因此此处只交出一份标准 panel 预览快照；假姓名版是 collection decoration，
-- 用来如实表达图标相对姓名版的位置，绝不是第二个 renderer 或可保存的世界 anchor。
local PREVIEW_NAMEPLATE_WIDTH = 220
local PREVIEW_NAMEPLATE_HEIGHT = 28
-- 第一枚与姓名版边缘的间距必须和运行时 ICON_CENTER_GAP 相同；后续图标
-- 则使用用户配置的 nameplateIcon.spacing。
local PREVIEW_ICON_GAP = ICON_CENTER_GAP
local PREVIEW_HEALTH_FILL = 0.70
-- EXCORE/ExwindMedia.lua 注册的 EX_WhiteForeground 状态条预设资源。
-- 预览模型使用其实际路径，不能退回 Blizzard 的 UI-StatusBar。
local EX_WHITE_FOREGROUND_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_WhiteForeground.tga"
local EX_WHITE_BACKGROUND_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Borders\\EX_WhiteBackground.tga"
local PREVIEW_BORDER_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local function PreviewFontStyle(layout)
    layout = type(layout) == "table" and layout or {}
    return {
        font = tostring(layout.font or ""),
        size = tonumber(layout.size) or 15,
        r = tonumber(layout.r) or 1,
        g = tonumber(layout.g) or 1,
        b = tonumber(layout.b) or 1,
        a = tonumber(layout.a) or 1,
        outline = tostring(layout.outline or "OUTLINE"),
        shadow = layout.shadow ~= false,
        shadowX = tonumber(layout.shadowX) or 1,
        shadowY = tonumber(layout.shadowY) or -1,
        justifyH = "CENTER",
        justifyV = "MIDDLE",
        wordWrap = false,
        maxLines = 1,
    }
end

local function PreviewIconAppearance(layout)
    layout = type(layout) == "table" and layout or {}
    return {
        icon = {
            showIcon = layout.showIcon ~= false,
            reverse = layout.reverse == true,
            width = math.max(10, tonumber(layout.width) or ICON_SIZE),
            height = math.max(10, tonumber(layout.height) or ICON_SIZE),
            showBorder = layout.showBorder ~= false,
            borderTexture = tostring(layout.borderTexture or "EX_WhiteBorder"),
            borderColorR = tonumber(layout.borderColorR) or 0,
            borderColorG = tonumber(layout.borderColorG) or 0,
            borderColorB = tonumber(layout.borderColorB) or 0,
            borderColorA = tonumber(layout.borderColorA) or 1,
            borderSize = tonumber(layout.borderSize) or 1,
            borderPadding = tonumber(layout.borderPadding) or 0,
            alpha = tonumber(layout.alpha) or 1,
            desaturated = layout.desaturated == true,
            colorR = tonumber(layout.colorR) or 1,
            colorG = tonumber(layout.colorG) or 1,
            colorB = tonumber(layout.colorB) or 1,
            colorA = tonumber(layout.colorA) or 1,
            blendMode = tostring(layout.blendMode or "BLEND"),
            rotation = tonumber(layout.rotation) or 0,
            enableCrop = layout.enableCrop ~= false,
            cropLeft = tonumber(layout.cropLeft) or 0.08,
            cropRight = tonumber(layout.cropRight) or 0.92,
            cropTop = tonumber(layout.cropTop) or 0.08,
            cropBottom = tonumber(layout.cropBottom) or 0.92,
            showCooldown = layout.showCooldown ~= false,
        },
    }
end

local function PreviewNameFontStyle(name)
    name = type(name) == "table" and name or {}
    local color = type(name.color) == "table" and name.color or {}
    local shadowColor = type(name.shadowColor) == "table" and name.shadowColor or {}
    return {
        font = tostring(name.font or ""), size = tonumber(name.size) or 11,
        r = tonumber(color.r) or 1, g = tonumber(color.g) or 1,
        b = tonumber(color.b) or 1, a = tonumber(color.a) or 1,
        outline = tostring(name.outline or "NONE"), shadow = true,
        shadowX = tonumber(name.shadowX) or 1, shadowY = tonumber(name.shadowY) or -1,
        shadowColorR = tonumber(shadowColor.r) or 0, shadowColorG = tonumber(shadowColor.g) or 0,
        shadowColorB = tonumber(shadowColor.b) or 0, shadowColorA = tonumber(shadowColor.a) or 1,
        justifyH = tostring(name.anchor and name.anchor.justifyH or "CENTER"),
        justifyV = "MIDDLE", wordWrap = false, maxLines = 1,
    }
end

-- 预览名称不是运行时单位资料。它只从 Core 已整理的本地化 NPC 名称池中取一个
-- 当前客户端可见语言的样本，避免在英文/韩文等客户端上固定显示中文占位字。
local previewNPCNamesByLocale = {}
local previewNPCNameSelectionByLocale = {}
local function GetRandomLocalizedPreviewNPCName()
    local locale = type(_G.GetLocale) == "function" and _G.GetLocale() or "enUS"
    locale = type(locale) == "string" and locale or "enUS"
    local selected = previewNPCNameSelectionByLocale[locale]
    if selected then return selected end
    local candidates = previewNPCNamesByLocale[locale]
    if not candidates then
        candidates = {}
        local source = _G.EXDB and _G.EXDB.NPCNameSource
        if type(source) == "table" then
            for _, names in pairs(source) do
                local name = type(names) == "table" and (names[locale] or names.enUS) or nil
                if type(name) == "string" and name ~= "" then
                    candidates[#candidates + 1] = name
                end
            end
        end
        previewNPCNamesByLocale[locale] = candidates
    end
    selected = #candidates > 0 and candidates[math.random(1, #candidates)] or L["敌对怪物预览"]
    -- Deliberately retain the selection for this Lua session: reapplying a
    -- settings preview must never make its sample NPC appear to change.
    previewNPCNameSelectionByLocale[locale] = selected
    return selected
end

local function GetPreviewNameplateStyle(EXUI)
    local previewName = GetRandomLocalizedPreviewNPCName()
    local fallback = {
        backend = "blizzard", width = PREVIEW_NAMEPLATE_WIDTH, height = PREVIEW_NAMEPLATE_HEIGHT,
        texture = EX_WHITE_FOREGROUND_TEXTURE, color = { r = 0.78, g = 0.08, b = 0.08, a = 1 },
        backgroundTexture = EX_WHITE_BACKGROUND_TEXTURE, backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 1 },
        border = {
            texture = PREVIEW_BORDER_TEXTURE,
            color = { r = 0, g = 0, b = 0, a = 1 },
            thickness = 1,
        },
        name = {
            text = previewName,
            anchor = { point = "BOTTOM", relativePoint = "TOP", x = 0, y = 2, justifyH = "CENTER" },
        },
    }
    if not EXUI or type(EXUI.GetThirdPartyNameplatePreviewStyle) ~= "function" then return fallback end
    local thirdParty = EXUI:GetThirdPartyNameplatePreviewStyle()
    if type(thirdParty) ~= "table" then return fallback end
    local name = type(thirdParty.name) == "table" and thirdParty.name or nil
    local anchor = name and type(name.anchor) == "table" and name.anchor or {}
    return {
        backend = tostring(thirdParty.backend or "third-party"),
        width = math.max(1, tonumber(thirdParty.width) or fallback.width),
        height = math.max(1, tonumber(thirdParty.height) or fallback.height),
        texture = type(thirdParty.texture) == "string" and thirdParty.texture or fallback.texture,
        color = type(thirdParty.color) == "table" and thirdParty.color or fallback.color,
        backgroundTexture = type(thirdParty.backgroundTexture) == "string" and thirdParty.backgroundTexture or fallback.backgroundTexture,
        backgroundColor = type(thirdParty.backgroundColor) == "table" and thirdParty.backgroundColor or fallback.backgroundColor,
        -- The settings canvas deliberately does not emulate third-party border
        -- skins.  They are decorative and their geometry differs per addon;
        -- use one stable black 1px outline for every backend instead.
        border = {
            texture = PREVIEW_BORDER_TEXTURE,
            color = { r = 0, g = 0, b = 0, a = 1 },
            thickness = 1,
        },
        name = name and {
            text = previewName,
            font = name.font, size = name.size, color = name.color, outline = name.outline,
            shadowColor = name.shadowColor, shadowX = name.shadowX, shadowY = name.shadowY,
            width = math.max(1, tonumber(name.width) or fallback.width),
            anchor = {
                point = tostring(anchor.point or "BOTTOM"), relativePoint = tostring(anchor.relativePoint or "TOP"),
                relativeElement = "nameplateBackground", x = tonumber(anchor.x) or 0, y = tonumber(anchor.y) or 0,
                justifyH = tostring(anchor.justifyH or "CENTER"),
            },
        } or nil,
    }
end

function Mod:BuildPreview()
    local Store = GetStore()
    local db = Store and type(Store.GetRuntimeSettings) == "function" and Store.GetRuntimeSettings() or {}
    local iconLayout = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
    local textLayout = type(db.nameplateIconText) == "table" and db.nameplateIconText or {}
    local iconWidth = math.max(10, tonumber(iconLayout.width) or ICON_SIZE)
    local iconHeight = math.max(10, tonumber(iconLayout.height) or ICON_SIZE)
    local iconGap = math.max(0, tonumber(iconLayout.spacing) or ICON_GAP)
    local hideAboveSeconds = math.max(0, tonumber(db.hideNameplateIconAboveSeconds) or 0)
    local offsetX = tonumber(iconLayout.x) or 0
    local offsetY = tonumber(iconLayout.y) or 0
    local EXUI = ExwindTools and ExwindTools.UI
    if not EXUI or type(EXUI.SnapshotPreviewData) ~= "function" then
        error("TrashCD nameplate preview requires EXUI standard preview", 2)
    end
    local nameplate = GetPreviewNameplateStyle(EXUI)
    local borderThickness = math.max(0, tonumber(nameplate.border and nameplate.border.thickness) or 0)
    local fillWidth = math.max(1, nameplate.width * PREVIEW_HEALTH_FILL)
    local side = tostring(db.nameplateGrowthSide or "left") == "left" and "left" or "right"
    local direction = side == "left" and -1 or 1
    local iconX = direction * (nameplate.width * 0.5 + PREVIEW_ICON_GAP + iconWidth * 0.5) + offsetX

    return {
        definition = EXUI:SnapshotPreviewData({
            kind = "icon",
            appearance = PreviewIconAppearance(iconLayout),
            layout = { mode = "ABSOLUTE", itemWidth = iconWidth, itemHeight = iconHeight },
            slots = {
                ["core.icon"] = {
                    movable = false,
                    focusable = true,
                    guiTarget = "nameplateIcon",
                    tooltip = L["姓名版图标本体"],
                },
                ["core.time"] = {
                    movable = true,
                    focusable = true,
                    guiTarget = "nameplateIconText",
                    tooltip = L["姓名版图标倒数时间"],
                    anchor = {
                        point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER",
                        x = tonumber(textLayout.x) or 0, y = tonumber(textLayout.y) or 0,
                    },
                    style = PreviewFontStyle(textLayout),
                },
                ["core.stacks"] = { shown = false },
            },
            children = {
                -- 标准图标本体本身永远固定在所属 preview item 中；这个透明声明
                -- 子元素只负责把“图标相对姓名版”的业务坐标转换成 intent，避免
                -- 让标准 renderer 直接修改固定本体或写模块 DB。
                {
                    id = "iconPosition", kind = "texture", movable = true, focusable = true,
                    guiTarget = "nameplateIcon", tooltip = L["姓名版图标位置"],
                    anchor = { point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER", x = 0, y = 0 },
                    width = iconWidth, height = iconHeight,
                },
            },
            collectionDecorations = {
                {
                    id = "nameplateBorder", kind = "texture", layer = "background", movable = false,
                    focusable = false, guiTarget = "nameplateIcon", tooltip = L["模拟姓名版血条边框"],
                    anchor = { point = "CENTER", relativeElement = "collection", relativePoint = "CENTER" },
                    width = nameplate.width + borderThickness * 2, height = nameplate.height + borderThickness * 2,
                },
                {
                    id = "nameplateBackground", kind = "texture", layer = "background", movable = false,
                    focusable = true, guiTarget = "nameplateIcon", tooltip = L["模拟姓名版血条"],
                    anchor = { point = "CENTER", relativeElement = "nameplateBorder", relativePoint = "CENTER" },
                    width = nameplate.width, height = nameplate.height,
                },
                {
                    -- The empty bar is the base. Keep the live fill above it:
                    -- pooled textures at the same layer have no stable sibling
                    -- draw order and could make the fill look dark.
                    id = "nameplate", kind = "texture", layer = "child", movable = false,
                    focusable = false, guiTarget = "nameplateIcon", tooltip = L["模拟姓名版当前血量"],
                    anchor = { point = "LEFT", relativeElement = "nameplateBackground", relativePoint = "LEFT" },
                    width = fillWidth, height = nameplate.height,
                },
                {
                    id = "nameplateName", kind = "text", layer = "child", movable = false,
                    focusable = false, guiTarget = "nameplateIcon", tooltip = L["模拟怪物名称"],
                    anchor = nameplate.name and nameplate.name.anchor
                        or { point = "BOTTOM", relativeElement = "nameplateBackground", relativePoint = "TOP", x = 0, y = 2 },
                    width = nameplate.name and tonumber(nameplate.name.width) or nameplate.width,
                    height = math.max(20, (nameplate.name and tonumber(nameplate.name.size) or 11) + 8),
                    style = PreviewNameFontStyle(nameplate.name),
                },
            },
        }, "TrashCD.nameplatePreviewDefinition"),
        model = EXUI:SnapshotPreviewData({
            items = (function()
                local items, visibleIndex = {}, 0
                for _, sample in ipairs({
                    { id = "trashcd:nameplate-icon:1", icon = 136243, remaining = 7, timeText = "7" },
                    { id = "trashcd:nameplate-icon:2", icon = 136197, remaining = 1, timeText = "1" },
                }) do
                    -- 与运行时同一条规则：0=不隐藏；正数时只显示剩余不超过阈值的图标。
                    if hideAboveSeconds <= 0 or sample.remaining <= hideAboveSeconds then
                        visibleIndex = visibleIndex + 1
                        items[#items + 1] = {
                            itemID = sample.id, type = "custom", name = L["内置冷却"], icon = sample.icon,
                            duration = 15, remaining = sample.remaining, timeText = sample.timeText, order = visibleIndex,
                            position = {
                                x = iconX + direction * (visibleIndex - 1) * (iconWidth + iconGap),
                                y = offsetY,
                            },
                            elements = {
                                iconPosition = {
                                    shown = true, texture = "Interface\\Buttons\\WHITE8X8",
                                    color = { r = 1, g = 1, b = 1, a = 0 },
                                },
                            },
                        }
                    end
                end
                return items
            end)(),
            decorations = {
                nameplateBorder = {
                    shown = borderThickness > 0, texture = nameplate.border.texture, color = nameplate.border.color,
                },
                nameplateBackground = {
                    shown = true, texture = nameplate.backgroundTexture, color = nameplate.backgroundColor,
                },
                nameplate = {
                    shown = true, texture = nameplate.texture, color = nameplate.color, width = fillWidth,
                },
                nameplateName = {
                    shown = nameplate.name ~= nil, text = nameplate.name and nameplate.name.text or "",
                    width = nameplate.name and tonumber(nameplate.name.width) or nameplate.width,
                    height = math.max(20, (nameplate.name and tonumber(nameplate.name.size) or 11) + 8),
                },
            },
        }, "TrashCD.nameplatePreviewModel"),
    }
end

-- =============================================================
-- 设置面板 Slider 实时预览
--
-- 这不是 StandardPreview 的通用 Patch 接口。姓名版模块知道自己只有一张
-- 假姓名版、一个 IconWidget 与一个倒数 TextWidget，因此只公开这组已经
-- materialize 的控件可安全就地修改的字段。它绝不写 Store/User Delta，
-- 也绝不调用 preview:Materialize；正式持久化仍由设置页的 commit 处理。
-- =============================================================
local LIVE_ICON_FIELDS = {
    width = true, height = true, x = true, y = true,
    borderSize = true, borderPadding = true, spacing = true,
}

local LIVE_TEXT_FIELDS = {
    size = true, x = true, y = true,
    shadowX = true, shadowY = true,
}

local function CopyLiveFields(destination, source)
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do destination[key] = value end
end

local function GetLivePreviewState(preview, settings)
    if type(preview._trashCDLiveSettings) == "table" then
        return preview._trashCDLiveSettings
    end

    local Store = GetStore()
    local runtime = Store and type(Store.GetRuntimeSettings) == "function"
        and Store.GetRuntimeSettings() or {}
    settings = type(settings) == "table" and settings or {}
    local state = {
        nameplateGrowthSide = settings.nameplateGrowthSide or runtime.nameplateGrowthSide or "left",
        nameplateIcon = {},
        nameplateIconText = {},
    }
    CopyLiveFields(state.nameplateIcon, runtime.nameplateIcon)
    CopyLiveFields(state.nameplateIcon, settings.nameplateIcon)
    -- spacing 不在拖动/尺寸 live 字段内，但后续图标的起点必须始终读取实际
    -- 配置；否则改第一枚宽度时第二枚会用默认间距重新排列。
    state.nameplateIcon.spacing = tonumber(settings.nameplateIcon and settings.nameplateIcon.spacing)
        or tonumber(runtime.nameplateIcon and runtime.nameplateIcon.spacing)
        or ICON_GAP
    CopyLiveFields(state.nameplateIconText, runtime.nameplateIconText)
    CopyLiveFields(state.nameplateIconText, settings.nameplateIconText)
    preview._trashCDLiveSettings = state
    return state
end

local function GetMaterializedNameplateWidth(preview)
    local collection = preview and preview.collection
    local element = collection and collection.elements and collection.elements.nameplateBackground
    local region = element and element.region
    local width = region and type(region.GetWidth) == "function" and tonumber(region:GetWidth()) or nil
    return width and width > 0 and width or PREVIEW_NAMEPLATE_WIDTH
end

local function ApplyLiveIconPosition(preview, item, state, sampleIndex)
    local layout = state.nameplateIcon
    local side = tostring(state.nameplateGrowthSide or "left") == "left" and "left" or "right"
    local direction = side == "left" and -1 or 1
    local width = math.max(10, tonumber(layout.width) or ICON_SIZE)
    local x = direction * (GetMaterializedNameplateWidth(preview) * 0.5 + PREVIEW_ICON_GAP + width * 0.5)
        + (tonumber(layout.x) or 0)
        + direction * (math.max(1, tonumber(sampleIndex) or 1) - 1)
            * (width + math.max(0, tonumber(layout.spacing) or ICON_GAP))
    local y = tonumber(layout.y) or 0
    item.root.__EXUIStandardPreviewPosition = { x = x, y = y }
    item.root:ClearAllPoints()
    item.root:SetPoint("CENTER", preview.layout, "CENTER", x, y)

    local positionElement = item.elements and item.elements.iconPosition
    if positionElement then
        positionElement.position = { x = 0, y = 0 }
        if positionElement.region then positionElement.region:SetSize(width, math.max(10, tonumber(layout.height) or ICON_SIZE)) end
    end
end

-- 公共窄接口：只允许页面在 Slider live 阶段调用。
-- 返回 false 表示该字段需要在 commit 后按正常路径 Materialize，调用方不能
-- 猜测 StandardPreview/Widget 的内部 Region 来强行修补。
function Mod:ApplyLiveVisual(preview, path, value, settings)
    if type(preview) ~= "table" or type(path) ~= "string" then return false end
    local items = type(preview.items) == "table" and preview.items or nil
    if type(items) ~= "table" or #items == 0 then return false end
    local section, field = path:match("^(nameplateIconText)%.([%w_]+)$")
    if not section then
        section, field = path:match("^(nameplateIcon)%.([%w_]+)$")
    end
    if not section or not field then return false end
    if type(value) ~= "number" then return false end

    local state = GetLivePreviewState(preview, settings)
    if section == "nameplateIcon" then
        if not LIVE_ICON_FIELDS[field] then return false end
        state.nameplateIcon[field] = value

        for sampleIndex, item in ipairs(items) do
            if not (item and item.widget and item.root and item.elements) then return false end
            local iconStyle = item.widget.style or {}
            iconStyle.icon = type(iconStyle.icon) == "table" and iconStyle.icon or {}
            iconStyle.icon.width = math.max(10, tonumber(state.nameplateIcon.width) or ICON_SIZE)
            iconStyle.icon.height = math.max(10, tonumber(state.nameplateIcon.height) or ICON_SIZE)
            iconStyle.icon.borderSize = tonumber(state.nameplateIcon.borderSize) or 1
            iconStyle.icon.borderPadding = tonumber(state.nameplateIcon.borderPadding) or 0
            item.widget:ApplyStyle(iconStyle)
            item.root:SetSize(item.widget:GetWidth(), item.widget:GetHeight())
            ApplyLiveIconPosition(preview, item, state, sampleIndex)
        end
        return true
    end

    if not LIVE_TEXT_FIELDS[field] then return false end
    state.nameplateIconText[field] = value
    for _, item in ipairs(items) do
        if not (item and item.widget and item.root and item.elements) then return false end
        local timeElement = item.elements["core.time"]
        local timeWidget = timeElement and timeElement.text
        if not (timeWidget and type(timeWidget.ApplyStyle) == "function" and type(timeWidget.SetAnchor) == "function") then
            return false
        end
        local style = timeWidget.style or {}
        if field ~= "x" and field ~= "y" then style[field] = value end
        timeWidget:ApplyStyle(style)
        local x = tonumber(state.nameplateIconText.x) or 0
        local y = tonumber(state.nameplateIconText.y) or 0
        timeWidget:SetAnchor("CENTER", item.widget, "CENTER", x, y)
        timeElement.position = { x = x, y = y }
    end
    return true
end

function Mod:ApplyPreviewLayoutIntent(intent)
    if type(intent) ~= "table" or intent.type ~= "elementMoved"
        or type(intent.position) ~= "table" or type(intent.position.x) ~= "number" or type(intent.position.y) ~= "number" then
        error("TrashCD nameplate preview received unsupported layout intent", 2)
    end
    local Store = GetStore()
    if not Store or type(Store.GetRuntimeSettings) ~= "function" or type(Store.SetConfigValue) ~= "function" then
        error("TrashCD nameplate preview Store is unavailable", 2)
    end
    local db = Store.GetRuntimeSettings() or {}
    local writes
    if intent.elementID == "core.time" then
        writes = {
            { "settings", "nameplateIconText", "x", intent.position.x },
            { "settings", "nameplateIconText", "y", intent.position.y },
        }
    elseif intent.elementID == "iconPosition" then
        local iconLayout = type(db.nameplateIcon) == "table" and db.nameplateIcon or {}
        writes = {
            { "settings", "nameplateIcon", "x", (tonumber(iconLayout.x) or 0) + intent.position.x },
            { "settings", "nameplateIcon", "y", (tonumber(iconLayout.y) or 0) + intent.position.y },
        }
    else
        error("TrashCD nameplate preview element is not movable: " .. tostring(intent.elementID), 2)
    end
    for _, write in ipairs(writes) do
        local ok, reason = Store.SetConfigValue({ write[1], write[2], write[3] }, write[4])
        if ok ~= true then
            error("TrashCD nameplate preview write failed: " .. tostring(reason or "unknown error"), 2)
        end
    end
    return true
end

-- 设置页全屏预览必须直接调用正式的 SetUnitTimers(unit, rows)；不能另建测试
-- Frame，否则就不是 Runtime -> NameplateMarker 的同一条显示链。关闭时由
-- Runtime 重套其真实 rows，或在 Runtime 未运行时隐藏这些测试 unit。
local screenPreviewUnits = {}
local screenPreviewEnabled = false

local function ClearScreenNameplatePreview(restoreRuntime)
    local hadPreview = next(screenPreviewUnits) ~= nil
    if restoreRuntime == true and hadPreview then
        local Runtime = ExBoss and ExBoss.TrashCD and ExBoss.TrashCD.Runtime
        if Runtime and type(Runtime.RefreshAllActiveNameplates) == "function" then
            Runtime:RefreshAllActiveNameplates("screen-preview-stop", false)
        else
            for unit in pairs(screenPreviewUnits) do
                Mod.HideUnit(unit)
            end
        end
    end
    screenPreviewUnits = {}
    screenPreviewEnabled = false
end

function Mod:IsScreenNameplatePreviewEnabled()
    return screenPreviewEnabled == true
end

function Mod:SetScreenNameplatePreview(enabled)
    ClearScreenNameplatePreview(enabled ~= true)
    if enabled ~= true then return 0 end

    local Store = GetStore()
    local settings = Store and type(Store.GetRuntimeSettings) == "function" and Store.GetRuntimeSettings() or {}
    local side = tostring(settings.nameplateGrowthSide or "left") == "left" and "left" or "right"
    local now = type(GetTime) == "function" and GetTime() or 0
    local shown, seenUnits = 0, {}
    local function TryShowUnit(unit)
        if type(unit) ~= "string" or seenUnits[unit] then return end
        seenUnits[unit] = true
        -- nameplateN 只涵盖当前屏幕已物化的姓名版；过滤掉友方与玩家本身。
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsUnit("player", unit)
            and GetNameplate(unit) then
            Mod.SetUnitTimers(unit, {
                {
                    spellID = 136243, iconFileID = 136243, side = side,
                    duration = 15, remaining = 7, startTime = now - 8, ready = false,
                },
                {
                    spellID = 136197, iconFileID = 136197, side = side,
                    duration = 15, remaining = 1, startTime = now - 14, ready = false,
                },
            })
            screenPreviewUnits[unit] = true
            shown = shown + 1
        end
    end
    -- 主路径直接读取当前已显示的姓名版；部分姓名版插件不会立即暴露完整的
    -- nameplateN 序号，因此仍保留 token 扫描作为兼容兜底。
    local namePlateAPI = _G.C_NamePlate
    if type(namePlateAPI) == "table" and type(namePlateAPI.GetNamePlates) == "function" then
        for _, plate in ipairs(namePlateAPI.GetNamePlates() or {}) do
            TryShowUnit(plate and (plate.namePlateUnitToken
                or (plate.UnitFrame and plate.UnitFrame.unit)
                or (plate.unitFrame and plate.unitFrame.unit)))
        end
    end
    for index = 1, 40 do
        TryShowUnit("nameplate" .. index)
    end
    screenPreviewEnabled = shown > 0
    return shown
end

function Mod.HideAll()
    ClearScreenNameplatePreview(false)
    for _, frame in pairs(framesByUnit) do
        if frame and frame.text then
            frame.text:SetText("")
            frame:Hide()
            HideUnusedIcons(frame.leftIcons or {}, 1)
            HideUnusedIcons(frame.rightIcons or {}, 1)
        end
    end
end

function Mod.HideUnit(unit)
    if type(unit) ~= "string" then
        return
    end
    local frame = framesByUnit[unit]
    if not frame then
        return
    end
    if frame.text then
        frame.text:SetText("")
    end
    HideUnusedIcons(frame.leftIcons or {}, 1)
    HideUnusedIcons(frame.rightIcons or {}, 1)
    frame:Hide()
end

function Mod.SetUnitText(unit, textValue, recognized, runtimeSettings)
    if type(unit) ~= "string" then
        return
    end
    local plate = GetNameplate(unit)
    if not plate then
        Mod.HideUnit(unit)
        return
    end

    local frame = EnsureUnitFrame(unit)
    if not frame or not frame.text then
        return
    end

    local Store = GetStore()
    runtimeSettings = type(runtimeSettings) == "table" and runtimeSettings
        or (Store and type(Store.GetRuntimeSettings) == "function" and Store.GetRuntimeSettings() or {})
    ApplyFrameStrata(frame, GetIconStrata(runtimeSettings))
    AnchorUnitFrameToPlate(frame, plate, unit)
    if Store and type(Store.IsNameplateNPCIDHidden) == "function" and Store.IsNameplateNPCIDHidden() == true then
        frame.text:SetText("")
        frame:Show()
        return
    end
    local text = tostring(textValue or "???")
    frame.text:SetText(text)
    if string.find(text, "|c", 1, true) then
        frame.text:SetTextColor(1.00, 1.00, 1.00)
    elseif recognized == true then
        frame.text:SetTextColor(0.20, 1.00, 0.35)
    else
        frame.text:SetTextColor(1.00, 0.25, 0.25)
    end
    frame:Show()
end

function Mod.SetUnitTimers(unit, timers, runtimeSettings)
    if type(unit) ~= "string" then
        return
    end
    local plate = GetNameplate(unit)
    local frame = plate and EnsureUnitFrame(unit) or nil
    if not frame then
        Mod.HideUnit(unit)
        return
    end

    local Store = GetStore()
    runtimeSettings = type(runtimeSettings) == "table" and runtimeSettings
        or (Store and type(Store.GetRuntimeSettings) == "function" and Store.GetRuntimeSettings() or {})
    local strata = GetIconStrata(runtimeSettings)
    ApplyFrameStrata(frame, strata)
    AnchorUnitFrameToPlate(frame, plate, unit)

    local iconsEnabled, iconWidth, iconHeight, offsetX, offsetY, reverseCooldown = GetIconLayout(runtimeSettings)
    local textLayout = GetTextLayout(runtimeSettings)
    local iconVisual = type(runtimeSettings.nameplateIcon) == "table" and runtimeSettings.nameplateIcon or {}
    local borderConfig = GetBorderConfig(runtimeSettings)
    local readyBorderConfig = GetReadyBorderConfig(runtimeSettings)
    local iconGap = GetIconSpacing(runtimeSettings)
    if iconsEnabled ~= true then
        HideUnusedIcons(frame.leftIcons or {}, 1)
        HideUnusedIcons(frame.rightIcons or {}, 1)
        frame:Show()
        return
    end

    local hideAboveSeconds = GetIconHideAboveSeconds(runtimeSettings)
    local left, right = {}, {}
    for i = 1, #(timers or {}) do
        local row = timers[i]
        local remaining = tonumber(type(row) == "table" and row.remaining) or 0
        local visibleByTime = hideAboveSeconds <= 0 or remaining <= hideAboveSeconds
        if type(row) == "table" and tonumber(row.spellID) and visibleByTime then
            if tostring(row.side or "right") == "left" then
                left[#left + 1] = row
            else
                right[#right + 1] = row
            end
        end
    end

    for i = 1, #left do
        local row = left[i]
        local icon = EnsureIconFrame(frame, "left", i)
        ApplyFrameStrata(icon, strata)
        icon:SetSize(iconWidth, iconHeight)
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("RIGHT", frame, "LEFT", -ICON_CENTER_GAP + offsetX, offsetY)
        else
            icon:SetPoint("RIGHT", frame.leftIcons[i - 1], "LEFT", -iconGap, 0)
        end
        icon.texture:SetTexture(tonumber(row.iconFileID) or 136243)
        ApplyRuntimeIconAppearance(icon, iconVisual)
        ApplyCooldown(icon, row, reverseCooldown, iconVisual.showCooldown ~= false)
        ApplyTextStyle(icon, textLayout)
        icon.countWidget:SetText(FormatRemainingText(row.remaining, row.ready))
        ApplyIconBorder(icon, borderConfig, row.ready, readyBorderConfig)
        icon:Show()
    end
    HideUnusedIcons(frame.leftIcons, #left + 1)

    for i = 1, #right do
        local row = right[i]
        local icon = EnsureIconFrame(frame, "right", i)
        ApplyFrameStrata(icon, strata)
        icon:SetSize(iconWidth, iconHeight)
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint("LEFT", frame, "RIGHT", ICON_CENTER_GAP + offsetX, offsetY)
        else
            icon:SetPoint("LEFT", frame.rightIcons[i - 1], "RIGHT", iconGap, 0)
        end
        icon.texture:SetTexture(tonumber(row.iconFileID) or 136243)
        ApplyRuntimeIconAppearance(icon, iconVisual)
        ApplyCooldown(icon, row, reverseCooldown, iconVisual.showCooldown ~= false)
        ApplyTextStyle(icon, textLayout)
        icon.countWidget:SetText(FormatRemainingText(row.remaining, row.ready))
        ApplyIconBorder(icon, borderConfig, row.ready, readyBorderConfig)
        icon:Show()
    end
    HideUnusedIcons(frame.rightIcons, #right + 1)
    -- SetUnitTimers is also the direct entry for the screen-nameplate test.
    -- Runtime normally reaches SetUnitText first (which shows this parent),
    -- but the test deliberately renders icons only.  A visible child cannot
    -- escape a hidden parent frame.
    frame:Show()
end
