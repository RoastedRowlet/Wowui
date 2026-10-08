-- [[ MDT 法术图标替换 ]]
-- { Key = "ExM+Info.MDTIconHook", Name = "MDT 法术图标替换", Desc = "将 MDT 地图中怪物头像替换为法术图标。", Category = 2 },

-- =========================================================
-- 一、模块标识与依赖引用 | Module Identity and Dependencies
-- =========================================================
local ExwindTools = _G.ExwindTools
local EXDB = _G.EXDB
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExM+Info.MDTIconHook"
local CUSTOM_ICONS_RENDERER = EXWIND_MODULE_KEY .. ".CustomIcons"
local BLACKLIST_RENDERER = EXWIND_MODULE_KEY .. ".Blacklist"
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local EXWIND_DEFAULTS = {
    enabled = true,
    useSpellIconMode = false,

    customNPCIcons = {},
    blacklistNPCs = {},
    customIconsText = "", -- 缓存文本
    blacklistText = "",   -- 缓存文本
}
local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EXWIND_DEFAULTS)
EX_DB.customNPCIcons = EX_DB.customNPCIcons or {}
EX_DB.blacklistNPCs = EX_DB.blacklistNPCs or {}

-- =========================================================
-- 五、业务状态与功能逻辑 | Business State and Logic
-- =========================================================
local MDT_HOOK_INSTALLED = false
local MDT_BUTTONS_CREATED = false
local MDT_PANEL_ATTACHED = false
local MDT_PANEL_FRAME_HOOKED = false

-- MDT 6.2.2 拆成 MythicDungeonTools（核心）+ MythicDungeonTools_UI（LoadOnDemand），
-- 并删除了 _G.MDT。本模块的集成入口只使用公开面：
--   _G.MythicDungeonToolsAPI:RegisterUIInitializer（UI 挂载时回调，早于主框体与 blip 池创建）
--   _G.MDTDungeonEnemyMixin（DungeonEnemies.lua 仍是真全局，地图怪物按钮 mixin）
--   _G.MDTFrame（MainFrame.lua 仍是真全局，MDT 主框体）
local AttachToMDTFrame

-- blip 由 MDT 自己的框体池复用；mixin hook 每次 SetUp 都会把当前 blip 记下来，
-- 切换图标模式时直接重投影自己画过的图标，不需要 MDT 的地图重绘内部接口。
local TRACKED_BLIPS = setmetatable({}, { __mode = "k" })

local function ApplyIconToBlip(blip, data)
    local texture = blip and blip.texture_Portrait
    if not texture or not data then return end

    local spellTexture
    if EX_DB.enabled and EX_DB.useSpellIconMode and not data.isBoss and not data.iconTexture
        and not EX_DB.blacklistNPCs[data.id] then
        local targetID = EX_DB.customNPCIcons[data.id] or data.SPELLICON or (data.spells and next(data.spells))
        if targetID then
            spellTexture = C_Spell.GetSpellTexture(targetID)
        end
    end

    if spellTexture then
        texture:SetTexture(spellTexture)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        blip._exSpellIconApplied = true
    elseif blip._exSpellIconApplied then
        -- MDT 的 SetUp 只在 portrait 变化时重设材质，关闭本功能后必须自己还原头像。
        blip._exSpellIconApplied = nil
        texture:SetTexCoord(0, 1, 0, 1)
        if data.iconTexture then
            texture:SetTexture(data.iconTexture)
        else
            SetPortraitTextureFromCreatureDisplayID(texture, data.displayId or 39490)
        end
    end
end

local function ApplyIconsToKnownBlips(silent)
    for blip in pairs(TRACKED_BLIPS) do
        ApplyIconToBlip(blip, blip.data)
    end
    if not silent then
        print("|cff00ff00[ExwindTools]|r " .. L["MDT 已刷新。"])
    end
end

