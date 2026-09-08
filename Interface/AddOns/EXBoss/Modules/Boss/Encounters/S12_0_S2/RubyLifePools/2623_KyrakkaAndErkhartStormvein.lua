---@diagnostic disable: undefined-global

do
    local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })
    local ENCOUNTER_ID = 2623
    local EVENT_WIND = 887
    local EVENT_FIRE_A = 894
    local EVENT_FIRE_B = 889
    local FIRE_LOCK_LEAD_SECS = 10
    local FIRE_COUNTDOWN_LEAD_SECS = 5
    local FIRE_COUNTDOWN_KEY = "exboss:2623:fire-countdown"

    local PANEL_SIZE = 160
    local PANEL_TEXTURE_PATH = "Interface\\AddOns\\EXBoss\\Core\\Media\\Textures\\RubyPanel.png"
    local FIRE_ATLAS = "dreamsurge_fire-portal-icon"
    local DIRECTION_TEXT = { [1] = L["上"], [2] = L["左"], [3] = L["下"], [4] = L["右"] }
    local WIND_ANCHOR = {
        [1] = { atlas = "NPE_ArrowUp", point = "BOTTOM", offsetX = 0, offsetY = 128 },
        [2] = { atlas = "NPE_ArrowLeft", point = "RIGHT", offsetX = -128, offsetY = 0 },
        [3] = { atlas = "NPE_ArrowDown", point = "TOP", offsetX = 0, offsetY = -128 },
        [4] = { atlas = "NPE_ArrowRight", point = "LEFT", offsetX = 128, offsetY = 0 },
    }
    local FIRE_OFFSET = {
        [1] = { x = 0, y = 36 }, [2] = { x = -36, y = 0 },
        [3] = { x = 0, y = -36 }, [4] = { x = 36, y = 0 },
    }
    local FIRE_COUNTDOWN_TEXT = {
        [1] = L["上方放火"], [2] = L["左侧放火"],
        [3] = L["下方放火"], [4] = L["右侧放火"],
    }

    local State = { windIndex = nil, fireIndex = nil, windCastTime = nil, fireCastTime = nil }
    local fireRequestToken = 0
    local fireCountdownToken = 0
    local pendingFireCastTime = nil
    local pendingFireResolved = false
    local panel, panelArea, windArrowTexture, windAnimGroup, windTranslate, fireIconTexture, fireAlphaGroup, fireScaleGroup

    local function IsKyrakkaActive()
        local state = ExwindTools and ExwindTools.State or nil
        if type(state) == "table" and state.IsBossEncounter == true and tonumber(state.EncounterID) == ENCOUNTER_ID then
            return true
        end
        local scheduler = ExBoss and ExBoss.Timeline and ExBoss.Timeline.Scheduler
        return type(scheduler) == "table" and scheduler._running == true and tonumber(scheduler._encounterID) == ENCOUNTER_ID
    end

    local function ResolveDirectionIndex(occurrenceCount)
        local n = math.max(1, math.floor(tonumber(occurrenceCount) or 1))
        return ((n - 1) % 4) + 1
    end

    local function NextDirectionIndex(index)
        return (tonumber(index) % 4) + 1
    end

    local function RefreshTexts()
        if not panel then return end
        panel.WindText:SetText(State.windIndex and string.format(L["下一次风: %s"], DIRECTION_TEXT[State.windIndex]) or L["下一次风: --"])
        panel.FireText:SetText(State.fireIndex and string.format(L["下一次火: %s"], DIRECTION_TEXT[State.fireIndex]) or L["下一次火: --"])
    end

    local function RefreshWindVisual()
        if not (windArrowTexture and State.windIndex) then return end
        local cfg = WIND_ANCHOR[State.windIndex]
        windAnimGroup:Stop()
        windArrowTexture:SetAtlas(cfg.atlas, false)
        windArrowTexture:ClearAllPoints()
        windArrowTexture:SetPoint(cfg.point, panelArea, cfg.point, 0, 0)
        windTranslate:SetOffset(cfg.offsetX, cfg.offsetY)
        windArrowTexture:Show()
        windAnimGroup:Play()
    end

    local function RefreshFireVisual()
        if not (fireIconTexture and State.fireIndex) then return end
        local cfg = FIRE_OFFSET[State.fireIndex]
        fireIconTexture:ClearAllPoints()
        fireIconTexture:SetPoint("CENTER", panelArea, "CENTER", cfg.x, cfg.y)
        fireIconTexture:Show()
        fireAlphaGroup:Stop(); fireAlphaGroup:Play()
        fireScaleGroup:Stop(); fireScaleGroup:Play()
    end

    local function ResetState()
        State.windIndex, State.fireIndex, State.windCastTime, State.fireCastTime = nil, nil, nil, nil
        pendingFireCastTime, pendingFireResolved = nil, false
        fireRequestToken = fireRequestToken + 1
        fireCountdownToken = fireCountdownToken + 1
        local alert = ExBoss and ExBoss.Alert
        if alert and type(alert.StopFlashCountdown) == "function" then
            alert:StopFlashCountdown(FIRE_COUNTDOWN_KEY)
        end
        if windAnimGroup then windAnimGroup:Stop() end
        if fireAlphaGroup then fireAlphaGroup:Stop() end
        if fireScaleGroup then fireScaleGroup:Stop() end
        if windArrowTexture then windArrowTexture:Hide() end
        if fireIconTexture then fireIconTexture:Hide() end
        RefreshTexts()
    end

    local function GetSavedPosition()
        local db = _G.EXBOSS12S2
        local position = type(db) == "table" and db.kyrakkaWindFirePosition or nil
        if type(position) ~= "table" then return nil end
        local point = tostring(position.point or "")
        local relativePoint = tostring(position.relativePoint or "")
        local x, y = tonumber(position.x), tonumber(position.y)
        if point == "" or relativePoint == "" or not x or not y then return nil end
        return point, relativePoint, x, y
    end

    local function ApplySavedPosition()
        local point, relativePoint, x, y = GetSavedPosition()
        panel:ClearAllPoints()
        if point then
            panel:SetPoint(point, UIParent, relativePoint, x, y)
        else
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        end
    end

    local function SaveCurrentPosition()
        local point, _, relativePoint, x, y = panel:GetPoint(1)
        if not point or not relativePoint or not x or not y then return end
        _G.EXBOSS12S2 = _G.EXBOSS12S2 or {}
        _G.EXBOSS12S2.kyrakkaWindFirePosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end

    local function EnsurePanel()
        if panel then return end
        panel = CreateFrame("Frame", "EXBossKyrakkaWindFirePanel", UIParent, "BackdropTemplate")
        panel:SetSize(PANEL_SIZE + 40, PANEL_SIZE + 70)
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
        panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveCurrentPosition() end)
        panel:SetClampedToScreen(true)
        ApplySavedPosition()
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        panel:SetBackdropColor(0, 0, 0, 0.55)
        panel:SetBackdropBorderColor(1, 1, 1, 0.6)
        panel:SetAlpha(0.9)
        panel:Hide()

        panel.WindText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.WindText:SetPoint("TOP", panel, "TOP", 0, -14)
        panel.FireText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.FireText:SetPoint("TOP", panel.WindText, "BOTTOM", 0, -4)

        local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", 2, 2)
        closeButton:SetScript("OnClick", function() panel:Hide() end)

        panelArea = CreateFrame("Frame", nil, panel)
        panelArea:SetSize(PANEL_SIZE, PANEL_SIZE)
        panelArea:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
        local panelTexture = panelArea:CreateTexture(nil, "BACKGROUND")
        panelTexture:SetSize(PANEL_SIZE * 1.35, PANEL_SIZE * 1.35)
        panelTexture:SetPoint("CENTER", panelArea, "CENTER")
        panelTexture:SetTexture(PANEL_TEXTURE_PATH)

        windArrowTexture = panelArea:CreateTexture(nil, "OVERLAY")
        windArrowTexture:SetSize(32, 32)
        windArrowTexture:Hide()
        windAnimGroup = windArrowTexture:CreateAnimationGroup()
        windAnimGroup:SetLooping("REPEAT")
        windTranslate = windAnimGroup:CreateAnimation("Translation")
        windTranslate:SetDuration(1)
        windTranslate:SetSmoothing("OUT")
        windTranslate:SetEndDelay(0.6)

        fireIconTexture = panelArea:CreateTexture(nil, "OVERLAY")
        fireIconTexture:SetAtlas(FIRE_ATLAS, false)
        fireIconTexture:SetSize(38, 38)
        fireIconTexture:Hide()
        fireAlphaGroup = fireIconTexture:CreateAnimationGroup()
        fireAlphaGroup:SetLooping("BOUNCE")
        local fireAlpha = fireAlphaGroup:CreateAnimation("Alpha")
        fireAlpha:SetFromAlpha(0.5); fireAlpha:SetToAlpha(1); fireAlpha:SetDuration(0.6); fireAlpha:SetSmoothing("IN_OUT")
        fireScaleGroup = fireIconTexture:CreateAnimationGroup()
        fireScaleGroup:SetLooping("BOUNCE")
        local fireScale = fireScaleGroup:CreateAnimation("Scale")
        fireScale:SetOrigin("CENTER", 0, 0)
        fireScale:SetScaleFrom(1, 1); fireScale:SetScaleTo(1.15, 1.15); fireScale:SetDuration(0.6); fireScale:SetSmoothing("OUT")
        fireScale:SetEndDelay(0.05)
        RefreshTexts()
    end

    local function ShowPanel()
        ResetState()
        panel:Show()
    end

    local function HidePanel()
        if panel then panel:Hide() end
        ResetState()
    end

    local function HandleWindScheduled(payload)
        local index = ResolveDirectionIndex(payload.occurrenceCount)
        State.windIndex, State.windCastTime = index, tonumber(payload.castTime)
        if pendingFireCastTime and not pendingFireResolved and State.windCastTime and State.windCastTime > pendingFireCastTime then
            State.fireIndex, pendingFireResolved = index, true
            RefreshFireVisual()
        end
        RefreshWindVisual()
        RefreshTexts()
    end

    local function ShowFireCountdown(castTime, token)
        if fireCountdownToken ~= token or not IsKyrakkaActive() or not State.fireIndex then return end
        local remaining = math.max(0, (tonumber(castTime) or 0) - GetTime())
        if remaining <= 0 then return end
        local alert = ExBoss and ExBoss.Alert
        local text = FIRE_COUNTDOWN_TEXT[State.fireIndex]
        if alert and type(alert.FlashCountdown) == "function" and text then
            alert:FlashCountdown(text, remaining, {
                key = FIRE_COUNTDOWN_KEY,
                endAt = castTime,
                noAnimation = true,
            })
        end
    end

    local function ApplyFireLock(castTime, token)
        if fireRequestToken ~= token or not IsKyrakkaActive() then return end
        pendingFireCastTime, State.fireCastTime = castTime, castTime
        if State.windCastTime and State.windCastTime > castTime then
            State.fireIndex, pendingFireResolved = State.windIndex, true
        elseif State.windIndex then
            State.fireIndex, pendingFireResolved = NextDirectionIndex(State.windIndex), false
        else
            State.fireIndex, pendingFireResolved = nil, false
        end
        RefreshFireVisual()
        RefreshTexts()
    end

    local function HandleFireScheduled(payload)
        fireRequestToken = fireRequestToken + 1
        local token = fireRequestToken
        local castTime = tonumber(payload.castTime)
        local remaining = tonumber(payload.remaining) or 0
        local delay = math.max(0, remaining - FIRE_LOCK_LEAD_SECS)
        if delay <= 0.05 or not (C_Timer and type(C_Timer.After) == "function") then
            ApplyFireLock(castTime, token)
        else
            C_Timer.After(delay, function() ApplyFireLock(castTime, token) end)
        end

        fireCountdownToken = fireCountdownToken + 1
        local countdownToken = fireCountdownToken
        local countdownDelay = math.max(0, remaining - FIRE_COUNTDOWN_LEAD_SECS)
        if countdownDelay <= 0.05 or not (C_Timer and type(C_Timer.After) == "function") then
            ShowFireCountdown(castTime, countdownToken)
        else
            C_Timer.After(countdownDelay, function() ShowFireCountdown(castTime, countdownToken) end)
        end
    end

    EnsurePanel()

    if ExwindTools and type(ExwindTools.RegisterEvent) == "function" then
        ExwindTools:RegisterEvent("EXBOSS_FIXED_AI_EVENT_SCHEDULED", "ExBoss_Kyrakka_WindFire_Scheduled", function(_, payload)
            if type(payload) ~= "table" or tonumber(payload.encounterID) ~= ENCOUNTER_ID or not IsKyrakkaActive() then return end
            local eventID = tonumber(payload.eventID)
            if eventID == EVENT_WIND then HandleWindScheduled(payload)
            elseif eventID == EVENT_FIRE_A or eventID == EVENT_FIRE_B then HandleFireScheduled(payload) end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_START", "ExBoss_Kyrakka_WindFire_Start", function(_, encounterID)
            if tonumber(encounterID) == ENCOUNTER_ID then ShowPanel() end
        end)
        ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss_Kyrakka_WindFire_End", function(_, encounterID)
            if encounterID == nil or tonumber(encounterID) == ENCOUNTER_ID then HidePanel() end
        end)
    end
end

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2623,
    dungeon = { key = "ruby_life_pools", name = "Ruby Life Pools", zhCN = "红玉新生法池" },
    boss = { key = "kyrakka_and_erkhart_stormvein", name = "Kyrakka and Erkhart Stormvein", zhCN = "基拉卡与厄克哈特·风脉" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
