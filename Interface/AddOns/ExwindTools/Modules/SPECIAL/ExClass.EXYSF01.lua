local Core = _G.ExwindTools
if not Core or not Core.UI then return end

local UI, L = Core.UI, Core.L
local KEY = "ExClass.EXYSF01"
local SOUND_ROOT = "Interface\\AddOns\\ExwindTools\\Sounds\\EXYSF01\\"
local LSM = LibStub("LibSharedMedia-3.0")
local white = Core.GUIColors.white

local defaults = {
    font = {
        enabled = true, size = 40, outline = "OUTLINE", shadow = false,
        r = white[1], g = white[2], b = white[3], a = white[4],
        justifyH = "CENTER", justifyV = "MIDDLE", fixedWidth = 80, x = 0, y = 0,
    },
    position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 100 },
}
local sounds = {
    { "sound2", "【露露】2", "2.ogg", L["2层语音"] },
    { "sound3", "【露露】3", "3.ogg", L["3层语音"] },
    { "soundOverride", "【露露】致命一击", "critical.ogg", L["致命一击语音"] },
}
for _, entry in ipairs(sounds) do
    local key, name, path = entry[1], entry[2], SOUND_ROOT .. entry[3]
    LSM:Register("sound", name, path)
    defaults[key .. "Enabled"] = true
    defaults[key .. "Source"] = "lsm"
    defaults[key .. "LSM"] = name
    defaults[key .. "Channel"] = "Master"
    defaults[key .. "Path"] = path
end
Core:DeclareModuleSpecDefaults(KEY, { root = defaults })
local DB = Core:GetModuleDB(KEY)
local host, container, countFont, worldCollection
local runtimeStarted = false
local controller
local SAMPLE_LAYOUT = { direction = "DOWN", spacing = 0, maxVisible = 1 }
local anchorController = Core:CreateAnchorController({
    moduleKey = KEY, frameName = "ExToolsEXYSF01Display", title = Core:GetModuleMeta(KEY).Name,
    getDB = function() return DB.position end,
    offsetXKey = "x", offsetYKey = "y", defaultOffsetX = 0, defaultOffsetY = 100,
    getAnchorPoint = function() return DB.position.point end,
    getRelativePoint = function() return DB.position.relativePoint end,
    initialWidth = 80, initialHeight = 64, clampedToScreen = false,
    onCreateFrame = function(_, frame) frame:Hide() end,
    onPositionSaved = function()
        UI:NotifyModuleValueChanged(KEY, "position", "committed")
    end,
})

local function EnsureAnchor()
    host = anchorController:Ensure()
    return host
end

local function BuildSample()
    local halfWidth = math.max(40, DB.font.size or 40)
    local halfHeight = math.max(32, (DB.font.size or 40) * 0.75)
    return {
        text = "2", style = DB.font, semanticSlot = "exysf01.count",
        declaredBounds = { left = -halfWidth, right = halfWidth, bottom = -halfHeight, top = halfHeight },
        anchor = { point = "CENTER", relativePoint = "CENTER", x = DB.font.x or 0, y = DB.font.y or 0 },
    }
end

local function PlayAlert(key, force)
    if not force and (not runtimeStarted or not Core:IsModuleEnabled(KEY)
        or DB[key .. "Enabled"] ~= true) then return end
    local source, sound = DB[key .. "Source"]
    if source == "lsm" then
        local name = DB[key .. "LSM"]
        if name ~= "None" then sound = LSM:Fetch("sound", name, true) end
    elseif source == "file" then
        sound = DB[key .. "Path"]
    end
    if sound and sound ~= "" then
        return PlaySoundFile(tonumber(sound) or sound, DB[key .. "Channel"])
    end
end

local function RefreshText()
    if not host then return end
    local enabled = runtimeStarted and Core:IsModuleEnabled(KEY)
    host:SetShown(worldCollection ~= nil or enabled)
    if container then
        container:SetShown(enabled and not worldCollection and DB.font.enabled ~= false)
        _G.EXDB:ApplyFont(countFont, DB.font)
        container:ClearAllPoints()
        container:SetPoint("CENTER", host, "CENTER", DB.font.x or 0, DB.font.y or 0)
    end
end

local function RestorePosition()
    if not host or host.isMoving then return end
    anchorController:ApplyPosition()
end

local function RenderWorld(worldHost)
    if worldCollection then worldCollection:Release() end
    worldCollection = UI:CreateTextCollection(worldHost, "world", KEY)
    local item = worldCollection:AcquireItem(KEY .. ":world")
    worldCollection:ApplyItem(item, BuildSample())
    worldCollection:SetItems({ item }, SAMPLE_LAYOUT)
    RefreshText()
end

local function ReleaseWorld()
    if worldCollection then worldCollection:Release(); worldCollection = nil end
    RefreshText()
end

