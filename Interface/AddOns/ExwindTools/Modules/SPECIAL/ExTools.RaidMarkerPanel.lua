-- =============================================================
-- ExTools.RaidMarkerPanel.lua - 唯一 SecureActionPanelWidget Renderer
-- =============================================================
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI, L = ExwindTools.UI, ExwindTools.L or setmetatable({}, { __index = function(_, k) return k end })
local MODULE_KEY = "ExTools.RaidMarkerPanel"
local C_Timer, UIParent = _G.C_Timer, _G.UIParent
local CreateFrame = _G.CreateFrame
local BINDINGS = { "left", "right", "shift-left", "shift-right", "ctrl-left", "ctrl-right" }
local ATTR = {
    left = { "type1", "action1", "marker1", "unit1" },
    right = { "type2", "action2", "marker2", "unit2" },
    ["shift-left"] = { "shift-type1", "shift-action1", "shift-marker1", "shift-unit1" },
    ["shift-right"] = { "shift-type2", "shift-action2", "shift-marker2", "shift-unit2" },
    ["ctrl-left"] = { "ctrl-type1", "ctrl-action1", "ctrl-marker1", "ctrl-unit1" },
    ["ctrl-right"] = { "ctrl-type2", "ctrl-action2", "ctrl-marker2", "ctrl-unit2" }
}
local BUTTON_SIZE, HOVER_SCALE = 28, 1.12
local PANEL_FADE_OUT_DELAY, PANEL_FADE_DURATION = 2, .35
local DEFAULTS = {
            attachToCustom = false,
            bundleLayout = false,
            buttonSpacing = 4,
            countdownSeconds = "10",
            customAttachTarget = "",
            enableCountdownButton = true,
            enableReadyCheckButton = true,
            hoverShow = true,
            idleAlpha = 0.15,
            posX = -12,
            posY = 490,
            raidMarkerBinding = "left",
            scale = 1,
            showPanel = true,
            swapCountdownAndReadyCheck = false,
            worldMarkerBinding = "right",
        }
ExwindTools:DeclareModuleSpecDefaults(MODULE_KEY, { root = DEFAULTS })
local DB = ExwindTools:GetModuleDB(MODULE_KEY)
local controller
local function PickRaidMarkerPanelAnchor()
    if controller and type(controller.StartFramePicker) == "function" then return controller:StartFramePicker() end
    return false
