---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/BunBar/View.lua
-- 束状条 HUD（图标沿时间轴向触发线滑动）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
--(无意义的注释 仅测试用)
local BunBar                = ExBoss.UI.BunBar
local BorderUtil            = ExBoss.BorderUtil
local L                     = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })
local function TraceColor(stage, timer, color, note)
    local trace = ExBoss and ExBoss.ColorTrace
    if trace and type(trace.Record) == "function" then trace:Record(stage, timer, color, note) end
end
local LSM                   = LibStub and LibStub("LibSharedMedia-3.0", true)
local EXUI                  = ExwindTools.UI

local MODULE_KEY            = "ExBoss.BunBar"
local POOL_TYPE             = "ExBoss_BunBarNode"
local TEXT_UPDATE_INTERVAL  = 0.05
local POSITION_SMOOTH_TIME  = 0.10
local ACTIVE_WINDOW_SECS    = 20
local QUEUE_HIDE_SECS       = 60
local PREWARM_NODE_COUNT    = 6
local SUDDEN_INTRO_OFFSET_X = 28
local SUDDEN_INTRO_DURATION = 0.45
local QUEUE_INTRO_OFFSET_Y  = 22
local QUEUE_INTRO_DURATION  = 0.22
local OUTRO_DURATION        = 0.20
local OUTRO_FADE_DURATION   = 0.20
local OUTRO_SCALE_TO        = 1.35
local FIVE_SEC_MARK_REMAIN  = 5
local TEST_PREFIX           = "__exboss_bun_test_"
local LEGACY_EVENT_KEY      = "encounter" .. "EventID"

local function EnsureBackdropBorderFrame(ownerFrame, key, parentFrame)
    if not ownerFrame or not key or not parentFrame then
        return nil
    end
    local borderFrame = ownerFrame[key]
    if borderFrame then
        return borderFrame
    end
    borderFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    borderFrame:Hide()
    ownerFrame[key] = borderFrame
    return borderFrame
end

local function ApplyBackdropBorder(borderFrame, targetFrame, texturePath, edgeSize, padding, r, g, b, a, frameLevel)
    if not borderFrame or not targetFrame or not texturePath then
        return
    end
    borderFrame:SetFrameLevel(frameLevel or (targetFrame:GetFrameLevel() + 2))
    borderFrame:ClearAllPoints()
    borderFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
    borderFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)
    borderFrame:SetBackdrop({
        edgeFile = texturePath,
        edgeSize = edgeSize,
    })
    borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    borderFrame:Show()
end

local function HideBackdropBorder(borderFrame)
    if borderFrame then
        borderFrame:Hide()
    end
end

local function Factory()
    return _G.ExwindFactory
end

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function DB()
    return ExwindTools:GetModuleDB(MODULE_KEY)
end

local function IsSpellCountDisplayEnabled()
    local root = _G.EXBOSS12S2
    return type(root) == "table"
        and type(root.ui) == "table"
        and type(root.ui.general) == "table"
        and root.ui.general.showSpellOccurrenceCount == true
end

local function FormatOccurrenceCountText(timer)
    if type(timer) ~= "table" then
        return ""
    end
    if not IsSpellCountDisplayEnabled() then
        return ""
    end
    if timer.useOccurrenceCount ~= true then
        return ""
    end
    local count = tonumber(timer.occurrenceCount)
    if not count or count <= 0 then
        return ""
    end
    return string.format("(%d)", count)
end

local function ResolveBunBarDisplayName(timer, spellInfo)
    local usingRename = type(timer) == "table" and type(timer.timerBarName) == "string" and timer.timerBarName ~= ""
    local name = type(timer) == "table" and (timer.timerBarName or timer.displayName) or nil
    if not name and spellInfo then
        name = spellInfo.name
    end
    if not name then
        name = "???"
    end
    if usingRename then
        local countText = FormatOccurrenceCountText(timer)
        if countText ~= "" then
            name = string.format("%s %s", name, countText)
            return name, ""
        end
    end
    if type(timer) == "table" and timer.occurrenceDisplayMode == "inline" then
        local countText = FormatOccurrenceCountText(timer)
        if countText ~= "" then
            name = string.format("%s %s", name, countText)
        end
        return name, ""
    end
    if type(timer) == "table" and timer.occurrenceDisplayMode == "none" then
        return name, ""
    end
    return name, FormatOccurrenceCountText(timer)
end

local function SafeNum(v, def)
    local n = tonumber(v)
    if not n then return def end
    return n
end

local function Clamp01(v, def)
    local n = tonumber(v)
    if n == nil then n = tonumber(def) end
    if n == nil then n = 1 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function GetMainIconMetrics(db)
    local iconStyle = type(db) == "table" and db.icon or nil
    local width = math.max(10, SafeNum(iconStyle and iconStyle.width, 39))
    local height = math.max(10, SafeNum(iconStyle and iconStyle.height, width))
    return width, height, math.max(width, height)
end

local function SetClickThrough(frame)
    if not frame then return end
    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(false)
    end
end

local function ResolveTimerEventID(timer)
    if type(timer) ~= "table" then return nil end
    local eventID = tonumber(timer.eventID)
    if eventID then return eventID end
    return tonumber(rawget(timer, LEGACY_EVENT_KEY))
end

local function SafeExtractRGB(c)
    if type(c) ~= "table" then return nil end
    local r = tonumber(c.r)
    local g = tonumber(c.g)
    local b = tonumber(c.b)
    if r and g and b then
        return r, g, b
    end
    if type(c.GetRGB) == "function" then
        local rr, gg, bb = c:GetRGB()
        if tonumber(rr) and tonumber(gg) and tonumber(bb) then return tonumber(rr), tonumber(gg), tonumber(bb) end
    end
    return nil
end

