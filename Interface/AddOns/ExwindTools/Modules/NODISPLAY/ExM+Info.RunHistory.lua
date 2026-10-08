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


-- 2. Grid 布局
local function EX_RegisterLayout()
    -- [声明迁移边界：设置页] 仅把原筛选与打开按钮改为 settings 声明；纯装饰 divider 不进入新合同。
    -- key/type、筛选/按钮绑定及历史记录排序禁止修改。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings",
                id = "filters",
                title = L["过滤设置"],
                description = {
                    key = "desc",
                    type = "description",
                    label = L["此模块提供了一个可随时调用的详细战绩表格。使用 /emr 打开窗口。"],
                },
                items = {
                    { key = "filterThisWeek", type = "switch", label = L["只看本周记录"] },
                    { key = "filterTimed", type = "switch", label = L["只看限时记录"] },
                    { key = "size", type = "slider", label = L["显示字号"], min = 10, max = 30 },
                },
            },
            {
                kind = "settings",
                id = "preview",
                title = L["记录预览"],
                items = {
                    { key = "open", type = "button", label = L["打开记录预览"] },
                },
            },
        },
    }

    EXUI:RegisterSettingsPage(EXWIND_MODULE_KEY, layout)
end

-- 3. 立即注册
EX_RegisterLayout()

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
EXMYRUN.RowHeight = 25
EXMYRUN.FrameWidth = 700
EXMYRUN.FrameHeight = 600

EXMYRUN.MainFrame = nil
EXMYRUN.SortState = { key = "date", asc = false }

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
-- 界面构建
-- [卡片迁移边界：自定义渲染] 下列历史窗口、表头、滚动区和行池不是设置页 Grid；迁移设置卡片时禁止改其尺寸、排序、拖动与点击回调。
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

    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.98)

    f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.Title:SetPoint("TOP", 0, -10)
    f.Title:SetText(L["大秘境赛季记录"])

    -- 关闭按钮
    local closeBtn = EXUI:CreatePicButton(f, 24, 24,
        "Interface\\Buttons\\UI-Panel-CloseButton-Up",
        "Interface\\Buttons\\UI-Panel-CloseButton-Down",
        "Interface\\Buttons\\UI-Panel-CloseButton-Highlight",
        function() f:Hide() end, true)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    local configBtn = EXUI:CreateButton(f, 80, 22, L["设置"], function()
        if ExwindTools.UI then ExwindTools.UI:Toggle() end
    end, { compact = true })
    configBtn:SetPoint("TOPLEFT", 10, -10)

    f.headers = {
        { key = "id", text = L["序号"], width = 50, justify = "CENTER" },
        { key = "map", text = L["副本 (层数)"], width = 280, justify = "LEFT" },
        { key = "date", text = L["日期时间"], width = 140, justify = "LEFT" },
        { key = "result", text = L["结果 (时间)"], width = 250, justify = "LEFT" },
    }

    local currentX = 20
    local headerY = -45
    f.headerBtns = {}

    for _, col in ipairs(f.headers) do
        local btn = EXUI:CreateButton(f, col.width, 20, col.text, nil, { compact = true })
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", currentX, headerY)
        btn:SetSize(col.width, 20)

        local text = btn:GetFontString()
        text:SetAllPoints()
        text:SetJustifyH(col.justify)
        text:SetText(col.text)
        btn.textWidget = text
        btn.key = col.key
        btn.textData = col.text

        btn:SetScript("OnClick", function(self)
            if self.key == "result" then return end
            if EXMYRUN.SortState.key == self.key then
                EXMYRUN.SortState.asc = not EXMYRUN.SortState.asc
            else
                EXMYRUN.SortState.key = self.key
                EXMYRUN.SortState.asc = (self.key ~= "date")
            end
            EXMYRUN:UpdateList()
        end)

        table.insert(f.headerBtns, btn)
        currentX = currentX + col.width
    end

    f.Scroll = CreateFrame("ScrollFrame", "EXMYRUNHistoryScroll", f, "ScrollFrameTemplate")
    f.Scroll:EnableMouseWheel(true)
    EXUI:ApplyModernScrollFrame(f.Scroll)
    f.Scroll:SetPoint("TOPLEFT", 10, headerY - 25)
    f.Scroll:SetPoint("BOTTOMRIGHT", -18, 10)

    f.ScrollChild = CreateFrame("Frame", nil, f.Scroll)
    f.ScrollChild:SetSize(self.FrameWidth - 40, 1)
    f.Scroll:SetScrollChild(f.ScrollChild)

    self.MainFrame = f
    f:Hide()