local cards, soundOptions = {}, {}
for _, entry in ipairs(sounds) do
    local key, label = entry[1], entry[4]
    cards[#cards + 1] = {
        id = "card." .. key, kind = "card", title = label,
        children = {
            { id = key .. "Enabled", kind = "control", controlType = "switch",
                path = key .. "Enabled", label = L["启用"] },
            { id = key .. "Row", kind = "setting", label = L["声音"], children = {
                { id = key, kind = "component", component = "soundselector", path = key,
                    opts = { sources = { "lsm", "file" } }, optionsRef = key },
            } },
            { id = key .. "Channel", kind = "control", controlType = "select",
                path = key .. "Channel", label = L["音频通道"], options = {
                    { value = "Master", label = L["主音量 (Master)"] },
                    { value = "SFX", label = L["音效 (SFX)"] },
                    { value = "Ambience", label = L["环境 (Ambience)"] },
                    { value = "Music", label = L["音乐 (Music)"] },
                    { value = "Dialog", label = L["对话 (Dialog)"] },
                } },
        },
    }
    soundOptions[key] = {
        onTest = function(_, button)
            UI:RunSoundPreview(button, function() return PlayAlert(key, true) end)
        end,
    }
end
cards[#cards + 1] = {
    id = "card.font", kind = "card", title = L["文本设置"],
    children = { { id = "font", kind = "component", component = "fontgroup", path = "font" } },
}

controller = Core:RegisterModule({
    moduleKey = KEY,
    getConfig = function() return DB end,
    settings = {
        layout = { version = 2, cards = cards },
        ownerFactory = function()
            return { options = soundOptions }
        end,
    },
    display = {
        kind = "text",
        buildPanel = function()
            return { {
                itemID = KEY .. ":preview",
                presentation = BuildSample(),
            } }, SAMPLE_LAYOUT
        end,
        onPanelRendered = function(panel, dock)
            for _, item in pairs(panel:GetCollection():GetItems()) do
                local widget = item.widget
                widget:SetFrameStrata(dock:GetFrameStrata())
                UI:ApplyVisualLayer(widget, EXFONTFRAME, item:GetRoot())
                widget:GetContentRegion():Show()
            end
        end,
    },
    RefreshActiveSurfaces = function(self)
        RestorePosition()
        RefreshText()
        if worldCollection then
            worldCollection:ReapplyCurrentItems(function(presentation)
                local sample = BuildSample()
                for key in pairs(presentation) do presentation[key] = nil end
                for key, value in pairs(sample) do presentation[key] = value end
            end)
        end
        self:RenderPreview()
    end,
    editable = {
        addon = "ExwindTools", key = KEY, name = Core:GetModuleMeta(KEY).Name,
        settingsPage = KEY, orientation = "HORIZONTAL", worldAnchorMode = "semantic-root",
        getAnchor = EnsureAnchor,
        RenderWorld = RenderWorld,
        ReleaseWorld = ReleaseWorld,
        GetWorldBounds = function() return worldCollection and worldCollection:GetWorldBounds() or nil end,
    },
})

if not Core:IsModuleEnabled(KEY) then return end
runtimeStarted = true
local state1, state2 = 0, false
EnsureAnchor()
countFont = CreateFont("ExToolsEXYSF01CountFont")
_G.EXDB:ApplyFont(countFont, DB.font)
container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
container:SetSize(80, 64)
container:SetPoint("CENTER", host, "CENTER", DB.font.x or 0, DB.font.y or 0)
container:SetEditModePreviewEnabled(false)
local formatter = C_StringUtil.CreateNumericRuleFormatter()
formatter:SetBreakpoints({ { threshold = 0, format = "" }, { threshold = 1, format = "%.0f" } })
container:AddAuraSlot("buff441786", "HELPFUL", {
    candidateFilters = { includeSpellIDs = { [441786] = true } },
    initializeFrame = function(button)
        button:SetSize(80, 64)
        button:SetPoint("CENTER", container, "CENTER", 0, 0)
        button:EnableMouse(false)
        -- 初始化回调结束后，原生按钮及后代禁止再次从插件代码访问。
        -- 样式继承独立 FontObject，文字偏移由外层容器承接。
        local nativeCount = UI:CreateVisualFontString(button, EXFONTFRAME, "GameFontHighlight")
        nativeCount:SetAllPoints(button)
        nativeCount:SetFontObject(countFont)
        button:SetApplicationCount(nativeCount, { formatter = formatter })
    end,
})
container:SetUnit("player")

-- 模块管理会移除该 owner 的事件；显示对象同时在下一次检查时收起。
C_Timer.NewTicker(0.1, function(ticker)
    if not Core:IsModuleEnabled(KEY) then
        runtimeStarted = false
        RefreshText()
        ticker:Cancel()
    end
end)

Core:RegisterEvent("SPELL_UPDATE_COOLDOWN", KEY, function(_, spellID)
    if issecretvalue(spellID) then return end
    if spellID ~= 441786 or state1 >= 4 then return end
    state1 = state1 + 1
    if state1 == 2 then PlayAlert("sound2") end
    if state1 == 3 then PlayAlert("sound3") end
end)
Core:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", KEY, function(_, baseSpellID, overrideSpellID)
    if issecretvalue(baseSpellID) or issecretvalue(overrideSpellID) then return end
    if baseSpellID ~= 196819 or overrideSpellID ~= 441776 then return end
    local wasActive = state2
    state2 = true
    if not wasActive then PlayAlert("soundOverride") end
end)
Core:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", KEY, function(_, _, _, spellID)
    if issecretvalue(spellID) then return end
    if spellID ~= 441776 then return end
    state2, state1 = false, 0
end)

RestorePosition()
RefreshText()
Core:ReportReady(KEY)
