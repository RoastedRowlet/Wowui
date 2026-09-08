local ExwindTools = _G.ExwindTools
if not ExwindTools then
    return
end

local UIParent = _G.UIParent
local CreateFrame = _G.CreateFrame
local GetCursorPosition = _G.GetCursorPosition
local issecretvalue = _G.issecretvalue
local math = _G.math
local pairs = _G.pairs
local string = _G.string
local table = _G.table
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type

local AnchorController = {}
AnchorController.__index = AnchorController

local function NormalizePoint(point, fallback)
    local text = type(point) == "string" and point or fallback or "CENTER"
    return string.upper(text)
end

local function SetClickThrough(frame)
    if not frame then
        return
    end

    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(false)
    end
end

local function SetInteractive(frame)
    if not frame then
        return
    end

    frame:EnableMouse(true)
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(true)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(true)
    end
end

local function ResolveFramePath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local target = _G
    for part in string.gmatch(path, "([^%.]+)") do
        if target then
            target = target[part]
        else
            break
        end
    end

    if type(target) ~= "table" then
        return nil
    end

    if type(target.GetPoint) ~= "function" and type(target.GetCenter) ~= "function" then
        return nil
    end

    return target
end

local function SafeGetScale(frame)
    if frame and type(frame.GetEffectiveScale) == "function" then
        local scale = frame:GetEffectiveScale()
        if type(scale) == "number" and scale > 0 then
            return scale
        end
    end
    return 1
end

local function CanMeasureFrame(frame)
    if not frame then
        return false
    end

    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end

    return true
end

local function SafeGetRect(frame)
    if not CanMeasureFrame(frame) then
        return nil, nil, nil, nil
    end

    if type(frame.GetLeft) ~= "function"
        or type(frame.GetRight) ~= "function"
        or type(frame.GetTop) ~= "function"
        or type(frame.GetBottom) ~= "function" then
        return nil, nil, nil, nil
    end

    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    if type(left) ~= "number" then
        return nil, nil, nil, nil
    end

    if issecretvalue and (issecretvalue(left) or issecretvalue(right) or issecretvalue(top) or issecretvalue(bottom)) then
        return nil, nil, nil, nil
    end

    if type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then
        return nil, nil, nil, nil
    end

    return left, right, top, bottom
end

local function ResolvePointPosition(frame, point)
    if not frame then
        return nil, nil
    end

    local normalizedPoint = NormalizePoint(point, "CENTER")
    local left, right, top, bottom = SafeGetRect(frame)
    local centerX, centerY = type(frame.GetCenter) == "function" and frame:GetCenter() or nil, nil
    if type(frame.GetCenter) == "function" then
        centerX, centerY = frame:GetCenter()
    end

    local x = centerX
    if normalizedPoint:find("LEFT", 1, true) then
        x = left
    elseif normalizedPoint:find("RIGHT", 1, true) then
        x = right
    elseif not x and left and right then
        x = (left + right) / 2
    end

    local y = centerY
    if normalizedPoint:find("TOP", 1, true) then
        y = top
    elseif normalizedPoint:find("BOTTOM", 1, true) then
        y = bottom
    elseif not y and top and bottom then
        y = (top + bottom) / 2
    end

    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then
        return nil, nil
    end

    return x, y
end

local function SyncGridWidget(moduleKey, widgetKey, value, rangeInfo)
    if type(widgetKey) ~= "string" or widgetKey == "" then
        return
    end

    local Grid = _G.ExwindGrid
    if not Grid or type(Grid.Widgets) ~= "table" then
        return
    end
    if not ExwindTools.UI or ExwindTools.UI.CurrentModule ~= moduleKey then
        return
    end

    local widget = Grid.Widgets[widgetKey]
    if not widget then
        return
    end

    if type(value) == "boolean" then
        if widget.SetChecked then
            widget:SetChecked(value)
        end
        return
    end

    if type(value) == "string" then
        local editBox = widget.editBox or widget
        if editBox and editBox.SetText then
            editBox:SetText(value)
        end
        return
    end

    if type(value) ~= "number" then
        return
    end

    if rangeInfo and widget.Init then
        local minValue = tonumber(rangeInfo.min)
        local maxValue = tonumber(rangeInfo.max)
        local stepValue = tonumber(rangeInfo.step) or 1
        if minValue and maxValue and maxValue ~= minValue then
            widget:Init(value, minValue, maxValue, (maxValue - minValue) / stepValue)
            return
        end
    end

    if widget.SetValue then
        widget:SetValue(value)
        if widget.ValueText then
            widget.ValueText:SetText(tostring(value))
        end
    end