end

function EXMYRUN:UpdateList(reuseOnly)
    if not self.MainFrame then return end

    local rawData = C_MythicPlus.GetRunHistory(true, true, true)
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

    for _, btn in ipairs(self.MainFrame.headerBtns) do
        local arrow = ""
        if self.SortState.key == btn.key then
            arrow = self.SortState.asc and " |cff00ff00▲|r" or " |cff00ff00▼|r"
        end
        btn.textWidget:SetText(btn.textData .. arrow)
    end

    -- 正常打开窗口可从池取得行；GUI 自动刷新只能重套已经物化的行。
    self.ActiveRows = self.ActiveRows or {}
    if not reuseOnly then
        for _, row in ipairs(self.ActiveRows) do
            ExwindFactory:Release("StandardRow", row)
        end
        wipe(self.ActiveRows)
    end

    local totalHeight = 0
    local fontPath = LSM and LSM:Fetch("font", EX_DB.font) or ExwindTools.MAIN_FONT

    for i, run in ipairs(displayData) do
        local row = reuseOnly and self.ActiveRows[i] or ExwindFactory:Acquire("StandardRow", self.MainFrame.ScrollChild)
        if not row then break end
        if not reuseOnly then table.insert(self.ActiveRows, row) end

        row:Show()
        row:SetSize(self.FrameWidth - 40, EX_DB.size + 12)
        row:SetPoint("TOPLEFT", self.MainFrame.ScrollChild, "TOPLEFT", 0, -totalHeight)

        if i % 2 == 0 then row.bg:Show() else row.bg:Hide() end

        -- 配置列对齐和字体 (StandardRow 预设了 5 个 cells)
        for idx, col in ipairs(self.MainFrame.headers) do
            local cell = row.cells[idx]
            if cell then
                cell:SetFont(fontPath, EX_DB.size, EX_DB.outline)
                cell:SetJustifyH(col.justify)
                -- 动态调整位置
                local xOfs = 10
                for prevIdx = 1, idx - 1 do
                    xOfs = xOfs + self.MainFrame.headers[prevIdx].width
                end
                cell:SetPoint("LEFT", row, "LEFT", xOfs, 0)
                cell:SetWidth(col.width)
            end
        end

        row.cells[1]:SetText(run.originalIndex)
        local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
        -- 为内联图标应用裁剪标准 (0.08, 0.92 对应 64像素下的 5:59)
        local icon = texture and ("|T" .. texture .. ":" .. EX_DB.size .. ":" .. EX_DB.size .. ":0:0:64:64:5:59:5:59|t ") or
            ""
        local color = EXMYRUN_GetLevelColorHex(run.level)
        row.cells[2]:SetText(icon .. "|c" .. color .. (mapName or L["未知副本"]) .. " (+" .. run.level .. ")|r")
        row.cells[3]:SetText(run.dateStr)

        local res = "|cff999999" .. L["无时间记录"] .. "|r"
        if run.hasData then
            local diff = math.abs(run.durationSec - run.timeLimit)
            local diffStr = EXMYRUN_FormatTime(diff)
            if run.isTimed then
                res = string.format("|cff00ff00" .. L["限时 (剩%s)"] .. "|r", diffStr)
            elseif run.isOverTime then
                res = string.format("|cffff0000" .. L["超时 (超%s)"] .. "|r", diffStr)
            end
        end
        row.cells[4]:SetText(res)

        totalHeight = totalHeight + (EX_DB.size + 12)
    end
    if reuseOnly then
        for i = #displayData + 1, #self.ActiveRows do self.ActiveRows[i]:Hide() end
    end
    self.MainFrame.ScrollChild:SetHeight(totalHeight)
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
    if EXMYRUN.MainFrame and EXMYRUN.MainFrame:IsShown() then EXMYRUN:UpdateList(true) end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
-- 报告模块加载完成
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
