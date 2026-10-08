-- =========================================================
-- ExwindTools UI v4.1 - 原生 Grid 引擎版
-- =========================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local GM = ExwindTools.GUIMetrics
local GC = ExwindTools.GUIColors
if not GC then error("ExwindGUIColor.lua must load before ExwindToolsUI.lua") end

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
    Background = GC.panel,
    Sidebar = GC.panel,
    Border = GC.panelBorder,
    Primary = GC.accent,
    Success = { 0.31, 0.78, 0.55 },
    Danger = { 0.91, 0.38, 0.47 },
    TextMain = GC.text,
    TextSub = GC.textDim,
    TextDim = GC.textPlaceholder,
    CardBg = GC.card,
    CardBgHover = GC.headerHover,
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
EXUI.ActivePageScrollFrame = nil     -- 当前页面的滚动 owner；不覆盖 Tools 自己的稳定 ModuleScrollFrame
EXUI._InternalPageFrame = nil        -- ExwindTools 内部专用，跟踪自身页面帧，不被外部覆写
EXUI.PendingRightScrollRestore = nil -- 通用右侧滚动容器刷新后需要恢复的滚动位置

-- gui.version=1 的唯一页面声明登记表。登记只保存纯声明；中央 Controller
-- 在实际挂载前另行注入 picker 等运行期回调，避免把函数写回模块声明。
EXUI.SettingsPageDeclarations = EXUI.SettingsPageDeclarations or {}
EXUI.ModuleSettingsV2Pages = EXUI.ModuleSettingsV2Pages or {}

function EXUI:RegisterModuleSettingsPageV2(moduleKey, declaration, ownerFactory)
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error("RegisterModuleSettingsPageV2 requires a moduleKey", 2)
    end
    if type(ownerFactory) ~= "function" then
        error("RegisterModuleSettingsPageV2 requires an owner factory", 2)
    end
    if self.ModuleSettingsV2Pages[moduleKey] ~= nil then
        error("duplicate module V2 settings page: " .. moduleKey, 2)
    end
    if type(self.RegisterSettingsPageV2) ~= "function" then
        error("RegisterModuleSettingsPageV2 requires ExwindSettingsV2", 2)
    end
    local pageId = "ExwindTools.Module." .. moduleKey
    self:RegisterSettingsPageV2(pageId, declaration)
    self.ModuleSettingsV2Pages[moduleKey] = {
        pageId = pageId,
        ownerFactory = ownerFactory,
    }
    return true
end

