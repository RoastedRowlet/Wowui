-- =============================================================
-- [[ 对话ID显示 / 自动对话 ]]
-- { Key = "ExTools.GossipID", Name = "对话ID显示", Desc = "显示对话 ID，并支持加入自动对话列表。", Category = 1 },
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExTools.GossipID"

local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local C_GossipInfo = _G.C_GossipInfo
local GameTooltip = _G.GameTooltip
local DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME
local hooksecurefunc = _G.hooksecurefunc
local strtrim = _G.strtrim or function(text)
    text = tostring(text or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local EX_DEFAULTS = {
    enabled = true,
    showOptionID = false,
    showQuestID = true,
    autoSelectEnabled = true,
    showActionButton = true,
    buttonPosition = "RIGHT",
    manualAddID = "",
    manualAddName = "",
    presetStates = {},
    customAutoOptions = {},
}

local EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)

local optionHookInstalled = false
local activeQuestHookInstalled = false
local availableQuestHookInstalled = false
local autoSelectScheduled = false
local lastHandledSignature = nil

local PRESET_DEFINITIONS = {
    {
        key = "mythic_academy_buff",
        title = function()
            return L["[大秘境] 自动对话学院(AA)BUFF"]
        end,
        ids = { 107065, 107081, 107082, 107083, 107088 },
    },

}

local PRESET_BY_ID = {}

for _, definition in ipairs(PRESET_DEFINITIONS) do
    for _, optionID in ipairs(definition.ids) do
        PRESET_BY_ID[optionID] = definition
    end
end

local INSTANCE_NAME_BY_ID = {
    [2813] = L["密谋小径"],
    [2859] = L["夺目谷"],
    [2923] = L["虚空之痕竞技场"],
    [2825] = L["纳洛拉克的洞穴"],
    [2521] = L["红玉新生法池"],
    [1762] = L["诸王之眠"],
    [1877] = L["塞塔里斯神庙"],
    [2993] = L["毒牙祭坛"],
}

local function GetCurrentInstanceID()
    local id = ExwindTools.State and tonumber(ExwindTools.State.InstanceID)
    return id and id > 0 and id or nil
end

local function GetInstanceNameByID(instanceID)
    instanceID = tonumber(instanceID)
    if not instanceID then
        return nil
    end
    return INSTANCE_NAME_BY_ID[instanceID]
end

local function PrintMessage(text)
    local message = "|cff00b3ffExwind|r " .. tostring(text or "")
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    else
        print(message)
    end
end

local function IsRuntimeEnabled()
    return ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) and EX_DB.enabled
end

local function EnsurePresetStatesTable()
    if type(EX_DB.presetStates) ~= "table" then
        EX_DB.presetStates = {}
    end

    for _, definition in ipairs(PRESET_DEFINITIONS) do
        local state = EX_DB.presetStates[definition.key]
        if type(state) ~= "table" then
            EX_DB.presetStates[definition.key] = { enabled = true }
        elseif state.enabled == nil then
            state.enabled = true
        end
    end

    return EX_DB.presetStates
end

local function EnsureCustomAutoOptionsTable()
    if type(EX_DB.customAutoOptions) ~= "table" then
        EX_DB.customAutoOptions = {}
    end
    return EX_DB.customAutoOptions
end

local function NormalizeEntry(rawEntry)
    if type(rawEntry) == "table" then
        return {
            enabled = (rawEntry.enabled ~= false),
            name = tostring(rawEntry.name or ""),
            instanceID = tonumber(rawEntry.instanceID) or nil,
        }
    end

    return {
        enabled = rawEntry and true or false,
        name = "",
        instanceID = nil,
    }
end

local function NormalizeSavedData()
    EnsurePresetStatesTable()

    local normalizedCustom = {}
    local sources = {
        EX_DB.customAutoOptions,
        EX_DB.autoOptions,
    }

    for _, source in ipairs(sources) do
        if type(source) == "table" then
            for rawID, rawEntry in pairs(source) do
                local optionID = tonumber(rawID)
                if optionID and optionID > 0 and not PRESET_BY_ID[optionID] then
                    normalizedCustom[optionID] = NormalizeEntry(rawEntry)
                end
            end
        end
    end

    EX_DB.customAutoOptions = normalizedCustom
    EX_DB.autoOptions = nil
