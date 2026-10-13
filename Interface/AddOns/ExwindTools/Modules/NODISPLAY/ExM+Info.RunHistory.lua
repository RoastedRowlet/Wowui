-- [[ 大秘境赛季记录 ]]
-- { Key = "ExM+Info.RunHistory", Name = "大秘境赛季记录", Desc = "查看本赛季大秘境通关记录表格。", Category = 2 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local EXState = ExwindTools.State
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

-- 1. 识别 Key
local EXWIND_MODULE_KEY = "ExM+Info.RunHistory"

-- 2. 载入检查
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

local EXDB = _G.EXDB

-- 3. 数据初始化
-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXMYRUN_DEFAULTS = {
    size = 16,
    outline = "OUTLINE",
    font = nil,
    filterThisWeek = false,
    filterTimed = false,
    point = "CENTER",
    relativePoint = "CENTER",
    xOfs = 0,
    yOfs = 0,
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXMYRUN_DEFAULTS)

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
-- =========================================================
-- [v4.2] 注册与配置
-- =========================================================


-- 2. 设置页（V2）
EXUI:RegisterModuleSettingsPageV2(EXWIND_MODULE_KEY, {
    version = 2,
    cards = {
        { id = "filters", kind = "card", title = L["过滤设置"], children = {
            { id = "desc", kind = "hint",
                text = L["此模块提供了一个可随时调用的详细战绩表格。使用 /emr 打开窗口。"] },
            { id = "filterThisWeek", kind = "control", controlType = "switch", path = "filterThisWeek",
                label = L["只看本周记录"] },
            { id = "filterTimed", kind = "control", controlType = "switch", path = "filterTimed",
                label = L["只看限时记录"] },
            { id = "size", kind = "control", controlType = "slider", path = "size",
                label = L["显示字号"], min = 10, max = 30 },
        } },
        { id = "preview", kind = "card", title = L["记录预览"], children = {
            { id = "open", kind = "button", text = L["打开记录预览"], clickKey = "open" },
        } },
    },
})

-- 按钮监听
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(data)
    if data.key == "open" then
        if _G.EXMYRUN and _G.EXMYRUN.ToggleWindow then _G.EXMYRUN:ToggleWindow() end
    end
end)

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
-- =========================================================
-- 核心业务逻辑
-- =========================================================
local EXMYRUN = {}
_G.EXMYRUN = EXMYRUN
-- (请勿在此处重复定义 EX_DB.WatchState，统一使用全局监听)

-- 5. 业务逻辑 (变量命名遵循规范)
-- local EXMYRUN = {} -- [Fix] 删除重复定义

local LSM = LibStub("LibSharedMedia-3.0", true)
EXMYRUN.TimeOffset = 8
EXMYRUN.FrameWidth = 960
EXMYRUN.FrameHeight = 620

EXMYRUN.MainFrame = nil
EXMYRUN.SortState = { key = "date", asc = false }
EXMYRUN.DisplayData = {}

-- 工具函数
local function EXMYRUN_FormatTime(seconds)
    if not seconds then return "00:00" end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function EXMYRUN_GetAdjustedCompletionDate(completionDate)
    if not completionDate then return nil end

    local year = completionDate.year
    local month = completionDate.month
    local monthDay = completionDate.monthDay or completionDate.day
    local hour = completionDate.hour or 0
    local minute = completionDate.minute or 0

    if not year or not month or not monthDay then
        return nil
    end

    if year < 100 then
        year = year + 2000
    end
    if month < 1 then
        month = month + 1
    end
    if monthDay < 1 then
        monthDay = monthDay + 1
    end

    local normalizedDate = {
        year = year,
        month = month,
        monthDay = monthDay,
        hour = hour,
        minute = minute,
        weekday = completionDate.weekday,
    }

    if C_DateAndTime and C_DateAndTime.AdjustTimeByMinutes then
        return C_DateAndTime.AdjustTimeByMinutes(normalizedDate, EXMYRUN.TimeOffset * 60)
    end

    return normalizedDate
end

local function EXMYRUN_GetFormattedDate(completionDate)
    if not completionDate then return L["未知"], 0 end

    local adjustedDate = EXMYRUN_GetAdjustedCompletionDate(completionDate)
    if not adjustedDate then
        return L["未知"], 0
    end

    local str = string.format("%02d/%02d %02d:%02d", adjustedDate.month, adjustedDate.monthDay, adjustedDate.hour,
        adjustedDate.minute)
    local sortVal = adjustedDate.year * 100000000 + adjustedDate.month * 1000000 + adjustedDate.monthDay * 10000 +
        adjustedDate.hour * 100 + adjustedDate.minute

    return str, sortVal
end

