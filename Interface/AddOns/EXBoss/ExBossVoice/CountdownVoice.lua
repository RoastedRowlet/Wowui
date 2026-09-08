---@diagnostic disable: undefined-global, undefined-field, need-check-nil

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.Countdown = ExBoss.Voice.Countdown or {}
local Runtime = ExBoss.Voice.Countdown
local MAX_COUNTDOWN_DIGIT = 5

local DEFAULTS = {
    nameLeadSeconds = 1,
    pullCountdownEnabled = true,
    pullCountdownVoiceEnabled = false,
    digits = {
        [1] = { enabled = true, sourceType = "pack", customLSM = "" },
        [2] = { enabled = true, sourceType = "pack", customLSM = "" },
        [3] = { enabled = true, sourceType = "pack", customLSM = "" },
        [4] = { enabled = true, sourceType = "pack", customLSM = "" },
        [5] = { enabled = true, sourceType = "pack", customLSM = "" },
    },
}

local _frame
local _active = {}

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[k] = DeepCopy(x)
    end
    return out
end

local function ApplyDefaults(dst, defaults)
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

local function NormalizeDigitSource(value)
    local source = tostring(value or "pack"):lower()
    if source ~= "lsm" then
        source = "pack"
    end
    return source
end

local function EnsureDB()
    EXBOSS12S2 = EXBOSS12S2 or {}
    EXBOSS12S2.voice = EXBOSS12S2.voice or {}
    EXBOSS12S2.voice.countdown = EXBOSS12S2.voice.countdown or {}
    local db = EXBOSS12S2.voice.countdown
    ApplyDefaults(db, DEFAULTS)
    db.nameLeadSeconds = math.max(0, math.min(10, tonumber(db.nameLeadSeconds) or DEFAULTS.nameLeadSeconds))
    db.digits = type(db.digits) == "table" and db.digits or {}
    for i = 1, MAX_COUNTDOWN_DIGIT do
        db.digits[i] = type(db.digits[i]) == "table" and db.digits[i] or {}
        if db.digits[i].enabled == nil then
            db.digits[i].enabled = true
        else
            db.digits[i].enabled = (db.digits[i].enabled == true)
        end
        db.digits[i].sourceType = NormalizeDigitSource(db.digits[i].sourceType)
        db.digits[i].customLSM = tostring(db.digits[i].customLSM or "")
    end
    return db
end

local function EnsureFrame()
    if _frame then
        return _frame
    end
    _frame = CreateFrame("Frame", "ExBoss_CountdownVoiceRuntimeFrame", UIParent)
    _frame:Hide()
    _frame:SetScript("OnUpdate", function()
        Runtime:OnUpdate()
    end)
    return _frame
end

local function HasActiveRows()
    return next(_active) ~= nil
end

function Runtime:GetDefaults()
    return DeepCopy(DEFAULTS)
end

function Runtime:GetDB()
    return EnsureDB()
end

function Runtime:GetNameLeadSeconds()
    local db = EnsureDB()
    return math.max(0, tonumber(db.nameLeadSeconds) or DEFAULTS.nameLeadSeconds)
end

function Runtime:IsPullCountdownEnabled()
    local db = EnsureDB()
    return db.pullCountdownEnabled ~= false
end

function Runtime:IsPullCountdownVoiceEnabled()
    local db = EnsureDB()
    return db.pullCountdownVoiceEnabled == true
end

