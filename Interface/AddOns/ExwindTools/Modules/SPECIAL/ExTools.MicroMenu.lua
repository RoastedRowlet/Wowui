-- =============================================================
-- [[ 微型选单 ]]
-- { Key = "ExTools.MicroMenu", Name = "微型选单", Desc = "顶端微型选单：中间显示时间，左右各有可配置的面板快捷图标。", Category = 1 },
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
local L = (ExwindTools and ExwindTools.L) or setmetatable({}, { __index = function(_, key) return key end })

local EXWIND_MODULE_KEY = "ExTools.MicroMenu"
local MAX_SLOTS = 10
local CUSTOM_ICON_MAX = 111
local EX_DB
local GetActionLabel
local NormalizeThemeId
local EnsureAnchorController
local ApplyMicroMenuLivePresentation
-- Layout 在 renderer 建立前已注册；因此 Grid 保存的必须是稳定的转发函数，
-- 而不能保存稍后才赋值的 nil callback。
local function ApplyMicroMenuLivePreview(value, context)
    if type(ApplyMicroMenuLivePresentation) == "function" then
        return ApplyMicroMenuLivePresentation(value, context)
    end
    return false
end

local function IsCombatRestricted()
    local state = ExwindTools and ExwindTools.State
    if state and state.InCombat == true then
        return true
    end
    return InCombatLockdown and InCombatLockdown() or false
end

-- =============================================================
-- 动作定义
-- =============================================================
local ACTION_LIST = {
    { id = "none", label = "（无）", atlas = nil },
    {
        id = "character",
        label = "角色",
        atlas = "UI-HUD-MicroMenu-Portrait-Shadow",
        action = function()
            ToggleCharacter("PaperDollFrame")
        end
    },
    {
        id = "professions",
        label = "专业技能",
        atlas = "UI-HUD-MicroMenu-Professions-Up",
        action = function()
            ToggleProfessionsBook()
        end
    },
    {
        id = "spellbook",
        label = "法术书/天赋",
        atlas = "UI-HUD-MicroMenu-SpecTalents-Up",
        action = function()
            TogglePlayerSpellsFrame()
        end
    },
    {
        id = "achievement",
        label = "成就",
        atlas = "UI-HUD-MicroMenu-Achievements-Up",
        action = function()
            ToggleAchievementFrame()
        end
    },
    { id = "questlog", label = "任务日志", atlas = "UI-HUD-MicroMenu-Questlog-Up", action = function() ToggleQuestLog() end },
    {
        id = "housing",
        label = "家园",
        atlas = "UI-HUD-MicroMenu-Housing-Up",
        action = function()
            HousingFramesUtil.ToggleHousingDashboard()
        end
    },
    { id = "guild", label = "公会/社区", atlas = "UI-HUD-MicroMenu-GuildCommunities-Up", action = function() ToggleGuildFrame() end },
    { id = "lfg", label = "寻求组队", atlas = "UI-HUD-MicroMenu-Groupfinder-Up", action = function() ToggleLFDParentFrame() end },
    {
        id = "collections",
        label = "收藏",
        atlas = "UI-HUD-MicroMenu-Collections-Up",
        action = function()
            ToggleCollectionsJournal()
        end
    },
    { id = "ej", label = "冒险指南", atlas = "UI-HUD-MicroMenu-AdventureGuide-Up", action = function() ToggleEncounterJournal() end },
    {
        id = "store",
        label = "商城",
        atlas = "UI-HUD-MicroMenu-Shop-Up",
        action = function()
            if ToggleStoreUI then
                ToggleStoreUI("StoreMicroButton")
            end
        end
    },
    {
        id = "mainmenu",
        label = "主菜单",
        atlas = "UI-HUD-MicroMenu-GameMenu-Up",
        action = function()
            if IsCombatRestricted() then
                return
            end
            ToggleGameMenu()
        end
    },
    {
        id = "cooldownmanager",
        label = "冷却管理器",
        atlas = "icon_cooldownmanager",
        action = function()
            if not CooldownViewerSettings and UIParentLoadAddOn then
                UIParentLoadAddOn("Blizzard_CooldownViewer")
            end
            if CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
                CooldownViewerSettings:TogglePanel()
            end
        end
    },
    { id = "custom", label = "自定义命令", atlas = "UI-HUD-MicroMenu-GameMenu-Up", action = nil },
}

local ACTION_BY_ID = {}
local ACTION_LABEL_TO_ID = {}
for _, actionDef in ipairs(ACTION_LIST) do
    ACTION_BY_ID[actionDef.id] = actionDef
    if actionDef.atlas then
        ACTION_LABEL_TO_ID[CreateAtlasMarkup(actionDef.atlas, 16, 16) .. " " .. actionDef.label] = actionDef.id
    end
    ACTION_LABEL_TO_ID[actionDef.label] = actionDef.id
    ACTION_LABEL_TO_ID[actionDef.id] = actionDef.id
end