end

-- 选择器写入锚点 DB 后，标准 AnchorGroup 内的输入框不在旧的 Grid.Widgets
-- 顶层索引中；只对当前显示的同模块容器走 Grid 已有的组合控件回读入口。
local function SyncActiveModuleContainer(moduleKey)
    local Grid = _G.ExwindGrid
    local ui = ExwindTools.UI
    if not Grid or not ui or ui.CurrentModule ~= moduleKey then
        return
    end

    local container = ui.ActivePageFrame
    if not container or type(Grid.RefreshContainerControlsFromDB) ~= "function" then
        return
    end

    Grid:RefreshContainerControlsFromDB(container)
end

-- One and only one post-anchor mutation path.  Standard modules must never
-- put RefreshContent/RefreshVisuals callbacks on their Anchor schema: that
-- created duplicate panel materialization and left Grid controls stale.
local function NotifyStandardAnchorContract(moduleKey, changedPath)
    local ui = ExwindTools.UI
    if not ui or type(ui.NotifyModuleValueChanged) ~= "function" then
        error("standard Anchor mutation requires EXUI NotifyModuleValueChanged", 2)
    end
    ui:NotifyModuleValueChanged(moduleKey, changedPath, "committed")
    SyncActiveModuleContainer(moduleKey)
end

function AnchorController:GetDB()
    local options = self.options
    if type(options.getDB) == "function" then
        local db = options.getDB(self)
        if type(db) == "table" then
            return db
        end
    end

    if type(options.db) == "table" then
        return options.db
    end

    return nil
end

function AnchorController:GetOffsetKeys()
    return self.options.offsetXKey, self.options.offsetYKey
end

function AnchorController:GetAnchorPoint(target)
    local options = self.options
    if type(options.getAnchorPoint) == "function" then
        return NormalizePoint(options.getAnchorPoint(self, target), options.anchorPoint or "CENTER")
    end
    return NormalizePoint(options.anchorPoint, "CENTER")
end

function AnchorController:GetRelativePoint(target)
    local options = self.options
    if type(options.getRelativePoint) == "function" then
        return NormalizePoint(options.getRelativePoint(self, target), options.relativePoint or "CENTER")
    end
    return NormalizePoint(options.relativePoint, "CENTER")
end

function AnchorController:GetAttachTargetPath()
    local db = self:GetDB()
    if not db then
        return nil
    end

    local key = self.options.attachTargetKey
    if type(key) ~= "string" or key == "" then
        return nil
    end

    return db[key]
end

function AnchorController:IsAttachEnabled()
    local db = self:GetDB()
    if not db then
        return false
    end

    local enabledKey = self.options.attachEnabledKey
    if type(enabledKey) ~= "string" or enabledKey == "" then
        return false
    end

    return db[enabledKey] == true
end

function AnchorController:ResolveAttachTarget()
    if not self:IsAttachEnabled() then
        return nil
    end

    local path = self:GetAttachTargetPath()
    return ResolveFramePath(path)
end

function AnchorController:GetResolvedTarget()
    return self:ResolveAttachTarget() or UIParent
end

function AnchorController:SyncWidgets(keys)
    local db = self:GetDB()
    if not db then
        return
    end

    local widgetRanges = self.options.widgetRanges or {}
    local widgetKeys = keys or self.options.syncWidgets or {
        self.options.offsetXKey,
        self.options.offsetYKey,
        self.options.attachEnabledKey,
        self.options.attachTargetKey,
    }

    for _, key in ipairs(widgetKeys) do
        if type(key) == "string" and key ~= "" then
            SyncGridWidget(self.options.moduleKey, key, db[key], widgetRanges[key])
        end
    end
