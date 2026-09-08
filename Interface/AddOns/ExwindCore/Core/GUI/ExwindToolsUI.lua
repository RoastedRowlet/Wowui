-- =========================================================
-- ExwindTools UI v4.1 - 原生 Grid 引擎版
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local L = ExwindTools.L

-- 使用已存在的 EXUI（由 ExwindGUI.lua 和 ExwindGrid.lua 创建）
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI
_G.ExwindToolsUI = EXUI


-- =========================================================
-- 视觉主题配置
-- =========================================================
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
-- [Fix] 优先提取当前游戏的通用字体（适配用户手动改字体的情况）
-- [Fix] 强制使用系统默认字体 (GameFontNormal)，不再依赖自定义或第三方字体
local defaultFontPath = GameFontNormal:GetFont()
-- [Fix] 恢复变量定义以兼容现有代码的 50+ 处引用 (功能上已全部指向系统默认字体)
local msyh = defaultFontPath
local msyhbd = defaultFontPath


local THEME = {
    -- [v26.7 Style] Protocol 风格：低对比深色画布，强调色只用于状态和主操作。
    Background = { 0.035, 0.038, 0.055, 0.985 },
    Sidebar = { 0.045, 0.048, 0.065, 0.58 },
    Border = { 0.19, 0.18, 0.24, 0.74 },
    Primary = { 0.57, 0.49, 0.91 },
    Success = { 0.31, 0.78, 0.55 },
    Danger = { 0.91, 0.38, 0.47 },
    TextMain = { 0.94, 0.93, 0.97, 1 },
    TextSub = { 0.62, 0.60, 0.68, 1 },
    TextDim = { 0.40, 0.38, 0.46, 1 },
    CardBg = { 0.09, 0.09, 0.13, 0.72 },
    CardBgHover = { 0.13, 0.12, 0.18, 0.86 },
}

local UI_AMBIENT_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\UI\\EXWIND_ProtocolAmbient.png"

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
}

local BACKDROP_SIMPLE = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = nil,
}

local FRAME_BACKDROP_FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
}

-- =========================================================
-- 全局状态
-- =========================================================
EXUI.MainFrame = nil    -- 原生 WoW Frame
EXUI.SidebarFrame = nil -- 左侧导航滚动子容器
EXUI.SidebarSearchBox = nil
EXUI.RightPanel = nil   -- 右侧内容容器
EXUI.SidebarPanel = nil -- 左侧导航的稳定 root（独立窗口与 Unified Shell 共用）
EXUI.SidebarScrollFrame = nil
EXUI.WorkspaceFrame = nil -- Unified Shell 中的 Tools 稳定工作区 root；不是旧窗口重父级化
EXUI.ShellHosts = nil
EXUI.ShellPanel = nil
EXUI.CurrentPage = "Home"
EXUI.CurrentModule = nil
EXUI.ActivePageFrame = nil           -- 当前页面的 Frame (公开 API，EXBoss 等外部 addon 可写入)
EXUI._InternalPageFrame = nil        -- ExwindTools 内部专用，跟踪自身页面帧，不被外部覆写
EXUI.PendingRightScrollRestore = nil -- 通用右侧滚动容器刷新后需要恢复的滚动位置

-- =========================================================
-- 模块设置页 · 面板内嵌预览（ModulePreviewDock）
-- 设计见 EXWIND-DEV/ExwindCore/模块SOP标准.md §5.2
-- =========================================================
EXUI.ModulePreviewDock = nil        -- 顶部固定预览区 Frame，未注册预览渲染器的模块保持 1px 收起
EXUI.ModulePreviewDockHeight = 160  -- 有预览时的固定高度
ExwindTools.ModulePreviewRenderers = ExwindTools.ModulePreviewRenderers or {}

-- ExwindTools 的模块设置页预览画布唯一使用 #94A5FC。Unified Shell 的 Dock 也会
-- 被 EXAura/EXBoss 借用，因此只在 Tools 预览可见期间覆盖，并在释放时恢复宿主原色。
local MODULE_PREVIEW_DOCK_BACKGROUND = { 148 / 255, 165 / 255, 252 / 255, 1 }

local function SetToolsPreviewDockBackground(dock, useToolsBackground)
    if not dock or not dock.SetBackdropColor then return end

    if useToolsBackground then
        if not dock._exToolsPreviewDockOriginalBackground and dock.GetBackdropColor then
            local r, g, b, a = dock:GetBackdropColor()
            dock._exToolsPreviewDockOriginalBackground = { r, g, b, a }
        end
        dock:SetBackdropColor(unpack(MODULE_PREVIEW_DOCK_BACKGROUND))
        return
    end

    local original = dock._exToolsPreviewDockOriginalBackground
    if original then
        dock:SetBackdropColor(unpack(original))
        dock._exToolsPreviewDockOriginalBackground = nil
    end
end

--- 注册一个模块的"面板内嵌预览"渲染器。不注册的模块不受影响（ModulePreviewDock 保持收起，Grid 顶满全部区域）。
--- @param moduleKey string
--- @param renderer table 支持三个可选生命周期函数：
---   mount(dockFrame, ctx)   -- 首次为该模块显示预览时调用一次
---   update(dockFrame, ctx)  -- 每次刷新该模块设置页时调用
---   release(dockFrame, ctx) -- 切换到其它模块前调用，用于清理 mount 阶段创建的对象
--- ctx 字段：{ moduleKey = string, config = 该模块的 GetModuleDB 返回表 }
function ExwindTools:RegisterModulePreview(moduleKey, renderer)
    if type(moduleKey) ~= "string" or moduleKey == "" or type(renderer) ~= "table" then
        return
    end
    self.ModulePreviewRenderers[moduleKey] = renderer
end

-- 统一面板与独立窗口共用同一套预览 renderer 生命周期。Shell 模式下由 Shell
-- 负责 Dock 的可见性和内容区重排；独立窗口仍沿用旧的本地 Dock 行为。
function EXUI:SetModulePreviewDockVisible(visible, height)
    local dock = EXUI.ModulePreviewDock
    if not dock then return end

    if EXUI.ShellPanel and EXUI.ShellHosts then
        -- Unified Shell may supply a new hosts table when its workspace is reused.
        -- The preview session must mount into that exact Shell Dock; showing a
        -- different/stale Dock makes a successful Render invisible to the page.
        local shellDock = EXUI.ShellHosts.previewDock
        if shellDock ~= dock then
            error("[ExwindToolsUI] ModulePreviewDock is not the current Unified Shell previewDock", 2)
        end
        SetToolsPreviewDockBackground(shellDock, visible == true)
        EXUI.ShellPanel:SetPreviewDockVisible(visible == true, height or EXUI.ModulePreviewDockHeight)
        local shellHost = shellDock:GetParent()
        if visible == true and (not shellHost or not shellHost:IsShown() or not shellDock:IsShown() or (shellDock:GetHeight() or 0) < 1) then
            error("[ExwindToolsUI] Unified Shell previewDock was not made visible with a non-zero height", 2)
        end
        return
    end

    SetToolsPreviewDockBackground(dock, visible == true)
    dock:SetHeight(visible and (height or EXUI.ModulePreviewDockHeight) or 1)
    dock:SetShown(visible == true)
end

-- =========================================================
-- 设置页预览交互层
-- =========================================================
-- 只在 ModulePreviewDock 内创建透明 hitbox。它写回的是普通配置 x/y，随后由模块的
-- applyStyle 完整重排 Widget；不对 FontString / Texture / Cooldown / StatusBar 直接 SetPoint。
local function ResolvePreviewConfigPath(config, path)
    if type(config) ~= "table" or type(path) ~= "string" or path == "" then return nil, nil end
    local parent, key = config, nil
    for part in string.gmatch(path, "[^%.]+") do
        if key ~= nil then
            if type(parent[key]) ~= "table" then return nil, nil end
            parent = parent[key]
        end
        key = part
    end
    return parent, key
end

local function GetPreviewConfigValue(config, path)
    local parent, key = ResolvePreviewConfigPath(config, path)
    return parent and key and tonumber(parent[key]) or 0
end

local function SetPreviewConfigValue(config, path, value)
    local parent, key = ResolvePreviewConfigPath(config, path)
    if not parent or not key then return false end
    parent[key] = value
    return true
end

--- 创建设置页预览的局部拖动层。handles 使用 getRoot + position={x,y} 的结构化契约。
--- @param host Frame ModulePreviewDock
--- @param options table { moduleKey, getDB, getHandles, applyStyle, focusGrid }
function EXUI:CreatePreviewInteractionLayer(host, options)
    if not host or type(options) ~= "table" or type(options.getDB) ~= "function" or
        type(options.getHandles) ~= "function" or type(options.applyStyle) ~= "function" then
        return nil
    end

    local layer = { host = host, options = options, hitboxes = host._exPreviewInteractionHitboxes or {}, dragging = nil }
    host._exPreviewInteractionHitboxes = layer.hitboxes

    -- 预览命中框只存在于设置页画布。视觉状态参考 EXAura：悬停蓝色细框、按下金色高亮，
    -- 用纯 hitbox 自己的缩放反馈点击，不移动或缩放真实 Widget / FontString。
    local function SetHitboxVisual(hitbox, state)
        if not hitbox then return end
        hitbox._exPreviewVisualState = state
        hitbox:SetScale(state == "pressed" and 0.96 or 1)
        if state == "pressed" then
            hitbox:SetBackdropBorderColor(1, 0.82, 0.12, 0.98)
            hitbox:SetBackdropColor(1, 0.72, 0.08, 0.18)
        elseif state == "hover" then
            hitbox:SetBackdropBorderColor(0.35, 0.82, 1, 0.90)
            hitbox:SetBackdropColor(0.20, 0.66, 1, 0.08)
        else
            hitbox:SetBackdropBorderColor(0.35, 0.82, 1, 0)
            hitbox:SetBackdropColor(0.20, 0.66, 1, 0)
        end
    end

    local function StopDrag()
        local drag = layer.dragging
        if not drag then return end
        if drag.hitbox then
            drag.hitbox:SetScript("OnUpdate", nil)
            SetHitboxVisual(drag.hitbox, drag.hitbox._exPreviewHover and "hover" or "idle")
        end
        layer.dragging = nil
        -- A drag commits two real DB paths.  They use the same automatic value
        -- contract as Grid controls; the retired DatabaseChanged bus is never
        -- emitted from preview interaction code.
        EXUI:NotifyModuleValueChanged(options.moduleKey, drag.handle.position.x, "committed")
        EXUI:NotifyModuleValueChanged(options.moduleKey, drag.handle.position.y, "committed")
    end

    local function BeginDrag(hitbox, handle)
        local config = options.getDB()
        if type(config) ~= "table" then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = hitbox:GetEffectiveScale() or 1
        layer.dragging = {
            hitbox = hitbox,
            handle = handle,
            startCursorX = cursorX,
            startCursorY = cursorY,
            scale = scale,
            startX = GetPreviewConfigValue(config, handle.position.x),
            startY = GetPreviewConfigValue(config, handle.position.y),
        }
        SetHitboxVisual(hitbox, "pressed")
        hitbox:SetScript("OnUpdate", function()
            local drag = layer.dragging
            if not drag then return end
            if _G.IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                StopDrag()
                return
            end
            local currentX, currentY = GetCursorPosition()
            local offsetX = math.floor(drag.startX + (currentX - drag.startCursorX) / drag.scale + 0.5)
            local offsetY = math.floor(drag.startY + (currentY - drag.startCursorY) / drag.scale + 0.5)
            local db = options.getDB()
            if SetPreviewConfigValue(db, drag.handle.position.x, offsetX) then
                SetPreviewConfigValue(db, drag.handle.position.y, offsetY)
                options.applyStyle()
                -- 文字控件的 ApplyStyle 足以实时重排；图标簇等模块专属预览还需在
                -- 鼠标移动期间同步其覆盖层位置，不能等到 MouseUp 的状态通知。
                if type(options.onPreviewDrag) == "function" then
                    options.onPreviewDrag(drag.handle)
                end
                layer:Sync()
            end
        end)
    end

    local function GetHitbox(index)
        local hitbox = layer.hitboxes[index]
        if hitbox then return hitbox end
        hitbox = CreateFrame("Button", nil, host, "BackdropTemplate")
        hitbox:SetFrameStrata(host:GetFrameStrata())
        hitbox:SetFrameLevel(host:GetFrameLevel() + 100 + index)
        hitbox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        hitbox:SetBackdropBorderColor(0.35, 0.82, 1, 0)
        hitbox:SetBackdropColor(0.20, 0.66, 1, 0)
        hitbox:EnableMouse(true)
        hitbox:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
        layer.hitboxes[index] = hitbox
        return hitbox
    end

    function layer:Sync()
        local handles = options.getHandles() or {}
        table.sort(handles, function(a, b) return (tonumber(a.priority) or 0) < (tonumber(b.priority) or 0) end)
        local used = 0
        for _, handle in ipairs(handles) do
            local currentHandle = handle
            local root = type(handle.getRoot) == "function" and handle.getRoot() or nil
            local position = handle.position
            if root and root.IsShown and root:IsShown() and type(position) == "table" and position.x and position.y then
                used = used + 1
                local hitbox = GetHitbox(used)
                local offsetX, offsetY, width, height = 0, 0, root:GetWidth() or 18, root:GetHeight() or 18
                if type(handle.getPreviewHitBox) == "function" then
                    offsetX, offsetY, width, height = handle.getPreviewHitBox()
                end
                hitbox:ClearAllPoints()
                hitbox:SetSize(math.max(18, tonumber(width) or 18), math.max(18, tonumber(height) or 18))
                hitbox:SetPoint("CENTER", root, "CENTER", tonumber(offsetX) or 0, tonumber(offsetY) or 0)
                hitbox._exPreviewHandle = currentHandle
                hitbox:SetScript("OnEnter", function(self)
                    self._exPreviewHover = true
                    if not layer.dragging or layer.dragging.hitbox ~= self then
                        SetHitboxVisual(self, "hover")
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(currentHandle.label or currentHandle.id or L["预览部件"], 0.35, 0.82, 1)
                    GameTooltip:AddLine(L["左键拖动位置；右键定位设置"], 0.72, 0.88, 1)
                    GameTooltip:Show()
                end)
                hitbox:SetScript("OnLeave", function(self)
                    self._exPreviewHover = nil
                    if not layer.dragging or layer.dragging.hitbox ~= self then
                        SetHitboxVisual(self, "idle")
                    end
                    GameTooltip:Hide()
                end)
                hitbox:SetScript("OnMouseDown", function(self, button)
                    if button == "LeftButton" then
                        BeginDrag(hitbox, currentHandle)
                    elseif button == "RightButton" and type(options.focusGrid) == "function" then
                        options.focusGrid(currentHandle.gridKey)
                    end
                end)
                hitbox:SetScript("OnMouseUp", function(_, button)
                    if button == "LeftButton" then StopDrag() end
                end)
                SetHitboxVisual(hitbox, hitbox._exPreviewHover and "hover" or "idle")
                hitbox:Show()
            end
        end
        for index = used + 1, #layer.hitboxes do
            local hitbox = layer.hitboxes[index]
            hitbox:SetScript("OnUpdate", nil)
            hitbox:SetScript("OnEnter", nil)
            hitbox:SetScript("OnLeave", nil)
            hitbox._exPreviewHover = nil
            SetHitboxVisual(hitbox, "idle")
            hitbox:Hide()
        end
    end

    function layer:Release()
        StopDrag()
        for _, hitbox in ipairs(self.hitboxes) do
            hitbox:SetScript("OnUpdate", nil)
            hitbox:SetScript("OnMouseDown", nil)
            hitbox:SetScript("OnMouseUp", nil)
            hitbox:SetScript("OnEnter", nil)
            hitbox:SetScript("OnLeave", nil)
            hitbox._exPreviewHover = nil
            SetHitboxVisual(hitbox, "idle")
            hitbox:Hide()
        end
    end

    layer:Sync()
    return layer
end

-- 预览右键必须由页面明确交出它正在显示的 ScrollFrame + ScrollChild。不能从
-- 当前全局 WidgetMap 猜同名 key：页面切换或另一容器完成 render 后会把焦点错误
-- 指到别的容器。模块仍只传语义 GUI target；Core 严格在该 container 的 state 中找。
function EXUI:FocusModuleGridKey(moduleKey, gridKey, scrollFrame, container)
    if type(moduleKey) ~= "string" or moduleKey == "" or type(gridKey) ~= "string" or gridKey == "" then
        return false
    end
    if not scrollFrame or type(scrollFrame.SetVerticalScroll) ~= "function" or not container then return false end
    local grid = _G.ExwindGrid
    if not grid or type(grid.ContainerStates) ~= "table" then return false end

    local function ResolveTarget()
        local state = grid.ContainerStates[container]
        if not state or state.moduleKey ~= moduleKey then return nil end
        local target = state.widgets and state.widgets[gridKey]
        local meta = target and state.widgetMap and state.widgetMap[target]
        if not target or not meta or not meta.item or meta.item.key ~= gridKey then return nil end
        -- Grid 顶层 widget 必须直接挂到它登记的 container；拒绝已回池、被页面
        -- 切换重新 parent 或来自其他 container 的同名对象。
        if type(target.GetParent) ~= "function" or target:GetParent() ~= container then return nil end
        return target
    end

    if not ResolveTarget() then return false end

    local function Reveal()
        local target = ResolveTarget()
        if not target or not target.GetTop then return end
        if scrollFrame and container and scrollFrame.SetVerticalScroll then
            local childTop, widgetTop = container:GetTop(), target:GetTop()
            if childTop and widgetTop then
                -- 预览右键的契约是“目标设置块位于可视区最上方”，不是只保证
                -- 可见或留一个任意边距。childTop - widgetTop 是该块在 ScrollChild
                -- 内的精确纵向偏移；ScrollFrame 会自行夹到可滚动范围。
                scrollFrame:SetVerticalScroll(math.max(0, childTop - widgetTop))
            end
        end

        local flash = target._exPreviewFocusFlash
        if not flash then
            flash = CreateFrame("Frame", nil, target, "BackdropTemplate")
            flash:SetAllPoints(target)
            flash:SetFrameLevel((target:GetFrameLevel() or 0) + 50)
            flash:EnableMouse(false)
            flash:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
            target._exPreviewFocusFlash = flash
        end
        flash:SetBackdropBorderColor(1, 0.82, 0.12, 1)
        flash:SetAlpha(1)
        flash:Show()
        local animation = flash._exPreviewFocusAnimation
        if not animation then
            animation = flash:CreateAnimationGroup()
            animation:SetLooping("REPEAT")
            local fadeOut = animation:CreateAnimation("Alpha")
            fadeOut:SetFromAlpha(1)
            fadeOut:SetToAlpha(0.2)
            fadeOut:SetDuration(0.32)
            fadeOut:SetOrder(1)
            local fadeIn = animation:CreateAnimation("Alpha")
            fadeIn:SetFromAlpha(0.2)
            fadeIn:SetToAlpha(1)
            fadeIn:SetDuration(0.32)
            fadeIn:SetOrder(2)
            flash._exPreviewFocusAnimation = animation
        end
        animation:Stop()
        animation:Play()
        C_Timer.After(1.2, function()
            if animation then animation:Stop() end
            if flash then flash:Hide() end
        end)
    end

    -- 等当前鼠标事件结束后再重新按同一 container 解析一次，确保坐标最新且
    -- 不会对页面切换后回池/改 parent 的旧目标操作。
    C_Timer.After(0, Reveal)
    return true
