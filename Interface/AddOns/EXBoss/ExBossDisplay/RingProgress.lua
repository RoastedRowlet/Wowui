---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- ExBossDisplay/RingProgress.lua
-- 屏幕中央圆环进度（透明背景）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or _G.ExwindToolsUI

ExBoss.UI.RingProgress = ExBoss.UI.RingProgress or {}
local Ring = ExBoss.UI.RingProgress

local MODULE_KEY = "ExBoss.RingProgress"
local L = ExBoss.L or setmetatable({}, { __index = function(_, key) return key end })

local DEFAULTS = {
    enabled = true,
    style = "thin1", -- thin1 | thin2 | classic
    size = 170,
    alpha = 0.95,
    castFillMode = "cw_fill",
    channelFillMode = "ccw_decay",
    ringColorR = 0.1,
    ringColorG = 0.8,
    ringColorB = 1.0,
    ringColorA = 1.0,
    bgEnabled = false,
    bgAlpha = 0.3,
    bgColorR = 0.3,
    bgColorG = 0.3,
    bgColorB = 0.3,
    bgColorA = 1.0,
    anchorX = 0,
    anchorY = 0,
    attachToCustom = false,
    customAttachTarget = "",
    font_spell = {
        enabled = false,
        autoWidth = false,
        font = "默认",
        size = 16,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        justifyH = "CENTER", justifyV = "MIDDLE",
        x = 0, y = 30,
    },
    font_timer = {
        autoWidth = false,
        font = "默认",
        size = 20,
        r = 1, g = 1, b = 1, a = 1,
        outline = "OUTLINE",
        shadow = false,
        shadowX = 1, shadowY = -1,
        justifyH = "CENTER", justifyV = "MIDDLE",
        x = 0, y = 0,
    },
}

local STYLE_TEXTURES = {
    thin1 = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RingWhiteThin1",
    thin2 = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RingWhiteThin2",
    classic = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RingWhite",
}

local frame
local anchorController
local cdForward
local cdReverse
local bgRing
local textOverlay
local nameText
local timeText
local timeDurationBinding
local timeDurationFormatter
local activeAnim = nil
local eventFrame = nil
local panelPreview
local panelDock
local panelSurface
local GetActiveCooldown
local ApplyDefaults
local Ensure
local EnsureAnchorController
local ClearTimeDurationBinding
local BindTimeDurationObject
local CreateDurationFromEnd
local ClearCooldownBackgrounds

local CAST_CHECK_MARGIN = 0.1
local CAST_CHECK_GOOD = { r = 0.10, g = 0.95, b = 0.20 }
local CAST_CHECK_BAD = { r = 1.00, g = 0.12, b = 0.08 }

local function SafeNum(v, def)
    local n = tonumber(v)
    if n == nil then
        return def
    end
    return n
end

local function Clamp01(v, def)
    local n = tonumber(v)
    if n == nil then
        n = tonumber(def)
    end
    if n == nil then
        n = 1
    end
    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    return n
end

local function NormalizeUnitToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    unit = tostring(unit):lower()
    if unit == "" then
        return nil
    end
    return unit
end

