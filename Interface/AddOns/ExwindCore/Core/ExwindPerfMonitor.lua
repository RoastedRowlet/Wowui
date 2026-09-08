---@diagnostic disable: undefined-global, undefined-field, need-check-nil
-- =============================================================
-- [[ ExwindTools 副本内 CPU/FPS 性能监控模块 ]]
-- 用途：在 Boss 战斗（ENCOUNTER_START ~ ENCOUNTER_END）期间，按秒采集
-- ExwindCore / EXBoss / EXAura / ExwindTools 四个插件的 CPU 占用（基于
-- 12.x 新版 C_AddOnProfiler，不需要旧版 scriptProfile CVar 或 /reload），
-- 同时记录当下 FPS、副本信息、是否处于 Boss 战斗，用于事后排查"到底是
-- 哪个插件在战斗中吃 CPU"。
--
-- 只在 Boss 战斗进行期间采样，不战斗时不跑 ticker，避免这个诊断工具本身
-- 变成新的常驻开销。默认关闭，需要 /exwindperf on 手动开启。
-- =============================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools then return end
if not C_AddOnProfiler then return end
local EXUI = ExwindTools.UI

local PerfMonitor = {}
ExwindTools.PerfMonitor = PerfMonitor

local ADDON_NAMES = { "ExwindCore", "EXBoss", "EXAura", "ExwindTools" }
local SAMPLE_INTERVAL = 1
local MAX_ENCOUNTERS = 20

local Metric = Enum.AddOnProfilerMetric

local db
local ticker
local currentEncounter

local function EnsureDB()
    if db then return db end
    EXCORE12S2 = EXCORE12S2 or {}
    EXCORE12S2.PerfMonitor = EXCORE12S2.PerfMonitor or {
        enabled = false,
        encounters = {},
    }
    db = EXCORE12S2.PerfMonitor
    return db
end

local function GetMetric(name, metric)
    return C_AddOnProfiler.GetAddOnMetric(name, metric) or 0
end