-- =========================================================
-- 二、默认配置与配置访问 | Defaults and Configuration Access
-- =========================================================
local function ApplyCustomSettings()
    wipe(EX_DB.customNPCIcons)
    local rawMap = EX_DB.customIconsText or ""
    for line in rawMap:gmatch("[^\r\n]+") do
        local n, s = line:match("(%d+)%s*=%s*(%d+)")
        if n and s then
            EX_DB.customNPCIcons[tonumber(n)] = tonumber(s)
        end
    end

    wipe(EX_DB.blacklistNPCs)
    local rawBlack = EX_DB.blacklistText or ""
    for id in rawBlack:gmatch("(%d+)") do
        EX_DB.blacklistNPCs[tonumber(id)] = true
    end

    ApplyIconsToKnownBlips(false)
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local function GetRawTableColumns(kind)
    return {
        { title = kind == "custom" and L["NPC ID = 法术 ID"] or L["NPC ID"] },
        { title = L["操作"] },
    }
end

local function ReleaseRawTableControl(control)
    if not control then return end
    if EXUI.RestoreSettingsListControl then EXUI:RestoreSettingsListControl(control) end
    local factory = _G.ExwindFactory
    if factory and control._isCompositeHost then
        factory:ReleaseCompositeHost(control)
    elseif factory then
        factory:ReleaseGridWidget(control)
    else
        control:Hide()
        control:SetParent(nil)
    end
end