end

--- Panel Preview 的模块侧右键入口。当前页面在 Render 时已明确持有其
--- ScrollFrame 与 Grid container；模块不允许猜 WidgetMap，也无需保存页面私有 Frame。
function EXUI:FocusCurrentModuleGridKey(moduleKey, gridKey)
    if moduleKey ~= self.CurrentModule then return false end
    return self:FocusModuleGridKey(moduleKey, gridKey, self.ModuleScrollFrame, self.ActivePageFrame)
end

--- 通用预览控制器：把"游戏内编辑模式预览 + 设置面板内嵌预览"这套调度逻辑收进框架，
--- 模块只需要提供三个纯粹跟自己视觉构成有关的函数，不用重复手写 mount/update/release
--- 三个回调、也不用自己记得"设置变化时要重新套样式"这一步——2026-07-13 `ExClass.FocusCast.lua`
--- 就是漏了这一步导致"设置面板改字段不实时生效"，这个控制器从结构上让新模块不会再漏。
--- @param moduleKey string
--- @param options table
---   createInstance(parent) -> widget   必填。组出这个模块专属的可视 widget（可以是任意
---                                      EXUI Widget 组合），parent 是 anchorFrame 或 dockFrame。
---   applyStyle(widget)                 必填。读模块自己的 EX_DB，把样式套到 widget 上；
---                                      游戏内预览、面板预览、以及模块自己手动调用
---                                      重套已存在表面时都只调这一个函数，不重复实现。
---   releaseInstance(widget)            必填。清理 widget（一般就是 widget:Release()，
---                                      如果有额外的池化子对象/OnUpdate 也在这里一并处理）。
---   seedContent(widget)                可选。createInstance 之后立即调用一次，用来填充
---                                      预览专用的固定假数据（图标/文字/进度这类不随
---                                      EX_DB 变化的常量内容），跟 applyStyle 分开是因为
---                                      这部分不需要在重套表面时重复执行。
---   getDB() / getPreviewHandles(widget) 可选。两者同时提供时，设置页预览会为结构化
---                                      handles 创建局部拖动 hitbox；游戏世界预览不会创建。
--- @return table controller
---   controller:ShowGameWorldPreview(anchorFrame) -> widget  创建/复用游戏内预览实例并显示
---   controller:HideGameWorldPreview()                        释放游戏内预览实例
---   controller:IsGameWorldPreviewing() -> bool
function ExwindTools:CreatePreviewController(moduleKey, options)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error("CreatePreviewController: moduleKey must be string", 2)
    end
    if type(options) ~= "table" then
        error("CreatePreviewController: options must be table", 2)
    end
    if type(options.createInstance) ~= "function" then
        error("CreatePreviewController: options.createInstance must be function", 2)
    end
    if type(options.applyStyle) ~= "function" then
        error("CreatePreviewController: options.applyStyle must be function", 2)
    end
    if type(options.releaseInstance) ~= "function" then
        error("CreatePreviewController: options.releaseInstance must be function", 2)
    end

    local gameWorldWidget = nil
    local panelWidget = nil
    local panelInteraction = nil

    local function CreateAndSeed(parent)
        local widget = options.createInstance(parent)
        if widget and options.seedContent then
            options.seedContent(widget)
        end
        if widget then
            options.applyStyle(widget)
        end
        return widget
    end

    local controller = {}

    function controller:ShowGameWorldPreview(anchorFrame)
        if not anchorFrame then return nil end
        if gameWorldWidget then
            options.releaseInstance(gameWorldWidget)
            gameWorldWidget = nil
        end
        gameWorldWidget = CreateAndSeed(anchorFrame)
        if gameWorldWidget then
            if gameWorldWidget.SetAnchor then
                gameWorldWidget:SetAnchor("CENTER", anchorFrame, "CENTER")
            end
            if gameWorldWidget.Show then
                gameWorldWidget:Show()
            end
        end
        return gameWorldWidget
    end

    function controller:HideGameWorldPreview()
        if gameWorldWidget then
            options.releaseInstance(gameWorldWidget)
            gameWorldWidget = nil
        end
    end

    function controller:IsGameWorldPreviewing()
        return gameWorldWidget ~= nil
    end

    -- 供非 UnifiedPanel 的宿主（例如 EXBoss 的独立设置页）复用同一套内嵌预览生命周期。
    -- 同一个 controller 同时只允许挂载一个面板预览实例，避免对象池重复借用。
    function controller:MountPanelPreview(dockFrame)
        if panelWidget or not dockFrame then return panelWidget end
        panelWidget = CreateAndSeed(dockFrame)
        if panelWidget then
            if panelWidget.SetAnchor then
                panelWidget:SetAnchor("CENTER", dockFrame, "CENTER")
            end
            if panelWidget.Show then
                panelWidget:Show()
            end
            if type(options.getDB) == "function" and type(options.getPreviewHandles) == "function" then
                panelInteraction = EXUI:CreatePreviewInteractionLayer(dockFrame, {
                    moduleKey = moduleKey,
                    getDB = options.getDB,
                    getHandles = function() return options.getPreviewHandles(panelWidget) end,
                    applyStyle = function() options.applyStyle(panelWidget) end,
                    focusGrid = options.focusGrid,
                })
            end
        end
        return panelWidget
    end

    function controller:ReleasePanelPreview()
        if panelInteraction then
            panelInteraction:Release()
            panelInteraction = nil
        end
        if panelWidget then
            options.releaseInstance(panelWidget)
            panelWidget = nil
        end
    end

    function controller:GetPanelPreviewWidget()
        return panelWidget
    end

    ExwindTools:RegisterModulePreview(moduleKey, {
        mount = function(dockFrame)
            controller:MountPanelPreview(dockFrame)
        end,
        update = function()
            if panelWidget then
                options.applyStyle(panelWidget)
                if panelInteraction then panelInteraction:Sync() end
            end
        end,
        release = function()
            controller:ReleasePanelPreview()
        end,
    })

    return controller
end

local function NormalizeSidebarSearchText(text)
    local value = tostring(text or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function SidebarTextContains(haystack, needle)
    if haystack == nil or needle == "" then
        return false
    end

    return string.find(string.lower(tostring(haystack)), needle, 1, true) ~= nil
end

-- 与 EXBOSS 左侧导航一致的扁平搜索框。Tools 只复用视觉与交互状态，
-- 搜索结果仍由自己的导航树负责。
local function CreateSidebarSearchBox(parent, initialText, opts)
    local config = type(opts) == "table" and opts or {}
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetHeight(config.height or 26)
    if edit.SetAutoFocus then edit:SetAutoFocus(false) end
    if edit.SetFont then edit:SetFont(defaultFontPath, 14, "") end
    if edit.SetTextColor then edit:SetTextColor(0.90, 0.93, 0.98, 1) end
    if edit.SetCursorColor then edit:SetCursorColor(0.0, 0.72, 1.0) end
    if edit.SetTextInsets then edit:SetTextInsets(10, 10, 0, 0) end
    edit:SetBackdrop(FRAME_BACKDROP_FLAT)
    edit:SetBackdropColor(0.06, 0.07, 0.09, 0.96)
    edit:SetBackdropBorderColor(0.20, 0.22, 0.28, 1)

    local placeholder = EXUI:CreateVisualFontString(edit, EXFONTFRAME)
    placeholder:SetPoint("LEFT", 10, 0)
    placeholder:SetPoint("RIGHT", -10, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetFont(defaultFontPath, 14, "")
    placeholder:SetTextColor(0.45, 0.50, 0.58, 1)
    placeholder:SetText(config.placeholder or L["搜索..."])
    edit._placeholder = placeholder

    local function RefreshPlaceholder(self)
        self._placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end

    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.00, 0.72, 1.00, 0.95)
        RefreshPlaceholder(self)
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.20, 0.22, 0.28, 1)
        RefreshPlaceholder(self)
    end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        RefreshPlaceholder(self)
        if config.onChanged then config.onChanged(self:GetText(), userInput, self) end
    end)

    edit:SetText(initialText or "")
    RefreshPlaceholder(edit)
    return edit
end

local function ApplyModernScrollBarSkin(scrollFrame)
    if not scrollFrame then
        return
    end
    -- ScrollFrameTemplate owns the native MinimalScrollBar.  This compatibility
    -- helper intentionally does not create, replace, hide, or rebind it.
    scrollFrame:EnableMouseWheel(true)
end

local function ModuleMatchesSidebarSearch(meta, needle)
    if needle == "" then
        return true
    end

    return SidebarTextContains(meta.Name, needle)
        or SidebarTextContains(meta.Desc, needle)
        or SidebarTextContains(meta.Key, needle)
end

-- =========================================================
-- Toggle UI
-- =========================================================
function EXUI:Toggle()
    local unified = ExwindTools.UnifiedPanel
    local provider = unified and unified.Providers and unified.Providers.tools
    if provider and type(provider.Toggle) == "function" then
        provider:Toggle()
        return
    end

    if not EXUI.MainFrame then
        EXUI:CreateMainFrame()
    end
    if EXUI.MainFrame._embedHost then
        EXUI:ClearEmbedHost()
    end
    if EXUI.MainFrame:IsShown() then
        EXUI.MainFrame:Hide()
    else
        EXUI.MainFrame:Show()
        EXUI:RefreshContent()
        if ExwindTools.HandleChangelogPopupOnUIOpen then
            C_Timer.After(0.05, function()
                if EXUI.MainFrame and EXUI.MainFrame:IsShown() and ExwindTools.HandleChangelogPopupOnUIOpen then
                    ExwindTools:HandleChangelogPopupOnUIOpen()
                end
            end)
        end
    end
end

-- =========================================================
-- 创建主框架 (完全原生实现)
-- =========================================================
function EXUI:CreateMainFrame()
    -- 1. 创建主窗口
    local f = CreateFrame("Frame", "ExwindToolsMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(1200, 720)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    f:SetClampedToScreen(false)
    if f.SetPropagateKeyboardInput then
        f:SetPropagateKeyboardInput(true)
    end

    -- 主题效果
    f:SetBackdrop(FRAME_BACKDROP_FLAT)
    f:SetBackdropColor(unpack(THEME.Background))
    f:SetBackdropBorderColor(unpack(THEME.Border))

    -- [v26.7 Style] 原创环境光纹理只负责空间深度，不承载交互或内容。
    local ambient = EXUI:CreateVisualTexture(f, EXBACKGROUNDFRAME)
    ambient:SetAllPoints()
    ambient:SetTexture(UI_AMBIENT_TEXTURE)
    ambient:SetAlpha(0.34)
    f.AmbientTexture = ambient

    local ambientMask = EXUI:CreateVisualTexture(f, EXBACKGROUNDFRAME)
    ambientMask:SetAllPoints()
    ambientMask:SetColorTexture(0.018, 0.019, 0.03, 0.38)
    f.AmbientMask = ambientMask

    local topLine = EXUI:CreateVisualTexture(f, EXBASEFRAME)
    topLine:SetPoint("TOPLEFT", 1, -46)
    topLine:SetPoint("TOPRIGHT", -1, -46)
    topLine:SetHeight(1)
    topLine:SetColorTexture(0.48, 0.42, 0.70, 0.34)

    local bottomLine = EXUI:CreateVisualTexture(f, EXBASEFRAME)
    bottomLine:SetPoint("BOTTOMLEFT", 1, 44)
    bottomLine:SetPoint("BOTTOMRIGHT", -1, 44)
    bottomLine:SetHeight(1)
    bottomLine:SetColorTexture(0.28, 0.27, 0.35, 0.64)

    -- 拖拽逻辑
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if self.SetPropagateKeyboardInput then
                self:SetPropagateKeyboardInput(false)
            end
            self:Hide()
            return
        end

        if self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    f:HookScript("OnHide", function(self)
        if EXUI.MainFrame ~= self then return end
        EXUI:ReleaseModuleSettingsPage()
        EXUI:ReleaseMountedModulePreview()
    end)

    -- 装饰：标题区
    local title = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -15)
    title:SetText("|cffE9E4FFEXWINDTOOLS|r |cff8E899D/ " .. L["设置中心"] .. "|r")
    f.Title = title

    --底层显示
    local status = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 18, 15)
    status:SetText(string.format("|cff777283%s|r", string.format(L["版本: %s | 引擎: GRID %s"],
        ExwindTools.VERSION or "Unknown", ExwindTools.GridEngineVersion or "Unknown")))
    f.Status = status

    -- 暴雪原生关闭按钮
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    f.CloseButton = closeBtn -- 存储引用供皮肤模块直接获取

    EXUI.MainFrame = f

    -- 2. 创建子区域
    EXUI:CreateSidebar(f)
    EXUI:CreateRightPanel(f)

    -- 底部功能区
    local footer = CreateFrame("Frame", nil, f)
    footer:SetSize(850, 40)
    footer:SetPoint("BOTTOMRIGHT", -15, 10)

    local reloadBtn = EXUI:CreateSmallButton(footer, L["立即重载界面"], function()
        C_UI.Reload()
    end)
    reloadBtn:SetPoint("RIGHT", 0, -8)
    reloadBtn:SetSize(180, 26)

    -- [v4.7] 新增编辑模式快捷开关
    local editBtn = EXUI:CreateSmallButton(footer, EXUI:IsEditModeActive() and L["关闭编辑模式"] or L["启用编辑模式"], function()
        EXUI:ToggleEditMode()
        -- [优化] 如果开启了编辑模式，自动关闭设置面板，方便用户调整布局
        if EXUI:IsEditModeActive() and f:IsShown() then
            f:Hide()
        end
    end)
    editBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -10, 0)
    editBtn:SetSize(180, 26)
    EXUI.EditModeToggleButton = editBtn

    local changelogBtn = EXUI:CreateSmallButton(footer, L["更新日志"], function()
        if ExwindTools.ShowChangelog then
            ExwindTools:ShowChangelog({ markShown = true })
        end
    end)
    changelogBtn:SetPoint("RIGHT", editBtn, "LEFT", -10, 0)
    changelogBtn:SetSize(150, 26)
    EXUI.ChangelogButton = changelogBtn

    f:Hide()
end

-- =========================================================
-- 嵌入模式 (供 EXBoss 等宿主窗口把本插件整个界面画进自己的画布)
-- =========================================================
function EXUI:SetEmbedHost(hostFrame)
    if not hostFrame then return end
    -- 旧 EXBoss embed tab 尚未删除前仍可能调用这里。Unified 工作区已经是
    -- Shell 拥有的稳定 root，绝不可再被重父级化到旧面板；改为显式打开 Tools
    -- Provider，等 EXBoss Provider 迁移时再删除旧调用方。
    if EXUI.WorkspaceFrame then
        local unified = ExwindTools.UnifiedPanel
        if unified and unified.Providers and unified.Providers.tools then
            unified:Show("tools")
        end
        return false
    end
    if not EXUI.MainFrame then
        EXUI:CreateMainFrame()
    end
    local f = EXUI.MainFrame
    if f._embedHost ~= hostFrame then
        if not f._embedHost then
            f._standaloneParent = f:GetParent()
            f._standaloneStrata = f:GetFrameStrata()
            local point, relTo, relPoint, x, y = f:GetPoint(1)
            f._standalonePoint = { point, relTo, relPoint, x, y }
            f._standaloneW, f._standaloneH = f:GetSize()
        end
        f._embedHost = hostFrame
        f:ClearAllPoints()
        f:SetParent(hostFrame)
        f:SetFrameStrata(hostFrame:GetFrameStrata())
        f:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 0, 0)
        f:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", 0, 0)
        f:RegisterForDrag()
        f:EnableKeyboard(false)
        if f.Title then f.Title:Hide() end
        if f.CloseButton then f.CloseButton:Hide() end
    end
    f:Show()
    EXUI:RefreshContent()
end

function EXUI:ClearEmbedHost()
    if EXUI.WorkspaceFrame then
        return false
    end
    local f = EXUI.MainFrame
    if not f or not f._embedHost then return end
    f._embedHost = nil
    f:ClearAllPoints()
    f:SetParent(f._standaloneParent or UIParent)
    f:SetFrameStrata(f._standaloneStrata or "DIALOG")
    local pt = f._standalonePoint
    if pt and pt[1] then
        f:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
    else
        f:SetPoint("CENTER")
    end
    f:SetSize(f._standaloneW or 1200, f._standaloneH or 720)
    f:RegisterForDrag("LeftButton")
    f:EnableKeyboard(true)
    if f.Title then f.Title:Show() end
    if f.CloseButton then f.CloseButton:Show() end
    f:Hide()
end