end
local RAID_MARKER_PANEL_ANCHOR_OPTS = {
    bindRoot = true,
    offsetXKey = "posX",
    offsetYKey = "posY",
    defaultOffsetX =
        DEFAULTS.posX,
    defaultOffsetY = DEFAULTS.posY,
    attachEnabledKey = "attachToCustom",
    attachTargetKey =
    "customAttachTarget",
    onPickFrame = PickRaidMarkerPanelAnchor
}
local layout = {
    { key = "header", type = "header", x = 1, y = 1, w = 200, h = 8, label = L["团队标记面板"], labelSize = 24 },
    { key = "showPanel", type = "checkbox", x = 1, y = 15, w = 46, h = 6, label = L["显示面板"] },
    { key = "scale", type = "slider", x = 51, y = 15, w = 46, h = 6, label = L["面板缩放"], min = .1, max = 3, step = .1 },
    { key = "buttonSpacing", type = "slider", x = 101, y = 15, w = 46, h = 6, label = L["按钮间距"], min = 0, max = 20, step = 1 },
    { key = "btn_reset_pos", type = "button", x = 151, y = 15, w = 46, h = 6, label = L["重置位置"] },
    { key = "enableCountdownButton", type = "checkbox", x = 1, y = 30, w = 46, h = 6, label = L["启用倒数"] },
    { key = "countdownSeconds", type = "input", x = 51, y = 30, w = 46, h = 6, label = L["倒数秒数"] },
    { key = "enableReadyCheckButton", type = "checkbox", x = 101, y = 30, w = 46, h = 6, label = L["启用就位确认"] },
    { key = "swapCountdownAndReadyCheck", type = "checkbox", x = 151, y = 30, w = 46, h = 6, label = L["交换确认与倒数"] },
    { key = "raidMarkerBinding", type = "dropdown", x = 1, y = 45, w = 46, h = 6, label = L["标记按键"], items = "left:左键,right:右键,shift-left:SHIFT+左键,shift-right:SHIFT+右键,ctrl-left:CTRL+左键,ctrl-right:CTRL+右键" },
    { key = "worldMarkerBinding", type = "dropdown", x = 51, y = 45, w = 46, h = 6, label = L["光柱按键"], items = "left:左键,right:右键,shift-left:SHIFT+左键,shift-right:SHIFT+右键,ctrl-left:CTRL+左键,ctrl-right:CTRL+右键" },
    { key = "bundleLayout", type = "checkbox", x = 1, y = 60, w = 46, h = 6, label = L["束状排列"] },
    { key = "hoverShow", type = "checkbox", x = 51, y = 60, w = 46, h = 6, label = L["悬停显示"] },
    { key = "idleAlpha", type = "slider", x = 101, y = 60, w = 46, h = 6, label = L["离开透明度"], min = 0, max = 1, step = .05 },
    { key = "anchorGroup", type = "anchorgroup", x = 1, y = 71, w = 200, h = 18, measure = true, label = L["锚点设置"], opts = RAID_MARKER_PANEL_ANCHOR_OPTS },
}
ExwindTools:RegisterModuleLayout(MODULE_KEY, layout)
if not ExwindTools:IsModuleEnabled(MODULE_KEY) then return end
local runtimeRoot, anchor, runtimePanel, worldPanel, dockPanel, worldActive
local refreshPending = false
local HandleRuntimeHoverEnter, HandleRuntimeHoverLeave
-- 战斗状态只读 ExwindState；本模块不再各自查询 InCombatLockdown。
-- 所有安全按钮的重建/重锚定都由该状态闸门统一延后至离战。
local function IsCombatLocked()
    return ExwindTools.State and ExwindTools.State.InCombat == true
end
local function bind(v, fallback) return ATTR[v] and v or fallback end
local function normalize()
    DB.scale = math.max(.1, math.min(3, tonumber(DB.scale) or 1)); DB.buttonSpacing = math.max(0,
        math.min(20, math.floor(tonumber(DB.buttonSpacing) or 4))); DB.countdownSeconds = tostring(math.max(1,
        math.min(30, math.floor(tonumber(DB.countdownSeconds) or 10)))); DB.raidMarkerBinding = bind(
        DB.raidMarkerBinding, "left"); DB.worldMarkerBinding = bind(DB.worldMarkerBinding, "right"); if DB.raidMarkerBinding == DB.worldMarkerBinding then
        DB.worldMarkerBinding =
            DB.raidMarkerBinding == "right" and "left" or "right"
    end
end
local function CanMark()
    if _G.IsInRaid and _G.IsInRaid() then return _G.UnitIsGroupLeader("player") or _G.UnitIsGroupAssistant("player") end
    return true
end
local function CanChat() return (_G.IsInGroup and _G.IsInGroup()) or (_G.IsInRaid and _G.IsInRaid()) end
local function worldID(marker)
    local order = { 8, 4, 1, 7, 2, 3, 6, 5 }; return order[9 - marker] or marker
end
local function secure(marker, remove)
    local out = {}; local raid, world = ATTR[DB.raidMarkerBinding], ATTR[DB.worldMarkerBinding]
    out[raid[1]] = "raidtarget"; out[raid[2]] = remove and "clear-all" or "toggle"; if not remove then
        out[raid[3]] = marker; out[raid[4]] = "target"
    end
    out[world[1]] = "worldmarker"; out[world[2]] = remove and "clear" or "toggle"; if not remove then
        out[world[3]] =
            worldID(marker)
    end; return out