end

function AnchorController:ApplyPosition()
    local frame = self.frame
    local db = self:GetDB()
    if not frame or not db or frame.isMoving then
        return false
    end

    local offsetXKey, offsetYKey = self:GetOffsetKeys()
    local offsetX = tonumber(db[offsetXKey]) or tonumber(self.options.defaultOffsetX) or 0
    local offsetY = tonumber(db[offsetYKey]) or tonumber(self.options.defaultOffsetY) or 0
    local target = self:GetResolvedTarget()
    local anchorPoint = self:GetAnchorPoint(target)
    local relativePoint = self:GetRelativePoint(target)
    if type(self.options.getAppliedOffsets) == "function" then
        local appliedOffsetX, appliedOffsetY = self.options.getAppliedOffsets(self, target, offsetX, offsetY)
        offsetX = tonumber(appliedOffsetX) or offsetX
        offsetY = tonumber(appliedOffsetY) or offsetY
    end
    -- 世界编辑预览可以有不对称的真实可见边界（例如计时条左侧 Atlas 链）。
    -- 这个偏移只把可拖 anchorFrame 的中心放到那份紧贴边界的几何中心；保存时会
    -- 反向扣除，故模块 DB 始终保持运行时内容的逻辑锚点，不能被编辑视觉污染。
    offsetX = offsetX + (self.editBoundsOffsetX or 0)
    offsetY = offsetY + (self.editBoundsOffsetY or 0)

    frame:ClearAllPoints()
    frame:SetPoint(anchorPoint, target, relativePoint, offsetX, offsetY)
    return true
end

function AnchorController:SavePosition()
    local frame = self.frame
    local db = self:GetDB()
    if not frame or not db then
        return false
    end

    local target = self:GetResolvedTarget()
    local anchorPoint = self:GetAnchorPoint(target)
    local relativePoint = self:GetRelativePoint(target)
    local anchorX, anchorY = ResolvePointPosition(frame, anchorPoint)
    local targetX, targetY = ResolvePointPosition(target, relativePoint)
    if not anchorX or not anchorY or not targetX or not targetY then
        return false
    end

    local anchorScale = SafeGetScale(frame)
    local targetScale = SafeGetScale(target)
    local offsetX = math.floor(((anchorX * anchorScale) - (targetX * targetScale)) / anchorScale)
    local offsetY = math.floor(((anchorY * anchorScale) - (targetY * targetScale)) / anchorScale)
    offsetX = offsetX - (self.editBoundsOffsetX or 0)
    offsetY = offsetY - (self.editBoundsOffsetY or 0)
    if type(self.options.normalizeSavedOffsets) == "function" then
        local normalizedOffsetX, normalizedOffsetY = self.options.normalizeSavedOffsets(self, target, offsetX, offsetY)
        offsetX = math.floor(tonumber(normalizedOffsetX) or offsetX)
        offsetY = math.floor(tonumber(normalizedOffsetY) or offsetY)
    end
    local offsetXKey, offsetYKey = self:GetOffsetKeys()

    if type(offsetXKey) == "string" and offsetXKey ~= "" then
        db[offsetXKey] = offsetX
    end
    if type(offsetYKey) == "string" and offsetYKey ~= "" then
        db[offsetYKey] = offsetY
    end

    self:SyncWidgets()
    if self.options._isStandardModuleAnchor then
        NotifyStandardAnchorContract(self.options.moduleKey, offsetXKey or offsetYKey or "anchor")
    elseif type(self.options.onPositionSaved) == "function" then
        self.options.onPositionSaved(self, offsetX, offsetY)
    end

    return true
end