-- =========================================================
-- 创建左侧导航栏
-- =========================================================
function EXUI:CreateSidebar(parent, options)
    options = options or {}
    local sidebar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if options.fillParent then
        sidebar:SetAllPoints(options.fillParent)
    else
        sidebar:SetWidth(258)
        sidebar:SetPoint("TOPLEFT", 1, -47)
        sidebar:SetPoint("BOTTOMLEFT", 1, 45)
    end
    sidebar:SetBackdrop(BACKDROP)
    sidebar:SetBackdropColor(0.06, 0.06, 0.08, 1)
    sidebar:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    -- [Style] 添加一条垂直分割线，区分侧边栏和内容区
    local vLine = EXUI:CreateVisualTexture(sidebar, EXBASEFRAME)
    vLine:SetPoint("TOPRIGHT", 0, 0)
    vLine:SetPoint("BOTTOMRIGHT", 0, 0)
    vLine:SetWidth(1)
    vLine:SetColorTexture(0.12, 0.15, 0.20, 0.9)

    local scrollFrame
    local searchBox = CreateSidebarSearchBox(sidebar, EXUI.SidebarState.SearchText or "", {
        placeholder = L["搜索模块..."],
        onChanged = function(text)
            local value = NormalizeSidebarSearchText(text)
            if EXUI.SidebarState.SearchText == value then
                return
            end

            EXUI.SidebarState.SearchText = value
            if scrollFrame and scrollFrame.SetVerticalScroll then
                scrollFrame:SetVerticalScroll(0)
            end
            if EXUI.SidebarFrame then
                EXUI:BuildNavigationTree(EXUI.SidebarFrame)
            end
        end,
    })
    searchBox:SetPoint("TOPLEFT", 0, -5)
    searchBox:SetPoint("TOPRIGHT", -22, -5)
    EXUI.SidebarSearchBox = searchBox

    scrollFrame = CreateFrame("ScrollFrame", "ExwindSidebarScroll", sidebar, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -38)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 5)
    ApplyModernScrollBarSkin(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(math.max(1, scrollFrame:GetWidth()), 1)
    scrollFrame:SetScrollChild(scrollChild)

    EXUI.SidebarPanel = sidebar
    EXUI.SidebarScrollFrame = scrollFrame
    EXUI.SidebarFrame = scrollChild
    EXUI:BuildNavigationTree(scrollChild)
end

-- =========================================================
-- [v4.6] Sidebar Redesign (Modern Tree View)
-- =========================================================
-- 侧边栏折叠状态与对象池
EXUI.SidebarState = { Expanded = { true, true, true, true, true }, SearchText = "" }
EXUI.SidebarPool = { Headers = {}, Items = {} }

local function GetTopNavColor(page)
    if page == "Home" then return 0.46, 0.76, 1.00 end
    if page == "LoadSettings" then return 0.47, 0.86, 0.66 end
    if page == "Diagnostic" then return 1.00, 0.70, 0.36 end
    if page == "ProfileManager" then return 0.77, 0.58, 1.00 end
    return 0.72, 0.78, 0.96
end

local function ApplySidebarItemLayout(btn, variant)
    btn.variant = variant or "module"
    if btn.variant == "topnav" then
        btn:SetHeight(28)
        btn.rail:Hide()
        btn.accent:Hide()
        btn.dot:Hide()
    else
        btn:SetHeight(24)
        btn.rail:Show()
        btn.accent:Show()
        btn.dot:Show()
    end
    btn.topnavAccent:Hide()
    btn.label:ClearAllPoints()
    if btn.variant == "topnav" then
        -- 快捷页不是模块树的子项：与分类标题共用左边线，并用整行轻底色
        -- 表达 hover/active，不能再伪装成带缩进的模块条目。
        btn.label:SetPoint("LEFT", 0, 0)
        btn.label:SetPoint("RIGHT", 0, 0)
    else
        btn.label:SetPoint("LEFT", 26, 0)
        btn.label:SetPoint("RIGHT", -10, 0)
    end
    btn.label:SetJustifyH("LEFT")
    btn.label:SetFont(defaultFontPath, btn.variant == "topnav" and 18 or 15, btn.variant == "topnav" and "OUTLINE" or "")
end

-- EXBOSS 左侧条目的唯一状态皮肤：无整行底色，仅保留轨道与蓝色选中线。
local function ApplySidebarModuleButtonState(btn, isActive, isEnabled)
    if not btn then return end
    btn.isActive = isActive == true
    btn.isEnabledState = (isEnabled ~= false)
    if btn.activeBg then btn.activeBg:SetAlpha(0) end
    if btn.topnavAccent then btn.topnavAccent:SetAlpha(0) end

    if btn.variant == "topnav" then
        local r, g, b = unpack(btn.topnavColor or { 0.72, 0.78, 0.96 })
        if btn.isActive then
            btn.label:SetTextColor(1, 1, 1, 1)
            btn.activeBg:SetColorTexture(r * 0.20, g * 0.20, b * 0.20, 0.96)
            btn.activeBg:SetAlpha(1)
        elseif btn._hovered then
            btn.label:SetTextColor(math.min(1, r * 1.22), math.min(1, g * 1.22), math.min(1, b * 1.22), 1)
            btn.activeBg:SetColorTexture(r * 0.13, g * 0.13, b * 0.13, 0.88)
            btn.activeBg:SetAlpha(1)
        else
            btn.label:SetTextColor(r, g, b, 1)
            btn.activeBg:SetColorTexture(r * 0.07, g * 0.07, b * 0.07, 0.62)
            btn.activeBg:SetAlpha(1)
        end
        return
    end

    if btn.isEnabledState == false then
        btn.label:SetTextColor(0.38, 0.42, 0.50, 1)
        btn.rail:SetColorTexture(0.18, 0.20, 0.24, 0.35)
        btn.accent:SetAlpha(0)
        btn.dot:SetTextColor(0.0, 0.72, 1.0, 0.0)
        return
    end

    if btn.isActive then
        btn.label:SetTextColor(0.92, 0.96, 1.00, 1)
        btn.rail:SetColorTexture(0.24, 0.29, 0.38, 0.25)
        btn.accent:SetAlpha(1)
        btn.dot:SetTextColor(0.0, 0.72, 1.0, 1.0)
        return
    end

    if btn._hovered then
        btn.label:SetTextColor(0.83, 0.88, 0.97, 1)
        btn.rail:SetColorTexture(0.34, 0.40, 0.52, 0.8)
    else
        btn.label:SetTextColor(0.57, 0.63, 0.75, 1)
        btn.rail:SetColorTexture(0.24, 0.29, 0.38, 0.55)
    end
    btn.accent:SetAlpha(0)
    btn.dot:SetTextColor(0.0, 0.72, 1.0, 0.0)
end

-- 对象池获取
function EXUI:GetSidebarObj(type, parent)
    local pool = EXUI.SidebarPool[type]
    for _, obj in ipairs(pool) do
        if not obj:IsShown() then
            obj:SetParent(parent)
            obj:Show()
            return obj
        end
    end
    -- 新建对象
    local obj
    if type == "Headers" then
        obj = EXUI:CreateCategoryHeaderBase(parent)
    elseif type == "Items" then
        obj = EXUI:CreateSidebarItemBase(parent)
    end
    table.insert(pool, obj)
    return obj
end

-- 创建分类标题头
function EXUI:CreateCategoryHeaderBase(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)

    btn.label = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    btn.label:SetPoint("LEFT", 0, 0)
    btn.label:SetPoint("RIGHT", 0, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetFont(defaultFontPath, 16, "OUTLINE")
    btn.label:SetTextColor(0.97, 0.98, 1.0, 0.98)

    btn:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.97, 0.98, 1.0, 0.98)
    end)

    return btn
end