local function EXMYRUN_GetLevelColorHex(level)
    local colorMixin = C_ChallengeMode.GetKeystoneLevelRarityColor(level)
    return colorMixin and colorMixin:GenerateHexColor() or "ffffffff"
end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
local HISTORY_PAGE = EXWIND_MODULE_KEY .. ".History"
local HISTORY_COLUMNS = {
    { key = "id", title = L["序号"], width = 48, justify = "CENTER" },
    { key = "map", title = L["副本 (层数)"], weight = 1, justify = "LEFT" },
    { key = "date", title = L["日期时间"], width = 148, justify = "LEFT" },
    { key = "result", title = L["结果 (时间)"], width = 180, justify = "LEFT" },
}

EXUI:RegisterSettingsPageV2(HISTORY_PAGE, {
    version = 2,
    cards = {{
        id = "history-card", kind = "card", title = "", children = {
            { id = "history-header", kind = "component", ref = "header" },
            { id = "history-records", kind = "repeat", source = "records", template = {
                id = "history-record", kind = "component", ref = "record",
            } },
            { id = "history-empty", kind = "text", textSource = "empty", visible = "empty" },
        },
    }},
})

local function LayoutHistoryWidget(widget, context, width, height)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT")
    widget:SetSize(width, height)
end

local function SetHistoryWidgetEnabled(widget, context, enabled)
    for _, button in ipairs(widget.sortButtons or {}) do button:SetEnabled(enabled) end
end

local function SetHistoryWidgetVisible(widget, context, visible)
    widget:SetShown(visible)
end