-- 仅由唯一 ExwindEditMode.lua 在标准世界预览 materialize/release 时调用。它不是
-- 编辑模式状态机，也不拥有视觉；只让现有 anchorFrame 的命中矩形能够紧贴真实
-- aggregate bounds，同时保证拖后写入的仍是模块运行时的逻辑坐标。
function AnchorController:SetEditBoundsOffset(offsetX, offsetY)
    if type(offsetX) ~= "number" or type(offsetY) ~= "number" then
        error("SetEditBoundsOffset requires numeric offsets", 2)
    end
    self.editBoundsOffsetX = offsetX
    self.editBoundsOffsetY = offsetY
    self:ApplyPosition()
end

function AnchorController:StartFramePicker()
    if type(ExwindTools.StartFramePicker) ~= "function" then
        return false
    end

    local db = self:GetDB()
    if not db then
        return false
    end

    local targetKey = self.options.attachTargetKey
    if type(targetKey) ~= "string" or targetKey == "" then
        return false
    end

    local enabledKey = self.options.attachEnabledKey
    local prevTarget = db[targetKey]
    local prevEnabled = type(enabledKey) == "string" and db[enabledKey] or nil

    ExwindTools:StartFramePicker(
        function(name)
            db[targetKey] = name
            if type(enabledKey) == "string" and enabledKey ~= "" then
                db[enabledKey] = true
            end
            self:SyncWidgets({ targetKey, enabledKey })
            self:ApplyPosition()
            if self.options._isStandardModuleAnchor then
                NotifyStandardAnchorContract(self.options.moduleKey, targetKey)
            else
                SyncActiveModuleContainer(self.options.moduleKey)
                if type(self.options.onFramePicked) == "function" then
                    self.options.onFramePicked(self, name)
                end
            end
        end,
        function()
            db[targetKey] = prevTarget
            if type(enabledKey) == "string" and enabledKey ~= "" then
                db[enabledKey] = prevEnabled
            end
            self:SyncWidgets({ targetKey, enabledKey })
            if self.options._isStandardModuleAnchor then
                NotifyStandardAnchorContract(self.options.moduleKey, targetKey)
            else
                SyncActiveModuleContainer(self.options.moduleKey)
                if type(self.options.onFramePickCancelled) == "function" then
                    self.options.onFramePickCancelled(self)
                end
            end
        end
    )

    return true
end

-- =============================================================
-- 场景可见性（可选）：整个 Region 是否该显示，由 ExwindTools.State 驱动
-- 设计见 EXWIND-DEV/ExwindCore/编辑模式与锚点封装.md §3.7
-- 完全可选：不声明 options.scenarios / options.isActiveScenario 的模块不受任何影响，
-- 保持"一直显示"的现状行为（IsScenarioActive 默认返回 true，RefreshScenarioVisibility 直接跳过）。
-- =============================================================
function AnchorController:IsScenarioActive()
    local options = self.options
    if type(options.isActiveScenario) == "function" then
        return options.isActiveScenario(self) == true
    end

    if type(options.scenarios) ~= "table" or #options.scenarios <= 0 then
        return true -- 没声明场景条件，视为不限制
    end

    local currentType = ExwindTools.State and ExwindTools.State.InstanceType
    for _, scenario in ipairs(options.scenarios) do
        if currentType == scenario then
            return true
        end
    end
    return false
end

--- 用户手动覆盖开关（例如"始终显示，忽略场景限制"），DB 字段名由 options.scenarioOverrideKey 声明。
function AnchorController:IsScenarioOverridden()
    local key = self.options.scenarioOverrideKey
    if type(key) ~= "string" or key == "" then
        return false
    end
    local db = self:GetDB()
    return db ~= nil and db[key] == true
end