local function NormalizeCastBarID(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return id
end

local function IsNonChineseLocale()
    local locale = ExwindTools and ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale() or GetLocale()
    return locale ~= "zhCN" and locale ~= "zhTW"
end

local function SetClickThrough(obj)
    if not obj then return end
    obj:EnableMouse(false)
    if obj.SetMouseClickEnabled then
        obj:SetMouseClickEnabled(false)
    end
    if obj.SetMouseMotionEnabled then
        obj:SetMouseMotionEnabled(false)
    end
end

local function DB()
    local db = ExwindTools:GetModuleDB(MODULE_KEY, DEFAULTS)
    ApplyDefaults(db, DEFAULTS)
    return db
end

function Ring:GetDB()
    return DB()
end

local function GetTexturePath(style)
    style = tostring(style or ""):lower()
    return STYLE_TEXTURES[style] or STYLE_TEXTURES.thin1
end

local function GetConfiguredColor(db)
    return Clamp01(db.ringColorR, DEFAULTS.ringColorR),
           Clamp01(db.ringColorG, DEFAULTS.ringColorG),
           Clamp01(db.ringColorB, DEFAULTS.ringColorB)
end

local function ApplyFont(fs, fontDB)
    if not fs then
        return
    end
    local staticDB = ExwindTools.DB_Static
    if staticDB and staticDB.ApplyFont then
        staticDB:ApplyFont(fs, fontDB)
        return
    end
    fs:SetFontObject(GameFontNormal)
end

ApplyDefaults = function(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function GetPlayerCastEndAt()
    local now = GetTime()

    if UnitCastingInfo then
        local _name, _text, _texture, _startTimeMS, endTimeMS = UnitCastingInfo("player")
        local endAt = tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then
            return endAt
        end
    end

    if UnitChannelInfo then
        local _name, _text, _texture, _startTimeMS, endTimeMS = UnitChannelInfo("player")
        local endAt = tonumber(endTimeMS) and (tonumber(endTimeMS) / 1000) or nil
        if endAt and endAt > now then
            return endAt
        end
    end

    return nil
end

local function ResolveCastCheckColor()
    local castEndAt = GetPlayerCastEndAt()
    local ringEndAt = activeAnim and tonumber(activeAnim.endAt) or nil
    if castEndAt and ringEndAt and castEndAt > (ringEndAt - CAST_CHECK_MARGIN) then
        return CAST_CHECK_BAD
    end
    return CAST_CHECK_GOOD
end

local function IsBadCheckColor(color)
    return type(color) == "table"
        and color.r == CAST_CHECK_BAD.r
        and color.g == CAST_CHECK_BAD.g
        and color.b == CAST_CHECK_BAD.b
end

local function ResolveActiveColor(db)
    if activeAnim then
        local hasCheck = false
        local c
        if activeAnim.castCheckEnabled == true then
            hasCheck = true
            c = ResolveCastCheckColor()
            if IsBadCheckColor(c) then
                return c.r, c.g, c.b
            end
        end
        if hasCheck then
            return CAST_CHECK_GOOD.r, CAST_CHECK_GOOD.g, CAST_CHECK_GOOD.b
        end
    end
    return GetConfiguredColor(db)
end

local function ApplyActiveColor()
    if not activeAnim then
        return
    end
    local db = DB()
    local r, g, b = ResolveActiveColor(db)
    local a = Clamp01(db.alpha, DEFAULTS.alpha)

    local function ApplyCooldownColor(cd)
        if not cd then return end
        if cd.SetSwipeColor then
            cd:SetSwipeColor(r, g, b, a)
        end

        -- 部分客户端/贴图组合不会把 SetSwipeColor 立即应用到自定义 swipe 贴图。
        -- 同步改可见 Texture 的 VertexColor，确保圆环颜色实时变化。
        local regionCount = cd.GetNumRegions and cd:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, cd:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetVertexColor then
                region:SetVertexColor(r, g, b, a)
            end
        end
    end

    ApplyCooldownColor(cdForward)
    ApplyCooldownColor(cdReverse)
    -- ApplyCooldownColor 为兼容自定义 swipe 会遍历原生 Cooldown 的 texture。
    -- 这一步会顺手改到模板背景；必须立即清空，避免它作为一层半透明雾盖在
    -- 父级 bgRing 和前景 swipe 之间。
    ClearCooldownBackgrounds()
end

local function ResolveFillMode(entry, db)
    if type(entry) == "table" and entry.reverse ~= nil then
        return (entry.reverse == true) and "ccw_decay" or "cw_decay"
    end

    local castKind = type(entry) == "table" and tostring(entry.castKind or "") or ""
    local mode
    if castKind == "channel" then
        mode = tostring(db.channelFillMode or DEFAULTS.channelFillMode)
    else
        mode = tostring(db.castFillMode or DEFAULTS.castFillMode)
    end
    if mode ~= "cw_fill" and mode ~= "cw_decay" and mode ~= "ccw_fill" and mode ~= "ccw_decay" then
        mode = DEFAULTS.castFillMode
    end
    return mode
end

local function ResolveReverseFromMode(mode)
    if mode == "cw_fill" then
        return true
    elseif mode == "cw_decay" then
        return false
    elseif mode == "ccw_fill" then
        return false
    elseif mode == "ccw_decay" then
        return true
    end
    return false
end

local function ResolveDisplayRemaining(duration, remaining, mode)
    if mode == "ccw_fill" or mode == "ccw_decay" then
        local elapsed = math.max(0, duration - remaining)
        return math.max(0.01, elapsed)
    end
    return remaining
end

local function ResolveDisplayName(entry)
    local spellID = tonumber(type(entry) == "table" and entry.spellID or nil)
    local rename = type(entry) == "table" and entry.ringRenameText or nil
    local progressName = type(entry) == "table" and entry.progressDisplayName or nil
    local name = type(entry) == "table" and entry.displayName or nil
    if type(entry) == "table" and entry.ringRenameEnabled == true and type(rename) == "string" and rename ~= "" then
        return rename
    end
    if type(entry) == "table" and entry.preferSpellName == true then
        if type(progressName) == "string" and progressName ~= "" then
            return progressName
        end
        if spellID and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and info.name then
                return info.name
            end
        end
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo and IsNonChineseLocale() then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    if type(name) == "string" and name ~= "" then
        return name
    end
    if type(progressName) == "string" and progressName ~= "" then
        return progressName
    end
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return info.name
        end
    end
    return ""
end

local function DoesOwnerMatch(state, owner)
    if type(state) ~= "table" or type(owner) ~= "table" then
        return false
    end
    if owner.source and tostring(state.ownerSource or "") ~= tostring(owner.source or "") then
        return false
    end
    if owner.castKind and tostring(state.ownerCastKind or "") ~= tostring(owner.castKind or "") then
        return false
    end
    local ownerCastBarID = NormalizeCastBarID(owner.castBarID)
    local stateCastBarID = NormalizeCastBarID(state.ownerCastBarID)
    if ownerCastBarID ~= nil and stateCastBarID ~= ownerCastBarID then
        return false
    end
    if owner.runtime ~= nil and state.ownerRuntime ~= owner.runtime then
        return false
    end
    if owner.encounterID ~= nil and tonumber(state.ownerEncounterID) ~= tonumber(owner.encounterID) then
        return false
    end
    if owner.eventID ~= nil and tonumber(state.ownerEventID) ~= tonumber(owner.eventID) then
        return false
    end
    if (owner.encounterID ~= nil or owner.eventID ~= nil)
        and tostring(state.ownerSource or "") == "boss"
        and tostring(owner.source or "") == "boss"
    then
        return true
    end
    local ownerUnit = NormalizeUnitToken(owner.unit)
    local stateUnit = NormalizeUnitToken(state.ownerUnit)
    if ownerUnit ~= nil then
        if stateUnit == ownerUnit then
            return true
        end
        if tostring(state.ownerSource or "") == "boss"
            and tostring(owner.source or "") == "boss"
            and ownerCastBarID ~= nil
            and stateCastBarID == ownerCastBarID
        then
            return true
        end
        return false
    end
    return true
end

local function StopAnimation()
    activeAnim = nil
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
    ClearTimeDurationBinding()
    if cdForward then cdForward:SetScript("OnCooldownDone", nil) end
    if cdReverse then cdReverse:SetScript("OnCooldownDone", nil) end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
    if bgRing then bgRing:Hide() end
end

local function EnsureEventFrame()
    if eventFrame then
        return eventFrame
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if unit ~= "player" then
            return
        end
        if not (activeAnim and activeAnim.castCheckEnabled == true) then
            return
        end
        ApplyActiveColor()
    end)
    return eventFrame
end

local function SetCastCheckEventsEnabled(enabled)
    local ef = EnsureEventFrame()
    ef:UnregisterAllEvents()
    if enabled ~= true then
        return
    end
    ef:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    ef:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end

-- 原生 Duration 继续独占倒数文字与秘密值圆环；普通逆时针圆环额外使用
-- 旧版的时间反转驱动，施法检测仍在同一 OnUpdate 中持续刷新红/绿颜色。
local BeginPhase

local function AdvanceActivePhase()
    if not activeAnim then
        return
    end
    local nextIndex = activeAnim.phaseIndex + 1
    if activeAnim.phases and activeAnim.phases[nextIndex] then
        activeAnim.phaseIndex = nextIndex
        BeginPhase(activeAnim.phases[nextIndex])
        return
    end
    StopAnimation()
    Ring:Hide()
end

-- 普通数值的逆时针模式必须沿用旧版的“反转时间进度”算法：
-- SetReverse 只改变扇形方向，不能替代填满/消退的时间轴反转。
-- 秘密值 Duration 不可读取或重建，始终由原生 Duration Object 独占。
local function SetRuntimeUpdatesEnabled()
    if not frame then return end
    if not activeAnim or (activeAnim.castCheckEnabled ~= true and activeAnim.manualProgress ~= true) then
        frame:SetScript("OnUpdate", nil)
        return
    end
    frame:SetScript("OnUpdate", function()
        local anim = activeAnim
        if not anim then
            frame:SetScript("OnUpdate", nil)
            return
        end

        if anim.manualProgress == true then
            local now = GetTime()
            if now >= anim.endAt then
                AdvanceActivePhase()
                return
            end
            local remaining = math.max(0.01, anim.endAt - now)
            local displayRemaining = ResolveDisplayRemaining(anim.duration, remaining, anim.mode)
            -- 旧版公式：将当前 elapsed 映射为 Cooldown 的虚拟剩余时间，
            -- 从而在不改显示倒数文字的前提下反转圆环进度。
            anim.cd:SetCooldown(now + displayRemaining - anim.duration, anim.duration)
        end

        if activeAnim and activeAnim.castCheckEnabled == true then
            ApplyActiveColor()
        elseif activeAnim and activeAnim.manualProgress ~= true then
            frame:SetScript("OnUpdate", nil)
        end
    end)
end

BeginPhase = function(phase)
    local db = DB()
    local mode = phase.mode or ResolveFillMode({ castKind = phase.castKind }, db)
    local reverse = ResolveReverseFromMode(mode)
    local cd, inactiveCd = GetActiveCooldown(reverse)
    if inactiveCd then
        inactiveCd:Hide()
    end

    local duration = math.max(0.1, SafeNum(phase.duration, 5))
    local now = GetTime()
    local initialRemaining = math.max(0.01, math.min(duration, SafeNum(phase.initialRemaining, duration)))
    -- 普通来源必须消费稳定的结束时间，绝不在每次刷新时以 GetTime 重新开始。
    -- Secret Duration 若上游已提供，则不读取、比较或重建，直接交给原生 Cooldown。
    local endAt = tonumber(phase.endTime)
    if not endAt or endAt <= now then
        endAt = now + initialRemaining
    end
    local durationObject = phase.durationObject
    if not durationObject then
        durationObject = CreateDurationFromEnd(endAt, duration)
    end
    -- 只有普通数值的逆时针模式可安全使用旧版起点重算；受保护 Duration
    -- 绝不走此路径，避免读取或伪造秘密值时间。
    local manualProgress = phase.durationObject == nil
        and (mode == "ccw_fill" or mode == "ccw_decay")
    if manualProgress then
        local displayRemaining = ResolveDisplayRemaining(duration, initialRemaining, mode)
        cd:SetCooldown(now + displayRemaining - duration, duration)
    else
        if not cd.SetCooldownFromDurationObject then
            error("RingProgress requires Cooldown:SetCooldownFromDurationObject", 2)
        end
        cd:SetCooldownFromDurationObject(durationObject, true)
    end
    cd:Show()
    frame:Show()
    if bgRing then
        if db.bgEnabled then bgRing:Show() else bgRing:Hide() end
    end
    if nameText then
        nameText:SetText(ResolveDisplayName(phase))
    end
    BindTimeDurationObject(durationObject)

    activeAnim.cd = cd
    activeAnim.mode = mode
    activeAnim.duration = duration
    activeAnim.endAt = endAt
    activeAnim.durationObject = durationObject
    activeAnim.isSecretDuration = phase.durationObject ~= nil
    activeAnim.manualProgress = manualProgress
    if cdForward then cdForward:SetScript("OnCooldownDone", nil) end
    if cdReverse then cdReverse:SetScript("OnCooldownDone", nil) end
    cd:SetScript("OnCooldownDone", function(doneCooldown)
        if not activeAnim or activeAnim.cd ~= doneCooldown then
            return
        end
        if activeAnim.manualProgress == true then
            return
        end
        AdvanceActivePhase()
    end)
    ApplyActiveColor()
    SetRuntimeUpdatesEnabled()
end

local function StartAnimation(phases, opts)
    opts = type(opts) == "table" and opts or {}
    local totalDuration = 0
    for i = 1, #phases do
        totalDuration = totalDuration + math.max(0.1, SafeNum(phases[i] and phases[i].duration, 5))
    end
    local now = GetTime()
    activeAnim = {
        phases = phases,
        phaseIndex = 1,
        cd = nil,
        duration = nil,
        mode = nil,
        endAt = now + totalDuration,
        castCheckEnabled = opts.castCheckEnabled == true,
        ownerSource = type(opts.owner) == "table" and tostring(opts.owner.source or "") or nil,
        ownerUnit = type(opts.owner) == "table" and NormalizeUnitToken(opts.owner.unit) or nil,
        ownerCastKind = type(opts.owner) == "table" and tostring(opts.owner.castKind or "") or nil,
        ownerCastBarID = type(opts.owner) == "table" and NormalizeCastBarID(opts.owner.castBarID) or nil,
        ownerEncounterID = type(opts.owner) == "table" and tonumber(opts.owner.encounterID) or nil,
        ownerEventID = type(opts.owner) == "table" and tonumber(opts.owner.eventID) or nil,
        ownerRuntime = type(opts.owner) == "table" and opts.owner.runtime or nil,
        earlyStopEnabled = type(opts.owner) == "table" and opts.owner.earlyStopEnabled == true or false,
    }
    SetCastCheckEventsEnabled(activeAnim.castCheckEnabled == true)
    BeginPhase(phases[1])
end

local function ApplyVisuals()
    if not frame then return end
    local db = DB()
    local size = SafeNum(db.size, DEFAULTS.size)
    if size < 20 then size = 20 end
    if size > 360 then size = 360 end

    frame:SetSize(size, size)
    EnsureAnchorController():ApplyPosition()

    if textOverlay and textOverlay.SetFrameLevel then
        textOverlay:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
        textOverlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    end
    if cdForward and cdForward.SetFrameLevel then
        cdForward:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    end
    if cdReverse and cdReverse.SetFrameLevel then
        cdReverse:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    end

    if nameText then
        ApplyFont(nameText, db.font_spell)
        if nameText.SetDrawLayer then
            ExwindTools.UI:ApplyVisualLayer(nameText, EXFONTFRAME)
        end
        nameText:ClearAllPoints()
        nameText:SetPoint("CENTER", frame, "CENTER",
            SafeNum(db.font_spell and db.font_spell.x, DEFAULTS.font_spell.x),
            SafeNum(db.font_spell and db.font_spell.y, DEFAULTS.font_spell.y))
        nameText:SetWidth(math.max(80, size - 20))
        nameText:SetJustifyH("CENTER")
        nameText:SetShown(not db.font_spell or db.font_spell.enabled ~= false)
    end
    if timeText then
        ApplyFont(timeText, db.font_timer)
        if timeText.SetDrawLayer then
            ExwindTools.UI:ApplyVisualLayer(timeText, EXFONTFRAME)
        end
        timeText:ClearAllPoints()
        timeText:SetPoint("CENTER", frame, "CENTER",
            SafeNum(db.font_timer and db.font_timer.x, DEFAULTS.font_timer.x),
            SafeNum(db.font_timer and db.font_timer.y, DEFAULTS.font_timer.y))
        timeText:SetWidth(math.max(54, math.floor(size * 0.5)))
        timeText:SetJustifyH("CENTER")
        timeText:SetShown(not db.font_timer or db.font_timer.enabled ~= false)
    end

    if bgRing then
        bgRing:SetTexture(GetTexturePath(db.style))
        bgRing:SetVertexColor(
            Clamp01(db.bgColorR, DEFAULTS.bgColorR),
            Clamp01(db.bgColorG, DEFAULTS.bgColorG),
            Clamp01(db.bgColorB, DEFAULTS.bgColorB),
            Clamp01(db.bgAlpha,  DEFAULTS.bgAlpha))
    end

    local function ApplyCooldownVisual(cd)
        if not cd then return end
        if cd.SetSwipeTexture then
            cd:SetSwipeTexture(GetTexturePath(db.style))
        end
        if cd.SetSwipeColor then
            local r, g, b = GetConfiguredColor(db)
            cd:SetSwipeColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
        end
        local r, g, b = GetConfiguredColor(db)
        local a = Clamp01(db.alpha, DEFAULTS.alpha)
        local regionCount = cd.GetNumRegions and cd:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, cd:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetVertexColor then
                region:SetVertexColor(r, g, b, a)
            end
        end
    end
    ApplyCooldownVisual(cdForward)
    ApplyCooldownVisual(cdReverse)
    -- CooldownFrameTemplate 的背景属于独立子 Frame，不能只依赖 bgRing 的
    -- DrawLayer 来压住它；每次套色后都重置该模板背景为透明。
    ClearCooldownBackgrounds()
end

ClearCooldownBackgrounds = function()
    local function ClearOne(cd)
        if not cd then return end
        local regionCount = cd:GetNumRegions() or 0
        for i = 1, regionCount do
            local region = select(i, cd:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local layer = region.GetDrawLayer and region:GetDrawLayer() or nil
                -- CooldownFrameTemplate owns several foreground textures in
                -- addition to its optional BACKGROUND.  The old blanket ADD
                -- blend turned the foreground RingWhite texture into a pale
                -- veil.  Keep the configured swipe on the normal alpha path;
                -- only the actual background region is removed below.
                if region.SetBlendMode then region:SetBlendMode("BLEND") end
                if layer == "BACKGROUND" then
                    if region.SetColorTexture then
                        region:SetColorTexture(0, 0, 0, 0)
                    end
                    if region.SetAlpha then
                        region:SetAlpha(0)
                    end
                end
            end
        end
    end
    ClearOne(cdForward)
    ClearOne(cdReverse)
end

local function SetupCooldown(cd, reverse)
    cd:SetAllPoints()
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end
    if cd.SetDrawBling then
        cd:SetDrawBling(false)
    end
    if cd.SetDrawEdge then
        cd:SetDrawEdge(false)
    end
    if cd.SetDrawSwipe then
        cd:SetDrawSwipe(true)
    end
    if cd.SetReverse then
        cd:SetReverse(reverse)
    end
end

function GetActiveCooldown(reverse)
    if reverse then
        return cdReverse, cdForward
    end
    return cdForward, cdReverse
end

Ensure = function()
    if frame then
        return
    end

    local db = DB()
    frame = EnsureAnchorController():Ensure()

    bgRing = ExwindTools.UI:CreateVisualTexture(frame, EXBACKGROUNDFRAME)
    bgRing:SetAllPoints()
    bgRing:Hide()

    textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
    textOverlay:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    SetClickThrough(textOverlay)

    nameText = ExwindTools.UI:CreateVisualFontString(textOverlay, EXFONTFRAME, "GameFontNormal")
    nameText:SetJustifyH("CENTER")
    nameText:SetWordWrap(false)

    timeText = ExwindTools.UI:CreateVisualFontString(textOverlay, EXFONTFRAME, "GameFontHighlightLarge")
    timeText:SetJustifyH("CENTER")
    timeText:SetWordWrap(false)

    cdForward = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    SetupCooldown(cdForward, false)
    cdReverse = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    SetupCooldown(cdReverse, true)

    ApplyVisuals()
    ClearCooldownBackgrounds()

    -- 初始化颜色
    if cdForward and cdForward.SetSwipeColor then
        local r, g, b = GetConfiguredColor(db)
        cdForward:SetSwipeColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
        cdReverse:SetSwipeColor(r, g, b, Clamp01(db.alpha, DEFAULTS.alpha))
    end
end

-- 整体位置只声明一次：运行时 AnchorController 与页面 anchorgroup 必须共用
-- CreateStandardModuleAnchor 返回的同一份合同，不能各自复制 key/default/picker。
local ANCHOR_SCHEMA = {
    moduleKey = MODULE_KEY,
    frameName = "ExBoss_RingProgress",
    title = "圆环进度",
    getDB = DB,
    offsetXKey = "anchorX",
    offsetYKey = "anchorY",
    defaultOffsetX = DEFAULTS.anchorX,
    defaultOffsetY = DEFAULTS.anchorY,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    syncWidgets = { "anchorX", "anchorY", "attachToCustom", "customAttachTarget" },
    widgetRanges = {
        anchorX = { min = -1000, max = 1000, step = 5 },
        anchorY = { min = -600, max = 600, step = 5 },
    },
    initialWidth = DEFAULTS.size,
    initialHeight = DEFAULTS.size,
    clampedToScreen = false,
    frameStrata = "DIALOG",
    fixedFrameStrata = true,
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    onCreateFrame = function(_, owner)
        owner:Hide()
    end,
}
local ANCHOR_OPTS

EnsureAnchorController = function()
    if anchorController then
        return anchorController
    end
    if not EXUI or type(EXUI.CreateStandardModuleAnchor) ~= "function" then
        error("RingProgress requires EXUI:CreateStandardModuleAnchor", 2)
    end
    anchorController, ANCHOR_OPTS = EXUI:CreateStandardModuleAnchor(ANCHOR_SCHEMA)
    return anchorController
end

-- 圆环 runtime 的时间文字与扇形必须共用同一个原生 Duration Object。
-- 不得以 OnUpdate/FormatTime 重写 FontString；该绑定由客户端 C++ 持续刷新。
ClearTimeDurationBinding = function()
    if timeDurationBinding then
        timeDurationBinding:SetEnabled(false)
        timeDurationBinding:SetToDefaults()
    end
end

BindTimeDurationObject = function(durationObject)
    if not timeText then
        return
    end
    if not (C_DurationUtil and C_StringUtil and Enum and Enum.DurationTextBindingProperty) then
        error("RingProgress requires Blizzard DurationTextBinding APIs", 2)
    end
    if not timeDurationBinding then
        timeDurationBinding = C_DurationUtil.CreateDurationTextBinding()
        timeDurationFormatter = C_StringUtil.CreateSecondsFormatter()
        timeDurationFormatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
        timeDurationFormatter:SetDesiredUnitCount(2)
        -- Keep the native Duration binding (including secret durations), but use
        -- Blizzard's one-decimal seconds display for the short ring countdown.
        timeDurationFormatter:SetMillisecondsThreshold(60)
        timeDurationFormatter:SetRounding(Enum.SecondsFormatterRounding.Truncate)
    end
    timeDurationBinding:SetEnabled(false)
    timeDurationBinding:SetFontString(timeText)
    timeDurationBinding:SetTextFormat("{}", {
        {
            property = Enum.DurationTextBindingProperty.RemainingDuration,
            formatter = timeDurationFormatter,
        },
    })
    timeDurationBinding:SetUpdateInterval(0)
    timeDurationBinding:SetDuration(durationObject)
    timeDurationBinding:SetEnabled(true)
    timeDurationBinding:UpdateFontString()
end

CreateDurationFromEnd = function(endAt, duration)
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then
        error("RingProgress requires C_DurationUtil.CreateDuration", 2)
    end
    local durationObject = C_DurationUtil.CreateDuration()
    durationObject:SetTimeFromEnd(endAt, duration, 1)
    return durationObject
end

function Ring:GetAnchorGroupOptions()
    EnsureAnchorController()
    return ANCHOR_OPTS
end

function Ring:ShowEntry(entry, forcedRemaining)
    Ensure()
    local db = DB()
    if type(entry) ~= "table" then
        frame:Hide()
        return
    end
    local duration = math.max(0.1, SafeNum(entry.duration, 5))
    local remaining = SafeNum(forcedRemaining, nil)
    local mode = ResolveFillMode(entry, db)
    if remaining == nil then
        remaining = math.max(0, SafeNum(entry.endTime, GetTime() + duration) - GetTime())
    end
    if remaining <= 0 then
        frame:Hide()
        return
    end
    StopAnimation()
    StartAnimation({
        {
            duration = duration,
            initialRemaining = remaining,
            -- 这是上游事件给出的稳定 expiration/end time；普通 Duration 的原生
            -- SetTimeFromEnd 必须消费它，不能把本次刷新当作新的起点。
            endTime = forcedRemaining == nil and tonumber(entry.endTime) or nil,
            -- 若未来受保护来源直接提供 Secret Duration，只能原样下传。
            durationObject = entry.durationObject,
            castKind = entry.castKind or "cast",
            mode = mode,
            displayName = entry.displayName,
            progressDisplayName = entry.progressDisplayName,
            preferSpellName = entry.preferSpellName == true,
            spellID = entry.spellID,
            ringRenameEnabled = entry.ringRenameEnabled == true,
            ringRenameText = entry.ringRenameText,
        },
    }, {
        castCheckEnabled = entry.castCheckEnabled == true,
        owner = type(entry.owner) == "table" and entry.owner or nil,
    })
end

-- 设置页测试仍走正式 ShowEntry/原生 Duration 链路；只固定 castKind，以便分别
-- 验证用户选择的施法与引导填充方向。
function Ring:ShowTestCast()
    local duration = 5
    self:ShowEntry({
        duration = duration,
        endTime = GetTime() + duration,
        castKind = "cast",
        displayName = IsNonChineseLocale() and "Test Cast" or "测试施法",
    })
end

function Ring:ShowTestChannel()
    local duration = 5
    self:ShowEntry({
        duration = duration,
        endTime = GetTime() + duration,
        castKind = "channel",
        displayName = IsNonChineseLocale() and "Test Channel" or "测试引导",
    })
end

function Ring:ShowSequence(sequence, opts)
    Ensure()
    if type(sequence) ~= "table" or #sequence == 0 then
        return
    end
    opts = type(opts) == "table" and opts or {}
    if opts.castCheckEnabled ~= true then
        for i = 1, #sequence do
            if type(sequence[i]) == "table" and sequence[i].castCheckEnabled == true then
                opts.castCheckEnabled = true
                break
            end
        end
    end
    StopAnimation()
    StartAnimation(sequence, opts)
end

function Ring:Hide()
    if frame then
        StopAnimation()
        if cdForward then cdForward:Hide() end
        if cdReverse then cdReverse:Hide() end
        if bgRing then bgRing:Hide() end
        frame:Hide()
    end
end

function Ring:StopByOwner(owner)
    if type(owner) ~= "table" then
        return 0
    end
    if type(activeAnim) ~= "table" or activeAnim.earlyStopEnabled ~= true or not DoesOwnerMatch(activeAnim, owner) then
        return 0
    end
    StopAnimation()
    self:Hide()
    return 1
end

function Ring:StopByUnitCastBar(unit, castBarID, castKind)
    return self:StopByOwner({
        source = "boss",
        unit = NormalizeUnitToken(unit),
        castBarID = NormalizeCastBarID(castBarID),
        castKind = tostring(castKind or ""),
    })
end

function Ring:IsPlaying()
    return activeAnim ~= nil
end

function Ring:RefreshVisuals()
    Ensure()
    ApplyVisuals()
    ClearCooldownBackgrounds()
    ExwindTools.UI:RefreshEditableModule("EXBoss", "ringprogress")
    -- Standard Slider commit 与标准 panel interaction 都只调用 binding 的这条
    -- 完整 refresh 出口，且不会再广播已废弃状态总线。已有 material session
    -- 必须在这里用 Surface 正式重套；Render 不会反向调用 RefreshVisuals，故无递归。
    if panelPreview then self:RefreshPanelPreview() end
end

function Ring:StartFramePicker()
    return EnsureAnchorController():StartFramePicker()
end

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. "_init", function()
    C_Timer.After(0.5, function()
        Ensure()
        Ring:RefreshVisuals()
    end)
end)

-- =============================================================
-- 唯一标准预览声明
-- =============================================================
-- 圆环的静态编辑预览就是一个声明式材质（加上原有可选背景与文字），而不是
-- 把运行时 Cooldown 动画或任意 renderer 注入标准层。
local function SnapshotPreviewData(value, path)
    local ui = ExwindTools and ExwindTools.UI
    if not ui or type(ui.SnapshotPreviewData) ~= "function" then
        error("RingProgress standard preview snapshot API is unavailable", 2)
    end
    return ui:SnapshotPreviewData(value, path)
end

local function PreviewFontStyle(source, fallback)
    source = type(source) == "table" and source or fallback
    local style = {}
    for key, value in pairs(source) do style[key] = value end
    style.justifyH = "CENTER"
    style.justifyV = "MIDDLE"
    return style
end

function Ring:BuildPreview()
    local db = DB()
    -- 圆环预览只是一帧原生静态 Cooldown 样本：remaining 6.6 / duration 10
    -- 会实际绘制 66% 的前景弧，完整背景环因此可见；绝不进入 runtime 动画。
    local previewDuration, previewRemaining = 10, 6.6
    local size = math.max(20, math.min(360, SafeNum(db.size, DEFAULTS.size)))
    local nameStyle = PreviewFontStyle(db.font_spell, DEFAULTS.font_spell)
    local timeStyle = PreviewFontStyle(db.font_timer, DEFAULTS.font_timer)
    local backgroundColor = {
        r = Clamp01(db.bgColorR, DEFAULTS.bgColorR),
        g = Clamp01(db.bgColorG, DEFAULTS.bgColorG),
        b = Clamp01(db.bgColorB, DEFAULTS.bgColorB),
        a = Clamp01(db.bgAlpha, DEFAULTS.bgAlpha),
    }
    local label = IsNonChineseLocale() and "Test Cast" or "测试施法"
    return {
        definition = SnapshotPreviewData({
            kind = "icon",
            appearance = {
                icon = {
                    showIcon = false,
                    showBorder = false,
                    width = size,
                    height = size,
                    -- 仅标准静态样本允许这个纹理入口；MaterializeItem 会传给
                    -- IconWidget:SetStaticCooldown，不能泄漏到 Ring runtime。
                    cooldown = {
                        showSwipe = true,
                        showEdge = false,
                        showBling = false,
                        swipeAlpha = Clamp01(db.alpha, DEFAULTS.alpha),
                        swipeTexture = GetTexturePath(db.style),
                        swipeColor = {
                            r = Clamp01(db.ringColorR, DEFAULTS.ringColorR),
                            g = Clamp01(db.ringColorG, DEFAULTS.ringColorG),
                            b = Clamp01(db.ringColorB, DEFAULTS.ringColorB),
                            a = Clamp01(db.alpha, DEFAULTS.alpha),
                        },
                    },
                },
            },
            layout = { direction = "DOWN", spacing = 0, maxVisible = 1, itemWidth = size, itemHeight = size },
            slots = { ["core.time"] = { shown = false }, ["core.stacks"] = { shown = false } },
            children = {
                {
                    id = "background",
                    kind = "texture",
                    -- This is the inactive ring behind the native Cooldown
                    -- swipe.  Without this explicit declaration the generic
                    -- preview child contract places it in the foreground.
                    layer = "background",
                    tooltip = "背景圆环",
                    movable = false,
                    focusable = false,
                    anchor = { point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER" },
                    width = size,
                    height = size,
                },
                {
                    id = "name",
                    kind = "text",
                    tooltip = "法术名称",
                    movable = true,
                    focusable = true,
                    guiTarget = "font_spell",
                    anchor = { point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER", x = SafeNum(nameStyle.x, 0), y = SafeNum(nameStyle.y, 0) },
                    width = math.max(80, size - 20),
                    height = size,
                    style = nameStyle,
                },
                {
                    id = "time",
                    kind = "text",
                    tooltip = "时间文本",
                    movable = true,
                    focusable = true,
                    guiTarget = "font_timer",
                    anchor = { point = "CENTER", relativeElement = "core.icon", relativePoint = "CENTER", x = SafeNum(timeStyle.x, 0), y = SafeNum(timeStyle.y, 0) },
                    width = math.max(54, math.floor(size * 0.5)),
                    height = size,
                    style = timeStyle,
                },
            },
        }, "RingProgress.previewDefinition"),
        model = SnapshotPreviewData({
            items = {
                {
                    itemID = "ringprogress-preview:1",
                    type = "custom",
                    name = label,
                    icon = 134400,
                    order = 1,
                    duration = previewDuration,
                    remaining = previewRemaining,
                    elements = {
                        -- Preview follows runtime: a disabled background must
                        -- not leave a translucent grey ring over the sample.
                        background = { shown = db.bgEnabled == true, texture = GetTexturePath(db.style), width = size, height = size, color = backgroundColor },
                        name = { shown = not db.font_spell or db.font_spell.enabled ~= false, text = label },
                        time = { shown = not db.font_timer or db.font_timer.enabled ~= false, text = "3.0" },
                    },
                },
            },
        }, "RingProgress.previewModel"),
    }
end

-- 只声明 BuildPreview 中已有的可移动语义槽。Panel 侧的右键、DB 写回、刷新与
-- Grid 回读全部由 BindStandardPreviewInteractions 收口；不得再写私有 onIntent。
local INTERACTION_SCHEMA = {
    name = {
        guiKey = "font_spell",
        movable = true,
        tooltip = "法术名称",
        position = { x = "font_spell.x", y = "font_spell.y" },
    },
    time = {
        guiKey = "font_timer",
        movable = true,
        tooltip = "时间文本",
        position = { x = "font_timer.x", y = "font_timer.y" },
    },
}

-- Slider 路径只用于同一份 ModuleDB 的配置白名单；拖动期是否可直接修改
-- 已物化 Panel 由 Core 的 旧字段补丁 决定，不再保留字段级分类。
local EXTRA_CONFIG_PATHS = { "size", "alpha", "bgAlpha" }
for _, key in ipairs({ "font_spell", "font_timer" }) do
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".size"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".x"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".y"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".shadowX"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".shadowY"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".fixedWidth"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".maxWidth"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".gradientStart"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".gradientLength"
    EXTRA_CONFIG_PATHS[#EXTRA_CONFIG_PATHS + 1] = key .. ".rotation"
end

Ring.StandardSliderContract = {
    groupPaths = {
        font_spell = "font_spell",
        font_timer = "font_timer",
    },
}

-- ConfigBinding 的唯一白名单：Slider、标准 Interaction、AnchorGroup 及 FontGroup
-- 自动/固定宽度附带写入均基于同一 ModuleDB，不兼容、桥接或缓存旧表。
local STANDARD_SCHEMA_PATHS = {
    enabled = true,
    style = true,
    castFillMode = true,
    channelFillMode = true,
    ringColorR = true, ringColorG = true, ringColorB = true, ringColorA = true,
    bgEnabled = true,
    bgColorR = true, bgColorG = true, bgColorB = true, bgColorA = true,
    anchorX = true, anchorY = true,
    attachToCustom = true, customAttachTarget = true,
}
for _, path in ipairs(EXTRA_CONFIG_PATHS) do STANDARD_SCHEMA_PATHS[path] = true end
for _, key in ipairs({ "font_spell", "font_timer" }) do
    STANDARD_SCHEMA_PATHS[key .. ".enabled"] = true
    STANDARD_SCHEMA_PATHS[key .. ".font"] = true
    STANDARD_SCHEMA_PATHS[key .. ".r"] = true
    STANDARD_SCHEMA_PATHS[key .. ".g"] = true
    STANDARD_SCHEMA_PATHS[key .. ".b"] = true
    STANDARD_SCHEMA_PATHS[key .. ".a"] = true
    STANDARD_SCHEMA_PATHS[key .. ".outline"] = true
    STANDARD_SCHEMA_PATHS[key .. ".shadow"] = true
    STANDARD_SCHEMA_PATHS[key .. ".shadowColorR"] = true
    STANDARD_SCHEMA_PATHS[key .. ".shadowColorG"] = true
    STANDARD_SCHEMA_PATHS[key .. ".shadowColorB"] = true
    STANDARD_SCHEMA_PATHS[key .. ".shadowColorA"] = true
    STANDARD_SCHEMA_PATHS[key .. ".autoWidth"] = true
    STANDARD_SCHEMA_PATHS[key .. ".justifyH"] = true
    STANDARD_SCHEMA_PATHS[key .. ".justifyV"] = true
    STANDARD_SCHEMA_PATHS[key .. ".gradientEnabled"] = true
end

if not EXUI or type(EXUI.RegisterStandardConfigBinding) ~= "function" then
    error("RingProgress requires EXUI standard display contract", 2)
end
for _, path in ipairs({ "anchorX", "anchorY", "attachToCustom", "customAttachTarget" }) do STANDARD_SCHEMA_PATHS[path] = true end
local STANDARD_CONFIG_BINDING = EXUI:RegisterStandardConfigBinding({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    reapplyExisting = function()
        local function reapply(surface)
            if surface and type(surface.ReapplyPanelPresentation) == "function" then
                surface:ReapplyPanelPresentation()
            elseif surface and type(surface.ReapplyCurrentItems) == "function" then
                surface:ReapplyCurrentItems()
            end
        end
        reapply(panelSurface)
        reapply(panelPreview)
        -- Slider 只重套已经存在的 Runtime / World / Panel；不能走 RefreshVisuals，
        -- 后者会请求编辑模式完整刷新并重建 World 预览。
        ApplyVisuals()
        ClearCooldownBackgrounds()
        EXUI:ReapplyActiveEditablePreviewMaterial("EXBoss", "ringprogress")
    end,
    schemaPaths = STANDARD_SCHEMA_PATHS,
})

local function RefreshActiveSurfaces()
    return STANDARD_CONFIG_BINDING.reapplyExisting()
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- EditMode 仍使用既有 BuildPreview/ApplyLayoutIntent 协议，但 world 的 element
-- move、同 DB 写回和完整刷新已经由 EXUI 标准合同唯一拥有。
local WORLD_LAYOUT_INTENT = EXUI:BuildStandardWorldLayoutIntent({
    moduleKey = MODULE_KEY,
    getConfig = DB,
    elements = INTERACTION_SCHEMA,
})

local function BuildRingPanelPresentation(_, mode)
    if mode ~= "panel" then error("RingProgress panel surface only accepts panel mode", 2) end
    return Ring:BuildPreview()
end

panelSurface = EXUI:CreateStandardPreviewSurface({
    moduleKey = MODULE_KEY,
    kind = "material",
    buildPresentation = BuildRingPanelPresentation,
    interactionSchema = INTERACTION_SCHEMA,
    requiredPositionGuiKeys = { "font_spell", "font_timer" },
})

local function RenderPanelPreview()
    if not panelSurface or not panelDock then return nil end
    panelPreview = panelSurface:Render({
        dock = panelDock,
        ruleKey = MODULE_KEY,
        state = true,
    })
    return panelPreview
end

function Ring:ShowPanelPreview(dock)
    if not dock then return end
    panelDock = dock
    local preview = RenderPanelPreview()
    if not preview then return end
    local _, height = preview:GetBounds()
    dock:SetHeight(math.max(180, (height or 0) + 28))
end

function Ring:RefreshPanelPreview()
    if not panelPreview then return end
    local preview = RenderPanelPreview()
    local _, height = preview:GetBounds()
    if panelDock then panelDock:SetHeight(math.max(180, (height or 0) + 28)) end
end

function Ring:ReleasePanelPreview()
    if panelSurface then panelSurface:Release() end
    panelPreview = nil
    panelDock = nil
end

ExwindTools.UI:RegisterEditableModule({
    addon = "EXBoss",
    key = "ringprogress",
    name = L["中央圆环"],
    settingsPage = "ringprogress",
    orientation = "HORIZONTAL",
    editOverlay = { titleFontSize = 30 },
    getAnchor = function()
        Ensure()
        return frame
    end,
    BuildPreview = function()
        return Ring:BuildPreview()
    end,
    ApplyLayoutIntent = WORLD_LAYOUT_INTENT,
})