local function Saturate(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function EaseOutCubic(t)
    t = Saturate(t)
    if EasingUtil and EasingUtil.OutCubic then
        return EasingUtil.OutCubic(t)
    end
    local inv = 1 - t
    return 1 - (inv * inv * inv)
end

local function EaseInCubic(t)
    t = Saturate(t)
    if EasingUtil and EasingUtil.InCubic then
        return EasingUtil.InCubic(t)
    end
    return t * t * t
end

-- BunBar 只声明这一份 ModuleDB。运行时、设置页、Scheduler 读取同一个根，
-- 不再回退或同步旧 EXBOSS12S2.timer.bunBar。
local EX_DEFAULTS = {
    module = {
        enabled           = true,
        locked            = false,
        anchorX           = -734,
        anchorY           = 141,
        attachToCustom    = false,
        customAttachTarget = "",
        width             = 420,
        trackHeight       = 10,
        preAlertSecs      = 5,
        moveDir           = "DOWN",
        hideLongTimersSeconds = 30,
        fiveSecLineWidth  = 3,
        fiveSecLineColorR = 1.0,
        fiveSecLineColorG = 0.9,
        fiveSecLineColorB = 0.35,
        fiveSecLineColorA = 0.85,
        colors = {
            [1] = { r = 1.0, g = 0.2, b = 0.2, a = 1.0 },
            [2] = { r = 1.0, g = 0.8, b = 0.0, a = 1.0 },
            [3] = { r = 0.6, g = 0.6, b = 0.6, a = 0.6 },
        },
    },
        icon              = {
            width = 40, height = 40, x = 0, y = 0,
            showIcon = true,
            showBorder = true,
            enableCrop = true,
            showCooldown = false,
            borderTexture = "EX_WhiteBorder",
            borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1,
            borderSize = 1, borderPadding = 0,
            reverse = false,
            cooldown = { edgeAlpha = 1, showBling = false, showEdge = true, showSwipe = true, swipeAlpha = 0.65 },
        },
        font_spell        = {
            font = "默认", size = 17, r = 1, g = 1, b = 1, a = 1,
            enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0,
            justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE",
            shadow = false, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
            shadowX = 1, shadowY = -1, rotation = 0,
            gradientEnabled = false, gradientStart = 0, gradientLength = 0,
            drawLayer = "OVERLAY", drawSubLevel = 0,
            side = "RIGHT", x = 2.7934611098561, y = -3,
        },
        font_timer        = {
            font = "默认", size = 20, r = 1, g = 0.81960791349411, b = 0, a = 1,
            enabled = true, autoWidth = false, fixedWidth = 200, maxWidth = 0,
            justifyH = "CENTER", justifyV = "MIDDLE", outline = "OUTLINE",
            shadow = true, shadowColorR = 0, shadowColorG = 0, shadowColorB = 0, shadowColorA = 1,
            shadowX = 1, shadowY = -1, rotation = 0,
            gradientEnabled = false, gradientStart = 0, gradientLength = 0,
            drawLayer = "OVERLAY", drawSubLevel = 0,
            x = 0, y = -2,
        },
        alertIcons        = {
            showIcon = true,
            anchor = "ICON_LEFT",
            layout = "VERTICAL",
            width = 36,
            height = 36,
            x = -1,
            y = 0,
            showBorder = true,
            enableCrop = true,
            showCooldown = true,
            reverse = false,
            cooldown = { edgeAlpha = 1, showBling = false, showEdge = true, showSwipe = true, swipeAlpha = 0.65 },
        },
        bgSettings        = {
            texture = "EX_WhiteBackground",
            bgColorR = 0,
            bgColorG = 0,
            bgColorB = 0,
            bgColorA = 1,
            borderTexture = "EX_WhiteBorder",
            borderColorR = 1,
            borderColorG = 1,
            borderColorB = 1,
            borderColorA = 1,
            edgeSize = 1,
            inset = 1,
            showBorder = true,
        },
}

local MODULE_FIELDS = {
    "enabled", "locked", "anchorX", "anchorY", "attachToCustom", "customAttachTarget",
    "width", "trackHeight", "preAlertSecs", "moveDir", "hideLongTimersSeconds",
    "fiveSecLineWidth", "fiveSecLineColorR", "fiveSecLineColorG", "fiveSecLineColorB", "fiveSecLineColorA", "colors",
}
local ICON_FIELDS = {
    "width", "height", "x", "y", "showIcon", "showBorder", "enableCrop", "showCooldown",
    "borderTexture", "borderColorR", "borderColorG", "borderColorB", "borderColorA", "borderSize", "borderPadding", "reverse",
    cooldown = { "edgeAlpha", "showBling", "showEdge", "showSwipe", "swipeAlpha" },
}
local FONT_FIELDS = {
    "font", "size", "r", "g", "b", "a", "enabled", "autoWidth", "fixedWidth", "maxWidth",
    "justifyH", "justifyV", "outline", "shadow", "shadowColorR", "shadowColorG", "shadowColorB",
    "shadowColorA", "shadowX", "shadowY", "rotation", "gradientEnabled", "gradientStart", "gradientLength",
    "drawLayer", "drawSubLevel", "side", "x", "y",
}
local ALERT_ICON_FIELDS = {
    "showIcon", "anchor", "layout", "width", "height", "x", "y", "showBorder", "enableCrop",
    "showCooldown", "reverse",
    cooldown = { "edgeAlpha", "showBling", "showEdge", "showSwipe", "swipeAlpha" },
}
local BG_FIELDS = {
    "texture", "bgColor", "bgColorR", "bgColorG", "bgColorB", "bgColorA", "showBorder", "borderTexture", "borderColor",
    "borderColorR", "borderColorG", "borderColorB", "borderColorA", "edgeSize", "inset",
}
local DEFAULT_SCHEMA = {
    { group = "module", root = true, fields = MODULE_FIELDS },
    { group = "icon", fields = ICON_FIELDS },
    { group = "font_spell", fields = FONT_FIELDS },
    { group = "font_timer", fields = FONT_FIELDS },
    { group = "alertIcons", fields = ALERT_ICON_FIELDS },
    { group = "bgSettings", fields = BG_FIELDS },
}
ExwindTools:DeclareModuleDefaults(MODULE_KEY, EX_DEFAULTS, DEFAULT_SCHEMA)

-- 标准显示合同：页面、Panel 局部拖动、世界整体锚点和 runtime 只读写同一
-- ModuleDB。BunBar 的 runtime 时间轴仍是白名单业务 OnUpdate；这里不把它
-- 扩散成通用 preview 计时器。
local INTERACTION_SCHEMA = {
    ["core.icon"] = { guiKey = "icon", movable = false, tooltip = L["主图标"] },
    ["core.spellName"] = {
        guiKey = "font_spell", movable = true, tooltip = L["法术名称"],
        position = { x = "font_spell.x", y = "font_spell.y" },
    },
    ["core.time"] = {
        guiKey = "font_timer", movable = true, tooltip = L["图标倒数时间"],
        position = { x = "font_timer.x", y = "font_timer.y" },
    },
    ["bunbar.alertIcons"] = {
        guiKey = "alertIcons", movable = true, tooltip = L["业务提示 Atlas"],
        position = { x = "alertIcons.x", y = "alertIcons.y" },
    },
}

local CONFIG_SCHEMA_PATHS = {
    enabled = true, moveDir = true, hideLongTimersSeconds = true, width = true, trackHeight = true,
    fiveSecLineWidth = true, fiveSecLineColor = true, fiveSecLineColorR = true, fiveSecLineColorG = true,
    fiveSecLineColorB = true, fiveSecLineColorA = true, anchorX = true, anchorY = true,
    attachToCustom = true, customAttachTarget = true,
    ["bgSettings.texture"] = true, ["bgSettings.bgColor"] = true, ["bgSettings.showBorder"] = true, ["bgSettings.borderTexture"] = true,
    ["bgSettings.borderColor"] = true,
    ["font_spell.side"] = true, ["font_spell.autoWidth"] = true, ["font_timer.autoWidth"] = true,
}
local EXTRA_CONFIG_PATHS = {
    "icon.width", "icon.height", "icon.x", "icon.y", "icon.alpha", "icon.rotation",
    "icon.cropLeft", "icon.cropRight", "icon.cropTop", "icon.cropBottom", "icon.borderSize",
    "icon.borderPadding", "icon.cooldown.swipeAlpha", "icon.cooldown.edgeAlpha",
    "alertIcons.width", "alertIcons.height", "alertIcons.x", "alertIcons.y", "alertIcons.alpha", "alertIcons.rotation",
    "alertIcons.cropLeft", "alertIcons.cropRight", "alertIcons.cropTop", "alertIcons.cropBottom", "alertIcons.borderSize",
    "alertIcons.borderPadding", "alertIcons.cooldown.swipeAlpha", "alertIcons.cooldown.edgeAlpha",
    "font_spell.size", "font_spell.x", "font_spell.y", "font_spell.shadowX", "font_spell.shadowY", "font_spell.fixedWidth",
    "font_spell.maxWidth", "font_spell.gradientStart", "font_spell.gradientLength", "font_spell.rotation",
    "font_timer.size", "font_timer.x", "font_timer.y", "font_timer.shadowX", "font_timer.shadowY", "font_timer.fixedWidth",
    "font_timer.maxWidth", "font_timer.gradientStart", "font_timer.gradientLength", "font_timer.rotation",
    "bgSettings.edgeSize", "bgSettings.inset",
}
for _, path in ipairs(EXTRA_CONFIG_PATHS) do CONFIG_SCHEMA_PATHS[path] = true end

BunBar.StandardSliderContract = {
    groupPaths = {
        moduleCommon = "", icon = "icon", alertIcons = "alertIcons",
        font_spell = "font_spell", font_timer = "font_timer",
    },
}

function BunBar:GetDB()
    return DB()
end

local DEFAULT_FONT_NAME = EX_DEFAULTS.font_spell
local DEFAULT_FONT_TIME = EX_DEFAULTS.font_timer

local anchorFrame = nil
local anchorController = nil
local activeNodes = {}     -- [timerID] = frame
local nodeList = {}
local syntheticTimers = {} -- [timerID] = timer
local testIDs = {}         -- [timerID] = true
local _textElapsed = 0
local _sortDirty = false
local _testSeed = 0
local _updateFrame = nil
local _runtimeConfig = nil
-- runtime 仍使用其业务 Node/OnUpdate；Panel 与 World 的静态样本改由 EXUI
-- Timeline session 物化，模块只交声明，绝不再私有 Acquire Node/拖动 hitbox。
local worldTimelinePreview = nil
local panelSurface = nil
local CONFIG_BINDING = nil
local standardAnchorGroupOptions = nil
local CreateAnchor
local EnsureAnchorController
local UpdateAnchorVisuals
local RuntimeTick

local function InvalidateRuntimeConfig()
    _runtimeConfig = nil
end

local function GetRuntimeConfig()
    if _runtimeConfig then
        return _runtimeConfig
    end
    local db = DB()
    local _, _, iconSize = GetMainIconMetrics(db)
    _runtimeConfig = {
        timelineLen = math.max(120, SafeNum(db.width, 420)),
        moveDir = db.moveDir or "DOWN",
        iconSize = iconSize,
        trackHeight = math.max(5, SafeNum(db.trackHeight, 49)),
        showName = not (type(db.font_spell) == "table" and db.font_spell.enabled == false),
        showTimer = not (type(db.font_timer) == "table" and db.font_timer.enabled == false),
    }
    return _runtimeConfig
end


local function ShouldShowAnchor()
    if worldTimelinePreview then
        return true
    end
    if anchorFrame and anchorFrame.__ExwindStandardWorldPreview then
        return true
    end
    return next(activeNodes) ~= nil
end

local function RefreshAnchorVisibility()
    if not anchorFrame then return end
    local show = ShouldShowAnchor()
    local standardWorld = anchorFrame.__ExwindStandardWorldPreview == true or worldTimelinePreview ~= nil
    if standardWorld then
        -- 编辑世界的轨道只能由 BuildPreview() 的 collection decoration 呈现；
        -- 运行时 anchor 自带的背景/线条不能叠成第二个预览。
        if anchorFrame.BgTexture then anchorFrame.BgTexture:Hide() end
        if anchorFrame.FiveSecLine then anchorFrame.FiveSecLine:Hide() end
        HideBackdropBorder(anchorFrame.BorderFrame)
    elseif show then
        UpdateAnchorVisuals()
    end
    if show then
        anchorFrame:Show()
        if _updateFrame and not worldTimelinePreview then
            _updateFrame:Show()
        elseif _updateFrame then
            _updateFrame:Hide()
        end
    else
        if _updateFrame then
            _updateFrame:Hide()
        end
        anchorFrame:Hide()
    end
end

local function FormatTime(secs)
    if secs >= 60 then
        return string.format("%d:%02d", math.floor(secs / 60), math.floor(secs % 60))
    end
    return string.format("%d", math.max(0, math.ceil(secs)))
end

local function UpdateTimeTextBounds(node, text, iconSize, fontSize)
    if not (node and node.TimeText) then return end
    local baseWidth = math.max((iconSize or 0) - 4, 10)
    local size = tonumber(fontSize) or DEFAULT_FONT_TIME.size
    local charCount = math.max(2, tostring(text or ""):len())
    local width = math.max(baseWidth, math.ceil(charCount * size * 0.95 + math.max(10, size * 0.8)))
    local height = math.max(10, math.floor(math.max((iconSize or 0) * 0.42, size * 1.15)))
    node.TimeText:SetWidth(width)
    if node.TimeBG then
        node.TimeBG:SetSize(width, height)
    end
end

local function RecommendSpacingSeconds(db)
    local _, _, iconSize = GetMainIconMetrics(db)
    local timelineLen = math.max(120, SafeNum(db and db.width, 420))
    local needPixels = iconSize + 2
    return math.max(0.5, (needPixels * ACTIVE_WINDOW_SECS) / timelineLen)
end

local function InitNodeStructure(node)
    node:SetSize(36, 36)
    SetClickThrough(node)

    -- 束状条节点的主图标由 EXUI Runtime IconWidget 承担。
    local runtimeIcon = ExwindTools.UI:CreateIconWidget(node)
    runtimeIcon:SetPoint("CENTER", node, "CENTER")
    node.RuntimeIconWidget = runtimeIcon
    node.Icon = runtimeIcon.icon

    local nameWidget = ExwindTools.UI:CreateTextWidget(node, "bunBarName")
    local nameText = nameWidget.text
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    node.NameText = nameText
    node.NameWidget = nameWidget

    node.AlertIcons = {}

    local countWidget = ExwindTools.UI:CreateTextWidget(node, "bunBarCount")
    local countText = countWidget.text
    countText:SetJustifyH("LEFT")
    countText:SetWordWrap(false)
    node.CountText = countText
    node.CountWidget = countWidget

    local timeBG = ExwindTools.UI:CreateVisualTexture(node, EXBACKGROUNDFRAME)
    timeBG:SetColorTexture(0, 0, 0, 0.55)
    node.TimeBG = timeBG

    local timeWidget = ExwindTools.UI:CreateTextWidget(node, "bunBarTime")
    local timeText = timeWidget.text
    timeText:SetJustifyH("CENTER")
    timeText:SetWordWrap(false)
    if timeText.SetNonSpaceWrap then
        timeText:SetNonSpaceWrap(false)
    end
    node.TimeText = timeText
    node.TimeWidget = timeWidget
end

local function StartOutro(node)
    if not node or node._outroEnd then return end
    local now = GetTime()
    local startX = node._displayX
    local startY = node._displayY
    if (startX == nil or startY == nil) and node.GetPoint then
        local _p, _r, _rp, ox, oy = node:GetPoint(1)
        if ox and oy then
            startX = startX or ox
            startY = startY or (-oy)
        end
    end
    if not startX then startX = 0 end
    if not startY then startY = 0 end

    node._outroStart = now
    node._outroEnd = now + OUTRO_DURATION
    node._outroFromX = startX
    node._outroFromY = startY
    node._introKind = nil
    node._introStart = nil
    node._introEnd = nil
    node._introFromX = nil
    node._introFromY = nil
end

local function UpdateOutro(node, now)
    if not node or not node._outroEnd then return false end
    if now >= node._outroEnd then
        return true
    end
    local elapsed = math.max(0, now - (node._outroStart or now))

    local alphaProgress = Saturate(elapsed / math.max(0.01, OUTRO_FADE_DURATION))
    local alphaValue = 1 - EaseInCubic(alphaProgress)
    node:SetAlpha(alphaValue)

    local scaleProgress = Saturate(elapsed / math.max(0.01, OUTRO_DURATION))
    local scaleValue = 1 + (OUTRO_SCALE_TO - 1) * EaseOutCubic(scaleProgress)
    local baseX = node._outroFromX or node._displayX or 0
    local baseY = node._outroFromY or node._displayY or 0
    local safeScale = (scaleValue > 0.001) and scaleValue or 0.001
    node._displayX = baseX
    node._displayY = baseY
    node:SetScale(scaleValue)
    if anchorFrame then
        -- WoW 对父坐标系缩放会引起锚点漂移；用反向补偿锁定视觉中心。
        node:ClearAllPoints()
        node:SetPoint("CENTER", anchorFrame, "TOPLEFT", baseX / safeScale, -(baseY / safeScale))
    end
    node:Show()
    return false
end

do
    local fac = Factory()
    if fac then
        fac:InitPool(POOL_TYPE, "Frame", nil, InitNodeStructure)
    end
end

local function GetRuntimeTimer(timerID)
    local sched = ExBoss.Timeline.Scheduler
    local active = sched and sched._active and sched._active[timerID]
    if active then return active end
    return syntheticTimers[timerID]
end

local function FetchLSM(mediaType, key, fallbackPath)
    if key == "None" or key == "" then
        return nil
    end
    if LSM and key then
        local path = LSM:Fetch(mediaType, key, true)
        if path then
            return path
        end
    end
    return fallbackPath
end

local function ApplyAnchorSkin(surface)
    surface = surface or anchorFrame
    if not surface then return end
    local db = DB()
    local conf = db.bgSettings or {}
    local inset = math.max(0, SafeNum(conf.inset, 2))
    local bgTex = surface.BgTexture or ExwindTools.UI:CreateVisualTexture(surface, EXBACKGROUNDFRAME)
    -- 背景可回退默认材质；边框是否显示则必须只由同一份 ModuleDB 决定。
    local bgFile = FetchLSM("background", conf.texture, "Interface\\Buttons\\WHITE8X8") or "Interface\\Buttons\\WHITE8X8"
    local edgeFile = nil
    if conf.showBorder ~= false then
        edgeFile = FetchLSM("border", conf.borderTexture, "Interface\\Tooltips\\UI-Tooltip-Border")
            or "Interface\\Tooltips\\UI-Tooltip-Border"
    end
    local edgeSize = math.max(1, SafeNum(conf.edgeSize, 8))

    surface.BgTexture = bgTex
    bgTex:ClearAllPoints()
    bgTex:SetPoint("TOPLEFT", surface, "TOPLEFT", inset, -inset)
    bgTex:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -inset, inset)

    local r = SafeNum(conf.bgColorR, 0.05)
    local g = SafeNum(conf.bgColorG, 0.06)
    local b = SafeNum(conf.bgColorB, 0.08)
    local a = SafeNum(conf.bgColorA, 0.55)
    local br = SafeNum(conf.borderColorR, 1)
    local bg = SafeNum(conf.borderColorG, 1)
    local bb = SafeNum(conf.borderColorB, 1)
    local ba = SafeNum(conf.borderColorA, 0.35)

    if bgFile then
        bgTex:SetTexture(bgFile)
        bgTex:SetVertexColor(r, g, b, a)
        bgTex:Show()
    else
        bgTex:Hide()
    end

    surface.BorderFrame = surface.BorderFrame or EnsureBackdropBorderFrame(surface, "BorderFrame", surface)
    if edgeFile then
        ApplyBackdropBorder(surface.BorderFrame, surface, edgeFile, edgeSize, 0, br, bg, bb, ba, (surface:GetFrameLevel() or 1) + 1)
    else
        HideBackdropBorder(surface.BorderFrame)
    end