end
local function slotSpec(kind, marker, sample)
    -- 团队标记/清除要求队长或助理；倒数和就位确认的可用条件是“在队伍中”。
    -- 之前把 CanMark() 错套给后两者：raid target 由 extra texture 显示仍有颜色，
    -- countdown/ready 则通过 IconWidget 被 SetDesaturated(true) 灰掉。
    local enabled = sample or ((kind == "marker" or kind == "remove") and CanMark() or CanChat())
    local visual = {
        width = BUTTON_SIZE,
        height = BUTTON_SIZE,
        shown = true,
        desaturated = not enabled,
        alpha = enabled and 1 or .35
    }
    if kind == "marker" then
        visual.raidTargetIndex = marker
    elseif kind == "remove" then
        visual.atlas, visual.contentScale, visual.enableCrop = "GM-raidMarker-remove", 1.31, false
    elseif kind == "countdown" then
        visual.atlas, visual.colorR, visual.colorG, visual.colorB, visual.contentScale, visual.enableCrop =
            "GM-icon-countdown-hover", .20, .85, 1.00, 1.87, false
    else
        visual.atlas, visual.colorR, visual.colorG, visual.colorB, visual.contentScale, visual.enableCrop =
            "GM-icon-readyCheck-hover", 1.00, .82, .20, 2.00, false
    end
    return {
        visual = visual,
        attributes = (kind == "marker" and secure(marker, false)) or
            (kind == "remove" and secure(nil, true)) or nil
    }