end

NormalizeSavedData()

local function GetStableOptionID(optionInfo)
    local optionID = optionInfo and tonumber(optionInfo.gossipOptionID)
    if optionID and optionID > 0 then
        return optionID
    end
    return nil
end

local function GetVisibleOptionID(optionInfo)
    local optionID = GetStableOptionID(optionInfo)
    if optionID then
        return optionID
    end

    optionID = optionInfo and tonumber(optionInfo.orderIndex)
    if optionID and optionID > 0 then
        return optionID
    end

    return nil
end

local function GetPresetTitle(definition)
    if not definition then
        return ""
    end
    if type(definition.title) == "function" then
        return tostring(definition.title() or "")
    end
    return tostring(definition.title or "")
end

local function GetPresetIDsText(definition)
    local ids = {}
    for _, optionID in ipairs(definition.ids or {}) do
        ids[#ids + 1] = tostring(optionID)
    end
    return "(" .. table.concat(ids, ", ") .. ")"
end

local function GetPresetState(definition)
    local states = EnsurePresetStatesTable()
    return states[definition.key]
end

local function GetPresetEntry(optionID)
    local definition = PRESET_BY_ID[tonumber(optionID or 0)]
    if not definition then
        return nil
    end

    local state = GetPresetState(definition)
    return {
        id = tonumber(optionID),
        enabled = state and state.enabled ~= false,
        name = GetPresetTitle(definition),
        source = "preset",
        presetKey = definition.key,
        preset = definition,
    }
end

local function GetCustomEntry(optionID)
    optionID = tonumber(optionID)
    if not optionID or optionID <= 0 then
        return nil
    end

    local entry = EnsureCustomAutoOptionsTable()[optionID]
    if type(entry) ~= "table" then
        return nil
    end

    return {
        id = optionID,
        enabled = entry.enabled ~= false,
        name = tostring(entry.name or ""),
        instanceID = tonumber(entry.instanceID) or nil,
        source = "custom",
    }
end

local function GetEffectiveEntry(optionID)
    return GetPresetEntry(optionID) or GetCustomEntry(optionID)
end

local function GetSortedCustomOptionIDs()
    local ids = {}
    for rawID, entry in pairs(EnsureCustomAutoOptionsTable()) do
        local optionID = tonumber(rawID)
        if optionID and optionID > 0 and type(entry) == "table" and not PRESET_BY_ID[optionID] then
            ids[#ids + 1] = optionID
        end
    end
    table.sort(ids)
    return ids
end

local function RefreshCurrentGossipFrame()
    local gossipFrame = _G.GossipFrame
    if gossipFrame and gossipFrame:IsShown() and gossipFrame.Update then
        gossipFrame:Update()
    end
end

local function RefreshCurrentGossipFrameLater()
    local function Runner()
        RefreshCurrentGossipFrame()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Runner)
    else
        Runner()
    end
end

local function RefreshConfigUI()
    if ExwindTools.UI and ExwindTools.UI.RefreshContent then
        ExwindTools.UI:RefreshContent()
    end
end

local function HasIDTag(text)
    return type(text) == "string" and text:find("%[ID:%d+%]")
end

local function AppendID(self, id)
    if not IsRuntimeEnabled() or not id or id <= 0 then
        return
    end

    local text = self:GetText()
    if not text or text == "" or HasIDTag(text) then
        return
    end

    self:SetText(string.format("%s |cff888888[ID:%d]|r", text, id))
    if self.Resize then
        self:Resize()
    end
end

local function ResetOptionTextAnchors(self)
    local textRegion = self and self.GetFontString and self:GetFontString()
    if not textRegion then
        return
    end

    textRegion:ClearAllPoints()
    textRegion:SetPoint("LEFT", self, "LEFT", 20, 0)
    textRegion:SetPoint("RIGHT", self, "RIGHT", -5, 0)
end

local function SaveCustomAutoOption(optionID, optionName, recordInstanceID)
    optionID = tonumber(optionID)
    if not optionID or optionID <= 0 then
        return nil, "invalid"
    end

    local preset = PRESET_BY_ID[optionID]
    if preset then
        EnsureCustomAutoOptionsTable()[optionID] = nil
        return GetPresetEntry(optionID), "preset"
    end

    local customOptions = EnsureCustomAutoOptionsTable()
    local entry = customOptions[optionID]
    if type(entry) ~= "table" then
        entry = { enabled = true, name = "" }
        customOptions[optionID] = entry
    end

    entry.enabled = true
    if optionName and optionName ~= "" then
        entry.name = tostring(optionName)
    end
    if recordInstanceID then
        entry.instanceID = GetCurrentInstanceID()
    end

    return GetCustomEntry(optionID), "custom"
end

local function RemoveCustomIfCoveredByPreset()
    local customOptions = EnsureCustomAutoOptionsTable()

    for rawID in pairs(customOptions) do
        local optionID = tonumber(rawID)
        if optionID and PRESET_BY_ID[optionID] then
            customOptions[rawID] = nil
        end
    end
end

local function RebuildLayoutAndRefreshUI(refreshGossip)
    RemoveCustomIfCoveredByPreset()

    if ExwindTools.RegisterModuleLayout then
        local layout = {
            { key = "header", type = "header", x = 1, y = 4, w = 200, h = 6, label = L["对话ID显示 / 自动对话"], labelSize = 25 },
            { key = "enabled", type = "checkbox", x = 1, y = 12, w = 80, h = 6, label = L["启用功能"] },
            { key = "showQuestID", type = "checkbox", x = 1, y = 18, w = 80, h = 6, label = L["显示任务 ID"] },
            { key = "showOptionID", type = "checkbox", x = 1, y = 24, w = 80, h = 6, label = L["显示对话选项 ID"] },
            { key = "autoSelectEnabled", type = "checkbox", x = 1, y = 30, w = 80, h = 6, label = L["启用自动对话"] },
            { key = "showActionButton", type = "checkbox", x = 1, y = 40, w = 80, h = 8, label = L["显示加入按钮"] },
            { key = "buttonPosition", type = "dropdown", x = 84, y = 41, w = 64, h = 8, label = L["按钮位置"], items = { { L["前面"], "LEFT" }, { L["后面"], "RIGHT" } } },
            { key = "sub_manual", type = "subheader", x = 1, y = 53, w = 192, h = 4, label = L["手动添加"] },
            { key = "manualAddID", type = "input", x = 15, y = 60, w = 46, h = 6, label = L["对话 ID"], labelPos = "left", labelSize = 16 },
            { key = "manualAddName", type = "input", x = 76, y = 60, w = 46, h = 6, label = L["名称"], labelPos = "left", labelSize = 16 },
            { key = "btn_add_auto_option", type = "button", x = 135, y = 60, w = 46, h = 6, label = L["添加"] },
        }

        local y = 70

        layout[#layout + 1] = { key = "sub_preset", type = "subheader", x = 1, y = y, w = 194, h = 7, label = L
        ["预设自动对话"] }
        y = y + 10

        for _, definition in ipairs(PRESET_DEFINITIONS) do
            layout[#layout + 1] = {
                key = "preset_enabled_" .. definition.key,
                parentKey = "presetStates." .. definition.key,
                subKey = "enabled",
                type = "checkbox",
                x = 1,
                y = y,
                w = 20,
                h = 6,
                label = "",
            }
            layout[#layout + 1] = {
                key = "preset_name_" .. definition.key,
                type = "description",
                x = 21,
                y = y,
                w = 96,
                h = 6,
                label = GetPresetTitle(definition),
            }
            layout[#layout + 1] = {
                key = "preset_ids_" .. definition.key,
                type = "description",
                x = 119,
                y = y,
                w = 80,
                h = 6,
                label = GetPresetIDsText(definition),
            }
            y = y + 10
        end

        layout[#layout + 1] = {
            key = "desc_preset_note",
            type = "description",
            x = 8,
            y = y,
            w = 192,
            h = 8,
            label = L["若某个自定义 ID 后续进入预设，将自动移除自定义项并以预设为准。"],
        }
        y = y + 16

        layout[#layout + 1] = {
            key = "sub_custom",
            type = "subheader",
            x = 8,
            y = y,
            w = 192,
            h = 4,
            label = L
                ["自定义自动对话"]
        }
        y = y + 8

        local ids = GetSortedCustomOptionIDs()
        if #ids == 0 then
            layout[#layout + 1] = {
                key = "empty_custom",
                type = "description",
                x = 8,
                y = y,
                w = 192,
                h = 8,
                label = L["当前没有自定义自动对话项。点击对话行图标，或在上方手动添加。"],
            }
        else
            for _, optionID in ipairs(ids) do
                local entryPath = "customAutoOptions." .. optionID
                local entry = GetCustomEntry(optionID)
                local instanceName = entry and GetInstanceNameByID(entry.instanceID)
                local idLabel = instanceName
                    and string.format("(%d) [%s]", optionID, instanceName)
                    or string.format("(%d)", optionID)
                layout[#layout + 1] = {
                    key = "custom_enabled_" .. optionID,
                    parentKey = entryPath,
                    subKey = "enabled",
                    type = "checkbox",
                    x = 8,
                    y = y,
                    w = 16,
                    h = 8,
                    label = "",
                }
                layout[#layout + 1] = {
                    key = "custom_name_" .. optionID,
                    parentKey = entryPath,
                    subKey = "name",
                    type = "input",
                    x = 20,
                    y = y,
                    w = 88,
                    h = 8,
                    label = "",
                    labelPos = "left",
                    labelSize = 16,
                }
                layout[#layout + 1] = {
                    key = "custom_id_" .. optionID,
                    type = "description",
                    x = 112,
                    y = y,
                    w = 64,
                    h = 8,
                    label = idLabel,
                }
                layout[#layout + 1] = {
                    key = "btn_delete_custom_" .. optionID,
                    type = "button",
                    x = 176,
                    y = y,
                    w = 24,
                    h = 8,
                    label = L["删除"],
                }
                y = y + 12
            end
        end

        ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, layout)
    end

    RefreshConfigUI()
    if refreshGossip then
        RefreshCurrentGossipFrameLater()
    end