function AnchorController:RefreshScenarioVisibility()
    if not self.frame then
        return
    end

    local options = self.options
    if type(options.isActiveScenario) ~= "function"
        and (type(options.scenarios) ~= "table" or #options.scenarios <= 0) then
        return -- 未声明场景条件，完全不介入 frame 的显隐
    end

    -- 唯一编辑模式 Core 已启用输入时始终显示，方便拖动定位，忽略场景判断。
    if self.editInputEnabled then
        self.frame:Show()
        return
    end

    local active = self:IsScenarioActive() or self:IsScenarioOverridden()
    if active then
        self.frame:Show()
    else
        self.frame:Hide()
    end

    if type(options.onScenarioChanged) == "function" then
        options.onScenarioChanged(self, active)
    end
end

-- 编辑输入可以落在独立的 SelectionFrame 上：它只接收鼠标，真正移动和保存的
-- 始终是 controller.frame（模块语义锚点）。这样选择框可以扩到内容之外，却不会
-- 把可见范围反写进模块的运行时布局。
local EDIT_TARGET_SCRIPTS = {
    "OnDragStart",
    "OnDragStop",
    "OnMouseDown",
    "OnMouseUp",
    "OnUpdate",
    "OnHide",
}

local EDIT_DRAG_THRESHOLD = 1

function AnchorController:StartEditMove()
    local frame = self.frame
    if not self.editInputEnabled or not frame or frame.isMoving then
        return
    end

    frame.isMoving = true
    frame:StartMoving()
end

function AnchorController:DisarmEditMove(target)
    local arm = target and target.__ExwindAnchorControllerDragArm
    if not arm then
        return
    end
    target.__ExwindAnchorControllerDragArm = nil
    target:SetScript("OnUpdate", arm.previousOnUpdate)
end

function AnchorController:ArmEditMove(target)
    if not self.editInputEnabled or not target or type(GetCursorPosition) ~= "function" then
        return
    end
    self:DisarmEditMove(target)
    local cursorX, cursorY = GetCursorPosition()
    target.__ExwindAnchorControllerDragArm = {
        cursorX = cursorX,
        cursorY = cursorY,
        previousOnUpdate = target:GetScript("OnUpdate"),
    }
    target:SetScript("OnUpdate", function(frame, elapsed)
        local arm = frame.__ExwindAnchorControllerDragArm
        if not arm then
            return
        end
        if arm.previousOnUpdate then
            arm.previousOnUpdate(frame, elapsed)
        end
        if not self.editInputEnabled then
            self:DisarmEditMove(frame)
            return
        end
        local cursorX, cursorY = GetCursorPosition()
        if math.abs(cursorX - arm.cursorX) >= EDIT_DRAG_THRESHOLD
            or math.abs(cursorY - arm.cursorY) >= EDIT_DRAG_THRESHOLD then
            self:DisarmEditMove(frame)
            self:StartEditMove()
        end
    end)
end

function AnchorController:StopEditMove()
    local frame = self.frame
    if not frame or not frame.isMoving then
        return
    end

    frame.isMoving = false
    frame:StopMovingOrSizing()
    self:SavePosition()
    -- StartMoving 会把原有相对锚点变成拖动结束时的屏幕位置。保存偏移后必须
    -- 立即重新应用相对目标；否则自定义锚点会在本次编辑会话中停止跟随暴雪
    -- Edit Mode 移动的目标，直到下一次生命周期刷新才恢复。
    self:ApplyPosition()
end

function AnchorController:ClearEditInteractionTarget(target)
    if not target or target == self.frame then
        return
    end

    local state = target.__ExwindAnchorControllerEditTarget
    if not state or state.controller ~= self then
        return
    end

    self:DisarmEditMove(target)
    for _, scriptName in ipairs(EDIT_TARGET_SCRIPTS) do
        target:SetScript(scriptName, state.scripts[scriptName])
    end
    -- 独立 SelectionFrame 只在编辑态拥有拖动注册；退出后不保留任何命中。
    target:RegisterForDrag()
    if state.mouseEnabled then
        SetInteractive(target)
    else
        SetClickThrough(target)
    end
    target.__ExwindAnchorControllerEditTarget = nil
end

function AnchorController:BindEditInteractionTarget(target)
    if not target or target == self.frame then
        return
    end
    if type(target.SetScript) ~= "function" or type(target.RegisterForDrag) ~= "function" then
        error("SetEditInteraction target must be a Frame", 2)
    end

    local previous = target.__ExwindAnchorControllerEditTarget
    if previous and previous.controller ~= self then
        error("SetEditInteraction target is already owned by another AnchorController", 2)
    end
    if not previous then
        local scripts = {}
        for _, scriptName in ipairs(EDIT_TARGET_SCRIPTS) do
            scripts[scriptName] = target:GetScript(scriptName)
        end
        target.__ExwindAnchorControllerEditTarget = {
            controller = self,
            scripts = scripts,
            mouseEnabled = target.IsMouseEnabled and target:IsMouseEnabled() == true,
        }
    end

    SetInteractive(target)
    target:RegisterForDrag("LeftButton")
    target:SetScript("OnDragStart", function() end)
    target:SetScript("OnDragStop", function()
        self:DisarmEditMove(target)
        self:StopEditMove()
    end)
    target:SetScript("OnHide", function()
        self:DisarmEditMove(target)
        self:StopEditMove()
    end)
    target:SetScript("OnMouseDown", function(_, button)
        if self.editInputEnabled and button == "RightButton" and self.onEditRightClick then
            self.onEditRightClick()
        elseif self.editInputEnabled and button == "LeftButton" then
            self:ArmEditMove(target)
        end
    end)
    target:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            self:DisarmEditMove(target)
            self:StopEditMove()
        end
    end)