local function TokenizeLines(raw)
    raw = type(raw) == "string" and raw or tostring(raw or "")
    if raw == "" then return {} end
    local lines, position = {}, 1
    while position <= #raw do
        local startPos = raw:find("[\r\n]", position)
        if not startPos then
            lines[#lines + 1] = { text = raw:sub(position), separator = "" }
            position = #raw + 1
        else
            local endPos = startPos
            if raw:sub(startPos, startPos) == "\r" and raw:sub(startPos + 1, startPos + 1) == "\n" then
                endPos = startPos + 1
            end
            lines[#lines + 1] = {
                text = raw:sub(position, startPos - 1),
                separator = raw:sub(startPos, endPos),
            }
            position = endPos + 1
            if position > #raw then
                lines[#lines + 1] = { text = "", separator = "" }
            end
        end
    end
    return lines
end

local function JoinLines(lines)
    local parts = {}
    for _, line in ipairs(lines) do
        parts[#parts + 1] = line.text
        parts[#parts + 1] = line.separator
    end
    return table.concat(parts)
end

local function TokenizeBlacklist(raw)
    raw = type(raw) == "string" and raw or tostring(raw or "")
    local tokens, position = {}, 1
    while position <= #raw do
        local digit = raw:sub(position, position):match("%d") ~= nil
        local endPos = position + 1
        while endPos <= #raw and (raw:sub(endPos, endPos):match("%d") ~= nil) == digit do
            endPos = endPos + 1
        end
        tokens[#tokens + 1] = { text = raw:sub(position, endPos - 1), digit = digit }
        position = endPos
    end
    return tokens
end

local function JoinTokens(tokens)
    local parts = {}
    for _, token in ipairs(tokens) do parts[#parts + 1] = token.text end
    return table.concat(parts)
end

local function GetRawTableRecords(kind)
    if kind == "custom" then
        local lines = TokenizeLines(EX_DB.customIconsText)
        local records = {}
        for index, line in ipairs(lines) do
            records[#records + 1] = {
                index = index,
                text = line.text,
                editable = true,
            }
        end
        return records
    end

    local tokens = TokenizeBlacklist(EX_DB.blacklistText)
    local records = {}
    for tokenIndex, token in ipairs(tokens) do
        local visibleText = token.text:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
        records[#records + 1] = {
            tokenIndex = tokenIndex,
            text = token.text,
            displayText = visibleText,
            editable = token.digit,
        }
    end
    return records
end

local function ReplaceRawRecord(kind, record, text)
    if kind == "custom" then
        local lines = TokenizeLines(EX_DB.customIconsText)
        if not lines[record.index] then return false end
        lines[record.index].text = text
        EX_DB.customIconsText = JoinLines(lines)
    else
        if type(text) ~= "string" or not text:match("^%d+$") then return false end
        local tokens = TokenizeBlacklist(EX_DB.blacklistText)
        local token = tokens[record.tokenIndex]
        if not token or not token.digit then return false end
        token.text = text
        EX_DB.blacklistText = JoinTokens(tokens)
    end
    return true
end

local function DeleteRawRecord(kind, record)
    if kind == "custom" then
        local lines = TokenizeLines(EX_DB.customIconsText)
        local line = lines[record.index]
        if not line then return false end
        if line.separator ~= "" then
            table.remove(lines, record.index)
        elseif record.index > 1 then
            lines[record.index - 1].separator = ""
            table.remove(lines, record.index)
        else
            table.remove(lines, record.index)
        end
        EX_DB.customIconsText = JoinLines(lines)
    else
        local tokens = TokenizeBlacklist(EX_DB.blacklistText)
        local token = tokens[record.tokenIndex]
        if not token or not token.digit then return false end
        table.remove(tokens, record.tokenIndex)
        EX_DB.blacklistText = JoinTokens(tokens)
    end
    return true
end

local function AppendRawRecord(kind, text)
    if kind == "custom" then
        local raw = type(EX_DB.customIconsText) == "string" and EX_DB.customIconsText
            or tostring(EX_DB.customIconsText or "")
        local separator = "\n"
        if raw == "" or raw:match("[\r\n]$") then separator = "" end
        EX_DB.customIconsText = raw .. separator .. text
    else
        if type(text) ~= "string" or not text:match("^%d+$") then return false end
        local raw = type(EX_DB.blacklistText) == "string" and EX_DB.blacklistText
            or tostring(EX_DB.blacklistText or "")
        EX_DB.blacklistText = raw .. (raw == "" and "" or ",") .. text
    end
    return true
end

local function ClearRawTableRows(controls)
    for index = #controls.rows, 1, -1 do
        local row = controls.rows[index]
        if row.inputIsEditBox then
            -- OnEditFocusLost 槽位上有 Core 的焦点画器，走 ClearControlScript
            -- 清槽位时一并丢掉安装记录，下一次借用才会重装画器。
            EXUI:ClearControlScript(row.input, "OnEditFocusLost")
            row.input:SetScript("OnEnterPressed", nil)
        end
        ReleaseRawTableControl(row.action)
        ReleaseRawTableControl(row.input)
        controls.rows[index] = nil
    end
end

local RebuildRawTable

local function QueueRawTableRebuild(host, ctx, kind)
    if host._exRawTableRefreshQueued then return end
    local lease = host._exRawTableLease
    host._exRawTableRefreshQueued = true
    C_Timer.After(0, function()
        if host._exRawTableLease ~= lease or not host._exRawTableControls then return end
        host._exRawTableRefreshQueued = nil
        RebuildRawTable(host, ctx, kind)
        ctx:RequestReflow()
    end)
end

RebuildRawTable = function(host, ctx, kind)
    local controls = host._exRawTableControls
    if not controls then return end
    ctx:ReleaseTablePresentation()
    ClearRawTableRows(controls)
    local records = GetRawTableRecords(kind)

    local addRow = {
        input = EXUI:CreateEditBox(host, "", 1, 28, nil, {
            placeholder = kind == "custom" and L["NPCID = SpellID"] or L["NPC ID"],
        }),
        inputIsEditBox = true,
    }
    addRow.action = EXUI:CreateButton(host, 1, 28, L["添加"], function()
        if AppendRawRecord(kind, addRow.input:GetText()) then
            RebuildRawTable(host, ctx, kind)
            ctx:RequestReflow()
        end
    end, { variant = "primary", compact = true })
    controls.rows[#controls.rows + 1] = addRow

    for _, record in ipairs(records) do
        local target = record
        local row = {}
        if record.editable then
            row.input = EXUI:CreateEditBox(host, record.text, 1, 28, nil, {})
            row.inputIsEditBox = true
            local committedText = record.text
            local function Commit(self)
                local text = self:GetText()
                if text == committedText then return end
                if ReplaceRawRecord(kind, target, text) then
                    committedText = text
                    QueueRawTableRebuild(host, ctx, kind)
                else
                    self:SetText(committedText)
                end
            end
            -- 焦点画器就在这个槽位上，用 HookScript 把提交逻辑叠加上去。
            row.input:HookScript("OnEditFocusLost", function(self)
                if self._exSkipLostCommit then self._exSkipLostCommit = nil return end
                Commit(self)
            end)
            row.input:SetScript("OnEnterPressed", function(self)
                Commit(self)
                self._exSkipLostCommit = true
                self:ClearFocus()
            end)
            row.action = EXUI:CreateButton(host, 1, 28, L["删除"], function()
                if DeleteRawRecord(kind, target) then
                    RebuildRawTable(host, ctx, kind)
                    ctx:RequestReflow()
                end
            end, { variant = "danger", compact = true })
        else
            row.input = EXUI:CreateDescription(host, record.displayText, 1)
            row.action = EXUI:CreateDescription(host, "—", 1)
        end
        controls.rows[#controls.rows + 1] = row
    end

    local presentedRecords = {}
    for index = 2, #controls.rows do
        local row = controls.rows[index]
        presentedRecords[#presentedRecords + 1] = {
            cells = {
                { widget = row.input, type = row.inputIsEditBox and "input" or "text" },
                { widget = row.action, type = row.inputIsEditBox and "button" or "text" },
            },
        }
    end
    ctx:SetTableControls({
        add = {
            cells = {
                { widget = addRow.input, type = "input" },
                { widget = addRow.action, type = "button" },
            },
        },
        records = presentedRecords,
    })
end

-- =========================================================
-- 三、GUI 声明 | GUI Declarations
-- =========================================================
local Grid = ExwindTools.Grid
if not Grid then error("MDTIconHook requires ExwindGrid", 2) end

local function RegisterRawTableControls(rendererKey, kind)
    Grid:RegisterTableControls(rendererKey, {
        mount = function(host, ctx)
            host._exRawTableLease = {}
            host._exRawTableControls = {
                rows = {},
            }
            RebuildRawTable(host, ctx, kind)
        end,
        update = function(host, ctx)
            RebuildRawTable(host, ctx, kind)
        end,
        release = function(host)
            local controls = host._exRawTableControls
            if controls then ClearRawTableRows(controls) end
            host._exRawTableControls = nil
            host._exRawTableRefreshQueued = nil
            host._exRawTableLease = nil
        end,
    })
end

RegisterRawTableControls(CUSTOM_ICONS_RENDERER, "custom")
RegisterRawTableControls(BLACKLIST_RENDERER, "blacklist")

local function EX_RegisterLayout()
    -- [声明迁移边界：设置页] 两组原始控件由唯一 shared table 承载，其余控件改为 typed sections。
    -- key/type、apply.func 与 NPC/法术解析顺序均属业务合同，禁止修改。
    local layout = {
        version = 1,
        sections = {
            {
                kind = "settings", id = "common", title = L["通用设置"],
                items = {
                    { key = "enabled", type = "switch", label = L["开启功能"] },
                },
            },
            {
                kind = "table", id = "custom_icons", title = L["自定义图标"],
                key = "customIconsRecords", controlFactory = CUSTOM_ICONS_RENDERER,
                columns = GetRawTableColumns("custom"), supportsAdd = true,
            },
            {
                kind = "table", id = "blacklist", title = L["黑名单 NPC"],
                key = "blacklistRecords", controlFactory = BLACKLIST_RENDERER,
                columns = GetRawTableColumns("blacklist"), supportsAdd = true,
            },
            {
                kind = "settings", id = "apply", title = L["保存并刷新"],
                items = {
                    { key = "apply", type = "button", label = L["保存并刷新"], func = ApplyCustomSettings },
                },
            },
        },
    }

    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
end
EX_RegisterLayout()

local function InitializeMDTVisuals()
    if MDT_HOOK_INSTALLED then return true end

    local Mixin = _G.MDTDungeonEnemyMixin
    if not Mixin or not Mixin.SetUp then
        return false
    end

    MDT_HOOK_INSTALLED = true

    hooksecurefunc(Mixin, "SetUp", function(self, data)
        -- 第一次画 blip 时主框体一定已经存在；作为面板挂载的兜底触发点。
        AttachToMDTFrame()
        if not data then return end

        TRACKED_BLIPS[self] = true
        -- 功能1：头像替换为法术图标
        ApplyIconToBlip(self, data)
    end)

    return true
end

-- =========================================================
-- 四、显示、预览与编辑接入 | Display, Preview and Edit Integration
-- =========================================================
-- [卡片迁移边界：外部UI] 下列视觉、位置、显隐、hook 与按钮 helper 均服务 MDT 自有窗口，不属于 ExwindTools 设置页；宿主锚点、按钮顺序、点击业务及显隐合同禁止修改。
local function UpdateMDTButtonsVisual()
    local toggleBtn = _G.ExMDT_Btn_ToggleIcon
    if toggleBtn then
        toggleBtn._exButtonVariant = EX_DB.useSpellIconMode and "primary" or "secondary"
        EXUI:ApplyControlAppearance(toggleBtn)
    end
end

local function ApplyLoadedUIBackdrop(frame)
    if not frame or not ExwindTools:HasLoadedUIReplacement() then return false end
    local backdrop = frame._exLoadedUIBackdrop
    if not backdrop then
        backdrop = frame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(frame)
        frame._exLoadedUIBackdrop = backdrop
    end
    backdrop:SetColorTexture(0, 0, 0, 0.8)
    return true
end

local function UpdateMDTActionPanelPosition()
    local panel = _G.ExMDT_ActionPanel
    local mainFrame = _G.MDTFrame
    if not panel or not mainFrame then return end

    panel:ClearAllPoints()
    panel:SetPoint("TOP", mainFrame, "BOTTOM", 0, -10)
end

local function UpdateMDTActionPanelVisibility()
    local panel = _G.ExMDT_ActionPanel
    local mainFrame = _G.MDTFrame
    if not panel then return end

    if EX_DB.enabled and mainFrame and mainFrame:IsShown() then
        UpdateMDTActionPanelPosition()
        panel:Show()
    else
        panel:Hide()
    end
end

local function HookMDTMainFrame()
    if MDT_PANEL_FRAME_HOOKED then return end

    local mainFrame = _G.MDTFrame
    if not mainFrame then return end

    MDT_PANEL_FRAME_HOOKED = true
    mainFrame:HookScript("OnShow", function()
        C_Timer.After(0.05, UpdateMDTActionPanelVisibility)
    end)
    mainFrame:HookScript("OnHide", function()
        UpdateMDTActionPanelVisibility()
    end)
    mainFrame:HookScript("OnSizeChanged", function()
        UpdateMDTActionPanelPosition()
    end)
end

local function CreateMDTTextButton(name, parent, width, labelText, onClick)
    local btn = EXUI:CreateButton(parent, width, 22, labelText, function(self, button)
        if button == "RightButton" and ExwindTools.OpenConfig then
            ExwindTools:OpenConfig(EXWIND_MODULE_KEY)
        else
            onClick(self, button)
        end
    end, { compact = true })
    _G[name] = btn
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(labelText .. " (" .. L["右键打开设置"] .. ")", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return btn
end

-- [卡片迁移边界：自定义渲染] 下列按钮注入 MDT 自有窗口，不属于 ExwindTools 设置页；外部锚点、点击业务和显隐 hook 禁止修改。
-- 面板本身不依赖 MDT 主框体，可在 MDT UI 挂载时直接建好；
-- 锚点与显隐 hook 由 AttachToMDTFrame 在 MDTFrame 出现后接上。
local function CreateMDTButtons()
    if MDT_BUTTONS_CREATED then return true end

    if not _G.ExMDT_ActionPanel then
        local panel
        local hasLoadedUIReplacement = ExwindTools:HasLoadedUIReplacement()

        if hasLoadedUIReplacement then
            panel = CreateFrame("Frame", "ExMDT_ActionPanel", UIParent)
            panel:SetSize(160, 58)

            local title = panel:CreateFontString(nil, "OVERLAY")
            title:SetFont(ExwindTools.MAIN_FONT, 15, "OUTLINE")
            title:SetPoint("TOP", 0, -8)
            title:SetTextColor(1, 0.82, 0)
            panel.TitleText = title

            local close = EXUI:CreatePicButton(panel, 24, 24,
                "Interface\\Buttons\\UI-Panel-CloseButton-Up",
                "Interface\\Buttons\\UI-Panel-CloseButton-Down",
                "Interface\\Buttons\\UI-Panel-CloseButton-Highlight",
                nil, true)
            close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
            panel.CloseButton = close

            ApplyLoadedUIBackdrop(panel)
        else
            panel = CreateFrame("Frame", "ExMDT_ActionPanel", UIParent, "DefaultPanelTemplate")
            panel:SetSize(160, 58)
        end

        panel:SetFrameStrata("MEDIUM")
        panel:SetToplevel(true)
        if panel.TitleText then
            panel.TitleText:SetText(L["MDT 快捷操作"])
        end

        if panel.CloseButton then
            panel.CloseButton:HookScript("OnClick", function()
                panel:Hide()
            end)
        end

        if _G.UISpecialFrames then
            local exists = false
            for _, frameName in ipairs(_G.UISpecialFrames) do
                if frameName == "ExMDT_ActionPanel" then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(_G.UISpecialFrames, "ExMDT_ActionPanel")
            end
        end

        local content = CreateFrame("Frame", nil, panel)
        content:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28)
        content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
        panel.Content = content

        local btnWidth = 132
        local btnHeight = 22

        local btnToggle = CreateMDTTextButton("ExMDT_Btn_ToggleIcon", content, btnWidth, L["替换图标"], function()
            EX_DB.useSpellIconMode = not EX_DB.useSpellIconMode
            ApplyIconsToKnownBlips(true)
            UpdateMDTButtonsVisual()
        end)
        btnToggle:SetSize(btnWidth, btnHeight)
        btnToggle:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

        panel:Hide()
    end

    MDT_BUTTONS_CREATED = true
    UpdateMDTButtonsVisual()
    return true
end

-- =========================================================
-- 七、初始化与启动 | Initialization and Startup
-- =========================================================
local MDT_FRAME_WATCH_TICKER
local MDT_UI_INITIALIZER_REGISTERED = false

-- MDTFrame 只在玩家第一次打开 MDT 时由 InitializeMainFrame 创建（MainFrame.lua:1001），
-- 公开面没有创建回调。这里用有限次 ticker 等它出现（10 秒后自行结束，不留常驻轮询），
-- 另有 blip SetUp hook 作为兜底触发点。
AttachToMDTFrame = function()
    if MDT_PANEL_ATTACHED then return true end
    if not _G.MDTFrame then return false end

    MDT_PANEL_ATTACHED = true
    if MDT_FRAME_WATCH_TICKER then
        MDT_FRAME_WATCH_TICKER:Cancel()
        MDT_FRAME_WATCH_TICKER = nil
    end

    HookMDTMainFrame()
    UpdateMDTActionPanelPosition()
    UpdateMDTButtonsVisual()
    UpdateMDTActionPanelVisibility()
    return true
end

local function StartMDTFrameWatch()
    if MDT_FRAME_WATCH_TICKER or MDT_PANEL_ATTACHED then return end
    MDT_FRAME_WATCH_TICKER = C_Timer.NewTicker(0.25, function()
        if AttachToMDTFrame() then return end
    end, 40)
end

local function OnMDTUIReady()
    InitializeMDTVisuals()
    CreateMDTButtons()
    if not AttachToMDTFrame() then
        StartMDTFrameWatch()
    end
end

local function RegisterWithMDT()
    if MDT_UI_INITIALIZER_REGISTERED then return true end
    local api = _G.MythicDungeonToolsAPI
    if type(api) ~= "table" or type(api.RegisterUIInitializer) ~= "function" then return false end

    MDT_UI_INITIALIZER_REGISTERED = true
    -- 回调在 MythicDungeonTools_UI 的 ADDON_LOADED 里触发（Core/Bootstrap.lua:94-108、
    -- Core/Lifecycle.lua:62），早于主框体与 blip 框体池创建，mixin hook 必须在这一步装上。
    api:RegisterUIInitializer(function()
        OnMDTUIReady()
    end)
    return true
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
if not RegisterWithMDT() then
    ExwindTools:RegisterEvent("ADDON_LOADED", EXWIND_MODULE_KEY .. "_MDT", function(_, addonName)
        if addonName == "MythicDungeonTools" then
            RegisterWithMDT()
        end
    end)
end

-- =========================================================
-- 六、事件订阅与配置刷新 | Events and Configuration Refresh
-- =========================================================
local function RefreshActiveSurfaces()
    UpdateMDTButtonsVisual()
    UpdateMDTActionPanelVisibility()
    ApplyIconsToKnownBlips(true)
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

ExwindTools:ReportReady(EXWIND_MODULE_KEY)