end

RebuildLayoutAndRefreshUI(false)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then
        return
    end

    if info.key == "btn_add_auto_option" then
        local rawID = strtrim(EX_DB.manualAddID or "")
        local rawName = strtrim(EX_DB.manualAddName or "")
        local optionID = tonumber(rawID)

        if not optionID or optionID <= 0 then
            PrintMessage(L["请输入有效的对话 ID。"])
            return
        end

        local entry, source = SaveCustomAutoOption(optionID, rawName)
        EX_DB.manualAddID = ""
        EX_DB.manualAddName = ""

        if source == "preset" then
            local preset = entry and entry.preset
            local presetState = preset and GetPresetState(preset)
            local wasEnabled = presetState and presetState.enabled ~= false
            if presetState then
                presetState.enabled = true
            end
            RebuildLayoutAndRefreshUI(true)
            if wasEnabled then
                PrintMessage(string.format(L["该对话 ID 已在预设范围：%s"], GetPresetTitle(preset)))
            else
                PrintMessage(string.format(L["已启用预设自动对话：%s"], GetPresetTitle(preset)))
            end
        elseif source == "custom" then
            RebuildLayoutAndRefreshUI(true)
            PrintMessage(string.format(L["已加入自定义自动对话：%d"], optionID))
        end
        return
    end

    local deleteID = tostring(info.key):match("^btn_delete_custom_(%d+)$")
    if deleteID then
        deleteID = tonumber(deleteID)
        EnsureCustomAutoOptionsTable()[deleteID] = nil
        RebuildLayoutAndRefreshUI(true)
        PrintMessage(string.format(L["已移除自定义自动对话：%d"], deleteID))
    end