end

-- Core 在唯一编辑生命周期中调用这里。AnchorController 不注册模块、不判断编辑状态、
-- 不绘制覆盖层；它只给已经存在的整体 anchor 开关输入，并把右键交还 Core。
-- target 是可选的独立 SelectionFrame。省略时完整保持旧版 anchorFrame 输入行为。
function AnchorController:SetEditInteraction(enabled, onRightClick, target)
    local oldTarget = self.editInteractionTarget
    local newTarget = target or self.frame
    if newTarget and type(newTarget.EnableMouse) ~= "function" then
        error("SetEditInteraction target must be a Frame", 2)
    end

    if oldTarget and oldTarget ~= newTarget then
        self:ClearEditInteractionTarget(oldTarget)
    end

    self.editInputEnabled = enabled == true
    self.onEditRightClick = self.editInputEnabled and onRightClick or nil
    if self.editInputEnabled then
        self.editInteractionTarget = newTarget
        if newTarget == self.frame then
            SetInteractive(self.frame)
        else
            -- selection 独占输入；语义 anchor 继续只承担移动与保存，不能抢鼠标。
            SetClickThrough(self.frame)
            self:BindEditInteractionTarget(newTarget)
        end
    else
        self:DisarmEditMove(oldTarget or self.frame)
        self:ClearEditInteractionTarget(oldTarget)
        self.editInteractionTarget = nil
        SetClickThrough(self.frame)
    end
    self:RefreshScenarioVisibility()
end

function AnchorController:GetFrame()
    return self.frame
end

function AnchorController:Ensure()
    if self.frame then
        return self.frame
    end

    local options = self.options
    local frame = CreateFrame("Frame", options.frameName, options.parent or UIParent, options.frameTemplate)
    self.frame = frame
    frame.__ExwindAnchorController = self

    frame:SetSize(tonumber(options.initialWidth) or 1, tonumber(options.initialHeight) or 1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(options.clampedToScreen == true)
    if type(options.frameStrata) == "string" and options.frameStrata ~= "" then
        frame:SetFrameStrata(options.frameStrata)
    end
    if type(options.frameLevel) == "number" then
        frame:SetFrameLevel(options.frameLevel)
    end
    if options.fixedFrameStrata == true and frame.SetFixedFrameStrata then
        frame:SetFixedFrameStrata(true)
    end

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() end)
    frame:SetScript("OnDragStop", function()
        self:DisarmEditMove(frame)
        self:StopEditMove()
    end)
    frame:SetScript("OnHide", function()
        self:DisarmEditMove(frame)
        self:StopEditMove()
    end)
    frame:SetScript("OnMouseDown", function(_, button)
        if self.editInputEnabled and button == "RightButton" and self.onEditRightClick then
            self.onEditRightClick()
        elseif self.editInputEnabled and button == "LeftButton" then
            self:ArmEditMove(frame)
        end
    end)
    frame:SetScript("OnMouseUp", function(owner, button)
        if button == "LeftButton" then
            self:DisarmEditMove(frame)
            self:StopEditMove()
        end
    end)

    if type(options.onCreateFrame) == "function" then options.onCreateFrame(self, frame) end

    -- RegisterForDrag can restore mouse hit testing.  This must be the final
    -- initialization of a normal runtime anchor; edit mode enables input later.
    SetClickThrough(frame)

    self:ApplyPosition()

    if type(options.isActiveScenario) == "function" or type(options.scenarios) == "table" then
        ExwindTools:WatchState("InstanceType", options.moduleKey, function()
            self:RefreshScenarioVisibility()
        end)
        self:RefreshScenarioVisibility()
    end

    return frame