-- 创建子项目按钮
function EXUI:CreateSidebarItemBase(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(24)

    btn.activeBg = EXUI:CreateVisualTexture(btn, EXBACKGROUNDFRAME)
    btn.activeBg:SetPoint("TOPLEFT", 0, -1)
    btn.activeBg:SetPoint("BOTTOMRIGHT", 0, 1)
    btn.activeBg:SetColorTexture(0, 0, 0, 0)
    btn.activeBg:SetAlpha(0)

    btn.rail = EXUI:CreateVisualTexture(btn, EXBACKGROUNDFRAME)
    btn.rail:SetPoint("TOPLEFT", 10, -2)
    btn.rail:SetPoint("BOTTOMLEFT", 10, 2)
    btn.rail:SetWidth(1)
    btn.rail:SetColorTexture(0.24, 0.29, 0.38, 0.55)

    btn.accent = EXUI:CreateVisualTexture(btn, EXBORDERFRAME)
    btn.accent:SetPoint("TOPLEFT", 10, -2)
    btn.accent:SetPoint("BOTTOMLEFT", 10, 2)
    btn.accent:SetWidth(1)
    btn.accent:SetColorTexture(0.0, 0.72, 1.0, 1.0)
    btn.accent:SetAlpha(0)

    btn.dot = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    btn.dot:SetFont(defaultFontPath, 15, "OUTLINE")
    btn.dot:SetPoint("CENTER", btn, "LEFT", 10, 0)
    btn.dot:SetText("")
    btn.dot:SetTextColor(0.0, 0.72, 1.0, 0.0)

    btn.topnavAccent = EXUI:CreateVisualTexture(btn, EXBASEFRAME)
    btn.topnavAccent:SetPoint("LEFT", 0, 0)
    btn.topnavAccent:SetSize(2, 18)
    btn.topnavAccent:Hide()

    btn.badge = EXUI:CreateVisualTexture(btn, EXBORDERFRAME)
    btn.badge:SetSize(64, 33)
    btn.badge:Hide()

    btn.label = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    btn.label:SetFont(defaultFontPath, 15, "")
    btn.label:SetPoint("LEFT", 26, 0)
    btn.label:SetPoint("RIGHT", -10, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetTextColor(0.57, 0.63, 0.75, 1)
    btn.label:SetWordWrap(false)

    btn:SetBackdrop(FRAME_BACKDROP_FLAT)
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    btn:SetScript("OnEnter", function(self)
        if self.isLoaded == false then return end
        self._hovered = true
        ApplySidebarModuleButtonState(self, self.isActive, self.isLoaded)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isLoaded == false then return end
        self._hovered = false
        ApplySidebarModuleButtonState(self, self.isActive, self.isLoaded)
    end)

    ApplySidebarItemLayout(btn, "module")
    return btn
end

local function UpdateSidebarItemBadge(btn, meta)
    if not btn or not btn.badge or not btn.label then return end

    btn.badge:Hide()
    ApplySidebarItemLayout(btn, btn.variant or "module")

    if meta and meta.new then
        local faction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
        local atlas = faction == "Alliance" and "NewCharacter-Alliance" or "NewCharacter-Horde"
        btn.badge:SetAtlas(atlas, false)
        btn.badge:ClearAllPoints()
        btn.badge:SetPoint("RIGHT", btn.label, "LEFT", 20, 0)
        btn.label:SetWidth(152)
        btn.badge:Show()
    end
end

-- 构建导航树 (核心逻辑)
function EXUI:BuildNavigationTree(parent)
    -- 1. 回收旧对象到池中 (Hide)
    if EXUI.SidebarPool.Headers then for _, v in ipairs(EXUI.SidebarPool.Headers) do v:Hide() end end
    if EXUI.SidebarPool.Items then for _, v in ipairs(EXUI.SidebarPool.Items) do v:Hide() end end

    local searchText = string.lower(NormalizeSidebarSearchText(EXUI.SidebarState.SearchText))
    local isSearching = searchText ~= ""
    local visibleModulesByCate = {}
    local totalVisibleModules = 0

    for _, meta in ipairs(ExwindTools.ModuleList) do
        if not meta.HideCfg and ModuleMatchesSidebarSearch(meta, searchText) then
            local cateId = meta.Category or 1
            visibleModulesByCate[cateId] = visibleModulesByCate[cateId] or {}
            visibleModulesByCate[cateId][#visibleModulesByCate[cateId] + 1] = meta
            totalVisibleModules = totalVisibleModules + 1
        end
    end

    local yOffset = -6

    -- 2. 静态导航项 (首页/载入/诊断/配置管理)
    local staticItems = {
        { name = L["首页概览"], page = "Home" },
        { name = L["模块管理"], page = "LoadSettings" },
        { name = L["状态诊断"], page = "Diagnostic" },
        { name = L["配置管理"], page = "ProfileManager" }
    }

    local function CreateItem(name, page, key, meta, variant)
        local btn = EXUI:GetSidebarObj("Items", parent)
        btn.page = page
        btn.moduleKey = key
        ApplySidebarItemLayout(btn, variant or "module")
        if btn.variant == "topnav" then
            local r, g, b = GetTopNavColor(page)
            btn.topnavColor = { r, g, b }
            btn.topnavAccent:SetColorTexture(r, g, b, 1)
        else
            btn.topnavColor = nil
        end
        UpdateSidebarItemBadge(btn, meta)

        -- [New] 检测模块是否已载入
        local isModule = (key ~= nil)
        local isLoaded = not isModule
        if isModule and ExwindTools.DB and ExwindTools.DB.LoadByKey then
            isLoaded = ExwindTools.DB.LoadByKey[key]
        end
        btn.isLoaded = isLoaded

        if isModule and not isLoaded then
            btn.label:SetText("|cff888888" .. name .. " (" .. L["未载入"] .. ")|r")
        else
            btn.label:SetText(name)
        end

        btn:SetPoint("TOPLEFT", 10, yOffset)
        btn:SetPoint("RIGHT", parent, "RIGHT", -8, 0)

        btn:SetScript("OnClick", function()
            -- [New] 未载入模块禁止点击切换
            if isModule and not isLoaded then return end

            -- [Fix] 增加延迟到 0.1s 以彻底断开执行栈，避免污染暴雪的 QuickJoinToast 更新
            C_Timer.After(0.1, function()
                EXUI.CurrentPage = page
                EXUI.CurrentModule = key
                EXUI:RefreshContent()
            end)
        end)

        yOffset = yOffset - (btn.variant == "topnav" and 30 or 26)
    end

    for _, info in ipairs(staticItems) do
        CreateItem(info.name, info.page, nil, nil, "topnav")
    end

    if EXUI.NavDivider then
        EXUI.NavDivider:Hide()
    end

    yOffset = yOffset - 8

    -- 3. 动态分类树
    local cateIds = {}
    for cateId in pairs(ExwindTools.Cate or {}) do
        if type(cateId) == "number" then
            cateIds[#cateIds + 1] = cateId
        end
    end
    table.sort(cateIds)

    for _, cateId in ipairs(cateIds) do
        local cateName = ExwindTools.Cate[cateId]
        local visibleModules = visibleModulesByCate[cateId]
        local shouldShowCategory = cateName and (not isSearching or (visibleModules and #visibleModules > 0))

        if shouldShowCategory then
            local header = EXUI:GetSidebarObj("Headers", parent)
            local isExpanded = true

            header.label:SetText(cateName)
            header:SetPoint("TOPLEFT", 10, yOffset)
            header:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
            header:SetScript("OnClick", nil)

            yOffset = yOffset - 24

            if isExpanded and visibleModules then
                for _, meta in ipairs(visibleModules) do
                    CreateItem(meta.Name, "ModuleSettings", meta.Key, meta, "module")
                end
                yOffset = yOffset - 6
            end
        end
    end

    if isSearching and totalVisibleModules == 0 then
        local emptyItem = EXUI:GetSidebarObj("Items", parent)
        emptyItem.page = nil
        emptyItem.moduleKey = nil
        emptyItem.isLoaded = true
        ApplySidebarItemLayout(emptyItem, "module")
        emptyItem.label:SetText("|cff888888" .. L["没有匹配的模块"] .. "|r")
        emptyItem:SetPoint("TOPLEFT", 10, yOffset)
        emptyItem:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        emptyItem:SetScript("OnClick", nil)
        UpdateSidebarItemBadge(emptyItem, nil)
        yOffset = yOffset - 26
    end

    parent:SetHeight(math.abs(yOffset) + 50)
    EXUI:UpdateNavButtonStates()
end

-- 更新侧边栏按钮选中状态
function EXUI:UpdateNavButtonStates()
    if not EXUI.SidebarFrame or not EXUI.SidebarPool.Items then return end

    for _, btn in ipairs(EXUI.SidebarPool.Items) do
        if btn:IsShown() and btn.page then
            local isActive = (btn.page == EXUI.CurrentPage and btn.moduleKey == EXUI.CurrentModule)
            ApplySidebarModuleButtonState(btn, isActive, btn.isLoaded)
        end
    end
end

-- =========================================================
-- 创建右侧普通 Frame 容器 (用于首页和载入页面)
-- =========================================================
function EXUI:CreateRightPanel(parent, options)
    options = options or {}
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if options.fillParent then
        panel:SetAllPoints(options.fillParent)
    else
        panel:SetPoint("TOPLEFT", 282, -47)
        panel:SetPoint("BOTTOMRIGHT", -18, 45)
    end
    -- 内容区是连续画布，页面各自决定信息分组；不再为整个区域套厚重卡片。
    panel:SetBackdrop(BACKDROP_SIMPLE)
    panel:SetBackdropColor(0.025, 0.027, 0.04, 0.22)

    -- [New] 通用滚动容器 (为所有普通页面提供滚动支持)
    local sf = CreateFrame("ScrollFrame", "ExwindCommonScroll", panel, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -12)
    sf:SetPoint("BOTTOMRIGHT", -15, 10)
    ApplyModernScrollBarSkin(sf)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(750, 1)
    sf:SetScrollChild(sc)

    EXUI.RightPanel = panel
    EXUI.RightScrollFrame = sf
    EXUI.RightScrollChild = sc
end

-- =========================================================
-- 同步滚动子容器宽度 (跟随实际容器宽度，独立开窗/嵌入EXBoss画布都适用)
-- =========================================================
function EXUI:SyncScrollChildWidths()
    if EXUI.SidebarScrollFrame and EXUI.SidebarFrame then
        local w = EXUI.SidebarScrollFrame:GetWidth()
        if w and w > 1 then EXUI.SidebarFrame:SetWidth(w) end
    end
    if EXUI.RightScrollFrame and EXUI.RightScrollChild then
        local w = EXUI.RightScrollFrame:GetWidth()
        if w and w > 1 then EXUI.RightScrollChild:SetWidth(w) end
    end
    if EXUI.ModuleScrollFrame and EXUI.ModuleScrollChild then
        local w = EXUI.ModuleScrollFrame:GetWidth()
        if w and w > 1 then EXUI.ModuleScrollChild:SetWidth(w) end
    end
end

-- =========================================================
-- Unified Shell 工作区
--
-- 这里创建的是 Tools 自己的稳定 root，再将 Sidebar / Content 直接绘制到
-- Shell 分配的 Nav / Content host。它不是 SetEmbedHost() 那种把旧独立窗口
-- 重父级化的“假嵌入”：旧窗口从未创建，业务页面继续使用原有 EXUI 状态与 renderer。
-- =========================================================
function EXUI:MountUnifiedWorkspace(hosts, shellPanel)
    if not hosts or not hosts.navHost or not hosts.contentHost or not hosts.contentBodyHost or not hosts.previewDock then
        error(L["[ExwindToolsUI] Unified Shell hosts 不完整"], 2)
    end

    if EXUI.WorkspaceFrame then
        EXUI.ShellHosts = hosts
        EXUI.ShellPanel = shellPanel
        EXUI.ModulePreviewDock = hosts.previewDock
        EXUI:RelayoutUnifiedWorkspace()
        return EXUI.WorkspaceFrame
    end

    -- 旧独立窗口一旦已经创建，其命名滚动框/子树不能安全地在同一会话复制。
    -- 标准入口会先注册 Provider，正常路径不会进入此分支；明确报错比静默重父级化安全。
    if EXUI.MainFrame then
        error(L["[ExwindToolsUI] 旧独立窗口已创建；请 /reload 后从 Unified Shell 打开"], 2)
    end

    local shellFrame = hosts.contentHost:GetParent()
    local root = CreateFrame("Frame", nil, shellFrame, "BackdropTemplate")
    root:SetPoint("TOPLEFT", hosts.navHost, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", hosts.contentHost, "BOTTOMRIGHT", 0, 0)
    root:SetFrameStrata(shellFrame:GetFrameStrata())
    root:EnableMouse(false)
    root:HookScript("OnHide", function(self)
        if EXUI.WorkspaceFrame ~= self then return end
        EXUI:ReleaseModuleSettingsPage()
        EXUI:ReleaseMountedModulePreview()
    end)

    EXUI.WorkspaceFrame = root
    EXUI.MainFrame = root -- 保留既有页面、皮肤和状态监听对“当前 UI root”的只读约定。
    EXUI.ShellHosts = hosts
    EXUI.ShellPanel = shellPanel

    EXUI:CreateSidebar(root, { fillParent = hosts.navHost })
    EXUI:CreateRightPanel(root, { fillParent = hosts.contentBodyHost })
    EXUI.ModulePreviewDock = hosts.previewDock
    EXUI:SyncScrollChildWidths()
    return root
end

function EXUI:RelayoutUnifiedWorkspace(metrics)
    local root, hosts = EXUI.WorkspaceFrame, EXUI.ShellHosts
    if not root or not hosts then return false end

    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", hosts.navHost, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", hosts.contentHost, "BOTTOMRIGHT", 0, 0)

    if EXUI.SidebarPanel then
        EXUI.SidebarPanel:ClearAllPoints()
        EXUI.SidebarPanel:SetAllPoints(hosts.navHost)
    end
    if EXUI.RightPanel then
        EXUI.RightPanel:ClearAllPoints()
        EXUI.RightPanel:SetAllPoints(hosts.contentBodyHost)
    end
    EXUI:SyncScrollChildWidths()

    local cols = metrics and metrics.splitGridCols
    if cols and _G.ExwindGrid and EXUI._InternalPageFrame then
        _G.ExwindGrid:SetContainerCols(EXUI._InternalPageFrame, cols)
    end
    return true
end

function EXUI:ShowUnifiedWorkspace()
    if not EXUI.WorkspaceFrame then return false end
    EXUI.WorkspaceFrame:Show()
    if EXUI.SidebarPanel then EXUI.SidebarPanel:Show() end
    if EXUI.RightPanel then EXUI.RightPanel:Show() end
    EXUI:SyncScrollChildWidths()
    return true
end

function EXUI:HideUnifiedWorkspace()
    if not EXUI.WorkspaceFrame then return false end
    EXUI:ReleaseModuleSettingsPage()
    EXUI:ReleaseMountedModulePreview()
    EXUI.WorkspaceFrame:Hide()
    return true
end

-- =========================================================
-- 模块设置页生命周期
--
-- PageCache 只缓存有限数量的页面 root；Grid 控件属于页面的动态内容。
-- 离开模块页时必须在 root Hide/SetParent(nil) 之前归还 Grid 实例，
-- 否则每个首次访问的模块都会长期占用一套 active pool widget。
-- =========================================================
function EXUI:ReleaseModuleSettingsPage(page)
    page = page or EXUI._InternalPageFrame
    if not page or not page._exGridPage then
        return false
    end

    local grid = _G.ExwindGrid
    if not grid then
        return false
    end

    -- Grid 编辑器的工具栏/浮层并不挂在页面 root 下；先正常退出该页的编辑会话，
    -- 再归还 widget，避免隐藏页面仍保留可操作的编辑器状态。
    if grid.IsLiveEditing and grid.LiveContainer == page then
        grid:ToggleLiveEdit(page)
        grid.LiveContainer = nil
    end

    grid:ReleaseContainerWidgets(page)

    -- Grid 之外由设置页直接创建的操作按钮同样不能被 PageCache root 强引用。
    -- 它们不是对象池控件，离页时解绑回调并脱离页面；下次进入时按当前模块状态重建。
    for _, child in ipairs({ page:GetChildren() }) do
        if child._exModuleSettingsTransient then
            child:SetScript("OnClick", nil)
            child:SetScript("OnEnter", nil)
            child:SetScript("OnLeave", nil)
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
    end

    return true
end

function EXUI:ReleaseMountedModulePreview()
    local dock = EXUI.ModulePreviewDock
    if not dock then
        return false
    end

    local mountedKey = dock._mountedModuleKey
    local definition = mountedKey and ExwindTools.ModuleDefinitions and ExwindTools.ModuleDefinitions[mountedKey]
    local renderer = mountedKey and ExwindTools.ModulePreviewRenderers[mountedKey]
    local central = mountedKey and type(EXUI.GetCentralModuleController) == "function"
        and EXUI:GetCentralModuleController(mountedKey) or nil
    if central then
        central:ReleasePanel()
    elseif definition then
        definition:ReleasePreview()
    elseif renderer and type(renderer.release) == "function" then
        -- 生命周期错误必须可见；不能用 pcall 吞掉后让旧预览继续残留。
        renderer.release(dock, {
            moduleKey = mountedKey,
            config = ExwindTools:GetModuleDB(mountedKey),
        })
    end

    dock._mountedModuleKey = nil
    EXUI:SetModulePreviewDockVisible(false)
    return mountedKey ~= nil
end

-- =========================================================
-- 刷新逻辑
-- =========================================================
function EXUI:RefreshContent()
    EXUI:SyncScrollChildWidths()

    local restoreRightScroll = EXUI.PendingRightScrollRestore
    EXUI.PendingRightScrollRestore = nil

    -- 设置切换标志
    EXUI.SwitchingModule = true

    -- 清理 ExwindTools 自身的旧页面帧 (与公开 ActivePageFrame 分离，避免误杀 EXBoss 等外部帧)
    if EXUI._InternalPageFrame then
        EXUI:ReleaseModuleSettingsPage(EXUI._InternalPageFrame)
        EXUI._InternalPageFrame:Hide()
        EXUI._InternalPageFrame:SetParent(nil)
        EXUI._InternalPageFrame = nil
    end
    EXUI.ActivePageFrame = nil

    -- 默认隐藏所有专用容器
    if EXUI.ModuleScrollFrame then EXUI.ModuleScrollFrame:Hide() end
    if EXUI.NoLayoutLabel then EXUI.NoLayoutLabel:Hide() end
    -- 离开 ModuleSettings 页（比如切到首页/加载设置）时，收起预览区并释放已挂载的渲染器
    if EXUI.CurrentPage ~= "ModuleSettings" and EXUI.ModulePreviewDock then
        EXUI:ReleaseMountedModulePreview()
    end

    -- 清除切换标志
    EXUI.SwitchingModule = nil
    -- [Fix] 防御性检查：如果 UI 还没初始化完整（RightPanel 为空），不执行刷新
    if not EXUI.RightPanel then return end

    -- 根据页面类型决定显示哪个滚动容器
    if EXUI.CurrentPage == "ModuleSettings" then
        -- ModuleSettings 使用自己独立的滚动容器 (ModuleScrollFrame)
        if EXUI.RightScrollFrame then EXUI.RightScrollFrame:Hide() end
        EXUI:ShowModuleSettingsPage()
    else
        -- 其他页面使用通用滚动容器
        if EXUI.RightScrollFrame then
            EXUI.RightScrollFrame:Show()
            if restoreRightScroll == nil then
                EXUI.RightScrollFrame:SetVerticalScroll(0)
            end
        end
        -- 显示对应页面
        if EXUI.CurrentPage == "Home" then
            EXUI.RightPanel:Show()
            EXUI:ShowHomePage()
        elseif EXUI.CurrentPage == "LoadSettings" then
            EXUI.RightPanel:Show()
            EXUI:ShowLoadSettingsPage()
        elseif EXUI.CurrentPage == "Diagnostic" then
            EXUI.RightPanel:Show()
            EXUI:ShowDiagnosticPage()
        elseif EXUI.CurrentPage == "ProfileManager" then
            EXUI.RightPanel:Show()
            EXUI:ShowProfileManagerPage()
        end

        -- [v4.8 Fix] 模块管理页启用/禁用刷新时保留滚动位置，避免跳回顶部
        if restoreRightScroll ~= nil and EXUI.RightScrollFrame and EXUI.RightScrollFrame:IsShown() then
            EXUI.RightScrollFrame:SetVerticalScroll(restoreRightScroll)
        end
    end

    EXUI:UpdateNavButtonStates()
end

-- 刷新右侧内容时保留当前通用滚动容器的位置（用于模块管理卡片刷新等场景）
function EXUI:RefreshContentKeepRightScroll()
    if EXUI.CurrentPage ~= "ModuleSettings" and EXUI.RightScrollFrame and EXUI.RightScrollFrame:IsShown() then
        EXUI.PendingRightScrollRestore = EXUI.RightScrollFrame:GetVerticalScroll() or 0
    end
    EXUI:RefreshContent()
end

function EXUI:RefreshContentKeepModuleScroll()
    if EXUI.CurrentPage == "ModuleSettings" and EXUI.ModuleScrollFrame and EXUI.ModuleScrollFrame:IsShown() then
        EXUI.PendingModuleScrollRestore = EXUI.ModuleScrollFrame:GetVerticalScroll() or 0
    end
    EXUI:RefreshContent()
end

-- =========================================================
-- 页面缓存 (Page Pooling)
-- =========================================================
EXUI.PageCache = {}

function EXUI:GetCachedPage(key, parent)
    -- 注意：这里的 parent 应该是 ScrollChild
    if not EXUI.PageCache[key] then
        local page = CreateFrame("Frame", nil, parent)
        -- page 高度由内容撑开，不应 SetAllPoints
        page:SetWidth(parent:GetWidth())
        page:SetPoint("TOPLEFT", 0, 0)
        EXUI.PageCache[key] = page
        page:Show()
        return page, true -- isNew = true
    end
    local page = EXUI.PageCache[key]
    page:SetParent(parent)
    page:SetWidth(parent:GetWidth())
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", 0, 0)
    page:Show()
    return page, false -- isNew = false
end

-- =========================================================
-- 首页
-- =========================================================

-- 确认弹窗（仅注册一次）
StaticPopupDialogs["EXWIND_CONFIRM_RESET"] = {
    text = L["确定要重置 ExwindTools 的所有配置并重载吗？\n|cffff4444此操作不可逆！|r"],
    button1 = L["确定重置"],
    button2 = L["取消"],
    OnAccept = function()
        ExwindTools:ResetAddonModuleStorage("TOOLS")
        C_UI.Reload()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EXWIND_CONFIRM_RESET_MODULE"] = {
    text = "%s",
    button1 = L["确定重置"],
    button2 = L["取消"],
    OnAccept = function(self, data)
        local moduleKey = data and data.moduleKey
        if not moduleKey then return end

        local db = ExwindTools:GetModuleDBStorage(moduleKey)
        if db and db.ModuleDB then
            db.ModuleDB[moduleKey] = nil
        end

        C_UI.Reload()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function EXUI:ShowHomePage()
    local page, isNew = EXUI:GetCachedPage("Home", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    if not isNew then
        if page.RefreshLocaleControls then
            page:RefreshLocaleControls()
        end
        EXUI.RightScrollChild:SetHeight(980)
        return
    end

    local FONT = ExwindTools.MAIN_FONT
    local HOME = {
        bg = { 0.045, 0.046, 0.065, 0.84 },
        panel = { 0.070, 0.070, 0.100, 0.80 },
        panel2 = { 0.052, 0.052, 0.077, 0.78 },
        line = { 0.30, 0.28, 0.37, 0.55 },
        gold = { 0.72, 0.65, 0.96, 1 },
        cyan = { 0.70, 0.67, 0.82, 1 },
        green = { 0.48, 0.78, 0.62, 1 },
        red = { 0.92, 0.45, 0.50, 1 },
        text = { 0.91, 0.90, 0.95, 1 },
        muted = { 0.57, 0.55, 0.64, 1 },
    }
    local CYAN = "|cffB7ACD1"
    local GOLD = "|cffB8A6F5"
    local GREY = "|cff888888"
    local SUPPORT_URL = "https://afdian.com/a/Exwind"
    -- 右侧通用滚动容器实际宽度约 750，这里留边距避免被裁切
    local W = math.min((page:GetWidth() or 750) - 30, 720)
    local PAGE_H = 980
    local COL_GAP = 14
    local COL_W = math.floor((W - COL_GAP) / 2)
    local INNER_W = COL_W - 42
    local localeItems = {
        { L["跟随客户端"], "AUTO" },
        { L["强制 zhCN"], "zhCN" },
        { L["强制 zhTW"], "zhTW" },
        { L["强制 enUS"], "enUS" },
    }

    local function GetLocaleModeLabel(mode)
        if mode == "zhCN" then
            return L["强制 zhCN"]
        elseif mode == "zhTW" then
            return L["强制 zhTW"]
        elseif mode == "enUS" then
            return L["强制 enUS"]
        end
        return L["跟随客户端"]
    end

    local function MakePanel(parent, w, h, point, rel, relPoint, x, y, bg, border)
        local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame:SetSize(w, h)
        frame:SetPoint(point, rel, relPoint, x, y)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(unpack(bg or HOME.panel))
        frame:SetBackdropBorderColor(unpack(border or HOME.line))
        return frame
    end

    local function Accent(frame, color)
        local c = color or HOME.gold
        local line = EXUI:CreateVisualTexture(frame, EXBASEFRAME)
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetVertexColor(c[1], c[2], c[3], 0.95)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        line:SetHeight(2)
        return line
    end

    local function Font(fs, size, color, flags)
        fs:SetFont(FONT, size or 14, flags or "")
        local c = color or HOME.text
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    local function Text(parent, text, size, color, point, rel, relPoint, x, y, w, flags)
        local fs = EXUI:CreateVisualFontString(parent, EXFONTFRAME)
        Font(fs, size, color, flags)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        if w then fs:SetWidth(w) end
        fs:SetText(text or "")
        fs:SetPoint(point or "TOPLEFT", rel or parent, relPoint or point or "TOPLEFT", x or 0, y or 0)
        return fs
    end

    local function MakeCopyBox(parent, label, value, color, width, height, fontSize)
        local c = color or HOME.cyan
        local title
        if label and label ~= "" then
            title = Text(parent, label, 12, HOME.muted, "TOPLEFT", parent, "TOPLEFT", 0, 0)
        end
        local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        box:SetSize(width or 360, height or 28)
        box:SetAutoFocus(false)
        box:SetMultiLine(false)
        box:SetTextInsets(10, 10, 0, 0)
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        box:SetBackdropColor(c[1] * 0.10, c[2] * 0.10, c[3] * 0.10, 0.92)
        box:SetBackdropBorderColor(c[1], c[2], c[3], 0.78)
        Font(box, fontSize or 13, HOME.text, "")
        box:SetText(tostring(value or ""))
        box:SetCursorPosition(0)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnMouseUp", function(self)
            self:SetFocus()
            self:HighlightText()
        end)
        return box, title
    end

    local function OpenCopyText(value)
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat(tostring(value or ""))
        else
            print(tostring(value or ""))
        end
    end

    local function MakeButton(parent, label, value, color, w, h, fontSize)
        local c = color or HOME.cyan
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(w or 168, h or 28)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        b:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.92)
        b:SetBackdropBorderColor(c[1], c[2], c[3], 0.78)
        b.text = EXUI:CreateVisualFontString(b, EXFONTFRAME)
        b.text:SetPoint("CENTER")
        Font(b.text, fontSize or 13, HOME.text, "OUTLINE")
        b.text:SetText(label)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropColor(c[1] * 0.24, c[2] * 0.24, c[3] * 0.24, 0.98)
            self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.92)
            self:SetBackdropBorderColor(c[1], c[2], c[3], 0.78)
        end)
        b:SetScript("OnClick", function()
            OpenCopyText(value)
        end)
        return b
    end

    local function SectionTitle(parent, title, sub, color)
        local t = Text(parent, title, 18, color or HOME.gold, "TOPLEFT", parent, "TOPLEFT", 16, -14, nil, "OUTLINE")
        if sub and sub ~= "" then
            local s = Text(parent, sub, 12, HOME.muted, "TOPLEFT", t, "BOTTOMLEFT", 0, -5)
            s:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, 0)
            return t, s
        end
        return t
    end

    local function MakeOpenExBossButton(parent)
        local b = EXUI:CreateSmallButton(parent, L["打开 EXBoss"], function()
        local panel = _G.ExBoss and _G.ExBoss.UI and _G.ExBoss.UI.Panel
        if not panel then
            return
        end
        if panel.SetTab then
            panel:SetTab("boss")
        end
        if EXUI.MainFrame then
            EXUI.MainFrame:Hide()
        end
        if panel.Show then
            panel:Show()
        elseif panel.Toggle then
            panel:Toggle()
        end
        end)
        return b
    end

    local hero = MakePanel(page, W, 168, "TOP", page, "TOP", 0, -18, HOME.bg, HOME.line)
    Accent(hero, HOME.gold)
    local title = Text(hero, "ExwindTools", 32, HOME.gold, "TOPLEFT", hero, "TOPLEFT", 24, -20, nil, "OUTLINE")
    Text(hero, L["零依赖 · 事件驱动 · State 订阅 · Grid 配置"], 14, HOME.text, "TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    Text(hero, L["模块管理用于启用/禁用功能；各模块配置页使用 Grid 面板实时调整。"], 13, HOME.muted, "TOPLEFT", title, "BOTTOMLEFT", 0, -38, W - 220)
    Text(hero, L["作者"] .. ": EXWIND", 13, HOME.cyan, "TOPLEFT", title, "BOTTOMLEFT", 0, -72)
    Text(hero, "Version " .. (ExwindTools.VERSION or "Unknown"), 13, HOME.muted, "TOPRIGHT", hero, "TOPRIGHT", -24, -24)
    local openExBossBtn = MakeOpenExBossButton(hero)
    openExBossBtn:SetSize(132, 28)
    openExBossBtn:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -24, -62)
    if openExBossBtn:GetFontString() then
        openExBossBtn:GetFontString():SetFont(FONT, 12, "OUTLINE")
    end

    local support = MakePanel(page, W, 190, "TOP", hero, "BOTTOM", 0, -16, HOME.panel2, HOME.line)
    Accent(support, HOME.gold)
    Text(support, L["赞助支持"], 28, HOME.gold, "TOPLEFT", support, "TOPLEFT", 22, -18, nil, "OUTLINE")
    Text(support, L["如果你觉得插件不错，可以小额赞助。"], 15, HOME.text, "TOPLEFT", support, "TOPLEFT", 22, -62, W - 44)
    Text(support, L["ExwindTools 和 EXBoss 是免费项目；赞助不会解锁额外功能，所有人使用同一版本。"], 12, HOME.muted, "TOPLEFT", support, "TOPLEFT", 22, -88, W - 44)
    local supportBox = MakeCopyBox(support, "", SUPPORT_URL, HOME.gold, W - 250, 38, 18)
    supportBox:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 22, 24)
    local supportBtn = MakeButton(support, L["复制赞助链接"], SUPPORT_URL, HOME.gold, 190, 38, 16)
    supportBtn:SetPoint("LEFT", supportBox, "RIGHT", 14, 0)
    Text(support, L["点击输入框可全选，按 Ctrl+C 复制链接。"], 11, HOME.muted, "BOTTOMLEFT", supportBox, "TOPLEFT", 0, 7)

    local cardRow = CreateFrame("Frame", nil, page)
    cardRow:SetSize(W, 410)
    cardRow:SetPoint("TOP", support, "BOTTOM", 0, -16)

    local infoPanel = MakePanel(cardRow, COL_W, 410, "TOPLEFT", cardRow, "TOPLEFT", 0, 0, HOME.panel, HOME.line)
    Accent(infoPanel, HOME.cyan)
    SectionTitle(infoPanel, L["信息与反馈"], L["遇到问题、配置建议或缺少选项都可以反馈。"], HOME.cyan)

    Text(infoPanel, L["网站"], 12, HOME.muted, "TOPLEFT", infoPanel, "TOPLEFT", 18, -78)
    local siteBox = MakeCopyBox(infoPanel, "", "exwind.net", HOME.cyan, INNER_W, 28, 13)
    siteBox:SetPoint("TOPLEFT", infoPanel, "TOPLEFT", 18, -100)

    Text(infoPanel, "BiliBili", 12, HOME.muted, "TOPLEFT", siteBox, "BOTTOMLEFT", 0, -22)
    Text(infoPanel, "EX-WIND " .. GREY .. "(" .. L["私信"] .. ")|r", 14, HOME.text, "TOPLEFT", siteBox, "BOTTOMLEFT", 0, -43)

    Text(infoPanel, L["NGA 链接"], 12, HOME.muted, "TOPLEFT", siteBox, "BOTTOMLEFT", 0, -78)
    local ngaBox = MakeCopyBox(infoPanel, "", "https://nga.178.com/read.php?tid=46217768", HOME.cyan, INNER_W, 28, 11)
    ngaBox:SetPoint("TOPLEFT", siteBox, "BOTTOMLEFT", 0, -100)
    Text(infoPanel, L["点击输入框可全选，按 Ctrl+C 复制链接"], 10, HOME.muted, "TOPLEFT", ngaBox, "BOTTOMLEFT", 0, -5)

    local actionPanel = MakePanel(cardRow, COL_W, 410, "TOPRIGHT", cardRow, "TOPRIGHT", 0, 0, HOME.panel, HOME.line)
    Accent(actionPanel, HOME.gold)
    SectionTitle(actionPanel, L["快捷操作"], L["这些操作会直接影响插件配置。"], HOME.gold)

    local localeDropdown = EXUI:CreateDropdown(
        actionPanel,
        188,
        L["界面语言"],
        localeItems,
        ExwindTools.GetLocaleMode and ExwindTools:GetLocaleMode() or "AUTO",
        function(value)
            if ExwindTools.SetLocaleMode then
                ExwindTools:SetLocaleMode(value)
            end
            if page.RefreshLocaleControls then
                page:RefreshLocaleControls()
            end
        end
    )
    localeDropdown:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 18, -82)

    local localeReloadBtn = EXUI:CreateSmallButton(actionPanel, L["立即重载界面"], function()
        C_UI.Reload()
    end)
    localeReloadBtn:SetSize(120, 26)
    localeReloadBtn:SetPoint("BOTTOMRIGHT", localeDropdown, "BOTTOMRIGHT", 122, 0)
    if localeReloadBtn:GetFontString() then
        localeReloadBtn:GetFontString():SetFont(FONT, 11, "OUTLINE")
    end

    local localeHint = Text(actionPanel, "", 11, HOME.muted, "TOPLEFT", localeDropdown, "BOTTOMLEFT", 0, -10, INNER_W)
    localeHint:SetWordWrap(true)
    local localeStatus = Text(actionPanel, "", 10, HOME.muted, "TOPLEFT", localeHint, "BOTTOMLEFT", 0, -6, INNER_W)
    localeStatus:SetWordWrap(true)

    page.LocaleDropdown = localeDropdown
    page.LocaleHint = localeHint
    page.LocaleStatus = localeStatus

    function page:RefreshLocaleControls()
        local localeMode = ExwindTools.GetLocaleMode and ExwindTools:GetLocaleMode() or "AUTO"
        local clientLocale = _G.ExwindLocale and _G.ExwindLocale.GetClientLocale and _G.ExwindLocale.GetClientLocale() or GetLocale()
        local effectiveLocale = ExwindTools.GetEffectiveLocale and ExwindTools:GetEffectiveLocale(localeMode) or clientLocale

        if self.LocaleDropdown then
            self.LocaleDropdown._currentValue = localeMode
            self.LocaleDropdown:SetText(GetLocaleModeLabel(localeMode))
        end

        if self.LocaleHint then
            self.LocaleHint:SetText(L["仅影响 Exwind 自身本地化文本；部分由游戏 API / 第三方库返回的内容不受影响。切换后建议立即重载界面。"])
        end

        if self.LocaleStatus then
            self.LocaleStatus:SetText(string.format(L["当前设置：%s | 客户端：%s | 当前生效：%s"], GetLocaleModeLabel(localeMode), clientLocale, effectiveLocale))
        end
    end
    page:RefreshLocaleControls()

    -- 小地图按钮隐藏开关是跨插件通用功能，已迁移到统一面板左下角"设置"入口
    -- (ExwindUnifiedPanel.lua 的 SettingsProvider)，不再在此处重复暴露。
    local tipHeader = Text(actionPanel, L["使用建议"], 13, HOME.gold, "TOPLEFT", localeStatus, "BOTTOMLEFT", 0, -20, nil, "OUTLINE")
    local tips = {
        L["模块管理页用于启用/禁用模块，变更后需 /reload 生效。"],
        L["进入模块设置页后可使用 Grid 面板调整样式、位置和功能开关。"],
        L["全局编辑模式命令: /ex edmode (用于拖动 HUD 位置)。"],
    }
    local lastTip = tipHeader
    for _, tip in ipairs(tips) do
        local fs = Text(actionPanel, "|cff9fb0c0•|r " .. tip, 12, HOME.text, "TOPLEFT", lastTip, "BOTTOMLEFT", 0, -8, INNER_W)
        lastTip = fs
    end

    local btnReset = CreateFrame("Button", nil, actionPanel, "BackdropTemplate")
    btnReset:SetSize(120, 24)
    btnReset:SetPoint("BOTTOMRIGHT", actionPanel, "BOTTOMRIGHT", -16, 16)
    btnReset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    btnReset:SetBackdropColor(0.35, 0.06, 0.06, 0.9)
    btnReset:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.9)

    local btnResetLabel = EXUI:CreateVisualFontString(btnReset, EXFONTFRAME)
    btnResetLabel:SetFont(FONT, 11, "OUTLINE")
    btnResetLabel:SetPoint("CENTER")
    btnResetLabel:SetText("|cffFF6666" .. L["重置设置"] .. "|r")

    btnReset:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.5, 0.08, 0.08, 0.95)
        self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end)
    btnReset:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.35, 0.06, 0.06, 0.9)
        self:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.9)
    end)
    btnReset:SetScript("OnClick", function()
        StaticPopup_Show("EXWIND_CONFIRM_RESET")
    end)

    local resetHint = Text(actionPanel, GREY .. L["RESET_HINT"] .. "|r", 10, HOME.muted, "BOTTOMLEFT", actionPanel, "BOTTOMLEFT", 18, 20, INNER_W - 110)

    local footerPanel = MakePanel(page, W, 84, "TOP", cardRow, "BOTTOM", 0, -16, HOME.bg, HOME.line)
    Accent(footerPanel, HOME.cyan)
    local footerText = Text(footerPanel, L["作者: Exwind  |  网站: exwind.net\n问题反馈: BiliBili(EX-WIND) / NGA"], 15, HOME.muted, "CENTER", footerPanel, "CENTER", 0, 0, W - 36)
    footerText:SetJustifyH("CENTER")
    footerText:SetWordWrap(true)

    page:SetHeight(PAGE_H)
    EXUI.RightScrollChild:SetHeight(PAGE_H)