local function UpdateHistoryRecord(row, context)
    local run = context.scope.item
    local fontPath = LSM and LSM:Fetch("font", EX_DB.font) or ExwindTools.MAIN_FONT
    for index, column in ipairs(HISTORY_COLUMNS) do
        local cell = row._exSettingsTableStaticLabels[index]
        cell:SetFont(fontPath, EX_DB.size, EX_DB.outline)
        cell:SetJustifyH(column.justify)
        cell:SetWordWrap(true)
    end

    row._exSettingsTableStaticLabels[1]:SetText(run.originalIndex)
    local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
    local icon = texture and ("|T" .. texture .. ":" .. EX_DB.size .. ":" .. EX_DB.size .. ":0:0:64:64:5:59:5:59|t ") or ""
    local color = EXMYRUN_GetLevelColorHex(run.level)
    row._exSettingsTableStaticLabels[2]:SetText(icon .. "|c" .. color .. (mapName or L["未知副本"]) .. " (+" .. run.level .. ")|r")
    row._exSettingsTableStaticLabels[3]:SetText(run.dateStr)

    local result = "|cff999999" .. L["无时间记录"] .. "|r"
    if run.hasData then
        local difference = EXMYRUN_FormatTime(math.abs(run.durationSec - run.timeLimit))
        if run.isTimed then
            result = string.format("|cff00ff00" .. L["限时 (剩%s)"] .. "|r", difference)
        elseif run.isOverTime then
            result = string.format("|cffff0000" .. L["超时 (超%s)"] .. "|r", difference)
        end
    end
    row._exSettingsTableStaticLabels[4]:SetText(result)
    EXUI:SetSettingsRowLast(row, context.scope.index == #EXMYRUN.DisplayData)
end

function EXMYRUN:CreateHistoryOwner()
    local owner = { controls = {}, components = {}, actions = {}, predicates = {}, sources = {}, texts = {} }
    owner.sources.records = function() return self.DisplayData end
    owner.predicates.empty = function() return #self.DisplayData == 0 end
    owner.texts.summary = function()
        local filters = {}
        if EX_DB.filterThisWeek then filters[#filters + 1] = L["只看本周记录"] end
        if EX_DB.filterTimed then filters[#filters + 1] = L["只看限时记录"] end
        return string.format(L["记录：%d"], #self.DisplayData)
            .. (#filters > 0 and ("  ·  " .. table.concat(filters, " / ")) or "")
    end
    owner.texts.empty = function()
        if self.RawRecordCount > 0 then
            return L["当前筛选条件下没有记录。可在设置中调整筛选条件。"]
        end
        return L["本赛季暂无大秘境通关记录。完成大秘境后可在这里查看副本、层数、日期与通关结果。"]
    end
    owner.onHeightChanged = function(height)
        self.MainFrame.ScrollChild:SetHeight(math.max(1, height))
        self.MainFrame.Scroll:UpdateScrollChildRect()
    end
    owner.components.header = {
        mount = function(host, context)
            local header = EXUI:CreateSettingsTableHeader(host, { columns = HISTORY_COLUMNS })
            header.sortButtons = {}
            for index, column in ipairs(HISTORY_COLUMNS) do
                if column.key ~= "result" then
                    header._exSettingsTableLabels[index]:Hide()
                    local key = column.key
                    header.sortButtons[index] = EXUI:CreateButton(header, 100, 30, column.title,
                        context:Guard(function()
                            if self.SortState.key == key then
                                self.SortState.asc = not self.SortState.asc
                            else
                                self.SortState.key = key
                                self.SortState.asc = (key ~= "date")
                            end
                            self:UpdateList()
                        end), { compact = true })
                end
            end
            return header
        end,
        update = function(header)
            for index, button in ipairs(header.sortButtons) do
                local column = HISTORY_COLUMNS[index]
                local arrow = self.SortState.key == column.key and (self.SortState.asc and " ▲" or " ▼") or ""
                button:SetText(column.title .. arrow)
            end
        end,
        measure = function(header, context, width)
            local _, columns = EXUI:UpdateSettingsTableHeaderLayout(header, width)
            local height = 26
            for index, button in ipairs(header.sortButtons) do
                button:ClearAllPoints()
                button:SetPoint("LEFT", header, "LEFT", columns[index].x + 4, 0)
                button:SetSize(math.max(1, columns[index].width - 8), height)
            end
            local resultLabel = header._exSettingsTableLabels[4]
            resultLabel:ClearAllPoints()
            resultLabel:SetPoint("LEFT", header, "LEFT", columns[4].x + 4, 0)
            resultLabel:SetWidth(math.max(1, columns[4].width - 8))
            return height
        end,
        layout = LayoutHistoryWidget,
        setEnabled = SetHistoryWidgetEnabled,
        setVisible = SetHistoryWidgetVisible,
        release = function(header)
            for _, button in ipairs(header.sortButtons) do ExwindFactory:Release(button._fromPool, button) end
            header.sortButtons = nil
            header:Release()
        end,
    }
    owner.components.record = {
        mount = function(host)
            return EXUI:CreateSettingsTableRow(host, { staticCells = { "", "", "", "" } })
        end,
        update = UpdateHistoryRecord,
        measure = function(row, context, width)
            local columns = EXUI:ResolveSettingsTableColumns(width, HISTORY_COLUMNS)
            local height = math.max(24, EX_DB.size + 6)
            for index, column in ipairs(columns) do
                local cell = row._exSettingsTableStaticLabels[index]
                cell:SetWidth(math.max(1, column.width - 8))
                height = math.max(height, cell:GetStringHeight() + 6)
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", column.x + 4, 0)
            end
            local divider = row._exSettingsTableDivider
            divider:ClearAllPoints()
            divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", columns[1].x, 0)
            divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -columns[1].x, 0)
            return height
        end,
        layout = LayoutHistoryWidget,
        setEnabled = SetHistoryWidgetEnabled,
        setVisible = SetHistoryWidgetVisible,
        release = function(row) row:Release() end,
    }
    return owner
end

-- 窗口几何仍由本模块持有，记录正文由正式 V2 会话持有。
function EXMYRUN:CreateMainFrame()
    local f = CreateFrame("Frame", "EXMYRUNMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(self.FrameWidth, self.FrameHeight)

    if EX_DB.point then
        f:SetPoint(EX_DB.point, UIParent, EX_DB.relativePoint, EX_DB.xOfs, EX_DB.yOfs)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(f:GetFrameLevel() + 101)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        EX_DB.point = point
        EX_DB.relativePoint = relativePoint
        EX_DB.xOfs = xOfs
        EX_DB.yOfs = yOfs
    end)

    local colors = ExwindTools.GUIColors
    EXUI:SetControlSurface(f, ExwindTools.GUIMetrics.radius.card, colors.panel, colors.panelBorder)

    f.Title = EXUI:CreateVisualFontString(f, _G.EXFONTFRAME, "GameFontNormalLarge")
    f.Title:SetPoint("TOPLEFT", 12, -10)
    f.Title:SetTextColor(unpack(colors.text))
    f.Title:SetText(L["大秘境赛季记录"])

    -- 关闭按钮
    f.CloseButton = EXUI:CreateButton(f, 26, 26, "×", function() f:Hide() end,
        { compact = true, variant = "danger" })
    f.CloseButton:SetPoint("TOPRIGHT", -6, -6)

    f.SettingsButton = EXUI:CreateButton(f, 64, 26, L["设置"],
        function() ExwindTools:OpenConfig(EXWIND_MODULE_KEY) end, { compact = true })
    f.SettingsButton:SetPoint("RIGHT", f.CloseButton, "LEFT", -8, 0)
    f.Summary = EXUI:CreateVisualFontString(f, _G.EXFONTFRAME, "GameFontHighlightSmall")
    f.Summary:SetPoint("LEFT", f.Title, "RIGHT", 12, 0)
    f.Summary:SetPoint("RIGHT", f.SettingsButton, "LEFT", -12, 0)
    f.Summary:SetJustifyH("LEFT")
    f.Summary:SetWordWrap(false)
    f.Summary:SetTextColor(unpack(colors.text))

    f.Scroll = EXUI:CreateScrollFrame(f, "EXMYRUNHistoryScroll")
    f.Scroll:SetPoint("TOPLEFT", 4, -38)
    f.Scroll:SetPoint("BOTTOMRIGHT", -EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET, 4)

    f.ScrollChild = CreateFrame("Frame", nil, f.Scroll)
    f.ScrollChild:SetSize(f.Scroll:GetWidth(), 1)
    f.Scroll:SetScrollChild(f.ScrollChild)

    self.MainFrame = f
    self.HistoryOwner = self:CreateHistoryOwner()
    f.Scroll:HookScript("OnSizeChanged", function(scroll)
        f.ScrollChild:SetWidth(scroll:GetWidth())
    end)
    f:SetScript("OnHide", function()
        if self.HistorySession then
            self.HistorySession:Release()
            self.HistorySession = nil
        end
    end)
    f:Hide()
end

function EXMYRUN:UpdateList()
    if not self.MainFrame then return end

    local rawData = C_MythicPlus.GetRunHistory(true, true, true)
    self.RawRecordCount = #rawData
    local displayData = {}

    for i, run in ipairs(rawData) do
        local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
        local isTimed, isOverTime, hasData = false, false, false

        if run.durationSec and run.durationSec > 0 and timeLimit and timeLimit > 0 then
            hasData = true
            if run.durationSec <= timeLimit then
                isTimed = true
            else
                isOverTime = true
            end
        end

        local pass = true
        if EX_DB.filterThisWeek and not run.thisWeek then pass = false end
        if EX_DB.filterTimed and not isTimed then pass = false end

        if pass then
            run.originalIndex = i
            local mapName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
            run.mapNameSort = mapName or ""
            local str, sortVal = EXMYRUN_GetFormattedDate(run.completionDate)
            run.dateStr = str
            run.dateSort = sortVal
            run.isTimed = isTimed
            run.isOverTime = isOverTime
            run.timeLimit = timeLimit
            run.hasData = hasData
            table.insert(displayData, run)
        end
    end

    -- [Safety] 确保数据表紧凑，无 nil 空洞
    local compactData = {}
    for _, v in pairs(displayData) do
        if v then table.insert(compactData, v) end
    end
    displayData = compactData

    table.sort(displayData, function(a, b)
        if not a or not b then return false end
        local k = self.SortState.key
        local asc = self.SortState.asc

        if k == "id" then
            if a.originalIndex == b.originalIndex then return false end
            if asc then return a.originalIndex < b.originalIndex else return a.originalIndex > b.originalIndex end
        elseif k == "map" then
            if a.mapNameSort ~= b.mapNameSort then
                if asc then return a.mapNameSort < b.mapNameSort else return a.mapNameSort > b.mapNameSort end
            end
            if a.level ~= b.level then return a.level > b.level end
            return a.originalIndex < b.originalIndex
        elseif k == "date" then
            local aSort = a.dateSort or 0
            local bSort = b.dateSort or 0
            if aSort ~= bSort then
                if asc then return aSort < bSort else return aSort > bSort end
            end
            return a.originalIndex < b.originalIndex
        end
        return a.originalIndex < b.originalIndex
    end)

    self.DisplayData = displayData
    self.MainFrame.Summary:SetText(self.HistoryOwner.texts.summary())
    if self.HistorySession then
        self.HistorySession:Refresh()
    elseif self.MainFrame:IsShown() then
        self.HistorySession = EXUI:MountSettingsPageV2(self.MainFrame.ScrollChild, HISTORY_PAGE, self.HistoryOwner)
    end
end

function EXMYRUN:ToggleWindow()
    if not self.MainFrame then
        self:CreateMainFrame()
    end
    if self.MainFrame:IsShown() then
        self.MainFrame:Hide()
    else
        self.MainFrame:Show()
        self:UpdateList()
    end
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
-- 注册斜杠命令
SLASH_EXMYRUN1 = "/emr"
SLASH_EXMYRUN2 = "/exmythicrun"
SlashCmdList["EXMYRUN"] = function()
    EXMYRUN:ToggleWindow()
end

local function RefreshActiveSurfaces()
    EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXMYRUN_DEFAULTS)
    if EXMYRUN.MainFrame and EXMYRUN.MainFrame:IsShown() then EXMYRUN:UpdateList() end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