end)

local function RefreshActiveSurfaces()
    RemoveCustomIfCoveredByPreset()
    RefreshCurrentGossipFrameLater()
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

local function BuildOptionSignature(options)
    if type(options) ~= "table" or #options == 0 then
        return nil
    end

    local parts = {}
    for index, optionInfo in ipairs(options) do
        local orderIndex = optionInfo and tonumber(optionInfo.orderIndex) or index
        local optionID = GetStableOptionID(optionInfo) or 0
        local optionName = optionInfo and tostring(optionInfo.name or "") or ""
        parts[#parts + 1] = string.format("%d:%d:%s", orderIndex or index, optionID, optionName)
    end

    return table.concat(parts, "|")
end

local function TryAutoSelectCurrentOption()
    if not IsRuntimeEnabled() or not EX_DB.autoSelectEnabled then
        return
    end
    if not C_GossipInfo or not C_GossipInfo.GetOptions then
        return
    end

    RemoveCustomIfCoveredByPreset()

    local options = C_GossipInfo.GetOptions()
    if type(options) ~= "table" or #options == 0 then
        return
    end

    local signature = BuildOptionSignature(options)
    if not signature or signature == lastHandledSignature then
        return
    end

    for _, optionInfo in ipairs(options) do
        local optionID = GetStableOptionID(optionInfo)
        local entry = GetEffectiveEntry(optionID)
        if entry and entry.enabled then
            lastHandledSignature = signature

            if C_GossipInfo.SelectOption and optionID then
                C_GossipInfo.SelectOption(optionID)
            elseif C_GossipInfo.SelectOptionByIndex and optionInfo.orderIndex then
                C_GossipInfo.SelectOptionByIndex(optionInfo.orderIndex)
            end
            return
        end
    end
end

local function ScheduleAutoSelect()
    if autoSelectScheduled then
        return
    end

    autoSelectScheduled = true
    local function Runner()
        autoSelectScheduled = false
        TryAutoSelectCurrentOption()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Runner)
    else
        Runner()
    end