end

UpdateAnchorVisuals = function(surface)
    surface = surface or anchorFrame
    if not surface then return end
    local db = DB()

    local timelineLen = math.max(120, SafeNum(db.width, 420))
    local trackHeight = math.max(5, SafeNum(db.trackHeight, 49))
    local trackCount = 1
    local crossLen = trackHeight * trackCount

    ApplyAnchorSkin(surface)

    surface:SetSize(crossLen, timelineLen)
    if surface.FiveSecLine then
        local fiveWidth = math.max(1, SafeNum(db.fiveSecLineWidth, 2))
        local fiveR = Clamp01(db.fiveSecLineColorR, 1.0)
        local fiveG = Clamp01(db.fiveSecLineColorG, 0.90)
        local fiveB = Clamp01(db.fiveSecLineColorB, 0.35)
        local fiveA = Clamp01(db.fiveSecLineColorA, 0.85)
        local remain = math.max(0, math.min(ACTIVE_WINDOW_SECS, FIVE_SEC_MARK_REMAIN))
        local moveDir = db.moveDir or "DOWN"
        local y
        if moveDir == "DOWN" then
            y = timelineLen * (1 - (remain / ACTIVE_WINDOW_SECS))
        else
            y = timelineLen * (remain / ACTIVE_WINDOW_SECS)
        end
        surface.FiveSecLine:ClearAllPoints()
        surface.FiveSecLine:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, -y)
        surface.FiveSecLine:SetSize(crossLen, fiveWidth)
        surface.FiveSecLine:SetColorTexture(fiveR, fiveG, fiveB, fiveA)
        surface.FiveSecLine:Show()
    end

    if surface == anchorFrame then InvalidateRuntimeConfig() end
end