local function CopySettingsDeclaration(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error("settings page declaration cannot be cyclic", 3) end
    local result = {}
    seen[value] = true
    for key, child in pairs(value) do
        result[CopySettingsDeclaration(key, seen)] = CopySettingsDeclaration(child, seen)
    end
    seen[value] = nil
    return result
end

local function ValidatePureSettingsDeclaration(value, seen)
    local valueType = type(value)
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        error("settings page declaration must contain data only", 3)
    end
    if valueType ~= "table" then return end
    seen = seen or {}
    if seen[value] then error("settings page declaration cannot be cyclic", 3) end
    seen[value] = true
    for key, child in pairs(value) do
        ValidatePureSettingsDeclaration(key, seen)
        ValidatePureSettingsDeclaration(child, seen)
    end
    seen[value] = nil
end

function EXUI:RegisterSettingsPage(pageId, guiDeclaration)
    if type(pageId) ~= "string" or pageId:match("^%s*$") then
        error("RegisterSettingsPage requires a non-empty pageId", 2)
    end
    if self.SettingsPageDeclarations[pageId] ~= nil then
        error("duplicate settings page declaration: " .. pageId, 2)
    end
    ValidatePureSettingsDeclaration(guiDeclaration)
    local grid = _G.ExwindGrid
    if not grid or type(grid.ValidateSettingsDeclaration) ~= "function" then
        error("RegisterSettingsPage requires ExwindGrid typed settings validation", 2)
    end
    if type(guiDeclaration) ~= "table" or guiDeclaration.version ~= 1
        or type(guiDeclaration.sections) ~= "table" or guiDeclaration.cards ~= nil then
        error("RegisterSettingsPage accepts only version=1 sections declarations; special cards use their owning page", 2)
    end
    local ok, reason = grid:ValidateSettingsDeclaration(guiDeclaration, {
        pageId = pageId,
        regionId = "registration",
    })
    if not ok then error(reason, 2) end
    self.SettingsPageDeclarations[pageId] = CopySettingsDeclaration(guiDeclaration)
    return true
end

function EXUI:GetSettingsPage(pageId)
    local declaration = self.SettingsPageDeclarations[pageId]
    return declaration and CopySettingsDeclaration(declaration) or nil
end

-- =========================================================
-- 模块设置页 · 面板内嵌预览（ModulePreviewDock）
-- 设计见 EXWIND-DEV/ExwindCore/模块SOP标准.md §5.2
-- =========================================================
EXUI.ModulePreviewDock = nil        -- 标准预览画布；模块 renderer 只接收这一个 Dock
EXUI.ModulePreviewShell = nil       -- 顶部固定预览区宿主
EXUI.ModuleTopPreview = nil         -- Core 唯一顶部预览封装的实例
EXUI.ModulePreviewDockHeight = EXUI:GetStandardPreviewMinimumCanvasHeight()
ExwindTools.ModulePreviewRenderers = ExwindTools.ModulePreviewRenderers or {}

local MODULE_PREVIEW_WHEEL_OWNER = {}

local function EnsureToolsTopPreview(shell)
    if EXUI.ModulePreviewShell == shell and EXUI.ModulePreviewDock then
        return EXUI.ModulePreviewDock
    end
    if EXUI.ModuleTopPreview then EXUI.ModuleTopPreview.row:Hide() end

    local top = EXUI:CreateStandardTopPreview(shell)
    top:Place(shell, EXUI.ModuleScrollChild and EXUI.ModuleScrollChild:GetWidth(), 0)
    top.row:Hide()
    EXUI.ModulePreviewShell = shell
    EXUI.ModuleTopPreview = top
    EXUI.ModulePreviewDock = top.canvas
    return top.canvas
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
    local shell = EXUI.ModulePreviewShell
    height = math.max(height or EXUI.ModulePreviewDockHeight,
        EXUI:GetStandardPreviewMinimumCanvasHeight())
    EXUI:SetPreviewDockScrollOwner(dock, MODULE_PREVIEW_WHEEL_OWNER,
        visible == true and EXUI.ModuleScrollFrame or nil)

    dock:SetHeight(height)
    EXUI.ModuleTopPreview:SyncHeight()
    EXUI.ModuleTopPreview.row:SetShown(visible == true)

    if EXUI.ShellPanel and EXUI.ShellHosts then
        -- Unified Shell may supply a new hosts table when its workspace is reused.
        -- The preview session must mount into that exact Shell Dock; showing a
        -- different/stale Dock makes a successful Render invisible to the page.
        local shellDock = EXUI.ShellHosts.previewDock
        if shellDock ~= shell then
            error("[ExwindToolsUI] ModulePreviewShell is not the current Unified Shell previewDock", 2)
        end
        EXUI.ShellPanel:SetPreviewDockVisible(visible == true, EXUI:GetStandardPreviewShellHeight(height))
        local shellHost = shellDock:GetParent()
        if visible == true and (not shellHost or not shellHost:IsShown() or not shellDock:IsShown() or (shellDock:GetHeight() or 0) < 1) then
            error("[ExwindToolsUI] Unified Shell previewDock was not made visible with a non-zero height", 2)
        end
        return
    end

    shell:SetHeight(visible and EXUI:GetStandardPreviewShellHeight(height) or 1)
    shell:SetShown(visible == true)
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
    if not grid or type(grid.FindMountedWidget) ~= "function" then return false end
    local mountedOwner = type(grid.GetMountedOwner) == "function"
        and grid:GetMountedOwner(container) or nil
    if not mountedOwner then return false end

    local function ResolveTarget()
        if type(grid.IsMountedOwnerCurrent) ~= "function"
            or not grid:IsMountedOwnerCurrent(container, mountedOwner) then return nil end
        local target, state, _, ownerContainer = grid:FindMountedWidget(container, gridKey)
        if not state or state.moduleKey ~= moduleKey then return nil end
        local meta = target and state.widgetMap and state.widgetMap[target]
        if not target or not meta or not meta.item or meta.item.key ~= gridKey then return nil end
        -- 卡片页的直接 owner 是该卡 Body；旧页仍是根 container。拒绝已回池、
        -- 被页面切换重新 parent 或来自另一个挂载会话的同名对象。
        if type(target.GetParent) ~= "function" or target:GetParent() ~= ownerContainer then return nil end
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
            flash:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
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
    local scrollFrame = self.ActivePageScrollFrame or self.ModuleScrollFrame
    return self:FocusModuleGridKey(moduleKey, gridKey, scrollFrame, self.ActivePageFrame)
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
    return EXUI:CreateSearchBox(parent, initialText, config.width, config.height, config)
end
local function ApplyModernScrollBarSkin(scrollFrame)
    if not scrollFrame then
        return
    end
    -- ScrollFrameTemplate owns and binds the only native MinimalScrollBar;
    -- the shared EXUI entry changes geometry/appearance without replacing it.
    scrollFrame:EnableMouseWheel(true)
    EXUI:ApplyModernScrollFrame(scrollFrame)
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
    ambientMask:SetColorTexture(unpack(GC.shell.toolsAmbientMask))
    f.AmbientMask = ambientMask

    local topLine = EXUI:CreateVisualTexture(f, EXBASEFRAME)
    topLine:SetPoint("TOPLEFT", 1, -46)
    topLine:SetPoint("TOPRIGHT", -1, -46)
    topLine:SetHeight(1)
    topLine:SetColorTexture(unpack(GC.shell.toolsTopLine))

    local bottomLine = EXUI:CreateVisualTexture(f, EXBASEFRAME)
    bottomLine:SetPoint("BOTTOMLEFT", 1, 44)
    bottomLine:SetPoint("BOTTOMRIGHT", -1, 44)
    bottomLine:SetHeight(1)
    bottomLine:SetColorTexture(unpack(GC.shell.toolsBottomLine))

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
    title:SetText(GC.markup.text .. "EXWINDTOOLS|r " .. GC.markup.textDim .. "/ " .. L["设置中心"] .. "|r")
    f.Title = title

    --底层显示
    local status = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 18, 15)
    status:SetText(string.format("%s%s|r", GC.markup.placeholder, string.format(L["版本: %s | 引擎: GRID %s"],
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

    local reloadBtn = EXUI:CreateButton(footer, 120, ExwindTools.GUIMetrics.size.buttonHeight, L["立即重载界面"], function()
        C_UI.Reload()
    end)
    reloadBtn:SetPoint("RIGHT", 0, -8)
    reloadBtn:SetSize(180, GM.size.buttonHeight)

    -- [v4.7] 新增编辑模式快捷开关
    local editBtn = EXUI:CreateButton(footer, 120, ExwindTools.GUIMetrics.size.buttonHeight, EXUI:IsEditModeActive() and L["关闭编辑模式"] or L["启用编辑模式"], function()
        EXUI:ToggleEditMode()
        -- [优化] 如果开启了编辑模式，自动关闭设置面板，方便用户调整布局
        if EXUI:IsEditModeActive() and f:IsShown() then
            f:Hide()
        end
    end)
    editBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -10, 0)
    editBtn:SetSize(180, GM.size.buttonHeight)
    EXUI.EditModeToggleButton = editBtn

    local changelogBtn = EXUI:CreateButton(footer, 120, ExwindTools.GUIMetrics.size.buttonHeight, L["更新日志"], function()
        if ExwindTools.ShowChangelog then
            ExwindTools:ShowChangelog({ markShown = true })
        end
    end)
    changelogBtn:SetPoint("RIGHT", editBtn, "LEFT", -10, 0)
    changelogBtn:SetSize(150, GM.size.buttonHeight)
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
    -- Unified Shell 已拥有 B/C 分隔线；嵌入时不再叠加第二道方形边框。
    if not options.fillParent then
        sidebar:SetBackdrop(BACKDROP)
        sidebar:SetBackdropColor(unpack(GC.shell.toolsSidebar))
        sidebar:SetBackdropBorderColor(unpack(GC.shell.toolsSidebarBorder))

        local vLine = EXUI:CreateVisualTexture(sidebar, EXBASEFRAME)
        vLine:SetPoint("TOPRIGHT", 0, 0)
        vLine:SetPoint("BOTTOMRIGHT", 0, 0)
        vLine:SetWidth(1)
        vLine:SetColorTexture(unpack(GC.shell.toolsSidebarDivider))
    end

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
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 5)
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
-- 分类标题保留轻量复用；Items 只追踪当前租用的共享 GridButton，重建时归还公共池。
EXUI.SidebarState = { Expanded = { true, true, true, true, true }, SearchText = "" }
EXUI.SidebarPool = { Headers = {}, Items = {} }

local function ApplySidebarItemLayout(btn, variant)
    btn.variant = variant or "module"
    EXUI:SetSidebarNavigationButtonLevel(btn, btn.variant == "topnav" and 0 or 1)
end

local function ApplySidebarModuleButtonState(btn, isActive, isEnabled)
    if not btn then return end
    btn.isActive = isActive == true
    btn.isEnabledState = (isEnabled ~= false)
    EXUI:SetSidebarNavigationButtonState(btn, btn.isActive, btn.isEnabledState)
end

local TOOLS_NAVIGATION_ICONS = {
    Home = "house", LoadSettings = "blocks", Diagnostic = "activity", ProfileManager = "sliders-horizontal",
    ["ExTools.MiniTools"] = "toolbox", ["ExTools.CombatAlert"] = "swords",
    ["ExTools.PlayerPosition"] = "map-pin", ["ExTools.ChatChannelBar"] = "messages-square",
    ["ExTools.AutoBuy"] = "shopping-cart", ["ExTools.GossipID"] = "message-circle-more",
    ["ExTools.CombatMobDebuffGrid"] = "skull", ["ExTools.RaidMarkerPanel"] = "star",
    ["ExM+Info.MDTIconHook"] = "map", ["ExM+Info.MythicIcon"] = "door-open",
    ["ExM+Info.TeleMsg"] = "message-square", ["ExM+Info.Tooltip"] = "trophy",
    ["ExM+Info.RunHistory"] = "history", ["ExM+.MythicDamage"] = "flame",
    ["ExTools.PveInfoPanel"] = "castle", ["ExTools.PveKeystoneInfo"] = "key-round",
    ["ExClass.FocusCast"] = "wand-sparkles", ["ExTools.BattleResurrection"] = "heart-pulse",
    ["ExTools.PlayerShield"] = "shield", ["ExTools.PlayerHealAbsorb"] = "shield-plus",
    ["ExTools.CombatTimer"] = "timer", ["ExTools.SpellQueue"] = "timer-reset",
    ["ExClass.SpellEffectAlpha"] = "blend", ["ExTools.PlayerStats"] = "chart-no-axes-column",
    ["ExTools.YYSound"] = "volume-2", ["ExTools.CastSequence"] = "book-open",
    ["ExClass.RangeCheck"] = "crosshair", ["ExClass.NoMoveSkillAlert"] = "move",
    ["ExClass.DKBloodBoil"] = "sparkles", ["ExClass.DKBloodBoilSmart"] = "sparkles",
    ["ExTools.CooldownFlash"] = "sparkles",
    ["ExClass.BrewmasterStagger"] = "beer", ["ExTools.TransformTimer"] = "hourglass",
    ["ExPTR.MiniTools"] = "toolbox", ["ExPTR.SetKey"] = "key-round",
}

-- 标题从本地 Frame 列表复用；可点击项始终从公共 GridButton 池取得。
function EXUI:GetSidebarObj(type, parent)
    local pool = EXUI.SidebarPool[type]
    if type == "Headers" then
        for _, obj in ipairs(pool) do
            if not obj:IsShown() then
                obj:SetParent(parent)
                obj:Show()
                return obj
            end
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
    return EXUI:CreateSidebarNavigationHeader(parent, "", { height = 22 })
end

-- 创建子项目按钮
function EXUI:CreateSidebarItemBase(parent)
    local btn = EXUI:CreateSidebarNavigationButton(parent, "", nil, { level = 1 })

    btn.badge = EXUI:CreateVisualTexture(btn, EXBORDERFRAME)
    btn.badge:SetSize(64, 33)
    btn.badge:Hide()

    btn.label:SetWordWrap(false)

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
    if EXUI.SidebarPool.Items then
        for _, v in ipairs(EXUI.SidebarPool.Items) do
            EXUI:ReleaseSidebarNavigationButton(v)
        end
        wipe(EXUI.SidebarPool.Items)
    end

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
        UpdateSidebarItemBadge(btn, meta)
        local iconID = TOOLS_NAVIGATION_ICONS[key or page]
        EXUI:SetSidebarNavigationButtonIcon(btn, iconID and EXUI:GetIcon(iconID) or nil)

        -- [New] 检测模块是否已载入
        local isModule = (key ~= nil)
        local isLoaded = not isModule
        if isModule and ExwindTools.DB and ExwindTools.DB.LoadByKey then
            isLoaded = ExwindTools.DB.LoadByKey[key] ~= false
        end
        btn.isLoaded = isLoaded

        if isModule and not isLoaded then
            btn.label:SetText(GC.markup.textDisabled .. name .. " (" .. L["未载入"] .. ")|r")
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
        emptyItem.isLoaded = false
        ApplySidebarItemLayout(emptyItem, "module")
        emptyItem.label:SetText(GC.markup.textDisabled .. L["没有匹配的模块"] .. "|r")
        emptyItem:SetPoint("TOPLEFT", 10, yOffset)
        emptyItem:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
        emptyItem:SetScript("OnClick", nil)
        UpdateSidebarItemBadge(emptyItem, nil)
        ApplySidebarModuleButtonState(emptyItem, false, false)
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
    panel:SetBackdropColor(unpack(GC.shell.toolsRightPanel))

    -- [New] 通用滚动容器 (为所有普通页面提供滚动支持)
    local sf = CreateFrame("ScrollFrame", "ExwindCommonScroll", panel, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -12)
    sf:SetPoint("BOTTOMRIGHT", -18, 10)
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
    if EXUI.ModuleTopPreview and EXUI.ModulePreviewShell and EXUI.ModuleScrollChild then
        EXUI.ModuleTopPreview:Place(EXUI.ModulePreviewShell, EXUI.ModuleScrollChild:GetWidth(), 0)
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
        EnsureToolsTopPreview(hosts.previewDock)
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
    EnsureToolsTopPreview(hosts.previewDock)
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

    if page._exV2Session then
        page._exV2Session:Release()
        page._exV2Session = nil
        page._exV2Owner = nil
    elseif not grid then
        return false
    end

    -- Grid 编辑器的工具栏/浮层并不挂在页面 root 下；先正常退出该页的编辑会话，
    -- 再归还 widget，避免隐藏页面仍保留可操作的编辑器状态。
    if grid and grid.IsLiveEditing and grid.LiveContainer == page then
        grid:ToggleLiveEdit(page)
        grid.LiveContainer = nil
    end

    local cardSession = grid and type(grid.GetMountedCardSession) == "function"
        and grid:GetMountedCardSession(page) or nil
    if cardSession then
        cardSession:Release()
        page._exCardSession = nil
    elseif grid then
        grid:ReleaseContainerWidgets(page)
    end

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
    EXUI.ActivePageScrollFrame = nil

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

local function ResetModuleConfirmed(moduleKey)
    if not moduleKey then return end
    local db = ExwindTools:GetModuleDBStorage(moduleKey)
    if db and db.ModuleDB then
        db.ModuleDB[moduleKey] = nil
    end
    C_UI.Reload()
end

function EXUI:ShowHomePage()
    local page, isNew = EXUI:GetCachedPage("Home", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    if isNew then
        local label = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        label:SetFontObject("GameFontHighlight")
        label:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -24)
        label:SetText(L["开发中"])
        label:SetTextColor(unpack(GC.text))
    end

    page:SetHeight(96)
    EXUI.RightScrollChild:SetHeight(96)
end

-- =========================================================
-- 插件载入页面
-- =========================================================
local function ModuleHasSettingsPage(meta)
    -- 路由可见性只能由静态 ModuleList 决定。不能检查运行时 Layout/Controller：
    -- 被禁用模块会在注册设置页之前 return，若据此过滤就永远无法从管理页重新启用。
    return type(meta) == "table" and meta.HideCfg ~= true
end

-- 模块管理页图标：与左侧导航共用 TOOLS_NAVIGATION_ICONS（统一图标库，白色线条，跟随文字色）。

local MODULE_MANAGEMENT_PAGE_ID = "ExwindTools.ModuleManagement"

local function ModuleManagementEnabled(meta)
    return ExwindTools.DB.LoadByKey[meta.Key] ~= false
end

local function SortedCategoryModules(category)
    local enabled, disabled = {}, {}
    for _, meta in ipairs(ExwindTools.ModuleList) do
        if ModuleHasSettingsPage(meta) and (tonumber(meta.Category) or 1) == category then
            local bucket = ModuleManagementEnabled(meta) and enabled or disabled
            bucket[#bucket + 1] = meta
        end
    end
    for _, meta in ipairs(disabled) do enabled[#enabled + 1] = meta end
    return enabled
end

local function CreateModuleManagementOwner(page, categories)
    local owner = { controls = {}, components = {}, actions = {}, predicates = {}, sources = {}, texts = {} }
    for _, category in ipairs(categories) do
        local categoryID = category
        owner.sources["category-" .. categoryID] = function()
            return SortedCategoryModules(categoryID)
        end
    end
    owner.onHeightChanged = function(height)
        page.cardsContainer:SetHeight(math.max(1, height))
        page:SetHeight(height + 102)
        EXUI.RightScrollChild:SetHeight(page:GetHeight())
    end
    owner.components.moduleRow = {
        mount = function(host, context)
            local meta = context.scope.item
            host._moduleKey = meta.Key
            if not host._moduleRowVisuals then
                local iconTile = CreateFrame("Frame", nil, host)
                iconTile:SetSize(42, 42)
                iconTile:SetPoint("LEFT", host, "LEFT", 12, 0)
                local iconArt = EXUI:CreateVisualTexture(iconTile, EXBASEFRAME)
                iconArt:SetPoint("CENTER")
                iconArt:SetSize(28, 28)
                local iconMark = EXUI:CreateVisualFontString(iconTile, EXFONTFRAME)
                iconMark:SetFont(defaultFontPath, GM.font.title, "OUTLINE")
                iconMark:SetPoint("CENTER")
                iconMark:SetText("EX")
                local name = EXUI:CreateVisualFontString(host, EXFONTFRAME)
                name:SetFont(defaultFontPath, GM.font.title, "OUTLINE")
                name:SetPoint("TOPLEFT", host, "TOPLEFT", 66, -11)
                name:SetJustifyH("LEFT")
                local description = EXUI:CreateVisualFontString(host, EXFONTFRAME)
                description:SetFont(defaultFontPath, GM.font.moduleDescription, "")
                description:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
                description:SetJustifyH("LEFT")
                description:SetWordWrap(true)
                description:SetMaxLines(2)
                local separator = EXUI:CreateSettingsSeparator(host, 1)
                separator:SetPoint("TOPLEFT", host, "TOPLEFT", 0, GM.space.settingsV2Gap / 2)
                host._moduleRowVisuals = {
                    iconTile = iconTile, iconArt = iconArt, iconMark = iconMark,
                    name = name, description = description, separator = separator,
                }
            end
            local visuals = host._moduleRowVisuals
            visuals.iconTile:Show()
            visuals.name:Show()
            visuals.description:Show()
            host.EnableSwitch = EXUI:CreateCheckbox(host, "", ModuleManagementEnabled(meta),
                context:Guard(function(checked)
                    ExwindTools:SetModuleEnabled(meta.Key, checked)
                    C_Timer.After(0, function()
                        if page.moduleListSession and page:IsVisible() then
                            page.moduleListSession:Refresh()
                        end
                    end)
                end))
            host.EnableSwitch:SetSize(44, GM.size.controlHeight)
            host.EnableSwitch:SetPoint("RIGHT", host, "RIGHT", -14, 0)
            EXUI:PrepareSettingsListControl(host.EnableSwitch, { presentation = "switch", hideLabel = true })
            return host
        end,
        update = function(host, context)
            local meta = context.scope.item
            local key = meta.Key
            local enabled = ModuleManagementEnabled(meta)
            local visuals = host._moduleRowVisuals
            visuals.separator:SetShown(context.scope.index > 1)
            local iconID = TOOLS_NAVIGATION_ICONS[key]
            visuals.iconArt:SetShown(iconID ~= nil)
            visuals.iconMark:SetShown(iconID == nil)
            if iconID then
                visuals.iconArt:SetTexture(EXUI:GetIcon(iconID))
                visuals.iconArt:SetDesaturated(false)
                visuals.iconArt:SetVertexColor(unpack(enabled and GC.text or GC.textDisabled))
            end
            visuals.iconMark:SetTextColor(unpack(enabled and GC.accent or GC.textDisabled))
            visuals.name:SetText(meta.Name or key)
            visuals.name:SetTextColor(unpack(enabled and GC.text or GC.textDisabled))
            visuals.description:SetText(meta.Desc or "")
            visuals.description:SetTextColor(unpack(enabled and GC.textDim or GC.textDisabled))
            host.EnableSwitch:SetChecked(enabled)
            EXUI:ApplyControlAppearance(host.EnableSwitch)
        end,
        measure = function(host, _, width)
            local visuals = host._moduleRowVisuals
            local textWidth = math.max(80, width - 130)
            visuals.name:SetWidth(textWidth)
            visuals.description:SetWidth(textWidth)
            return math.max(52, math.ceil(16 + visuals.name:GetStringHeight()
                + 4 + visuals.description:GetStringHeight()))
        end,
        layout = function(host, context, width, height)
            host:SetSize(width, height)
            local textWidth = math.max(80, width - 130)
            host._moduleRowVisuals.name:SetWidth(textWidth)
            host._moduleRowVisuals.description:SetWidth(textWidth)
            host._moduleRowVisuals.separator:SetWidth(width)
            local visuals = host._moduleRowVisuals
            local textHeight = visuals.name:GetStringHeight() + 4 + visuals.description:GetStringHeight()
            visuals.name:ClearAllPoints()
            visuals.name:SetPoint("TOPLEFT", host, "TOPLEFT", 66, -(height - textHeight) / 2)
        end,
        setEnabled = function() end,
        setVisible = function(host, context, visible) host:SetShown(visible) end,
        release = function(host)
            local factory = _G.ExwindFactory
            EXUI:RestoreSettingsListControl(host.EnableSwitch)
            factory:Release(host.EnableSwitch._fromPool, host.EnableSwitch)
            host.EnableSwitch = nil
            host._moduleKey = nil
            local visuals = host._moduleRowVisuals
            visuals.iconTile:Hide()
            visuals.name:Hide()
            visuals.description:Hide()
            visuals.separator:Hide()
        end,
    }
    return owner
end

function EXUI:ShowLoadSettingsPage()
    EXUI:SyncScrollChildWidths()
    local page, isNew = EXUI:GetCachedPage("LoadSettings", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    if isNew then
        local title = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        title:SetFont(defaultFontPath, GM.font.tools.moduleTitle, "OUTLINE")
        title:SetPoint("TOPLEFT", 20, -15)
        title:SetText(L["模块管理"])
        title:SetTextColor(unpack(GC.text))
        local hint = EXUI:CreateVisualFontString(page, EXFONTFRAME)
        hint:SetFontObject("GameFontHighlight")
        hint:SetPoint("TOPLEFT", 20, -45)
        hint:SetText(L["按左侧路由分类管理模块；禁用立即生效，重新启用后需要 /reload。"])
        hint:SetTextColor(unpack(GC.textDim))

        local enableAll = EXUI:CreateButton(page, 120, GM.size.buttonHeight, L["全部启用"], function()
            for _, meta in ipairs(ExwindTools.ModuleList) do
                if ModuleHasSettingsPage(meta) then ExwindTools:SetModuleEnabled(meta.Key, true) end
            end
            page.moduleListSession:Refresh()
        end, { variant = "primary", compact = true })
        enableAll:SetPoint("TOPRIGHT", -150, -12)
        local disableAll = EXUI:CreateButton(page, 120, GM.size.buttonHeight, L["全部禁用"], function()
            for _, meta in ipairs(ExwindTools.ModuleList) do
                if ModuleHasSettingsPage(meta) then ExwindTools:SetModuleEnabled(meta.Key, false) end
            end
            page.moduleListSession:Refresh()
        end, { variant = "danger", compact = true })
        disableAll:SetPoint("TOPRIGHT", -20, -12)

        page.cardsContainer = CreateFrame("Frame", nil, page)
        page.cardsContainer:SetPoint("TOPLEFT", page, "TOPLEFT", 15, -82)
        page.cardsContainer:SetPoint("TOPRIGHT", page, "TOPRIGHT", -15, -82)
        page.cardsContainer:SetHeight(1)

        local seen, categories = {}, {}
        for _, meta in ipairs(ExwindTools.ModuleList) do
            if ModuleHasSettingsPage(meta) then
                local category = tonumber(meta.Category) or 1
                if not seen[category] then
                    seen[category] = true
                    categories[#categories + 1] = category
                end
            end
        end
        table.sort(categories)
        local cards = {}
        for _, category in ipairs(categories) do
            cards[#cards + 1] = {
                id = "category-card-" .. category, kind = "card",
                title = (ExwindTools.Cate and ExwindTools.Cate[category]) or (L["分类"] .. " " .. category),
                children = {{
                    id = "category-list-" .. category, kind = "repeat", source = "category-" .. category,
                    template = { id = "module-row-" .. category, kind = "component", ref = "moduleRow" },
                }},
            }
        end
        EXUI:RegisterSettingsPageV2(MODULE_MANAGEMENT_PAGE_ID, { version = 2, cards = cards })
        page.moduleListSession = EXUI:MountSettingsPageV2(page.cardsContainer,
            MODULE_MANAGEMENT_PAGE_ID, CreateModuleManagementOwner(page, categories))
    else
        page.moduleListSession:Refresh()
    end
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
    local v2Entry = EXUI.ModuleSettingsV2Pages[EXUI.CurrentModule]
    local centralController = type(EXUI.GetCentralModuleController) == "function"
        and EXUI:GetCentralModuleController(EXUI.CurrentModule) or nil
    local registeredSettingsPage = type(EXUI.GetSettingsPage) == "function"
        and EXUI:GetSettingsPage(EXUI.CurrentModule) or nil
    local layoutData = v2Entry and { version = 2 }
        or centralController
        and ((type(centralController.BuildSettingsDeclaration) == "function"
            and centralController:BuildSettingsDeclaration()) or centralController:BuildGridLayout())
        or (definition and definition:GetLayout()
            or registeredSettingsPage
            or ExwindTools.RegisteredLayouts[EXUI.CurrentModule])
    local usesV2Declaration = v2Entry ~= nil
    local ordinarySettingsEntry = centralController ~= nil or definition ~= nil or registeredSettingsPage ~= nil
    local hasSections = type(layoutData) == "table" and type(layoutData.sections) == "table"
    local hasCards = type(layoutData) == "table" and type(layoutData.cards) == "table"
    local pageDeclarationMode
    if usesV2Declaration then
        pageDeclarationMode = "v2"
    elseif ordinarySettingsEntry then
        if type(layoutData) ~= "table" or layoutData.version ~= 1
            or not hasSections or hasCards then
            error("ordinary settings modules require version=1 sections; special cards use RegisterModuleLayout with their owning page", 2)
        end
        pageDeclarationMode = "sections"
    elseif type(layoutData) == "table" and layoutData.version == 1 and hasSections ~= hasCards then
        -- RegisterModuleLayout is the retained legacy/special declaration entry.
        -- Its owning page may choose typed sections, free cards, or the old flat
        -- Grid path; ordinary controller/definition/registered pages cannot.
        pageDeclarationMode = hasSections and "sections" or "cards"
    end
    local usesCardDeclaration = pageDeclarationMode ~= nil and pageDeclarationMode ~= "v2"
    local declaresStructuredPage = type(layoutData) == "table"
        and (layoutData.version ~= nil or layoutData.cards ~= nil or layoutData.sections ~= nil)
    if declaresStructuredPage and not usesCardDeclaration and not usesV2Declaration then
        error("unsupported settings page declaration for " .. tostring(EXUI.CurrentModule), 2)
    end
    if layoutData and _G.ExwindGrid then
        EXUI.RightPanel:Show()
        -- [Fix] 这里的 MainFrame 就是原生 Frame 了，不再需要 .frame
        EXUI.RightPanel:SetFrameLevel(EXUI.MainFrame:GetFrameLevel() + 10)

        if not EXUI.ModulePreviewDock then
            -- 顶部固定预览区：不参与滚动，未注册渲染器的模块保持 1px 收起，不占布局空间
            local shell = CreateFrame("Frame", "ExwindModulePreviewDock", EXUI.RightPanel)
            shell:SetPoint("TOPLEFT", EXUI.RightPanel, "TOPLEFT", 0, -5)
            shell:SetPoint("TOPRIGHT", EXUI.RightPanel, "TOPRIGHT", -18, -5)
            shell:SetHeight(1)
            EnsureToolsTopPreview(shell)
        end

        if not EXUI.ModuleScrollFrame then
            -- 原生细滚动条由 ScrollFrameTemplate 自动创建并管理。
            EXUI.ModuleScrollFrame = CreateFrame("ScrollFrame", "ExwindModuleGridScroll", EXUI.RightPanel,
                "ScrollFrameTemplate")
            -- [Fix] 顶部锚点改挂在 ModulePreviewDock 的底部，而不是直接贴 RightPanel 顶部，
            -- 这样预览区高度变化（0 或 ModulePreviewDockHeight）会自动带动 Grid 区域跟着收缩/展开。
            EXUI.ModuleScrollFrame:SetPoint("TOPLEFT", EXUI.ModulePreviewShell, "BOTTOMLEFT", 0, 0)
            -- 右边只交给 BOTTOMRIGHT 定义；若再用 TOPRIGHT=0 重复定义同一条边，
            -- 模板滚动条会按未内缩的右边向外展开，使 BOTTOMRIGHT 的内距实际失效。
            EXUI.ModuleScrollFrame:SetPoint("BOTTOMRIGHT", -18, 5)
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
        local previousCardSession = type(_G.ExwindGrid.GetMountedCardSession) == "function"
            and _G.ExwindGrid:GetMountedCardSession(page) or nil
        if previousCardSession then previousCardSession:Release() end
        page._exCardSession = nil
        if page._exV2Session then
            page._exV2Session:Release()
            page._exV2Session = nil
            page._exV2Owner = nil
        end
        if usesCardDeclaration and _G.ExwindGrid.ContainerStates[page] then
            _G.ExwindGrid:ReleaseContainerWidgets(page)
        end
        if not usesCardDeclaration and EXUI.ShellPanel and _G.ExwindGrid then
            local metrics = EXUI.ShellPanel:GetMetrics()
            _G.ExwindGrid:SetContainerCols(page, metrics.splitGridCols)
        end
        EXUI.ActivePageFrame = page
        EXUI.ActivePageScrollFrame = EXUI.ModuleScrollFrame
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
        if usesV2Declaration then
            local mountContext = {
                pageId = v2Entry.pageId,
                moduleKey = currentModuleKey,
                config = config,
                settingsPageTitle = moduleMeta.Name,
                settingsPageDescription = moduleMeta.Desc,
                scrollFrame = EXUI.ModuleScrollFrame,
            }
            local owner = v2Entry.ownerFactory(mountContext)
            if type(owner) ~= "table" then
                error("module V2 owner factory must return a table: " .. tostring(currentModuleKey), 2)
            end
            local ownerHeightChanged = owner.onHeightChanged
            owner.onHeightChanged = function(height)
                page:SetHeight(math.max(1, height + 52))
                if EXUI.ModuleScrollFrame.UpdateScrollChildRect then
                    EXUI.ModuleScrollFrame:UpdateScrollChildRect()
                end
                if ownerHeightChanged then ownerHeightChanged(height) end
            end
            page._exV2Owner = owner
            page._exV2Session = EXUI:MountSettingsPageV2(page, v2Entry.pageId, owner)
            if type(owner.AttachSession) == "function" then
                owner:AttachSession(page._exV2Session)
            end
            ExwindTools:UpdateState(currentModuleKey .. ".PanelRendered", GetTime())
        elseif usesCardDeclaration then
            local sharedCardDefaults = type(EXUI.GetSettingsCardLayoutDefaults) == "function"
                and EXUI:GetSettingsCardLayoutDefaults() or nil
            local baseBottom = type(sharedCardDefaults) == "table" and sharedCardDefaults.bottom
                or (_G.ExwindGrid.CardLayoutDefaults and _G.ExwindGrid.CardLayoutDefaults.bottom)
                or 0
            local mountContext = {
                pageId = currentModuleKey,
                regionId = "module-settings",
                binding = centralController and centralController.binding or nil,
                config = config,
                moduleKey = currentModuleKey,
                settingsPageTitle = moduleMeta.Name,
                settingsPageDescription = moduleMeta.Desc,
                scrollFrame = EXUI.ModuleScrollFrame,
                layoutDefaults = { bottom = (tonumber(baseBottom) or 0) + 52 },
            }
            if pageDeclarationMode == "sections" then
                page._exCardSession = _G.ExwindGrid:MountSettingsDeclaration(page, layoutData, mountContext)
            else
                page._exCardSession = _G.ExwindGrid:MountCards(page, layoutData, mountContext)
            end
            ExwindTools:UpdateState(currentModuleKey .. ".PanelRendered", GetTime())
        else
            page._exCardSession = nil
            _G.ExwindGrid:Render(page, layoutData, config, currentModuleKey, function()
                -- Render 完成后通知当前模块面板已刷新（各模块可订阅此事件更新动态内容）
                ExwindTools:UpdateState(currentModuleKey .. ".PanelRendered", GetTime())
            end)
        end

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

        local resetBtn = EXUI:CreateButton(page, 120, GM.size.buttonHeight, L["重置当前模块设置"], function()
            local moduleName = (moduleMeta and moduleMeta.Name) or EXUI.CurrentModule or L["当前模块"]
            local message = string.format(L["你将重置%s模块设置，并重载。是否确定？"], moduleName)
            local moduleKey = EXUI.CurrentModule
            EXUI:ShowConfirmDialog({
                sourceAddon = "ExwindTools", sourceModule = moduleName,
                title = L["重置当前模块设置"], text = message,
                confirmText = L["确定重置"], cancelText = L["取消"], danger = true,
                onConfirm = function()
                    ResetModuleConfirmed(moduleKey)
                end,
            })
        end, { variant = "danger", compact = true })
        local resetLabel = resetBtn:GetFontString()
        resetBtn:SetWidth(math.max(GM.size.buttonMinWidth,
            math.ceil(resetLabel:GetUnboundedStringWidth()) + GM.space.buttonPaddingX * 2))
        resetBtn:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 16)
        resetBtn:SetFrameLevel(page:GetFrameLevel() + 50)
        resetBtn._exModuleSettingsTransient = true
        if not usesCardDeclaration and not usesV2Declaration then
            page:SetHeight((page:GetHeight() or 1) + 52)
        end

        -- [New v4.2] 如果处于开发者模式，在右上角显示“编辑”按钮
        if ExwindTools.State.DevMode and not usesV2Declaration then
            local editBtn = EXUI:CreateButton(page, 120, ExwindTools.GUIMetrics.size.buttonHeight, L["|cff00ff00编辑布局|r"], function()
                _G.ExwindGrid:ToggleLiveEdit(page, EXUI.CurrentModule)
            end)
            if usesCardDeclaration then
                -- Card 标题栏右侧属于折叠按钮。开发者入口放进已经为 reset
                -- 预留的 footer，避免以更高 frame level 盖住第一张卡的交互。
                editBtn:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 20, 16)
            else
                editBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -20, -5)
            end
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
    pageTitle:SetFont(defaultFontPath, GM.font.pageTitle, "OUTLINE")
    pageTitle:SetPoint("TOPLEFT", 16, yOffset)
    pageTitle:SetText(L["状态总控"])
    pageTitle:SetTextColor(unpack(GC.text))
    yOffset = yOffset - 38

    local pageIntro = EXUI:CreateVisualFontString(page, EXFONTFRAME)
    pageIntro:SetFont(defaultFontPath, GM.font.title, "")
    pageIntro:SetPoint("TOPLEFT", 20, yOffset)
    pageIntro:SetWidth(sectionWidth)
    pageIntro:SetJustifyH("LEFT")
    pageIntro:SetText(L["实时查看 ExwindTools 当前环境、玩家状态与核心运行信息。"])
    pageIntro:SetTextColor(unpack(GC.textDim))
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
        header:SetFont(defaultFontPath, GM.font.dialogTitle, "OUTLINE")
        header:SetPoint("TOPLEFT", 16, yOffset)
        header:SetText(title)
        header:SetTextColor(unpack(GC.text))
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
                label:SetFont(defaultFontPath, GM.font.label, "OUTLINE")
                label:SetPoint("TOPLEFT", x, rowTop)
                label:SetWidth(labelWidth)
                label:SetJustifyH("LEFT")
                label:SetJustifyV("TOP")
                label:SetText(field.label)
                label:SetTextColor(unpack(GC.textPlaceholder))

                local value = EXUI:CreateVisualFontString(page, EXFONTFRAME)
                value:SetFont(defaultFontPath, GM.font.fieldValue, "")
                value:SetPoint("TOPLEFT", x + labelWidth + 10, rowTop)
                value:SetWidth(width - labelWidth - 10)
                value:SetJustifyH("LEFT")
                value:SetJustifyV("TOP")
                value:SetText(field.value)
                value:SetTextColor(unpack(GC.text))

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
        modText:SetFont(defaultFontPath, GM.font.title, "")
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
    EXUI:SyncScrollChildWidths()
    local page, isNew = EXUI:GetCachedPage("ProfileManager", EXUI.RightScrollChild)
    EXUI.ActivePageFrame = page
    EXUI._InternalPageFrame = page

    if not EXUI.ProfileState then
        EXUI.ProfileState = {
            exportSelected = {},
            importSelected = {},
            parsedData = nil,
            mergeMode = "replace",
        }
    end
    local state = EXUI.ProfileState
    if not isNew then
        if page.RelayoutProfileManagerPage then page:RelayoutProfileManagerPage() end
        EXUI.RightScrollChild:SetHeight(page:GetHeight())
        return
    end

    local Export = ExwindTools.Export
    local sectionWidth = math.max(620, math.min((page:GetWidth() or 800) - 40, 980))
    local innerWidth = sectionWidth - 36
    page.ProfileColumnCount = innerWidth >= 750 and 3 or 2
    local function StyleMultiline(field)
        local hovered, focused = false, false
        local function Paint()
            EXUI:SetControlSurface(field, GM.radius.control,
                (hovered or focused) and GC.inputHover or GC.input,
                focused and GC.inputFocusBorder or (hovered and GC.inputHoverBorder or GC.inputBorder))
        end
        field.scrollFrame:HookScript("OnEnter", function() hovered = true; Paint() end)
        field.scrollFrame:HookScript("OnLeave", function() hovered = false; Paint() end)
        field.editBox:HookScript("OnEnter", function() hovered = true; Paint() end)
        field.editBox:HookScript("OnLeave", function() hovered = false; Paint() end)
        field.editBox:HookScript("OnEditFocusGained", function() focused = true; Paint() end)
        field.editBox:HookScript("OnEditFocusLost", function() focused = false; Paint() end)
        Paint()
    end

    local title = EXUI:CreateVisualFontString(page, EXFONTFRAME)
    title:SetFont(ExwindTools.MAIN_FONT, GM.font.tools.profileTitle, "OUTLINE")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -18)
    title:SetText(L["配置管理"])
    title:SetTextColor(unpack(GC.text))

    local exportSection = CreateFrame("Frame", nil, page, "BackdropTemplate")
    exportSection:SetSize(sectionWidth, 400)
    exportSection:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -74)
    EXUI:SetControlSurface(exportSection, GM.radius.card, GC.card, GC.cardBorder)
    page.ProfileExportSection = exportSection
    local exportTitle = EXUI:CreateVisualFontString(exportSection, EXFONTFRAME)
    exportTitle:SetFont(ExwindTools.MAIN_FONT, GM.font.cardTitle, "OUTLINE")
    exportTitle:SetPoint("TOPLEFT", exportSection, "TOPLEFT", 18, -17)
    exportTitle:SetText(L["导出配置"])
    exportTitle:SetTextColor(unpack(GC.text))

    local nameWidth = math.floor((innerWidth - 16) * 0.55)
    local authorWidth = innerWidth - nameWidth - 16
    local nameInput = EXUI:CreateEditBox(exportSection, L["我的配置"], nameWidth, GM.size.inputHeight,
        L["配置名称:"], { labelPos = "top" })
    nameInput:SetPoint("TOPLEFT", exportSection, "TOPLEFT", 18, -76)
    local authorInput = EXUI:CreateEditBox(exportSection, "", authorWidth, GM.size.inputHeight,
        L["导出者:"], { labelPos = "top", placeholder = L["留空则使用当前名"] })
    authorInput:SetPoint("TOPLEFT", nameInput, "TOPRIGHT", 16, 0)
    local noteInput = EXUI:CreateEditBox(exportSection, "", innerWidth, 76,
        L["备注说明:"], { labelPos = "top" })
    noteInput:SetPoint("TOPLEFT", exportSection, "TOPLEFT", 18, -154)
    StyleMultiline(noteInput)

    local moduleLabel = EXUI:CreateVisualFontString(exportSection, EXFONTFRAME)
    moduleLabel:SetFont(ExwindTools.MAIN_FONT, GM.font.tools.profileLabel, "OUTLINE")
    moduleLabel:SetPoint("TOPLEFT", exportSection, "TOPLEFT", 18, -257)
    moduleLabel:SetText(L["选择导出模块:"])
    moduleLabel:SetTextColor(unpack(GC.text))
    local selectAllBtn = EXUI:CreateButton(exportSection, 62, GM.size.buttonHeight, L["全选"], function()
        local modules = Export:GetExportableModules()
        for _, m in ipairs(modules) do state.exportSelected[m.key] = true end
        EXUI:RefreshExportCheckboxes()
    end, { variant = "secondary", compact = true })
    selectAllBtn:SetPoint("LEFT", moduleLabel, "RIGHT", 16, 0)
    local selectNoneBtn = EXUI:CreateButton(exportSection, 74, GM.size.buttonHeight, L["全不选"], function()
        wipe(state.exportSelected)
        EXUI:RefreshExportCheckboxes()
    end, { variant = "secondary", compact = true })
    selectNoneBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 8, 0)

    local exportList = CreateFrame("Frame", nil, exportSection)
    exportList:SetSize(innerWidth, 1)
    exportList:SetPoint("TOPLEFT", exportSection, "TOPLEFT", 18, -294)
    EXUI.ExportListFrame = exportList
    local exportBtn = EXUI:CreateButton(exportSection, 200, GM.size.buttonHeight, L["生成导出字符串"], function()
        local profileName = nameInput:GetText() or L["未命名"]
        local authorName = authorInput:GetText() or ""
        local note = noteInput:GetText() or ""
        local result, err = Export:ExportModules(state.exportSelected, profileName, authorName, note)
        if result then
            EXUI:ShowExportResultPopup(result, profileName)
        else
            print("|cffff0000[ExwindTools]|r " .. L["导出失败: "] .. (err or L["未知错误"]))
        end
    end, { variant = "primary", compact = true })
    exportBtn:SetPoint("BOTTOMRIGHT", exportSection, "BOTTOMRIGHT", -18, 18)
    EXUI.ExportGenBtn = exportBtn

    local importSection = CreateFrame("Frame", nil, page, "BackdropTemplate")
    importSection:SetSize(sectionWidth, 550)
    importSection:SetPoint("TOPLEFT", exportSection, "BOTTOMLEFT", 0, -18)
    EXUI:SetControlSurface(importSection, GM.radius.card, GC.card, GC.cardBorder)
    EXUI.ImportSection = importSection
    page.ProfileImportSection = importSection
    local importTitle = EXUI:CreateVisualFontString(importSection, EXFONTFRAME)
    importTitle:SetFont(ExwindTools.MAIN_FONT, GM.font.cardTitle, "OUTLINE")
    importTitle:SetPoint("TOPLEFT", importSection, "TOPLEFT", 18, -17)
    importTitle:SetText(L["导入配置"])
    importTitle:SetTextColor(unpack(GC.text))

    local importInput = EXUI:CreateEditBox(importSection, "", innerWidth, 96,
        L["粘贴导入字符串:"], { labelPos = "top" })
    importInput:SetPoint("TOPLEFT", importSection, "TOPLEFT", 18, -76)
    StyleMultiline(importInput)
    EXUI.ImportStringField = importInput
    local parseBtn = EXUI:CreateButton(importSection, 120, GM.size.buttonHeight, L["解析预览"], function()
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
    end, { variant = "secondary", compact = true })
    parseBtn:SetPoint("TOPLEFT", importSection, "TOPLEFT", 18, -192)

    local previewFrame = CreateFrame("Frame", nil, importSection)
    previewFrame:SetSize(innerWidth, 1)
    previewFrame:SetPoint("TOPLEFT", importSection, "TOPLEFT", 18, -250)
    EXUI.ImportPreviewFrame = previewFrame
    local pName = EXUI:CreateEditBox(previewFrame, "", nameWidth, GM.size.inputHeight,
        GC.markup.textDim .. L["配置名称:"] .. "|r", { labelPos = "top" })
    pName:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, -22)
    pName.editBox:Disable()
    EXUI:ApplyControlAppearance(pName)
    EXUI.ImportPreviewName = pName
    local pAuthor = EXUI:CreateEditBox(previewFrame, "", authorWidth, GM.size.inputHeight,
        GC.markup.textDim .. L["作者:"] .. "|r", { labelPos = "top" })
    pAuthor:SetPoint("TOPLEFT", pName, "TOPRIGHT", 16, 0)
    pAuthor.editBox:Disable()
    EXUI:ApplyControlAppearance(pAuthor)
    EXUI.ImportPreviewAuthor = pAuthor
    local pNote = EXUI:CreateEditBox(previewFrame, "", innerWidth, 62,
        GC.markup.textDim .. L["备注说明:"] .. "|r", { labelPos = "top" })
    pNote:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, -94)
    pNote.editBox:Disable()
    EXUI:SetControlSurface(pNote, GM.radius.control, GC.inputDisabled, GC.inputDisabledBorder)
    EXUI.ImportPreviewNote = pNote
    local importModLabel = EXUI:CreateVisualFontString(previewFrame, EXFONTFRAME)
    importModLabel:SetFont(ExwindTools.MAIN_FONT, GM.font.tools.profileLabel, "OUTLINE")
    importModLabel:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, -184)
    importModLabel:SetTextColor(unpack(GC.textDim))
    EXUI.ImportPreviewLabel = importModLabel
    local importList = CreateFrame("Frame", nil, previewFrame)
    importList:SetSize(innerWidth, 1)
    importList:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 0, -220)
    EXUI.ImportListFrame = importList
    local applyBtn = EXUI:CreateButton(importSection, 160, GM.size.buttonHeight, L["应用导入"], function()
        if not state.parsedData then
            print("|cffff0000[ExwindTools]|r " .. L["请先解析导入字符串"])
            return
        end
        local count = Export:ApplyImport(state.parsedData, state.importSelected, "replace")
        if count > 0 then
            EXUI:ShowDialog({
                sourceAddon = "ExwindTools", sourceModule = L["配置分享"],
                id = "EXWIND_IMPORT_SUCCESS", title = L["提示"],
                text = string.format(L["导入成功！已导入 %d 个模块的配置。\n\n配置需要重载界面才能完全生效。"], count),
                defaultButton = "reload", cancelButton = "later",
                buttons = {
                    { id = "later", text = L["稍后重载"], variant = "secondary" },
                    { id = "reload", text = L["立即重载"], variant = "primary", onClick = function() C_UI.Reload() end },
                },
            })
        else
            print("|cffff8800[ExwindTools]|r " .. L["未导入任何模块 (可能未选中或数据为空)"])
        end
    end, { variant = "primary", compact = true })
    applyBtn:SetPoint("BOTTOMRIGHT", importSection, "BOTTOMRIGHT", -18, 18)

    function page:RelayoutProfileManagerPage()
        local width = math.max(560, math.min((self:GetWidth() or 800) - 40, 980))
        if self.ProfileLayoutWidth == width then return end
        self.ProfileLayoutWidth = width
        local inner = width - 36
        local columns = inner >= 750 and 3 or 2
        self.ProfileColumnCount = columns
        exportSection:SetWidth(width)
        importSection:SetWidth(width)
        local firstWidth = math.floor((inner - 16) * 0.55)
        local secondWidth = inner - firstWidth - 16
        local function ResizeField(field, fieldWidth)
            field:SetWidth(fieldWidth)
            if field.scrollFrame then
                local scrollChild = field.scrollFrame:GetScrollChild()
                if scrollChild then scrollChild:SetWidth(math.max(1, fieldWidth - 20)) end
            end
        end
        ResizeField(nameInput, firstWidth)
        ResizeField(authorInput, secondWidth)
        ResizeField(noteInput, inner)
        ResizeField(importInput, inner)
        ResizeField(pName, firstWidth)
        ResizeField(pAuthor, secondWidth)
        ResizeField(pNote, inner)
        exportList:SetWidth(inner)
        previewFrame:SetWidth(inner)
        importList:SetWidth(inner)
        local function ArrangeCheckboxes(list)
            local gap = 12
            local cellWidth = math.floor((inner - (columns - 1) * gap) / columns)
            local count = 0
            for _, cb in ipairs({ list:GetChildren() }) do
                local index = cb._profileIndex
                if index then
                    cb:SetSize(cellWidth, GM.size.checkboxRowHeight)
                    cb:ClearAllPoints()
                    cb:SetPoint("TOPLEFT", list, "TOPLEFT",
                        ((index - 1) % columns) * (cellWidth + gap),
                        -math.floor((index - 1) / columns) * 34)
                    cb.label:SetWidth(math.max(1, cellWidth - 36))
                    count = math.max(count, index)
                end
            end
            local height = math.max(38, math.ceil(count / columns) * 34 + 6)
            list:SetHeight(height)
            return height
        end
        local exportHeight = ArrangeCheckboxes(exportList)
        local importHeight = ArrangeCheckboxes(importList)
        exportSection:SetHeight(294 + exportHeight + 66)
        importSection:SetHeight(250 + 220 + importHeight + 64)
        self:SetHeight(74 + exportSection:GetHeight() + 18 + importSection:GetHeight() + 28)
        EXUI.RightScrollChild:SetHeight(self:GetHeight())
    end

    EXUI:RefreshExportCheckboxes()
    EXUI:RefreshImportPreview(nil)
    page:RelayoutProfileManagerPage()
    page:SetScript("OnSizeChanged", function(self)
        self:RelayoutProfileManagerPage()
    end)