end
local function ordered()
    local out = {}
    for i = 8, 1, -1 do out[#out + 1] = { "marker", i } end
    out[#out + 1] = { "remove" }
    local first, second = "countdown", "ready"
    if DB.swapCountdownAndReadyCheck then first, second = second, first end
    local function isEnabled(kind)
        return (kind == "countdown" and DB.enableCountdownButton == true)
            or (kind == "ready" and DB.enableReadyCheckButton == true)
    end
    if isEnabled(first) then out[#out + 1] = { first } end
    if isEnabled(second) then out[#out + 1] = { second } end
    return out
end
-- 唯一声明式尺寸：运行时、世界编辑和面板预览都必须使用这一份。
-- SecureActionPanel 的内容从宿主 CENTER 排列，因此可视并集中心就是
-- 语义 Anchor；覆盖层不扫描子按钮，也绝不把内容尺寸反写为保存坐标。
local function LayoutMetrics(list, valuesAreNormalized)
    if not valuesAreNormalized then normalize() end
    local count = #(list or ordered())
    local spacing = DB.buttonSpacing
    local bundle = DB.bundleLayout == true
    local width = bundle and (16 + BUTTON_SIZE) or (16 + count * BUTTON_SIZE + math.max(0, count - 1) * spacing)
    local height = bundle and (16 + count * BUTTON_SIZE + math.max(0, count - 1) * spacing) or (16 + BUTTON_SIZE)
    if type(width) ~= "number" or width <= 0 or width ~= width
        or type(height) ~= "number" or height <= 0 or height ~= height then
        error("RaidMarkerPanel LayoutMetrics must return finite positive dimensions", 2)
    end
    return width, height
end
local function PositionSlot(surface, slot, index, bundle, spacing)
    local left = 8 + (bundle and 0 or (index - 1) * (BUTTON_SIZE + spacing))
    local top = 8 + (bundle and (index - 1) * (BUTTON_SIZE + spacing) or 0)
    slot.button:ClearAllPoints()
    slot.button:SetPoint("CENTER", surface.panel.root, "TOPLEFT", left + BUTTON_SIZE / 2, -(top + BUTTON_SIZE / 2))
end
local function SyncSurfaceGeometry(surface, list, valuesAreNormalized)
    if not surface or not surface.host or not surface.panel then return false end
    local width, height = LayoutMetrics(list, valuesAreNormalized)
    local spacing, bundle = DB.buttonSpacing, DB.bundleLayout == true
    surface.host:SetSize(width, height)
    surface.panel.root:SetAllPoints(surface.host)
    for index, data in ipairs(list) do
        local slot = surface.panel.slots[data[1] .. (data[2] or "")]
        if slot then PositionSlot(surface, slot, index, bundle, spacing) end
    end
    -- AnchorController 的 frame 是 runtime/world 的真实命中与编辑框，不能继续保留
    -- 创建时的 320×44。它必须和缩放后的可见并集同尺寸。
    if anchor and surface.host:GetParent() == anchor then
        anchor:SetSize(width * DB.scale, height * DB.scale)
    end
    return true
end
local function Mount(parent, mode)
    local host = CreateFrame("Frame", nil, parent); host:EnableMouse(mode == "runtime"); local panel = EXUI
        :CreateSecureActionPanelWidget(host, mode)
    local surface = { host = host, panel = panel, slots = {}, fadeToken = 0 }
    if mode == "runtime" then
        host:SetScript("OnEnter", function() HandleRuntimeHoverEnter(surface) end)
        host:SetScript("OnLeave", function() HandleRuntimeHoverLeave(surface) end)
    end
    return surface
end
local function Release(surface)
    if surface then
        surface.panel:Release(); surface.host:Hide(); surface.host:SetParent(nil)
    end
end
local function SetRuntimeIdleAlpha(surface)
    if surface and surface.host and surface.panel and surface.panel.mode == "runtime" then
        surface.host:SetAlpha(DB.hoverShow == true and DB.idleAlpha or 1)
    end
end
local function StopRuntimeFade(surface)
    if surface and surface.fadeGroup then surface.fadeGroup:Stop() end
end
local function FadeRuntimeSurfaceToIdle(surface)
    if not surface or not surface.host or not surface.host:IsShown() then return end
    local targetAlpha = DB.hoverShow == true and DB.idleAlpha or 1
    local currentAlpha = surface.host:GetAlpha() or 1
    if math.abs(currentAlpha - targetAlpha) < .01 then
        surface.host:SetAlpha(targetAlpha); return
    end
    StopRuntimeFade(surface)
    if not surface.fadeGroup then
        surface.fadeGroup = surface.host:CreateAnimationGroup()
        surface.fadeAnimation = surface.fadeGroup:CreateAnimation("Alpha")
        surface.fadeGroup:SetScript("OnFinished", function()
            if surface.host then surface.host:SetAlpha(surface.fadeTargetAlpha or 1) end
        end)
    end
    surface.fadeTargetAlpha = targetAlpha
    surface.fadeAnimation:SetFromAlpha(currentAlpha)
    surface.fadeAnimation:SetToAlpha(targetAlpha)
    surface.fadeAnimation:SetDuration(PANEL_FADE_DURATION)
    surface.fadeGroup:Play()
end
HandleRuntimeHoverEnter = function(surface)
    if not surface or DB.hoverShow ~= true then return end
    surface.fadeToken = surface.fadeToken + 1
    StopRuntimeFade(surface)
    surface.host:SetAlpha(1)
end
HandleRuntimeHoverLeave = function(surface)
    if not surface or DB.hoverShow ~= true then return end
    surface.fadeToken = surface.fadeToken + 1
    local fadeToken = surface.fadeToken
    C_Timer.After(PANEL_FADE_OUT_DELAY, function()
        if not surface.host or fadeToken ~= surface.fadeToken or not surface.host:IsShown() or surface.host:IsMouseOver() then return end
        FadeRuntimeSurfaceToIdle(surface)
    end)
end
local function Tooltip(surface, slot, kind, marker)
    local button = slot.button
    button:SetScript("OnEnter",
        function(self)
            slot:SetVisualScale(HOVER_SCALE)
            HandleRuntimeHoverEnter(surface)
            if _G.GameTooltip then
                _G.GameTooltip:SetOwner(self, "ANCHOR_TOP"); _G.GameTooltip:SetText(kind == "marker" and
                    (L["团队标记"] .. " " .. marker) or kind == "remove" and L["移除全部标记"] or kind == "countdown" and L
                    ["团队倒数"] or
                    L["就位确认"]); _G.GameTooltip:Show()
            end
        end)
    button:SetScript("OnLeave", function(self)
        slot:SetVisualScale(1)
        HandleRuntimeHoverLeave(surface)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
end
local function Apply(surface, sample)
    -- runtime 内含 SecureActionButtonTemplate；战斗中不得重新锚定、改尺寸或 Acquire/Show slot。
    -- 设置改动和目标/团队事件留到 ExwindState.InCombat=false 后由同一 Refresh 完整投影。
    if surface and surface.panel and surface.panel.mode == "runtime" and IsCombatLocked() then
        refreshPending = true
        return false
    end
    local list = ordered(); local w, h = LayoutMetrics(list); local spacing = DB.buttonSpacing; local bundle = DB
        .bundleLayout
    surface.host:ClearAllPoints(); surface.host:SetPoint("CENTER", surface.host:GetParent(), "CENTER"); surface.host
        :SetSize(w, h); surface.panel.root:SetAllPoints(surface.host)
    for index, data in ipairs(list) do
        local kind, marker = data[1], data[2]; local id = kind .. (marker or ""); local slot = surface.panel:AcquireSlot(
            id); surface.slots[id] = slot; slot:Apply(slotSpec(kind, marker, sample)); slot.button:ClearAllPoints()
        -- 按视觉中心锚定：SetScale 只能向四方等量扩张，不能把整排按钮推向右下。
        PositionSlot(surface, slot, index, bundle, spacing)
        slot:SetVisualScale(1); slot:SetShown(true)
        if surface.panel.mode == "runtime" then
            Tooltip(surface, slot, kind, marker); if kind == "countdown" then
                slot.button:SetScript("OnClick",
                    function(_, b)
                        if CanChat() and _G.C_PartyInfo and _G.C_PartyInfo.DoCountdown then
                            pcall(
                                _G.C_PartyInfo.DoCountdown, b == "RightButton" and 0 or tonumber(DB.countdownSeconds))
                        end
                    end)
            elseif kind == "ready" then
                slot.button:SetScript("OnClick",
                    function()
                        if CanChat() and _G.C_PartyInfo and _G.C_PartyInfo.DoReadyCheck then
                            pcall(_G.C_PartyInfo
                                .DoReadyCheck)
                        end
                    end)
            end
        end
    end
    surface.host:SetScale(DB.scale); SyncSurfaceGeometry(surface, list); SetRuntimeIdleAlpha(surface); surface.host:Show()
    return true
end
local function EnsureAnchor()
    if controller then return controller:Ensure() end; controller = ExwindTools:CreateAnchorController({
        moduleKey =
            MODULE_KEY,
        frameName = "ExwindRaidMarkerAnchor",
        title = L["团队标记面板"],
        getDB = function() return DB end,
        offsetXKey =
        "posX",
        offsetYKey = "posY",
        defaultOffsetX = DEFAULTS.posX,
        defaultOffsetY = DEFAULTS.posY,
        attachEnabledKey =
        "attachToCustom",
        attachTargetKey = "customAttachTarget",
        initialWidth = 320,
        initialHeight = 44,
        clampedToScreen = true,
        onPositionSaved = function()
            if EXUI.CurrentModule == MODULE_KEY and EXUI.MainFrame and EXUI.MainFrame:IsShown() and type(EXUI.RefreshContent) == "function" then
                EXUI:RefreshContent()
            end
        end
    }); anchor = controller:Ensure(); return anchor
end
local function Runtime()
    if IsCombatLocked() then
        refreshPending = true; return
    end
    local host = EnsureAnchor(); controller:ApplyPosition(); if worldActive then return end; if not runtimeRoot then
        runtimeRoot =
            Mount(host, "runtime")
    end; Apply(runtimeRoot, false); runtimeRoot.host:SetShown(DB.showPanel == true)
end
local function RenderWorld(host)
    worldActive = true; if runtimeRoot then runtimeRoot.host:Hide() end; Release(worldPanel); worldPanel = Mount(host,
        "world"); Apply(worldPanel, true); host:Show()
end
local function ReleaseWorld()
    Release(worldPanel); worldPanel = nil; worldActive = false; Runtime()
end
local function ShowPanel(dock)
    Release(dockPanel); dockPanel = Mount(dock, "panel"); Apply(dockPanel, true)
end
local function Refresh()
    if IsCombatLocked() then
        -- 不能在战斗中重建或重锚定 Runtime 安全按钮；也不刷新预览，
        -- 以免同一次业务刷新产生 Runtime/Panel 不同投影。
        refreshPending = true
        return
    end
    refreshPending = false
    Runtime(); if worldPanel then Apply(worldPanel, true) end; if dockPanel then Apply(dockPanel, true) end
end
local function ReapplyExistingSurface(surface, sample)
    if not surface or not surface.panel or type(surface.panel.ReapplyExistingSlots) ~= "function" then return end
    local list, w, h = ordered(), LayoutMetrics(ordered())
    local spacing, bundle = DB.buttonSpacing, DB.bundleLayout
    -- 完整 Apply 已把缩放放在 surface host；统一重套不能只把每个 slot
    -- 归零，否则面板缩放 Slider 永远看起来无效。
    surface.host:SetScale(DB.scale)
    SyncSurfaceGeometry(surface, list, true)
    local wanted = {}
    surface.panel:ReapplyExistingSlots(function(id)
        for index, data in ipairs(list) do
            local kind, marker = data[1], data[2]
            local currentID = kind .. (marker or "")
            if currentID == id then
                wanted[id] = true
                local slot = surface.slots[id]
                if slot then
                    PositionSlot(surface, slot, index, bundle, spacing); slot:SetVisualScale(1); slot:SetShown(true)
                end
                return slotSpec(kind, marker, sample)
            end
        end
        local slot = surface.slots[id]
        if slot then slot:SetShown(false) end
        return nil
    end)
end
local function RefreshActiveSurfaces()
    if runtimeRoot and runtimeRoot.host then
        runtimeRoot.host:SetShown(DB.showPanel == true)
    end
    ReapplyExistingSurface(dockPanel, true)
    ReapplyExistingSurface(worldPanel, true)
    ReapplyExistingSurface(runtimeRoot, false)
end
EXUI:RegisterModuleValueController(MODULE_KEY, { RefreshActiveSurfaces = RefreshActiveSurfaces })
EnsureAnchor(); ExwindTools:RegisterModulePreview(MODULE_KEY,
    {
        mount = ShowPanel,
        update = Refresh,
        release = function()
            Release(dockPanel); dockPanel = nil
        end
    }); EXUI:RegisterEditableModule({
    addon = "ExwindTools",
    key = MODULE_KEY,
    name = L["团队标记面板"],
    settingsPage =
        MODULE_KEY,
    orientation = "HORIZONTAL",
    worldAnchorMode = "semantic-root",
    getAnchor = EnsureAnchor,
    RenderWorld =
        RenderWorld,
    ReleaseWorld = ReleaseWorld,
    GetWorldBounds = function()
        local width, height = LayoutMetrics(); return { width = width * DB.scale, height = height * DB.scale, anchorOffsetX = 0, anchorOffsetY = 0 }
    end
})
ExwindTools:WatchState(MODULE_KEY .. ".ButtonClicked", MODULE_KEY,
    function(info)
        if info and info.key == "btn_reset_pos" then
            DB.posX, DB.posY = 0, 0; Refresh()
        end
    end)
ExwindTools:WatchState("InCombat", MODULE_KEY .. ".CombatRefresh", function(inCombat)
    if inCombat ~= false then return end
    if runtimeRoot then runtimeRoot.panel:FlushSecure() end
    if refreshPending then Refresh() end
end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do
    ExwindTools:RegisterEvent(e, MODULE_KEY,
        function() Refresh() end)
end
ExwindTools:ReportReady(MODULE_KEY); C_Timer.After(0, Refresh)