end

function ExwindTools:CreateAnchorController(options)
    if type(options) ~= "table" then
        error("CreateAnchorController: options must be table", 2)
    end
    if type(options.moduleKey) ~= "string" or options.moduleKey == "" then
        error("CreateAnchorController: moduleKey must be string", 2)
    end

    local controller = setmetatable({
        options = options,
        editInputEnabled = false,
        editBoundsOffsetX = 0,
        editBoundsOffsetY = 0,
        editInteractionTarget = nil,
        frame = nil,
    }, AnchorController)

    return controller
end

-- 标准模块锚点的唯一声明入口。它不接管业务 Frame，也不创建第二个拖动层；只把
-- AnchorController 与 Grid 的 anchorgroup 使用同一份 key/default/picker 合同。
-- Page 将第二返回值直接作为 anchorgroup opts，禁止再手写一份字段映射。
local EXUI = ExwindTools.UI
if EXUI then
    function EXUI:CreateStandardModuleAnchor(options)
        if type(options) ~= "table" then error("CreateStandardModuleAnchor: options must be table", 2) end
        if type(options.moduleKey) ~= "string" or options.moduleKey == "" then
            error("CreateStandardModuleAnchor: moduleKey must be string", 2)
        end
        if type(options.getDB) ~= "function" and type(options.db) ~= "table" then
            error("CreateStandardModuleAnchor: getDB or db is required", 2)
        end
        for _, keyName in ipairs({ "offsetXKey", "offsetYKey" }) do
            if type(options[keyName]) ~= "string" or options[keyName] == "" then
                error("CreateStandardModuleAnchor: " .. keyName .. " is required", 2)
            end
        end
        if options.allowCustomAttach ~= false then
            for _, keyName in ipairs({ "attachEnabledKey", "attachTargetKey" }) do
                if type(options[keyName]) ~= "string" or options[keyName] == "" then
                    error("CreateStandardModuleAnchor: " .. keyName .. " is required", 2)
                end
            end
        end
        for _, callbackName in ipairs({ "onPositionSaved", "onFramePicked", "onFramePickCancelled" }) do
            if options[callbackName] ~= nil then
                error("CreateStandardModuleAnchor owns " .. callbackName .. "; Core automatically notifies the module controller", 2)
            end
        end
        if type(EXUI.RegisterStandardAnchorDeclaration) ~= "function" then
            error("CreateStandardModuleAnchor requires ExwindPanelPreview contract registry", 2)
        end
        EXUI:RegisterStandardAnchorDeclaration(options.moduleKey, options)
        options._isStandardModuleAnchor = true
        local controller = ExwindTools:CreateAnchorController(options)
        local groupOptions = {
            bindRoot = true,
            offsetXKey = options.offsetXKey,
            offsetYKey = options.offsetYKey,
            defaultOffsetX = options.defaultOffsetX or 0,
            defaultOffsetY = options.defaultOffsetY or 0,
            allowCustomAttach = options.allowCustomAttach ~= false,
            attachEnabledKey = options.attachEnabledKey,
            attachTargetKey = options.attachTargetKey,
            onPickFrame = function() return controller:StartFramePicker() end,
        }
        return controller, groupOptions
    end
end