end

-- =========================================================
-- Async Handler (单例，确保能取消之前的任务)
-- =========================================================
EXUI.AsyncHandler = LibStub("LibAsync"):GetHandler({
    type = "everyFrame",
    maxTime = 20, -- 增加一点每帧处理时间
    errorHandler = geterrorhandler()
})

-- =========================================================
-- 插件载入页面
-- =========================================================
local function ModuleHasSettingsPage(meta)
    -- 路由可见性只能由静态 ModuleList 决定。不能检查运行时 Layout/Controller：
    -- 被禁用模块会在注册设置页之前 return，若据此过滤就永远无法从管理页重新启用。
    return type(meta) == "table" and meta.HideCfg ~= true
end

-- 模块管理页图标。文件名使用完整模块键，避免不同产品出现同名模块时互相覆盖。
local MODULE_CARD_ICON_TEXTURES = {
    ["ExTools.MiniTools"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_MiniTools.png",
    ["ExTools.CombatTimer"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_CombatTimer.png",
    ["ExTools.CombatAlert"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_CombatAlert.png",
    ["ExTools.PlayerPosition"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_PlayerPosition.png",
    ["ExTools.ChatChannelBar"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_ChatChannelBar.png",
    ["ExTools.AutoBuy"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_AutoBuy.png",
    ["ExTools.GossipID"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_GossipID.png",
    ["ExTools.MicroMenu"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_MicroMenu.png",
    ["ExTools.RaidMarkerPanel"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_RaidMarkerPanel.png",
    ["ExTools.BattleResurrection"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_BattleResurrection.png",
    ["ExM+Info.MDTIconHook"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExMInfo_MDTIconHook.png",
    ["ExM+Info.MythicIcon"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExMInfo_MythicIcon.png",
    ["ExM+Info.TeleMsg"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExMInfo_TeleMsg.png",
    ["ExM+.MythicDamage"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExM_MythicDamage.png",
    ["ExTools.PveKeystoneInfo"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_PveKeystoneInfo.png",
    ["ExTools.PlayerHealAbsorb"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_PlayerHealAbsorb.png",
    ["ExTools.PlayerShield"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_PlayerShield.png",
    ["ExClass.FocusCast"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExClass_FocusCast.png",
    ["ExTools.SpellQueue"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_SpellQueue.png",
    ["ExClass.SpellEffectAlpha"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExClass_SpellEffectAlpha.png",
    ["ExTools.PlayerStats"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_PlayerStats.png",
    ["ExTools.YYSound"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_YYSound.png",
    ["ExTools.CastSequence"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_CastSequence.png",
    ["ExClass.RangeCheck"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExClass_RangeCheck.png",
    ["ExClass.NoMoveSkillAlert"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExClass_NoMoveSkillAlert.png",
    ["ExClass.BrewmasterStagger"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExClass_BrewmasterStagger.png",
    ["ExTools.TransformTimer"] = "Interface\\AddOns\\ExwindCore\\Textures\\LOGO\\ExTools_TransformTimer.png",
}

function EXUI:ShowLoadSettingsPage()
    -- 卡片必须按右侧滚动区域的最终宽度排版。页面首次打开时 ScrollChild
    -- 仍可能保留初始化宽度，先同步一次，避免三列只占左半边。
    EXUI:SyncScrollChildWidths()
    -- [Fix] 挂载到 ScrollChild
    local page, isNew = EXUI:GetCachedPage("LoadSettings", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    if isNew then
        local pageTitle = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        pageTitle:SetFont(defaultFontPath, 22, "OUTLINE")
        pageTitle:SetPoint("TOPLEFT", 20, -15)
        pageTitle:SetText(L["模块管理"])
        pageTitle:SetTextColor(unpack(THEME.TextMain))

        local hint = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        hint:SetFontObject("GameFontHighlight")
        hint:SetPoint("TOPLEFT", 20, -45)
        hint:SetText(L["按左侧路由分类管理模块；禁用立即生效，重新启用后需要 /reload。"])
        hint:SetTextColor(unpack(THEME.TextSub))

        local btnEnableAll = EXUI:CreateSmallButton(page, L["全部启用"], function()
            for _, meta in ipairs(ExwindTools.ModuleList) do
                if ModuleHasSettingsPage(meta) then ExwindTools:SetModuleEnabled(meta.Key, true) end
            end
            if page.cardsContainer then
                EXUI:RefreshModuleCardStates(page.cardsContainer)
            else
                EXUI:RefreshContentKeepRightScroll()
            end
        end)
        btnEnableAll:SetPoint("TOPRIGHT", -150, -12)

        local btnDisableAll = EXUI:CreateSmallButton(page, L["全部禁用"], function()
            for _, meta in ipairs(ExwindTools.ModuleList) do
                if ModuleHasSettingsPage(meta) then ExwindTools:SetModuleEnabled(meta.Key, false) end
            end
            if page.cardsContainer then
                EXUI:RefreshModuleCardStates(page.cardsContainer)
            else
                EXUI:RefreshContentKeepRightScroll()
            end
        end)
        btnDisableAll:SetPoint("TOPRIGHT", -20, -12)

        -- [Fix] 不再创建内部 ScrollFrame，直接使用 page 作为容器
        -- 用于挂载卡片的容器 (其实就是 page 本身)
        page.cardsContainer = CreateFrame("Frame", nil, page)
        page.cardsContainer:SetPoint("TOPLEFT", 15, -75)
        page.cardsContainer:SetPoint("BOTTOMRIGHT", -15, 0)
        page.cardsContainer:SetSize(720, 1) -- 初始高度
    end

    -- 刷新卡片列表
    if page.cardsContainer then
        EXUI.AsyncHandler:CancelAsync("ExwindTools_GenCards")
        for _, child in ipairs({ page.cardsContainer:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end
        -- 生成卡片并自适应高度
        EXUI:GenerateModuleCards(page.cardsContainer, function(contentHeight)
            page:SetHeight(contentHeight + 100)
            EXUI.RightScrollChild:SetHeight(page:GetHeight())
        end)
    end
end

-- 模块管理卡片：根据启用状态刷新视觉（避免整页刷新导致闪烁）
function EXUI:ApplyModuleCardState(card, isEnabled)
    if not card then return end
    local accent = card.CategoryAccent or THEME.Primary
    local pendingReload = isEnabled and ExwindTools.ModuleStatus[card._moduleKey] == "pending_reload"
    card:SetBackdropBorderColor(accent[1], accent[2], accent[3], isEnabled and 0.52 or 0.20)
    card:SetBackdropColor(0.060, 0.062, 0.088, isEnabled and 0.94 or 0.70)
    if card.Accent then
        card.Accent:SetColorTexture(accent[1], accent[2], accent[3], isEnabled and 0.95 or 0.30)
    end
    if card.IconMark then card.IconMark:SetAlpha(isEnabled and 1 or 0.38) end
    if card.IconArt then
        card.IconArt:SetDesaturated(not isEnabled)
        local brightness = isEnabled and 1 or 0.32
        card.IconArt:SetVertexColor(brightness, brightness, brightness, 1)
        card.IconArt:SetAlpha(isEnabled and 1 or 0.72)
    end
    if card.StatusDot then
        local color = pendingReload and { 0.93, 0.69, 0.31 } or (isEnabled and THEME.Success or THEME.Danger)
        card.StatusDot:SetTextColor(color[1], color[2], color[3], 1)
    end
    if card.StatusText then
        card.StatusText:SetText(pendingReload and L["待重载"] or (isEnabled and L["已启用"] or L["已禁用"]))
        local color = pendingReload and { 0.93, 0.69, 0.31 } or (isEnabled and THEME.Success or THEME.Danger)
        card.StatusText:SetTextColor(color[1], color[2], color[3], 1)
    end
    if card.SettingsBtn then
        local key = card._moduleKey
        local controller = type(EXUI.GetCentralModuleController) == "function" and EXUI:GetCentralModuleController(key) or nil
        local ready = isEnabled and (ExwindTools.RegisteredLayouts[key] ~= nil
            or (ExwindTools.ModuleDefinitions and ExwindTools.ModuleDefinitions[key] ~= nil)
            or controller ~= nil)
        card.SettingsBtn:SetEnabled(ready == true)
        card.SettingsBtn:SetAlpha(ready and 1 or 0.35)
    end
    if card.EnableBtnText then
        card.EnableBtnText:SetText(isEnabled and L["禁用"] or L["启用"])
        local actionColor = isEnabled and THEME.Danger or THEME.Success
        card.EnableBtnText:SetTextColor(actionColor[1], actionColor[2], actionColor[3], 1)
    end
end

function EXUI:RefreshModuleCardStates(container)
    if not container then return end
    for _, child in ipairs({ container:GetChildren() }) do
        if child._moduleKey then
            local isEnabled = ExwindTools.DB.LoadByKey[child._moduleKey] ~= false
            EXUI:ApplyModuleCardState(child, isEnabled)
        end
    end
end

-- [Update] 修改 GenerateModuleCards 以支持高度回调
function EXUI:GenerateModuleCards(parent, onComplete)
    local cardsPerRow, cardHeight = 3, 126
    local cardGap, rowGap, sectionGap = 12, 12, 18
    local xInset, headerHeight = 6, 28
    local contentWidth = tonumber(parent:GetWidth()) or 0
    local viewportWidth = EXUI.RightScrollFrame and tonumber(EXUI.RightScrollFrame:GetWidth()) or 0
    if viewportWidth > 1 then
        -- cardsContainer 相对页面左右各缩进 15。
        contentWidth = viewportWidth - 30
    end
    if contentWidth < 600 then contentWidth = 780 end
    local cardWidth = math.floor((contentWidth - xInset * 2
        - (cardsPerRow - 1) * cardGap) / cardsPerRow)

    local categoryPalette = {
        [1] = { 0.57, 0.49, 0.91 },
        [2] = { 0.28, 0.72, 0.90 },
        [3] = { 0.31, 0.78, 0.55 },
        [4] = { 0.93, 0.69, 0.31 },
        [5] = { 0.91, 0.38, 0.47 },
        [6] = { 0.44, 0.63, 0.95 },
    }
    local grouped = {}
    for _, meta in ipairs(ExwindTools.ModuleList) do
        if ModuleHasSettingsPage(meta) then
            local category = tonumber(meta.Category) or 1
            grouped[category] = grouped[category] or {}
            grouped[category][#grouped[category] + 1] = meta
        end
    end
    local categoryIDs = {}
    for category in pairs(grouped) do categoryIDs[#categoryIDs + 1] = category end
    table.sort(categoryIDs)

    local totalHeight = 8
    for _, category in ipairs(categoryIDs) do
        local rows = math.ceil(#grouped[category] / cardsPerRow)
        totalHeight = totalHeight + headerHeight + 8 + rows * cardHeight
            + math.max(0, rows - 1) * rowGap + sectionGap
    end
    parent:SetHeight(totalHeight)
    if onComplete then onComplete(totalHeight) end

    EXUI.AsyncHandler:Async(function()
        local cursorY, rendered = 5, 0
        for _, category in ipairs(categoryIDs) do
            if not parent:IsVisible() then return end
            local modules = grouped[category]
            local accent = categoryPalette[category] or THEME.Primary

            local header = CreateFrame("Frame", nil, parent)
            header:SetSize(contentWidth - xInset * 2, headerHeight)
            header:SetPoint("TOPLEFT", parent, "TOPLEFT", xInset, -cursorY)
            local rail = EXUI:CreateVisualTexture(header, EXBASEFRAME)
            rail:SetPoint("LEFT", 0, 0)
            rail:SetSize(3, 18)
            rail:SetColorTexture(accent[1], accent[2], accent[3], 1)
            local categoryTitle = EXUI:CreateVisualFontString(header, EXFONTFRAME)
            categoryTitle:SetFont(defaultFontPath, 17, "OUTLINE")
            categoryTitle:SetPoint("LEFT", rail, "RIGHT", 9, 0)
            categoryTitle:SetText((ExwindTools.Cate and ExwindTools.Cate[category]) or (L["分类"] .. " " .. category))
            categoryTitle:SetTextColor(unpack(THEME.TextMain))
            local categoryCount = EXUI:CreateVisualFontString(header, EXFONTFRAME)
            categoryCount:SetFont(defaultFontPath, 11, "")
            categoryCount:SetPoint("LEFT", categoryTitle, "RIGHT", 10, -1)
            categoryCount:SetText(string.format("%d %s", #modules, L["个模块"]))
            categoryCount:SetTextColor(unpack(THEME.TextDim))
            local line = EXUI:CreateVisualTexture(header, EXBASEFRAME)
            line:SetPoint("LEFT", categoryCount, "RIGHT", 12, 0)
            line:SetPoint("RIGHT", header, "RIGHT", 0, 0)
            line:SetHeight(1)
            line:SetColorTexture(accent[1], accent[2], accent[3], 0.18)

            cursorY = cursorY + headerHeight + 8
            for index, meta in ipairs(modules) do
                local moduleMeta, moduleKey = meta, meta.Key
                rendered = rendered + 1
                if rendered % 4 == 0 then coroutine.yield() end
                if not parent:IsVisible() then return end

                local row = math.floor((index - 1) / cardsPerRow)
                local col = (index - 1) % cardsPerRow
                local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
                card._moduleKey = moduleKey
                card.CategoryAccent = accent
                card:SetSize(cardWidth, cardHeight)
                card:SetPoint("TOPLEFT", parent, "TOPLEFT",
                    xInset + col * (cardWidth + cardGap), -cursorY - row * (cardHeight + rowGap))
                card:SetBackdrop(BACKDROP)

                local cardAccent = EXUI:CreateVisualTexture(card, EXBASEFRAME)
                cardAccent:SetPoint("TOPLEFT", 0, 0)
                cardAccent:SetPoint("BOTTOMLEFT", 0, 0)
                cardAccent:SetWidth(3)
                card.Accent = cardAccent

                local iconTile = CreateFrame("Frame", nil, card, "BackdropTemplate")
                iconTile:SetSize(48, 48)
                iconTile:SetPoint("TOPLEFT", 14, -15)
                iconTile:SetBackdrop(BACKDROP)
                iconTile:SetBackdropColor(accent[1] * 0.12, accent[2] * 0.12, accent[3] * 0.12, 0.96)
                iconTile:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.42)
                local iconTexturePath = MODULE_CARD_ICON_TEXTURES[moduleKey]
                if iconTexturePath then
                    local iconArt = EXUI:CreateVisualTexture(iconTile, EXBASEFRAME)
                    iconArt:SetPoint("TOPLEFT", 3, -3)
                    iconArt:SetPoint("BOTTOMRIGHT", -3, 3)
                    iconArt:SetTexture(iconTexturePath)
                    iconArt:SetTexCoord(0, 1, 0, 1)
                    card.IconArt = iconArt
                else
                    local iconMark = EXUI:CreateVisualFontString(iconTile, EXFONTFRAME)
                    iconMark:SetFont(defaultFontPath, 17, "OUTLINE")
                    iconMark:SetPoint("CENTER", 0, 0)
                    iconMark:SetText("EX")
                    iconMark:SetTextColor(accent[1], accent[2], accent[3], 1)
                    card.IconMark = iconMark
                end

                local nameText = EXUI:CreateVisualFontString(card, EXFONTFRAME)
                nameText:SetFont(defaultFontPath, 16, "OUTLINE")
                nameText:SetPoint("TOPLEFT", 76, -15)
                nameText:SetWidth(math.max(80, cardWidth - 168))
                nameText:SetJustifyH("LEFT")
                nameText:SetText(moduleMeta.Name or moduleKey)
                nameText:SetTextColor(unpack(THEME.TextMain))

                local statusDot = EXUI:CreateVisualFontString(card, EXFONTFRAME)
                statusDot:SetFont(defaultFontPath, 12, "OUTLINE")
                statusDot:SetPoint("TOPRIGHT", -72, -17)
                statusDot:SetText("●")
                card.StatusDot = statusDot
                local statusText = EXUI:CreateVisualFontString(card, EXFONTFRAME)
                statusText:SetFont(defaultFontPath, 11, "")
                statusText:SetPoint("LEFT", statusDot, "RIGHT", 4, 0)
                card.StatusText = statusText

                local descText = EXUI:CreateVisualFontString(card, EXFONTFRAME)
                descText:SetFont(defaultFontPath, 12, "")
                descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -7)
                descText:SetWidth(math.max(100, cardWidth - 90))
                descText:SetJustifyH("LEFT")
                descText:SetJustifyV("TOP")
                descText:SetWordWrap(true)
                descText:SetMaxLines(2)
                descText:SetText(moduleMeta.Desc or "")
                descText:SetTextColor(unpack(THEME.TextSub))

                local settingsBtn = EXUI:CreateSmallButton(card, L["设置"], function()
                    EXUI.CurrentPage = "ModuleSettings"
                    EXUI.CurrentModule = moduleKey
                    EXUI:RefreshContent()
                end)
                settingsBtn:SetSize(84, 25)
                settingsBtn:SetPoint("BOTTOMLEFT", 76, 12)
                card.SettingsBtn = settingsBtn

                local enableBtn = EXUI:CreateSmallButton(card, "", function()
                    local currentEnabled = ExwindTools.DB.LoadByKey[moduleKey] ~= false
                    local newEnabled = not currentEnabled
                    ExwindTools:SetModuleEnabled(moduleKey, newEnabled)
                    EXUI:ApplyModuleCardState(card, newEnabled)
                end)
                card.EnableBtn = enableBtn
                card.EnableBtnText = enableBtn.Label
                enableBtn:SetSize(84, 25)
                enableBtn:SetPoint("BOTTOMRIGHT", -14, 12)

                EXUI:ApplyModuleCardState(card, ExwindTools.DB.LoadByKey[moduleKey] ~= false)
            end

            local rows = math.ceil(#modules / cardsPerRow)
            cursorY = cursorY + rows * cardHeight + math.max(0, rows - 1) * rowGap + sectionGap
        end
    end, "ExwindTools_GenCards")
end

-- =========================================================
-- 模块设置页面 (ExwindGrid Layout)
-- 使用原生 Grid 布局引擎渲染
-- =========================================================
function EXUI:ShowModuleSettingsPage()
    if not EXUI.CurrentModule then
        EXUI:ReleaseMountedModulePreview()
        return
    end

    local moduleMeta = nil
    for _, meta in ipairs(ExwindTools.ModuleList) do
        if meta.Key == EXUI.CurrentModule then
            moduleMeta = meta
            break
        end
    end
    if not moduleMeta then
        EXUI:ReleaseMountedModulePreview()
        return
    end

    EXUI.SwitchingModule = true

    -- 现有 ModuleDefinition / legacy layout 与 Central basicIcon 是三条显式
    -- 路线；Central 不会被包装或回退进前两者。
    local definition = ExwindTools.ModuleDefinitions and ExwindTools.ModuleDefinitions[EXUI.CurrentModule]
    local centralController = type(EXUI.GetCentralModuleController) == "function"
        and EXUI:GetCentralModuleController(EXUI.CurrentModule) or nil
    local layoutData = centralController and centralController:BuildGridLayout()
        or (definition and definition:GetLayout() or ExwindTools.RegisteredLayouts[EXUI.CurrentModule])
    if layoutData and _G.ExwindGrid then
        EXUI.RightPanel:Show()
        -- [Fix] 这里的 MainFrame 就是原生 Frame 了，不再需要 .frame
        EXUI.RightPanel:SetFrameLevel(EXUI.MainFrame:GetFrameLevel() + 10)

        if not EXUI.ModulePreviewDock then
            -- 顶部固定预览区：不参与滚动，未注册渲染器的模块保持 1px 收起，不占布局空间
            local dock = CreateFrame("Frame", "ExwindModulePreviewDock", EXUI.RightPanel, "BackdropTemplate")
            dock:SetPoint("TOPLEFT", EXUI.RightPanel, "TOPLEFT", 0, -5)
            dock:SetPoint("TOPRIGHT", EXUI.RightPanel, "TOPRIGHT", -25, -5)
            dock:SetHeight(1)
            dock:SetBackdrop(BACKDROP_SIMPLE)
            EXUI.ModulePreviewDock = dock
        end

        if not EXUI.ModuleScrollFrame then
            -- 原生细滚动条由 ScrollFrameTemplate 自动创建并管理。
            EXUI.ModuleScrollFrame = CreateFrame("ScrollFrame", "ExwindModuleGridScroll", EXUI.RightPanel,
                "ScrollFrameTemplate")
            -- [Fix] 顶部锚点改挂在 ModulePreviewDock 的底部，而不是直接贴 RightPanel 顶部，
            -- 这样预览区高度变化（0 或 ModulePreviewDockHeight）会自动带动 Grid 区域跟着收缩/展开。
            EXUI.ModuleScrollFrame:SetPoint("TOPLEFT", EXUI.ModulePreviewDock, "BOTTOMLEFT", 0, 0)
            EXUI.ModuleScrollFrame:SetPoint("TOPRIGHT", EXUI.ModulePreviewDock, "BOTTOMRIGHT", 0, 0)
            EXUI.ModuleScrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
            ApplyModernScrollBarSkin(EXUI.ModuleScrollFrame)

            local child = CreateFrame("Frame", nil, EXUI.ModuleScrollFrame)
            child:SetSize(750, 1)
            EXUI.ModuleScrollFrame:SetScrollChild(child)
            EXUI.ModuleScrollChild = child
            EXUI:SyncScrollChildWidths()
        end
        EXUI.ModuleScrollFrame:Show()
        if EXUI.PendingModuleScrollRestore ~= nil then
            EXUI.ModuleScrollFrame:SetVerticalScroll(EXUI.PendingModuleScrollRestore)
        else
            EXUI.ModuleScrollFrame:SetVerticalScroll(0)
        end

        -- 先确定 Dock 的占位高度和旧预览的释放时机。标准 PreviewSurface 的
        -- mount/update 必须等待下方当前模块 Grid 完成 Render：它们会同步读取
        -- Grid 的 active ContainerState，不能读取切换前模块留下的状态。
        local previewRenderer = nil
        local previewContext = nil
        do
            local dock = EXUI.ModulePreviewDock
            local previousKey = dock._mountedModuleKey
            if previousKey and previousKey ~= EXUI.CurrentModule then
                EXUI:ReleaseMountedModulePreview()
            end

            previewRenderer = ExwindTools.ModulePreviewRenderers[EXUI.CurrentModule]
            if centralController then
                previewContext = { moduleKey = EXUI.CurrentModule, config = centralController:GetConfig() }
                EXUI:SetModulePreviewDockVisible(true, EXUI.ModulePreviewDockHeight)
            elseif definition then
                previewContext = { moduleKey = EXUI.CurrentModule, config = definition:GetConfig() }
                EXUI:SetModulePreviewDockVisible(true, EXUI.ModulePreviewDockHeight)
            elseif previewRenderer then
                previewContext = { moduleKey = EXUI.CurrentModule, config = ExwindTools:GetModuleDB(EXUI.CurrentModule) }
                EXUI:SetModulePreviewDockVisible(true, EXUI.ModulePreviewDockHeight)
            else
                EXUI:ReleaseMountedModulePreview()
            end
        end

        -- 获取或创建 Grid 容器页面 (挂载到 ScrollChild 上)
        local page, isNew = EXUI:GetCachedPage("ModuleGrid_" .. EXUI.CurrentModule, EXUI.ModuleScrollChild)
        page._exGridPage = true
        if EXUI.ShellPanel and _G.ExwindGrid then
            local metrics = EXUI.ShellPanel:GetMetrics()
            _G.ExwindGrid:SetContainerCols(page, metrics.splitGridCols)
        end
        EXUI.ActivePageFrame = page
        EXUI._InternalPageFrame = page

        -- 清理页面旧内容 (防止切模块残留)
        for _, child in ipairs({ page:GetChildren() }) do
            if not child._isPersistent then
                child:Hide()
                child:SetParent(nil)
            end
        end

        -- 渲染布局前先隐藏提示标签
        if EXUI.NoLayoutLabel then EXUI.NoLayoutLabel:Hide() end

        -- 渲染布局
        local config = centralController and centralController:GetConfig() or ExwindTools:GetModuleDB(EXUI.CurrentModule)
        local currentModuleKey = EXUI.CurrentModule
        _G.ExwindGrid:Render(page, layoutData, config, currentModuleKey, function()
            -- Render 完成后通知当前模块面板已刷新（各模块可订阅此事件更新动态内容）
            ExwindTools:UpdateState(currentModuleKey .. ".PanelRendered", GetTime())
        end)

        -- Render 已同步创建并激活 currentModuleKey 的 ContainerState；仅此时标准
        -- PreviewSurface 才能绑定正确的 Grid 容器，避免模块切换时读取旧模块状态。
        if centralController then
            local dock = EXUI.ModulePreviewDock
            centralController:MountPanel(dock)
            dock._mountedModuleKey = currentModuleKey
        elseif definition then
            local dock = EXUI.ModulePreviewDock
            definition:MountPreview(dock)
            dock._mountedModuleKey = currentModuleKey
        elseif previewRenderer then
            local dock = EXUI.ModulePreviewDock
            if dock._mountedModuleKey ~= currentModuleKey then
                if type(previewRenderer.mount) == "function" then
                    previewRenderer.mount(dock, previewContext)
                end
                dock._mountedModuleKey = currentModuleKey
            end
            if type(previewRenderer.update) == "function" then
                previewRenderer.update(dock, previewContext)
            end
        end
        if EXUI.PendingModuleScrollRestore ~= nil then
            EXUI.ModuleScrollFrame:SetVerticalScroll(EXUI.PendingModuleScrollRestore)
            EXUI.PendingModuleScrollRestore = nil
        end

        local resetBtn = EXUI:CreateSmallButton(page, L["重置当前模块设置"], function()
            local moduleName = (moduleMeta and moduleMeta.Name) or EXUI.CurrentModule or L["当前模块"]
            local message = string.format(L["你将重置%s模块设置，并重载。是否确定？"], moduleName)
            StaticPopup_Show("EXWIND_CONFIRM_RESET_MODULE", message, nil, { moduleKey = EXUI.CurrentModule })
        end)
        resetBtn:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 16)
        resetBtn:SetFrameLevel(page:GetFrameLevel() + 50)
        resetBtn._exModuleSettingsTransient = true
        page:SetHeight((page:GetHeight() or 1) + 52)

        -- [New v4.2] 如果处于开发者模式，在右上角显示“编辑”按钮
        if ExwindTools.State.DevMode then
            local editBtn = EXUI:CreateSmallButton(page, L["|cff00ff00编辑布局|r"], function()
                _G.ExwindGrid:ToggleLiveEdit(page, EXUI.CurrentModule)
            end)
            editBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -20, -5)
            editBtn:SetFrameLevel(page:GetFrameLevel() + 50)
            editBtn._exModuleSettingsTransient = true
        end
    else
        -- 模块未注册 Grid 布局，显示提示
        EXUI:ReleaseMountedModulePreview()
        EXUI.RightPanel:Show()
        EXUI.RightPanel:SetFrameLevel(EXUI.MainFrame:GetFrameLevel() + 10)

        if not EXUI.NoLayoutLabel then
            local lbl = EXUI:CreateVisualFontString(EXUI.RightPanel, EXFONTFRAME, "GameFontHighlightLarge")
            lbl:SetPoint("CENTER", EXUI.RightPanel, "CENTER", 0, 0)
            EXUI.NoLayoutLabel = lbl
        end
        EXUI.NoLayoutLabel:SetText("|cffff8800[" ..
            moduleMeta.Name .. L["]|r\n\n 插件内容意外缺失\n 请在插件更新器重新安装插件\n 如重新安装无法解决，请通知插件作者\n\nPlugin content is unexpectedly missing.\nPlease reinstall the addon using the addon updater.\nIf reinstalling does not resolve the issue, please contact the addon author."])
        EXUI.NoLayoutLabel:Show()
    end


    -- 清除切换标志
    EXUI.SwitchingModule = nil
end

-- =========================================================
-- 辅助函数
-- =========================================================
function EXUI:CreateActionButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(180, 40)
    btn:SetBackdrop(FRAME_BACKDROP_FLAT)
    btn:SetBackdropColor(unpack(THEME.Primary))
    btn:SetBackdropBorderColor(0.79, 0.73, 1.0, 0.68)

    local btnText = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    btn.Label = btnText
    btnText:SetFontObject("GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btnText:SetTextColor(1, 1, 1, 1)

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.68, 0.60, 1.0, 1)
        self:SetBackdropBorderColor(0.90, 0.86, 1.0, 0.96)
    end)
    btn:SetScript("OnLeave", function(self)
        -- 回复到 Exwind 经典紫色
        self:SetBackdropColor(unpack(THEME.Primary))
        self:SetBackdropBorderColor(0.79, 0.73, 1.0, 0.68)
    end)

    return btn
end

function EXUI:CreateSmallButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(120, 28)
    btn:SetBackdrop(FRAME_BACKDROP_FLAT)
    btn:SetBackdropColor(0.10, 0.095, 0.14, 0.84)
    btn:SetBackdropBorderColor(0.30, 0.28, 0.38, 0.62)

    local btnText = EXUI:CreateVisualFontString(btn, EXFONTFRAME)
    btn.Label = btnText
    btnText:SetFontObject("GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btnText:SetTextColor(unpack(THEME.TextMain))

    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.16, 0.14, 0.22, 0.96)
        self:SetBackdropBorderColor(0.54, 0.48, 0.72, 0.86)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.10, 0.095, 0.14, 0.84)
        self:SetBackdropBorderColor(0.30, 0.28, 0.38, 0.62)
    end)

    return btn
end

-- =========================================================
-- 状态总控页面
-- =========================================================
-- =========================================================
-- 状态总控页面
-- =========================================================
function EXUI:ShowDiagnosticPage()
    -- [Fix] 挂载到 ScrollChild，防止被 ScrollFrame 遮挡
    local page, isNew = EXUI:GetCachedPage("Diagnostic", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    -- 每次都需要刷新数据，所以清理旧内容
    for _, child in pairs({ page:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in pairs({ page:GetRegions() }) do
        region:Hide()
    end

    local env = ExwindTools:GetEnvironmentInfo()
    local db = ExwindTools.DB
    local yOffset = -18
    local localTime = date("%Y-%m-%d %H:%M:%S")
    local sectionWidth = 800

    local pageTitle = EXUI:CreateVisualFontString(page, EXFONTFRAME)
    pageTitle:SetFont(defaultFontPath, 24, "OUTLINE")
    pageTitle:SetPoint("TOPLEFT", 16, yOffset)
    pageTitle:SetText(L["状态总控"])
    pageTitle:SetTextColor(0.98, 0.99, 1, 1)
    yOffset = yOffset - 38

    local pageIntro = EXUI:CreateVisualFontString(page, EXFONTFRAME)
    pageIntro:SetFont(defaultFontPath, 15, "")
    pageIntro:SetPoint("TOPLEFT", 20, yOffset)
    pageIntro:SetWidth(sectionWidth)
    pageIntro:SetJustifyH("LEFT")
    pageIntro:SetText(L["实时查看 ExwindTools 当前环境、玩家状态与核心运行信息。"])
    pageIntro:SetTextColor(0.58, 0.67, 0.8, 1)
    yOffset = yOffset - 30

    local YES      = "|cff00ff00" .. L["是"] .. "|r"
    local NO       = "|cffaaaaaa" .. L["否"] .. "|r"

    local state = ExwindTools.State
    local function IsSecretValue(value)
        return type(issecretvalue) == "function" and issecretvalue(value)
    end

    local function ValueText(value)
        if IsSecretValue(value) then
            return "|cffedf2ff-|r"
        end
        return string.format("|cffedf2ff%s|r", tostring(value or "-"))
    end

    local function BoolText(value, trueColor)
        if IsSecretValue(value) then
            return NO
        end
        if value then
            return (trueColor or "|cffedf2ff") .. L["是"] .. "|r"
        end
        return NO
    end

    local function SafeNum(value)
        if IsSecretValue(value) then
            return 0
        end
        return tonumber(value) or 0
    end

    local function SafeText(value, fallback)
        if IsSecretValue(value) or IsSecretValue(fallback) then
            return "-"
        end
        local text = tostring(value or "")
        if text == "" then
            return fallback or "-"
        end
        return text
    end

    local function FormatLargeNumber(value)
        local num = SafeNum(value)
        if BreakUpLargeNumbers then
            return BreakUpLargeNumbers(num)
        end
        return tostring(num)
    end

    local function FormatPercent(value)
        return string.format("%.2f%%", tonumber(value) or 0)
    end

    local function FormatSessionTime(value)
        local num = tonumber(value) or 0
        if num <= 0 then
            return "|cff7f8aa3 0.0s|r"
        end
        return ValueText(string.format("%.1fs", num))
    end

    local function FormatList(values)
        if type(values) ~= "table" or #values == 0 then
            return "-"
        end
        local parts = {}
        for _, v in ipairs(values) do
            parts[#parts + 1] = tostring(v)
        end
        return table.concat(parts, ", ")
    end

    local sectionIndex = 0
    local function AddSection(title)
        if sectionIndex > 0 then
            yOffset = yOffset - 12
        end
        sectionIndex = sectionIndex + 1
        local header = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        header:SetFont(defaultFontPath, 22, "OUTLINE")
        header:SetPoint("TOPLEFT", 16, yOffset)
        header:SetText(title)
        header:SetTextColor(0.98, 0.99, 1, 1)
        yOffset = yOffset - 36
    end

    local function AddFieldGrid(fields, columns)
        columns = columns or 2
        local startX = 20
        local colGap = 54
        local colWidth = math.floor((sectionWidth - (columns - 1) * colGap) / columns)
        local labelWidth = 106
        local index = 1

        while index <= #fields do
            local rowTop = yOffset
            local rowHeight = 0
            local usedCols = 0

            while index <= #fields and usedCols < columns do
                local field = fields[index]
                local span = math.min(field.span or 1, columns - usedCols)
                local x = startX + usedCols * (colWidth + colGap)
                local width = colWidth * span + colGap * (span - 1)

                local label = EXUI:CreateVisualFontString(page, EXFONTFRAME)
                label:SetFont(defaultFontPath, 14, "OUTLINE")
                label:SetPoint("TOPLEFT", x, rowTop)
                label:SetWidth(labelWidth)
                label:SetJustifyH("LEFT")
                label:SetJustifyV("TOP")
                label:SetText(field.label)
                label:SetTextColor(0.48, 0.57, 0.70, 1)

                local value = EXUI:CreateVisualFontString(page, EXFONTFRAME)
                value:SetFont(defaultFontPath, 15, "")
                value:SetPoint("TOPLEFT", x + labelWidth + 10, rowTop)
                value:SetWidth(width - labelWidth - 10)
                value:SetJustifyH("LEFT")
                value:SetJustifyV("TOP")
                value:SetText(field.value)
                value:SetTextColor(0.90, 0.94, 1, 1)

                rowHeight = math.max(rowHeight, label:GetStringHeight() or 18, value:GetStringHeight() or 20)
                usedCols = usedCols + span
                index = index + 1
            end

            yOffset = rowTop - math.max(28, math.ceil(rowHeight) + 4)
        end
        yOffset = yOffset - 16
    end

    local mapID = tonumber(state.MapID) or 0
    local mapGroup = tonumber(state.MapGroup) or 0
    local instanceID = tonumber(state.InstanceID) or 0
    if mapGroup <= 0 then mapGroup = mapID end
    local encounterID = tonumber(state.EncounterID) or 0
    local level = tonumber(state.Level) or 0

    AddSection(L["环境信息"])
    AddFieldGrid({
        { label = L["插件版本"], value = ValueText(env.addonVersion) },
        { label = "WTF", value = ValueText(env.dbVersion) },
        { label = L["游戏版本"], value = ValueText(env.gameVersion) },
        { label = "Build", value = ValueText(env.gameBuild) },
        { label = L["系统"], value = ValueText(string.format("%s (%s)", env.platform, env.arch)) },
        { label = L["区域"], value = ValueText(env.region) },
        { label = L["语言"], value = ValueText(env.locale) },
        { label = L["时间"], value = ValueText(localTime) },
        { label = "PTR", value = env.isPTR == L["是"] and BoolText(true) or NO },
        { label = "BETA", value = env.isBeta == L["是"] and BoolText(true) or NO },
        { label = "ElvUI", value = env.isElvUI == L["是"] and BoolText(true) or NO },
    }, 2)

    AddSection(L["当前状态"])
    AddFieldGrid({
        { label = L["玩家"], value = ValueText(SafeText(state.PlayerName, "?") .. "-" .. SafeText(state.RealmName, "?")) },
        { label = L["职业"], value = ValueText(SafeText(state.ClassName, "?")) },
        { label = L["专精"], value = ValueText(SafeText(state.SpecName, "?")) },
        { label = L["职责"], value = ValueText(SafeText(state.RoleName, "?")) },
        { label = L["等级"], value = ValueText(level) },
        { label = L["战斗"], value = BoolText(state.InCombat, "|cffff7a7a") },
        { label = L["副本内"], value = BoolText(state.InInstance) },
        { label = L["五人本"], value = BoolText(state.InFivePlayerInstance) },
        { label = L["乘骑"], value = BoolText(state.IsMounted) },
        { label = L["开发模式"], value = BoolText(state.DevMode, "|cffd9b3ff") },
        { label = L["区域"], value = ValueText(SafeText(state.ZoneText)), span = 2 },
        { label = L["地图ID"], value = ValueText(mapID) },
        { label = L["地图组"], value = ValueText(mapGroup) },
        { label = L["副本ID"], value = ValueText(instanceID) },
        { label = L["副本类型"], value = ValueText(SafeText(state.InstanceType, "none")) },
        { label = L["难度ID"], value = ValueText(SafeNum(state.DifficultyID)) },
        { label = L["首领战"], value = BoolText(state.IsBossEncounter, "|cffff7a7a") },
        { label = "EncounterID", value = ValueText(encounterID) },
        { label = L["光环秘事"], value = BoolText(state.AuraSecretsActive, "|cff7fd4ff") },
        { label = L["打断就绪"], value = BoolText(state.InterruptReady) },
    }, 2)

    AddSection(L["大秘境状态"])
    AddFieldGrid({
        { label = L["大秘境"], value = BoolText(state.InMythicPlus, "|cff7fd4ff") },
        { label = L["层数"], value = ValueText(SafeNum(state.MythicPlusLevel)) },
        { label = L["限时完成"], value = BoolText(state.MythicPlusWasCharged) },
        { label = L["词缀"], value = ValueText(FormatList(state.MythicPlusAffixIDs)), span = 2 },
        { label = L["敌方进度"], value = ValueText(string.format("%d / %d", SafeNum(state.MythicPlusForcesCurrent), SafeNum(state.MythicPlusForcesTotal))) },
        { label = L["百分比"], value = ValueText(FormatPercent(state.MythicPlusForcesPercent)) },
        { label = L["有效"], value = BoolText(state.MythicPlusForcesValid) },
        { label = L["进度文本"], value = ValueText(SafeText(state.MythicPlusForcesText)), span = 2 },
        { label = L["已击杀首领"], value = ValueText(SafeNum(state.DungeonBossKilledCount)) },
        { label = L["进度序号"], value = ValueText(SafeNum(state.DungeonBossProgressIndex)) },
    }, 2)

    AddSection(L["玩家属性"])
    AddFieldGrid({
        { label = L["力量"], value = ValueText(SafeNum(state.PStat_Str)) },
        { label = L["敏捷"], value = ValueText(SafeNum(state.PStat_Agi)) },
        { label = L["智力"], value = ValueText(SafeNum(state.PStat_Int)) },
        { label = L["耐力"], value = ValueText(SafeNum(state.PStat_Sta)) },
        { label = L["主属性"], value = ValueText(SafeNum(state.PStat_Major)) },
        { label = L["暴击"], value = ValueText(FormatPercent(state.PStat_Crit)) },
        { label = L["急速"], value = ValueText(FormatPercent(state.PStat_Haste)) },
        { label = L["精通"], value = ValueText(FormatPercent(state.PStat_Mastery)) },
        { label = L["全能"], value = ValueText(FormatPercent(state.PStat_Versa)) },
        { label = L["护甲"], value = ValueText(FormatLargeNumber(state.PStat_Armor)) },
        { label = L["闪避"], value = ValueText(FormatPercent(state.PStat_Dodge)) },
        { label = L["招架"], value = ValueText(FormatPercent(state.PStat_Parry)) },
        { label = L["格挡"], value = ValueText(FormatPercent(state.PStat_Block)) },
        { label = L["吸血"], value = ValueText(FormatPercent(state.PStat_Leech)) },
        { label = L["减伤"], value = ValueText(FormatPercent(state.PStat_Avoidance)) },
        { label = L["速度"], value = ValueText(FormatPercent(state.PStat_Speed)) },
        { label = L["移速"], value = ValueText(SafeText(state.PStat_MovementText, FormatPercent(state.PStat_Movement))) },
        { label = L["装等"], value = ValueText(FormatLargeNumber(state.PStat_EquippedItemLevel)) },
        { label = L["最大生命"], value = ValueText(FormatLargeNumber(state.PStat_MaxHealth)) },
        { label = L["耐久"], value = ValueText(FormatPercent(state.PStat_Durability)) },
    }, 2)

    AddSection(L["玩家监控"])
    AddFieldGrid({
        -- 12.1 暂停：旧版 Debuff 快照状态链已停用
        -- { label = "减益数量", value = ValueText(SafeNum(state.PlayerDebuffCount)) },
        -- { label = "减益修订", value = ValueText(SafeNum(state.PlayerDebuffRevision)) },
        -- { label = "本次新增", value = ValueText(SafeNum(state.PlayerDebuffAddedCount)) },
        -- { label = "新增时间", value = FormatSessionTime(state.PlayerDebuffLastAddedAt) },
        -- { label = "最后修订", value = ValueText(SafeNum(state.PlayerDebuffLastAddedRevision)) },
        { label = L["影遁可用"], value = BoolText(state.ShadowmeldAvailable) },
        { label = L["影遁冷却"], value = BoolText(state.ShadowmeldCD, "|cffff7a7a") },
        { label = L["到期时间"], value = FormatSessionTime(state.ShadowmeldExpiration) },
    }, 2)

    AddSection(L["模块状态"])

    local colWidth = 260
    local col = 0
    local rowY = yOffset

    for _, meta in ipairs(ExwindTools.ModuleList) do
        local key = meta.Key
        local enabled = db.LoadByKey[key]
        local ready = ExwindTools.ModuleStatus[key] == "ready"

        local statusIcon, statusColor
        if not enabled then
            statusIcon = "|cff888888[" .. L["关"] .. "]|r"
            statusColor = { 0.6, 0.6, 0.6 }
        elseif ready then
            statusIcon = "|cff00ff00[OK]|r"
            statusColor = { 0.13, 0.77, 0.37 }
        else
            statusIcon = "|cffff0000[!!]|r"
            statusColor = { 0.87, 0.26, 0.26 }
        end

        local modText = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        modText:SetFont(defaultFontPath, 15, "")
        modText:SetPoint("TOPLEFT", 20 + col * colWidth, rowY)
        modText:SetText(string.format("%s %s", statusIcon, meta.Name))
        modText:SetTextColor(unpack(statusColor))

        col = col + 1
        if col >= 3 then
            col = 0
            rowY = rowY - 22
        end
    end
    if col > 0 then rowY = rowY - 22 end
    yOffset = rowY - 15

    -- [Fix] 设置高度以撑开滚动条
    page:SetHeight(math.abs(yOffset) + 50)
    EXUI.RightScrollChild:SetHeight(page:GetHeight())
end

-- =========================================================
-- 配置管理页面 (导出/导入)
-- =========================================================
function EXUI:ShowProfileManagerPage()
    local page, isNew = EXUI:GetCachedPage("ProfileManager", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    -- 状态存储
    if not EXUI.ProfileState then
        EXUI.ProfileState = {
            exportSelected = {},   -- 导出时选中的模块
            importSelected = {},   -- 导入时选中的模块
            parsedData = nil,      -- 解析后的导入数据
            mergeMode = "replace", -- 导入模式
        }
    end
    local state = EXUI.ProfileState

    if not isNew then
        EXUI.RightScrollChild:SetHeight(1200)
        return
    end

    local yOffset = -20
    local Export = ExwindTools.Export

    -- ===== 标题 =====
    local title = EXUI:CreateVisualFontString(page, EXFONTFRAME)
    title:SetFont(ExwindTools.MAIN_FONT, 25, "OUTLINE")
    title:SetPoint("TOPLEFT", 20, yOffset)
    title:SetText("|cffA330C9" .. L["配置管理"] .. "|r")
    yOffset = yOffset - 40

    -- ===== 导出区域 =====
    local exportSection = CreateFrame("Frame", nil, page, "BackdropTemplate")
    exportSection:SetSize(780, 400)
    exportSection:SetPoint("TOPLEFT", 20, yOffset)
    exportSection:SetBackdrop(BACKDROP)
    exportSection:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
    exportSection:SetBackdropBorderColor(unpack(THEME.Border))

    local exportTitle = EXUI:CreateVisualFontString(exportSection, EXFONTFRAME)
    exportTitle:SetFont(ExwindTools.MAIN_FONT, 20, "OUTLINE")
    exportTitle:SetPoint("TOPLEFT", 15, -15)
    exportTitle:SetText("|cff00ff80 " .. L["导出配置"] .. "|r")

    -- 配置名称输入
    local nameInput = EXUI:CreateEditBox(exportSection, L["我的配置"], 300, 30, L["配置名称:"], { labelPos = "left" })
    nameInput:SetPoint("TOPLEFT", 100, -50)

    -- 导出者名称输入
    local authorInput = EXUI:CreateEditBox(exportSection, "", 200, 30, L["导出者:"],
        { labelPos = "left", placeholder = L["留空则使用当前名"] })
    authorInput:SetPoint("LEFT", nameInput, "RIGHT", 80, 0)

    -- 备注说明输入
    local noteInput = EXUI:CreateEditBox(exportSection, "", 600, 70, L["备注说明:"], { labelPos = "left" })
    noteInput:SetPoint("TOPLEFT", 100, -100)

    -- 模块选择区域 (向下顺延偏移，防止重叠)
    local moduleLabel = EXUI:CreateVisualFontString(exportSection, EXFONTFRAME, "GameFontHighlight")
    moduleLabel:SetPoint("TOPLEFT", 15, -190)
    moduleLabel:SetText(L["选择导出模块:"])

    -- 全选/全不选按钮
    local selectAllBtn = EXUI:CreateSmallButton(exportSection, L["全选"], function()
        local modules = Export:GetExportableModules()
        for _, m in ipairs(modules) do state.exportSelected[m.key] = true end
        EXUI:RefreshExportCheckboxes()
    end)
    selectAllBtn:SetSize(60, 22); selectAllBtn:SetPoint("LEFT", moduleLabel, "RIGHT", 15, 0)

    local selectNoneBtn = EXUI:CreateSmallButton(exportSection, L["全不选"], function()
        wipe(state.exportSelected); EXUI:RefreshExportCheckboxes()
    end)
    selectNoneBtn:SetSize(70, 22); selectNoneBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 5, 0)

    -- 模块列表容器 (调整位位移)
    local exportList = CreateFrame("Frame", nil, exportSection)
    exportList:SetSize(740, 1)
    exportList:SetPoint("TOPLEFT", 15, -220)
    EXUI.ExportListFrame = exportList

    -- 导出按钮 (回归 Exwind 经典紫)
    local exportBtn = EXUI:CreateActionButton(exportSection, L["生成导出字符串"], function()
        local profileName = nameInput:GetText() or L["未命名"]
        local authorName = authorInput:GetText() or ""
        local note = noteInput:GetText() or ""
        local result, err = Export:ExportModules(state.exportSelected, profileName, authorName, note)
        if result then
            EXUI:ShowExportResultPopup(result, profileName)
        else
            print("|cffff0000[ExwindTools]|r " .. L["导出失败: "] .. (err or L["未知错误"]))
        end
    end)
    exportBtn:SetSize(200, 38)
    exportBtn:SetBackdropColor(unpack(THEME.Primary))
    exportBtn:SetBackdropBorderColor(0.5, 0.5, 0.55, 0.8)
    exportBtn:SetPoint("BOTTOMRIGHT", exportSection, "BOTTOMRIGHT", -15, 15)
    EXUI.ExportGenBtn = exportBtn

    yOffset = yOffset - 420

    -- ===== 导入区域 =====
    local importSection = CreateFrame("Frame", nil, page, "BackdropTemplate")
    importSection:SetSize(780, 480)
    -- 初始位置设低一点，等待动态计算覆盖
    importSection:SetPoint("TOPLEFT", 20, -1000)
    EXUI.ImportSection = importSection
    importSection:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
    importSection:SetBackdropBorderColor(unpack(THEME.Border))

    local importTitle = EXUI:CreateVisualFontString(importSection, EXFONTFRAME)
    importTitle:SetFont(ExwindTools.MAIN_FONT, 20, "OUTLINE")
    importTitle:SetPoint("TOPLEFT", 15, -15)
    importTitle:SetText("|cff00aaff " .. L["导入配置"] .. "|r")

    -- 导入字符串输入 (统一使用标准 EditBox，移除所有滚动层包装)
    local importInput = EXUI:CreateEditBox(importSection, "", 750, 100, L["粘贴导入字符串:"], { labelPos = "top" })
    importInput:SetPoint("TOPLEFT", 15, -60)
    EXUI.ImportStringField = importInput

    -- 解析预览按钮
    local parseBtn = EXUI:CreateSmallButton(importSection, L["解析预览"], function()
        local importDataInput = EXUI.ImportStringField:GetText()
        local data, err = Export:ParseImportString(importDataInput)
        if data then
            state.parsedData = data
            local summary = Export:GetImportSummary(data)
            wipe(state.importSelected)
            for _, m in ipairs(summary.modules) do state.importSelected[m.key] = true end
            EXUI:RefreshImportPreview(summary)
            print("|cff00ff00[ExwindTools]|r " .. string.format(L["解析成功！包含 %d 个模块配置"], summary.moduleCount))
        else
            state.parsedData = nil
            EXUI:RefreshImportPreview(nil)
            print("|cffff0000[ExwindTools]|r " .. L["解析失败: "] .. (err or L["未知错误"]))
        end
    end)
    parseBtn:SetSize(120, 26)
    parseBtn:SetPoint("TOPLEFT", EXUI.ImportStringField, "BOTTOMLEFT", 0, -10)

    -- 预览信息区 (结构完全对齐导出区)
    local previewFrame = CreateFrame("Frame", nil, importSection)
    previewFrame:SetSize(740, 1)
    previewFrame:SetPoint("TOPLEFT", 15, -195)
    EXUI.ImportPreviewFrame = previewFrame

    -- [Style] 模拟导出页的数据字段 (只读模式)
    local pName = EXUI:CreateEditBox(previewFrame, "", 300, 30, "|cffffd100" .. L["配置名称:"] .. "|r", { labelPos = "left" })
    pName:SetPoint("TOPLEFT", 85, 0)
    pName.editBox:Disable(); pName:SetBackdropColor(0.05, 0.05, 0.05, 1)
    EXUI.ImportPreviewName = pName

    local pAuthor = EXUI:CreateEditBox(previewFrame, "", 200, 30, "|cffffd100" .. L["作者:"] .. "|r", { labelPos = "left" })
    pAuthor:SetPoint("LEFT", pName, "RIGHT", 75, 0)
    pAuthor.editBox:Disable(); pAuthor:SetBackdropColor(0.05, 0.05, 0.05, 1)
    EXUI.ImportPreviewAuthor = pAuthor

    local pNote = EXUI:CreateEditBox(previewFrame, "", 600, 60, "|cffffd100" .. L["备注说明:"] .. "|r", { labelPos = "left" })
    pNote:SetPoint("TOPLEFT", 85, -45)
    pNote.editBox:Disable(); pNote:SetBackdropColor(0.05, 0.05, 0.05, 1)
    EXUI.ImportPreviewNote = pNote

    -- [Standard] 模块选择标题 (下移防止重叠)
    local importModLabel = EXUI:CreateVisualFontString(previewFrame, EXFONTFRAME, "GameFontHighlight")
    importModLabel:SetPoint("TOPLEFT", 0, -125)
    importModLabel:SetText(L["选择导入模块:"])
    EXUI.ImportPreviewLabel = importModLabel

    -- 导入模块选择列表 (直挂预览框架)
    local importList = CreateFrame("Frame", nil, previewFrame)
    importList:SetSize(740, 1)
    importList:SetPoint("TOPLEFT", 0, -155)
    EXUI.ImportListFrame = importList

    -- 应用导入按钮
    local applyBtn = EXUI:CreateActionButton(importSection, L["应用导入"], function()
        if not state.parsedData then
            print("|cffff0000[ExwindTools]|r " .. L["请先解析导入字符串"])
            return
        end
        -- 默认使用覆盖模式
        local count = Export:ApplyImport(state.parsedData, state.importSelected, "replace")
        if count > 0 then
            StaticPopup_Show("EXWIND_IMPORT_SUCCESS", count)
        else
            print("|cffff8800[ExwindTools]|r " .. L["未导入任何模块 (可能未选中或数据为空)"])
        end
    end)
    applyBtn:SetSize(160, 38)
    applyBtn:SetPoint("BOTTOMRIGHT", importSection, "BOTTOMRIGHT", -15, 15)

    yOffset = yOffset - 500

    -- 初始化导出模块列表
    EXUI:RefreshExportCheckboxes()

    -- 设置页面高度
    page:SetHeight(math.abs(yOffset) + 50)
    EXUI.RightScrollChild:SetHeight(page:GetHeight())
end

-- =========================================================
-- 刷新导出模块复选框
-- =========================================================
function EXUI:RefreshExportCheckboxes()
    local Export = ExwindTools.Export
    local state = EXUI.ProfileState
    local parent = EXUI.ExportListFrame
    if not parent then return end

    -- 清理旧内容
    for _, child in ipairs({ parent:GetChildren() }) do
        if not child._isPersistent then
            child:Hide(); child:SetParent(nil)
        end
    end

    local modules = Export:GetExportableModules()
    local yOff = 0
    local col = 0
    local rowHeight = 32 -- 提高行高，适配大勾选框

    for i, m in ipairs(modules) do
        -- 使用自研勾选框组件 (取代 UICheckButtonTemplate)
        local cb = EXUI:CreateCheckbox(parent, m.name, state.exportSelected[m.key] or false, function(checked)
            state.exportSelected[m.key] = checked
        end)
        cb:SetSize(220, 26)
        cb:SetPoint("TOPLEFT", (col * 240), yOff)

        -- 对齐文本
        cb.label:ClearAllPoints()
        cb.label:SetPoint("LEFT", cb.checkbox, "RIGHT", 5, 0)
        cb.label:SetJustifyH("LEFT")
        cb.label:SetTextColor(0.9, 0.9, 0.9)

        col = col + 1
        if col >= 3 then
            col = 0
            yOff = yOff - rowHeight
        end
    end

    -- 动态布局计算
    local listHeight = math.abs(yOff) + 40
    parent:SetHeight(listHeight)

    local exportSection = parent:GetParent()
    -- 基础偏移(180) + 备注框高度(70) + 列表高度 + 底部按钮区域(80)
    local sectionHeight = 250 + listHeight + 80
    exportSection:SetHeight(sectionHeight)

    -- [CRITICAL] 重新排布导入区域的锚点，确保永远不重叠
    if EXUI.ImportSection then
        EXUI.ImportSection:ClearAllPoints()
        EXUI.ImportSection:SetPoint("TOPLEFT", 20, -(100 + sectionHeight + 50))
    end

    -- 更新页面总高度
    local page = exportSection:GetParent()
    if page then
        page:SetHeight(sectionHeight + (EXUI.ImportSection and EXUI.ImportSection:GetHeight() or 500) + 200)
    end
end

-- =========================================================
-- 刷新导入预览
-- =========================================================
function EXUI:RefreshImportPreview(summary)
    local state = EXUI.ProfileState
    local parent = EXUI.ImportListFrame
    if not parent then return end

    -- 清理旧内容
    for _, child in ipairs({ parent:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end

    if not summary then
        EXUI.ImportPreviewName:SetText("")
        EXUI.ImportPreviewAuthor:SetText("")
        EXUI.ImportPreviewNote:SetText("")
        EXUI.ImportPreviewLabel:SetText("|cff888888" .. L["等待解析..."] .. "|r")
        return
    end

    -- [Standard] 填充数据到标准化只读字段
    EXUI.ImportPreviewName:SetText(summary.profileName or L["未命名"])
    EXUI.ImportPreviewAuthor:SetText(summary.author or L["未知"])
    EXUI.ImportPreviewNote:SetText(summary.note or L["无备注说明"])
    EXUI.ImportPreviewLabel:SetText("|cff00ff80" ..
        L["解析成功预览:"] .. "|r " .. string.format("|cffaaaaaa(" .. L["版本: %s"] .. ")|r", summary.addonVersion))

    -- 创建模块勾选列表
    local yOff = 0
    local col = 0
    local rowHeight = 32

    for i, m in ipairs(summary.modules) do
        local labelText = m.name
        if not m.exists then
            labelText = "|cffff6666" .. labelText .. " (" .. L["未安装"] .. ")|r"
        else
            labelText = "|cff90ee90" .. labelText .. "|r"
        end

        local cb = EXUI:CreateCheckbox(parent, labelText, state.importSelected[m.key] or false, function(checked)
            state.importSelected[m.key] = checked
        end)
        cb:SetSize(220, 26)
        cb:SetPoint("TOPLEFT", (col * 240), yOff)

        -- 对齐文本
        cb.label:ClearAllPoints()
        cb.label:SetPoint("LEFT", cb.checkbox, "RIGHT", 5, 0)
        cb.label:SetJustifyH("LEFT")

        col = col + 1
        if col >= 3 then
            col = 0; yOff = yOff - rowHeight
        end
    end

    -- 动态布局：调整整个区块高度
    local listHeight = math.abs(yOff) + 60
    parent:SetHeight(listHeight)

    local importSection = parent:GetParent():GetParent()
    if importSection then
        importSection:SetHeight(260 + listHeight + 80)
    end

    local page = importSection:GetParent()
    if page then page:SetHeight(math.abs(page:GetTop() - importSection:GetBottom()) + 200) end
end

-- =========================================================
-- 导出结果弹窗
-- =========================================================
function EXUI:ShowExportResultPopup(exportString, profileName)
    -- 创建或复用弹窗
    if not EXUI.ExportPopup then
        local popup = CreateFrame("Frame", "ExwindExportPopup", UIParent, "BackdropTemplate")
        popup:SetSize(600, 350)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetBackdrop(BACKDROP)
        popup:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        popup:SetBackdropBorderColor(unpack(THEME.Border))
        popup:EnableMouse(true)
        popup:SetMovable(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

        local title = EXUI:CreateVisualFontString(popup, EXFONTFRAME)
        title:SetFont(ExwindTools.MAIN_FONT, 25, "OUTLINE")
        title:SetPoint("TOP", 0, -15)
        title:SetText("|cff00ff80" .. L["导出成功"] .. "|r")
        popup.Title = title

        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function() popup:Hide() end)

        local hint = EXUI:CreateVisualFontString(popup, EXFONTFRAME)
        hint:SetFontObject("GameFontHighlight")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -10)
        hint:SetText(L["导出弹窗提示"])
        hint:SetTextColor(0.8, 0.8, 0.8)
        popup.Hint = hint

        -- 复制成功提示层
        local copyHint = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        copyHint:SetSize(200, 60)
        copyHint:SetPoint("CENTER", popup, "CENTER", 0, 0)
        copyHint:SetFrameLevel(popup:GetFrameLevel() + 10)
        copyHint:SetBackdrop(BACKDROP)
        copyHint:SetBackdropColor(0.1, 0.3, 0.1, 0.95)
        copyHint:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        copyHint:Hide()

        local copyHintText = EXUI:CreateVisualFontString(copyHint, EXFONTFRAME)
        copyHintText:SetFontObject("GameFontNormalLarge")
        copyHintText:SetPoint("CENTER")
        copyHintText:SetText("|cff00ff00✓ " .. L["已复制到剪贴板"] .. "|r")
        popup.CopyHint = copyHint

        local editFrame = CreateFrame("Frame", nil, popup, "BackdropTemplate")
        editFrame:SetSize(560, 200)
        editFrame:SetPoint("TOP", hint, "BOTTOM", 0, -10)
        editFrame:SetBackdrop(BACKDROP_SIMPLE)
        editFrame:SetBackdropColor(0.1, 0.1, 0.12, 1)

        local scrollFrame = CreateFrame("ScrollFrame", nil, editFrame, "ScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 5, -5)
        scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
        ApplyModernScrollBarSkin(scrollFrame)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetSize(530, 190)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetTextColor(0.7, 0.9, 0.7)
        editBox:SetAutoFocus(false)
        editBox:SetMultiLine(true)
        editBox:SetMaxLetters(999999)
        editBox:EnableMouseWheel(true)
        editBox:HookScript("OnMouseWheel", function(_, delta)
            local onMouseWheel = scrollFrame:GetScript("OnMouseWheel")
            if onMouseWheel then
                onMouseWheel(scrollFrame, delta)
            end
        end)
        scrollFrame:SetScrollChild(editBox)
        popup.EditBox = editBox

        -- Ctrl 键追踪
        popup.lastCtrlDown = 0
        popup:SetScript("OnUpdate", function(self)
            if IsControlKeyDown() then
                self.lastCtrlDown = GetTime()
            end
        end)

        -- 监听 Ctrl+C
        editBox:SetScript("OnKeyUp", function(self, key)
            local wasCtrlDown = IsControlKeyDown() or (GetTime() - popup.lastCtrlDown < 0.5)
            if wasCtrlDown and key == "C" then
                self:ClearFocus()
                -- 显示复制成功提示
                popup.CopyHint:Show()
                popup.CopyHint:SetAlpha(1)
                C_Timer.After(0.6, function()
                    popup:Hide()
                    popup.CopyHint:Hide()
                end)
            end
        end)

        local selectBtn = EXUI:CreateSmallButton(popup, L["全选复制"], function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)
        selectBtn:SetSize(100, 28)
        selectBtn:SetPoint("BOTTOM", popup, "BOTTOM", -60, 15)

        local closeBtn2 = EXUI:CreateSmallButton(popup, L["关闭"], function()
            popup:Hide()
        end)
        closeBtn2:SetSize(80, 28)
        closeBtn2:SetPoint("BOTTOM", popup, "BOTTOM", 60, 15)

        EXUI.ExportPopup = popup
    end

    local popup = EXUI.ExportPopup
    popup.EditBox:SetText(exportString)
    popup.Title:SetText("|cff00ff80" .. L["导出成功"] .. "|r - " .. profileName)
    popup.CopyHint:Hide()
    popup:Show()
    popup.EditBox:SetFocus()
    popup.EditBox:HighlightText()
end

-- =========================================================
-- 监听核心状态变动以实时刷新 UI
-- =========================================================
local function OnIdentityStateChanged()
    -- 如果 UI 正在显示，则根据当前页面决定是否刷新
    if EXUI.MainFrame and EXUI.MainFrame:IsShown() then
        if EXUI.CurrentPage == "Diagnostic" then
            -- 即使是 Diagnostic 页面，我们也通过 RefreshContent 统一路由
            EXUI:RefreshContent()
        end
        -- 注意：ModuleSettings 的刷新由各模块内部的 WatchState 触发，此处不重复 RefreshContent
        -- 避免在 ModuleSettings 页面造成双重刷新导致输入框失去焦点
    end
end

-- 注册状态监听
ExwindTools:WatchState("ClassID", "ExUI_Identity", OnIdentityStateChanged)
ExwindTools:WatchState("ClassName", "ExUI_Identity", OnIdentityStateChanged)
ExwindTools:WatchState("SpecID", "ExUI_Identity", OnIdentityStateChanged)
ExwindTools:WatchState("SpecName", "ExUI_Identity", OnIdentityStateChanged)

-- 绑定 Grid 引擎到 EXUI (Grid 在此之前加载)
if ExwindTools.Grid then
    EXUI.Grid = ExwindTools.Grid
end
