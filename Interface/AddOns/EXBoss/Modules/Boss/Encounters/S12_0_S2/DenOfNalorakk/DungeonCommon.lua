---@diagnostic disable: undefined-global, undefined-field
-- 纳洛拉克的洞穴副本通用机制：1 号死亡至 2 号开战之间的强风提示。

local ExwindTools = _G.ExwindTools
if not ExwindTools or type(ExwindTools.RegisterEvent) ~= "function" then
    return
end

local MODULE_KEY = "ExBoss.DenOfNalorakk.HarshWinds"
-- EXDB 的纳洛拉克条目仅以 instanceID 登记，没有可查询的语义 key。
local DUNGEON_INSTANCE_ID = 2825
local SPELL_ID = 1252825
local TIMER_ID = "exboss:den_of_nalorakk:harsh_winds"
local BAR_DURATION = 50
local CAST_DURATION = 15
local OWNER = {
    source = "den_of_nalorakk_harsh_winds",
    earlyStopEnabled = true,
}

local function GetState()
    return ExwindTools and ExwindTools.State or nil
end

local function GetDungeonMeta()
    local exdb = _G.EXDB
    if exdb and type(exdb.GetInstanceNoteMetaByInstanceID) == "function" then
        return exdb:GetInstanceNoteMetaByInstanceID(DUNGEON_INSTANCE_ID)
    end
    return nil
end

local function IsInTargetDungeon()
    local state = GetState()
    local meta = GetDungeonMeta()
    if type(state) ~= "table" or type(meta) ~= "table" then
        return false
    end

    -- 先确认确实在五人副本；副本归属只以 InstanceID 判断。
    -- MapID 是玩家地图上下文，MapGroup 是地图归组，均不能替代副本 ID。
    if state.InInstance ~= true or tostring(state.InstanceType or "") ~= "party" then
        return false
    end

    local instanceID = tonumber(state.InstanceID) or 0
    return instanceID == (tonumber(meta.instanceID) or 0)
end

local function BuildDisplayData(now)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(SPELL_ID)
    return {
        spellID = SPELL_ID,
        displaySource = "boss",
        displayName = (info and info.name) or tostring(SPELL_ID),
        iconFileID = info and info.iconID or nil,
        castTime = now + BAR_DURATION,
        duration = BAR_DURATION,
        timerBarDuration = BAR_DURATION,
        barPriority = 2,
    }
end

local function StopHarshWinds()
    local ui = ExBoss and ExBoss.UI or nil
    local bunBar = ui and ui.BunBar or nil
    if bunBar and type(bunBar.StopExternalTimer) == "function" then
        bunBar:StopExternalTimer(TIMER_ID)
    end

    local castBar = ui and ui.CastProgressBar or nil
    if castBar and type(castBar.StopByOwner) == "function" then
        castBar:StopByOwner(OWNER)
    end
end

local function IsWarningWindowOpen()
    if not IsInTargetDungeon() then
        return false
    end

    local state = GetState()
    if type(state) ~= "table" then
        return false
    end

    -- State 的定义：ProgressIndex=2 即 1 号已死亡、2 号前。
    -- 额外要求当前不在首领战；2 号 ENCOUNTER_START 时 State 会立刻置为 true，
    -- 由 WatchState 回调清除已有条目。
    local killedCount = tonumber(state.DungeonBossKilledCount) or 0
    local progressIndex = tonumber(state.DungeonBossProgressIndex) or 0
    return killedCount == 1 and progressIndex == 2 and state.IsBossEncounter ~= true
end

local function StartOrResetHarshWinds()
    if not IsWarningWindowOpen() then
        return
    end

    local now = GetTime()
    local timer = BuildDisplayData(now)
    timer.id = TIMER_ID

    local ui = ExBoss and ExBoss.UI or nil
    local bunBar = ui and ui.BunBar or nil
    if bunBar and type(bunBar.StartExternalTimer) == "function" then
        bunBar:StartExternalTimer(timer)
    end

    local castBar = ui and ui.CastProgressBar or nil
    if castBar and type(castBar.StopByOwner) == "function" then
        castBar:StopByOwner(OWNER)
    end
    if castBar and type(castBar.ShowEntry) == "function" then
        castBar:ShowEntry({
            duration = CAST_DURATION,
            endTime = now + CAST_DURATION,
            spellID = SPELL_ID,
            displayName = timer.displayName,
            iconFileID = timer.iconFileID,
            owner = OWNER,
        })
    end
end

local function ReconcileWarningWindow()
    if not IsWarningWindowOpen() then
        StopHarshWinds()
    end
end

-- 不读取、不过滤 ENCOUNTER_WARNING 的任何参数：窗口内每次事件都重新开始计时。
ExwindTools:RegisterEvent("ENCOUNTER_WARNING", MODULE_KEY .. ".EncounterWarning", function()
    StartOrResetHarshWinds()
end)

ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", MODULE_KEY .. ".PlayerEnteringWorld", function()
    StopHarshWinds()
end)

-- 副本切换、1 号击杀后的进度刷新、以及 2 号开战都会经过 State。
-- 状态一旦离开有效窗口，立刻只回收本模块创建的条目。
if type(ExwindTools.WatchState) == "function" then
    ExwindTools:WatchState("InstanceID", MODULE_KEY .. ".InstanceID", ReconcileWarningWindow)
    ExwindTools:WatchState("InInstance", MODULE_KEY .. ".InInstance", ReconcileWarningWindow)
    ExwindTools:WatchState("InstanceType", MODULE_KEY .. ".InstanceType", ReconcileWarningWindow)
    ExwindTools:WatchState("DungeonBossKilledCount", MODULE_KEY .. ".BossProgress", ReconcileWarningWindow)
    ExwindTools:WatchState("DungeonBossProgressIndex", MODULE_KEY .. ".BossProgressIndex", ReconcileWarningWindow)
    ExwindTools:WatchState("IsBossEncounter", MODULE_KEY .. ".BossEncounter", ReconcileWarningWindow)
    ExwindTools:WatchState("EncounterID", MODULE_KEY .. ".EncounterID", ReconcileWarningWindow)
end