local function StopSampling()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function SampleTick()
    if not currentEncounter then
        StopSampling()
        return
    end
    local sample = {
        t = math.floor((GetTime() - currentEncounter.startTime) * 10) / 10,
        fps = math.floor(GetFramerate() * 10) / 10,
    }
    for _, name in ipairs(ADDON_NAMES) do
        sample[name] = GetMetric(name, Metric.LastTime)
    end
    currentEncounter.samples[#currentEncounter.samples + 1] = sample
end

local function StartSampling()
    StopSampling()
    ticker = C_Timer.NewTicker(SAMPLE_INTERVAL, SampleTick)
end

local function TrimEncounterHistory()
    local list = EnsureDB().encounters
    while #list > MAX_ENCOUNTERS do
        table.remove(list, 1)
    end
end

local function OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    if not EnsureDB().enabled then return end
    local _, instanceType, _, difficultyName, _, _, _, instanceMapID = GetInstanceInfo()
    currentEncounter = {
        encounterID = encounterID,
        encounterName = encounterName,
        difficultyID = difficultyID,
        difficultyName = difficultyName,
        groupSize = groupSize,
        instanceType = instanceType,
        instanceMapID = instanceMapID,
        startTime = GetTime(),
        samples = {},
    }
    StartSampling()
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    StopSampling()
    if not currentEncounter or currentEncounter.encounterID ~= encounterID then
        currentEncounter = nil
        return
    end

    currentEncounter.success = success == 1
    currentEncounter.duration = math.floor((GetTime() - currentEncounter.startTime) * 10) / 10
    currentEncounter.avgCPU = {}
    currentEncounter.peakCPU = {}
    for _, name in ipairs(ADDON_NAMES) do
        currentEncounter.avgCPU[name] = GetMetric(name, Metric.EncounterAverageTime)
        currentEncounter.peakCPU[name] = GetMetric(name, Metric.PeakTime)
    end
    currentEncounter.top10 = C_AddOnProfiler.GetTopKAddOnsForMetric(Metric.EncounterAverageTime, 10)

    local list = EnsureDB().encounters
    list[#list + 1] = currentEncounter
    TrimEncounterHistory()
    currentEncounter = nil
end

ExwindTools:RegisterEvent("ENCOUNTER_START", "PerfMonitor", OnEncounterStart)
ExwindTools:RegisterEvent("ENCOUNTER_END", "PerfMonitor", OnEncounterEnd)

-- =========================================================
-- 公共接口
-- =========================================================

function PerfMonitor:SetEnabled(enabled)
    EnsureDB().enabled = enabled and true or false
    if not enabled then
        StopSampling()
        currentEncounter = nil
    end
end

function PerfMonitor:IsEnabled()
    return EnsureDB().enabled
end

function PerfMonitor:GetEncounters()
    return EnsureDB().encounters
end

function PerfMonitor:ClearHistory()
    EnsureDB().encounters = {}
end

-- =========================================================
-- 任意函数耗时埋点（给其他模块用，比如 TrashCD 的热路径函数）
-- =========================================================

PerfMonitor.timingStats = {}

--- 记录一次调用耗时。key 是调用方自己起的标识名（比如"TrashCD.BuildCandidates"），
--- elapsedMs 通常是 debugprofilestop() 两次取差得到的毫秒数。
function PerfMonitor:RecordTiming(key, elapsedMs)
    local stat = self.timingStats[key]
    if not stat then
        stat = { count = 0, total = 0, max = 0 }
        self.timingStats[key] = stat
    end
    stat.count = stat.count + 1
    stat.total = stat.total + elapsedMs
    if elapsedMs > stat.max then
        stat.max = elapsedMs
    end
end

function PerfMonitor:ResetTimingStats()
    wipe(self.timingStats)
end

function PerfMonitor:GetTimingStats()
    return self.timingStats
end

-- =========================================================
-- 常驻小面板（显示埋点耗时统计 + 重置按钮）
-- =========================================================

local Panel
local PANEL_ROW_COUNT = 16
local PANEL_ROW_HEIGHT = 18
local PANEL_REFRESH_INTERVAL = 0.5

local function CreatePanel()
    local f = CreateFrame("Frame", "ExwindPerfMonitorPanel", UIParent, "BackdropTemplate")
    f:SetSize(460, 66 + PANEL_ROW_COUNT * PANEL_ROW_HEIGHT)
    f:SetPoint("CENTER", 0, 200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetFrameStrata("HIGH")

    local title = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("|cff33ff99Exwind Perf Monitor|r")

    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(56, 20)
    resetBtn:SetPoint("TOPRIGHT", -28, -6)
    resetBtn:SetText(L["重置"])
    resetBtn:SetScript("OnClick", function()
        PerfMonitor:ResetTimingStats()
        Panel.scrollOffset = 0
        PerfMonitor:RefreshPanel()
    end)

    local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    copyBtn:SetSize(56, 20)
    copyBtn:SetPoint("TOPRIGHT", resetBtn, "TOPLEFT", -6, 0)
    copyBtn:SetText(L["复制"])
    copyBtn:SetScript("OnClick", function()
        PerfMonitor:ShowCopyBox()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local header = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontDisableSmall")
    header:SetPoint("TOPLEFT", 10, -26)
    header:SetText(L["埋点名称 / 次数 / 平均 / 峰值 / 总计（滚轮翻页）"])

    f.scrollOffset = 0
    f:SetScript("OnMouseWheel", function(self, delta)
        self.scrollOffset = math.max(0, (self.scrollOffset or 0) - delta * 3)
        PerfMonitor:RefreshPanel()
    end)

    f.rows = {}
    for i = 1, PANEL_ROW_COUNT do
        local row = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", 10, -42 - (i - 1) * PANEL_ROW_HEIGHT)
        row:SetPoint("RIGHT", -10, 0)
        row:SetHeight(PANEL_ROW_HEIGHT)
        row:SetJustifyH("LEFT")
        row:SetWordWrap(false)
        row:Hide()
        f.rows[i] = row
    end

    f.emptyText = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontDisableSmall")
    f.emptyText:SetPoint("TOPLEFT", 10, -42)
    f.emptyText:SetText(L["暂无数据（等待被埋点的函数被调用）"])

    f.footerText = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontDisableSmall")
    f.footerText:SetPoint("BOTTOMLEFT", 10, 6)

    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < PANEL_REFRESH_INTERVAL then return end
        self._t = 0
        PerfMonitor:RefreshPanel()
    end)

    f:Hide()
    Panel = f
    return f
end

function PerfMonitor:RefreshPanel()
    if not Panel or not Panel:IsShown() then return end

    local keys = {}
    for key in pairs(self.timingStats) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return self.timingStats[a].total > self.timingStats[b].total end)

    local total = #keys
    local maxOffset = math.max(0, total - PANEL_ROW_COUNT)
    Panel.scrollOffset = math.min(Panel.scrollOffset or 0, maxOffset)
    local offset = Panel.scrollOffset

    Panel.emptyText:SetShown(total == 0)

    for i, row in ipairs(Panel.rows) do
        local key = keys[offset + i]
        if key then
            local s = self.timingStats[key]
            row:SetText(string.format(L["%s   x%d   平均 %.2fms   峰值 %.2fms   总计 %.0fms"],
                key, s.count, s.total / math.max(1, s.count), s.max, s.total))
            row:Show()
        else
            row:Hide()
        end
    end

    if total > 0 then
        Panel.footerText:SetText(string.format(L["共 %d 条，当前显示第 %d-%d 条"],
            total, offset + 1, math.min(total, offset + PANEL_ROW_COUNT)))
    else
        Panel.footerText:SetText("")
    end
end

-- =========================================================
-- 复制文本框（面板上文字是FontString不能选中，这里单独开一个可复制的编辑框）
-- =========================================================

local CopyBox

local function CreateCopyBox()
    local f = CreateFrame("Frame", "ExwindPerfMonitorCopyBox", UIParent, "BackdropTemplate")
    f:SetSize(520, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.95)

    local title = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L["|cff33ff99全选已完成，直接 Ctrl+C 复制|r"])

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f, "ScrollFrameTemplate")
    scroll:EnableMouseWheel(true)
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(468)
    editBox:SetAutoFocus(false)
    editBox:EnableMouseWheel(true)
    editBox:HookScript("OnMouseWheel", function(_, delta)
        local onMouseWheel = scroll:GetScript("OnMouseWheel")
        if onMouseWheel then
            onMouseWheel(scroll, delta)
        end
    end)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(editBox)

    f.editBox = editBox
    f:Hide()
    CopyBox = f
    return f
