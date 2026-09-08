---@diagnostic disable: undefined-global

ExBoss.Modules = ExBoss.Modules or {}
ExBoss.Modules.Boss = ExBoss.Modules.Boss or {}

local TimelineModeRules = {}
ExBoss.Modules.Boss.TimelineModeRules = TimelineModeRules

TimelineModeRules.rules = {
    fixed = {
        capabilities = {
            perEventEnabled = true,
            eventColor = true,
            centralText = true,
            preAlertText = true,
            timerBarRename = true,
            ringProgress = true,
            occurrenceCount = true,
            blizzardHintCountdown = false,
            blizzardHintCentral = false,
        },
        sources = {
            eventColor = "own",
            countdown = "own",
            central = "own",
            castVoice = "own",
            preAlertVoice = "own",
        },
        occurrenceDisplayMode = "inline",
    },
    blizzard = {
        capabilities = {
            perEventEnabled = false,
            eventColor = true,
            centralText = false,
            preAlertText = false,
            timerBarRename = false,
            ringProgress = false,
            -- 暴雪轴的 timeline event id 是运行时实例 ID，不是稳定技能 ID。
            -- 用它统计次数会导致所有事件永远显示 (1)，且暴雪原生名称可能已带次数。
            occurrenceCount = false,
            blizzardHintCountdown = true,
            blizzardHintCentral = true,
        },
        sources = {
            eventColor = "blizzard",
            countdown = "blizzard",
            central = "blizzard_hint",
            castVoice = "blizzard",
            preAlertVoice = "blizzard",
        },
        occurrenceDisplayMode = "none",
        blizzardHintCountdownLead = 5,
        blizzardHintCentralLead = 2,
        blizzardHintCentralDuration = 2,
    },
    test_fixed = {
        capabilities = {
            perEventEnabled = true,
            eventColor = true,
            centralText = true,
            preAlertText = true,
            timerBarRename = true,
            ringProgress = true,
            occurrenceCount = true,
            blizzardHintCountdown = false,
            blizzardHintCentral = false,
        },
        sources = {
            eventColor = "own",
            countdown = "own",
            central = "own",
            castVoice = "own",
            preAlertVoice = "own",
        },
        occurrenceDisplayMode = "inline",
    },
}

function TimelineModeRules:Get(mode)
    local key = tostring(mode or ""):lower()
    return self.rules[key] or self.rules.fixed
end

function TimelineModeRules:ResolveMode(timer, explicitMode)
    if explicitMode then
        return tostring(explicitMode):lower()
    end
    if type(timer) ~= "table" then
        return "fixed"
    end
    if timer.__testFixed == true then
        return "test_fixed"
    end
    if timer.timelineManaged or timer.source == "blizzard" then
        return "blizzard"
    end
    return "fixed"
end