end

local function UpdateActionButtonTooltip(self)
    if not self.optionID or not GameTooltip then
        return
    end

    local entry = GetEffectiveEntry(self.optionID)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["加入自动对话"], 1, 0.82, 0.18)
    GameTooltip:AddLine(string.format(L["ID: %d"], self.optionID), 0.85, 0.85, 0.85)
    if self.optionName and self.optionName ~= "" then
        GameTooltip:AddLine(self.optionName, 1, 1, 1, true)
    end
    if entry then
        if entry.source == "preset" then
            GameTooltip:AddLine(L["来源：预设"], 0.35, 1, 0.35, true)
        else
            GameTooltip:AddLine(L["来源：自定义"], 0.35, 0.82, 1, true)
        end

        if entry.enabled then
            GameTooltip:AddLine(L["当前已启用自动选择。"], 0.35, 1, 0.35, true)
        else
            GameTooltip:AddLine(L["当前已保存，但处于禁用状态。"], 1, 0.82, 0.18, true)
        end
    else
        GameTooltip:AddLine(L["点击后会把当前选项加入自定义自动对话列表。"], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function EnsureOptionActionButton(owner)
    if owner.ExwindAutoButton then
        return owner.ExwindAutoButton
    end

    local button = CreateFrame("Button", nil, owner)
    button:SetSize(18, 18)
    button:SetFrameLevel(owner:GetFrameLevel() + 5)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetAtlas("talents-icon-learnableplus", true)

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.08)

    button:SetScript("OnClick", function(self)
        if not self.optionID then
            return
        end

        local entry, source = SaveCustomAutoOption(self.optionID, self.optionName, true)

        if source == "preset" then
            local preset = entry and entry.preset
            local presetState = preset and GetPresetState(preset)
            local wasEnabled = presetState and presetState.enabled ~= false
            if presetState then
                presetState.enabled = true
            end
            RebuildLayoutAndRefreshUI(true)
            if wasEnabled then
                PrintMessage(string.format(L["该对话 ID 已在预设范围：%s"], GetPresetTitle(preset)))
            else
                PrintMessage(string.format(L["已启用预设自动对话：%s"], GetPresetTitle(preset)))
            end
        elseif source == "custom" then
            RebuildLayoutAndRefreshUI(true)
            PrintMessage(string.format(L["已加入自定义自动对话：%d"], self.optionID))
        end
    end)
    button:SetScript("OnEnter", function(self)
        UpdateActionButtonTooltip(self)
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    owner.ExwindAutoButton = button
    return button
end

local function UpdateActionButtonAppearance(button, entry)
    if not button or not button.icon then
        return
    end

    if not entry then
        button.icon:SetDesaturated(false)
        button.icon:SetVertexColor(1, 1, 1, 1)
    elseif entry.enabled then
        button.icon:SetDesaturated(false)
        button.icon:SetVertexColor(0.35, 1, 0.35, 1)
    else
        button.icon:SetDesaturated(false)
        button.icon:SetVertexColor(1, 0.82, 0.18, 1)
    end
end

local function UpdateOptionActionButton(self, optionInfo)
    local textRegion = self and self.GetFontString and self:GetFontString()
    if not textRegion then
        return
    end

    local actionButton = self.ExwindAutoButton
    local optionID = GetStableOptionID(optionInfo)

    if not IsRuntimeEnabled() or not EX_DB.showActionButton or not optionID then
        if actionButton then
            actionButton:Hide()
        end
        ResetOptionTextAnchors(self)
        if self.Resize then
            self:Resize()
        end
        return
    end

    actionButton = EnsureOptionActionButton(self)
    local entry = GetEffectiveEntry(optionID)

    actionButton.optionID = optionID
    actionButton.optionName = tostring(optionInfo and optionInfo.name or "")
    actionButton:ClearAllPoints()

    textRegion:ClearAllPoints()
    if EX_DB.buttonPosition == "LEFT" then
        actionButton:SetPoint("LEFT", self, "LEFT", 20, 0)
        textRegion:SetPoint("LEFT", actionButton, "RIGHT", 6, 0)
        textRegion:SetPoint("RIGHT", self, "RIGHT", -5, 0)
    else
        actionButton:SetPoint("RIGHT", self, "RIGHT", -5, 0)
        textRegion:SetPoint("LEFT", self, "LEFT", 20, 0)
        textRegion:SetPoint("RIGHT", actionButton, "LEFT", -6, 0)
    end

    UpdateActionButtonAppearance(actionButton, entry)
    actionButton:Show()

    if self.Resize then
        self:Resize()
    end
end

local function InstallOptionHook()
    if optionHookInstalled or type(_G.GossipOptionButtonMixin) ~= "table" then
        return
    end

    hooksecurefunc(_G.GossipOptionButtonMixin, "Setup", function(self, optionInfo)
        if IsRuntimeEnabled() and EX_DB.showOptionID then
            AppendID(self, GetVisibleOptionID(optionInfo))
        end

        UpdateOptionActionButton(self, optionInfo)
        ScheduleAutoSelect()
    end)

    optionHookInstalled = true
end

local function InstallAvailableQuestHook()
    if availableQuestHookInstalled or type(_G.GossipAvailableQuestButtonMixin) ~= "table" then
        return
    end

    hooksecurefunc(_G.GossipAvailableQuestButtonMixin, "Setup", function(self, questInfo)
        if EX_DB.showQuestID then
            AppendID(self, questInfo and questInfo.questID)
        end
    end)

    availableQuestHookInstalled = true
end

local function InstallActiveQuestHook()
    if activeQuestHookInstalled or type(_G.GossipActiveQuestButtonMixin) ~= "table" then
        return
    end

    hooksecurefunc(_G.GossipActiveQuestButtonMixin, "Setup", function(self, questInfo)
        if EX_DB.showQuestID then
            AppendID(self, questInfo and questInfo.questID)
        end
    end)

    activeQuestHookInstalled = true
end

local function AreAllHooksInstalled()
    return optionHookInstalled and activeQuestHookInstalled and availableQuestHookInstalled
end

local function TryInstallHooks()
    InstallOptionHook()
    InstallAvailableQuestHook()
    InstallActiveQuestHook()
    return AreAllHooksInstalled()
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("GOSSIP_SHOW")
driver:RegisterEvent("GOSSIP_CLOSED")
driver:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_UIPanels_Game" then
        return
    end

    local installedNow = TryInstallHooks()
    if installedNow and (event == "ADDON_LOADED" or event == "PLAYER_LOGIN") then
        driver:UnregisterEvent("ADDON_LOADED")
        driver:UnregisterEvent("PLAYER_LOGIN")
    end

    if event == "GOSSIP_SHOW" then
        lastHandledSignature = nil
        RefreshCurrentGossipFrameLater()
        ScheduleAutoSelect()
    elseif event == "GOSSIP_CLOSED" then
        lastHandledSignature = nil
    end
end)

if TryInstallHooks() then
    driver:UnregisterEvent("ADDON_LOADED")
    driver:UnregisterEvent("PLAYER_LOGIN")
end

ExwindTools:ReportReady(EXWIND_MODULE_KEY)