function Runtime:TryPlayDigit(second, scope, key, opts)
    local digit = tonumber(second)
    if not digit or digit < 1 or digit > MAX_COUNTDOWN_DIGIT then
        return false, "invalid digit"
    end

    local engine = ExBoss.Voice and ExBoss.Voice.Engine
    if not (engine and type(engine.TryPlayStandaloneSound) == "function") then
        return false, "no engine"
    end

    local db = EnsureDB()
    if opts == nil then
        opts = {}
    end
    local digitCfg = db.digits and db.digits[digit] or nil
    if opts.ignoreState ~= true then
        if digitCfg and digitCfg.enabled == false then
            return false, "digit disabled"
        end
    end

    local triggerCfg
    if digitCfg and NormalizeDigitSource(digitCfg.sourceType) == "lsm" and tostring(digitCfg.customLSM or "") ~= "" then
        triggerCfg = {
            sourceType = "lsm",
            customLSM = tostring(digitCfg.customLSM or ""),
        }
    else
        triggerCfg = {
            sourceType = "pack",
            label = "countdown-" .. tostring(digit),
        }
    end

    return engine:TryPlayStandaloneSound(
        triggerCfg,
        tostring(opts.throttleKey or ("countdown:" .. tostring(key or "runtime") .. ":" .. tostring(digit))),
        {
            triggerIndex = digit,
            ignoreState = opts.ignoreState == true,
            throttle = opts.throttle,
        }
    )
end

function Runtime:PreviewDigit(second)
    local digit = tonumber(second)
    if not digit then
        return false, "invalid digit"
    end
    return self:TryPlayDigit(digit, "global", "preview", {
        ignoreState = true,
        throttle = false,
        throttleKey = "countdown:preview:" .. tostring(digit),
    })
end

function Runtime:Start(spec)
    if type(spec) ~= "table" then
        return
    end
    local key = tostring(spec.key or "")
    if key == "" then
        return
    end

    local endAt = tonumber(spec.endAt)
    if not endAt then
        return
    end

    local startFrom = math.floor(math.max(1, math.min(MAX_COUNTDOWN_DIGIT, tonumber(spec.startFrom) or MAX_COUNTDOWN_DIGIT)))
    local minDigit = math.floor(math.max(1, math.min(startFrom, tonumber(spec.minDigit) or 1)))
    local scope = tostring(spec.scope or "global")
    if scope ~= "boss" and scope ~= "trash" then
        scope = "global"
    end

    _active[key] = {
        key = key,
        scope = scope,
        endAt = endAt,
        startFrom = startFrom,
        minDigit = minDigit,
        lastPlayed = nil,
    }

    local frame = EnsureFrame()
    if frame and not frame:IsShown() then
        frame:Show()
    end
end

function Runtime:GetMaxCountdownDigit()
    return MAX_COUNTDOWN_DIGIT
end

function Runtime:Cancel(key)
    local id = tostring(key or "")
    if id == "" then
        return
    end
    _active[id] = nil
    if _frame and not HasActiveRows() then
        _frame:Hide()
    end
end

function Runtime:CancelScope(scope)
    local target = tostring(scope or "")
    if target == "" then
        return
    end
    for key, row in pairs(_active) do
        if type(row) == "table" and tostring(row.scope or "") == target then
            _active[key] = nil
        end
    end
    if _frame and not HasActiveRows() then
        _frame:Hide()
    end
end

function Runtime:CancelAll()
    for key in pairs(_active) do
        _active[key] = nil
    end
    if _frame then
        _frame:Hide()
    end
end

function Runtime:OnUpdate()
    if not HasActiveRows() then
        if _frame then
            _frame:Hide()
        end
        return
    end

    local now = GetTime()
    for key, row in pairs(_active) do
        local remaining = math.ceil((tonumber(row.endAt) or 0) - now)
        if remaining < (tonumber(row.minDigit) or 1) then
            _active[key] = nil
        elseif remaining <= (tonumber(row.startFrom) or 5) and remaining ~= row.lastPlayed then
            row.lastPlayed = remaining
            self:TryPlayDigit(remaining, row.scope, key)
        end
    end

    if _frame and not HasActiveRows() then
        _frame:Hide()
    end
end

if not Runtime._eventsRegistered then
    ExwindTools:RegisterEvent("ENCOUNTER_END", "ExBoss.CountdownVoice.EncounterEnd", function()
        Runtime:CancelScope("boss")
    end)
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExBoss.CountdownVoice.PEW", function()
        Runtime:CancelAll()
    end)
    Runtime._eventsRegistered = true
end