local ALERT_FLAG_DEFS = {
    { name = "deadly",  bit = 1,   atlases = { "icons_64x64_deadly", "combattimeline-fx-deadlyglow-base", "common-icon-redx" },                                            texture = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "enrage",  bit = 2,   atlases = { "icons_64x64_enrage" },                                                                                                     texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "bleed",   bit = 4,   atlases = { "icons_64x64_bleed", "UI-Debuff-Border-Bleed-Icon", "RaidFrame-Icon-DebuffBleed" },                                         texture = { file = "Interface\\RaidFrame\\ReadyCheck-NotReady", left = 0, right = 1, top = 0, bottom = 1 } },
    { name = "magic",   bit = 8,   atlases = { "icons_64x64_magic", "RaidFrame-Icon-DebuffMagic", "UI-HUD-CoolDownManager-Debuff-Magic" } },
    { name = "disease", bit = 16,  atlases = { "icons_64x64_disease", "RaidFrame-Icon-DebuffDisease", "UI-HUD-CoolDownManager-Debuff-Disease" } },
    { name = "curse",   bit = 32,  atlases = { "icons_64x64_curse", "RaidFrame-Icon-DebuffCurse", "UI-HUD-CoolDownManager-Debuff-Curse" } },
    { name = "poison",  bit = 64,  atlases = { "icons_64x64_poison", "RaidFrame-Icon-DebuffPoison", "UI-HUD-CoolDownManager-Debuff-Poison" } },
    { name = "tank",    bit = 128, atlases = { "icons_64x64_tank", "UI-LFG-RoleIcon-Tank-Micro-GroupFinder", "UI-LFG-RoleIcon-Tank-Micro", "UI-LFG-RoleIcon-Tank" },       texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 0, right = 19 / 64, top = 22 / 64, bottom = 41 / 64 } },
    { name = "heal",    bit = 256, atlases = { "icons_64x64_heal", "UI-LFG-RoleIcon-Healer-Micro-GroupFinder", "UI-LFG-RoleIcon-Healer-Micro", "UI-LFG-RoleIcon-Healer" }, texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 1 / 64, bottom = 20 / 64 } },
    { name = "damage",  bit = 512, atlases = { "icons_64x64_damage", "UI-LFG-RoleIcon-DPS-Micro-GroupFinder", "UI-LFG-RoleIcon-DPS-Micro", "UI-LFG-RoleIcon-DPS" },        texture = { file = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", left = 20 / 64, right = 39 / 64, top = 22 / 64, bottom = 41 / 64 } },
}

local _alertAtlasExistCache = {}

local function HasFlag(v, b)
    v = tonumber(v) or 0
    b = tonumber(b) or 0
    if v <= 0 or b <= 0 then return false end
    if bit32 and bit32.band then return bit32.band(v, b) ~= 0 end
    if bit and bit.band then return bit.band(v, b) ~= 0 end
    return (v % (b * 2)) >= b
end

local function IsAlertAtlasValid(atlasName)
    if not atlasName or atlasName == "" then return false end
    local cached = _alertAtlasExistCache[atlasName]
    if cached ~= nil then return cached end
    local valid = true
    if C_Texture and C_Texture.GetAtlasInfo then
        valid = C_Texture.GetAtlasInfo(atlasName) ~= nil
    end
    _alertAtlasExistCache[atlasName] = valid and true or false
    return _alertAtlasExistCache[atlasName]
end

local function GetTimerIconFlags(timer)
    return tonumber(type(timer) == "table" and timer.iconFlags or nil) or 0
end

local function ApplyAlertTexture(tex, iconFlags)
    if not tex then return false end
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        tex:Hide()
        return false
    end
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        if HasFlag(flags, cfg.bit) then
            if type(cfg.atlases) == "table" then
                for _, atlas in ipairs(cfg.atlases) do
                    if IsAlertAtlasValid(atlas) then
                        tex:SetTexture(nil)
                        tex:SetTexCoord(0, 1, 0, 1)
                        tex:SetAtlas(atlas, true)
                        tex:Show()
                        return true
                    end
                end
            end
            if cfg.texture and cfg.texture.file then
                tex:SetTexture(cfg.texture.file)
                tex:SetTexCoord(cfg.texture.left or 0, cfg.texture.right or 1, cfg.texture.top or 0,
                    cfg.texture.bottom or 1)
                tex:Show()
                return true
            end
        end
    end
    tex:Hide()
    return false
end

local function CollectAlertVisuals(iconFlags)
    local out = {}
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return out
    end
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        if HasFlag(flags, cfg.bit) then
            local added = false
            if type(cfg.atlases) == "table" then
                for _, atlas in ipairs(cfg.atlases) do
                    if IsAlertAtlasValid(atlas) then
                        out[#out + 1] = { atlas = atlas }
                        added = true
                        break
                    end
                end
            end
            if (not added) and cfg.texture and cfg.texture.file then
                out[#out + 1] = {
                    file = cfg.texture.file,
                    left = cfg.texture.left or 0,
                    right = cfg.texture.right or 1,
                    top = cfg.texture.top or 0,
                    bottom = cfg.texture.bottom or 1,
                }
            end
        end
    end
    return out
end

local function BuildAlertIconMarkup(iconFlags, iconSize, iconYOffset)
    local flags = tonumber(iconFlags) or 0
    if flags <= 0 then
        return ""
    end
    local renderSize = tonumber(iconSize) or 14
    local renderYOffset = tonumber(iconYOffset) or 0
    local marks = {}
    for _, cfg in ipairs(ALERT_FLAG_DEFS) do
        local bitMask = tonumber(cfg.bit) or 0
        if bitMask > 0 and HasFlag(flags, bitMask) then
            local atlasList = cfg.atlases
            local added = false
            if type(atlasList) ~= "table" or #atlasList == 0 then
                atlasList = { "icons_64x64_" .. tostring(cfg.name or "") }
            end
            for _, atlas in ipairs(atlasList) do
                if IsAlertAtlasValid(atlas) then
                    if CreateAtlasMarkup then
                        marks[#marks + 1] = CreateAtlasMarkup(atlas, renderSize, renderSize, 0, renderYOffset)
                    else
                        marks[#marks + 1] = string.format("|A:%s:%d:%d:0:%d|a", atlas, renderSize, renderSize,
                            renderYOffset)
                    end
                    added = true
                    break
                end
            end
            if (not added) and cfg.texture and cfg.texture.file and cfg.texture.file ~= "" then
                local tex = cfg.texture
                local width = tonumber(tex.width) or 64
                local height = tonumber(tex.height) or 64
                if CreateTextureMarkup then
                    marks[#marks + 1] = CreateTextureMarkup(
                        tex.file,
                        width,
                        height,
                        renderSize,
                        renderSize,
                        tonumber(tex.left) or 0,
                        tonumber(tex.right) or 1,
                        tonumber(tex.top) or 0,
                        tonumber(tex.bottom) or 1,
                        0,
                        renderYOffset
                    )
                else
                    marks[#marks + 1] = string.format(
                        "|T%s:%d:%d:0:%d:%d:%d:%d:%d:%d:%d:%d|t",
                        tex.file,
                        renderSize,
                        renderSize,
                        renderYOffset,
                        width,
                        height,
                        math.floor((tonumber(tex.left) or 0) * width),
                        math.floor((tonumber(tex.right) or 1) * width),
                        math.floor((tonumber(tex.top) or 0) * height),
                        math.floor((tonumber(tex.bottom) or 1) * height)
                    )
                end
            end
        end
    end
    return table.concat(marks, " ")
end

local function EnsureAlertIcons(owner, count)
    owner.AlertIcons = owner.AlertIcons or {}
    while #owner.AlertIcons < count do
        local tex = ExwindTools.UI:CreateVisualTexture(owner, EXBASEFRAME)
        tex:Hide()
        owner.AlertIcons[#owner.AlertIcons + 1] = tex
    end
    return owner.AlertIcons
end

local function ResolveAlertIconDB(db)
    local cfg = type(db) == "table" and type(db.alertIcons) == "table" and db.alertIcons or nil
    local fallback = EX_DEFAULTS.alertIcons
    return cfg or fallback
end

local function UpdateAlertIcons(owner, iconFlags, cfg)
    local defs = CollectAlertVisuals(iconFlags)
    while #defs > 2 do table.remove(defs) end
    local icons = EnsureAlertIcons(owner, #defs)
    local enabled = type(cfg) ~= "table" or cfg.showIcon ~= false
    local baseWidth = math.max(6, tonumber(type(cfg) == "table" and cfg.width) or 16)
    local baseHeight = math.max(6, tonumber(type(cfg) == "table" and cfg.height) or baseWidth)
    local hasPair = #defs == 2
    local width = hasPair and math.max(4, math.floor(baseWidth / 2)) or baseWidth
    local height = hasPair and math.max(4, math.floor(baseHeight / 2)) or baseHeight
    local ox = tonumber(type(cfg) == "table" and cfg.x) or 0
    local oy = tonumber(type(cfg) == "table" and cfg.y) or 0
    local anchorMode = tostring(type(cfg) == "table" and cfg.anchor or "ICON_LEFT"):upper()
    local last = nil
    local function PlaceIcon(tex, index, baseFrame, point, relPoint, horizontalDir)
        if hasPair then
            local rowOffset = index == 1 and math.floor(height * .5) or -math.floor(height * .5)
            tex:SetPoint(point, baseFrame, relPoint, ox, oy + rowOffset)
            return
        end
        if index == 1 then
            tex:SetPoint(point, baseFrame, relPoint, ox, oy)
        elseif horizontalDir < 0 then
            tex:SetPoint("RIGHT", icons[index - 1], "LEFT", -2, 0)
        else
            tex:SetPoint("LEFT", icons[index - 1], "RIGHT", 2, 0)
        end
    end
    for i, tex in ipairs(icons) do
        local def = defs[i]
        if def and enabled then
            tex:ClearAllPoints()
            tex:SetSize(width, height)
            if anchorMode == "ICON_RIGHT" then
                PlaceIcon(tex, i, owner.Icon or owner, "LEFT", "RIGHT", 1)
            elseif anchorMode == "NAME_LEFT" then
                PlaceIcon(tex, i, owner.NameText or owner.Icon or owner, "RIGHT", "LEFT", -1)
            elseif anchorMode == "NAME_RIGHT" then
                PlaceIcon(tex, i, owner.NameText or owner.Icon or owner, "LEFT", "RIGHT", 1)
            else
                PlaceIcon(tex, i, owner.Icon or owner, "RIGHT", "LEFT", -1)
            end
            if def.atlas then
                tex:SetTexture(nil)
                tex:SetTexCoord(0, 1, 0, 1)
                tex:SetAtlas(def.atlas, false)
            else
                tex:SetAtlas(nil)
                tex:SetTexture(def.file)
                tex:SetTexCoord(def.left, def.right, def.top, def.bottom)
            end
            tex:Show()
            last = tex
        else
            tex:Hide()
        end
    end
    owner._lastAlertIcon = last
    return last
end

local function UpdateNodeVisuals(node, priority)
    local db = DB()
    local iconStyle = type(db.icon) == "table" and db.icon or {}
    local iconWidth, iconHeight, iconSize = GetMainIconMetrics(db)
    local showMainIcon = iconStyle.showIcon ~= false
    local col = db.colors and db.colors[priority or 2] or nil
    local staticDB = ExwindTools and ExwindTools.DB_Static
    if not col then col = { r = 1, g = 0.8, b = 0, a = 1 } end

    local overrideColor = nil
    if node and type(node._eventColor) == "table"
        and tonumber(node._eventColor.r) and tonumber(node._eventColor.g) and tonumber(node._eventColor.b) then
        overrideColor = { r = node._eventColor.r, g = node._eventColor.g, b = node._eventColor.b }
    end

    local colorR = overrideColor and overrideColor.r or (col.r or 1)
    local colorG = overrideColor and overrideColor.g or (col.g or 1)
    local colorB = overrideColor and overrideColor.b or (col.b or 1)
    local textColorR = colorR
    local textColorG = colorG
    local textColorB = colorB
    local textColorA = 1
    if type(node._timerTextColor) == "table"
        and tonumber(node._timerTextColor.r)
        and tonumber(node._timerTextColor.g)
        and tonumber(node._timerTextColor.b) then
        textColorR = node._timerTextColor.r
        textColorG = node._timerTextColor.g
        textColorB = node._timerTextColor.b
        textColorA = tonumber(node._timerTextColor.a) or 1
    end

    node:SetSize(iconSize + 4, iconSize + 4)

    if node.RuntimeIconWidget then
        local runtimeIconStyle = {}
        for key, value in pairs(iconStyle) do runtimeIconStyle[key] = value end
        runtimeIconStyle.width = math.max(1, iconWidth - 2)
        runtimeIconStyle.height = math.max(1, iconHeight - 2)
        runtimeIconStyle.showIcon = showMainIcon
        runtimeIconStyle.showCooldown = false
        node.RuntimeIconWidget:ApplyStyle({
            icon = runtimeIconStyle,
        })
        node.RuntimeIconWidget:ClearAllPoints()
        node.RuntimeIconWidget:SetPoint("CENTER", node, "CENTER")
    end

    if node.Icon then
        node.Icon:ClearAllPoints()
        node.Icon:SetPoint("CENTER", node, "CENTER", 0, 0)
        node.Icon:SetSize(iconWidth - 2, iconHeight - 2)
        node.Icon:SetShown(showMainIcon)
    end

    if node.TimeBG then
        node.TimeBG:ClearAllPoints()
        node.TimeBG:SetPoint("BOTTOM", node.Icon, "BOTTOM", 0, 1)
        node.TimeBG:SetSize(iconWidth - 4, math.max(10, math.floor(iconHeight * 0.42)))
        node.TimeBG:SetShown(false)
    end

    if node.NameText then
        local nameFont = (type(db.font_spell) == "table") and db.font_spell or DEFAULT_FONT_NAME
        local side = tostring(nameFont.side or DEFAULT_FONT_NAME.side or "RIGHT"):upper()
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(node.NameText, nameFont)
        end
        node.NameText:ClearAllPoints()
        local nx = SafeNum(nameFont.x, DEFAULT_FONT_NAME.x)
        local ny = SafeNum(nameFont.y, DEFAULT_FONT_NAME.y)
        if side == "LEFT" then
            node.NameText:SetJustifyH("RIGHT")
            node.NameText:SetPoint("RIGHT", node.Icon, "LEFT", nx, ny)
            node.NameText:SetPoint("LEFT", node.Icon, "LEFT", -200 + nx, ny)
        else
            node.NameText:SetJustifyH("LEFT")
            node.NameText:SetPoint("LEFT", node.Icon, "RIGHT", nx, ny)
            node.NameText:SetPoint("RIGHT", node.Icon, "RIGHT", 200 + nx, ny)
        end
        node.NameText:SetShown(not (type(db.font_spell) == "table" and db.font_spell.enabled == false))
        node.NameText:SetTextColor(textColorR, textColorG, textColorB, textColorA)
    end

    if node.CountText then
        local nameFont = (type(db.font_spell) == "table") and db.font_spell or DEFAULT_FONT_NAME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(node.CountText, nameFont)
        end
        node.CountText:ClearAllPoints()
        node.CountText:SetJustifyH("LEFT")
        node.CountText:SetPoint("LEFT", node.NameText or node.Icon, "RIGHT", 4, 0)
        node.CountText:SetShown(not (type(db.font_spell) == "table" and db.font_spell.enabled == false) and type(node._occurrenceCountText) == "string" and
        node._occurrenceCountText ~= "")
        node.CountText:SetTextColor(textColorR, textColorG, textColorB, textColorA)
    end

    if node.TimeText then
        local timeFont = (type(db.font_timer) == "table") and db.font_timer or DEFAULT_FONT_TIME
        if staticDB and staticDB.ApplyFont then
            staticDB:ApplyFont(node.TimeText, timeFont)
        end
        node.TimeText:ClearAllPoints()
        local tx = SafeNum(timeFont.x, DEFAULT_FONT_TIME.x)
        local ty = SafeNum(timeFont.y, DEFAULT_FONT_TIME.y)
        node.TimeText:SetPoint("CENTER", node.Icon, "CENTER", tx, ty)
        UpdateTimeTextBounds(node, node.TimeText:GetText(), iconSize, SafeNum(timeFont.size, DEFAULT_FONT_TIME.size))
        node.TimeText:SetShown(not (type(db.font_timer) == "table" and db.font_timer.enabled == false))
    end

    UpdateAlertIcons(node, node._iconFlags, ResolveAlertIconDB(db))
end

-- runtime、world 与 panel 都先将业务 record 投影为同一份普通 presentation；
-- Node 只物化这个结果，宿主不再决定名称、图标或样式语义。
local function BuildBunBarPresentation(timer)
    local spellInfo = timer and timer.spellID and C_Spell.GetSpellInfo(timer.spellID) or nil
    local name, countText = ResolveBunBarDisplayName(timer, spellInfo)
    return {
        castTime = timer.castTime,
        duration = math.max(1, timer.duration or 30),
        eventColor = timer.eventColor,
        timerTextColor = timer.timerTextColor,
        iconFlags = GetTimerIconFlags(timer),
        mode = timer._mode,
        priority = timer.barPriority or 2,
        label = name,
        occurrence = countText,
        icon = (spellInfo and spellInfo.iconID) or timer.iconFileID or 136197,
    }
end

local function ApplyTimerToNode(node, timer)
    if not node or type(timer) ~= "table" then return end
    local presentation = BuildBunBarPresentation(timer)
    local trace = ExBoss and ExBoss.ColorTrace
    local text = trace and type(trace.Describe) == "function" and trace:Describe(presentation.timerTextColor) or "?"
    TraceColor("BunBar.Apply", timer, presentation.eventColor, "timerText=" .. text)
    node._castTime = presentation.castTime
    node._duration = presentation.duration
    node._eventColor = presentation.eventColor
    node._timerTextColor = presentation.timerTextColor
    node._iconFlags = presentation.iconFlags
    node._mode = presentation.mode
    node._priority = presentation.priority
    node._occurrenceCountText = presentation.occurrence
    if node.NameText then node.NameText:SetText(presentation.label) end
    if node.CountText then node.CountText:SetText(node._occurrenceCountText or "") end
    if node.Icon then node.Icon:SetTexture(presentation.icon) end
    if node.AlertIcons then
        for _, tex in ipairs(node.AlertIcons) do tex:Hide() end
    end
    node._lastAlertIcon = nil
    UpdateNodeVisuals(node, node._priority)
end

local function AcquireNode(timerID, priority)
    local fac = Factory()
    if not fac or not anchorFrame then return nil end
    local node = fac:Acquire(POOL_TYPE, anchorFrame)
    node._timerID = timerID
    node._priority = priority or 2
    node._trackIndex = nil
    node._castTime = 0
    node._duration = 30
    node._eventColor = nil
    node._timerTextColor = nil
    node._occurrenceCountText = nil
    node._iconFlags = 0
    node._mode = nil
    node._isMovingNow = false
    node._wasMoving = false
    node._isQueuedNow = false
    node._wasQueued = false
    node._introKind = nil
    node._introStart = nil
    node._introEnd = nil
    node._introFromX = nil
    node._introFromY = nil
    node._outroStart = nil
    node._outroEnd = nil
    node._outroFromX = nil
    node._outroFromY = nil
    node._displayX = nil
    node._displayY = nil
    node._waitingTimelineFinish = nil
    node:SetAlpha(1)
    node:SetScale(1)
    SetClickThrough(node)
    UpdateNodeVisuals(node, node._priority)
    activeNodes[timerID] = node
    table.insert(nodeList, node)
    _sortDirty = true
    return node
end

local function ReleaseNode(timerID)
    local node = activeNodes[timerID]
    if not node then return end

    activeNodes[timerID] = nil
    syntheticTimers[timerID] = nil
    testIDs[timerID] = nil

    for i, n in ipairs(nodeList) do
        if n == node then
            table.remove(nodeList, i)
            break
        end
    end

    node:Hide()
    node._mode = nil
    node._timerTextColor = nil
    node._trackIndex = nil
    node._isMovingNow = nil
    node._wasMoving = nil
    node._isQueuedNow = nil
    node._wasQueued = nil
    node._introKind = nil
    node._introStart = nil
    node._introEnd = nil
    node._introFromX = nil
    node._introFromY = nil
    node._outroStart = nil
    node._outroEnd = nil
    node._outroFromX = nil
    node._outroFromY = nil
    node._displayX = nil
    node._displayY = nil
    node._waitingTimelineFinish = nil
    node:SetAlpha(1)
    node:SetScale(1)
    if node.NameText then node.NameText:SetText("") end
    if node.CountText then node.CountText:SetText("") end
    if node.TimeText then node.TimeText:SetText("") end
    if node.Icon then node.Icon:SetTexture(nil) end
    node._iconFlags = 0
    if node.AlertIcons then
        for _, tex in ipairs(node.AlertIcons) do
            tex:Hide()
        end
    end
    node._lastAlertIcon = nil
    node._occurrenceCountText = nil

    local fac = Factory()
    if fac then
        fac:Release(POOL_TYPE, node)
    end
    _sortDirty = true
    RefreshAnchorVisibility()
end

local _sortBuf = {}
local function RebuildTrackOrder()
    local now = GetTime()

    wipe(_sortBuf)
    for _, node in ipairs(nodeList) do
        table.insert(_sortBuf, node)
    end
    table.sort(_sortBuf, function(a, b)
        return (a._castTime - now) < (b._castTime - now)
    end)

    for _, node in ipairs(_sortBuf) do
        node._trackIndex = 1
    end
    _sortDirty = false
end

-- BunBar 的唯一标准预览真源。时间轴本质是“绝对排布的标准图标集合 + 一张
-- collection 级轨道材质。函数只返回普通快照，
-- 不创建 Frame、不读取运行时 timer、也不保存编辑状态。
local BUNBAR_PREVIEW_SPELL_IDS = { 1311923, 1310025, 1300372, 1248112, 1227247, 1227197 }
local BUNBAR_PREVIEW_TIMES = { "3", "6", "9", "12", "15" }
-- 预览必须展示单 Atlas 与双 Atlas；双 Atlas 与 runtime 一样最多两个、各缩为半尺寸上下排列。
local BUNBAR_PREVIEW_ICON_FLAGS = { 3, 4, 24, 32, 96, 128 }
local PANEL_TIMELINE_OFFSET_X, PANEL_TIMELINE_OFFSET_Y = -80, 45

-- 仅 panel/world 静态节点使用；缺失信息直接跳过，绝不退回假名称或图标。
local function BuildBunBarPreviewSpells()
    local spells = {}
    if not (C_Spell and type(C_Spell.GetSpellInfo) == "function") then return spells end
    for _, spellID in ipairs(BUNBAR_PREVIEW_SPELL_IDS) do
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name and info.iconID then
            spells[#spells + 1] = { spellID = spellID, name = info.name, iconID = info.iconID }
        end
    end
    return spells
end

-- The Panel and world-edit samples intentionally share this one static
-- declaration.  It contains no runtime timer, Scheduler record, or module
-- Frame/overlay; EXUI's timeline session owns those visual nodes.
local SAMPLE_REMAINING = { 3, 6, 9, 12, 15 }

local function BuildBunBarPreviewFont(style, fallback)
    style = type(style) == "table" and style or fallback
    local font = FetchLSM("font", style.font, nil) or STANDARD_TEXT_FONT
    return {
        font = font,
        size = math.max(6, SafeNum(style.size, fallback.size)),
        flags = tostring(style.outline or fallback.outline or ""),
        color = { r = SafeNum(style.r, fallback.r), g = SafeNum(style.g, fallback.g),
            b = SafeNum(style.b, fallback.b), a = SafeNum(style.a, fallback.a) },
        shadowColor = { r = SafeNum(style.shadowColorR, fallback.shadowColorR),
            g = SafeNum(style.shadowColorG, fallback.shadowColorG),
            b = SafeNum(style.shadowColorB, fallback.shadowColorB),
            a = SafeNum(style.shadowColorA, fallback.shadowColorA) },
        shadowX = style.shadow == true and SafeNum(style.shadowX, fallback.shadowX) or 0,
        shadowY = style.shadow == true and SafeNum(style.shadowY, fallback.shadowY) or 0,
    }
end

local function BuildBunBarTimelinePresentation(mode)
    local db = DB()
    local timelineLen = math.max(120, SafeNum(db.width, EX_DEFAULTS.module.width))
    local trackHeight = math.max(5, SafeNum(db.trackHeight, EX_DEFAULTS.module.trackHeight))
    local iconStyle = type(db.icon) == "table" and db.icon or EX_DEFAULTS.icon
    local alertStyle = ResolveAlertIconDB(db)
    local nameStyle = type(db.font_spell) == "table" and db.font_spell or DEFAULT_FONT_NAME
    local timeStyle = type(db.font_timer) == "table" and db.font_timer or DEFAULT_FONT_TIME
    local nameFont, timeFont = BuildBunBarPreviewFont(nameStyle, DEFAULT_FONT_NAME), BuildBunBarPreviewFont(timeStyle, DEFAULT_FONT_TIME)
    local iconWidth = math.max(8, SafeNum(iconStyle.width, EX_DEFAULTS.icon.width) - 2)
    local iconHeight = math.max(8, SafeNum(iconStyle.height, EX_DEFAULTS.icon.height) - 2)
    local nameWidth = nameStyle.autoWidth == false and math.max(20, SafeNum(nameStyle.fixedWidth, 200)) or 200
    local timelineX = trackHeight
    local conf = type(db.bgSettings) == "table" and db.bgSettings or {}
    local bgTexture = FetchLSM("background", conf.texture, "Interface\\Buttons\\WHITE8X8") or "Interface\\Buttons\\WHITE8X8"
    local moveDown = db.moveDir == "DOWN"
    local fiveWidth = math.max(1, SafeNum(db.fiveSecLineWidth, 2))
    local fiveY = moveDown
        and timelineLen * (FIVE_SEC_MARK_REMAIN / ACTIVE_WINDOW_SECS)
        or timelineLen * (1 - (FIVE_SEC_MARK_REMAIN / ACTIVE_WINDOW_SECS))
    local timeline = {
        anchor = "CENTER", lockAnchor = true,
        x = mode == "panel" and PANEL_TIMELINE_OFFSET_X or 0,
        y = mode == "panel" and PANEL_TIMELINE_OFFSET_Y or 0,
        width = timelineX, height = timelineLen,
        track = { x = 0, y = 0, width = timelineX, height = timelineLen, texture = bgTexture,
            color = { r = SafeNum(conf.bgColorR, 0.05), g = SafeNum(conf.bgColorG, 0.06),
                b = SafeNum(conf.bgColorB, 0.08), a = SafeNum(conf.bgColorA, 0.55) },
            border = { enabled = conf.showBorder ~= false,
                texture = FetchLSM("border", conf.borderTexture, "Interface\\Tooltips\\UI-Tooltip-Border") or "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = math.max(1, SafeNum(conf.edgeSize, 8)), padding = 0,
                color = { r = SafeNum(conf.borderColorR, 1), g = SafeNum(conf.borderColorG, 1),
                    b = SafeNum(conf.borderColorB, 1), a = SafeNum(conf.borderColorA, .35) } } },
        fiveSecondLine = { x = 0, y = fiveY, width = timelineX, height = fiveWidth,
            texture = "Interface\\Buttons\\WHITE8X8",
            color = { r = Clamp01(db.fiveSecLineColorR, 1), g = Clamp01(db.fiveSecLineColorG, .9),
                b = Clamp01(db.fiveSecLineColorB, .35), a = Clamp01(db.fiveSecLineColorA, .85) } },
    }
    local entries, spells = {}, BuildBunBarPreviewSpells()
    for index, spell in ipairs(spells) do
        local remain = SAMPLE_REMAINING[index] or (index * 3)
        local distance = moveDown and timelineLen * (remain / ACTIVE_WINDOW_SECS)
            or timelineLen * (1 - (remain / ACTIVE_WINDOW_SECS))
        local y = math.max(0, math.min(timelineLen - iconHeight, distance - iconHeight * .5))
        local iconX = (timelineX - iconWidth) * .5
        local texts = {}
        if nameStyle.enabled ~= false then
            local leftSide = tostring(nameStyle.side or "RIGHT"):upper() == "LEFT"
            texts[#texts + 1] = {
                elementID = "core.spellName", text = spell.name, x = leftSide and (iconX - nameWidth + SafeNum(nameStyle.x, 0)) or (iconX + iconWidth + SafeNum(nameStyle.x, 0)),
                y = y + (iconHeight - nameFont.size) * .5 + SafeNum(nameStyle.y, 0), width = nameWidth, height = math.max(12, nameFont.size + 6),
                font = nameFont.font, size = nameFont.size, flags = nameFont.flags, color = nameFont.color,
                shadowColor = nameFont.shadowColor, shadowX = nameFont.shadowX, shadowY = nameFont.shadowY,
                justifyH = leftSide and "RIGHT" or "LEFT",
            }
        end
        if timeStyle.enabled ~= false then
            local label = BUNBAR_PREVIEW_TIMES[index] or tostring(remain)
            texts[#texts + 1] = {
                elementID = "core.time", text = label, x = iconX + SafeNum(timeStyle.x, 0),
                y = y + (iconHeight - timeFont.size) * .5 + SafeNum(timeStyle.y, 0), width = iconWidth, height = math.max(12, timeFont.size + 6),
                font = timeFont.font, size = timeFont.size, flags = timeFont.flags, color = timeFont.color,
                shadowColor = timeFont.shadowColor, shadowX = timeFont.shadowX, shadowY = timeFont.shadowY,
                justifyH = "CENTER",
            }
        end
        local alerts = {}
        if alertStyle.showIcon ~= false then
            local defs = CollectAlertVisuals(BUNBAR_PREVIEW_ICON_FLAGS[index] or 0)
            while #defs > 2 do table.remove(defs) end
            local hasPair = #defs == 2
            local aw = math.max(6, SafeNum(alertStyle.width, 20))
            local ah = math.max(6, SafeNum(alertStyle.height, 20))
            if hasPair then aw, ah = math.max(4, math.floor(aw / 2)), math.max(4, math.floor(ah / 2)) end
            for alertIndex, alert in ipairs(defs) do
                local rowOffset = hasPair and (alertIndex == 1 and math.floor(ah * .5) or -math.floor(ah * .5)) or 0
                alerts[#alerts + 1] = { elementID = "bunbar.alertIcons", atlas = alert.atlas, texture = alert.atlas and nil or alert.file,
                    left = alert.left, right = alert.right, top = alert.top, bottom = alert.bottom,
                    x = iconX - aw + SafeNum(alertStyle.x, 0), y = y + (iconHeight - ah) * .5 + SafeNum(alertStyle.y, 0) + rowOffset, width = aw, height = ah,
                    color = { r = 1, g = 1, b = 1, a = 1 } }
            end
        end
        entries[#entries + 1] = {
            itemID = "bunbar.sample." .. tostring(index),
            icon = { elementID = "core.icon", texture = spell.iconID, x = iconX, y = y, width = iconWidth, height = iconHeight,
                color = { r = 1, g = 1, b = 1, a = iconStyle.showIcon == false and 0 or 1 },
                border = { enabled = iconStyle.showBorder ~= false,
                    texture = FetchLSM("border", iconStyle.borderTexture, "Interface\\Tooltips\\UI-Tooltip-Border") or "Interface\\Tooltips\\UI-Tooltip-Border",
                    edgeSize = math.max(1, SafeNum(iconStyle.borderSize, 1)), padding = math.max(0, SafeNum(iconStyle.borderPadding, 0)),
                    color = { r = SafeNum(iconStyle.borderColorR, 0), g = SafeNum(iconStyle.borderColorG, 0),
                        b = SafeNum(iconStyle.borderColorB, 0), a = SafeNum(iconStyle.borderColorA, 1) } } },
            texts = texts, alertIcons = alerts,
        }
    end
    return { timeline = timeline, entries = entries }
end

-- =============================================================
-- Standard static timeline preview
-- =============================================================
-- The runtime pool and OnUpdate below remain BunBar business. Preview is a
-- declarative snapshot only: no runtime Node, Scheduler record, or private
-- hitbox is ever created by this module.
local function RenderWorldTimeline(host)
    if worldTimelinePreview then worldTimelinePreview:Release() end
    for _, node in pairs(activeNodes) do node:Hide() end
    worldTimelinePreview = EXUI:CreateStandardTimelinePanelPreview(host, MODULE_KEY)
    local presentation = BuildBunBarTimelinePresentation("world")
    worldTimelinePreview:Render(presentation.timeline, presentation.entries)
    RefreshAnchorVisibility()
    return worldTimelinePreview
end

function BunBar:RenderWorld(host)
    return RenderWorldTimeline(host)
end

function BunBar:ReleaseWorld()
    if worldTimelinePreview then worldTimelinePreview:Release() end
    worldTimelinePreview = nil
    RuntimeTick(0, GetTime())
    RefreshAnchorVisibility()
end

function BunBar:GetWorldBounds()
    if not worldTimelinePreview then return nil end
    local db = DB()
    local trackHeight = math.max(5, SafeNum(db.trackHeight, EX_DEFAULTS.module.trackHeight))
    local timelineLen = math.max(120, SafeNum(db.width, EX_DEFAULTS.module.width))
    local nameStyle = type(db.font_spell) == "table" and db.font_spell or DEFAULT_FONT_NAME
    local nameWidth = nameStyle.autoWidth == false and math.max(80, SafeNum(nameStyle.fixedWidth, 200)) or 200
    local left = -math.max(60, trackHeight * .5 + 12)
    local right = math.max(60, trackHeight * .5 + nameWidth + 40)
    return {
        anchor = worldTimelinePreview.root,
        left = left, right = right, bottom = -timelineLen * .5, top = timelineLen * .5,
        width = right - left, height = timelineLen, anchorOffsetX = (left + right) * .5, anchorOffsetY = 0,
    }
end

function BunBar:ShowPanelPreview(dock)
    panelSurface = self:GetStandardPreviewSurface()
    return panelSurface:Render({ dock = dock, ruleKey = "bunbar.static", state = {} })
end

function BunBar:RefreshPanelPreview(dock)
    return self:ShowPanelPreview(dock)
end

function BunBar:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
end

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end

    anchorController, standardAnchorGroupOptions = EXUI:CreateStandardModuleAnchor({
        moduleKey = MODULE_KEY,
        frameName = "ExBoss_BunBarAnchor",
        title = L["束状条"],
        getDB = DB,
        offsetXKey = "anchorX",
        offsetYKey = "anchorY",
        syncWidgets = {
            "anchorX",
            "anchorY",
            "attachToCustom",
            "customAttachTarget",
        },
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        widgetRanges = {
            anchorX = { min = -1000, max = 1000, step = 1 },
            anchorY = { min = -600, max = 600, step = 1 },
        },
        initialWidth = 420,
        initialHeight = 50,
        clampedToScreen = false,
        frameStrata = "DIALOG",
        anchorPoint = "CENTER",
        relativePoint = "CENTER",
        onCreateFrame = function(_, owner)
            owner:Hide()
        end,
    })

    return anchorController
end

function BunBar:GetStandardAnchorGroupOptions()
    EnsureAnchorController()
    return standardAnchorGroupOptions
end

CreateAnchor = function()
    if anchorFrame then return end

    local db = DB()
    anchorFrame = EnsureAnchorController():Ensure()

    local fiveSecLine = ExwindTools.UI:CreateVisualTexture(anchorFrame, EXBORDERFRAME)
    fiveSecLine:SetColorTexture(1.0, 0.90, 0.35, 0.85)
    anchorFrame.FiveSecLine = fiveSecLine
    UpdateAnchorVisuals()
    _updateFrame:SetParent(anchorFrame)
    RefreshAnchorVisibility()
end

local function CreateTestBars(count)
    if not anchorFrame then CreateAnchor() end
    count = math.max(1, math.min(tonumber(count) or 5, 5))

    local now = GetTime()
    local preset = { 5, 10, 15, 20, 25 }
    for i = 1, count do
        _testSeed = _testSeed + 1
        local id = TEST_PREFIX .. tostring(_testSeed)
        local rem = preset[i] or (i * 5)
        local dur = math.max(rem + 6, 10)
        local timer = {
            id = id,
            barPriority = ((i - 1) % 3) + 1,
            castTime = now + rem,
            duration = dur,
            displayName = IsNonChineseLocale() and ("Test Spell " .. i) or ("测试技能 " .. i),
            spellID = 136197,
            iconFlags = (i % 3 == 1 and 128) or (i % 3 == 2 and 256) or 1,
            _mode = "test",
        }
        syntheticTimers[id] = timer
        testIDs[id] = true
        BunBar:AddTimer(timer)
    end
end

local function ClearTestBars()
    for id in pairs(testIDs) do
        ReleaseNode(id)
    end
end

local _movingBuf = {}
local _queueBuf = {}
local _releaseBuf = {}

local function ApplyPlacement(node, targetX, targetY, remaining, introKind, isQueue, now, elapsed, cfg, updateText,
                              timelineLen, iconSize)
    if not node then return end

    if introKind == "sudden" then
        node._displayX = targetX + SUDDEN_INTRO_OFFSET_X
        node._displayY = targetY
        node._introKind = "sudden"
        node._introFromX = node._displayX
        node._introFromY = node._displayY
        node._introStart = now
        node._introEnd = now + SUDDEN_INTRO_DURATION
    elseif introKind == "queue" then
        node._displayX = targetX
        node._displayY = targetY - QUEUE_INTRO_OFFSET_Y
        node._introKind = "queue"
        node._introFromX = node._displayX
        node._introFromY = node._displayY
        node._introStart = now
        node._introEnd = now + QUEUE_INTRO_DURATION
    elseif node._displayX == nil or node._displayY == nil then
        node._displayX = targetX
        node._displayY = targetY
    elseif node._introEnd and now < node._introEnd then
        local span = math.max(0.01, node._introEnd - (node._introStart or (node._introEnd - 0.01)))
        local t = (now - (node._introStart or (node._introEnd - span))) / span
        local ease = EaseOutCubic(t)
        local fromX = node._introFromX or targetX
        local fromY = node._introFromY or targetY
        if node._introKind == "sudden" then
            node._displayX = fromX + (targetX - fromX) * ease
            node._displayY = targetY
        elseif node._introKind == "queue" then
            node._displayX = targetX
            node._displayY = fromY + (targetY - fromY) * ease
        else
            node._displayX = fromX + (targetX - fromX) * ease
            node._displayY = fromY + (targetY - fromY) * ease
        end
    else
        if node._introEnd and now >= node._introEnd then
            node._introKind = nil
            node._introStart = nil
            node._introEnd = nil
            node._introFromX = nil
            node._introFromY = nil
        end
        local lerpAlpha = 1
        if POSITION_SMOOTH_TIME > 0 then
            lerpAlpha = 1 - math.exp(-elapsed / POSITION_SMOOTH_TIME)
            if lerpAlpha < 0 then lerpAlpha = 0 end
            if lerpAlpha > 1 then lerpAlpha = 1 end
        end
        node._displayX = node._displayX + (targetX - node._displayX) * lerpAlpha
        node._displayY = node._displayY + (targetY - node._displayY) * lerpAlpha
    end

    node:ClearAllPoints()
    node:SetPoint("CENTER", anchorFrame, "TOPLEFT", node._displayX, -node._displayY)

    if node.NameText then
        node.NameText:SetShown(cfg.showName)
    end
    -- 实战条到达时间轴终点后仍可等待施放/调度清理；只隐藏时间文字，
    -- 节点本体、图标与其他视觉状态保持正常显示。
    local showTimeText = cfg.showTimer and remaining > 0
    if node.TimeText then
        node.TimeText:SetShown(showTimeText)
    end
    if node.TimeBG then
        node.TimeBG:SetShown(false)
    end

    local iconHalf = iconSize * 0.5
    local dy = node._displayY or targetY
    local outOfRange = (not isQueue) and (dy > timelineLen + iconHalf + 2 or dy < -iconHalf - 2)
    if outOfRange then
        node:Hide()
    else
        if node._waitingTimelineFinish == true then
            node:SetAlpha(0.62 + 0.38 * math.abs(math.sin((now or GetTime()) * 5.5)))
        else
            node:SetAlpha(1)
        end
        node:SetScale(1)
        node:Show()
    end
    if updateText and showTimeText and node.TimeText then
        local txt = FormatTime(remaining)
        local db = DB()
        local timeFont = (type(db.font_timer) == "table") and db.font_timer or DEFAULT_FONT_TIME
        node.TimeText:SetText(txt)
        UpdateTimeTextBounds(node, txt, iconSize, SafeNum(timeFont.size, DEFAULT_FONT_TIME.size))
    end
end

RuntimeTick = function(elapsed, nowOverride)
    if not anchorFrame then return end

    _textElapsed = _textElapsed + elapsed
    local updateText = false
    if _textElapsed >= TEXT_UPDATE_INTERVAL then
        _textElapsed = 0
        updateText = true
    end

    if _sortDirty then
        RebuildTrackOrder()
    end

    local cfg = GetRuntimeConfig()
    local timelineLen = cfg.timelineLen
    local moveDir = cfg.moveDir
    local iconSize = cfg.iconSize
    local trackHeight = cfg.trackHeight
    local now = nowOverride or GetTime()
    local minIconGap = iconSize + 2
    wipe(_movingBuf)
    wipe(_queueBuf)
    wipe(_releaseBuf)

    for _, node in pairs(activeNodes) do
        node._wasMoving = node._isMovingNow
        node._isMovingNow = false
        node._wasQueued = node._isQueuedNow
        node._isQueuedNow = false
    end

    for timerID, node in pairs(activeNodes) do
        if node._outroEnd then
            if UpdateOutro(node, now) then
                table.insert(_releaseBuf, timerID)
            end
        else
            local timer = GetRuntimeTimer(timerID)
            if not timer then
                StartOutro(node)
                if UpdateOutro(node, now) then
                    table.insert(_releaseBuf, timerID)
                end
            else
                local remaining = timer.castTime - now
                node._waitingTimelineFinish = timer.fixedAIWaitingTimelineFinish == true
                if remaining <= 0 then
                    if timer._mode == "test" then
                        StartOutro(node)
                        if UpdateOutro(node, now) then
                            table.insert(_releaseBuf, timerID)
                        end
                        remaining = 0
                    elseif timer._mode == "external" then
                        StartOutro(node)
                        if UpdateOutro(node, now) then
                            table.insert(_releaseBuf, timerID)
                        end
                        remaining = 0
                    else
                        -- 实战条不在这里提前删，保持在触发线直到 OnCast / 调度清理。
                        remaining = 0
                    end
                end

                if node._outroEnd then
                    -- 已进入退场动画，跳过轨道计算
                elseif remaining > QUEUE_HIDE_SECS then
                    node:Hide()
                    node._displayX = nil
                    node._displayY = nil
                    node._introKind = nil
                    node._introStart = nil
                    node._introEnd = nil
                    node._introFromX = nil
                    node._introFromY = nil
                elseif remaining > ACTIVE_WINDOW_SECS then
                    node._isQueuedNow = true
                    node._introKind = nil
                    node._introStart = nil
                    node._introEnd = nil
                    node._introFromX = nil
                    node._introFromY = nil
                    node._rtRemaining = remaining
                    table.insert(_queueBuf, node)
                elseif node._trackIndex then
                    node._isMovingNow = true
                    local y = 0
                    local progress = remaining / ACTIVE_WINDOW_SECS
                    if moveDir == "DOWN" then
                        y = timelineLen * (1 - progress)
                    else
                        y = timelineLen * progress
                    end
                    node._rtRemaining = remaining
                    node._rtTargetY = y
                    node._rtIntroKind = (node._wasQueued and "queue") or ((not node._wasMoving) and "sudden") or nil
                    table.insert(_movingBuf, node)
                else
                    node:Hide()
                end
            end
        end
    end

    if #_movingBuf > 1 then
        table.sort(_movingBuf, function(a, b)
            return (a._rtTargetY or 0) < (b._rtTargetY or 0)
        end)
    end

    if #_movingBuf > 1 then
        for i = #_movingBuf - 1, 1, -1 do
            local nextNode = _movingBuf[i + 1]
            local cur = _movingBuf[i]
            local nextY = nextNode and nextNode._rtTargetY or 0
            local curY = cur and cur._rtTargetY or 0
            if nextY - curY < minIconGap then
                cur._rtTargetY = nextY - minIconGap
            end
        end
    end

    if #_queueBuf > 1 then
        table.sort(_queueBuf, function(a, b)
            return (a._rtRemaining or 0) < (b._rtRemaining or 0)
        end)
    end

    if #_queueBuf > 0 then
        local queueEdge = (moveDir == "DOWN") and 0 or timelineLen
        local queueSign = (moveDir == "DOWN") and -1 or 1
        for i, node in ipairs(_queueBuf) do
            ApplyPlacement(
                node,
                trackHeight * 0.5,
                queueEdge + queueSign * (i * minIconGap),
                node._rtRemaining or 0,
                nil,
                true,
                now,
                elapsed,
                cfg,
                updateText,
                timelineLen,
                iconSize
            )
        end
    end

    for _, node in ipairs(_movingBuf) do
        ApplyPlacement(
            node,
            trackHeight * 0.5,
            node._rtTargetY or 0,
            node._rtRemaining or 0,
            node._rtIntroKind,
            false,
            now,
            elapsed,
            cfg,
            updateText,
            timelineLen,
            iconSize
        )
    end

    if #_releaseBuf > 0 then
        for _, id in ipairs(_releaseBuf) do
            ReleaseNode(id)
        end
    end
end

_updateFrame = CreateFrame("Frame")
_updateFrame:Hide()
SetClickThrough(_updateFrame)
EXUI:RequireLegacyRuntimeTickOwner(MODULE_KEY, "ExBoss.BunBar runtime OnUpdate")
_updateFrame:SetScript("OnUpdate", function(_, elapsed)
    RuntimeTick(elapsed)
end)

function BunBar:AddTimer(timer)
    local db = DB()
    if db and db.enabled == false then return end
    if not anchorFrame then CreateAnchor() end
    RefreshAnchorVisibility()
    if activeNodes[timer.id] then return end

    local node = AcquireNode(timer.id, timer.barPriority)
    if not node then return end

    ApplyTimerToNode(node, timer)

    _sortDirty = true
    RefreshAnchorVisibility()
end

function BunBar:RefreshTimer(timer)
    if type(timer) ~= "table" then
        return
    end
    local node = activeNodes[timer.id]
    if not node then
        return
    end

    ApplyTimerToNode(node, timer)

    _sortDirty = true
    RefreshAnchorVisibility()
end

function BunBar:OnCast(timer)
    local node = activeNodes[timer.id]
    if node then
        StartOutro(node)
    else
        ReleaseNode(timer.id)
    end
end

-- 副本通用机制的独立倒数入口：使用本模块已有 synthetic timer 生命周期，
-- 不写入 Scheduler，也不会参与普通时间轴的施放回调。
function BunBar:StartExternalTimer(timer)
    if type(timer) ~= "table" or timer.id == nil then
        return false
    end
    local policy = ExBoss and ExBoss.DisplayPolicy
    if policy and type(policy.ShouldShowTimerOnBar) == "function"
        and policy.ShouldShowTimerOnBar(timer, "bun") ~= true then
        self:StopExternalTimer(timer.id)
        return false
    end
    timer._mode = "external"
    if activeNodes[timer.id] then
        ReleaseNode(timer.id)
    end
    syntheticTimers[timer.id] = timer
    self:AddTimer(timer)
    return true
end

function BunBar:StopExternalTimer(timerID)
    syntheticTimers[timerID] = nil
    ReleaseNode(timerID)
end

function BunBar:OnPreAlert(timer)
    -- 束状条不需要额外预警动画
end

function BunBar:ReleaseAll()
    local ids = {}
    for id in pairs(activeNodes) do
        table.insert(ids, id)
    end
    for _, id in ipairs(ids) do
        ReleaseNode(id)
    end
    syntheticTimers = {}
    testIDs = {}
    RefreshAnchorVisibility()
end

function BunBar:RefreshVisuals(options)
    options = type(options) == "table" and options or {}
    local rebuildPanelPreview = options.rebuildPanelPreview
    if rebuildPanelPreview == nil then rebuildPanelPreview = true end
    if anchorFrame then
        EnsureAnchorController():ApplyPosition()
    end
    UpdateAnchorVisuals()
    for _, node in pairs(activeNodes) do
        UpdateNodeVisuals(node, node._priority)
    end
    _sortDirty = true
    InvalidateRuntimeConfig()
    -- Slider drag has already patched the materialized Timeline session.  Only
    -- a path whose Core patch reports unsupported may rebuild it on mouse-up.
    if rebuildPanelPreview and panelSurface then BunBar:RefreshPanelPreview(panelSurface.dock) end
    if worldTimelinePreview then
        local presentation = BuildBunBarTimelinePresentation("world")
        worldTimelinePreview:Render(presentation.timeline, presentation.entries)
    end
    ExwindTools.UI:RefreshEditableModule("EXBoss", "bunbar")
    RefreshAnchorVisibility()
end

function BunBar:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

function BunBar:CreateTestBars(count)
    CreateTestBars(count)
end

function BunBar:ClearTestBars()
    ClearTestBars()
end

function BunBar:OnRuntimeTick(elapsed, now)
    RuntimeTick(elapsed, now)
end

for _, path in ipairs({ "anchorX", "anchorY", "attachToCustom", "customAttachTarget" }) do CONFIG_SCHEMA_PATHS[path] = true end
CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    reapplyExisting = function()
        local function reapply(surface)
            if not surface then
                return true
            end
            if type(surface.ReapplyPanelPresentation) == "function" then
                return surface:ReapplyPanelPresentation() == true
            elseif type(surface.ReapplyCurrentItems) == "function" then
                return surface:ReapplyCurrentItems(function() end) == true
            end
            return false
        end
        local allPatched = reapply(panelSurface)
        if worldTimelinePreview then
            if type(worldTimelinePreview.ReapplyCurrent) == "function" then
                local presentation = BuildBunBarTimelinePresentation("world")
                if worldTimelinePreview:ReapplyCurrent(presentation.timeline, presentation.entries) ~= true then
                    allPatched = false
                end
            else
                allPatched = false
            end
        end
        if anchorFrame then
            EnsureAnchorController():ApplyPosition()
        end
        UpdateAnchorVisuals()
        for _, node in pairs(activeNodes) do
            UpdateNodeVisuals(node, node._priority)
        end
        InvalidateRuntimeConfig()
        return allPatched
    end,
    schemaPaths = CONFIG_SCHEMA_PATHS,
})

local function EnsurePanelSurface()
    if panelSurface then return panelSurface end
    panelSurface = EXUI:CreateStandardPreviewSurface({
        moduleKey = MODULE_KEY,
        kind = "timeline",
        binding = CONFIG_BINDING,
        buildPresentation = function(_, mode) return BuildBunBarTimelinePresentation(mode) end,
        interactionSchema = INTERACTION_SCHEMA,
        requiredPositionGuiKeys = { "font_spell", "font_timer", "alertIcons" },
    })
    return panelSurface
end

BunBar.StandardConfigBinding = CONFIG_BINDING
BunBar.InteractionSchema = INTERACTION_SCHEMA
BunBar.BuildPreviewPresentation = BuildBunBarTimelinePresentation
local function RefreshActiveSurfaces(_, phase)
    local allPatched = CONFIG_BINDING.reapplyExisting()
    -- 拖动期间只走 Core 的轻量补丁；松开滑块时若该字段不能补丁，才完整重建。
    if phase == "committed" and allPatched ~= true then
        BunBar:RefreshVisuals({ rebuildPanelPreview = true })
    end
    return allPatched
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })
function BunBar:GetStandardPreviewSurface()
    return EnsurePanelSurface()
end

-- 运行时节点池的空闲期预热入口。预热对象不进入 activeNodes/nodeList，
-- 因而不会参与 Scheduler、轨道排序或 BunBar 的运行时 OnUpdate。
function BunBar:GetPrewarmTargetCount()
    local db = DB()
    return db and db.enabled == false and 0 or PREWARM_NODE_COUNT
end

function BunBar:AcquirePrewarmObject()
    if not anchorFrame then CreateAnchor() end
    local fac = Factory()
    if not (fac and anchorFrame) then return nil end
    local node = fac:Acquire(POOL_TYPE, anchorFrame)
    node._priority = 2
    node._iconFlags = 0
    node._timerTextColor = nil
    node._eventColor = nil
    node._occurrenceCountText = nil
    node:SetAlpha(1)
    node:SetScale(1)
    SetClickThrough(node)
    UpdateNodeVisuals(node, 2)
    node:Hide()
    return node
end

function BunBar:ReleasePrewarmObject(node)
    if not node then return end
    node:Hide()
    node:ClearAllPoints()
    node._priority = nil
    node._iconFlags = 0
    node._timerTextColor = nil
    node._eventColor = nil
    node._occurrenceCountText = nil
    local fac = Factory()
    if fac then fac:Release(POOL_TYPE, node) end
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        CreateAnchor()
        UpdateAnchorVisuals()
    end)
end)