end

function PerfMonitor:ShowCopyBox()
    if not CopyBox then CreateCopyBox() end

    local keys = {}
    for key in pairs(self.timingStats) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return self.timingStats[a].total > self.timingStats[b].total end)

    local lines = {}
    for _, key in ipairs(keys) do
        local s = self.timingStats[key]
        lines[#lines + 1] = string.format(L["%s   x%d   平均%.2fms   峰值%.2fms   总计%.0fms"],
            key, s.count, s.total / math.max(1, s.count), s.max, s.total)
    end
    if #lines == 0 then
        lines[1] = L["（暂无数据）"]
    end

    CopyBox.editBox:SetText(table.concat(lines, "\n"))
    CopyBox:Show()
    CopyBox.editBox:HighlightText()
    CopyBox.editBox:SetFocus()
end

function PerfMonitor:ShowPanel()
    if not Panel then CreatePanel() end
    Panel:Show()
    self:RefreshPanel()
end

function PerfMonitor:HidePanel()
    if Panel then Panel:Hide() end
end

function PerfMonitor:TogglePanel()
    if Panel and Panel:IsShown() then
        self:HidePanel()
    else
        self:ShowPanel()
    end
end

-- =========================================================
-- 斜杠命令
-- =========================================================

local function FormatMs(ms)
    return string.format("%.2f", ms or 0)
end

local function PrintEncounterSummary(entry, index)
    print(string.format(L["|cff33ff99[ExwindPerf]|r #%s %s (难度:%s 人数:%s) 时长 %.1fs 成功:%s"],
        tostring(index), entry.encounterName or "?", entry.difficultyName or "?", tostring(entry.groupSize),
        entry.duration or 0, entry.success and L["是"] or L["否"]))

    for _, name in ipairs(ADDON_NAMES) do
        local avg = entry.avgCPU and entry.avgCPU[name]
        local peak = entry.peakCPU and entry.peakCPU[name]
        if avg or peak then
            print(string.format(L["    %s: 平均 %sms  峰值 %sms"], name, FormatMs(avg), FormatMs(peak)))
        end
    end

    if entry.samples and #entry.samples > 0 then
        local minFPS, maxFPS, sumFPS = math.huge, 0, 0
        for _, s in ipairs(entry.samples) do
            minFPS = math.min(minFPS, s.fps)
            maxFPS = math.max(maxFPS, s.fps)
            sumFPS = sumFPS + s.fps
        end
        print(string.format(L["    FPS: 最低 %.1f  最高 %.1f  平均 %.1f  (采样点数 %d)"],
            minFPS, maxFPS, sumFPS / #entry.samples, #entry.samples))
    end

    if entry.top10 then
        local parts = {}
        for i, r in ipairs(entry.top10) do
            if i > 5 then break end
            parts[#parts + 1] = string.format("%s(%sms)", r.addOnName, FormatMs(r.metricValue))
        end
        print(L["    全服插件Top5(按本次战斗平均耗时): "] .. table.concat(parts, ", "))
    end
end

SLASH_EXWINDPERF1 = "/exwindperf"
SlashCmdList["EXWINDPERF"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "on" then
        PerfMonitor:SetEnabled(true)
        print(L["|cff33ff99[ExwindPerf]|r 已开启，下次进入 Boss 战斗会自动采样。"])
    elseif cmd == "off" then
        PerfMonitor:SetEnabled(false)
        print(L["|cff33ff99[ExwindPerf]|r 已关闭。"])
    elseif cmd == "clear" then
        PerfMonitor:ClearHistory()
        print(L["|cff33ff99[ExwindPerf]|r 历史记录已清空。"])
    elseif cmd == "panel" then
        PerfMonitor:TogglePanel()
    elseif cmd == "status" then
        print(string.format(L["|cff33ff99[ExwindPerf]|r 开关:%s  C_AddOnProfiler可用:%s  当前是否在采样:%s  已保存战斗数:%d"],
            PerfMonitor:IsEnabled() and L["开"] or L["关"],
            C_AddOnProfiler.IsEnabled() and L["是"] or L["否"],
            currentEncounter and L["是"] or L["否"],
            #PerfMonitor:GetEncounters()))
    elseif cmd == "dump" then
        local n = tonumber(rest) or 1
        local list = PerfMonitor:GetEncounters()
        if #list == 0 then
            print(L["|cff33ff99[ExwindPerf]|r 没有已保存的战斗记录。"])
            return
        end
        local from = math.max(1, #list - n + 1)
        for i = from, #list do
            PrintEncounterSummary(list[i], i)
        end
    else
        print(L["|cff33ff99[ExwindPerf]|r 用法: /exwindperf on|off|status|dump [n]|clear|panel"])
    end
end