end

-- =========================================================
-- 刷新导出模块复选框
-- =========================================================
function EXUI:RefreshExportCheckboxes()
    local Export = ExwindTools.Export
    local state = EXUI.ProfileState
    local parent = EXUI.ExportListFrame
    if not parent then return end

    local factory = _G.ExwindFactory
    for _, child in ipairs({ parent:GetChildren() }) do
        child._profileIndex = nil
        factory:Release(child._fromPool, child)
    end

    local modules = Export:GetExportableModules()
    local columns = parent:GetParent():GetParent().ProfileColumnCount or 3
    local columnGap = 12
    local columnWidth = math.floor((parent:GetWidth() - (columns - 1) * columnGap) / columns)
    for index, m in ipairs(modules) do
        local cb = EXUI:CreateCheckbox(parent, m.name, state.exportSelected[m.key] or false, function(checked)
            state.exportSelected[m.key] = checked
        end)
        cb._profileIndex = index
        cb:SetSize(columnWidth, GM.size.checkboxRowHeight)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT",
            ((index - 1) % columns) * (columnWidth + columnGap),
            -math.floor((index - 1) / columns) * 34)
        cb.label:SetWidth(math.max(1, columnWidth - 36))
        cb.label:SetJustifyH("LEFT")
        cb.label:SetWordWrap(false)
    end

    local rows = math.ceil(#modules / columns)
    local listHeight = math.max(38, rows * 34 + 6)
    parent:SetHeight(listHeight)
    local page = parent:GetParent():GetParent()
    page.ProfileExportSection:SetHeight(294 + listHeight + 66)
    page:SetHeight(74 + page.ProfileExportSection:GetHeight() + 18
        + page.ProfileImportSection:GetHeight() + 28)
    EXUI.RightScrollChild:SetHeight(page:GetHeight())
end

function EXUI:RefreshImportPreview(summary)
    local state = EXUI.ProfileState
    local parent = EXUI.ImportListFrame
    if not parent then return end

    local factory = _G.ExwindFactory
    for _, child in ipairs({ parent:GetChildren() }) do
        child._profileIndex = nil
        factory:Release(child._fromPool, child)
    end

    if summary then
        EXUI.ImportPreviewName:SetText(summary.profileName or L["未命名"])
        EXUI.ImportPreviewAuthor:SetText(summary.author or L["未知"])
        EXUI.ImportPreviewNote:SetText(summary.note or L["无备注说明"])
        EXUI.ImportPreviewLabel:SetText("|cff00ff80" ..
            L["解析成功预览:"] .. "|r " .. string.format("|cffaaaaaa(" .. L["版本: %s"] .. ")|r", summary.addonVersion))
    else
        EXUI.ImportPreviewName:SetText("")
        EXUI.ImportPreviewAuthor:SetText("")
        EXUI.ImportPreviewNote:SetText("")
        EXUI.ImportPreviewLabel:SetText(GC.markup.placeholder .. L["等待解析..."] .. "|r")
    end

    local modules = summary and summary.modules or {}
    local page = parent:GetParent():GetParent():GetParent()
    local columns = page.ProfileColumnCount or 3
    local columnGap = 12
    local columnWidth = math.floor((parent:GetWidth() - (columns - 1) * columnGap) / columns)
    for index, m in ipairs(modules) do
        local labelText = m.name
        if not m.exists then
            labelText = "|cffff6666" .. labelText .. " (" .. L["未安装"] .. ")|r"
        else
            labelText = "|cff90ee90" .. labelText .. "|r"
        end
        local cb = EXUI:CreateCheckbox(parent, labelText, state.importSelected[m.key] or false, function(checked)
            state.importSelected[m.key] = checked
        end)
        cb._profileIndex = index
        cb:SetSize(columnWidth, GM.size.checkboxRowHeight)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT",
            ((index - 1) % columns) * (columnWidth + columnGap),
            -math.floor((index - 1) / columns) * 34)
        cb.label:SetWidth(math.max(1, columnWidth - 36))
        cb.label:SetJustifyH("LEFT")
        cb.label:SetWordWrap(false)
    end

    local rows = math.ceil(#modules / columns)
    local listHeight = math.max(38, rows * 34 + 6)
    parent:SetHeight(listHeight)
    page.ProfileImportSection:SetHeight(250 + 220 + listHeight + 64)
    page:SetHeight(74 + page.ProfileExportSection:GetHeight() + 18
        + page.ProfileImportSection:GetHeight() + 28)
    EXUI.RightScrollChild:SetHeight(page:GetHeight())
end

-- =========================================================
-- 导出结果弹窗
-- =========================================================
function EXUI:ShowExportResultPopup(exportString, profileName)
    return self:ShowDialog({
        sourceAddon = "ExwindTools", sourceModule = L["配置分享"],
        id = "EXWIND_EXPORT_RESULT", title = L["导出成功"] .. " - " .. profileName,
        text = L["导出弹窗提示"], width = 600, movable = true, enterConfirms = false,
        input = { text = exportString, multiline = true, readOnly = true, highlight = true, height = 200 },
        cancelButton = "close",
        buttons = {
            { id = "select", text = L["全选复制"], variant = "secondary", close = false,
                onClick = function(_, dialog) dialog.activeInput:SetFocus(); dialog.activeInput:HighlightText() end },
            { id = "close", text = L["关闭"], variant = "primary" },
        },
        onShow = function(dialog)
            local token = dialog._dialogToken
            dialog.activeInput:SetScript("OnKeyUp", function(input, key)
                if key ~= "C" or not IsControlKeyDown() then return end
                input:ClearFocus()
                dialog.body:SetText(L["已复制到剪贴板"])
                C_Timer.After(0.6, function()
                    if dialog._dialogToken == token then EXUI:HideDialog("EXWIND_EXPORT_RESULT") end
                end)
            end)
        end,
    })
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