-- 模块只交出身份、整体 anchor、纯预览快照与 panel intent 回写；世界编辑的
-- 生命周期、覆盖层、左拖和右键路由均由唯一 ExwindEditMode.lua 管理。
EXUI:RegisterEditableModule({
    addon = "EXBoss",
    key = "bunbar",
    name = L["束状条"],
    settingsPage = "bunbar",
    orientation = "VERTICAL",
    -- 运行时 anchor 的语义原点是竖向轨道中心；名称向右延展不能把整个
    -- anchor 改写为内容并集中心，否则世界覆盖层会只落到文字一侧。
    worldAnchorMode = "semantic-root",
    editOverlay = { titleFontSize = 30 },
    getAnchor = function()
        CreateAnchor()
        if not anchorFrame then error("BunBar anchor is unavailable", 2) end
        return anchorFrame
    end,
    RenderWorld = function(host) return BunBar:RenderWorld(host) end,
    ReleaseWorld = function() return BunBar:ReleaseWorld() end,
    GetWorldBounds = function() return BunBar:GetWorldBounds() end,
    OnWorldPreviewStateChanged = function(_)
        -- 唯一编辑模式已切换标准世界预览标记：进入时隐藏运行时轨道，退出时
        -- 根据真实 activeNodes 决定是否恢复。该模块不拥有 world preview 生命周期。
        RefreshAnchorVisibility()
    end,
})

BunBar._active = activeNodes