local function BuildActionDropdownItems()
    local items = {}
    for _, actionDef in ipairs(ACTION_LIST) do
        local text = actionDef.label
        if actionDef.atlas then
            text = CreateAtlasMarkup(actionDef.atlas, 16, 16) .. " " .. actionDef.label
        end
        items[#items + 1] = { text, actionDef.id }
    end
    return items
end

ExwindTools.GetMicroMenuActionItems = BuildActionDropdownItems

-- =============================================================
-- 图标主题
-- =============================================================
local BLIZZARD_ICON_IDS = {
    "character", "professions", "spellbook", "achievement",
    "questlog", "housing", "guild", "lfg",
    "collections", "ej", "store", "mainmenu",
    "cooldownmanager", "custom",
}

local ADDON_PATH = "Interface\\AddOns\\ExwindTools\\Textures\\Icons\\"
local ICON_THEMES = {
    {
        id = "blizzard",
        name = "暴雪原版",
        type = "blizzard",
    },
    {
        id = "custom",
        name = "自定义图库",
        type = "custom",
        path = ADDON_PATH .. "custom\\",
        fallbackPath = ADDON_PATH .. "cyberpunk\\",
    },
}

local THEME_BY_ID = {}
local THEME_NAME_TO_ID = {}
for _, theme in ipairs(ICON_THEMES) do
    THEME_BY_ID[theme.id] = theme
    THEME_NAME_TO_ID[theme.name] = theme.id
    THEME_NAME_TO_ID[theme.id] = theme.id
end
THEME_NAME_TO_ID["cyberpunk"] = "custom"

local function ResolveThemeForStoredIcon(themeId, iconId)
    return THEME_BY_ID[NormalizeThemeId(themeId)] or THEME_BY_ID.blizzard
end

local IconTextureProbe = nil

local function GetIconTextureProbe()
    if IconTextureProbe then
        return IconTextureProbe
    end

    local probeFrame = CreateFrame("Frame", nil, UIParent)
    probeFrame:Hide()
    IconTextureProbe = probeFrame:CreateTexture(nil, "ARTWORK")
    return IconTextureProbe
end

local function CanLoadCustomTexture(path)
    if type(path) ~= "string" or path == "" then
        return false
    end

    local probe = GetIconTextureProbe()
    probe:SetTexture(nil)
    local ok = probe:SetTexture(path)
    probe:SetTexture(nil)
    return ok == true
end

local function ResolveCustomTexturePath(theme, iconId)
    if not theme or theme.type ~= "custom" or not iconId or iconId == "" then
        return nil
    end

    local primaryPath = theme.path .. iconId .. ".tga"
    if CanLoadCustomTexture(primaryPath) then
        return primaryPath
    end

    if type(theme.fallbackPath) == "string" and theme.fallbackPath ~= "" then
        local fallbackPath = theme.fallbackPath .. iconId .. ".tga"
        if CanLoadCustomTexture(fallbackPath) then
            return fallbackPath
        end
    end

    return primaryPath
end

local function BuildIconPickerChoices()
    local choices = {}

    for _, iconId in ipairs(BLIZZARD_ICON_IDS) do
        local actionDef = ACTION_BY_ID[iconId]
        if actionDef and actionDef.atlas then
            choices[#choices + 1] = {
                themeId = "blizzard",
                iconId = iconId,
                label = GetActionLabel(iconId),
                themeName = THEME_BY_ID.blizzard.name,
            }
        end
    end

    for _, theme in ipairs(ICON_THEMES) do
        if theme.type == "custom" then
            for i = 1, CUSTOM_ICON_MAX do
                local iconId = tostring(i)
                local texturePath = ResolveCustomTexturePath(theme, iconId)
                if texturePath and CanLoadCustomTexture(texturePath) then
                    choices[#choices + 1] = {
                        themeId = theme.id,
                        iconId = iconId,
                        label = "图标 " .. iconId,
                        themeName = theme.name,
                    }
                end
            end
        end
    end

    return choices
end

local function BuildThemeDropdownItems()
    local items = {}
    for _, theme in ipairs(ICON_THEMES) do
        items[#items + 1] = { theme.name, theme.id }
    end
    return items
end

ExwindTools.GetMicroMenuThemeItems = BuildThemeDropdownItems

local DEFAULT_LEFT_ACTIONS = {
    "character", "questlog", "achievement", "lfg", "guild",
    "none", "none", "none", "none", "none",
}

local DEFAULT_RIGHT_ACTIONS = {
    "spellbook", "professions", "collections", "ej", "housing",
    "none", "none", "none", "none", "none",
}

local function CreateDefaultSlot(primaryAction)
    return {
        icon = "",
        tooltip = "",
        leftClick = {
            action = primaryAction or "none",
            cmd = "",
        },
        rightClick = {
            action = "none",
            cmd = "",
        },
    }
end

local function CreateDefaultSlotList(defaultActions)
    local slots = {}
    for i = 1, MAX_SLOTS do
        slots[i] = CreateDefaultSlot(defaultActions[i] or "none")
    end
    return slots
end

local EX_DEFAULTS = {
    schemaVersion = 3,
    enabled = true,
    iconStyle = { width = 28, height = 28, showIcon = true, showBorder = false, borderTexture = "EX_Default", borderSize = 0, borderPadding = 0.6, borderColorR = 0, borderColorG = 0, borderColorB = 0, borderColorA = 1, reverse = false, x = 0, y = 0 },
    barScale = 1.0,
    showBackground = true,
    bgAlpha = 0.6,
    timeFormat = "24小时制",
    showSeconds = false,
    timeFont = { font = "默认", size = 0, r = 1, g = 1, b = 1, a = 1, outline = "OUTLINE", shadow = false, shadowX = 1, shadowY = -1, x = 0, y = 0 },

    -- 微型选单是一套显示：中间时间为唯一根点，左右图标只相对它排列。
    anchorX = 0,
    anchorY = -22,
    attachToCustom = false,
    customAttachTarget = "",

    iconTheme = "blizzard",

    leftCount = 5,
    rightCount = 5,

    selectedSlotSide = "left",
    selectedSlotIndex = 1,

    slots = {
        left = CreateDefaultSlotList(DEFAULT_LEFT_ACTIONS),
        right = CreateDefaultSlotList(DEFAULT_RIGHT_ACTIONS),
    },
}

local function PickMicroMenuAnchor()
    return EnsureAnchorController():StartFramePicker()
end

local MICRO_MENU_ANCHOR_OPTS = {
    bindRoot = true,
    offsetXKey = "anchorX",
    offsetYKey = "anchorY",
    defaultOffsetX = EX_DEFAULTS.anchorX,
    defaultOffsetY = EX_DEFAULTS.anchorY,
    attachEnabledKey = "attachToCustom",
    attachTargetKey = "customAttachTarget",
    onPickFrame = PickMicroMenuAnchor,
}

-- Grid/EXUI 的 Slider live 阶段已经先写入唯一 ModuleDB；这里仅公开模块的
-- 三宿主窄投影入口。数量类 Slider 会改变 item 集合，故只在松手 commit 后
-- 完整重排，不能滥用 live 回调 Acquire/Release 项目。
local MICRO_MENU_FONT_LIVE = {
    size = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    x = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    y = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    shadowX = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    shadowY = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
}

local MICRO_MENU_ICON_LIVE = {
    width = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    height = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    alpha = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    rotation = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    cropLeft = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    cropRight = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    cropTop = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    cropBottom = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    borderSize = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    borderPadding = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    ["cooldown.swipeAlpha"] = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
    ["cooldown.edgeAlpha"] = function(value, context) return ApplyMicroMenuLivePreview(value, context) end,
}

local function BuildSlotPath(side, index)
    return "slots." .. side .. "." .. index
end

local function BuildSelectedSlotTitle(side, index)
    return (side == "right" and L["右"] or L["左"]) .. index
end

local function BuildSlotEditorItems(selectedSide, selectedIndex)
    local slotPath = BuildSlotPath(selectedSide or "left", selectedIndex or 1)
    local slot
    if EX_DB and type(EX_DB.slots) == "table" and type(EX_DB.slots[selectedSide or "left"]) == "table" then
        slot = EX_DB.slots[selectedSide or "left"][selectedIndex or 1]
    end

    local leftAction = type(slot) == "table" and type(slot.leftClick) == "table" and slot.leftClick.action or "none"
    local rightAction = type(slot) == "table" and type(slot.rightClick) == "table" and slot.rightClick.action or "none"
    local leftIsCustom = leftAction == "custom"
    local rightIsCustom = rightAction == "custom"

    local children = {
        {
            key = "left_action",
            parentKey = slotPath,
            subKey = "leftClick.action",
            type = "dropdown",
            x = 1,
            y = 252,
            w = leftIsCustom and 96 or 200,
            h = 8,
            label = "左键点击",
            items = "func:ExwindTools.GetMicroMenuActionItems"
        },
        {
            key = "right_action",
            parentKey = slotPath,
            subKey = "rightClick.action",
            type = "dropdown",
            x = 1,
            y = 268,
            w = rightIsCustom and 96 or 200,
            h = 8,
            label = "右键点击",
            items = "func:ExwindTools.GetMicroMenuActionItems"
        },
    }

    if leftIsCustom then
        children[#children + 1] = {
            key = "left_cmd",
            parentKey = slotPath,
            subKey = "leftClick.cmd",
            type = "input",
            x = 108,
            y = 252,
            w = 96,
            h = 8,
            label = "左键命令",
            placeholder = "/target boss1"
        }
    end

    if rightIsCustom then
        children[#children + 1] = {
            key = "right_cmd",
            parentKey = slotPath,
            subKey = "rightClick.cmd",
            type = "input",
            x = 108,
            y = 268,
            w = 96,
            h = 8,
            label = "右键命令",
            placeholder = "/focus mouseover"
        }
    end

    return children
end

local function BuildLayout(selectedSide, selectedIndex)
    local currentSide = EX_DB and EX_DB.selectedSlotSide or selectedSide or "left"
    local currentIndex = EX_DB and EX_DB.selectedSlotIndex or selectedIndex or 1
    local selectedTitle = BuildSelectedSlotTitle(currentSide, currentIndex)
    local layout = {
        { key = "header", type = "header", x = 1, y = 4, w = 197, h = 8, label = "微型选单" },
        {
            key = "desc",
            type = "description",
            x = 1,
            y = 12,
            w = 200,
            h = 8,
            label = "中间时间是唯一根点；左右动作固定相对它排列，三宿主都只展示这一套选单。"
        },

        { key = "div_basic", type = "divider", x = 1, y = 24, w = 197, h = 4 },
        { key = "sh_basic", type = "subheader", x = 1, y = 28, w = 197, h = 4, label = "基础设置" },

        { key = "enabled", type = "checkbox", x = 1, y = 36, w = 32, h = 8, label = "启用" },
        { key = "showBackground", type = "checkbox", x = 40, y = 36, w = 40, h = 8, label = "显示背景" },

        { key = "barScale", type = "slider", x = 76, y = 48, w = 64, h = 8, label = "整体缩放", min = 0.5, max = 2.0, step = 0.05 },
        { key = "bgAlpha", type = "slider", x = 144, y = 48, w = 56, h = 8, label = "背景透明度", min = 0, max = 1, step = 0.05 },

        { key = "div_theme", type = "divider", x = 1, y = 60, w = 197, h = 4 },
        { key = "sh_theme", type = "subheader", x = 1, y = 64, w = 197, h = 4, label = "图标风格" },
        { key = "iconTheme", type = "dropdown", x = 1, y = 72, w = 64, h = 8, label = "整体风格", items = "func:ExwindTools.GetMicroMenuThemeItems" },
        { key = "leftCount", type = "slider", x = 76, y = 72, w = 56, h = 8, label = "左侧数量", min = 0, max = MAX_SLOTS, step = 1 },
        { key = "rightCount", type = "slider", x = 140, y = 72, w = 56, h = 8, label = "右侧数量", min = 0, max = MAX_SLOTS, step = 1 },

        { key = "div_time", type = "divider", x = 1, y = 84, w = 197, h = 4 },
        { key = "sh_time", type = "subheader", x = 1, y = 88, w = 197, h = 4, label = "时间文字" },
        { key = "timeFormat", type = "dropdown", x = 1, y = 96, w = 64, h = 8, label = "时间格式", items = "24小时制:24小时制,12小时制:12小时制" },
        { key = "showSeconds", type = "checkbox", x = 76, y = 96, w = 32, h = 8, label = "显示秒数" },

        { key = "div_pos", type = "divider", x = 1, y = 120, w = 197, h = 4 },
        { key = "anchorGroup", type = "anchorgroup", x = 1, y = 126, w = 200, h = 20, measure = true, label = L["锚点设置"], opts = MICRO_MENU_ANCHOR_OPTS },

        { key = "div_slot", type = "divider", x = 1, y = 150, w = 197, h = 4 },
        { key = "sh_slot", type = "subheader", x = 1, y = 154, w = 197, h = 4, label = "当前槽位：" .. selectedTitle },
        { key = "slot_desc", type = "description", x = 1, y = 162, w = 197, h = 8, label = "先选择左右分组与槽位编号，再编辑图标和左右键动作；上方预览只展示同一套选单。" },
        { key = "selectedSlotSide", type = "dropdown", x = 1, y = 174, w = 64, h = 8, label = "分组", items = "左侧:left,右侧:right" },
        { key = "selectedSlotIndex", type = "slider", x = 72, y = 174, w = 64, h = 8, label = "槽位编号", min = 1, max = MAX_SLOTS, step = 1 },
        { key = "btn_select_icon", type = "button", x = 144, y = 174, w = 56, h = 8, label = "选择图案" },
        { key = "timeFont", type = "fontgroup", x = 1, y = 288, w = 200, h = 50, label = "时间文字", labelSize = 20, opts = {} },
        { key = "iconStyle", type = "icongroup", x = 1, y = 364, w = 200, h = 50, label = "整体图标", labelSize = 20, opts = { enableOffset = false } },
    }

    for _, item in ipairs(BuildSlotEditorItems(currentSide, currentIndex)) do
        layout[#layout + 1] = item
    end

    return layout
end

local function EX_RegisterLayout(selectedSide, selectedIndex)
    ExwindTools:RegisterModuleLayout(EXWIND_MODULE_KEY, BuildLayout(selectedSide, selectedIndex))
end

EX_RegisterLayout("left", 1)

-- =============================================================
-- 载入检查
-- =============================================================
if not ExwindTools:IsModuleEnabled(EXWIND_MODULE_KEY) then return end

EX_DB = ExwindTools:GetModuleDB(EXWIND_MODULE_KEY, EX_DEFAULTS)
local function GetIconSize()
    if type(EX_DB.iconStyle) ~= "table" then
        EX_DB.iconStyle = EX_DEFAULTS.iconStyle
    end
    return math.max(16, tonumber(EX_DB.iconStyle.width) or 28),
        math.max(16, tonumber(EX_DB.iconStyle.height) or 28)
end
if type(EX_DB.timeFont) ~= "table" then
    EX_DB.timeFont = EX_DEFAULTS.timeFont
end

-- =============================================================
-- 工具函数
-- =============================================================
local function NormalizeActionId(value, fallback)
    local id = ACTION_LABEL_TO_ID[value or ""]
    if ACTION_BY_ID[id] then
        return id
    end
    if ACTION_BY_ID[value] then
        return value
    end
    return fallback or "none"
end

NormalizeThemeId = function(value)
    return THEME_NAME_TO_ID[value or ""] or "blizzard"
end

local function RunCustomCmd(cmd)
    if not cmd or cmd == "" then return end
    cmd = cmd:match("^%s*(.-)%s*$")
    if cmd == "" then return end
    local slash, args = cmd:match("^(/[^%s]+)%s*(.*)")
    if slash then
        slash = slash:upper()
        for key, handler in pairs(_G.SlashCmdList) do
            local i = 1
            while true do
                local registered = _G["SLASH_" .. key .. i]
                if not registered then break end
                if registered:upper() == slash then
                    handler(args or "")
                    return
                end
                i = i + 1
            end
        end
    end
    local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
    if editBox then
        editBox:SetText(cmd)
        ChatEdit_SendText(editBox, 0)
    end
end

local function NormalizeClickData(clickData, fallbackAction)
    if type(clickData) ~= "table" then
        clickData = {}
    end
    clickData.action = NormalizeActionId(clickData.action, fallbackAction or "none")
    clickData.cmd = type(clickData.cmd) == "string" and clickData.cmd or ""
    return clickData
end

local function NormalizeSlot(slot, fallbackAction)
    if type(slot) ~= "table" then
        slot = {}
    end

    slot.icon = type(slot.icon) == "string" and slot.icon or ""
    slot.tooltip = type(slot.tooltip) == "string" and slot.tooltip or ""
    slot.leftClick = NormalizeClickData(slot.leftClick, fallbackAction or "none")
    slot.rightClick = NormalizeClickData(slot.rightClick, "none")

    if slot.icon ~= "" then
        local themeId, iconId = slot.icon:match("^(.+):(.+)$")
        themeId = NormalizeThemeId(themeId)
        if THEME_BY_ID[themeId] and iconId and iconId ~= "" then
            slot.icon = ResolveThemeForStoredIcon(themeId, iconId).id .. ":" .. iconId
        else
            slot.icon = ""
        end
    end

    if slot.icon == "" then
        local actionId = slot.leftClick.action ~= "none" and slot.leftClick.action or slot.rightClick.action
        if actionId and actionId ~= "none" then
            local preferredThemeId = NormalizeThemeId(EX_DB and EX_DB.iconTheme or "blizzard")
            local resolvedTheme = ResolveThemeForStoredIcon(preferredThemeId, actionId)
            slot.icon = resolvedTheme.id .. ":" .. actionId
        end
    end

    return slot
end

local function EnsureSlotList(side)
    if type(EX_DB.slots) ~= "table" then
        EX_DB.slots = {}
    end
    if type(EX_DB.slots[side]) ~= "table" then
        EX_DB.slots[side] = {}
    end
    local fallbackList = side == "left" and DEFAULT_LEFT_ACTIONS or DEFAULT_RIGHT_ACTIONS
    for i = 1, MAX_SLOTS do
        EX_DB.slots[side][i] = NormalizeSlot(EX_DB.slots[side][i], fallbackList[i] or "none")
    end
end

local function GetSlot(side, index)
    EnsureSlotList(side)
    index = math.max(1, math.min(MAX_SLOTS, tonumber(index) or 1))
    return EX_DB.slots[side][index]
end

local function EnsureSelectedSlotVisible()
    local side = EX_DB.selectedSlotSide == "right" and "right" or "left"
    local index = math.max(1, math.min(MAX_SLOTS, tonumber(EX_DB.selectedSlotIndex) or 1))
    local changed = false

    local count = side == "left" and tonumber(EX_DB.leftCount) or tonumber(EX_DB.rightCount)
    count = math.max(0, math.min(MAX_SLOTS, count or 0))
    if count <= 0 then
        local otherSide = side == "left" and "right" or "left"
        local otherCount = otherSide == "left" and tonumber(EX_DB.leftCount) or tonumber(EX_DB.rightCount)
        otherCount = math.max(0, math.min(MAX_SLOTS, otherCount or 0))
        if otherCount > 0 then
            side = otherSide
            index = math.min(index, otherCount)
            changed = true
        else
            side = "left"
            index = 1
            changed = true
        end
    elseif index > count then
        index = count
        changed = true
    end

    if EX_DB.selectedSlotSide ~= side or EX_DB.selectedSlotIndex ~= index then
        EX_DB.selectedSlotSide = side
        EX_DB.selectedSlotIndex = index
        changed = true
    end
    return changed
end

local function NormalizeDatabase()
    EX_DB.schemaVersion = 3
    EX_DB.anchorX = tonumber(EX_DB.anchorX) or EX_DEFAULTS.anchorX
    EX_DB.anchorY = tonumber(EX_DB.anchorY) or EX_DEFAULTS.anchorY
    EX_DB.attachToCustom = EX_DB.attachToCustom == true
    EX_DB.customAttachTarget = type(EX_DB.customAttachTarget) == "string" and EX_DB.customAttachTarget or ""
    EX_DB.iconTheme = NormalizeThemeId(EX_DB.iconTheme)
    EX_DB.leftCount = math.max(0, math.min(MAX_SLOTS, tonumber(EX_DB.leftCount) or 5))
    EX_DB.rightCount = math.max(0, math.min(MAX_SLOTS, tonumber(EX_DB.rightCount) or 5))
    EnsureSlotList("left")
    EnsureSlotList("right")
    if EX_DB.timeFormat ~= "12小时制" then
        EX_DB.timeFormat = "24小时制"
    end
    EnsureSelectedSlotVisible()
end

NormalizeDatabase()
EX_RegisterLayout(EX_DB.selectedSlotSide, EX_DB.selectedSlotIndex)

local function GetSelectedSlotInfo()
    EnsureSelectedSlotVisible()
    local side = EX_DB.selectedSlotSide == "right" and "right" or "left"
    local index = math.max(1, math.min(MAX_SLOTS, tonumber(EX_DB.selectedSlotIndex) or 1))
    return side, index, GetSlot(side, index)
end

local function GetSlotBinding(slot, mouseButton)
    if mouseButton == "RightButton" then
        return NormalizeClickData(slot and slot.rightClick, "none")
    end
    return NormalizeClickData(slot and slot.leftClick, "none")
end

local function GetSlotIconInfo(side, index)
    local slot = GetSlot(side, index)
    local override = slot.icon
    if type(override) == "string" and override ~= "" then
        local themeId, iconId = override:match("^(.+):(.+)$")
        themeId = NormalizeThemeId(themeId)
        if THEME_BY_ID[themeId] and iconId then
            return ResolveThemeForStoredIcon(themeId, iconId).id, iconId
        end
    end
    return nil, nil
end

local function GetAtlasAspectRatio(atlas)
    if not atlas or not C_Texture or not C_Texture.GetAtlasInfo then
        return nil
    end

    local atlasInfo = C_Texture.GetAtlasInfo(atlas)
    if not atlasInfo or not atlasInfo.width or not atlasInfo.height or atlasInfo.width <= 0 or atlasInfo.height <= 0 then
        return nil
    end
    return atlasInfo.width / atlasInfo.height
end

local function ResolveThemeForIcon(themeId, iconId)
    return ResolveThemeForStoredIcon(themeId, iconId)
end

local function IsBlizzardCharacterIcon(themeId, iconId)
    local theme = ResolveThemeForIcon(themeId, iconId)
    return theme.type == "blizzard" and iconId == "character"
end

local function EnsureCharacterPortraitLayers(host)
    if not host then
        return
    end

    if not host.characterPortraitTex then
        local portrait = host:CreateTexture(nil, "ARTWORK", nil, 1)
        portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
        host.characterPortraitTex = portrait
    end

    if not host.characterPortraitMask then
        local mask = host:CreateMaskTexture(nil, "OVERLAY")
        mask:SetAtlas("UI-HUD-MicroMenu-Portrait-Mask", false)
        host.characterPortraitMask = mask
        host.characterPortraitTex:AddMaskTexture(mask)
    end
end

local function HideCharacterPortraitLayers(host)
    if not host then
        return
    end

    if host.characterPortraitTex then
        host.characterPortraitTex:Hide()
    end
    if host.characterPortraitMask then
        host.characterPortraitMask:Hide()
    end
end

local function LayoutIconTexture(tex, host, themeId, iconId, scale)
    tex:ClearAllPoints()

    local width, height = host:GetSize()
    if not width or not height or width <= 0 or height <= 0 then
        tex:SetAllPoints(host)
        return
    end

    scale = scale or 1
    local targetWidth = width * scale
    local targetHeight = height * scale
    local theme = ResolveThemeForIcon(themeId, iconId)
    if theme.type == "blizzard" then
        local actionDef = ACTION_BY_ID[iconId]
        local aspect = actionDef and GetAtlasAspectRatio(actionDef.atlas)
        if aspect and aspect > 0 then
            targetWidth = width * scale
            targetHeight = targetWidth / aspect
            if targetHeight > height * scale then
                targetHeight = height * scale
                targetWidth = targetHeight * aspect
            end
        end
    end

    tex:SetPoint("CENTER", host, "CENTER", 0, 0)
    tex:SetSize(targetWidth, targetHeight)
end

local function LayoutCharacterPortrait(host, scale)
    if not host or not host.normalTex then
        return
    end

    EnsureCharacterPortraitLayers(host)
    LayoutIconTexture(host.normalTex, host, "blizzard", "character", scale)

    local shadowWidth, shadowHeight = host.normalTex:GetSize()
    if not shadowWidth or not shadowHeight or shadowWidth <= 0 or shadowHeight <= 0 then
        shadowWidth, shadowHeight = host:GetSize()
    end

    local leftInset = shadowWidth * (7 / 32)
    local rightInset = shadowWidth * (7 / 32)
    local topInset = shadowHeight * (7 / 40)
    local bottomInset = shadowHeight * (7 / 40)

    host.characterPortraitTex:ClearAllPoints()
    host.characterPortraitTex:SetPoint("CENTER", host, "CENTER", 0, 0)
    host.characterPortraitTex:SetSize(math.max(1, shadowWidth - leftInset - rightInset),
        math.max(1, shadowHeight - topInset - bottomInset))

    host.characterPortraitMask:ClearAllPoints()
    host.characterPortraitMask:SetPoint("CENTER", host, "CENTER", 0, 0)
    host.characterPortraitMask:SetSize(shadowWidth * (35 / 32), shadowHeight * (65 / 40))
end

local function ApplyIconToTex(tex, themeId, iconId, scale)
    local host = tex and tex:GetParent()
    if host and IsBlizzardCharacterIcon(themeId, iconId) then
        tex:SetAtlas("UI-HUD-MicroMenu-Portrait-Shadow", false)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAlpha(1)
        tex:Show()

        EnsureCharacterPortraitLayers(host)
        SetPortraitTexture(host.characterPortraitTex, "player")
        host.characterPortraitTex:SetDesaturated(false)
        host.characterPortraitTex:SetAlpha(1)
        host.characterPortraitTex:Show()
        host.characterPortraitMask:Show()
        LayoutCharacterPortrait(host, scale)
        return
    end

    if host then
        HideCharacterPortraitLayers(host)
    end

    local theme = ResolveThemeForIcon(themeId, iconId)
    if theme.type == "blizzard" then
        local actionDef = ACTION_BY_ID[iconId]
        if actionDef and actionDef.atlas then
            tex:SetAtlas(actionDef.atlas, false)
        else
            tex:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        end
        tex:SetTexCoord(0, 1, 0, 1)
    else
        local texturePath = ResolveCustomTexturePath(theme, iconId)
        local ok = texturePath and tex:SetTexture(texturePath)
        if ok == true then
            tex:SetTexCoord(0, 1, 0, 1)
        else
            tex:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            tex:SetTexCoord(0, 1, 0, 1)
        end
    end
    tex:SetAlpha(1)
    tex:Show()
    LayoutIconTexture(tex, host, themeId, iconId, scale)
end

GetActionLabel = function(actionId)
    local actionDef = ACTION_BY_ID[actionId]
    return actionDef and actionDef.label or ACTION_BY_ID.none.label
end

local function GetTimeString()
    local d = date("*t")
    local hour, minute, sec = d.hour, d.min, d.sec
    local format24 = EX_DB.timeFormat ~= "12小时制"
    if format24 then
        if EX_DB.showSeconds then
            return string.format("%02d:%02d:%02d", hour, minute, sec)
        end
        return string.format("%02d:%02d", hour, minute)
    end

    local ampm = hour >= 12 and "PM" or "AM"
    local h12 = hour % 12
    if h12 == 0 then h12 = 12 end
    if EX_DB.showSeconds then
        return string.format("%d:%02d:%02d %s", h12, minute, sec, ampm)
    end
    return string.format("%d:%02d %s", h12, minute, ampm)
end

local function GetSlotSummaryLines(side, index)
    local slot = GetSlot(side, index)
    local leftBinding = GetSlotBinding(slot, "LeftButton")
    local rightBinding = GetSlotBinding(slot, "RightButton")
    return {
        "|cffffd100" .. L["左键"] .. "：|r" .. GetActionLabel(leftBinding.action),
        "|cff66c2ff" .. L["右键"] .. "：|r" .. GetActionLabel(rightBinding.action),
    }
end

local function RunSlotAction(side, index, mouseButton)
    local slot = GetSlot(side, index)
    local binding = GetSlotBinding(slot, mouseButton)
    local actionDef = ACTION_BY_ID[binding.action]
    if not actionDef or actionDef.id == "none" then
        return
    end
    if actionDef.id == "custom" then
        RunCustomCmd(binding.cmd)
        return
    end
    if actionDef.action then
        local ok, err = pcall(actionDef.action)
        if not ok then
            EXDebug("MicroMenu 按钮执行失败: %s", tostring(err))
        end
    end
end

local function RefreshLayoutPanel()
    EX_RegisterLayout(EX_DB.selectedSlotSide, EX_DB.selectedSlotIndex)
    if ExwindTools.UI and ExwindTools.UI.RefreshContentKeepModuleScroll then
        ExwindTools.UI:RefreshContentKeepModuleScroll()
    elseif ExwindTools.UI and ExwindTools.UI.RefreshContent then
        ExwindTools.UI:RefreshContent()
    end
end

-- =============================================================
-- 图标选择器
-- =============================================================
local IconPicker = {
    frame = nil,
    targetSide = nil,
    targetIndex = nil,
    scrollRow = 0,
}

local PICKER_CELL_SIZE = 44
local PICKER_PADDING = 12
local PICKER_COLUMN_COUNT = 10
local PICKER_VISIBLE_ROWS = 8

local function IconPicker_Close()
    if IconPicker.frame then
        IconPicker.frame:Hide()
    end
end

local function IconPicker_Refresh()
    local frame = IconPicker.frame
    if not frame or not IconPicker.targetSide or not IconPicker.targetIndex then
        IconPicker_Close()
        return
    end

    if frame.cells then
        for _, cell in ipairs(frame.cells) do
            cell:Hide()
            cell:SetParent(nil)
        end
    end
    frame.cells = {}

    local choices = BuildIconPickerChoices()
    local columnCount = math.min(PICKER_COLUMN_COUNT, math.max(1, #choices))
    local totalRows = math.max(1, math.ceil(#choices / columnCount))
    local maxScrollRow = math.max(0, totalRows - PICKER_VISIBLE_ROWS)
    IconPicker.scrollRow = math.max(0, math.min(IconPicker.scrollRow or 0, maxScrollRow))
    local startIndex = IconPicker.scrollRow * columnCount + 1
    local endIndex = math.min(#choices, startIndex + columnCount * PICKER_VISIBLE_ROWS - 1)
    local visibleCount = math.max(0, endIndex - startIndex + 1)
    local rowCount = math.max(1, math.ceil(visibleCount / columnCount))
    local totalW = PICKER_PADDING * 2 + columnCount * PICKER_CELL_SIZE + math.max(0, columnCount - 1) * 2
    local totalH = PICKER_PADDING * 2 + 24 + rowCount * PICKER_CELL_SIZE + math.max(0, rowCount - 1) * 2 + 8
    frame:SetSize(totalW, totalH)

    if not frame.titleText then
        frame.titleText = frame:CreateFontString(nil, "OVERLAY")
        frame.titleText:SetFont(ExwindTools.MAIN_FONT, 13, "OUTLINE")
        frame.titleText:SetTextColor(1, 1, 1, 1)
        frame.titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -PICKER_PADDING)
    end
    frame.titleText:SetText(L["选择图案"] ..
        "  [" .. BuildSelectedSlotTitle(IconPicker.targetSide, IconPicker.targetIndex) .. "]")

    if not frame.scrollText then
        frame.scrollText = frame:CreateFontString(nil, "OVERLAY")
        frame.scrollText:SetFont(ExwindTools.MAIN_FONT, 12, "OUTLINE")
        frame.scrollText:SetTextColor(0.95, 0.82, 0.25, 1)
        frame.scrollText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -PICKER_PADDING)
    end
    if maxScrollRow > 0 then
        frame.scrollText:SetText((IconPicker.scrollRow + 1) .. "/" .. (maxScrollRow + 1))
        frame.scrollText:Show()
    else
        frame.scrollText:SetText("")
        frame.scrollText:Hide()
    end

    local slot = GetSlot(IconPicker.targetSide, IconPicker.targetIndex)
    local currentIcon = slot.icon or ""
    for index = startIndex, endIndex do
        local choice = choices[index]
        local displayIndex = index - startIndex
        local row = math.floor(displayIndex / columnCount)
        local col = displayIndex % columnCount
        local cellX = PICKER_PADDING + col * (PICKER_CELL_SIZE + 2)
        local cellY = -(PICKER_PADDING + 24 + row * (PICKER_CELL_SIZE + 2))

        local cell = CreateFrame("Button", nil, frame)
        cell:SetSize(PICKER_CELL_SIZE, PICKER_CELL_SIZE)
        cell:SetPoint("TOPLEFT", frame, "TOPLEFT", cellX, cellY)
        cell:EnableMouse(true)
        cell:RegisterForClicks("AnyUp")

        local bg = cell:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        cell.bg = bg

        local choiceValue = choice.themeId .. ":" .. choice.iconId
        if currentIcon == choiceValue then
            local border = cell:CreateTexture(nil, "OVERLAY")
            border:SetAllPoints()
            border:SetColorTexture(1, 0.8, 0, 0.4)
        end

        cell.normalTex = cell:CreateTexture(nil, "ARTWORK")
        cell.normalTex:SetAllPoints()
        ApplyIconToTex(cell.normalTex, choice.themeId, choice.iconId)

        cell:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(0.3, 0.6, 1.0, 0.4)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(choice.themeName .. " · " .. choice.label, 1, 1, 1)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function(self)
            self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
            GameTooltip:Hide()
        end)
        cell:SetScript("OnClick", function()
            slot.icon = choiceValue
            ExwindTools:UpdateState(EXWIND_MODULE_KEY .. ".IconPickerApplied",
                { side = IconPicker.targetSide, index = IconPicker.targetIndex, ts = GetTime() })
            IconPicker_Close()
        end)

        frame.cells[#frame.cells + 1] = cell
    end

    if not frame.closeBtn then
        frame.closeBtn = CreateFrame("Button", nil, frame)
        frame.closeBtn:SetSize(22, 22)
        local closeTex = frame.closeBtn:CreateTexture(nil, "BACKGROUND")
        closeTex:SetAllPoints()
        closeTex:SetColorTexture(0.6, 0.1, 0.1, 0.9)
        local closeLbl = frame.closeBtn:CreateFontString(nil, "OVERLAY")
        closeLbl:SetFont(ExwindTools.MAIN_FONT, 13, "OUTLINE")
        closeLbl:SetTextColor(1, 1, 1, 1)
        closeLbl:SetText("✕")
        closeLbl:SetAllPoints()
        frame.closeBtn:SetScript("OnClick", IconPicker_Close)
        frame.closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    end

    frame:Show()
end

local function IconPicker_Open(side, index)
    if not IconPicker.frame then
        local frame = CreateFrame("Frame", "ExMicroMenuIconPicker", UIParent, "BackdropTemplate")
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(100)
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:EnableMouseWheel(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        frame:SetScript("OnMouseWheel", function(_, delta)
            local choices = BuildIconPickerChoices()
            local columnCount = math.min(PICKER_COLUMN_COUNT, math.max(1, #choices))
            local totalRows = math.max(1, math.ceil(#choices / columnCount))
            local maxScrollRow = math.max(0, totalRows - PICKER_VISIBLE_ROWS)
            if delta > 0 and (IconPicker.scrollRow or 0) > 0 then
                IconPicker.scrollRow = IconPicker.scrollRow - 1
                IconPicker_Refresh()
            elseif delta < 0 and (IconPicker.scrollRow or 0) < maxScrollRow then
                IconPicker.scrollRow = IconPicker.scrollRow + 1
                IconPicker_Refresh()
            end
        end)
        frame:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                IconPicker_Close()
            end
        end)
        frame:SetPropagateKeyboardInput(true)
        frame:Hide()
        IconPicker.frame = frame
    end

    IconPicker.targetSide = side
    IconPicker.targetIndex = index
    IconPicker.scrollRow = 0
    IconPicker.frame:ClearAllPoints()
    IconPicker.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    IconPicker_Refresh()
end

-- =============================================================
-- 唯一微型选单 Renderer
--
-- 这是一套以中心时间为根点的显示，不是三个可独立移动模块。图标与时间的
-- Body 尺寸不同，IconCollection 的正式 contract 禁止把它们塞进同一个
-- collection；故每个宿主只建立一个结构根，根下三段均使用标准
-- IconCollection。三段的位置由中心时间计算，唯一 AnchorController/DB/Edit
-- 注册只属于这个根。
-- =============================================================
local ACTION_BACKGROUND_ELEMENT_ID = "actionBackground"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local anchorController, anchorFrame
local runtimeSurface, worldSurface, panelSurface
local ticker
local SyncBlizzardMicroMenu
local PositionSurfaceHosts

local function Number(value, fallback)
    return tonumber(value) or fallback
end

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, Number(value, minimum)))
end

local function GetScale()
    return Clamp(EX_DB.barScale, 0.5, 2)
end

local function CopyTable(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do copy[key] = value end
    return copy
end

local function BuildIconStyle()
    local source = type(EX_DB.iconStyle) == "table" and EX_DB.iconStyle or EX_DEFAULTS.iconStyle
    local width, height = GetIconSize()
    local scale = GetScale()
    local style = CopyTable(source)
    style.width, style.height = math.max(1, width * scale), math.max(1, height * scale)
    style.borderSize = math.max(0, Number(source.borderSize, 0) * scale)
    style.borderPadding = Number(source.borderPadding, 0) * scale
    style.showIcon, style.enableCrop, style.showCooldown = true, false, false
    return style
end

local function BuildTimeStyle()
    local source = type(EX_DB.timeFont) == "table" and EX_DB.timeFont or EX_DEFAULTS.timeFont
    local style = CopyTable(source)
    local _, iconHeight = GetIconSize()
    local scale = GetScale()
    local configuredSize = Number(source.size, 0)
    style.size = math.max(10, (configuredSize > 0 and configuredSize or math.floor(iconHeight * 0.75)) * scale)
    style.x, style.y = Number(source.x, 0) * scale, Number(source.y, 0) * scale
    style.justifyH, style.justifyV, style.enabled = "CENTER", "MIDDLE", true
    return style
end

-- IconWidget 的正式输入：暴雪按钮走 ATLAS，角色按钮走 PORTRAIT；自定义
-- 图库走普通 texture path。三个宿主不会再创建 mask/Texture fallback。
local function BuildIconInput(side, index)
    local themeId, iconId = GetSlotIconInfo(side, index)
    if not iconId or iconId == "" or iconId == "none" then
        return { value = WHITE_TEXTURE }, true
    end
    local theme = ResolveThemeForIcon(themeId, iconId)
    if theme.type == "blizzard" then
        if iconId == "character" then return { mode = "PORTRAIT", unit = "player" }, false end
        local actionDef = ACTION_BY_ID[iconId]
        if actionDef and actionDef.atlas then
            return { mode = "ATLAS", value = actionDef.atlas }, false
        end
    else
        local path = ResolveCustomTexturePath(theme, iconId)
        if path then return { value = path }, false end
    end
    return { value = WHITE_TEXTURE }, true
end

local function ShowSlotTooltip(owner, side, index)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(BuildSelectedSlotTitle(side, index), 1, 1, 1)
    for _, line in ipairs(GetSlotSummaryLines(side, index)) do GameTooltip:AddLine(line, 1, 1, 1) end
    GameTooltip:Show()
end

local function BuildRuntimeAction(record)
    return {
        onEnter = function(item, owner)
            item.widget:SetAlpha(0.82)
            ShowSlotTooltip(owner, record.side, record.index)
        end,
        onLeave = function(item)
            item.widget:SetAlpha(1)
            if GameTooltip then GameTooltip:Hide() end
        end,
        onDown = function(item) item.widget:SetAlpha(0.65) end,
        onUp = function(item, owner, button)
            item.widget:SetAlpha(0.82)
            RunSlotAction(record.side, record.index, button)
        end,
        -- runtimeAction 的存在以 onClick 声明；业务在 OnMouseUp 执行，保留
        -- 槽位既有的 LeftButton / RightButton 双绑定。World/Panel 不建该层。
        onClick = function() end,
    }
end

local function BuildActionItemPresentation(record, presentation, itemIndex)
    local style = CopyTable(presentation.iconStyle)
    if record.empty then
        style.colorR, style.colorG, style.colorB, style.colorA = 0.3, 0.3, 0.3, 0.4
    end

    local halfWidth, halfHeight = presentation.bodyWidth * 0.5, presentation.bodyHeight * 0.5
    local borderPadding = presentation.borderPadding
    local declaredBounds = {
        left = -halfWidth - borderPadding,
        right = halfWidth + borderPadding,
        bottom = -halfHeight - borderPadding,
        top = halfHeight + borderPadding,
    }
    local regionElements
    if itemIndex == 1 then
        local backgroundLeft = -halfWidth - presentation.padding
        local backgroundRight = backgroundLeft + presentation.backgroundWidth
        local backgroundBottom, backgroundTop = -presentation.backgroundHeight * 0.5, presentation.backgroundHeight * 0.5
        if presentation.backgroundShown then
            declaredBounds.left = math.min(declaredBounds.left, backgroundLeft)
            declaredBounds.right = math.max(declaredBounds.right, backgroundRight)
            declaredBounds.bottom = math.min(declaredBounds.bottom, backgroundBottom)
            declaredBounds.top = math.max(declaredBounds.top, backgroundTop)
        end
        regionElements = {
            {
                id = ACTION_BACKGROUND_ELEMENT_ID,
                kind = "texture",
                stylePath = "background",
                style = presentation.backgroundStyle,
                anchor = {
                    relativeElement = "core.icon", point = "CENTER", relativePoint = "CENTER",
                    x = (backgroundLeft + backgroundRight) * 0.5, y = 0,
                },
                bounds = { width = presentation.backgroundWidth, height = presentation.backgroundHeight },
                content = {
                    texture = WHITE_TEXTURE,
                    color = { r = 0, g = 0, b = 0, a = presentation.backgroundAlpha },
                    shown = presentation.backgroundShown,
                },
                interaction = { elementID = "elements." .. ACTION_BACKGROUND_ELEMENT_ID, movable = false },
            },
        }
    end

    return {
        style = { icon = style },
        icon = record.icon,
        -- 一组动作按钮共用 BuildActionPresentation 声明的 Body；背景只是
        -- 首项额外子元素，不能改变该项在 IconCollection FLOW 中的尺寸。
        bodySize = presentation.bodySize,
        declaredBounds = declaredBounds,
        regionElements = regionElements,
        runtimeAction = presentation.sample and nil or BuildRuntimeAction(record),
        -- Panel 只提供右键 GUI 聚焦；runtime 的鼠标业务只由 runtimeAction 承担。
        interaction = presentation.sample and {
            slots = {
                -- slot ID 必须携带实际左右/编号。若都叫 core.icon，Core 只会把
                -- core.icon 交回 intent，模块无法知道用户右键的是哪一个槽位。
                [record.id] = { movable = false, guiTarget = "selectedSlotSide", tooltip = BuildSelectedSlotTitle(record.side, record.index) },
            },
        } or nil,
    }
end

local function BuildActionPresentation(side, sample)
    local count = math.floor(Clamp(side == "left" and EX_DB.leftCount or EX_DB.rightCount, 0, MAX_SLOTS))
    if sample and count == 0 then count = 1 end

    local iconStyle = BuildIconStyle()
    local spacing, padding = 4 * GetScale(), 8 * GetScale()
    local records = {}
    for index = 1, count do
        local icon, empty = BuildIconInput(side, index)
        records[#records + 1] = {
            id = side .. ".slot." .. index,
            side = side, index = index, icon = icon, empty = empty,
        }
    end

    local contentWidth = count > 0
        and (count * iconStyle.width + math.max(0, count - 1) * spacing)
        or iconStyle.width
    return {
        sample = sample == true,
        records = records,
        iconStyle = iconStyle,
        bodyWidth = iconStyle.width,
        bodyHeight = iconStyle.height,
        bodySize = { width = iconStyle.width, height = iconStyle.height },
        borderPadding = iconStyle.showBorder ~= false and math.max(0, Number(iconStyle.borderPadding, 0)) or 0,
        spacing = spacing,
        padding = padding,
        backgroundShown = EX_DB.showBackground == true,
        backgroundAlpha = Clamp(EX_DB.bgAlpha, 0, 1),
        backgroundWidth = contentWidth + padding * 2,
        backgroundHeight = iconStyle.height + padding * 2,
        backgroundStyle = { width = contentWidth + padding * 2, height = iconStyle.height + padding * 2 },
        layout = { mode = "SEMANTIC", direction = side == "left" and "LEFT" or "RIGHT", spacing = spacing, maxVisible = count },
    }
end

local function BuildClockText(sample)
    if not sample then return GetTimeString() end
    if EX_DB.timeFormat == "12小时制" then
        return EX_DB.showSeconds and "12:34:56 PM" or "12:34 PM"
    end
    return EX_DB.showSeconds and "12:34:56" or "12:34"
end

local function BuildClockPresentation(sample)
    local scale = GetScale()
    local _, iconHeight = GetIconSize()
    local width, height = 100 * scale, (iconHeight + 16) * scale
    local timeStyle = BuildTimeStyle()
    local offsetX, offsetY = Number(timeStyle.x, 0), Number(timeStyle.y, 0)
    local iconStyle = {
        width = width, height = height,
        showIcon = EX_DB.showBackground == true,
        alpha = 1,
        colorR = 0, colorG = 0, colorB = 0, colorA = Clamp(EX_DB.bgAlpha, 0, 1),
        enableCrop = false, showBorder = false, showCooldown = true,
        cooldown = { showSwipe = false, showEdge = false, showBling = false },
    }
    return {
        sample = sample == true,
        records = {
            {
                id = "center.clock",
                itemPresentation = {
                    style = { icon = iconStyle, text = { countdown = timeStyle } },
                    icon = { value = WHITE_TEXTURE },
                    cooldown = { text = BuildClockText(sample) },
                    bodySize = { width = width, height = height },
                    declaredBounds = {
                        left = -width * 0.5 + math.min(0, offsetX),
                        right = width * 0.5 + math.max(0, offsetX),
                        bottom = -height * 0.5 + math.min(0, offsetY),
                        top = height * 0.5 + math.max(0, offsetY),
                    },
                    interaction = sample and {
                        slots = { ["core.icon"] = { movable = false, guiTarget = "timeFont", tooltip = L["时间文字"] } },
                    } or nil,
                },
            },
        },
        layout = { mode = "SEMANTIC", direction = "RIGHT", spacing = 0, maxVisible = 1 },
    }
end

local function BuildPresentation(sample)
    return {
        sample = sample == true,
        left = BuildActionPresentation("left", sample),
        center = BuildClockPresentation(sample),
        right = BuildActionPresentation("right", sample),
    }
end

local function CreateRendererSession(host, interactionMode)
    return EXUI:CreateIconCollection(host, interactionMode, EXWIND_MODULE_KEY)
end

local function ApplyPresentation(collection, presentation)
    local items = {}
    for index, record in ipairs(presentation.records) do
        local item = collection:AcquireItem(record.id)
        local itemPresentation = record.itemPresentation or BuildActionItemPresentation(record, presentation, index)
        collection:ApplyItem(item, itemPresentation)
        items[#items + 1] = item
    end
    collection:SetItems(items, presentation.layout)
    return collection
end

local function RenderPanelPresentation(preview, presentation)
    if not preview then return end
    local entries = {}
    for index, record in ipairs(presentation.records) do
        entries[#entries + 1] = {
            itemID = record.id,
            presentation = record.itemPresentation or BuildActionItemPresentation(record, presentation, index),
        }
    end
    preview:Render(entries, presentation.layout)
end

EnsureAnchorController = function()
    if anchorController then return anchorController end
    anchorController = ExwindTools:CreateAnchorController({
        moduleKey = EXWIND_MODULE_KEY,
        frameName = "ExMicroMenuAnchor",
        title = L["微型选单"],
        getDB = function() return EX_DB end,
        offsetXKey = "anchorX",
        offsetYKey = "anchorY",
        defaultOffsetX = EX_DEFAULTS.anchorX,
        defaultOffsetY = EX_DEFAULTS.anchorY,
        attachEnabledKey = "attachToCustom",
        attachTargetKey = "customAttachTarget",
        syncWidgets = { "anchorX", "anchorY" },
        widgetRanges = {
            anchorX = { min = -1200, max = 1200, step = 1 },
            anchorY = { min = -1000, max = 1000, step = 1 },
        },
        anchorPoint = "CENTER",
        relativePoint = "TOP",
        initialWidth = 1,
        initialHeight = 1,
        clampedToScreen = true,
    })
    return anchorController
end

local function EnsureAnchor()
    if not anchorFrame then anchorFrame = EnsureAnchorController():Ensure() end
    anchorController:ApplyPosition()
    return anchorFrame
end

local function ReleaseCollection(collection)
    if collection then collection:Release() end
end

local function CreateSurface(parent, interactionMode, panelCallbacks)
    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(1, 1)
    root:SetPoint("CENTER", parent, "CENTER")
    root:EnableMouse(false)
    local hosts = {}
    for _, key in ipairs({ "left", "center", "right" }) do
        local host = CreateFrame("Frame", nil, root)
        host:SetSize(1, 1)
        host:SetPoint("CENTER", root, "CENTER")
        host:EnableMouse(false)
        hosts[key] = host
    end
    local surface = { root = root, hosts = hosts, dock = parent, interactionMode = interactionMode }
    if interactionMode == "panel" then
        surface.left = EXUI:CreateIconPanelPreview(hosts.left, EXWIND_MODULE_KEY, panelCallbacks)
        surface.center = EXUI:CreateIconPanelPreview(hosts.center, EXWIND_MODULE_KEY, panelCallbacks)
        surface.right = EXUI:CreateIconPanelPreview(hosts.right, EXWIND_MODULE_KEY, panelCallbacks)
    else
        surface.left = CreateRendererSession(hosts.left, interactionMode)
        surface.center = CreateRendererSession(hosts.center, interactionMode)
        surface.right = CreateRendererSession(hosts.right, interactionMode)
    end
    return surface
end

local function ReleaseSurface(surface)
    if not surface then return end
    for _, key in ipairs({ "left", "center", "right" }) do
        ReleaseCollection(surface[key])
        surface[key] = nil
    end
    if surface.root then
        surface.root:Hide()
        surface.root:ClearAllPoints()
        surface.root:SetParent(nil)
        surface.root = nil
    end
end

PositionSurfaceHosts = function(surface, presentation)
    local iconWidth = presentation.left.bodyWidth or 1
    local clockWidth = presentation.center.records[1].itemPresentation.bodySize.width
    local gap = math.max(8, presentation.left.padding or 0)
    local sideOffset = clockWidth * 0.5 + gap + iconWidth * 0.5
    surface._sideOffset = sideOffset
    local left, center, right = surface.hosts.left, surface.hosts.center, surface.hosts.right
    left:ClearAllPoints(); left:SetPoint("CENTER", surface.root, "CENTER", -sideOffset, 0)
    center:ClearAllPoints(); center:SetPoint("CENTER", surface.root, "CENTER", 0, 0)
    right:ClearAllPoints(); right:SetPoint("CENTER", surface.root, "CENTER", sideOffset, 0)
end

local function ApplySurface(surface, presentation)
    if surface.interactionMode == "panel" then
        RenderPanelPresentation(surface.left, presentation.left)
        RenderPanelPresentation(surface.center, presentation.center)
        RenderPanelPresentation(surface.right, presentation.right)
    else
        ApplyPresentation(surface.left, presentation.left)
        ApplyPresentation(surface.center, presentation.center)
        ApplyPresentation(surface.right, presentation.right)
    end
    PositionSurfaceHosts(surface, presentation)
    surface.root:Show()
end

-- live 阶段不得 Render/Acquire/Release；只用 Collection 正式的
-- ReapplyCurrentItems 重套当前三宿主已经 materialize 的 presentation。
local function ReplacePresentation(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
end

local function FindActionRecord(presentation, itemID)
    for index, record in ipairs(presentation.records or {}) do
        if record.id == itemID then return record, index end
    end
    return nil, nil
end

local function ReapplyMicroMenuLiveCollection(collection, presentation, kind)
    if not collection or type(collection.ReapplyCurrentItems) ~= "function" then return end
    if type(collection.currentLayout) == "table" then
        collection.currentLayout.spacing = presentation.layout.spacing
        collection.currentLayout.maxVisible = presentation.layout.maxVisible
    end
    collection:ReapplyCurrentItems(function(itemPresentation, item)
        if kind == "center" then
            local record = presentation.records[1]
            if record and record.itemPresentation then ReplacePresentation(itemPresentation, record.itemPresentation) end
            return
        end
        local record, index = FindActionRecord(presentation, item and item.id)
        if record then ReplacePresentation(itemPresentation, BuildActionItemPresentation(record, presentation, index)) end
    end)
end

local function ReapplyMicroMenuLiveSurface(surface, presentation)
    if not surface or not surface.root then return end
    ReapplyMicroMenuLiveCollection(surface.left, presentation.left, "left")
    ReapplyMicroMenuLiveCollection(surface.center, presentation.center, "center")
    ReapplyMicroMenuLiveCollection(surface.right, presentation.right, "right")
    -- 中间时间仍是唯一几何根：缩放/字体/图标尺寸的 live 投影后，左右只能
    -- 由新时钟宽度重新定位，不能读取或写入任何独立左右坐标。
    PositionSurfaceHosts(surface, presentation)
end

ApplyMicroMenuLivePresentation = function(_, context)
    local path = type(context) == "table" and context.fullPath or nil
    local visualPath = path == "barScale" or path == "bgAlpha" or
        (type(path) == "string" and (path:match("^timeFont%.") or path:match("^iconStyle%.")))
    if not visualPath then return false end
    ReapplyMicroMenuLiveSurface(runtimeSurface, BuildPresentation(false))
    ReapplyMicroMenuLiveSurface(worldSurface, BuildPresentation(true))
    ReapplyMicroMenuLiveSurface(panelSurface, BuildPresentation(true))
    return true
end

local function UnionSurfaceBounds(result, bounds, x, y)
    if type(bounds) ~= "table" then return result end
    local left = (bounds.left or -bounds.width * 0.5) + x
    local right = (bounds.right or bounds.width * 0.5) + x
    local bottom = (bounds.bottom or -bounds.height * 0.5) + y
    local top = (bounds.top or bounds.height * 0.5) + y
    if not result then return { left = left, right = right, bottom = bottom, top = top } end
    result.left, result.right = math.min(result.left, left), math.max(result.right, right)
    result.bottom, result.top = math.min(result.bottom, bottom), math.max(result.top, top)
    return result
end

local function GetSurfaceWorldBounds(surface)
    if not surface or not surface.root then return nil end
    local bounds
    for _, key in ipairs({ "left", "center", "right" }) do
        local collection = surface[key]
        local part = collection and collection.GetWorldBounds and collection:GetWorldBounds()
        local offset = key == "left" and -((surface._sideOffset) or 0) or key == "right" and ((surface._sideOffset) or 0) or 0
        bounds = UnionSurfaceBounds(bounds, part, offset, 0)
    end
    if not bounds then return nil end
    return {
        anchor = surface.root,
        left = bounds.left, right = bounds.right, bottom = bounds.bottom, top = bounds.top,
        width = math.max(1, bounds.right - bounds.left), height = math.max(1, bounds.top - bounds.bottom),
        anchorOffsetX = (bounds.left + bounds.right) * 0.5, anchorOffsetY = (bounds.bottom + bounds.top) * 0.5,
    }
end

local function RenderRuntime()
    local anchor = EnsureAnchor()
    if not runtimeSurface then runtimeSurface = CreateSurface(anchor, "runtime") end
    ApplySurface(runtimeSurface, BuildPresentation(false))
    anchor:SetShown(EX_DB.enabled == true)
end

local function RenderWorld(host)
    ReleaseSurface(runtimeSurface); runtimeSurface = nil
    ReleaseSurface(worldSurface)
    worldSurface = CreateSurface(host, "world")
    ApplySurface(worldSurface, BuildPresentation(true))
    host:Show()
    if SyncBlizzardMicroMenu then SyncBlizzardMicroMenu() end
end

local function ReleaseWorld()
    ReleaseSurface(worldSurface); worldSurface = nil
    RenderRuntime()
    if SyncBlizzardMicroMenu then SyncBlizzardMicroMenu() end
end

local function HandlePanelIntent(intent)
    if type(intent) ~= "table" then return false end
    -- 左键仅验证 panel 命中层；右键才进入对应槽位的设置 GUI。IconCollection
    -- 的正式 intent 名称是 elementRightClicked，不是不存在的 openGUI。
    if intent.type == "elementClicked" then return true end
    if intent.type ~= "elementRightClicked" then return false end
    local side, index = type(intent.elementID) == "string" and intent.elementID:match("^(left|right)%.slot%.(%d+)")
    if side and index then
        EX_DB.selectedSlotSide, EX_DB.selectedSlotIndex = side, tonumber(index)
        RefreshLayoutPanel()
    end
    if ExwindTools.UI and type(ExwindTools.UI.FocusModuleGridKey) == "function" then
        ExwindTools.UI:FocusModuleGridKey(EXWIND_MODULE_KEY, intent.guiTarget or "selectedSlotSide")
        return true
    end
    return false
end

local function ReleasePanel()
    ReleaseSurface(panelSurface)
    panelSurface = nil
end

local function ShowPanel(dock)
    ReleasePanel()
    dock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1)
    panelSurface = CreateSurface(dock, "panel", { onIntent = HandlePanelIntent })
    ApplySurface(panelSurface, BuildPresentation(true))
end

local function AnyWorldDisplayActive()
    return worldSurface ~= nil
end

local blizzMicroMenuOrigPoint
local function SetBlizzardMicroMenuVisible(visible)
    local container = _G.MicroMenuContainer
    if not container then return end
    if visible then
        container:ClearAllPoints()
        if blizzMicroMenuOrigPoint then
            container:SetPoint(unpack(blizzMicroMenuOrigPoint))
        else
            container:SetPoint("TOP", UIParent, "TOP", 0, 0)
        end
        return
    end
    if not blizzMicroMenuOrigPoint then
        local point, relativeTo, relativePoint, x, y = container:GetPoint()
        if point then blizzMicroMenuOrigPoint = { point, relativeTo, relativePoint, x, y } end
    end
    container:ClearAllPoints()
    container:SetPoint("TOP", UIParent, "BOTTOM", 0, -9999)
end

SyncBlizzardMicroMenu = function()
    SetBlizzardMicroMenuVisible(not (EX_DB.enabled == true or AnyWorldDisplayActive()))
end

local function TickClock()
    if EX_DB.enabled ~= true or worldSurface then return end
    if runtimeSurface then ApplySurface(runtimeSurface, BuildPresentation(false)) end
end

local function SyncTicker()
    if EX_DB.enabled == true then
        if not ticker then ticker = C_Timer.NewTicker(1, TickClock) end
    elseif ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function RefreshVisuals()
    EnsureAnchor()
    if worldSurface then
        ApplySurface(worldSurface, BuildPresentation(true))
    else
        RenderRuntime()
    end
    if panelSurface then
        if panelSurface.dock then panelSurface.dock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1) end
        ApplySurface(panelSurface, BuildPresentation(true))
    end
    SyncTicker()
    SyncBlizzardMicroMenu()
end

local function RefreshActiveSurfaces()
    if worldSurface then ReapplyMicroMenuLiveSurface(worldSurface, BuildPresentation(true)) end
    if runtimeSurface then ReapplyMicroMenuLiveSurface(runtimeSurface, BuildPresentation(false)) end
    if panelSurface then ReapplyMicroMenuLiveSurface(panelSurface, BuildPresentation(true)) end
end

EXUI:RegisterModuleValueController(EXWIND_MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })

EXUI:RegisterEditableModule({
    addon = "ExwindTools", key = EXWIND_MODULE_KEY, name = L["微型选单"], settingsPage = EXWIND_MODULE_KEY,
    orientation = "HORIZONTAL", worldAnchorMode = "semantic-root", editOverlay = { titleFontSize = 26 },
    getAnchor = EnsureAnchor, RenderWorld = RenderWorld, ReleaseWorld = ReleaseWorld,
    GetWorldBounds = function() return GetSurfaceWorldBounds(worldSurface) end,
})

ExwindTools:RegisterModulePreview(EXWIND_MODULE_KEY, {
    mount = ShowPanel,
    update = function()
        if panelSurface then
            if panelSurface.dock then panelSurface.dock:SetBackdropColor(0.5804, 0.6471, 0.9882, 1) end
            ApplySurface(panelSurface, BuildPresentation(true))
        end
    end,
    release = ReleasePanel,
})

-- =============================================================
-- 状态订阅：业务只更新数据，唯一 Renderer 重新应用同一份 presentation。
-- =============================================================
ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", EXWIND_MODULE_KEY, RefreshVisuals)
ExwindTools:RegisterEvent("UNIT_PORTRAIT_UPDATE", EXWIND_MODULE_KEY, function(_, unit)
    if unit and unit ~= "player" then return end
    RefreshVisuals()
    if IconPicker.frame and IconPicker.frame:IsShown() then IconPicker_Refresh() end
end)
ExwindTools:RegisterEvent("PORTRAITS_UPDATED", EXWIND_MODULE_KEY, function()
    RefreshVisuals()
    if IconPicker.frame and IconPicker.frame:IsShown() then IconPicker_Refresh() end
end)

ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".IconPickerApplied", EXWIND_MODULE_KEY, RefreshVisuals)
ExwindTools:WatchState(EXWIND_MODULE_KEY .. ".ButtonClicked", EXWIND_MODULE_KEY, function(info)
    if not info or not info.key then return end
    if info.key == "btn_reset_pos" then
        EX_DB.anchorX, EX_DB.anchorY = EX_DEFAULTS.anchorX, EX_DEFAULTS.anchorY
        EnsureAnchorController():ApplyPosition()
        RefreshVisuals()
    elseif info.key == "btn_select_icon" then
        local side, index = GetSelectedSlotInfo()
        IconPicker_Open(side, index)
    end
end)

RefreshVisuals()
ExwindTools:ReportReady(EXWIND_MODULE_KEY)
