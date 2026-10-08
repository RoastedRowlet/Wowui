---@diagnostic disable: undefined-global

-- 唯一编辑模式权威：注册、生命周期、世界预览、输入、视觉、控制面板和设置页路由。
-- 模块只能注册纯预览声明；AnchorController 与 VisualLayers 都只是被这里调用的底层工具。

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI
if not EXUI then return end

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetCursorPosition = _G.GetCursorPosition
local L = ExwindTools.L

_G.EXCORE12S2 = _G.EXCORE12S2 or {}
local coreDB = _G.EXCORE12S2
coreDB.EditMode = coreDB.EditMode or {}
local settings = coreDB.EditMode
settings.visibleByKey = settings.visibleByKey or {}
if settings.overlayVisible == nil then settings.overlayVisible = true end

-- 编辑覆盖层色板只能在唯一 Core 定义。模块只能声明 addon，不能传入任何颜色或绘制信息。
local OVERLAY_PROFILES = {
    EXBoss = {
        fill = { r = 1.00, g = 0.80, b = 0.30, a = 0.18 },
        border = { r = 1.00, g = 0.92, b = 0.68, a = 1.00 },
        borderSize = 2,
        title = { r = 1.00, g = 0.97, b = 0.84, a = 1.00 },
        titleOutline = "THICKOUTLINE",
        titleShadow = { r = 0.20, g = 0.12, b = 0.02, a = 1.00, x = 2, y = -2 },
    },
    ExwindTools = {
        fill = { r = 0.52, g = 0.28, b = 0.88, a = 0.18 },
        border = { r = 0.84, g = 0.66, b = 1.00, a = 1.00 },
        borderSize = 2,
        title = { r = 0.92, g = 0.84, b = 1.00, a = 1.00 },
        titleOutline = "OUTLINE",
        titleShadow = { r = 0.12, g = 0.03, b = 0.24, a = 1.00, x = 2, y = -2 },
    },
    EXAura = {
        titleStrata = "HIGH",
        fill = { r = 0.56, g = 0.25, b = 0.88, a = 0.16 },
        border = { r = 0.84, g = 0.62, b = 1.00, a = 1.00 },
        borderSize = 2,
        title = { r = 0.96, g = 0.88, b = 1.00, a = 1.00 },
        titleOutline = "OUTLINE",
        titleShadow = { r = 0.12, g = 0.02, b = 0.22, a = 1.00, x = 2, y = -2 },
        quietRoot = true,
        -- 画面直编的会话视觉（选框、手柄、描边、群组外框）随编辑会话存在，不受 Core “显示覆盖层”
        -- 面板开关控制：该开关只管全局编辑模式里的模块覆盖层，EXAura 会话期间没有入口去切换它。
        sessionWorldAlwaysVisible = true,
        -- [WEB-REQ 08/10/13/35/59/60/61] 画面直编的视觉常量：与网页原型同色（#1e90ff 主色），
        -- 尺寸按原型 ×1.25 画布换算（原型 handle 9 → 8，选框外扩 6/11 → 5/9）。
        world = {
            accent = { r = 0.118, g = 0.565, b = 1.00, a = 1.00 },
            hover = { r = 0.44, g = 0.72, b = 1.00, a = 0.95 },
            folder = { r = 0.24, g = 0.55, b = 0.99, a = 0.90 },
            faintAccent = { r = 0.44, g = 0.72, b = 1.00, a = 0.35 },
            green = { r = 0.25, g = 0.75, b = 0.44, a = 1.00 },
            yellow = { r = 1.00, g = 0.81, b = 0.35, a = 0.92 },
            dashed = { r = 1.00, g = 1.00, b = 1.00, a = 0.55 },
            faint = { r = 1.00, g = 1.00, b = 1.00, a = 0.30 },
            cell = { r = 1.00, g = 1.00, b = 1.00, a = 0.30 },
            cellUsed = { r = 1.00, g = 1.00, b = 1.00, a = 0.00 },
            cellCurrent = { r = 0.47, g = 0.71, b = 1.00, a = 0.75 },
            cellCurrentUsed = { r = 0.47, g = 0.71, b = 1.00, a = 0.30 },
            chipText = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 },
            chipDark = { r = 0.024, g = 0.071, b = 0.122, a = 1.00 },
            chipBackground = { r = 0.00, g = 0.00, b = 0.00, a = 0.55 },
            chipMuted = { r = 0.91, g = 0.92, b = 0.93, a = 1.00 },
            label = { r = 0.74, g = 0.82, b = 1.00, a = 1.00 },
            labelBackground = { r = 0.00, g = 0.00, b = 0.00, a = 0.60 },
            handleRing = { r = 0.00, g = 0.00, b = 0.00, a = 0.50 },
            ringHole = { r = 0.08, g = 0.09, b = 0.11, a = 0.90 },
            pad = 5, padSmall = 9, small = 24, handle = 8, edge = 10, badgeSize = 11,
        },
    },
}

local state = {
    phase = "OFF",
    modules = {},
    routers = {},
    editSessionProviders = {},
    editSessions = {},
    worldOverlayPool = {},
    selectionRoots = {},
    presentationHostPool = {},
    presentationRoot = nil,
    overlayVisible = settings.overlayVisible == true,
    exitCallback = nil,
}
EXUI.EditModeState = state

local function ModuleID(module)
    return module.addon .. ":" .. module.key
end

-- 编辑模式遍历的是所有已注册模块；任何一个模块的预览回调失败都不能打断
-- 其它模块的进入、刷新或退出。错误必须保留模块 ID、生命周期阶段和调用栈，
-- 既写入统一错误日志，也立即打印给开发者。
local function BuildEditModeModuleStageError(module, stage, original)
    local stack
    if type(_G.debugstack) == "function" then
        stack = _G.debugstack(3, 40, 40)
    elseif _G.debug and type(_G.debug.traceback) == "function" then
        stack = _G.debug.traceback("", 3)
    else
        stack = "<debug stack unavailable>"
    end
    return "EXUI EditMode module stage failed"
        .. " | module=" .. ModuleID(module)
        .. " | stage=" .. tostring(stage)
        .. "\noriginal=" .. tostring(original)
        .. "\nstack=" .. tostring(stack)
end

local function ReportEditModeModuleFailure(module, stage, detail)
    local source = "EditMode[" .. ModuleID(module) .. "][" .. tostring(stage) .. "]"
    if type(ExwindTools.LogError) == "function" then
        ExwindTools:LogError(source, detail)
    end
    print(L["|cffff0000[ExwindTools] 编辑模式模块错误 ["] .. ModuleID(module) .. "][" .. tostring(stage) .. "]: " .. tostring(detail) .. "|r")
end

local function RunEditModeModuleStage(module, stage, callback)
    local ok, result = xpcall(callback, function(original)
        return BuildEditModeModuleStageError(module, stage, original)
    end)
    if not ok then
        ReportEditModeModuleFailure(module, stage, result)
        return false, result
    end
    return true, result
end

local function RequireFrame(frame, context)
    if not frame or type(frame.GetObjectType) ~= "function" or frame:GetObjectType() ~= "Frame" then
        error(context .. " must return a Frame", 3)
    end
    return frame
end

local function GetProfile(module)
    local profile = OVERLAY_PROFILES[module.addon]
    if not profile then error("unregistered edit overlay addon: " .. module.addon, 3) end
    return profile
end

local function GetTitleSize()
    return 18
end

local function GetModuleWorldBounds(module)
    if type(module.GetWorldBounds) == "function" then
        return module.GetWorldBounds()
    end
    if module.worldPreview and type(module.worldPreview.GetWorldBounds) == "function"
        and type(module.worldPreview.worldBounds) == "table" then
        return module.worldPreview:GetWorldBounds()
    end
    return nil
end

local function SetOverlay(module, shown)
    local host = module.host
    if not host then return end
    local worldBounds = GetModuleWorldBounds(module)
    local layer = EXUI:SetEditModeVisualLayerShown(
        host,
        shown == true,
        GetProfile(module),
        module.name,
        GetTitleSize(module),
        worldBounds
    )
    -- World renderer 的蓝框就是正式 SelectionFrame：它和可视范围使用同一份
    -- 声明式四边，并由 AnchorController 接收整体拖动/右键输入。
    module.__worldSelectionFrame = layer and layer.frame or nil
    return module.__worldSelectionFrame
end

local function SetWorldInput(module, enabled)
    local controller = module.host and module.host.__ExwindAnchorController
    if not controller or type(controller.SetEditInteraction) ~= "function" then
        error("registered editable module has no AnchorController: " .. ModuleID(module), 3)
    end
    local target = enabled == true and state.overlayVisible and module.__worldRendererActive and module.__worldSelectionFrame or nil
    controller:SetEditInteraction(enabled == true, function()
        EXUI:OpenModuleSettings(module.addon, module.settingsPage)
    end, target)
end

-- 标准 renderer 已计算世界预览的真实可见非对称 union。唯一编辑模式只把这个
-- 通用几何结果交给 AnchorController：host 命中范围与 Overlay 紧贴 union，而
-- Controller 负责保证保存的模块逻辑坐标不被这份编辑期视觉偏移改写。
local function ApplyWorldBounds(module)
    local controller = module.host and module.host.__ExwindAnchorController
    if not controller or type(controller.SetEditBoundsOffset) ~= "function" then
        error("registered editable module has no bounds-capable AnchorController: " .. ModuleID(module), 3)
    end
    -- semantic-root 保留模块 anchorFrame 的语义原点；内容 union 只用于
    -- 命中范围，不能把 union center 再写回整体锚点造成世界偏移。
    if module.worldPreview and module.worldPreview.worldAnchorMode == "semantic-root" then
        controller:SetEditBoundsOffset(0, 0)
        return
    end
    local bounds = module.worldPreview:GetWorldBounds()
    controller:SetEditBoundsOffset(bounds.anchorOffsetX, bounds.anchorOffsetY)
end

local function ClearWorldBounds(module)
    local controller = module.host and module.host.__ExwindAnchorController
    if not controller or type(controller.SetEditBoundsOffset) ~= "function" then
        error("registered editable module has no bounds-capable AnchorController: " .. ModuleID(module), 3)
    end
    controller:SetEditBoundsOffset(0, 0)
end

local function ApplySemanticRootHostBounds(module)
    -- 暴雪式 world renderer 提供独立的声明式 SelectionFrame；它绝不能把
    -- selection 范围反写到语义 Anchor host。
    if module.__worldRendererActive then return end
    local isStandardSemanticRoot = module.worldPreview and module.worldPreview.worldAnchorMode == "semantic-root"
    if not isStandardSemanticRoot and type(module.GetWorldBounds) ~= "function" then return end
    local host = module.host
    local bounds = GetModuleWorldBounds(module)
    if not host or type(bounds) ~= "table" then return end
    if not module.__editWorldPreviewOriginalSize then
        module.__editWorldPreviewOriginalSize = {
            width = host:GetWidth(),
            height = host:GetHeight(),
        }
    end
    -- semantic-root 保留内容的逻辑原点。union 可能整体偏向一侧，直接把
    -- host 设成 union 宽高会让语义根落在命中框外；按 union 相对原点的偏移
    -- 对称扩展 host，既覆盖全部内容，又不改变 layout/保存坐标的中心。
    local width = bounds.width + math.abs(bounds.anchorOffsetX or 0) * 2
    local height = bounds.height + math.abs(bounds.anchorOffsetY or 0) * 2
    host:SetSize(width, height)
end

local function RestoreSemanticRootHostBounds(module)
    local original = module.__editWorldPreviewOriginalSize
    local host = module.host
    if original and host then
        host:SetSize(original.width, original.height)
    end
    module.__editWorldPreviewOriginalSize = nil
end

-- 世界预览必须在配置面板（HIGH）之上。层级的临时改写只由唯一 Core
-- 生命周期持有；无论全局编辑模块还是 Provider session 实体都走同一对函数。
local function ElevateWorldPreviewHost(module, host)
    if module.__editWorldPreviewHost then
        if module.__editWorldPreviewHost ~= host then
            error("world preview host changed while materialized: " .. ModuleID(module), 3)
        end
        return
    end

    module.__editWorldPreviewHost = host
    module.__editWorldPreviewOriginalStrata = host:GetFrameStrata()
    module.__editWorldPreviewOriginalLevel = host:GetFrameLevel()
    host:SetFrameStrata("TOOLTIP")
end

local function RestoreWorldPreviewHost(module)
    local host = module.__editWorldPreviewHost
    if not host then return end

    host:SetFrameStrata(module.__editWorldPreviewOriginalStrata)
    host:SetFrameLevel(module.__editWorldPreviewOriginalLevel)
    module.__editWorldPreviewHost = nil
    module.__editWorldPreviewOriginalStrata = nil
    module.__editWorldPreviewOriginalLevel = nil
end

-- 标准世界预览的进入/退出只由唯一编辑模式状态机决定。少数拥有运行时
-- anchor 视觉的模块需要在这个确定时点同步隐藏或恢复自身运行时外观；回调
-- 不拥有 preview、不能创建 Frame，也不能改变 Core 生命周期。
local function NotifyWorldPreviewState(module, active)
    if module.OnWorldPreviewStateChanged then
        module.OnWorldPreviewStateChanged(active == true)
    end
end

-- TimerBar 这类模块可以把世界编辑态交给自身的唯一 renderer。它仍然使用
-- 同一个 host、AnchorController、输入和覆盖层；差别仅是没有 StandardPreview
-- 的第二棵可见 Frame 树，也没有内容 union 参与锚点计算。
local function UsesWorldRenderer(module)
    return type(module.RenderWorld) == "function"
        and type(module.ReleaseWorld) == "function"
        and type(module.GetWorldBounds) == "function"
end

-- renderer 世界宿主是一笔由 Core 管理的事务：新的 RenderWorld 之前，旧的
-- renderer 必须完整 Release；Core 保留运行时抑制状态，因此不会把编辑所有权
-- 交给 provider。这里不恢复 host/anchor，因为替换后的 renderer 仍使用同一宿主。
local function ReplaceWorldRenderer(module)
    if not module.__worldRendererActive then return end
    SetWorldInput(module, false)
    SetOverlay(module, false)
    module.ReleaseWorld()
    module.__worldRendererActive = nil
    NotifyWorldPreviewState(module, true)
    module.__worldSelectionFrame = nil
end

local function ReleaseWorldPreview(module)
    if UsesWorldRenderer(module) then
        if module.__worldRendererActive then
            SetWorldInput(module, false)
            SetOverlay(module, false)
            module.ReleaseWorld()
            module.__worldRendererActive = nil
        end
    elseif module.worldPreview then
        SetOverlay(module, false)
        module.worldPreview:Release()
    end
    -- Release 已清除标准预览，或由模块唯一 renderer 恢复真实内容；模块现在才能按真实运行态恢复 anchor。
    NotifyWorldPreviewState(module, false)
    RestoreWorldPreviewHost(module)
    if module.host then
        RestoreSemanticRootHostBounds(module)
        ClearWorldBounds(module)
        SetWorldInput(module, false)
    end
    module.__worldSelectionFrame = nil
    module.host = nil
end

local function MaterializeWorldPreview(module)
    local host = RequireFrame(module.getAnchor(), "getAnchor() for " .. ModuleID(module))
    module.host = host
    ElevateWorldPreviewHost(module, host)
    if UsesWorldRenderer(module) then
        ReplaceWorldRenderer(module)
        -- 运行时显示/抑制状态只由 Core 进入此事务时切换；provider 只渲染到
        -- 指定 host，不能自行管理 SelectionFrame、整体拖动或编辑输入。
        NotifyWorldPreviewState(module, true)
        -- 在调用模块 renderer 前就标记活动状态。若 renderer 半途抛错，失败
        -- 清理仍会受保护地请求 ReleaseWorld，避免遗留半棵世界预览树。
        module.__worldRendererActive = true
        module.RenderWorld(host)
        -- TimerBar 的世界编辑覆盖层直接锚定 renderer 提供的声明式四角；不再
        -- 扫描子 Frame、延迟重试或反写语义 Anchor host 的尺寸。
        ClearWorldBounds(module)
        SetOverlay(module, state.overlayVisible)
        SetWorldInput(module, true)
        return
    end
    if not module.worldPreview then
        module.worldPreview = EXUI:CreateStandardPreview(host, {
            interactionMode = "world",
            worldAnchorMode = module.worldAnchorMode,
            renderExtraChildren = module.RenderPreviewExtraChildren,
        })
    end

    local preview = module.BuildPreview()
    if type(preview) ~= "table" or type(preview.definition) ~= "table" or type(preview.model) ~= "table" then
        error("BuildPreview() for " .. ModuleID(module) .. " must return { definition = table, model = table }", 3)
    end
    module.worldPreview:Materialize(preview.definition, preview.model)
    -- Materialize 已标记 host 为标准世界预览；模块必须在此后隐藏原运行时视觉，
    -- 不能让两套轨道/边框同时绘制。
    NotifyWorldPreviewState(module, true)
    ApplySemanticRootHostBounds(module)
    ApplyWorldBounds(module)
    SetWorldInput(module, true)
    SetOverlay(module, state.overlayVisible)
end

-- 失败后的回收只处理 Core 拥有的交互、覆盖层、宿主状态和生命周期标记。
-- renderer 的 ReleaseWorld 与模块状态回调也可能是模块代码，因此分别受保护；
-- 任一清理步骤失败只会额外打印该步骤，不会阻断其余清理或其它模块。
local function CleanupFailedWorldPreview(module)
    local host = module.host

    RunEditModeModuleStage(module, "failure-cleanup.input", function()
        if host and host.__ExwindAnchorController and type(host.__ExwindAnchorController.SetEditInteraction) == "function" then
            host.__ExwindAnchorController:SetEditInteraction(false)
        end
    end)
    RunEditModeModuleStage(module, "failure-cleanup.overlay", function()
        if module.__worldSelectionFrame then module.__worldSelectionFrame:Hide() end
    end)

    if UsesWorldRenderer(module) and module.__worldRendererActive then
        RunEditModeModuleStage(module, "failure-cleanup.release-renderer", function()
            module.ReleaseWorld()
        end)
    elseif module.worldPreview then
        RunEditModeModuleStage(module, "failure-cleanup.release-preview", function()
            module.worldPreview:Release()
        end)
    end

    RunEditModeModuleStage(module, "failure-cleanup.preview-state", function()
        NotifyWorldPreviewState(module, false)
    end)
    RunEditModeModuleStage(module, "failure-cleanup.restore-host", function()
        RestoreWorldPreviewHost(module)
    end)
    RunEditModeModuleStage(module, "failure-cleanup.restore-bounds", function()
        if host then
            RestoreSemanticRootHostBounds(module)
            local controller = host.__ExwindAnchorController
            if controller and type(controller.SetEditBoundsOffset) == "function" then
                controller:SetEditBoundsOffset(0, 0)
            end
        end
    end)

    module.__worldRendererActive = nil
    module.__worldSelectionFrame = nil
    module.host = nil
end

local function RefreshModule(module)
    if state.phase ~= "ACTIVE" then return true end
    local stage = settings.visibleByKey[ModuleID(module)] == false and "refresh.release" or "refresh.materialize"
    local ok, result = RunEditModeModuleStage(module, stage, function()
        if settings.visibleByKey[ModuleID(module)] == false then
            ReleaseWorldPreview(module)
        else
            MaterializeWorldPreview(module)
        end
    end)
    if not ok then
        CleanupFailedWorldPreview(module)
        return false, result
    end
    return true
end

local function RefreshAll()
    for _, module in pairs(state.modules) do RefreshModule(module) end
    EXUI:RefreshEditModeControlPanel()
end

local function SyncToggleButton()
    local button = EXUI.EditModeToggleButton
    if button then
        button:SetText(state.phase == "ACTIVE" and L["关闭编辑模式"] or L["启用编辑模式"])
    end
end

local function SetEnabled(enabled)
    if enabled then
        if state.phase == "ACTIVE" then return end
        state.phase = "ENTERING"
        state.phase = "ACTIVE"
        -- 控制面板只在每次新的编辑会话开始时回到中心；本会话内允许玩家拖动，
        -- 但不把位置写入任何 SavedVariables，退出后不会留下屏幕外坐标。
        if EXUI.EditModeControlPanel then EXUI.EditModeControlPanel.__resetPositionOnNextRefresh = true end
        RefreshAll()
        SyncToggleButton()
    else
        if state.phase == "OFF" then return end
        state.phase = "EXITING"
        for _, module in pairs(state.modules) do
            local ok = RunEditModeModuleStage(module, "disable.release", function()
                ReleaseWorldPreview(module)
            end)
            if not ok then CleanupFailedWorldPreview(module) end
        end
        state.phase = "OFF"
        EXUI:RefreshEditModeControlPanel()
        SyncToggleButton()
        local exitCallback = state.exitCallback
        state.exitCallback = nil
        if exitCallback then
            local ok, err = pcall(exitCallback)
            if not ok then
                print(L["|cffff0000[ExwindTools] 编辑模式退出回调失败: "] .. tostring(err) .. "|r")
            end
        end
    end
end

-- EXAura 等大规模目录使用独立会话，不会临时注册为全局 editable module。
-- Provider 只返回对象资料和只读 preview declaration；焦点、手动集合、实体
-- 生命周期与差分同步全部属于本文件。
local function GetSessionProvider(providerID)
    local provider = state.editSessionProviders[providerID]
    if not provider then error("unknown edit session provider " .. tostring(providerID), 3) end
    return provider
end

local function GetSession(providerID)
    local session = state.editSessions[providerID]
    if not session then error("edit session is not open for provider " .. tostring(providerID), 3) end
    return session
end

local function GetSessionObjectMap(provider)
    local catalog = provider.contract == "presentation-transaction" and provider.Catalog() or provider.GetObjects()
    local objects = provider.contract == "presentation-transaction" and catalog and catalog.objects or catalog
    if type(objects) ~= "table" then error("Catalog()/GetObjects() must return a table for " .. provider.id, 3) end
    local mapped = {}
    for key, object in pairs(objects) do
        if type(object) == "table" and (object.id == nil) and type(key) == "string" then object.id = key end
        if type(object) ~= "table" or type(object.id) ~= "string" or object.id == ""
            or type(object.supported) ~= "boolean" or type(object.loadMatched) ~= "boolean" then
            error("edit session object metadata is malformed for provider " .. provider.id, 3)
        end
        if mapped[object.id] then error("duplicate edit session object " .. provider.id .. ":" .. object.id, 3) end
        mapped[object.id] = object
    end
    return mapped
end

local function BuildSessionTarget(session, objects)
    local target = {}
    local provider = session.provider
    local function AddObjectRoot(objectID)
        local rootID = objectID
        if provider.contract == "presentation-transaction" then
            rootID = provider.RootOf(objectID)
            if type(rootID) ~= "string" or rootID == "" then
                error("RootOf() must return a non-empty string for " .. provider.id .. ":" .. objectID, 3)
            end
            local root = objects[rootID]
            if not root or not root.supported then return end
        else
            local object = objects[objectID]
            if not object or not object.supported then return end
        end
        target[rootID] = true
    end
    if session.focusID then
        AddObjectRoot(session.focusID)
    end
    for objectID in pairs(session.manualSelection) do
        AddObjectRoot(objectID)
    end
    -- A panel-only root is still an active presentation transaction root: its
    -- runtime visual must remain suppressed while its settings-page Surface is
    -- visible.  It is deliberately added after focus/manual selection, so a
    -- page can temporarily take ownership without rewriting the user's World
    -- Edit selection state.
    for rootID in pairs(session.panelOnlyRoots or {}) do
        local root = objects[rootID]
        if root and root.supported then target[rootID] = true end
    end
    return target
end


-- presentation-transaction is a one-way edit transaction.  Core owns every
-- temporary frame; Project is pure data, and Runtime only receives the final
-- suppression set after Core has finished rendering.  Runtime never calls back.
--
-- A provider may opt into the same renderer world transaction used by ordinary
-- editable modules.  It must declare renderer callbacks plus a per-root
-- selector below.  Core creates
-- and owns the host, selection overlay, root drag and teardown; the provider
-- only paints its collection/renderer into that host and returns declarative
-- world bounds.  This is deliberately an alternative to StandardPreview, not
-- a fallback layered on top of it.
local function HasPresentationWorldRenderer(provider)
    return type(provider.RenderWorld) == "function"
        and type(provider.ReleaseWorld) == "function"
        and type(provider.GetWorldBounds) == "function"
end

-- Renderer capability belongs to the provider, but renderer ownership belongs
-- to an individual project root.  A mixed provider can therefore move one
-- root to its collection renderer without accidentally changing the existing
-- StandardPreview semantics of every other root.
local function SelectsPresentationWorldRenderer(provider, rootID, project)
    if not HasPresentationWorldRenderer(provider) then return false end
    local selected = provider.UsesWorldRenderer(rootID, project)
    if type(selected) ~= "boolean" then
        error("UsesWorldRenderer() must return boolean for " .. provider.id .. ":" .. rootID, 3)
    end
    return selected
end

local function EnsurePresentationRoot()
    if state.presentationRoot then return state.presentationRoot end
    local root = CreateFrame("Frame", "EXWIND_EDIT_PRESENTATION", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("FULLSCREEN_DIALOG")
    root:SetFrameLevel(1)
    root:EnableMouse(false)
    root:Show()
    state.presentationRoot = root
    return root
end

local function ApplyPresentationPlacement(host, placement)
    placement = placement or {}
    local point = placement.point or "CENTER"
    local relativePoint = placement.relativePoint or point
    local x, y = tonumber(placement.x) or 0, tonumber(placement.y) or 0
    local width, height = tonumber(placement.width) or 1, tonumber(placement.height) or 1
    if width <= 0 or height <= 0 then error("Project().placement width/height must be positive", 3) end
    host:ClearAllPoints()
    host:SetSize(width, height)
    host:SetPoint(point, UIParent, relativePoint, x, y)
end

-- 事务实体也是唯一编辑模式的世界对象，不能因为它们没有注册进
-- state.modules 就漏掉覆盖层。标题来自同一次 Catalog 快照的根对象名称；
-- 视觉仍完全交由唯一 VisualLayers API 绘制。
local function GetPresentationWorldBounds(session, rootID, entity)
    if not entity or not entity.host then return nil end
    if entity.rendererActive then
        local bounds = session.provider.GetWorldBounds(rootID, entity.renderer)
        if type(bounds) ~= "table" then
            error("presentation renderer GetWorldBounds() must return a table for " .. session.provider.id .. ":" .. rootID, 3)
        end
        local width, height = tonumber(bounds.width), tonumber(bounds.height)
        if not width or not height or width <= 0 or height <= 0 then
            error("presentation renderer GetWorldBounds() must return positive width/height for " .. session.provider.id .. ":" .. rootID, 3)
        end
        return {
            width = width,
            height = height,
            anchorOffsetX = tonumber(bounds.anchorOffsetX) or 0,
            anchorOffsetY = tonumber(bounds.anchorOffsetY) or 0,
        }
    end
    local union
    for _, preview in ipairs(entity.previews or {}) do
        local bounds = preview:GetWorldBounds()
        -- Layer hosts share the root's center, but bounds are in layer units.
        local scale = entity.previewScales and entity.previewScales[preview] or 1
        local left = (bounds.anchorOffsetX - bounds.width * 0.5) * scale
        local right = (bounds.anchorOffsetX + bounds.width * 0.5) * scale
        local bottom = (bounds.anchorOffsetY - bounds.height * 0.5) * scale
        local top = (bounds.anchorOffsetY + bounds.height * 0.5) * scale
        union = union or { left = left, right = right, bottom = bottom, top = top }
        if union then
            union.left = math.min(union.left, left)
            union.right = math.max(union.right, right)
            union.bottom = math.min(union.bottom, bottom)
            union.top = math.max(union.top, top)
        end
    end
    if union then
        return {
            width = math.max(1, union.right - union.left),
            height = math.max(1, union.top - union.bottom),
            anchorOffsetX = (union.left + union.right) * 0.5,
            anchorOffsetY = (union.bottom + union.top) * 0.5,
        }
    end
    return nil
end

local function SetPresentationOverlay(session, rootID, entity, shown)
    if not entity or not entity.host then return end
    -- [WEB-REQ 08/11] 画面直编的 profile（quietRoot）不画整块填充/边框，也没有光环名称标签：
    -- 常显轮廓、悬停、选中、群组外框都由元素级视觉（SelectionRoot 里的输入层）承担，宿主上不建覆盖层。
    if GetProfile(session.provider).quietRoot == true then return end
    local object = session.objectMap and session.objectMap[rootID]
    local title = object and object.name or session.provider.name
    local worldBounds = GetPresentationWorldBounds(session, rootID, entity)
    entity.overlayApplied = true
    EXUI:SetEditModeVisualLayerShown(
        entity.host,
        shown == true,
        GetProfile(session.provider),
        title,
        GetTitleSize(session.provider),
        worldBounds
    )
end

-- =========================================================
-- 画面直编（EXAura 编辑画面）
-- [WEB-REQ 08/09/10/11/12/13/36/61] 无虚线（群组外框除外，见 35）；悬停高亮 + 实线选中框；
--   四角方块 + 四边隐形拉伸带（边上显示箭头）+ 框下“宽 × 高”；命中优先级 文字 > 子元素 > 主体。
-- [WEB-REQ 25/33/46/47] 拖动子元素完全跟随鼠标；锚点提示 / 对齐线由 Provider 的 PreviewWorldElement 返回，Core 只负责画。
-- [WEB-REQ 35/59/69] Provider 的 ListWorldOverlays 声明群组外框/格子/手柄，Core 画并转发拖动。
-- [WEB-REQ 60] 资料夹：SetEditSessionWorldOutlines 给每个成员各自描边，拖任一描边成员 = 整体移动。
-- Core 仍是唯一拥有命中、选中框、拖动与销毁的一方；Provider 只汇报几何并在 Commit 里落盘。
-- =========================================================
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Materials\\ExwindTools\\PlayerPosition\\Circle.png"
local ARROW_LEFT_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\Unified\\arrow-left.tga"
local ARROW_RIGHT_TEXTURE = "Interface\\AddOns\\ExwindCore\\Textures\\Icons\\Unified\\arrow-right.tga"
local CIRCLE_COORD = 15 / 64
local CIRCLE_COORD_MAX = 49 / 64

local function WorldTheme(session)
    local theme = GetProfile(session.provider).world
    if type(theme) ~= "table" then
        error("presentation world input requires a profile.world theme for " .. session.provider.id, 3)
    end
    return theme
end

local function NewTexture(parent)
    local texture = EXUI:CreateVisualTexture(parent, _G.EXBORDERFRAME)
    texture:SetTexture(WHITE_TEXTURE)
    return texture
end

local function PaintTexture(texture, color, alpha)
    texture:SetVertexColor(color.r, color.g, color.b, alpha or color.a or 1)
end

-- 四条实线边：锚在 frame 自己的四边上，frame 改尺寸后无需重排。
local function CreateBorder(frame, thickness)
    local border = { parts = {} }
    local top, bottom, left, right = NewTexture(frame), NewTexture(frame), NewTexture(frame), NewTexture(frame)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT"); top:SetPoint("TOPRIGHT", frame, "TOPRIGHT"); top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT"); bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT"); left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT"); left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT"); right:SetWidth(thickness)
    border.parts = { top, bottom, left, right }
    return border
end

local function PaintBorder(border, color)
    for _, part in ipairs(border.parts) do PaintTexture(part, color) end
end

local function SetBorderShown(border, shown)
    for _, part in ipairs(border.parts) do part:SetShown(shown) end
end

-- [WEB-REQ 35] 动态群组的虚线外框。虚线只在群组外框使用，随尺寸变化重排。
local DASH_LENGTH, DASH_GAP, DASH_THICKNESS = 6, 4, 1.5
local function CreateDashed(frame)
    return { frame = frame, parts = {}, width = nil, height = nil, color = nil }
end

local function LayoutDashed(dashed, width, height, color)
    if dashed.width == width and dashed.height == height and dashed.color == color then return end
    dashed.width, dashed.height, dashed.color = width, height, color
    local count = 0
    local function Put(x, y, w, h)
        count = count + 1
        local part = dashed.parts[count]
        if not part then
            part = NewTexture(dashed.frame)
            dashed.parts[count] = part
        end
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", dashed.frame, "TOPLEFT", x, -y)
        part:SetSize(w, h)
        PaintTexture(part, color)
        part:Show()
    end
    local function Run(length, horizontal, fixed)
        local at = 0
        while at < length do
            local size = math.min(DASH_LENGTH, length - at)
            if horizontal then Put(at, fixed, size, DASH_THICKNESS) else Put(fixed, at, DASH_THICKNESS, size) end
            at = at + DASH_LENGTH + DASH_GAP
        end
    end
    Run(width, true, 0)
    Run(width, true, height - DASH_THICKNESS)
    Run(height, false, 0)
    Run(height, false, width - DASH_THICKNESS)
    for index = count + 1, #dashed.parts do dashed.parts[index]:Hide() end
end

local function SetDashedShown(dashed, shown)
    if not shown then
        for _, part in ipairs(dashed.parts) do part:Hide() end
        dashed.width = nil
    end
end

-- 标签（“宽 × 高”、群组名、格子大小、锚点名）：底色 + 文字，字体走 EXDB:ApplyFont。
local function CreateChip(parent, clickable)
    local chip = CreateFrame(clickable and "Button" or "Frame", nil, parent)
    chip:EnableMouse(clickable == true)
    chip.background = NewTexture(chip)
    chip.background:SetAllPoints(chip)
    chip.label = EXUI:CreateVisualFontString(chip, _G.EXFONTFRAME, "GameFontNormalSmall")
    chip.label:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chip.label:SetJustifyH("CENTER")
    chip.label:SetWordWrap(false)
    return chip
end

local function SetChip(chip, text, background, foreground, size)
    local fontDB = _G.EXDB
    if not fontDB or type(fontDB.ApplyFont) ~= "function" then
        error("edit mode world label font service is unavailable", 2)
    end
    size = size or 11
    -- 拖动时标签每帧更新：字体只在样式变化时重设，文字只在内容变化时重设。
    local key = size .. ":" .. foreground.r .. ":" .. foreground.g .. ":" .. foreground.b .. ":" .. (foreground.a or 1)
    if chip.styleKey ~= key then
        fontDB:ApplyFont(chip.label, { font = "默认", size = size, outline = "NONE",
            r = foreground.r, g = foreground.g, b = foreground.b, a = foreground.a or 1 })
        chip.styleKey, chip.textValue = key, nil
    end
    if chip.textValue ~= text then
        chip.label:SetText(text)
        chip.textValue = text
        chip:SetSize(chip.label:GetStringWidth() + 12, size + 7)
    end
    PaintTexture(chip.background, background)
end

-- [WEB-REQ 61] 拉伸带悬停时，鼠标旁出现上下 / 左右箭头；拖动期间保持显示。
local function EnsureCursorHint()
    if state.cursorHint then return state.cursorHint end
    local hint = CreateFrame("Frame", nil, UIParent)
    hint:SetFrameStrata("TOOLTIP")
    hint:SetFrameLevel(2000)
    hint:EnableMouse(false)
    hint:SetSize(40, 40)
    hint.arrows = {}
    for _, spec in ipairs({
        { texture = ARROW_LEFT_TEXTURE, dark = true }, { texture = ARROW_RIGHT_TEXTURE, dark = true },
        { texture = ARROW_LEFT_TEXTURE }, { texture = ARROW_RIGHT_TEXTURE },
    }) do
        local arrow = hint:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(spec.texture)
        arrow:SetSize(16, 16)
        if spec.dark then arrow:SetVertexColor(0, 0, 0, 0.85) else arrow:SetVertexColor(1, 1, 1, 1) end
        hint.arrows[#hint.arrows + 1] = { texture = arrow, dark = spec.dark == true, right = spec.texture == ARROW_RIGHT_TEXTURE }
    end
    hint:Hide()
    state.cursorHint = hint
    return hint
end

local function HideCursorHint()
    local hint = state.cursorHint
    if not hint then return end
    hint:SetScript("OnUpdate", nil)
    hint:Hide()
end

local function ShowCursorHint(direction)
    if direction ~= "N" and direction ~= "S" and direction ~= "E" and direction ~= "W" then return end
    local hint = EnsureCursorHint()
    local vertical = direction == "N" or direction == "S"
    for _, arrow in ipairs(hint.arrows) do
        local texture = arrow.texture
        texture:ClearAllPoints()
        texture:SetRotation(vertical and -math.pi / 2 or 0)
        local shift = arrow.dark and 1 or 0
        if vertical then
            texture:SetPoint("CENTER", hint, "CENTER", shift, (arrow.right and -9 or 9) - shift)
        else
            texture:SetPoint("CENTER", hint, "CENTER", (arrow.right and 9 or -9) + shift, -shift)
        end
    end
    hint:SetScript("OnUpdate", function(frame)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 20, y / scale - 20)
    end)
    hint:Show()
end

local function SessionInputAllowed(session)
    return not (_G.InCombatLockdown and _G.InCombatLockdown())
        and not (session and session.clock and session.clock.state == "playing")
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- 选中只受战斗限制：播放中也能选中；拖动 / 缩放 / 提交另外要求会话时钟已停（SessionInputAllowed）。
local function SelectionAllowed()
    return not (_G.InCombatLockdown and _G.InCombatLockdown())
end

-- 世界输入层的辅助函数集中放在这张表里：顶层 local 数量已接近 Lua 上限，
-- 同时避免相互引用的前向声明（表字段在调用时才解析）。
local WorldInput = {}

-- 层级常量：所有编辑视觉与命中框都在 Core 自有的 SelectionRoot（挂 UIParent，不挂宿主）内，层级由 Core 统一分配。
-- 命中框按“文字 > 子元素 > 本体”分三个带，同带内按实体创建顺序错开；选中元素的命中框提升到所在带的顶部，
-- 选框、手柄与徽标整体提升到 6000 以上（暴雪选框 EditModeSystemSelectionBaseTemplate 是
-- frameLevel 1000 + toplevel：选中的系统总在最上）。
WorldInput.LEVEL = {
    rootBase = 1000, max = 9990,
    band = { body = 2000, child = 3000, text = 4000 }, selectedHit = 999,
    faint = 1300, hover = 5000, nameChip = 5010, outline = 5100,
    selection = 6000, edge = 6010, corner = 6020, badge = 6030,
    overlayCell = 1100, overlayFrame = 1110, overlayStrip = 5200, overlayChip = 5210,
    overlayHandle = 7000, overlayLabel = 7100, decor = 7200,
}
-- 太小的元素把命中面外扩到至少这么大（屏幕固定单位），保证点得到。
WorldInput.MIN_HIT_SIZE = 12

-- 先解除固定再设置、最后重新固定：层级既不被父级的层级变化带走，也不被点击自动 Raise 改写
-- （暴雪天赋树 SetElementFrameLevel 用同一手法）。
function WorldInput.SetLevel(frame, level)
    frame:SetFixedFrameLevel(false)
    frame:SetFrameLevel(math.min(level, WorldInput.LEVEL.max))
    frame:SetFixedFrameLevel(true)
end

-- 矩形契约：{ x, y, width, height } 全部是有限数字，width/height 为正；x/y 是矩形中心，原点是
-- entity.host 的中心，y 向上，单位是 entity.host 的局部单位（host 有效缩放下的单位）。
-- 返回规范化矩形，或 nil + 原因；调用方决定抛错还是丢弃。不做静默纠正。
local function ReadWorldRect(rect)
    if type(rect) ~= "table" or not IsFiniteNumber(rect.x) or not IsFiniteNumber(rect.y)
        or not IsFiniteNumber(rect.width) or not IsFiniteNumber(rect.height)
        or rect.width <= 0 or rect.height <= 0 then
        return nil, "must be { x, y, width, height } finite numbers with positive width/height,"
            .. " centered on entity.host and measured in host-local units"
    end
    return { x = rect.x, y = rect.y, width = rect.width, height = rect.height }
end

function WorldInput.IsFrame(frame)
    return type(frame) == "table" and frame.GetCenter ~= nil and frame.GetWidth ~= nil
        and frame.GetHeight ~= nil and frame.GetEffectiveScale ~= nil
end

-- 真实 frame 在宿主局部单位下的矩形：x = frameCenterX * ratio - hostCenterX，width 乘 ratio，
-- ratio = frame 有效缩放 / host 有效缩放。位置未解析或尺寸非正返回 nil + 原因。
function WorldInput.FrameLocalRect(host, frame)
    local x, y = frame:GetCenter()
    if not (x and y) then return nil, "frame has no resolved position" end
    local hostX, hostY = host:GetCenter()
    if not (hostX and hostY) then return nil, "host has no resolved position" end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not IsFiniteNumber(width) or not IsFiniteNumber(height) or width <= 0 or height <= 0 then
        return nil, "frame has no positive size"
    end
    local ratio = (frame:GetEffectiveScale() or 1) / (host:GetEffectiveScale() or 1)
    return { x = x * ratio - hostX, y = y * ratio - hostY, width = width * ratio, height = height * ratio }
end

-- 宿主局部单位 → 目标 frame 单位的换算比例（宿主有效缩放 / frame 有效缩放）。
function WorldInput.ScaleRatio(host, frame)
    local frameScale = frame:GetEffectiveScale() or 1
    if frameScale <= 0 then frameScale = 1 end
    return (host:GetEffectiveScale() or 1) / frameScale
end

-- 把 frame 摆到虚拟 rect（宿主局部单位）上：偏移与尺寸按宿主缩放换算；pad 是屏幕固定单位；
-- fixedSize = true 时尺寸按屏幕固定单位（圆点手柄），只有位置随宿主缩放。
function WorldInput.PlaceVirtual(frame, host, rect, pad, fixedSize)
    pad = pad or 0
    local ratio = WorldInput.ScaleRatio(host, frame)
    local sizeRatio = fixedSize and 1 or ratio
    frame:ClearAllPoints()
    frame:SetSize(rect.width * sizeRatio + pad * 2, rect.height * sizeRatio + pad * 2)
    frame:SetPoint("CENTER", host, "CENTER", rect.x * ratio, rect.y * ratio)
end

-- 拖动期间真实 frame 跟着手势：快照 / 还原 / 预览。预览用的真实 frame 是 entry.previewFrame
-- （frame 型就是 frame 自己；虚拟 rect 型由 provider 声明）。
local function CaptureWorldElementFrame(entry)
    local frame = entry.previewFrame
    if not frame or not frame.GetNumPoints or not frame.GetPoint or not frame.SetPoint
        or not frame.ClearAllPoints or not frame.SetSize or not frame.GetEffectiveScale then return nil end
    local snapshot = { frame = frame, width = frame:GetWidth(), height = frame:GetHeight(), points = {} }
    for index = 1, frame:GetNumPoints() do
        snapshot.points[index] = { frame:GetPoint(index) }
    end
    return snapshot
end

local function RestoreWorldElementFrame(snapshot)
    if not snapshot then return end
    local frame = snapshot.frame
    frame:ClearAllPoints()
    frame:SetSize(snapshot.width, snapshot.height)
    for _, point in ipairs(snapshot.points) do
        frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
    end
end

-- 拖动期间让真实 frame 跟着命中矩形：frame 自己的矩形（active.frameStartRect）
-- 按“起始命中矩形 → 当前命中矩形”的同一缩放 + 平移变换。文字（spec.scaleFont）只平移不缩放。
-- 命中矩形与 frame 单位的缩放不同（群组成员宿主、带自身 scale 的 frame）时按比例换算后再摆放。
local function PreviewWorldElementFrame(active, rect)
    local snapshot = active.frameSnapshot
    if not snapshot then return end
    local start, frameStart = active.startRect, active.frameStartRect
    local scaleX = start.width > 0 and rect.width / start.width or 1
    local scaleY = start.height > 0 and rect.height / start.height or 1
    local centerX = rect.x + (frameStart.x - start.x) * scaleX
    local centerY = rect.y + (frameStart.y - start.y) * scaleY
    local frame, host = snapshot.frame, active.host
    local frameScale = frame:GetEffectiveScale() or 1
    if frameScale <= 0 then frameScale = 1 end
    local toFrame = (host:GetEffectiveScale() or 1) / frameScale
    frame:ClearAllPoints()
    if active.entry.spec.scaleFont == true then
        frame:SetSize(frameStart.width * toFrame, frameStart.height * toFrame)
    else
        frame:SetSize(math.max(1, frameStart.width * scaleX * toFrame), math.max(1, frameStart.height * scaleY * toFrame))
    end
    frame:SetPoint("CENTER", host, "CENTER", centerX * toFrame, centerY * toFrame)
end

-- 元素过滤谓词：返回 boolean。谓词抛错直接传出（调用方在改任何状态之前先评估）。
local function EvaluateWorldElementFilter(filter, rootID, elementID)
    if not filter then return true end
    local visible = filter(rootID, elementID)
    if type(visible) ~= "boolean" then
        error("world element filter must return boolean for " .. rootID .. ":" .. elementID, 2)
    end
    return visible
end

local function WorldModifiers()
    return {
        shift = _G.IsShiftKeyDown and _G.IsShiftKeyDown() or false,
        ctrl = _G.IsControlKeyDown and _G.IsControlKeyDown() or false,
        alt = _G.IsAltKeyDown and _G.IsAltKeyDown() or false,
    }
end

-- ---------- 装饰层（对齐线、锚点提示点、格子高亮） ----------
-- 装饰层挂在 SelectionRoot 上；provider 声明的坐标是宿主局部单位，按宿主缩放换算成屏幕单位，
-- 线宽、点大小、提示文字偏移是屏幕固定尺寸，不随宿主缩放。
local function CreateDecor(root, theme)
    local decor = { frame = CreateFrame("Frame", nil, root), lines = {}, dots = {}, rects = {} }
    decor.frame:EnableMouse(false)
    decor.frame:SetAllPoints(root)
    WorldInput.SetLevel(decor.frame, WorldInput.LEVEL.decor)
    decor.tip = CreateChip(decor.frame, false)
    decor.tip:Hide()
    decor.theme = theme
    return decor
end

local function HideDecor(decor)
    if not decor then return end
    for _, line in ipairs(decor.lines) do line:Hide() end
    for _, dot in ipairs(decor.dots) do dot.outer:Hide(); dot.inner:Hide(); dot.core:Hide() end
    for _, rect in ipairs(decor.rects) do rect.frame:Hide() end
    decor.tip:Hide()
end

local function ApplyDecor(entity, declared)
    local decor = entity.worldDecor
    if not decor then return end
    HideDecor(decor)
    if type(declared) ~= "table" then return end
    local host, theme = entity.host, decor.theme
    local ratio = WorldInput.ScaleRatio(host, decor.frame)
    for index, spec in ipairs(declared.lines or {}) do
        local line = decor.lines[index]
        if not line then line = NewTexture(decor.frame); decor.lines[index] = line end
        line:ClearAllPoints()
        PaintTexture(line, theme.accent)
        if spec.y1 == spec.y2 then
            line:SetPoint("CENTER", host, "CENTER", (spec.x1 + spec.x2) / 2 * ratio, spec.y1 * ratio)
            line:SetSize(math.abs(spec.x2 - spec.x1) * ratio, 1.5)
        else
            line:SetPoint("CENTER", host, "CENTER", spec.x1 * ratio, (spec.y1 + spec.y2) / 2 * ratio)
            line:SetSize(1.5, math.abs(spec.y2 - spec.y1) * ratio)
        end
        line:Show()
    end
    for index, spec in ipairs(declared.dots or {}) do
        local dot = decor.dots[index]
        if not dot then
            dot = { outer = decor.frame:CreateTexture(nil, "OVERLAY", nil, 1),
                inner = decor.frame:CreateTexture(nil, "OVERLAY", nil, 2),
                core = decor.frame:CreateTexture(nil, "OVERLAY", nil, 3) }
            for _, texture in pairs(dot) do
                texture:SetTexture(CIRCLE_TEXTURE)
                texture:SetTexCoord(CIRCLE_COORD, CIRCLE_COORD_MAX, CIRCLE_COORD, CIRCLE_COORD_MAX)
            end
            decor.dots[index] = dot
        end
        for _, texture in pairs(dot) do
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", host, "CENTER", spec.x * ratio, spec.y * ratio)
        end
        if spec.state == "in" then
            dot.outer:SetSize(18, 18); PaintTexture(dot.outer, theme.chipText)
            dot.inner:SetSize(14, 14); PaintTexture(dot.inner, theme.accent)
            dot.outer:Show(); dot.inner:Show(); dot.core:Hide()
        elseif spec.state == "out" then
            dot.outer:SetSize(18, 18); PaintTexture(dot.outer, theme.accent)
            dot.inner:SetSize(11, 11); PaintTexture(dot.inner, theme.ringHole)
            dot.outer:Show(); dot.inner:Show(); dot.core:Hide()
        else
            dot.core:SetSize(8, 8); PaintTexture(dot.core, theme.accent, 0.35)
            dot.core:Show(); dot.outer:Hide(); dot.inner:Hide()
        end
    end
    for index, spec in ipairs(declared.rects or {}) do
        local rect = decor.rects[index]
        if not rect then
            local frame = CreateFrame("Frame", nil, decor.frame)
            frame:EnableMouse(false)
            rect = { frame = frame, fill = NewTexture(frame), border = CreateBorder(frame, 3) }
            rect.fill:SetAllPoints(frame)
            decor.rects[index] = rect
        end
        local color = spec.color == "green" and theme.green or theme.faintAccent
        PaintTexture(rect.fill, color, spec.color == "green" and 0.22 or 0.08)
        PaintBorder(rect.border, color)
        WorldInput.PlaceVirtual(rect.frame, host, spec, 0)
        rect.frame:Show()
    end
    if type(declared.tip) == "table" then
        local tip = decor.tip
        SetChip(tip, declared.tip.text, theme.accent, theme.chipText, theme.badgeSize)
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOM", host, "CENTER", declared.tip.x * ratio, declared.tip.y * ratio + 8)
        tip:Show()
    end
end

-- ---------- 单一指针会话（元素移动 / 缩放、整根移动、容器移动、格子拖放、手柄拖动共用） ----------
-- 会话只存在于鼠标按下期间：OnUpdate 只在会话期间挂在一个专用 frame 上，鼠标松开或 Esc 即卸下。
local POINTER_THRESHOLD = 2

local function EnsurePointerDriver()
    if state.pointerDriver then return state.pointerDriver end
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:EnableMouse(false)
    driver:SetFrameStrata("TOOLTIP")
    state.pointerDriver = driver
    return driver
end

local function StopPointerDriver()
    local driver = state.pointerDriver
    if not driver then return end
    driver:SetScript("OnUpdate", nil)
    driver:SetScript("OnKeyDown", nil)
    driver:EnableKeyboard(false)
    driver:Hide()
end

local function CancelPointer()
    local pointer = state.pointer
    if not pointer then return end
    state.pointer = nil
    StopPointerDriver()
    HideCursorHint()
    if pointer.cfg.onCancel then pointer.cfg.onCancel() end
end

local function PointerDelta(pointer)
    local x, y = GetCursorPosition()
    return x / pointer.scale - pointer.startX, y / pointer.scale - pointer.startY
end

local function FinishPointer()
    local pointer = state.pointer
    if not pointer then return end
    local dx, dy = PointerDelta(pointer)
    local moved = pointer.moved or math.abs(dx * pointer.scale) >= POINTER_THRESHOLD
        or math.abs(dy * pointer.scale) >= POINTER_THRESHOLD
    state.pointer = nil
    StopPointerDriver()
    HideCursorHint()
    pointer.cfg.onFinish(moved, dx, dy)
end

-- 上一次 Commit 抛错时没来得及还原的手势视觉（见 CommitWorldIntent）：在下一次可以安全还原的时机补做。
-- Commit 仍在进行（同一帧内）时不动，免得把还没落定的预览还原掉。
local function RunCommitResidue()
    local residue = state.commitResidue
    if not residue or state.commitStamp == _G.GetTime() then return end
    state.commitResidue, state.commitStamp = nil, nil
    residue()
end

-- 鼠标按下那一刻的光标（屏幕像素）：OnDragStart 触发时光标已经走过拖动阈值，
-- 手势的起点必须取按下时刻，否则起步会跳。
function WorldInput.CursorOrigin()
    local x, y = GetCursorPosition()
    return { x = x, y = y }
end

-- 指针手势在鼠标按下期间的持续条件：战斗中一律取消；默认还要求会话时钟已停，
-- 框选（cfg.allowPlaying）允许在播放中开始，拖过阈值才由 BeforeWorldInput 停播。
local function PointerAllowed(pointer)
    if pointer.cfg.allowPlaying then return SelectionAllowed() end
    return SessionInputAllowed(pointer.session)
end

-- entity 为 nil 表示不属于任何根的屏幕级手势（框选），坐标按 UIParent 的有效缩放换算；
-- cfg.canContinue 可选：返回 false 时手势在下一帧完整取消；
-- cfg.origin 可选：手势起点（鼠标按下时刻的屏幕光标，见 CursorOrigin），缺省取当前光标。
local function BeginPointer(session, entity, cfg)
    RunCommitResidue()
    if state.pointer then CancelPointer() end
    local scale = (entity and entity.host or UIParent):GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    local x, y = GetCursorPosition()
    if cfg.origin then x, y = cfg.origin.x, cfg.origin.y end
    state.pointer = { session = session, entity = entity, cfg = cfg, scale = scale,
        startX = x / scale, startY = y / scale, moved = false, entry = cfg.entry }
    local driver = EnsurePointerDriver()
    driver:Show()
    driver:EnableKeyboard(true)
    driver:SetScript("OnKeyDown", function(frame, key)
        if key == "ESCAPE" then
            frame:SetPropagateKeyboardInput(false)
            CancelPointer()
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)
    driver:SetScript("OnUpdate", function()
        local pointer = state.pointer
        if not pointer then return end
        if not PointerAllowed(pointer) then CancelPointer(); return end
        if pointer.cfg.canContinue and not pointer.cfg.canContinue() then CancelPointer(); return end
        if not _G.IsMouseButtonDown("LeftButton") then FinishPointer(); return end
        local dx, dy = PointerDelta(pointer)
        if not pointer.moved and math.abs(dx * pointer.scale) < POINTER_THRESHOLD
            and math.abs(dy * pointer.scale) < POINTER_THRESHOLD then return end
        pointer.moved = true
        if pointer.cfg.onMove then pointer.cfg.onMove(dx, dy) end
    end)
end

local function ReportPresentationCommitFailure(session, rootID, intent, reason)
    if type(session.provider.OnCommitFailed) == "function" then
        session.provider.OnCommitFailed(rootID, intent, reason)
        return
    end
    local detail = "edit session Commit failed: " .. session.provider.id .. ":" .. rootID
        .. " (" .. intent.type .. "): " .. tostring(reason)
    if type(ExwindTools.LogError) == "function" then
        ExwindTools:LogError("EditMode[" .. session.provider.id .. "]", detail)
    end
    print(detail)
end

local function ReportInputPreparationFailure(session, rootID, elementID, reason)
    local detail = "edit session world input preparation failed: "
        .. session.provider.id .. ":" .. tostring(rootID) .. ":" .. tostring(elementID)
        .. ": " .. tostring(reason)
    if type(ExwindTools.LogError) == "function" then
        ExwindTools:LogError("EditModeInput[" .. session.provider.id .. "]", detail)
    end
    print(detail)
end

-- A provider may exit its editor preview before Core consumes this same mouse
-- gesture. It must restore any provider-owned condition preview as well as
-- stop Core's clock; Core then checks that the clicked entity still exists.
-- 只在真正开始拖动 / 缩放 / 框选手势时调用（选中不调用）。provider 回调抛错直接传出，手势不会开始。
-- 框选在空白处开始时没有根和元素：rootID、elementID 均为 nil。
local function RunWorldInputPreparation(session, rootID, elementID, button)
    -- 暂停定位（SeekEditSessionClock）显示的是某一时刻的样本：编辑前先还原静态样本。
    local restored, restoreReason = WorldInput.ClearSeekedSample(session)
    if not restored then
        ReportInputPreparationFailure(session, rootID, elementID, restoreReason)
        return false
    end
    local before = session.provider.BeforeWorldInput
    if type(before) == "function" then
        local accepted, reason = before(rootID, elementID, button)
        if accepted ~= true then
            ReportInputPreparationFailure(session, rootID, elementID, reason or accepted)
            return false
        end
    elseif session.clock and session.clock.state == "playing" then
        return false
    end
    return true
end

local function PrepareWorldInput(session, rootID, entity, elementID, button)
    if not session or session.entities[rootID] ~= entity
        or (_G.InCombatLockdown and _G.InCombatLockdown()) then return false end
    if not RunWorldInputPreparation(session, rootID, elementID, button) then return false end
    return session.entities[rootID] == entity and SessionInputAllowed(session)
end

-- 会话的画面直编视觉是否启用：Core “显示覆盖层”面板开关，或 profile 声明的会话常显。
local function SessionWorldVisualsEnabled(session)
    return state.overlayVisible or GetProfile(session.provider).sessionWorldAlwaysVisible == true
end

-- ---------- 命中项的视觉与几何 ----------
function WorldInput.HideHover(entry)
    entry.hover:Hide()
    if entry.nameChip then entry.nameChip:Hide() end
end

function WorldInput.HideVisuals(entry)
    entry.faint:Hide()
    WorldInput.HideHover(entry)
    if entry.outline then entry.outline:Hide() end
    if entry.selection then entry.selection:Hide() end
end

-- 把一个视觉 / 命中 frame 摆到元素的矩形上（外扩 pad，屏幕固定单位）：frame 型直接用 TOPLEFT / BOTTOMRIGHT
-- 双点锚在真实 frame 上；虚拟 rect 型（以及手势期间的 liveRect）按 host 局部 rect 摆放。
function WorldInput.AnchorBox(entry, frame, pad)
    local live = entry.liveRect
    if entry.anchorFrame and not live then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", entry.anchorFrame, "TOPLEFT", -pad, pad)
        frame:SetPoint("BOTTOMRIGHT", entry.anchorFrame, "BOTTOMRIGHT", pad, -pad)
    else
        WorldInput.PlaceVirtual(frame, entry.host, live or entry.rect, pad)
    end
end

-- 命中框按 文字 > 子元素 > 本体 分带，同带内按实体创建顺序错开；选中的元素提升到所在带的顶部，
-- 选框、手柄与徽标整体提升到更高的带。
function WorldInput.ApplyLevels(entity, entry)
    local LEVEL = WorldInput.LEVEL
    local band = LEVEL.band[entry.spec.priority] or LEVEL.band.body
    WorldInput.SetLevel(entry.hitbox, band + (entry.selected and LEVEL.selectedHit or (entity.order or 0)))
    WorldInput.SetLevel(entry.faint, LEVEL.faint)
    WorldInput.SetLevel(entry.hover, LEVEL.hover)
    if entry.nameChip then WorldInput.SetLevel(entry.nameChip, LEVEL.nameChip) end
    if entry.selection then
        WorldInput.SetLevel(entry.outline, LEVEL.outline)
        WorldInput.SetLevel(entry.selection, LEVEL.selection)
        WorldInput.SetLevel(entry.badge, LEVEL.badge)
    end
end

-- 重新摆放一个命中项的全部部件。命中面用 SetHitRectInsets 外扩：选中时外扩到选框的外环
-- （可见选框内部整体属于命中面，可缩放与否都一样），太小的元素外扩到至少 MIN_HIT_SIZE。
function WorldInput.Layout(entry)
    local theme = entry.theme
    local rect = entry.liveRect or entry.rect
    local ratio = WorldInput.ScaleRatio(entry.host, entry.hitbox)
    local widthPx, heightPx = rect.width * ratio, rect.height * ratio
    -- [WEB-REQ 13] 选框向外扩一圈，控制点落在扩出的框上；小元素扩得更多，避免盖住内容。
    local small = widthPx < theme.small or heightPx < theme.small
    entry.selectionPad = small and theme.padSmall or theme.pad
    WorldInput.AnchorBox(entry, entry.hitbox, 0)
    local selectedPad = entry.selected and entry.selectionPad or 0
    local growX = math.max(selectedPad, (WorldInput.MIN_HIT_SIZE - widthPx) / 2, 0)
    local growY = math.max(selectedPad, (WorldInput.MIN_HIT_SIZE - heightPx) / 2, 0)
    entry.hitbox:SetHitRectInsets(-growX, -growX, -growY, -growY)
    WorldInput.AnchorBox(entry, entry.faint, 0)
    WorldInput.AnchorBox(entry, entry.hover, 1)
    if entry.selection then
        WorldInput.AnchorBox(entry, entry.outline, 3)
        WorldInput.AnchorBox(entry, entry.selection, entry.selectionPad)
        SetChip(entry.badge, string.format("%d × %d", math.floor(rect.width + 0.5), math.floor(rect.height + 0.5)),
            theme.accent, theme.chipText, theme.badgeSize)
    end
end

-- 手势期间的临时矩形（host 局部单位）；nil 回到真实几何。
function WorldInput.SetLive(entry, rect)
    entry.liveRect = rect
    WorldInput.Layout(entry)
end

function WorldInput.SetSelected(entity, entry, selected)
    if entry.selected == selected then return end
    entry.selected = selected
    WorldInput.ApplyLevels(entity, entry)
    WorldInput.Layout(entry)
end

-- 把会话里“选中 / 描边 / 常显轮廓”的状态同步到每个命中项。
local function SetWorldElementSelection(session)
    local selected = session.worldSelection
    local outlined = session.worldOutlineSet
    local canBegin = SessionInputAllowed(session)
        or (session.clock and session.clock.state == "playing"
            and type(session.provider.BeforeWorldInput) == "function"
            and not (_G.InCombatLockdown and _G.InCombatLockdown()))
    local visible = SessionWorldVisualsEnabled(session) and canBegin or false
    session.worldVisible = visible
    local ownerID = selected and selected.ownerID
    for rootID, entity in pairs(session.entities) do
        for elementID, entry in pairs(entity.worldElements or {}) do
            local active = selected ~= nil and selected.rootID == rootID and selected.elementID == elementID
            local shown = entry.hitbox:IsShown()
            local isOutlined = outlined and outlined[rootID] and outlined[rootID][elementID] == true
            local showSelection = active and shown and visible
            local showOutline = isOutlined == true and not active and shown and visible
            if showSelection or showOutline then WorldInput.EnsureKit(session, rootID, entity, entry) end
            WorldInput.SetSelected(entity, entry, showSelection == true)
            if entry.selection then
                entry.selection:SetShown(showSelection)
                entry.outline:SetShown(showOutline)
            end
            -- 会话中所有可选元素常显淡色轮廓；选中 / 资料夹描边的元素由各自更醒目的框代替。
            entry.faint:SetShown(shown and visible and not showSelection and not showOutline)
            if showSelection then WorldInput.HideHover(entry) end
        end
        for _, widget in ipairs(entity.worldOverlays or {}) do
            widget.Apply(ownerID, visible)
        end
    end
end

-- 选中只受战斗限制（播放中也能选中），并通知 provider（OnSelect 只回报、不写数据）。
local function SelectWorldElement(session, rootID, elementID, button)
    if not SelectionAllowed() then return end
    local previous = session.worldSelection
    session.worldSelection = { rootID = rootID, elementID = elementID,
        ownerID = previous and previous.rootID == rootID and previous.ownerID or nil }
    SetWorldElementSelection(session)
    if type(session.provider.OnSelect) == "function" then
        session.provider.OnSelect(rootID, elementID, button, WorldModifiers())
    end
end

-- ---------- 框选（橡皮筋） ----------
-- 手势复用唯一指针会话（BeginPointer）：只在左键按住期间挂一个专用 OnUpdate，松手 / Esc / 进入战斗 /
-- 会话结束 / provider.IsWorldInputBlocked() 为 true 时整个卸下，不存在常驻轮询帧。
-- 起点只来自 WorldFrame 收到的左键按下：Core 的命中框、手柄与编辑器面板是鼠标启用的 frame，
-- 点在它们上面时 WorldFrame 收不到事件，所以框选只会从空白处开始。
local MARQUEE_THRESHOLD = 4

local function HideMarquee()
    if state.marqueeFrame then state.marqueeFrame:Hide() end
end

local function EnsureMarqueeFrame()
    if state.marqueeFrame then return state.marqueeFrame end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1900)
    frame:EnableMouse(false)
    frame.fill = NewTexture(frame)
    frame.fill:SetAllPoints(frame)
    frame.border = CreateBorder(frame, 1)
    frame:Hide()
    state.marqueeFrame = frame
    return frame
end

-- 命中元素 = 命中框的屏幕矩形与框选矩形相交（rect 为 UIParent 单位，开区间）。
-- 元素列表为空的“空根”没有命中面，不会出现在结果里。
local function CollectMarqueeHits(session, rect)
    local uiScale = UIParent:GetEffectiveScale() or 1
    local function Intersects(frame)
        if not frame or not frame:IsVisible() then return false end
        local left, bottom, width, height = frame:GetRect()
        if not left then return false end
        local ratio = (frame:GetEffectiveScale() or 1) / uiScale
        left, bottom, width, height = left * ratio, bottom * ratio, width * ratio, height * ratio
        return left < rect.right and left + width > rect.left
            and bottom < rect.top and bottom + height > rect.bottom
    end
    local elements, rootIDs, seenRoots = {}, {}, {}
    for rootID, entity in pairs(session.entities) do
        local hitRoot = false
        for elementID, entry in pairs(entity.worldElements or {}) do
            if Intersects(entry.hitbox) then
                elements[#elements + 1] = { rootID = rootID, elementID = elementID }
                hitRoot = true
            end
        end
        if hitRoot and not seenRoots[rootID] then
            seenRoots[rootID] = true
            rootIDs[#rootIDs + 1] = rootID
        end
    end
    table.sort(elements, function(a, b)
        if a.rootID ~= b.rootID then return a.rootID < b.rootID end
        return (a.elementID or "") < (b.elementID or "")
    end)
    table.sort(rootIDs)
    return elements, rootIDs
end

local function BeginMarquee(session)
    local provider = session.provider
    if session.phase ~= "ACTIVE" or not SelectionAllowed() then return end
    local function Blocked()
        return type(provider.IsWorldInputBlocked) == "function" and provider.IsWorldInputBlocked() == true
    end
    if Blocked() then return end
    -- 点击与拖动分离：按下时不过 BeforeWorldInput，空白处单击（不拖动）只回报 moved=false，播放中也能清除选择；
    -- 拖过阈值才和元素输入走同一条前置——provider 先停播并恢复静态预览，失败则不开始画矩形。

    local theme = WorldTheme(session)
    local modifiers = WorldModifiers()
    local uiScale = UIParent:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    local startX, startY = cursorX / uiScale, cursorY / uiScale
    local active = false
    local function CurrentRect(dx, dy)
        local x, y = startX + dx, startY + dy
        return { left = math.min(startX, x), right = math.max(startX, x),
            bottom = math.min(startY, y), top = math.max(startY, y) }
    end
    BeginPointer(session, nil, {
        allowPlaying = true,
        canContinue = function() return not Blocked() end,
        onMove = function(dx, dy)
            if not active then
                if math.abs(dx) + math.abs(dy) <= MARQUEE_THRESHOLD then return end
                if not RunWorldInputPreparation(session, nil, nil, "LeftButton") then CancelPointer(); return end
                if state.editSessions[provider.id] ~= session or session.phase ~= "ACTIVE"
                    or not SessionInputAllowed(session) then CancelPointer(); return end
                active = true
                local frame = EnsureMarqueeFrame()
                PaintTexture(frame.fill, theme.faintAccent, 0.14)
                PaintBorder(frame.border, theme.accent)
            end
            local rect = CurrentRect(dx, dy)
            local frame = state.marqueeFrame
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom)
            frame:SetSize(math.max(1, rect.right - rect.left), math.max(1, rect.top - rect.bottom))
            frame:Show()
        end,
        onCancel = HideMarquee,
        onFinish = function(_, dx, dy)
            HideMarquee()
            if state.editSessions[provider.id] ~= session or session.phase ~= "ACTIVE" then return end
            if not active and math.abs(dx) + math.abs(dy) > MARQUEE_THRESHOLD then
                -- OnUpdate 没来得及跑到阈值就松手了：这里补做拖动前置。
                if not RunWorldInputPreparation(session, nil, nil, "LeftButton") then return end
                if state.editSessions[provider.id] ~= session or session.phase ~= "ACTIVE"
                    or not SessionInputAllowed(session) then return end
                active = true
            end
            local result = { moved = active, modifiers = modifiers, elements = {}, rootIDs = {} }
            if active then
                result.rect = CurrentRect(dx, dy)
                result.elements, result.rootIDs = CollectMarqueeHits(session, result.rect)
            end
            provider.OnMarqueeSelect(result)
        end,
    })
end

local function OnWorldFrameMouseDown(_, button)
    if button ~= "LeftButton" then return end
    for _, session in pairs(state.editSessions) do
        if session.provider.contract == "presentation-transaction"
            and type(session.provider.OnMarqueeSelect) == "function" then
            BeginMarquee(session)
            return
        end
    end
end
_G.WorldFrame:HookScript("OnMouseDown", OnWorldFrameMouseDown)

-- ---------- 元素移动 / 缩放 ----------
local function CalculateWorldElementRect(active, dx, dy)
    local start = active.startRect
    if active.mode == "move" then
        return { x = start.x + dx, y = start.y + dy, width = start.width, height = start.height }
    end
    local direction = active.direction
    local spec = active.entry.spec
    local left, right = start.x - start.width / 2, start.x + start.width / 2
    local bottom, top = start.y - start.height / 2, start.y + start.height / 2
    if spec.uniform == true then
        -- [WEB-REQ 10] 文字缩放 = 改字号：宽高等比，对边 / 对角固定；边上拉伸用该方向的变化量决定比例。
        local vertical = direction:find("N", 1, true) or direction:find("S", 1, true)
        local factor
        if vertical then
            local height = start.height + (direction:find("N", 1, true) and dy or -dy)
            factor = height / start.height
        else
            local width = start.width + (direction:find("E", 1, true) and dx or -dx)
            factor = width / start.width
        end
        factor = math.max(0.1, math.min(10, factor))
        local width, height = start.width * factor, start.height * factor
        if direction:find("W", 1, true) then left = right - width
        elseif direction:find("E", 1, true) then right = left + width
        else left, right = start.x - width / 2, start.x + width / 2 end
        if direction:find("N", 1, true) then top = bottom + height
        elseif direction:find("S", 1, true) then bottom = top - height
        else bottom, top = start.y - height / 2, start.y + height / 2 end
        return { x = (left + right) / 2, y = (bottom + top) / 2, width = right - left, height = top - bottom }
    end
    local minimumWidth = tonumber(spec.minWidth) or 1
    local minimumHeight = tonumber(spec.minHeight) or 1
    local maximumWidth = tonumber(spec.maxWidth) or math.huge
    local maximumHeight = tonumber(spec.maxHeight) or math.huge
    if direction:find("W", 1, true) then left = math.max(right - maximumWidth, math.min(right - minimumWidth, left + dx)) end
    if direction:find("E", 1, true) then right = math.min(left + maximumWidth, math.max(left + minimumWidth, right + dx)) end
    if direction:find("S", 1, true) then bottom = math.max(top - maximumHeight, math.min(top - minimumHeight, bottom + dy)) end
    if direction:find("N", 1, true) then top = math.min(bottom + maximumHeight, math.max(bottom + minimumHeight, top + dy)) end
    return { x = (left + right) / 2, y = (bottom + top) / 2, width = right - left, height = top - bottom }
end

-- 向 provider 提交一次意图。Core 只在 Commit 返回 true 后接受新几何；返回 true / false。
-- Commit 抛错时没有机会还原手势视觉（不做错误拦截）：还原动作登记在 state.commitResidue，
-- 下一次手势 / 几何刷新 / 对账 / 会话结束时补做。Commit 进行中（同一帧内）的再入刷新不会触发它。
local function CommitWorldIntent(session, rootID, intent, onRejected)
    state.commitResidue = onRejected
    state.commitStamp = _G.GetTime()
    local accepted, reason = session.provider.Commit(rootID, intent)
    state.commitStamp = nil
    state.commitResidue = nil
    if accepted ~= true then
        if onRejected then onRejected() end
        ReportPresentationCommitFailure(session, rootID, intent, reason)
        return false
    end
    return true
end

-- [WEB-REQ 10/25/33/47/61] 元素移动 / 缩放：完全跟随鼠标；松手时一次性 Commit（元素矩形 + 提示层由 Provider 给出）。
-- 手势期间命中框 / 选框 / 悬停按 liveRect 摆放；真实 frame 由 Core 预览（frame 与宿主缩放不同时按比例换算），
-- provider 实现了 PreviewWorldElementLive 时由它让真实视觉（字号、图标 / 材质尺寸）实时变化。
-- 提交成功后真实 frame 与实时视觉保持松手时的状态，输入层原地对账（不重建整根）；
-- 失败或取消则全部还原到起点。
local function BeginElementPointer(session, rootID, entity, entry, mode, direction, origin)
    local spec = entry.spec
    local provider = session.provider
    local host = entity.host
    -- 起点以真实 frame 当前的几何为准，避免读到过期的枚举快照。
    if entry.anchorFrame then
        entry.rect = WorldInput.FrameLocalRect(host, entry.anchorFrame) or entry.rect
    end
    local frameStart = entry.frameRect or entry.rect
    if entry.previewFrame then
        frameStart = WorldInput.FrameLocalRect(host, entry.previewFrame) or frameStart
    end
    local function Copy(rect) return { x = rect.x, y = rect.y, width = rect.width, height = rect.height } end
    local active = { entry = entry, mode = mode, direction = direction, host = host,
        startRect = Copy(entry.rect), frameStartRect = Copy(frameStart),
        frameSnapshot = CaptureWorldElementFrame(entry) }
    local function PreviewLive(rect, phase)
        if type(provider.PreviewWorldElementLive) ~= "function" then return end
        local start = active.startRect
        provider.PreviewWorldElementLive(rootID, spec.elementID, rect, { phase = phase, mode = mode,
            direction = direction, startRect = start,
            scaleX = rect and rect.width / start.width or nil, scaleY = rect and rect.height / start.height or nil })
    end
    local function Restore()
        RestoreWorldElementFrame(active.frameSnapshot)
        if entry.spec == spec then WorldInput.SetLive(entry, nil) end
        ApplyDecor(entity, nil)
        PreviewLive(nil, "cancel")
    end
    if mode == "resize" then ShowCursorHint(direction:len() == 1 and direction or nil) end
    -- 同一个函数算移动中的矩形和松手时的矩形：Provider 可以在这里做对齐吸附、给出锚点提示。
    local function Resolve(dx, dy)
        local rect = CalculateWorldElementRect(active, dx, dy)
        local decor
        if type(provider.PreviewWorldElement) == "function" then
            local preview = provider.PreviewWorldElement(rootID, spec.elementID, rect, active.startRect,
                { mode = mode, direction = direction })
            if type(preview) == "table" then
                rect = preview.rect or rect
                decor = preview.decor
            end
        end
        return rect, decor
    end
    BeginPointer(session, entity, { entry = entry, origin = origin,
        onMove = function(dx, dy)
            local rect, decor = Resolve(dx, dy)
            WorldInput.SetLive(entry, rect)
            PreviewWorldElementFrame(active, rect)
            ApplyDecor(entity, decor)
            PreviewLive(rect, "move")
        end,
        onCancel = Restore,
        onFinish = function(moved, dx, dy)
            if not moved or not SessionInputAllowed(session) or session.entities[rootID] ~= entity then
                Restore()
                return
            end
            -- OnUpdate 可能没有跑到最后一次移动与松手之间：以松手点重新计算。
            local rect = Resolve(dx, dy)
            WorldInput.SetLive(entry, rect)
            PreviewWorldElementFrame(active, rect)
            ApplyDecor(entity, nil)
            PreviewLive(rect, "commit")
            local intent = { type = mode == "move" and "elementMoved" or "elementResized",
                elementID = spec.elementID, position = { x = rect.x, y = rect.y },
                rect = rect, width = rect.width, height = rect.height, direction = direction }
            if CommitWorldIntent(session, rootID, intent, Restore) then
                if entry.spec == spec then WorldInput.SetLive(entry, nil) end
                if session.entities[rootID] == entity then WorldInput.Reproject(session, rootID, entity) end
            end
        end })
end

-- ---------- 整根移动 / 容器整体移动 ----------
-- linkedSet = session.worldOutlineSet 里的其它根（资料夹成员）；它们的宿主按同一增量一起动（[WEB-REQ 60]）。
local function CollectLinkedEntities(session, rootID, entity, target)
    local hosts = { { rootID = rootID, entity = entity } }
    if target then
        for linkedRootID in pairs(session.worldOutlineSet or {}) do
            local linked = session.entities[linkedRootID]
            if linkedRootID ~= rootID and linked then hosts[#hosts + 1] = { rootID = linkedRootID, entity = linked } end
        end
    end
    return hosts
end

local function ApplyRootOffset(item, dx, dy)
    local placement = item.entity.placement or {}
    ApplyPresentationPlacement(item.entity.host, { point = placement.point, relativePoint = placement.relativePoint,
        width = placement.width, height = placement.height,
        x = (tonumber(placement.x) or 0) + dx, y = (tonumber(placement.y) or 0) + dy })
end

-- 整根（含资料夹成员）拖动：宿主跟着鼠标走，选框与命中框锚在真实 frame 上自然跟随；松手 Commit 一次，
-- 成功后各根重新取放置信息原地对账，失败 / 取消回到原位。
local function BeginRootPointer(session, rootID, entity, target, origin)
    local hosts = CollectLinkedEntities(session, rootID, entity, target)
    local function Restore()
        for _, item in ipairs(hosts) do
            if session.entities[item.rootID] == item.entity then ApplyRootOffset(item, 0, 0) end
        end
    end
    BeginPointer(session, entity, { origin = origin,
        onMove = function(dx, dy)
            for _, item in ipairs(hosts) do ApplyRootOffset(item, dx, dy) end
        end,
        onCancel = Restore,
        onFinish = function(moved, dx, dy)
            if not moved or not SessionInputAllowed(session) or session.entities[rootID] ~= entity then
                Restore()
                return
            end
            local placement = entity.placement or {}
            local intent = { type = "rootMoved",
                position = { x = (tonumber(placement.x) or 0) + dx, y = (tonumber(placement.y) or 0) + dy },
                delta = { x = dx, y = dy }, outlineTarget = target }
            if not CommitWorldIntent(session, rootID, intent, Restore) then return end
            for _, item in ipairs(hosts) do
                if session.entities[item.rootID] == item.entity then
                    WorldInput.Reproject(session, item.rootID, item.entity)
                end
            end
        end })
end

-- [WEB-REQ 59/69] 固定群组：拖光环到另一格 = 移动，目标有光环 = 互换。Provider 按光标位置判断落在哪一格。
local function CursorInHost(entity)
    local x, y = GetCursorPosition()
    local scale = entity.host:GetEffectiveScale() or 1
    local hostX, hostY = entity.host:GetCenter()
    return x / scale - hostX, y / scale - hostY
end

local function BeginCellPointer(session, rootID, entity, entry, origin)
    local provider = session.provider
    local spec = entry.spec
    BeginPointer(session, entity, { origin = origin,
        onMove = function()
            local cursorX, cursorY = CursorInHost(entity)
            local decor
            if type(provider.PreviewWorldElement) == "function" then
                local preview = provider.PreviewWorldElement(rootID, spec.elementID, entry.rect, entry.rect,
                    { mode = "cell", cursor = { x = cursorX, y = cursorY } })
                decor = type(preview) == "table" and preview.decor or nil
            end
            ApplyDecor(entity, decor)
        end,
        onCancel = function() ApplyDecor(entity, nil) end,
        onFinish = function(moved)
            ApplyDecor(entity, nil)
            if not moved or not SessionInputAllowed(session) or session.entities[rootID] ~= entity then return end
            local cursorX, cursorY = CursorInHost(entity)
            if CommitWorldIntent(session, rootID, { type = "cellMoved", elementID = spec.elementID,
                cursor = { x = cursorX, y = cursorY } }) and session.entities[rootID] == entity then
                WorldInput.Reproject(session, rootID, entity)
            end
        end })
end


-- ---------- 元素命中 ----------
-- 点击与拖动分离：OnMouseDown 只做选中（不过 BeforeWorldInput，选中不受播放状态影响）；
-- OnDragStart（RegisterForDrag("LeftButton")）才先停播再进入元素移动 / 缩放 / 整根移动 / 格子拖放；
-- 手势起点取鼠标按下那一刻的光标，起步不跳。
-- 命中顺序靠 Core 统一分配的 frame level：文字 > 子元素 > 本体（悬停与点击同一规则）。
local function WorldPressMode(session, rootID, spec)
    if spec.body ~= true then return "element" end
    local provider = session.provider
    if type(provider.GetWorldPressMode) ~= "function" then return "root" end
    local outline = session.worldOutlines
    local mode = provider.GetWorldPressMode(rootID, spec.elementID, outline and outline.target or nil)
    if mode ~= "root" and mode ~= "container" and mode ~= "cell" then
        error("GetWorldPressMode must return root, container or cell for " .. provider.id .. ":" .. rootID, 3)
    end
    return mode
end

function WorldInput.OnEnter(entry)
    if state.pointer or entry.selected or not entry.spec then return end
    entry.hover:Show()
    local label = entry.spec.label
    if label then
        local theme = entry.theme
        if not entry.nameChip then
            entry.nameChip = CreateChip(entry.root, false)
            WorldInput.SetLevel(entry.nameChip, WorldInput.LEVEL.nameChip)
        end
        entry.nameChip:ClearAllPoints()
        entry.nameChip:SetPoint("BOTTOMLEFT", entry.hover, "TOPLEFT", 0, 2)
        SetChip(entry.nameChip, label, theme.labelBackground, theme.label, theme.badgeSize)
        entry.nameChip:Show()
    end
end

function WorldInput.OnPress(session, rootID, entity, entry, button)
    local spec = entry.spec
    if not spec or session.entities[rootID] ~= entity or not SelectionAllowed() then return end
    -- 真实 frame 已不可见（provider 事后改了结构）：这个命中框是过期的，重新对账后丢弃这次点击。
    if entry.anchorFrame and not entry.anchorFrame:IsVisible() then
        WorldInput.RefreshGeometry(session, rootID, entity)
        return
    end
    if button ~= "LeftButton" then
        SelectWorldElement(session, rootID, spec.elementID, button)
        return
    end
    local mode = WorldPressMode(session, rootID, spec)
    state.press = { kind = "element", session = session, rootID = rootID, entity = entity, entry = entry,
        spec = spec, mode = mode, origin = WorldInput.CursorOrigin() }
    -- 已选中的群组 / 资料夹成员：按下时不改选中，松手没拖动才选中这个光环；拖动则整体移动。
    if mode ~= "container" then SelectWorldElement(session, rootID, spec.elementID, button) end
end

function WorldInput.OnRelease(session, rootID, entity, entry, button)
    local press = state.press
    if button ~= "LeftButton" or not press or press.kind ~= "element" or press.entry ~= entry then return end
    state.press = nil
    if press.mode == "container" and session.entities[rootID] == entity and SelectionAllowed() then
        SelectWorldElement(session, rootID, press.spec.elementID, "LeftButton")
    end
end

function WorldInput.OnDragStart(session, rootID, entity, entry)
    local press = state.press
    if not press or press.kind ~= "element" or press.entry ~= entry then return end
    state.press = nil
    local spec = press.spec
    if session.entities[rootID] ~= entity or not entity.worldElements
        or entity.worldElements[spec.elementID] ~= entry then return end
    if not PrepareWorldInput(session, rootID, entity, spec.elementID, "LeftButton") then return end
    local mode = press.mode
    if mode == "container" then
        -- 已选中的群组 / 资料夹：拖动 = 整体移动。
        local target = session.worldOutlines and session.worldOutlines.target or nil
        BeginRootPointer(session, rootID, entity, target, press.origin)
    elseif mode == "cell" then
        BeginCellPointer(session, rootID, entity, entry, press.origin)
    elseif mode == "root" then
        BeginRootPointer(session, rootID, entity, nil, press.origin)
    elseif spec.movable == true then
        BeginElementPointer(session, rootID, entity, entry, "move", nil, press.origin)
    end
end

local CORNER_DIRECTIONS = { "NW", "NE", "SE", "SW" }
local EDGE_DIRECTIONS = { "N", "E", "S", "W" }

-- 每个命中项的基础部件：命中框（鼠标）、常显淡色轮廓、悬停框。选框、手柄、徽标、描边等
-- 只有被选中 / 描边时才创建（EnsureKit）。全部挂在 SelectionRoot 下。
local function CreateEntryBase(root, theme)
    local entry = { root = root, theme = theme, selected = false }
    entry.hitbox = CreateFrame("Button", nil, root)
    entry.hitbox:EnableMouse(true)
    entry.hitbox:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown")
    entry.hitbox:RegisterForDrag("LeftButton")
    entry.faint = CreateFrame("Frame", nil, root)
    entry.faint:EnableMouse(false)
    entry.faintBorder = CreateBorder(entry.faint, 1)
    PaintBorder(entry.faintBorder, theme.faintAccent)
    entry.faint:Hide()
    entry.hover = CreateFrame("Frame", nil, root)
    entry.hover:EnableMouse(false)
    entry.hoverBorder = CreateBorder(entry.hover, 2)
    PaintBorder(entry.hoverBorder, theme.hover)
    entry.hover:Hide()
    return entry
end

-- 选框的手柄：四角方块 + 四条看不见的拉伸带（跨在选框线上，角方块盖在带子两端之上）。
-- 按下记录手势起点，拖过阈值（OnDragStart）才先停播再开始缩放。
function WorldInput.BindHandles(session, rootID, entity, entry)
    local spec, theme, selection = entry.spec, entry.theme, entry.selection
    local LEVEL = WorldInput.LEVEL
    local resizable = spec.resizable == true
    local thickness = theme.edge
    local function Bind(handle, direction, level)
        WorldInput.SetLevel(handle, level)
        handle:SetShown(resizable)
        handle:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" or not SelectionAllowed() then return end
            if not entity.worldElements or entity.worldElements[spec.elementID] ~= entry then return end
            state.press = { kind = "resize", session = session, rootID = rootID, entity = entity, entry = entry,
                direction = direction, origin = WorldInput.CursorOrigin() }
        end)
        handle:SetScript("OnDragStart", function()
            local press = state.press
            if not press or press.kind ~= "resize" or press.entry ~= entry or press.direction ~= direction then return end
            state.press = nil
            if not entity.worldElements or entity.worldElements[spec.elementID] ~= entry then return end
            if PrepareWorldInput(session, rootID, entity, spec.elementID, "LeftButton") then
                BeginElementPointer(session, rootID, entity, entry, "resize", direction, press.origin)
            end
        end)
        handle:SetScript("OnEnter", function() if direction:len() == 1 then ShowCursorHint(direction) end end)
        handle:SetScript("OnLeave", function() if not state.pointer then HideCursorHint() end end)
    end
    for direction, handle in pairs(entry.corners) do
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", selection, direction == "NW" and "TOPLEFT" or direction == "NE" and "TOPRIGHT"
            or direction == "SE" and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, 0)
        Bind(handle, direction, LEVEL.corner)
    end
    for direction, strip in pairs(entry.edges) do
        strip:ClearAllPoints()
        if direction == "N" then
            strip:SetPoint("TOPLEFT", selection, "TOPLEFT", 0, thickness / 2)
            strip:SetPoint("TOPRIGHT", selection, "TOPRIGHT", 0, thickness / 2)
            strip:SetHeight(thickness)
        elseif direction == "S" then
            strip:SetPoint("BOTTOMLEFT", selection, "BOTTOMLEFT", 0, -thickness / 2)
            strip:SetPoint("BOTTOMRIGHT", selection, "BOTTOMRIGHT", 0, -thickness / 2)
            strip:SetHeight(thickness)
        elseif direction == "W" then
            strip:SetPoint("TOPLEFT", selection, "TOPLEFT", -thickness / 2, 0)
            strip:SetPoint("BOTTOMLEFT", selection, "BOTTOMLEFT", -thickness / 2, 0)
            strip:SetWidth(thickness)
        else
            strip:SetPoint("TOPRIGHT", selection, "TOPRIGHT", thickness / 2, 0)
            strip:SetPoint("BOTTOMRIGHT", selection, "BOTTOMRIGHT", thickness / 2, 0)
            strip:SetWidth(thickness)
        end
        Bind(strip, direction, LEVEL.edge)
    end
end

-- 创建一个命中项的选框套件（资料夹描边、选框、手柄、尺寸徽标）。已有则什么也不做。
function WorldInput.EnsureKit(session, rootID, entity, entry)
    if entry.selection then return end
    local root, theme = entry.root, entry.theme
    entry.outline = CreateFrame("Frame", nil, root)
    entry.outline:EnableMouse(false)
    entry.outlineBorder = CreateBorder(entry.outline, 2)
    PaintBorder(entry.outlineBorder, theme.folder)
    entry.outline:Hide()
    entry.selection = CreateFrame("Frame", nil, root)
    entry.selection:EnableMouse(false)
    entry.selectionBorder = CreateBorder(entry.selection, 1.5)
    PaintBorder(entry.selectionBorder, theme.accent)
    entry.selection:Hide()
    entry.corners, entry.edges = {}, {}
    for _, direction in ipairs(CORNER_DIRECTIONS) do
        local handle = CreateFrame("Button", nil, entry.selection)
        handle:SetSize(theme.handle, theme.handle)
        handle:EnableMouse(true)
        handle:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        handle:RegisterForDrag("LeftButton")
        handle.outer = NewTexture(handle)
        handle.outer:SetAllPoints(handle)
        PaintTexture(handle.outer, theme.accent)
        handle.inner = EXUI:CreateVisualTexture(handle, _G.EXFONTFRAME)
        handle.inner:SetTexture(WHITE_TEXTURE)
        handle.inner:SetPoint("TOPLEFT", handle, "TOPLEFT", 1.5, -1.5)
        handle.inner:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", -1.5, 1.5)
        PaintTexture(handle.inner, theme.chipText)
        entry.corners[direction] = handle
    end
    for _, direction in ipairs(EDGE_DIRECTIONS) do
        local strip = CreateFrame("Button", nil, entry.selection)
        strip:EnableMouse(true)
        strip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        strip:RegisterForDrag("LeftButton")
        entry.edges[direction] = strip
    end
    entry.badge = CreateChip(entry.selection, false)
    entry.badge:SetPoint("TOP", entry.selection, "BOTTOM", 0, -6)
    WorldInput.ApplyLevels(entity, entry)
    WorldInput.BindHandles(session, rootID, entity, entry)
    WorldInput.Layout(entry)
end

local function ClearEntry(entry)
    entry.hitbox:Hide()
    entry.hitbox:ClearAllPoints()
    entry.hitbox:SetHitRectInsets(0, 0, 0, 0)
    for _, name in ipairs({ "OnMouseDown", "OnMouseUp", "OnEnter", "OnLeave", "OnDragStart" }) do
        entry.hitbox:SetScript(name, nil)
    end
    entry.faint:Hide(); entry.faint:ClearAllPoints()
    entry.hover:Hide(); entry.hover:ClearAllPoints()
    if entry.nameChip then entry.nameChip:Hide(); entry.nameChip:ClearAllPoints() end
    if entry.selection then
        entry.outline:Hide(); entry.outline:ClearAllPoints()
        entry.selection:Hide(); entry.selection:ClearAllPoints()
        for _, handle in pairs(entry.corners) do
            handle:SetScript("OnMouseDown", nil); handle:SetScript("OnDragStart", nil)
            handle:SetScript("OnEnter", nil); handle:SetScript("OnLeave", nil)
        end
        for _, strip in pairs(entry.edges) do
            strip:SetScript("OnMouseDown", nil); strip:SetScript("OnDragStart", nil)
            strip:SetScript("OnEnter", nil); strip:SetScript("OnLeave", nil)
        end
    end
    if state.press and state.press.entry == entry then state.press = nil end
    entry.spec, entry.rect, entry.host = nil, nil, nil
    entry.anchorFrame, entry.previewFrame, entry.frameRect, entry.liveRect = nil, nil, nil, nil
    entry.selected = false
end

-- ---------- 群组外框 / 格子 / 手柄（Provider 的 ListWorldOverlays） ----------
-- 外框、格子、手柄的 frame 按“种类”进池复用（每次根刷新都会重建一遍），脚本与 spec 在绑定时才挂上。
-- 它们和元素命中框一样挂在 SelectionRoot 下，层级由 Core 统一分配；rect 是宿主局部单位，摆放时按宿主缩放换算，
-- 边带厚度 / 圆点手柄 / 标签这类“屏幕固定尺寸”的部分不随宿主缩放。
local function BuildOverlayParts(root, spec)
    local parts = { levels = {} }
    local LEVEL = WorldInput.LEVEL
    local function Track(frame, level) parts.levels[#parts.levels + 1] = { frame = frame, level = level } end
    if spec.kind == "frame" then
        parts.visual = CreateFrame("Frame", nil, root)
        parts.visual:EnableMouse(false)
        Track(parts.visual, LEVEL.overlayFrame)
        parts.solid = CreateBorder(parts.visual, 1.5)
        parts.dashed = CreateDashed(parts.visual)
        parts.edges = {}
        for _, direction in ipairs(EDGE_DIRECTIONS) do
            local strip = CreateFrame("Button", nil, root)
            strip:EnableMouse(true)
            strip:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown")
            strip:RegisterForDrag("LeftButton")
            Track(strip, LEVEL.overlayStrip)
            parts.edges[direction] = strip
        end
        if type(spec.label) == "string" then
            parts.chip = CreateChip(root, true)
            parts.chip:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown")
            parts.chip:RegisterForDrag("LeftButton")
            Track(parts.chip, LEVEL.overlayChip)
        end
    elseif spec.kind == "cell" then
        parts.visual = CreateFrame("Frame", nil, root)
        parts.visual:EnableMouse(false)
        Track(parts.visual, LEVEL.overlayCell)
        parts.solid = CreateBorder(parts.visual, 1)
    elseif spec.kind == "handle" then
        local button = CreateFrame("Button", nil, root)
        button:EnableMouse(true)
        button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        Track(button, LEVEL.overlayHandle)
        parts.handle = button
        if spec.shape == "dot" then
            parts.ring = button:CreateTexture(nil, "OVERLAY", nil, 0)
            parts.ring:SetTexture(CIRCLE_TEXTURE)
            parts.ring:SetTexCoord(CIRCLE_COORD, CIRCLE_COORD_MAX, CIRCLE_COORD, CIRCLE_COORD_MAX)
            parts.ring:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
            parts.ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
            parts.fill = button:CreateTexture(nil, "OVERLAY", nil, 1)
            parts.fill:SetTexture(CIRCLE_TEXTURE)
            parts.fill:SetTexCoord(CIRCLE_COORD, CIRCLE_COORD_MAX, CIRCLE_COORD, CIRCLE_COORD_MAX)
            parts.fill:SetAllPoints(button)
        else
            parts.fill = NewTexture(button)
            parts.fill:SetAllPoints(button)
        end
    elseif spec.kind == "label" then
        parts.chip = CreateChip(root, false)
        Track(parts.chip, LEVEL.overlayLabel)
    else
        error("ListWorldOverlays contains an unknown overlay kind: " .. tostring(spec.kind), 4)
    end
    return parts
end

local function OverlayPoolKey(spec)
    return tostring(spec.kind) .. ":" .. tostring(spec.shape or "") .. ":"
        .. ((spec.kind == "frame" and type(spec.label) == "string") and "label" or "plain")
end

local function CreateOverlayWidget(session, rootID, entity, bundle, spec, theme)
    local root = bundle.root
    local key = OverlayPoolKey(spec)
    bundle.overlayPool = bundle.overlayPool or {}
    local pool = bundle.overlayPool[key]
    local parts = pool and table.remove(pool) or BuildOverlayParts(root, spec)
    parts.key = key
    for _, tracked in ipairs(parts.levels) do WorldInput.SetLevel(tracked.frame, tracked.level) end
    local widget = { spec = spec }
    local host = entity.host
    local thickness = spec.edgeHit or 12

    -- 点击与拖动分离：鼠标按下只做选中（群组外框的边带 / 标签选中该群组，不过 BeforeWorldInput）；
    -- OnDragStart 才先过 BeforeWorldInput 再开始整根移动 / 手柄拖动。
    local function OnPress(source, kind, button)
        if session.entities[rootID] ~= entity or not SelectionAllowed() then return end
        if kind == "root" and type(session.provider.OnSelect) == "function" then
            session.provider.OnSelect(rootID, nil, button, WorldModifiers())
        end
        if button == "LeftButton" then
            state.press = { kind = kind, source = source, session = session, rootID = rootID,
                entity = entity, origin = WorldInput.CursorOrigin() }
        end
    end

    local function BeginHandleDrag(origin)
        local provider = session.provider
        BeginPointer(session, entity, { origin = origin,
            onMove = function(dx, dy)
                if type(provider.PreviewWorldOverlay) ~= "function" then return end
                local overrides = provider.PreviewWorldOverlay(rootID, spec.id, dx, dy)
                if type(overrides) == "table" then
                    for overlayID, value in pairs(overrides) do
                        local target = entity.worldOverlayByID and entity.worldOverlayByID[overlayID]
                        if target then target.Override(value) end
                    end
                end
            end,
            onCancel = function()
                for _, other in ipairs(entity.worldOverlays or {}) do other.Override(nil) end
            end,
            onFinish = function(moved, dx, dy)
                for _, other in ipairs(entity.worldOverlays or {}) do other.Override(nil) end
                if not moved or not SessionInputAllowed(session) or session.entities[rootID] ~= entity then return end
                if CommitWorldIntent(session, rootID, { type = "overlayDragged", overlayID = spec.id,
                    dx = dx, dy = dy }) and session.entities[rootID] == entity then
                    WorldInput.Reproject(session, rootID, entity)
                end
            end })
    end

    local function OnDrag(source, kind)
        local press = state.press
        if not press or press.source ~= source or press.kind ~= kind then return end
        state.press = nil
        if session.entities[rootID] ~= entity then return end
        if not PrepareWorldInput(session, rootID, entity, nil, "LeftButton") then return end
        if kind == "root" then
            BeginRootPointer(session, rootID, entity, nil, press.origin)
        else
            BeginHandleDrag(press.origin)
        end
    end

    local override
    local function Place()
        local current = override and override.rect or spec.rect
        if spec.kind == "frame" then
            WorldInput.PlaceVirtual(parts.visual, host, current, 0)
            for direction, strip in pairs(parts.edges) do
                strip:ClearAllPoints()
                local t = thickness
                if direction == "N" then
                    strip:SetPoint("TOPLEFT", parts.visual, "TOPLEFT", -t / 2, t / 2)
                    strip:SetPoint("TOPRIGHT", parts.visual, "TOPRIGHT", t / 2, t / 2); strip:SetHeight(t)
                elseif direction == "S" then
                    strip:SetPoint("BOTTOMLEFT", parts.visual, "BOTTOMLEFT", -t / 2, -t / 2)
                    strip:SetPoint("BOTTOMRIGHT", parts.visual, "BOTTOMRIGHT", t / 2, -t / 2); strip:SetHeight(t)
                elseif direction == "W" then
                    strip:SetPoint("TOPLEFT", parts.visual, "TOPLEFT", -t / 2, t / 2)
                    strip:SetPoint("BOTTOMLEFT", parts.visual, "BOTTOMLEFT", -t / 2, -t / 2); strip:SetWidth(t)
                else
                    strip:SetPoint("TOPRIGHT", parts.visual, "TOPRIGHT", t / 2, t / 2)
                    strip:SetPoint("BOTTOMRIGHT", parts.visual, "BOTTOMRIGHT", t / 2, -t / 2); strip:SetWidth(t)
                end
            end
            if parts.chip then
                parts.chip:ClearAllPoints()
                parts.chip:SetPoint("BOTTOMLEFT", parts.visual, "TOPLEFT", -1, 3)
            end
        elseif spec.kind == "cell" then
            WorldInput.PlaceVirtual(parts.visual, host, current, 0)
        elseif spec.kind == "handle" then
            WorldInput.PlaceVirtual(parts.handle, host, current, 0, spec.shape == "dot")
        else
            local ratio = WorldInput.ScaleRatio(host, parts.chip)
            parts.chip:ClearAllPoints()
            parts.chip:SetPoint(spec.anchor or "LEFT", host, "CENTER", current.x * ratio, current.y * ratio)
        end
    end

    -- ownerID：当前被选中的群组 ID；visible：覆盖层总开关（编辑视觉开关 + 输入是否可用）。
    function widget.Apply(ownerID, visible)
        local current = ownerID ~= nil and ownerID == spec.owner
        local shown = visible == true and (spec.onlyCurrent ~= true or current)
        if spec.kind == "frame" then
            parts.visual:SetShown(shown)
            for _, strip in pairs(parts.edges) do strip:SetShown(shown) end
            local currentRect = override and override.rect or spec.rect
            if current then
                SetDashedShown(parts.dashed, false)
                SetBorderShown(parts.solid, true)
                PaintBorder(parts.solid, theme.accent)
            elseif spec.border == "dashed" then
                SetBorderShown(parts.solid, false)
                local ratio = WorldInput.ScaleRatio(host, parts.visual)
                LayoutDashed(parts.dashed, currentRect.width * ratio, currentRect.height * ratio, theme.dashed)
            else
                SetDashedShown(parts.dashed, false)
                SetBorderShown(parts.solid, true)
                PaintBorder(parts.solid, theme.faint)
            end
            if parts.chip then
                parts.chip:SetShown(shown)
                local text = override and override.text or spec.label
                if current then SetChip(parts.chip, text, theme.accent, theme.chipDark, theme.badgeSize)
                else SetChip(parts.chip, text, theme.chipBackground, theme.chipMuted, theme.badgeSize) end
            end
        elseif spec.kind == "cell" then
            parts.visual:SetShown(shown)
            local color = current and theme.cellCurrent or theme.cell
            if spec.used then color = current and theme.cellCurrentUsed or theme.cellUsed end
            PaintBorder(parts.solid, color)
        elseif spec.kind == "handle" then
            parts.handle:SetShown(shown)
            PaintTexture(parts.fill, spec.color == "yellow" and theme.yellow or theme.accent)
            if parts.ring then PaintTexture(parts.ring, theme.handleRing) end
        else
            parts.chip:SetShown(shown)
            SetChip(parts.chip, override and override.text or spec.text, theme.labelBackground, theme.label, theme.badgeSize)
        end
    end

    function widget.Override(value)
        override = value
        Place()
        widget.Apply(session.worldSelection and session.worldSelection.ownerID, session.worldVisible == true)
    end

    widget.spec = spec
    function widget.UpdateSpec(value)
        spec, widget.spec, override = value, value, nil
        Place()
        widget.Apply(session.worldSelection and session.worldSelection.ownerID, session.worldVisible == true)
    end

    function widget.Release()
        if spec.kind == "frame" then
            for _, strip in pairs(parts.edges) do
                strip:Hide(); strip:SetScript("OnMouseDown", nil); strip:SetScript("OnDragStart", nil); strip:ClearAllPoints()
            end
            SetDashedShown(parts.dashed, false)
        end
        for _, name in ipairs({ "visual", "chip", "handle" }) do
            local frame = parts[name]
            if frame then
                frame:Hide()
                frame:ClearAllPoints()
                if frame.SetScript then frame:SetScript("OnMouseDown", nil); frame:SetScript("OnDragStart", nil) end
            end
        end
        local list = bundle.overlayPool[key]
        if not list then list = {}; bundle.overlayPool[key] = list end
        list[#list + 1] = parts
    end

    -- 脚本绑定
    if spec.kind == "frame" then
        for _, strip in pairs(parts.edges) do
            strip:SetScript("OnMouseDown", function(self, button) OnPress(self, "root", button) end)
            strip:SetScript("OnDragStart", function(self) OnDrag(self, "root") end)
        end
        if parts.chip then
            parts.chip:SetScript("OnMouseDown", function(self, button) OnPress(self, "root", button) end)
            parts.chip:SetScript("OnDragStart", function(self) OnDrag(self, "root") end)
        end
    elseif spec.kind == "handle" then
        parts.handle:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            OnPress(self, "handle", button)
        end)
        parts.handle:SetScript("OnDragStart", function(self) OnDrag(self, "handle") end)
    end
    Place()
    return widget
end

local function ReleaseOverlays(entity)
    local widgets = entity.worldOverlays or {}
    while #widgets > 0 do
        widgets[#widgets].Release()
        widgets[#widgets] = nil
    end
    entity.worldOverlays, entity.worldOverlayByID = nil, nil
end

-- ---------- 世界输入层：枚举、创建与刷新 ----------
-- frame 型元素的命中框 / 悬停 / 选框直接锚在真实 frame 上（暴雪的选择框也是直接锚在系统 frame 上），
-- 几何随 frame 走，不依赖枚举快照；虚拟 rect 型元素（字形框、格子、手柄……）与群组外框按 host 局部 rect
-- 摆放，几何变化由重新枚举更新。重新枚举的唯一入口是 RefreshEntityWorldGeometry：
-- 创建实体、会话时钟应用 / 恢复样本、提交成功后的原地更新，以及公开的
-- EXUI:RefreshEditSessionWorldGeometry 都走它；Core 不轮询几何。

function WorldInput.StageError(session, rootID, stage, reason)
    return "EXUI edit session failed | provider=" .. session.provider.id .. " | root=" .. tostring(rootID)
        .. " | stage=" .. tostring(stage) .. "\n" .. tostring(reason)
end

-- 世界编辑的宿主与 SelectionRoot 共用的 strata：EXAura 的宿主在 HIGH，选框必须压过光环、又低于 DIALOG 的编辑器面板。
function WorldInput.PresentationStrata(provider)
    return provider.addon == "EXAura" and "HIGH" or "FULLSCREEN_DIALOG"
end

-- 把 provider 的一个元素规格解析成输入项。返回 item；或 nil, 原因, isDrop：
-- isDrop = false 表示违反合同（调用方抛错）；isDrop = true 表示 frame 暂时没有可用几何，
-- 元素被丢弃并带原因上报（聊天框与 GetEditSessionDiagnostics）。
function WorldInput.ResolveSpec(host, spec)
    local band = WorldInput.LEVEL.band
    if spec.frame ~= nil and spec.rect ~= nil then
        return nil, "declares both frame and rect; a provider must choose a frame-type or a virtual rect-type element", false
    end
    if spec.frame == nil and spec.rect == nil then return nil, "declares neither frame nor rect", false end
    if spec.label ~= nil and type(spec.label) ~= "string" then return nil, "label must be a string", false end
    if spec.priority ~= nil and band[spec.priority] == nil then
        return nil, "priority must be text, child or body", false
    end
    local item = { spec = spec }
    if spec.frame ~= nil then
        if spec.previewFrame ~= nil or spec.frameRect ~= nil then
            return nil, "a frame-type element cannot declare previewFrame or frameRect", false
        end
        if not WorldInput.IsFrame(spec.frame) then return nil, "frame is not a Frame", false end
        local rect, reason = WorldInput.FrameLocalRect(host, spec.frame)
        if not rect then return nil, reason, true end
        item.anchorFrame, item.previewFrame, item.rect, item.frameRect = spec.frame, spec.frame, rect, rect
        return item
    end
    local rect, reason = ReadWorldRect(spec.rect)
    if not rect then return nil, "rect " .. reason, false end
    item.rect = rect
    if spec.previewFrame ~= nil then
        if not WorldInput.IsFrame(spec.previewFrame) then return nil, "previewFrame is not a Frame", false end
        local frameRect
        if spec.frameRect ~= nil then
            frameRect, reason = ReadWorldRect(spec.frameRect)
            if not frameRect then return nil, "frameRect " .. reason, false end
        else
            frameRect, reason = WorldInput.FrameLocalRect(host, spec.previewFrame)
            if not frameRect then return nil, "previewFrame: " .. reason, true end
        end
        item.previewFrame, item.frameRect = spec.previewFrame, frameRect
    elseif spec.frameRect ~= nil then
        return nil, "frameRect requires previewFrame", false
    end
    return item
end

-- 枚举并校验元素规格；先全部校验再动任何 Core frame，错误不会留下半更新的输入层。
-- 成功返回 resolved（输入项数组）、dropped（elementID → 丢弃原因）、renderer；
-- 违反合同返回 nil, 原因（由调用方清理后抛错）。provider 回调自己抛的错原样传出。
local function ListWorldElementSpecs(session, rootID, entity)
    local provider = session.provider
    local renderer = entity.rendererActive and entity.renderer or entity.previews
    local listed = provider.ListWorldElements(rootID, renderer)
    if type(listed) ~= "table" then return nil, "ListWorldElements must return an array" end
    local resolved, dropped, seen = {}, {}, {}
    for _, spec in ipairs(listed) do
        if type(spec) ~= "table" or type(spec.elementID) ~= "string" or spec.elementID == "" then
            return nil, "ListWorldElements contains an item without a non-empty string elementID"
        end
        if seen[spec.elementID] then
            return nil, "ListWorldElements contains a duplicate elementID: " .. spec.elementID
        end
        seen[spec.elementID] = true
        local item, reason, isDrop = WorldInput.ResolveSpec(entity.host, spec)
        if item then
            resolved[#resolved + 1] = item
        elseif isDrop then
            dropped[spec.elementID] = reason
        else
            return nil, "ListWorldElements element " .. spec.elementID .. ": " .. reason
        end
    end
    return resolved, dropped, renderer
end

local function ListWorldOverlaySpecs(session, rootID, entity, renderer)
    local provider = session.provider
    local overlays = {}
    if type(provider.ListWorldOverlays) == "function" then
        overlays = provider.ListWorldOverlays(rootID, renderer)
        if type(overlays) ~= "table" then return nil, "ListWorldOverlays must return an array" end
    end
    local seen = {}
    for _, spec in ipairs(overlays) do
        if type(spec) ~= "table" or type(spec.id) ~= "string" or seen[spec.id] then
            return nil, "ListWorldOverlays contains an invalid or duplicate overlay id"
        end
        seen[spec.id] = true
        if spec.kind ~= "frame" and spec.kind ~= "cell" and spec.kind ~= "handle" and spec.kind ~= "label" then
            return nil, "ListWorldOverlays overlay " .. spec.id .. " has an unknown kind: " .. tostring(spec.kind)
        end
        local rect = spec.rect
        if type(rect) ~= "table" or not IsFiniteNumber(rect.x) or not IsFiniteNumber(rect.y) then
            return nil, "ListWorldOverlays overlay " .. spec.id .. " requires a rect with finite x and y"
        end
        -- label 只用 x / y 定位；其余种类还需要正的宽高。
        if spec.kind ~= "label" then
            local _, reason = ReadWorldRect(rect)
            if reason then return nil, "ListWorldOverlays overlay " .. spec.id .. " rect " .. reason end
        end
    end
    return overlays
end

-- 被丢弃的元素必须带原因上报：同一元素同一原因只在聊天框提示一次，完整列表见 GetEditSessionDiagnostics。
function WorldInput.ReportDropped(session, rootID, entity, dropped)
    local previous = entity.reportedDrops or {}
    local reported = {}
    for elementID, reason in pairs(dropped) do
        reported[elementID] = reason
        if previous[elementID] ~= reason then
            local detail = "edit session dropped a world element: " .. session.provider.id .. ":" .. rootID
                .. ":" .. elementID .. ": " .. tostring(reason)
            if type(ExwindTools.LogError) == "function" then
                ExwindTools:LogError("EditModeInput[" .. session.provider.id .. "]", detail)
            end
            print(detail)
        end
    end
    entity.reportedDrops = reported
    entity.droppedElements = dropped
end

-- 把一个输入项绑定到命中项：新建与刷新共用。reused = true 时保留悬停 / 选中 / 描边的显示状态，
-- 只更新规格、几何、层级、手柄与脚本。
local function BindWorldElementEntry(session, rootID, entity, entry, item, reused)
    local spec = item.spec
    entry.host, entry.spec = entity.host, spec
    entry.rect, entry.anchorFrame = item.rect, item.anchorFrame
    entry.previewFrame, entry.frameRect = item.previewFrame, item.frameRect
    entry.liveRect = nil
    if not reused then
        WorldInput.HideVisuals(entry)
        entry.selected = false
    end
    WorldInput.ApplyLevels(entity, entry)
    WorldInput.Layout(entry)
    entry.hitbox:SetShown(EvaluateWorldElementFilter(session.worldElementFilters[rootID], rootID, spec.elementID))
    if entry.selection then WorldInput.BindHandles(session, rootID, entity, entry) end
    entry.hitbox:SetScript("OnEnter", function() WorldInput.OnEnter(entry) end)
    entry.hitbox:SetScript("OnLeave", function() WorldInput.HideHover(entry) end)
    entry.hitbox:SetScript("OnMouseDown", function(_, button)
        WorldInput.OnPress(session, rootID, entity, entry, button)
    end)
    entry.hitbox:SetScript("OnMouseUp", function(_, button)
        WorldInput.OnRelease(session, rootID, entity, entry, button)
    end)
    entry.hitbox:SetScript("OnDragStart", function()
        WorldInput.OnDragStart(session, rootID, entity, entry)
    end)
end

-- 按 elementID 对账：已存在的命中项原地更新，新元素取空闲项，消失的元素清掉。
local function ApplyWorldElementSpecs(session, rootID, entity, resolved)
    local bundle = entity.worldOverlayBundle
    local theme = WorldTheme(session)
    local bound = entity.worldElements
    local free = {}
    for _, entry in ipairs(bundle.entries) do
        if entry.spec == nil then free[#free + 1] = entry end
    end
    local current = {}
    for _, item in ipairs(resolved) do
        local elementID = item.spec.elementID
        local entry = bound[elementID]
        local reused = entry ~= nil
        if not entry then
            entry = table.remove(free)
            if not entry then
                entry = CreateEntryBase(bundle.root, theme)
                bundle.entries[#bundle.entries + 1] = entry
            end
            entry.theme = theme
            bound[elementID] = entry
        end
        current[elementID] = true
        BindWorldElementEntry(session, rootID, entity, entry, item, reused)
    end
    for elementID, entry in pairs(bound) do
        if not current[elementID] then
            ClearEntry(entry)
            bound[elementID] = nil
        end
    end
end

-- 群组外框 / 格子 / 手柄：整组释放后按最新规格重建（frame 进池复用）。
local function ApplyWorldOverlaySpecs(session, rootID, entity, overlays)
    local bundle, theme = entity.worldOverlayBundle, WorldTheme(session)
    ReleaseOverlays(entity)
    entity.worldOverlays, entity.worldOverlayByID = {}, {}
    for _, spec in ipairs(overlays) do
        local widget = CreateOverlayWidget(session, rootID, entity, bundle, spec, theme)
        entity.worldOverlays[#entity.worldOverlays + 1] = widget
        entity.worldOverlayByID[spec.id] = widget
    end
end

-- Core 自有的 SelectionRoot（每个 provider 一个）：挂 UIParent，不挂宿主。
--   · SetFixedFrameStrata / SetFixedFrameLevel：strata 压过被编辑光环、低于 DIALOG 的编辑器面板，
--     层级由 Core 统一分配，不被任何宿主、provider 或点击 Raise 改写；
--   · SetIgnoreParentAlpha：宿主 alpha 为 0（播放）或被改写时选框照常显示（暴雪选框同样 ignoreParentAlpha）；
--   · SetIgnoreParentScale + scale = UIParent 有效缩放：手柄、边带、描边、徽标是屏幕固定尺寸，不随宿主 scale 缩放；
--     UI 缩放变化时同步 scale 并重新枚举（虚拟 rect 的换算比例随之更新）。
function WorldInput.EnsureRoot(provider)
    local root = state.selectionRoots[provider.id]
    if root then return root end
    root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata(WorldInput.PresentationStrata(provider))
    root:SetFixedFrameStrata(true)
    root:SetFrameLevel(WorldInput.LEVEL.rootBase)
    root:SetFixedFrameLevel(true)
    root:SetIgnoreParentAlpha(true)
    root:SetIgnoreParentScale(true)
    root:SetScale(UIParent:GetEffectiveScale())
    root:SetAllPoints(UIParent)
    root:EnableMouse(false)
    root:Show()
    root.providerID = provider.id
    root:RegisterEvent("UI_SCALE_CHANGED")
    root:RegisterEvent("DISPLAY_SIZE_CHANGED")
    root:SetScript("OnEvent", function(frame)
        frame:SetScale(UIParent:GetEffectiveScale())
        local session = state.editSessions[frame.providerID]
        if session and session.provider.contract == "presentation-transaction" and session.phase == "ACTIVE" then
            for rootID, entity in pairs(session.entities) do
                WorldInput.RefreshGeometry(session, rootID, entity)
            end
        end
    end)
    state.selectionRoots[provider.id] = root
    return root
end

-- 创建输入层：命中项、群组外框 / 格子 / 手柄、装饰层。实体此时还在 session.pending。
function WorldInput.BindInputs(session, rootID, entity, resolved, dropped, overlays)
    local provider = session.provider
    local root = WorldInput.EnsureRoot(provider)
    local theme = WorldTheme(session)
    local pool = state.worldOverlayPool[provider.id]
    if not pool then pool = {}; state.worldOverlayPool[provider.id] = pool end
    local bundle = table.remove(pool)
    if not bundle then bundle = { root = root, entries = {} } end
    bundle.root = root
    if not bundle.decor then bundle.decor = CreateDecor(root, theme) end
    bundle.decor.frame:Show()
    entity.worldElements, entity.worldOverlayBundle = {}, bundle
    entity.worldDecor = bundle.decor
    ApplyWorldElementSpecs(session, rootID, entity, resolved)
    ApplyWorldOverlaySpecs(session, rootID, entity, overlays)
    -- 元素列表与外框都为空是显式的“空根”状态：没有任何命中面，不再悄悄退化为宿主命中。
    entity.emptyRoot = #resolved == 0 and #overlays == 0
    WorldInput.ReportDropped(session, rootID, entity, dropped)
end

-- 重新枚举一个根的元素与群组外框并原地更新。返回 true，或 false + 原因（该根正被指针手势占用时拒绝：
-- 手势中的预览由 Core 自己摆放，松手后再对账）。provider 回调出错与违反合同都直接抛出；校验先于任何改动。
local function RefreshEntityWorldGeometry(session, rootID, entity)
    if not entity.worldOverlayBundle then return true end
    if state.pointer and state.pointer.entity == entity then
        return false, "world pointer gesture in progress"
    end
    RunCommitResidue()
    local resolved, dropped, renderer = ListWorldElementSpecs(session, rootID, entity)
    if not resolved then error(WorldInput.StageError(session, rootID, "refresh-elements", dropped), 0) end
    local overlays, overlayReason = ListWorldOverlaySpecs(session, rootID, entity, renderer)
    if not overlays then error(WorldInput.StageError(session, rootID, "refresh-overlays", overlayReason), 0) end
    ApplyWorldElementSpecs(session, rootID, entity, resolved)
    ApplyWorldOverlaySpecs(session, rootID, entity, overlays)
    entity.emptyRoot = #resolved == 0 and #overlays == 0
    WorldInput.ReportDropped(session, rootID, entity, dropped)
    SetWorldElementSelection(session)
    return true
end
WorldInput.RefreshGeometry = RefreshEntityWorldGeometry

-- 提交成功后的原地更新：重新取放置信息摆回宿主，再对账输入层；命中框 / 选框 / 悬停状态保留，
-- 不销毁重建整根。provider 的内容刷新由它自己完成（见手册）；只有对象结构变了
-- （根不再投影、世界渲染路线变了）才走一次对账重建。
function WorldInput.Reproject(session, rootID, entity)
    if session.entities[rootID] ~= entity then return true end
    local provider = session.provider
    local project = provider.Project(rootID)
    local needsRebuild = type(project) ~= "table" or type(project.placement) ~= "table"
    if not needsRebuild then
        needsRebuild = SelectsPresentationWorldRenderer(provider, rootID, project) ~= (entity.rendererActive == true)
    end
    if needsRebuild then
        session.dirtyRoots[rootID] = true
        return WorldInput.Reconcile(provider.id)
    end
    entity.placement = project.placement
    ApplyPresentationPlacement(entity.host, project.placement)
    return RefreshEntityWorldGeometry(session, rootID, entity)
end

-- 释放一个实体持有的全部 Core 资源：输入层、provider 世界渲染、宿主。已登记实体和创建中途失败的
-- 半成品（仍在 session.pending）走同一条路径；rendererActive 在渲染开始前置位，所以半成品也一定会
-- 调用 ReleaseWorld（此时 renderer 可能为 nil，provider 的 ReleaseWorld 必须容忍）。
local function ReleaseEntityResources(session, rootID, entity)
    -- Ownership survives a throwing ReleaseWorld/Unmount. A later close or
    -- reconcile resumes the unfinished steps; completed resources are detached.
    session.releasing = session.releasing or {}
    session.releasing[entity] = rootID
    if entity.releaseStamp == _G.GetTime() then return false, "entity release is already in progress" end
    entity.releaseStamp = _G.GetTime()
    if state.pointer and state.pointer.entity == entity then CancelPointer() end
    if state.press and state.press.entity == entity then state.press = nil end
    local bundle = entity.worldOverlayBundle
    if bundle then
        for _, entry in ipairs(bundle.entries) do ClearEntry(entry) end
        ReleaseOverlays(entity)
        HideDecor(bundle.decor)
        local pool = state.worldOverlayPool[session.provider.id]
        if not pool then pool = {}; state.worldOverlayPool[session.provider.id] = pool end
        pool[#pool + 1] = bundle
        entity.worldOverlayBundle, entity.worldElements, entity.worldDecor = nil, nil, nil
    end
    -- 只有真正画过宿主覆盖层的实体才需要再隐藏它（该调用会向 provider 取 GetWorldBounds）。
    if entity.overlayApplied then
        SetPresentationOverlay(session, rootID, entity, false)
        entity.overlayApplied = nil
    end
    -- A transaction entity is atomic.  Core always owns the release moment;
    -- renderer entities never acquire StandardPreview, and preview entities
    -- retain their existing terminal unmount behaviour.
    if entity.rendererActive then
        local released, reason = session.provider.ReleaseWorld(rootID, entity.renderer)
        if released == false then entity.releaseStamp = nil; return false, reason or "ReleaseWorld rejected" end
        entity.renderer, entity.rendererActive = nil, nil
    else
        local previews = entity.previews or {}
        while #previews > 0 do
            local preview = previews[#previews]
            preview:Unmount()
            if entity.previewScales then entity.previewScales[preview] = nil end
            if entity.layerTransforms then entity.layerTransforms[#previews] = nil end
            previews[#previews] = nil
        end
    end
    local layerHosts = entity.layerHosts or {}
    while #layerHosts > 0 do
        local layerHost = layerHosts[#layerHosts]
        layerHost:Hide()
        layerHost:EnableMouse(false)
        layerHost:ClearAllPoints()
        layerHost:SetParent(nil)
        layerHost:SetScale(1)
        layerHost:SetAlpha(1)
        local pool = state.presentationLayerHostPool[session.provider.id]
        pool[#pool + 1] = layerHost
        layerHosts[#layerHosts] = nil
    end
    local host = entity.host
    if host then
        host:SetScript("OnMouseDown", nil)
        host:EnableMouse(false)
        host:Hide()
        host:ClearAllPoints()
        host:SetParent(nil)
        local pool = state.presentationHostPool[session.provider.id]
        if not pool then pool = {}; state.presentationHostPool[session.provider.id] = pool end
        pool[#pool + 1] = host
        entity.host = nil
    end
    if session.restorePending and session.restorePending[rootID] == entity then
        session.restorePending[rootID] = nil
    end
    session.releasing[entity], entity.releaseStamp = nil, nil
    return true
end

local function DestroyPresentationEntity(session, rootID)
    local entity = session.entities[rootID]
    if not entity then return true end
    -- Remove ownership before destroying UI so a provider release callback
    -- cannot re-enter a half-destroyed entity.
    session.entities[rootID] = nil
    return ReleaseEntityResources(session, rootID, entity)
end

-- 回收创建中途被 provider 回调抛错打断的半成品（见 CreatePresentationEntity）。
local function SweepPendingEntities(session)
    session.releasing = session.releasing or {}
    for rootID, entity in pairs(session.pending) do
        session.releasing[entity] = rootID
        session.pending[rootID] = nil
    end
    for entity, rootID in pairs(session.releasing) do
        local released, reason = ReleaseEntityResources(session, rootID, entity)
        if not released then return false, reason end
    end
    return true
end

local function ValidatePresentationProject(provider, rootID, project)
    local providerID = provider.id
    if type(project) ~= "table" or type(project.placement) ~= "table" then
        error("Project() must return a table with placement for " .. providerID, 3)
    end
    local usesWorldRenderer = SelectsPresentationWorldRenderer(provider, rootID, project)
    if usesWorldRenderer then
        -- RenderWorld receives this same immutable project data and paints into
        -- the Core-owned host.  No StandardPreview is constructed on this path.
        return project, true
    end
    if type(project.layers) ~= "table" or #project.layers == 0 then
        error("Project().layers must be a non-empty array for " .. providerID, 3)
    end
    for index, layer in ipairs(project.layers) do
        if type(layer) ~= "table" or type(layer.definition) ~= "table" or type(layer.model) ~= "table" then
            error("Project().layers[" .. index .. "] must be { definition = table, model = table } for " .. providerID, 3)
        end
    end
    return project, false
end

local function FailEntityCreation(session, rootID, entity, stage, reason)
    session.pending[rootID] = nil
    ReleaseEntityResources(session, rootID, entity)
    error(WorldInput.StageError(session, rootID, stage, reason), 0)
end

-- Only transaction world layers consume outerTransform. StandardPreview keeps
-- its local model contract; the pure copy never changes provider-owned data.
function WorldInput.PreparePresentationLayers(layers)
    local prepared = {}
    for index, layer in ipairs(layers) do
        local definition = EXUI:SnapshotPreviewData(layer.definition, "EditMode.layer.definition")
        local model = EXUI:SnapshotPreviewData(layer.model, "EditMode.layer.model")
        local transform = model.outerTransform
        local scale, alpha = 1, 1
        if transform ~= nil then
            if type(transform) ~= "table" then error("model.outerTransform must be a table", 3) end
            scale = transform.scale == nil and 1 or transform.scale
            alpha = transform.alpha == nil and 1 or transform.alpha
            if not IsFiniteNumber(scale) or scale <= 0 then error("outerTransform.scale must be positive and finite", 3) end
            if not IsFiniteNumber(alpha) or alpha < 0 or alpha > 1 then error("outerTransform.alpha must be within [0,1]", 3) end
            if definition.layout and definition.layout.mode == "ABSOLUTE" then
                if type(model.items) ~= "table" then error("layer model.items must be an array", 3) end
                for _, item in ipairs(model.items) do
                    local position = item.position
                    if type(position) ~= "table" or not IsFiniteNumber(position.x) or not IsFiniteNumber(position.y) then
                        error("absolute layer position must contain finite x/y", 3)
                    end
                    position.x, position.y = position.x / scale, position.y / scale
                    if not IsFiniteNumber(position.x) or not IsFiniteNumber(position.y) then
                        error("absolute layer position exceeds local coordinate range", 3)
                    end
                end
            end
            model.outerTransform = nil
        end
        EXUI:ValidateStandardPreviewData(definition, model)
        prepared[index] = { definition = definition, model = model,
            transformed = transform ~= nil, scale = scale, alpha = alpha }
    end
    return prepared
end

-- 实体创建是原子的：先渲染、再校验并枚举、再创建输入层，全部成功后才把实体写进 session.entities。
-- 创建期间实体登记在 session.pending 且 rendererActive 在渲染开始前就已置位：
--   · Core 自己发现的问题（元素规格不合格等）立刻 ReleaseWorld 并清理，再带着根 ID 与阶段抛错；
--   · provider 回调自己抛出的错误无法在这里拦截（Core 不拦截错误），错误原样交给游戏错误处理器，
--     半成品留在 pending，下一次对账或会话结束时一定会 ReleaseWorld 并回收宿主。
-- 阶段（entity.stage）可在 GetEditSessionDiagnostics().pending 里看到。
local function CreatePresentationEntity(session, rootID)
    local provider = session.provider
    -- profile 没有世界输入主题时，在创建任何资源之前就报错。
    WorldTheme(session)
    local project, usesWorldRenderer = ValidatePresentationProject(provider, rootID, provider.Project(rootID))
    local preparedLayers = not usesWorldRenderer and WorldInput.PreparePresentationLayers(project.layers) or nil
    local belowEditor = provider.addon == "EXAura"
    local parent = belowEditor and UIParent or EnsurePresentationRoot()
    local pool = state.presentationHostPool[provider.id]
    local host = pool and table.remove(pool) or CreateFrame("Frame", nil, parent)
    host:SetParent(parent)
    -- A pooled root may previously have hosted a scaled renderer. World layer
    -- transforms are relative to a neutral root, never to its previous owner.
    host:SetScale(1)
    host:SetAlpha(1)
    host:SetFrameStrata(WorldInput.PresentationStrata(provider))
    host:SetFrameLevel(2)
    host:SetMovable(false)
    -- 宿主永远不吃鼠标：命中、悬停、选中与拖动全部由 Core 自有的 SelectionRoot 承担。
    host:EnableMouse(false)
    host:EnableKeyboard(false)
    host:RegisterForDrag()
    ApplyPresentationPlacement(host, project.placement)
    session.orderSeq = (session.orderSeq or 0) + 1
    local entity = { host = host, previews = {}, layerHosts = {}, previewScales = {}, layerTransforms = {}, placement = project.placement, rootID = rootID,
        order = (session.orderSeq - 1) % 900, stage = "render",
        rendererActive = usesWorldRenderer or nil }
    session.pending[rootID] = entity
    entity.standardLayers = preparedLayers

    if usesWorldRenderer then
        -- The renderer is allowed to return a collection handle.  Core treats
        -- it as opaque and passes it back only to ReleaseWorld/GetWorldBounds;
        -- the host itself remains Core-owned for placement and teardown.
        entity.renderer = provider.RenderWorld(rootID, host, project)
    else
        for _, layer in ipairs(preparedLayers) do
            local layerHost = host
            if layer.transformed then
                state.presentationLayerHostPool = state.presentationLayerHostPool or {}
                local layerPool = state.presentationLayerHostPool[provider.id]
                if not layerPool then layerPool = {}; state.presentationLayerHostPool[provider.id] = layerPool end
                layerHost = table.remove(layerPool) or CreateFrame("Frame", nil, host)
                -- Register before any setup that can throw; pending-entity
                -- cleanup owns this host even if Materialize never returns.
                entity.layerHosts[#entity.layerHosts + 1] = layerHost
                layerHost:SetParent(host)
                layerHost:ClearAllPoints()
                layerHost:SetScale(layer.scale)
                layerHost:SetAlpha(layer.alpha)
                layerHost:EnableMouse(false)
                layerHost:EnableKeyboard(false)
                layerHost:SetSize(1, 1)
                layerHost:SetPoint("CENTER", host, "CENTER", 0, 0)
                layerHost:SetFrameStrata(host:GetFrameStrata())
                layerHost:SetFrameLevel(host:GetFrameLevel() + 1)
                layerHost:Show()
            end
            local preview = EXUI:CreateStandardPreview(layerHost, {
                interactionMode = "world",
                worldAnchorMode = "semantic-root",
            })
            entity.previews[#entity.previews + 1] = preview
            entity.previewScales[preview] = layer.scale
            entity.layerTransforms[#entity.previews] = { scale = layer.scale, alpha = layer.alpha, transformed = layer.transformed }
            preview:Materialize(layer.definition, layer.model)
        end
    end
    ApplyPresentationPlacement(host, project.placement)
    host:Show()

    entity.stage = "list"
    local resolved, dropped, renderer = ListWorldElementSpecs(session, rootID, entity)
    if not resolved then FailEntityCreation(session, rootID, entity, "list-elements", dropped) end
    local overlays, overlayReason = ListWorldOverlaySpecs(session, rootID, entity, renderer)
    if not overlays then FailEntityCreation(session, rootID, entity, "list-overlays", overlayReason) end

    entity.stage = "inputs"
    WorldInput.BindInputs(session, rootID, entity, resolved, dropped, overlays)
    entity.stage = "overlay"
    SetPresentationOverlay(session, rootID, entity, state.overlayVisible)

    session.pending[rootID] = nil
    session.entities[rootID] = entity
    entity.stage = "ready"
    SetWorldElementSelection(session)
    return entity
end

local function ClockRenderer(entity)
    return entity.rendererActive and entity.renderer or entity.previews
end

local function ReportSessionClockFailure(session, detail)
    local message = "edit session clock failed: " .. session.provider.id .. ": " .. tostring(detail)
    if type(ExwindTools.LogError) == "function" then
        ExwindTools:LogError("EditModeClock[" .. session.provider.id .. "]", message)
    end
    print(message)
end

local function NotifySessionClock(session)
    if type(session.provider.OnSessionClockChanged) ~= "function" then session.clockNotifyPending = nil; return true end
    local clock = session.clock
    local ok, reason = pcall(session.provider.OnSessionClockChanged, clock.state, clock.at, clock.length)
    session.clockNotifyPending = not ok
    if not ok then ReportSessionClockFailure(session, reason); return false end
    return true
end

local function ReadSessionClockLength(session)
    local length, count = 0, 0
    for rootID in pairs(session.entities) do
        local ok, value = pcall(session.provider.GetSessionClockLength, rootID)
        if not ok then return nil, "GetSessionClockLength failed for " .. rootID .. ": " .. tostring(value) end
        if type(value) ~= "number" or value <= 0 or value == math.huge or value ~= value then
            return nil, "GetSessionClockLength requires a positive finite number for " .. rootID
        end
        length = math.max(length, value)
        count = count + 1
    end
    if count == 0 then return nil, "session clock has no visible roots" end
    return length
end

-- Providers expose only the next sample/condition transition. The playhead
-- may advance every frame, while presentation projection stays event-bound.
local function NextSessionClockBoundary(session, after)
    local nextAt
    for rootID in pairs(session.entities) do
        local ok, value = pcall(session.provider.GetSessionClockNextBoundary, rootID, after)
        if not ok then return nil, value end
        if value ~= nil then
            if type(value) ~= "number" or value ~= value or value == math.huge
                or value <= after then
                return nil, "GetSessionClockNextBoundary must return a later finite time for " .. rootID
            end
            if value <= session.clock.length and (not nextAt or value < nextAt) then nextAt = value end
        end
    end
    return nextAt
end

local function StopSessionClock(session, at, release)
    local clock = session.clock
    if not clock then return true end
    clock.state = "stopped"
    clock.at = at or clock.at or 0
    clock.startTime = nil
    if clock.frame then
        clock.frame:SetScript("OnUpdate", nil)
        clock.frame:Hide()
        if release then clock.frame:SetParent(nil); clock.frame = nil end
    end
    clock.nextBoundary = nil
    local restored, failure = true, nil
    if not release and type(session.provider.RestoreSessionSample) == "function" then
        for rootID, entity in pairs(session.restorePending or {}) do
            if session.entities[rootID] ~= entity then
                restored, failure = false, "sample entity release is incomplete"
            else
                local ok, accepted, reason = pcall(session.provider.RestoreSessionSample, rootID, ClockRenderer(entity))
                if not ok or accepted == false then
                    restored, failure = false, ok and reason or accepted
                elseif session.entities[rootID] == entity then
                    -- pcall success and the geometry operation's success are distinct.
                    local okGeometry, refreshed, refreshReason = pcall(RefreshEntityWorldGeometry, session, rootID, entity)
                    if not okGeometry or refreshed == false then
                        restored, failure = false, okGeometry and refreshReason or refreshed
                    elseif session.restorePending[rootID] == entity then
                        session.restorePending[rootID] = nil
                    end
                elseif session.restorePending[rootID] == entity then
                    restored, failure = false, "sample entity release is incomplete"
                end
            end
        end
    end
    SetWorldElementSelection(session)
    session.clockNotifyPending = not NotifySessionClock(session)
    if session.clockNotifyPending then
        restored, failure = false, failure or "OnSessionClockChanged failed"
    end
    return restored, failure
end

-- Automatic/error-cleanup callers have no synchronous receiver for a stop
-- failure. Keep pending recovery and surface that failure through the clock log.
function WorldInput.StopClockAndReport(session, at, release)
    local restored, reason = StopSessionClock(session, at, release)
    if not restored then ReportSessionClockFailure(session, reason) end
    return restored, reason
end

local function ApplySessionClockFrame(session, at)
    for rootID, entity in pairs(session.entities) do
        session.restorePending = session.restorePending or {}
        session.restorePending[rootID] = entity
        local ok, sample = pcall(session.provider.SampleAt, rootID, at)
        if not ok then return false, sample end
        local applied, accepted, reason = pcall(session.provider.ApplySessionSample,
            rootID, ClockRenderer(entity), sample, at)
        if not applied or accepted == false then return false, applied and reason or accepted end
        -- 样本帧切换 / 条件阈值会改变真实 frame 的几何：这是事件边界，不是逐帧轮询。
        -- 输入层随之重新枚举；枚举出错按时钟失败返回（调用方停钟并报告）。
        local okGeometry, refreshed, refreshReason = pcall(RefreshEntityWorldGeometry, session, rootID, entity)
        if not okGeometry or refreshed == false then return false, okGeometry and refreshReason or refreshed end
    end
    session.clock.at = at
    if not NotifySessionClock(session) then return false, "OnSessionClockChanged failed" end
    return true
end

-- 暂停定位（SeekEditSessionClock）把画面停在某一时刻的样本上；任何编辑输入或新的时钟请求之前
-- 先还原静态样本（走与“停播”相同的 RestoreSessionSample 路径）。返回 true，或 false + 原因。
function WorldInput.ClearSeekedSample(session)
    local clock = session.clock
    if not clock or clock.state == "playing" then return true end
    if not clock.seeked and not next(session.restorePending or {}) and not session.clockNotifyPending then return true end
    clock.seeked = nil
    return StopSessionClock(session, clock.at)
end

local function MaterializeSessionEntity(session, objectID)
    if session.provider.contract == "presentation-transaction" then
        CreatePresentationEntity(session, objectID)
        return
    end
    local module = session.entities[objectID]
    if not module then
        module = session.provider.BuildDeclaration(objectID)
        if type(module) ~= "table" then error("BuildDeclaration() must return a preview declaration", 3) end
        module.__editSessionProviderID = session.provider.id
        module.__editSessionObjectID = objectID
        -- Reuse the standard world renderer/lifecycle but never place session objects
        -- in state.modules: they are not global modules and have no saved visibility.
        session.entities[objectID] = module
    end
    MaterializeWorldPreview(module)
end

local function ApplySessionPresentation(session, suppressed)
    local called, accepted, reason = pcall(session.provider.SetPresentation, session.token, suppressed)
    if not called then
        return false, "SetPresentation failed for " .. session.provider.id .. ": " .. tostring(accepted)
    end
    -- Existing providers may return nil on success; only an explicit false
    -- rejects the presentation transaction.
    if accepted == false then
        return false, "SetPresentation rejected for " .. session.provider.id .. ": " .. tostring(reason)
    end
    return true
end

local function ReconcileEditSessionBody(providerID)
    local session = GetSession(providerID)
    -- 重入保护：provider 回调在对账过程中再次请求对账时直接返回。Core 不拦截错误，没有“出错后复位”的机会，
    -- 所以标记带着当前帧时间：对账中途抛错会把标记留下，但之后任何一帧里的新请求都会把它当作过期标记忽略。
    if session.reconciling and session.reconcileStamp == _G.GetTime() then return true end
    session.reconciling = true
    session.reconcileStamp = _G.GetTime()
    RunCommitResidue()
    -- 上一次创建途中被 provider 回调抛错打断的半成品先回收（ReleaseWorld、归还宿主）。
    if session.provider.contract == "presentation-transaction" then
        local released, reason = SweepPendingEntities(session)
        if not released then session.reconciling = false; return false, reason end
    end
    local objects = GetSessionObjectMap(session.provider)
    -- Entity creation below needs the exact Catalog name for its overlay title;
    -- keep the current snapshot before materializing any world object.
    session.objectMap = objects
    local function IsSupportedObject(objectID)
        local rootID = session.provider.contract == "presentation-transaction" and session.provider.RootOf(objectID) or objectID
        local object = type(rootID) == "string" and objects[rootID] or nil
        return object and object.supported
    end
    if session.focusID and not IsSupportedObject(session.focusID) then
        session.focusID = nil
    end
    for objectID in pairs(session.manualSelection) do
        if not IsSupportedObject(objectID) then session.manualSelection[objectID] = nil end
    end
    local target = BuildSessionTarget(session, objects)
    -- `target` is the complete Runtime-suppression set.  panel-only roots are
    -- intentionally absent from `materializedTarget`: the bounded settings
    -- preview owns their visible sample, while Core owns the one-way Runtime
    -- suppression.  Do not remove an object from Catalog or mark it
    -- unsupported to achieve this; doing that loses the suppression root.
    local materializedTarget = {}
    for rootID in pairs(target) do
        if not (session.panelOnlyRoots and session.panelOnlyRoots[rootID]) then
            materializedTarget[rootID] = true
        end
    end
    local stale = {}
    for objectID, module in pairs(session.entities) do
        if not materializedTarget[objectID] then
            stale[#stale + 1] = { id = objectID, module = module }
        end
    end
    for _, entry in ipairs(stale) do
        if session.provider.contract == "presentation-transaction" then
            local released, reason = DestroyPresentationEntity(session, entry.id)
            if not released then session.reconciling = false; return false, reason end
        else ReleaseWorldPreview(entry.module); session.entities[entry.id] = nil end
    end
    if session.worldSelection and not materializedTarget[session.worldSelection.rootID] then
        session.worldSelection = nil
    end
    for objectID in pairs(materializedTarget) do
        if session.provider.contract == "presentation-transaction" then
            -- A configuration refresh is an entirely new entity. StandardPreview
            -- is never reused after Unmount.
            if session.dirtyRoots and session.dirtyRoots[objectID] and session.entities[objectID] then
                local released, reason = DestroyPresentationEntity(session, objectID)
                if not released then session.reconciling = false; return false, reason end
            end
        end
        if not session.entities[objectID] then MaterializeSessionEntity(session, objectID) end
    end
    session.dirtyRoots = {}
    if session.provider.contract == "presentation-transaction" then SetWorldElementSelection(session) end
    session.reconciling = false
    if session.provider.contract == "presentation-transaction" then
        local suppressed = {}
        for rootID in pairs(target) do suppressed[rootID] = true end
        local applied, reason = ApplySessionPresentation(session, suppressed)
        if not applied then session.phase = "PRESENTATION_FAILED"; return false, reason end
        if session.clock then
            local length, lengthReason
            if session.clock.state ~= "playing" and next(session.entities) == nil then
                -- Empty stopped sessions can still reconcile after edit preparation.
                -- Retry outstanding restoration/notification before accepting them.
                local restored, restoreReason = WorldInput.ClearSeekedSample(session)
                if not restored then session.phase = "ACTIVE"; return false, restoreReason end
                length = session.clock.length
            else
                length, lengthReason = ReadSessionClockLength(session)
            end
            if not length then
                if session.clock.state == "playing" then WorldInput.StopClockAndReport(session, session.clock.at) end
                session.phase = "ACTIVE"
                return false, lengthReason
            end
            session.clock.length = length
            if session.clock.state ~= "playing" then
                session.clock.at = math.min(session.clock.at, length)
            end
            if session.clock.state == "playing" then
                if session.clock.at >= length then
                    local restored, restoreReason = StopSessionClock(session, length)
                    session.phase = "ACTIVE"
                    if not restored then return false, restoreReason end
                    return true, target
                end
                local nextAt, boundaryReason = NextSessionClockBoundary(session, session.clock.at)
                if boundaryReason then
                    WorldInput.StopClockAndReport(session, session.clock.at)
                    session.phase = "ACTIVE"
                    return false, boundaryReason
                end
                session.clock.nextBoundary = nextAt
            end
        end
        if session.clock and session.clock.state == "playing" then
            local sampled, sampleReason = ApplySessionClockFrame(session, session.clock.at)
            if not sampled then
                WorldInput.StopClockAndReport(session, session.clock.at)
                session.phase = "ACTIVE"
                return false, "session clock sample failed: " .. tostring(sampleReason)
            end
        end
        -- 暂停定位（SeekEditSessionClock）：新建的实体也要显示定位的那一刻。
        if session.clock and session.clock.state ~= "playing" and session.clock.seeked then
            local sampled, sampleReason = ApplySessionClockFrame(session, session.clock.at)
            if not sampled then
                session.clock.seeked = nil
                session.phase = "ACTIVE"
                return false, "session clock sample failed: " .. tostring(sampleReason)
            end
        end
    end
    session.phase = "ACTIVE"
    return true, target
end

-- 对账出错时错误直接抛给游戏错误处理器（Core 不拦截错误）：重入标记靠帧时间自愈（见 ReconcileEditSessionBody），
-- 创建途中的半成品留在 session.pending，下一次对账回收。
local function ReconcileEditSession(providerID)
    return ReconcileEditSessionBody(providerID)
end
WorldInput.Reconcile = ReconcileEditSession

function EXUI:RegisterEditSessionProvider(provider)
    if type(provider) ~= "table" then error("RegisterEditSessionProvider: provider must be table", 2) end
    if type(provider.id) ~= "string" or provider.id == "" then error("RegisterEditSessionProvider: id must be non-empty string", 2) end
    if type(provider.name) ~= "string" or provider.name == "" then error("RegisterEditSessionProvider: name must be non-empty string", 2) end
    if type(provider.addon) ~= "string" or not OVERLAY_PROFILES[provider.addon] then
        error("RegisterEditSessionProvider: addon must have a Core overlay profile", 2)
    end
    if provider.contract ~= "presentation-transaction" and type(provider.GetObjects) ~= "function" then
        error("RegisterEditSessionProvider: GetObjects must be function", 2)
    end
    if provider.contract == "presentation-transaction" then
        if type(provider.Catalog) ~= "function" or type(provider.RootOf) ~= "function" or type(provider.Project) ~= "function"
            or type(provider.Commit) ~= "function" or type(provider.SetPresentation) ~= "function" then
            error("RegisterEditSessionProvider: presentation-transaction requires Catalog, RootOf, Project, Commit, SetPresentation", 2)
        end
        -- 宿主不再承担任何命中：没有 ListWorldElements 的 provider 无法选中 / 拖动，所以它是必需的。
        if type(provider.ListWorldElements) ~= "function" then
            error("RegisterEditSessionProvider: presentation-transaction requires ListWorldElements", 2)
        end
        if provider.OnSelect ~= nil and type(provider.OnSelect) ~= "function" then
            error("RegisterEditSessionProvider: OnSelect must be function", 2)
        end
        if provider.OnCommitFailed ~= nil and type(provider.OnCommitFailed) ~= "function" then
            error("RegisterEditSessionProvider: OnCommitFailed must be function", 2)
        end
        -- 画面直编的可选回调（见“画面直编”一节）：声明了就必须是函数，否则注册时就报错，不会拖到鼠标按下才炸。
        for _, callbackName in ipairs({ "GetWorldPressMode", "PreviewWorldElement", "PreviewWorldElementLive",
            "ListWorldOverlays", "PreviewWorldOverlay", "OnMarqueeSelect", "IsWorldInputBlocked",
            "BeforeWorldInput" }) do
            if provider[callbackName] ~= nil and type(provider[callbackName]) ~= "function" then
                error("RegisterEditSessionProvider: " .. callbackName .. " must be function", 2)
            end
        end
        for _, callbackName in ipairs({ "GetSessionClockLength", "SampleAt", "ApplySessionSample",
            "RestoreSessionSample", "OnSessionClockChanged" }) do
            if provider[callbackName] ~= nil and type(provider[callbackName]) ~= "function" then
                error("RegisterEditSessionProvider: " .. callbackName .. " must be function", 2)
            end
        end
        -- This is the provider-session form of the existing RenderWorld /
        -- ReleaseWorld / GetWorldBounds transaction.  Partial declarations are
        -- rejected so a renderer provider can never silently fall back to a
        -- StandardPreview layer while editing is active.
        local declaresWorldRenderer = provider.RenderWorld ~= nil or provider.ReleaseWorld ~= nil
            or provider.GetWorldBounds ~= nil or provider.UsesWorldRenderer ~= nil
        if declaresWorldRenderer and (not HasPresentationWorldRenderer(provider) or type(provider.UsesWorldRenderer) ~= "function") then
            error("RegisterEditSessionProvider: presentation renderer requires UsesWorldRenderer, RenderWorld, ReleaseWorld, GetWorldBounds", 2)
        end
    elseif type(provider.BuildDeclaration) ~= "function" then
        error("RegisterEditSessionProvider: legacy providers require BuildDeclaration", 2)
    end
    if state.editSessionProviders[provider.id] then error("RegisterEditSessionProvider: duplicate provider " .. provider.id, 2) end
    state.editSessionProviders[provider.id] = provider
end

-- Combat can begin between mouse-down and mouse-up. Drop every transient
-- position immediately; the provider's editor owns closing its session.
local presentationCombatGate = CreateFrame("Frame")
presentationCombatGate:RegisterEvent("PLAYER_REGEN_DISABLED")
presentationCombatGate:RegisterEvent("PLAYER_REGEN_ENABLED")
presentationCombatGate:SetScript("OnEvent", function(_, event)
    for _, session in pairs(state.editSessions) do
        if session.provider.contract == "presentation-transaction" then
            if event == "PLAYER_REGEN_DISABLED" then
                if session.clock and session.clock.state == "playing" then
                    local restored, reason = StopSessionClock(session, session.clock.at)
                    if not restored then ReportSessionClockFailure(session, reason) end
                end
                if state.pointer and state.pointer.session == session then CancelPointer() end
                if state.press and state.press.session == session then state.press = nil end
                for _, entity in pairs(session.entities) do
                    for _, entry in pairs(entity.worldElements or {}) do
                        WorldInput.HideVisuals(entry)
                    end
                    for _, widget in ipairs(entity.worldOverlays or {}) do widget.Apply(nil, false) end
                end
            else
                SetWorldElementSelection(session)
            end
        end
    end
end)

function EXUI:BeginEditSession(providerID)
    local provider = GetSessionProvider(providerID)
    -- UnifiedPanel can call a provider's Show route more than once without an
    -- intervening OnHide.  Opening the same provider session is idempotent:
    -- retain its focus/manual set rather than throwing or resetting choices.
    local existing = state.editSessions[providerID]
    if existing then
        if existing.phase == "CLOSE_FAILED" then
            return false, "previous edit session close failed for " .. providerID
        end
        -- OPENING：上一次打开在对账中途被 provider 回调的错误打断（错误已交给游戏错误处理器），重新对账。
        if existing.phase == "PRESENTATION_FAILED" or existing.phase == "OPENING" then
            local applied, reason = ReconcileEditSession(providerID)
            if not applied then return false, reason end
        end
        return true, existing
    end
    local session = {
        provider = provider, phase = "OPENING", token = {}, focusID = nil,
        manualSelection = {}, entities = {}, objectMap = {}, dirtyRoots = {},
        pending = {}, worldElementFilters = {},
        panelOnlyRoots = {}, panelOnlyRootsByOwner = {},
    }
    state.editSessions[providerID] = session
    local objects = GetSessionObjectMap(provider)
    for objectID, object in pairs(objects) do
        if object.supported and object.loadMatched then session.manualSelection[objectID] = true end
    end
    local applied, reason = ReconcileEditSession(providerID)
    if not applied then return false, reason end
    return true, session
end

function EXUI:EndEditSession(providerID)
    local session = state.editSessions[providerID]
    if not session then return false end
    session.phase = "CLOSING"
    -- 进行中的指针手势（含不属于任何根的框选）随会话取消：停止手势、卸下驱动 frame、隐藏矩形。
    if state.pointer and state.pointer.session == session then CancelPointer() end
    if state.press and state.press.session == session then state.press = nil end
    RunCommitResidue()
    WorldInput.StopClockAndReport(session, nil, true)
    -- 创建途中被打断的半成品也在这里回收（ReleaseWorld、归还宿主）。
    if session.provider.contract == "presentation-transaction" then
        local released, reason = SweepPendingEntities(session)
        if not released then session.phase = "CLOSE_FAILED"; return false, reason end
    end
    local entityIDs = {}
    for objectID in pairs(session.entities) do entityIDs[#entityIDs + 1] = objectID end
    for _, objectID in ipairs(entityIDs) do
        local module = session.entities[objectID]
        if session.provider.contract == "presentation-transaction" then
            local released, reason = DestroyPresentationEntity(session, objectID)
            if not released then session.phase = "CLOSE_FAILED"; return false, reason end
        else ReleaseWorldPreview(module) end
    end
    if session.provider.contract == "presentation-transaction" then
        local released, reason = ApplySessionPresentation(session, {})
        if not released then session.phase = "CLOSE_FAILED"; return false, reason end
    end
    state.editSessions[providerID] = nil
    return true
end

function EXUI:GetSessionClock(providerID)
    local session = state.editSessions[providerID]
    if not session or not session.clock then return nil end
    local clock = session.clock
    local length = ReadSessionClockLength(session)
    if length and clock.state ~= "playing" then
        clock.length = length
        clock.at = math.min(clock.at, length)
    end
    return { state = clock.state, at = clock.at, length = clock.length }
end

function EXUI:SetSessionClock(providerID, request)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" or session.phase ~= "ACTIVE" then
        return false, "presentation edit session is not active"
    end
    if type(request) ~= "table" or (request.state ~= "playing" and request.state ~= "stopped") then
        return false, "session clock state must be playing or stopped"
    end
    local provider = session.provider
    if type(provider.GetSessionClockLength) ~= "function" or type(provider.SampleAt) ~= "function"
        or type(provider.ApplySessionSample) ~= "function" or type(provider.RestoreSessionSample) ~= "function" then
        return false, "provider has no session clock sample contract"
    end
    local length, lengthReason
    if request.state == "stopped" and next(session.entities) == nil then
        -- Stopping is also the edit-preparation barrier for an empty catalog.
        -- Retain an existing clock's range without inventing a playable sample;
        -- pending restoration/notification still runs through the normal path.
        length = session.clock and session.clock.length or 0
    else
        length, lengthReason = ReadSessionClockLength(session)
        if not length then return false, lengthReason end
    end
    -- 暂停定位显示的是某一时刻的样本：新的时钟请求先还原静态样本。
    local restored, restoreReason = WorldInput.ClearSeekedSample(session)
    if not restored then return false, restoreReason end
    local previous = session.clock
    local from = request.from
    if from == nil then from = previous and math.min(previous.at, length) or 0 end
    if type(from) ~= "number" or from < 0 or from > length or from ~= from then
        return false, "session clock from must be within its length"
    end
    if previous and previous.state == "playing" then
        local stopped, stopReason = StopSessionClock(session, from)
        if not stopped then return false, stopReason end
    end
    local clock = previous or { state = "stopped", at = 0 }
    session.clock = clock
    clock.length, clock.at = length, from
    if request.state == "stopped" or from == length then
        clock.state = "stopped"
        SetWorldElementSelection(session)
        if not NotifySessionClock(session) then return false, "OnSessionClockChanged failed" end
        return true, { state = clock.state, at = clock.at, length = clock.length }
    end
    if type(provider.GetSessionClockNextBoundary) ~= "function" then
        return false, "provider has no GetSessionClockNextBoundary contract"
    end
    if state.pointer and state.pointer.session == session then CancelPointer() end
    clock.state = "playing"
    clock.from, clock.startTime = from, _G.GetTime()
    SetWorldElementSelection(session)
    local applied, reason = ApplySessionClockFrame(session, from)
    if not applied then
        WorldInput.StopClockAndReport(session, from)
        return false, "session clock sample failed: " .. tostring(reason)
    end
    if state.editSessions[providerID] ~= session or clock.state ~= "playing" then
        return false, "session clock was closed during sample"
    end
    local nextAt, boundaryReason = NextSessionClockBoundary(session, from)
    if boundaryReason then
        WorldInput.StopClockAndReport(session, from)
        return false, boundaryReason
    end
    clock.nextBoundary = nextAt
    if not clock.frame then clock.frame = CreateFrame("Frame", nil, UIParent) end
    clock.frame:SetScript("OnUpdate", function()
        if state.editSessions[providerID] ~= session or session.phase ~= "ACTIVE"
            or (_G.InCombatLockdown and _G.InCombatLockdown()) then
            WorldInput.StopClockAndReport(session, clock.at, state.editSessions[providerID] ~= session)
            return
        end
        local at = math.min(clock.length, clock.from + _G.GetTime() - clock.startTime)
        while clock.nextBoundary and clock.nextBoundary <= at do
            local boundary = clock.nextBoundary
            local okay, sampleReason = ApplySessionClockFrame(session, boundary)
            if not okay then
                ReportSessionClockFailure(session, sampleReason)
                WorldInput.StopClockAndReport(session, at)
                return
            end
            local nextBoundary, nextReason = NextSessionClockBoundary(session, boundary)
            if nextReason then
                ReportSessionClockFailure(session, nextReason)
                WorldInput.StopClockAndReport(session, at)
                return
            end
            clock.nextBoundary = nextBoundary
        end
        if state.editSessions[providerID] ~= session or session.phase ~= "ACTIVE" or clock.state ~= "playing" then return end
        clock.at = at
        if not NotifySessionClock(session) then WorldInput.StopClockAndReport(session, at); return end
        if at >= clock.length then
            local restored, restoreReason = StopSessionClock(session, clock.length)
            if not restored then ReportSessionClockFailure(session, restoreReason) end
        end
    end)
    clock.frame:Show()
    return true, { state = clock.state, at = clock.at, length = clock.length }
end

function EXUI:SetEditSessionFocus(providerID, objectID)
    local session = state.editSessions[providerID]
    if not session then return false, L["编辑会话未开启"] end
    if objectID ~= nil and type(objectID) ~= "string" then error("SetEditSessionFocus: objectID must be string or nil", 2) end
    if objectID then
        local objects = GetSessionObjectMap(session.provider)
        local rootID = session.provider.contract == "presentation-transaction" and session.provider.RootOf(objectID) or objectID
        local object = objects[rootID]
        if type(rootID) ~= "string" or not object then return false, L["对象已不存在或目录已刷新"] end
        if not object.supported then return false, tostring(object.reason or L["该对象暂不支持预览"]) end
    end
    session.focusID = objectID
    return ReconcileEditSession(providerID)
end

function EXUI:SetEditSessionManualSelected(providerID, objectID, selected)
    if type(objectID) ~= "string" or objectID == "" then error("SetEditSessionManualSelected: objectID must be non-empty string", 2) end
    if type(selected) ~= "boolean" then error("SetEditSessionManualSelected: selected must be boolean", 2) end
    local session = state.editSessions[providerID]
    if not session then return false, L["编辑会话未开启"] end
    local objects = GetSessionObjectMap(session.provider)
    local rootID = session.provider.contract == "presentation-transaction" and session.provider.RootOf(objectID) or objectID
    local object = type(rootID) == "string" and objects[rootID] or nil
    if not object then return false, L["对象已不存在或目录已刷新"] end
    if selected and not object.supported then return false, tostring(object.reason or L["该对象暂不支持预览"]) end
    session.manualSelection[objectID] = selected or nil
    return ReconcileEditSession(providerID)
end

-- An edit root may contain several independently shown members. The provider
-- owns their visual hosts; Core owns the separate input/selection overlays.
-- This session-only predicate gates those overlays by their declared elementID.
function EXUI:SetEditSessionWorldElementFilter(providerID, rootID, filter)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" then
        return false, "presentation edit session is not open"
    end
    if type(rootID) ~= "string" or rootID == "" or (filter ~= nil and type(filter) ~= "function") then
        error("SetEditSessionWorldElementFilter requires rootID and function or nil", 2)
    end
    local root = GetSessionObjectMap(session.provider)[rootID]
    if not root or session.provider.RootOf(rootID) ~= rootID then
        return false, "edit session root is unavailable"
    end
    local entity = session.entities[rootID]
    -- 先对现有元素全部评估一遍再改任何状态：谓词抛错（或返回非 boolean）直接传出，会话状态保持原样。
    local visibleByID = {}
    for elementID in pairs(entity and entity.worldElements or {}) do
        visibleByID[elementID] = EvaluateWorldElementFilter(filter, rootID, elementID)
    end
    session.worldElementFilters[rootID] = filter
    if entity then
        for elementID, entry in pairs(entity.worldElements or {}) do
            if not visibleByID[elementID] then
                if state.pointer and state.pointer.entry == entry then CancelPointer() end
                if session.worldSelection and session.worldSelection.rootID == rootID
                    and session.worldSelection.elementID == elementID then
                    session.worldSelection.elementID = nil
                end
            end
            entry.hitbox:SetShown(visibleByID[elementID])
        end
        SetWorldElementSelection(session)
    end
    return true
end

-- 样本几何变化后让 Core 重新枚举命中矩形与群组外框并原地更新（命中框、选框、手柄、描边、尺寸标签）。
-- 会话时钟的样本帧切换 / 条件阈值 / 停播恢复已由 Core 自己刷新；provider 在其它时机改变了
-- 真实 frame 的几何（例如成员预览显隐、条件预览切换）后调用本函数。rootID 为 nil 时刷新全部根。
-- 返回 true，或 false + 原因；该根正被指针手势占用时拒绝。provider.ListWorldElements 报错直接抛出。
-- Placement-only commits never enter Reproject's structural Reconcile path.
-- All provider reads and state refusals precede the first host mutation.
function WorldInput.ApplyStandardLayers(session, rootID, entity, layers)
    if entity.rendererActive or not entity.standardLayers or #layers ~= #entity.previews then
        return false, "WORLD_STRUCTURE_CHANGED"
    end
    for index, layer in ipairs(layers) do
        local original = entity.standardLayers[index]
        if not original or original.transformed ~= layer.transformed then return false, "WORLD_STRUCTURE_CHANGED" end
    end
    -- Register before touching any layer: a later Materialize failure must
    -- restore the entire root, not just the last successfully updated preview.
    session.restorePending = session.restorePending or {}
    session.restorePending[rootID] = entity
    for index, layer in ipairs(layers) do
        local preview = entity.previews[index]
        if layer.transformed then
            preview.host:SetScale(layer.scale)
            preview.host:SetAlpha(layer.alpha)
        end
        entity.previewScales[preview] = layer.scale
        if not preview:ReapplyCurrentMaterial(layer.definition, layer.model) then
            preview:Materialize(layer.definition, layer.model)
        end
    end
    return true
end

-- Provider supplies complete ordinary sample layers in root coordinates. It
-- never reads a preview's private model or repeats outerTransform conversion.
function EXUI:ApplyEditSessionStandardSample(providerID, rootID, layers)
    local session = state.editSessions[providerID]
    local entity = session and session.entities[rootID]
    if not session or session.provider.contract ~= "presentation-transaction" or not entity then
        return false, "WORLD_SAMPLE_UNAVAILABLE"
    end
    if type(layers) ~= "table" then error("standard sample layers must be a dense array", 2) end
    local count = 0
    for index in ipairs(layers) do count = index end
    for key in pairs(layers) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then error("standard sample layers must be dense", 2) end
    end
    if count ~= #entity.previews then return false, "WORLD_STRUCTURE_CHANGED" end
    local prepared = WorldInput.PreparePresentationLayers(layers)
    return WorldInput.ApplyStandardLayers(session, rootID, entity, prepared)
end

function EXUI:RestoreEditSessionStandardSample(providerID, rootID)
    local session = state.editSessions[providerID]
    local entity = session and session.entities[rootID]
    if not session or session.provider.contract ~= "presentation-transaction" or not entity or not entity.standardLayers then
        return false, "WORLD_SAMPLE_UNAVAILABLE"
    end
    -- These are already-normalized immutable creation snapshots: do not divide
    -- positions by scale a second time. StopSessionClock clears pending only
    -- after its subsequent input-geometry refresh succeeds.
    return WorldInput.ApplyStandardLayers(session, rootID, entity, entity.standardLayers)
end

function EXUI:ReapplyEditSessionWorldPlacement(providerID, rootIDs)
    if type(providerID) ~= "string" or providerID == "" or type(rootIDs) ~= "table" or #rootIDs == 0 then
        error("ReapplyEditSessionWorldPlacement requires providerID and a non-empty rootIDs array", 2)
    end
    local seen, count = {}, 0
    for index, id in ipairs(rootIDs) do
        if type(id) ~= "string" or id == "" or seen[id] then error("rootIDs must contain unique non-empty strings", 2) end
        seen[id] = index
        count = index
    end
    for key in pairs(rootIDs) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then error("rootIDs must be dense", 2) end
    end
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" then return false, "presentation edit session is not open" end
    if session.phase ~= "ACTIVE" then return false, "presentation edit session is not active" end
    if not SelectionAllowed() then return false, "cannot reapply world placement in combat" end
    if state.pointer then return false, "world pointer gesture in progress" end
    if state.commitResidue then return false, "world gesture cleanup is pending" end
    if (session.clock and (session.clock.state == "playing" or session.clock.seeked))
        or next(session.restorePending or {}) or session.clockNotifyPending then
        return false, "session sample must be restored before reapplying placement"
    end
    local plans, points = {}, { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    for _, id in ipairs(rootIDs) do
        local entity = session.entities[id]
        if not entity then return false, "edit session root is unavailable" end
        if session.dirtyRoots[id] then return false, "WORLD_STRUCTURE_CHANGED" end
        local project = session.provider.Project(id)
        if type(project) ~= "table" or type(project.placement) ~= "table" then return false, "WORLD_STRUCTURE_CHANGED" end
        if SelectsPresentationWorldRenderer(session.provider, id, project) ~= (entity.rendererActive == true) then
            return false, "WORLD_STRUCTURE_CHANGED"
        end
        if not entity.rendererActive then
            if type(project.layers) ~= "table" or #project.layers ~= #entity.previews then return false, "WORLD_STRUCTURE_CHANGED" end
            local layers = WorldInput.PreparePresentationLayers(project.layers)
            for index, layer in ipairs(layers) do
                local previous = entity.layerTransforms[index]
                if not previous or previous.scale ~= layer.scale or previous.alpha ~= layer.alpha
                    or previous.transformed ~= layer.transformed then return false, "WORLD_STRUCTURE_CHANGED" end
            end
        end
        local source, placement = project.placement, {}
        placement.point = source.point or "CENTER"
        placement.relativePoint = source.relativePoint or placement.point
        if not points[placement.point] or not points[placement.relativePoint] then error("invalid placement anchor", 2) end
        for _, key in ipairs({ "x", "y", "width", "height" }) do
            local value = source[key]
            if value == nil then value = (key == "x" or key == "y") and 0 or 1 end
            if (issecretvalue and issecretvalue(value)) or not IsFiniteNumber(value)
                or ((key == "width" or key == "height") and value <= 0) then error("invalid placement " .. key, 2) end
            placement[key] = value
        end
        local plan = { id = id, entity = entity, placement = placement }
        if entity.worldOverlayBundle then
            local resolved, dropped, renderer = ListWorldElementSpecs(session, id, entity)
            if not resolved then error(WorldInput.StageError(session, id, "placement-elements", dropped), 0) end
            local overlays, reason = ListWorldOverlaySpecs(session, id, entity, renderer)
            if not overlays then error(WorldInput.StageError(session, id, "placement-overlays", reason), 0) end
            local present = {}
            for _, item in ipairs(resolved) do
                local entry = entity.worldElements[item.spec.elementID]
                if not entry or entry.anchorFrame ~= item.anchorFrame or entry.previewFrame ~= item.previewFrame then
                    return false, "WORLD_STRUCTURE_CHANGED"
                end
                present[item.spec.elementID] = true
            end
            for elementID in pairs(entity.worldElements) do if not present[elementID] then return false, "WORLD_STRUCTURE_CHANGED" end end
            if #overlays ~= #(entity.worldOverlays or {}) then return false, "WORLD_STRUCTURE_CHANGED" end
            for _, spec in ipairs(overlays) do
                local old = entity.worldOverlayByID[spec.id]
                if not old or OverlayPoolKey(old.spec) ~= OverlayPoolKey(spec) then
                    return false, "WORLD_STRUCTURE_CHANGED"
                end
            end
            plan.resolved, plan.dropped, plan.overlays = resolved, dropped, overlays
        end
        plans[#plans + 1] = plan
    end
    -- Reentrant providers may invalidate a prior root; check the entire batch again.
    if state.editSessions[providerID] ~= session or session.phase ~= "ACTIVE" or state.pointer or not SelectionAllowed() then
        return false, "presentation edit session changed during placement preparation"
    end
    if state.commitResidue or (session.clock and (session.clock.state == "playing" or session.clock.seeked))
        or next(session.restorePending or {}) or session.clockNotifyPending then
        return false, "session sample or gesture changed during placement preparation"
    end
    for _, plan in ipairs(plans) do
        if session.entities[plan.id] ~= plan.entity or session.dirtyRoots[plan.id] then return false, "WORLD_STRUCTURE_CHANGED" end
    end
    for _, plan in ipairs(plans) do
        plan.entity.placement = plan.placement
        ApplyPresentationPlacement(plan.entity.host, plan.placement)
    end
    for _, plan in ipairs(plans) do
        if plan.resolved then
            for _, item in ipairs(plan.resolved) do
                BindWorldElementEntry(session, plan.id, plan.entity, plan.entity.worldElements[item.spec.elementID], item, true)
            end
            for _, spec in ipairs(plan.overlays) do plan.entity.worldOverlayByID[spec.id].UpdateSpec(spec) end
            WorldInput.ReportDropped(session, plan.id, plan.entity, plan.dropped)
        end
    end
    SetWorldElementSelection(session)
    return true
end

function EXUI:RefreshEditSessionWorldGeometry(providerID, rootID)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" then
        return false, "presentation edit session is not open"
    end
    if session.phase ~= "ACTIVE" then return false, "presentation edit session is not active" end
    if rootID ~= nil and (type(rootID) ~= "string" or rootID == "") then
        error("RefreshEditSessionWorldGeometry: rootID must be a non-empty string or nil", 2)
    end
    if rootID ~= nil then
        local entity = session.entities[rootID]
        if not entity then return false, "edit session root is unavailable" end
        return RefreshEntityWorldGeometry(session, rootID, entity)
    end
    local rootIDs = {}
    for id in pairs(session.entities) do rootIDs[#rootIDs + 1] = id end
    for _, id in ipairs(rootIDs) do
        local entity = session.entities[id]
        if entity then
            local refreshed, reason = RefreshEntityWorldGeometry(session, id, entity)
            if not refreshed then return false, reason end
        end
    end
    return true
end

-- 停播（会话时钟 stopped）时把画面定位到 seconds 秒并显示该时刻的状态：走 provider 现有的
-- SampleAt / ApplySessionSample 路径，Core 随后重新枚举几何。不改变“停播 = 回到起点”的 StopSessionClock 语义：
-- 之后任何编辑输入或新的时钟请求都会先 RestoreSessionSample 还原静态样本。rootID 为 nil 时作用于全部根。
-- 返回 true, { state, at, length }，或 false + 原因（会话未开 / 时钟正在播放 / 手势进行中 / 战斗中 /
-- seconds 越界 / provider 拒绝）。时钟不在播放即视为可定位（Core 没有单独的“暂停”状态，暂停 = stopped）。
function EXUI:SeekEditSessionClock(providerID, rootID, seconds)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" or session.phase ~= "ACTIVE" then
        return false, "presentation edit session is not active"
    end
    if rootID ~= nil and (type(rootID) ~= "string" or rootID == "") then
        error("SeekEditSessionClock: rootID must be a non-empty string or nil", 2)
    end
    if not IsFiniteNumber(seconds) then error("SeekEditSessionClock: seconds must be a finite number", 2) end
    local provider = session.provider
    if type(provider.GetSessionClockLength) ~= "function" or type(provider.SampleAt) ~= "function"
        or type(provider.ApplySessionSample) ~= "function" or type(provider.RestoreSessionSample) ~= "function" then
        return false, "provider has no session clock sample contract"
    end
    if session.clock and session.clock.state == "playing" then return false, "session clock is playing" end
    if not SelectionAllowed() then return false, "cannot seek in combat" end
    if state.pointer and state.pointer.session == session then return false, "world pointer gesture in progress" end
    local length, lengthReason = ReadSessionClockLength(session)
    if not length then return false, lengthReason end
    if seconds < 0 or seconds > length then return false, "seconds must be within the session clock length" end
    local targets = {}
    if rootID ~= nil then
        if not session.entities[rootID] then return false, "edit session root is unavailable" end
        targets[1] = rootID
    else
        for id in pairs(session.entities) do targets[#targets + 1] = id end
    end
    local restored, restoreReason = WorldInput.ClearSeekedSample(session)
    if not restored then return false, restoreReason end
    local clock = session.clock
    if not clock then
        clock = { state = "stopped", at = 0 }
        session.clock = clock
    end
    -- 先登记“已定位”，即便中途某个根被 provider 拒绝，已套用的根也能在之后被还原。
    clock.length, clock.at, clock.state, clock.seeked = length, seconds, "stopped", true
    for _, id in ipairs(targets) do
        local entity = session.entities[id]
        if entity then
            session.restorePending = session.restorePending or {}
            session.restorePending[id] = entity
            local sample = provider.SampleAt(id, seconds)
            local accepted, reason = provider.ApplySessionSample(id, ClockRenderer(entity), sample, seconds)
            if accepted == false then
                return false, "ApplySessionSample rejected for " .. id .. ": " .. tostring(reason)
            end
            -- 样本改变了真实 frame 的几何：这是事件边界，输入层随之重新枚举。
            local refreshed, refreshReason = RefreshEntityWorldGeometry(session, id, entity)
            if refreshed == false then return false, refreshReason end
        end
    end
    SetWorldElementSelection(session)
    if not NotifySessionClock(session) then return false, "OnSessionClockChanged failed" end
    return true, { state = clock.state, at = clock.at, length = clock.length }
end

-- 诊断：把会话里每个根的实体状态、元素数、命中框、被丢弃的元素及原因整理成纯数据返回，
-- 不要求读私有表。游戏里用一条命令查看：/dump ExwindTools.UI:GetEditSessionDiagnostics("exaura")
function WorldInput.DescribeEntity(entity)
    local host = entity.host
    local hostWidth, hostHeight
    if host then hostWidth, hostHeight = host:GetSize() end
    local info = { state = entity.emptyRoot and "empty" or entity.stage or "ready",
        stage = entity.stage, rendererActive = entity.rendererActive == true,
        hostShown = host and host:IsShown() or false, hostVisible = host and host:IsVisible() or false,
        hostScale = host and host:GetEffectiveScale() or nil, hostAlpha = host and host:GetEffectiveAlpha() or nil,
        hostStrata = host and host:GetFrameStrata() or nil, hostLevel = host and host:GetFrameLevel() or nil,
        hostWidth = hostWidth, hostHeight = hostHeight,
        elementCount = 0, overlayCount = #(entity.worldOverlays or {}),
        hitboxes = {}, dropped = {} }
    for elementID, entry in pairs(entity.worldElements or {}) do
        local hitbox = entry.hitbox
        local width, height = hitbox:GetSize()
        info.hitboxes[#info.hitboxes + 1] = { elementID = elementID,
            kind = entry.anchorFrame and "frame" or "rect",
            width = width, height = height,
            shown = hitbox:IsShown(), visible = hitbox:IsVisible(), mouse = hitbox:IsMouseEnabled(),
            strata = hitbox:GetFrameStrata(), level = hitbox:GetFrameLevel(),
            selected = entry.selected == true, priority = entry.spec and entry.spec.priority or "body",
            label = entry.spec and entry.spec.label or nil,
            movable = entry.spec and entry.spec.movable == true or false,
            resizable = entry.spec and entry.spec.resizable == true or false }
        info.elementCount = info.elementCount + 1
    end
    table.sort(info.hitboxes, function(a, b) return a.elementID < b.elementID end)
    for elementID, reason in pairs(entity.droppedElements or {}) do
        info.dropped[#info.dropped + 1] = { elementID = elementID, reason = reason }
    end
    table.sort(info.dropped, function(a, b) return a.elementID < b.elementID end)
    return info
end

function EXUI:GetEditSessionDiagnostics(providerID)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" then
        return nil, "presentation edit session is not open for provider " .. tostring(providerID)
    end
    local result = { providerID = providerID, phase = session.phase, reconciling = session.reconciling == true,
        inCombat = (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false,
        worldVisible = session.worldVisible == true, roots = {}, pending = {} }
    local clock = session.clock
    if clock then
        result.clock = { state = clock.state, at = clock.at, length = clock.length, seeked = clock.seeked == true }
    end
    local selected = session.worldSelection
    if selected then
        result.selection = { rootID = selected.rootID, elementID = selected.elementID, ownerID = selected.ownerID }
    end
    local selectionRoot = state.selectionRoots[providerID]
    if selectionRoot then
        result.selectionRoot = { shown = selectionRoot:IsShown(), strata = selectionRoot:GetFrameStrata(),
            level = selectionRoot:GetFrameLevel(), scale = selectionRoot:GetEffectiveScale(),
            alpha = selectionRoot:GetEffectiveAlpha(), uiParentScale = UIParent:GetEffectiveScale() }
    end
    for rootID, entity in pairs(session.entities) do result.roots[rootID] = WorldInput.DescribeEntity(entity) end
    for rootID, entity in pairs(session.pending) do
        result.pending[rootID] = { stage = entity.stage, rendererActive = entity.rendererActive == true }
    end
    return result
end

-- [WEB-REQ 10/12/35/60] 编辑器把“当前选中的画面元素 / 群组”告诉 Core，只改视觉，不触发 provider.OnSelect。
-- selection = nil（点空白：清除全部选中框）或 { rootID, elementID = 元素 ID 或 nil, ownerID = 被选中的群组对象 ID 或 nil }。
-- 元素 ID 不在该根里时只保留 rootID / ownerID（选中的是群组或元素已被隐藏）。
function EXUI:SetEditSessionWorldSelection(providerID, selection)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" then
        return false, "presentation edit session is not open"
    end
    if selection ~= nil and (type(selection) ~= "table" or type(selection.rootID) ~= "string") then
        error("SetEditSessionWorldSelection requires nil or { rootID, elementID, ownerID }", 2)
    end
    if selection == nil then
        session.worldSelection = nil
    else
        local entity = session.entities[selection.rootID]
        local elementID = selection.elementID
        if elementID ~= nil and not (entity and entity.worldElements and entity.worldElements[elementID]) then
            elementID = nil
        end
        session.worldSelection = { rootID = selection.rootID, elementID = elementID, ownerID = selection.ownerID }
    end
    SetWorldElementSelection(session)
    return true
end

-- [WEB-REQ 60] 选中资料夹时：outlines = { { rootID, elementID }, ... } 给每个成员各自描边（不画整块外框）；
-- target 是不透明的容器标识（如 "folder:<id>"），拖动任一描边成员时原样放进 rootMoved 的 intent.outlineTarget，
-- 同时 Core 让所有描边成员的宿主一起动。outlines = nil 清除。
function EXUI:SetEditSessionWorldOutlines(providerID, outlines, target)
    local session = state.editSessions[providerID]
    if not session or session.provider.contract ~= "presentation-transaction" then
        return false, "presentation edit session is not open"
    end
    if outlines ~= nil and type(outlines) ~= "table" then
        error("SetEditSessionWorldOutlines requires an array or nil", 2)
    end
    if target ~= nil and type(target) ~= "string" then
        error("SetEditSessionWorldOutlines target must be a string or nil", 2)
    end
    session.worldOutlineSet, session.worldOutlines = nil, nil
    if outlines ~= nil or target ~= nil then
        local set = {}
        for _, item in ipairs(outlines or {}) do
            if type(item) ~= "table" or type(item.rootID) ~= "string" or type(item.elementID) ~= "string" then
                error("SetEditSessionWorldOutlines items require rootID and elementID", 2)
            end
            set[item.rootID] = set[item.rootID] or {}
            set[item.rootID][item.elementID] = true
        end
        session.worldOutlineSet = set
        session.worldOutlines = { target = target }
    end
    SetWorldElementSelection(session)
    return true
end

local function ReplaceSessionManualSelection(providerID, predicate)
    local session = GetSession(providerID)
    local objects = GetSessionObjectMap(session.provider)
    session.manualSelection = {}
    for objectID, object in pairs(objects) do
        if object.supported and predicate(object) then session.manualSelection[objectID] = true end
    end
    return ReconcileEditSession(providerID)
end

function EXUI:ReplaceEditSessionManualWithLoaded(providerID)
    return ReplaceSessionManualSelection(providerID, function(object) return object.loadMatched end)
end

function EXUI:ReplaceEditSessionManualWithAll(providerID)
    return ReplaceSessionManualSelection(providerID, function() return true end)
end

function EXUI:ClearEditSessionManualSelection(providerID)
    local session = GetSession(providerID)
    session.manualSelection = {}
    return ReconcileEditSession(providerID)
end

function EXUI:IsEditSessionObjectSelected(providerID, objectID)
    local session = state.editSessions[providerID]
    return session and session.manualSelection[objectID] == true or false
end

function EXUI:RefreshEditSessionProvider(providerID)
    if not state.editSessions[providerID] then return false end
    return ReconcileEditSession(providerID)
end

function EXUI:RefreshEditSessionObject(providerID, objectID)
    local session = state.editSessions[providerID]
    if not session then return false end
    if session.provider.contract == "presentation-transaction" then
        local rootID = session.provider.RootOf(objectID)
        if type(rootID) ~= "string" or rootID == "" then return false end
        session.dirtyRoots[rootID] = true
    elseif session.entities[objectID] then
        local module = session.entities[objectID]
        ReleaseWorldPreview(module)
        session.entities[objectID] = nil
    end
    return ReconcileEditSession(providerID)
end

function EXUI:RegisterEditableModule(declaration)
    if type(declaration) ~= "table" then error("RegisterEditableModule: declaration must be table", 2) end
    if type(declaration.addon) ~= "string" or not OVERLAY_PROFILES[declaration.addon] then error("RegisterEditableModule: addon must have a Core overlay profile", 2) end
    if type(declaration.key) ~= "string" or declaration.key == "" then error("RegisterEditableModule: key must be non-empty string", 2) end
    if type(declaration.name) ~= "string" or declaration.name == "" then error("RegisterEditableModule: name must be localized non-empty string", 2) end
    if declaration.orientation ~= "HORIZONTAL" and declaration.orientation ~= "VERTICAL" then error("RegisterEditableModule: orientation must be HORIZONTAL or VERTICAL", 2) end
    if type(declaration.settingsPage) ~= "string" or declaration.settingsPage == "" then error("RegisterEditableModule: settingsPage must be non-empty string", 2) end
    if type(declaration.getAnchor) ~= "function" then error("RegisterEditableModule: getAnchor must be function", 2) end
    local declaresStandardPreview = declaration.BuildPreview ~= nil or declaration.ApplyLayoutIntent ~= nil
    if declaresStandardPreview then
        if type(declaration.BuildPreview) ~= "function" then error("RegisterEditableModule: BuildPreview must be function", 2) end
        if type(declaration.ApplyLayoutIntent) ~= "function" then error("RegisterEditableModule: ApplyLayoutIntent must be function", 2) end
    end
    local declaresWorldRenderer = declaration.RenderWorld ~= nil or declaration.ReleaseWorld ~= nil
    if declaresWorldRenderer then
        if type(declaration.RenderWorld) ~= "function" then error("RegisterEditableModule: RenderWorld must be function", 2) end
        if type(declaration.ReleaseWorld) ~= "function" then error("RegisterEditableModule: ReleaseWorld must be function", 2) end
        if type(declaration.GetWorldBounds) ~= "function" then error("RegisterEditableModule: renderer requires GetWorldBounds function", 2) end
    end
    if not declaresStandardPreview and not declaresWorldRenderer then
        error("RegisterEditableModule: requires BuildPreview+ApplyLayoutIntent or RenderWorld+ReleaseWorld", 2)
    end
    if declaration.OnWorldPreviewStateChanged ~= nil and type(declaration.OnWorldPreviewStateChanged) ~= "function" then
        error("RegisterEditableModule: OnWorldPreviewStateChanged must be function or nil", 2)
    end
    if declaration.GetWorldBounds ~= nil and type(declaration.GetWorldBounds) ~= "function" then
        error("RegisterEditableModule: GetWorldBounds must be function or nil", 2)
    end
    if declaration.RenderPreviewExtraChildren ~= nil and type(declaration.RenderPreviewExtraChildren) ~= "function" then
        error("RegisterEditableModule: RenderPreviewExtraChildren must be function or nil", 2)
    end
    if declaration.worldAnchorMode ~= nil and declaration.worldAnchorMode ~= "content-center" and declaration.worldAnchorMode ~= "semantic-root" then
        error("RegisterEditableModule: worldAnchorMode must be content-center or semantic-root", 2)
    end
    if declaration.editOverlay ~= nil and (type(declaration.editOverlay) ~= "table" or type(declaration.editOverlay.titleFontSize) ~= "number" or declaration.editOverlay.titleFontSize <= 0) then
        error("RegisterEditableModule: editOverlay.titleFontSize must be positive number", 2)
    end

    local id = declaration.addon .. ":" .. declaration.key
    if state.modules[id] then error("RegisterEditableModule: duplicate module " .. id, 2) end
    state.modules[id] = declaration
    if state.phase == "ACTIVE" then RefreshModule(declaration) end
    EXUI:RefreshEditModeControlPanel()
end

function EXUI:RegisterModuleSettingsRouter(addon, router)
    if type(addon) ~= "string" or addon == "" then error("RegisterModuleSettingsRouter: addon must be non-empty string", 2) end
    if type(router) ~= "function" then error("RegisterModuleSettingsRouter: router must be function", 2) end
    if state.routers[addon] then error("RegisterModuleSettingsRouter: duplicate router " .. addon, 2) end
    state.routers[addon] = router
end

function EXUI:OpenModuleSettings(addon, settingsPage)
    local router = state.routers[addon]
    if not router then error("no settings router registered for " .. tostring(addon), 2) end
    router(settingsPage)
end

function EXUI:IsEditModeActive()
    return state.phase == "ACTIVE"
end

function EXUI:ToggleEditMode(forceState)
    if forceState ~= nil and type(forceState) ~= "boolean" then error("ToggleEditMode: forceState must be boolean or nil", 2) end
    SetEnabled(forceState == nil and state.phase ~= "ACTIVE" or forceState)
end

-- Unified Panel 的快捷入口需要在编辑期间让出整块画布，并在退出后恢复原窗口。
-- 回调只属于当前这一轮编辑会话；无论使用明确退出键、右上角关闭键或其它正式
-- ToggleEditMode(false) 入口退出，都只执行一次，避免留下跨会话的返回动作。
function EXUI:EnterEditModeWithExitCallback(exitCallback)
    if type(exitCallback) ~= "function" then
        error("EnterEditModeWithExitCallback: exitCallback must be function", 2)
    end
    state.exitCallback = exitCallback
    SetEnabled(true)
end

function EXUI:SetEditModeModuleVisible(addon, key, shown)
    local id = tostring(addon) .. ":" .. tostring(key)
    if not state.modules[id] then error("SetEditModeModuleVisible: unknown module " .. id, 2) end
    -- 不能写成 `shown == true and nil or false`：这是 Lua and-or 模拟三元
    -- 表达式的经典陷阱，中间的真值分支本身是 nil，会导致 and 结果为 nil、
    -- 又被 or 继续判定为假值而落到 false——整个表达式无论 shown 是什么，
    -- 结果永远是 false，可见性永远锁死在"隐藏"，这正是"点显示也勾不上、
    -- 必须点全部显示才恢复"的直接原因。
    if shown == true then
        settings.visibleByKey[id] = nil
    else
        settings.visibleByKey[id] = false
    end
    -- 单个模块的显示/隐藏切换走和"全部显示"按钮相同的 RefreshAll 路径，
    -- 而不是只 RefreshModule 这一个模块，保持两条路径行为一致。
    RefreshAll()
end

-- A settings page may temporarily own a selected root's visible preview.
-- The root remains in the transaction suppression set, but Core does not
-- materialize its FULLSCREEN_DIALOG World entity.  Ownership is named so
-- multiple pages can change their own roots atomically without clearing one
-- another.  This is intentionally a Core session API: pages must never write
-- Runtime presentation suppression or mutate provider Catalog support flags.
function EXUI:SetEditSessionPanelOnlyRoots(providerID, ownerID, rootIDs)
    if type(ownerID) ~= "string" or ownerID == "" then
        error("SetEditSessionPanelOnlyRoots: ownerID must be non-empty string", 2)
    end
    if type(rootIDs) ~= "table" then error("SetEditSessionPanelOnlyRoots: rootIDs must be table", 2) end
    local session = state.editSessions[providerID]
    if not session then return false, L["编辑会话未开启"] end
    if session.provider.contract ~= "presentation-transaction" then
        return false, L["该编辑会话不支持 panel-only root"]
    end
    local objects = GetSessionObjectMap(session.provider)
    local nextRoots = {}
    for key, value in pairs(rootIDs) do
        local rootID = type(key) == "number" and value or (value == true and key or nil)
        if type(rootID) ~= "string" or rootID == "" then
            error("SetEditSessionPanelOnlyRoots: every rootID must be a non-empty string", 2)
        end
        local object = objects[rootID]
        if not object or not object.supported then
            return false, L["对象已不存在或暂不支持预览"]
        end
        nextRoots[rootID] = true
    end
    session.panelOnlyRootsByOwner[ownerID] = nextRoots
    session.panelOnlyRoots = {}
    for _, ownedRoots in pairs(session.panelOnlyRootsByOwner) do
        for rootID in pairs(ownedRoots) do session.panelOnlyRoots[rootID] = true end
    end
    return ReconcileEditSession(providerID)
end

-- 配置页或模块业务写入完成后只请求唯一 Core 重新取纯预览快照；模块不拥有世界
-- preview 生命周期，也不能自己显示/隐藏 world Frame。
function EXUI:RefreshEditableModule(addon, key)
    local id = tostring(addon) .. ":" .. tostring(key)
    local module = state.modules[id]
    if not module then error("RefreshEditableModule: unknown module " .. id, 2) end
    local ok, err = RefreshModule(module)
    if not ok then return false, err end
    return true
end

-- Slider 实时写回只允许重套当前已物化的标准 World 预览；绝不进入
-- RefreshModule，因此不会 Release/Materialize、改变宿主生命周期或重建框架。
-- 仅单样本 icon/material 且拓扑不变的 Preview 可成功；其余情况明确返回 false，
-- 调用方不得把 false 降级为刷新/重建。
function EXUI:ReapplyActiveEditablePreviewMaterial(addon, key)
    local id = tostring(addon) .. ":" .. tostring(key)
    local module = state.modules[id]
    if not module then error("ReapplyActiveEditablePreviewMaterial: unknown module " .. id, 2) end
    if state.phase ~= "ACTIVE" or settings.visibleByKey[id] == false or UsesWorldRenderer(module)
        or not module.host or not module.worldPreview or module.worldPreview.released then
        return false
    end

    local preview = module.BuildPreview()
    if type(preview) ~= "table" or type(preview.definition) ~= "table" or type(preview.model) ~= "table" then
        error("BuildPreview() for " .. id .. " must return { definition = table, model = table }", 2)
    end
    local ok, result = RunEditModeModuleStage(module, "reapply.material", function()
        if not module.worldPreview:ReapplyCurrentMaterial(preview.definition, preview.model) then
            return false
        end
        ApplySemanticRootHostBounds(module)
        ApplyWorldBounds(module)
        SetWorldInput(module, true)
        SetOverlay(module, state.overlayVisible)
        return true
    end)
    if not ok then return false, result end
    return result == true
end

function EXUI:SetEditModeOverlayVisible(shown)
    state.overlayVisible = shown == true
    settings.overlayVisible = state.overlayVisible
    if state.phase == "ACTIVE" then
        for _, module in pairs(state.modules) do
            if module.host then
                local ok = RunEditModeModuleStage(module, "overlay", function()
                    SetOverlay(module, state.overlayVisible)
                    if module.__worldRendererActive then SetWorldInput(module, true) end
                end)
                if not ok then CleanupFailedWorldPreview(module) end
            end
        end
    end
    -- EXAura uses an edit-session transaction rather than global module
    -- registration. The global switch must affect those entities too.
    for _, session in pairs(state.editSessions) do
        if session.provider.contract == "presentation-transaction" then
            for rootID, entity in pairs(session.entities) do
                SetPresentationOverlay(session, rootID, entity, state.overlayVisible)
            end
            SetWorldElementSelection(session)
        end
    end
    EXUI:RefreshEditModeControlPanel()
end

local EDIT_PANEL_GROUPS = {
    {
        addon = "EXBoss",
        label = L["EXBOSS"],
        title = { 1.00, 0.91, 0.62, 1.00 },
    },
    {
        addon = "ExwindTools",
        label = L["EXTOOLS"],
        title = { 0.88, 0.70, 1.00, 1.00 },
    },
}

local function SetAddonModulesVisible(addon, shown)
    local changed = false
    for _, module in pairs(state.modules) do
        if module.addon == addon then
            local id = ModuleID(module)
            if shown == true then
                if settings.visibleByKey[id] ~= nil then changed = true end
                settings.visibleByKey[id] = nil
            else
                if settings.visibleByKey[id] ~= false then changed = true end
                settings.visibleByKey[id] = false
            end
        end
    end
    if changed then RefreshAll() end
end

local function AreAddonModulesVisible(entries)
    if #entries == 0 then return false end
    for _, module in ipairs(entries) do
        if settings.visibleByKey[ModuleID(module)] == false then return false end
    end
    return true
end

local EDIT_PANEL_METRICS = ExwindTools.GUIMetrics
local EDIT_PANEL_COLORS = ExwindTools.GUIColors
-- EXUI.ControlAppearance 由 ExwindGUI.lua 定义，该文件在 TOC 中晚于本文件加载，只能在调用时取值。
local EDIT_PANEL_LEVEL = 3000 -- 高于同 owner 的 TOOLTIP 覆盖层（1900）及拖动提示（2000）。

local function RaiseEditModeControlPanel(panel)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(EDIT_PANEL_LEVEL)
    panel:Raise()
end

local function PositionEditModeControlPanel(panel)
    local margin = EDIT_PANEL_METRICS.space.cardBodyPadding * 2
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -margin, -margin)
end

local function EnsurePanel()
    if EXUI.EditModeControlPanel then return EXUI.EditModeControlPanel end
    local panel = CreateFrame("Frame", "ExwindEditModeControlPanel", UIParent, "BackdropTemplate")
    panel:SetSize(EDIT_PANEL_METRICS.size.menuMaxWidth, EDIT_PANEL_METRICS.size.menuMaxHeight)
    PositionEditModeControlPanel(panel)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(EDIT_PANEL_LEVEL)
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetScript("OnShow", RaiseEditModeControlPanel)
    EXUI:ApplyDialogStyle(panel)
    panel.groups = {}

    local title = EXUI:CreateVisualFontString(panel, _G.EXFONTFRAME, "GameFontNormalLarge")
    title:SetText(L["EXWIND 编辑模式"])
    EXUI.ControlAppearance.ApplyTextRole(title, "cardTitle", EDIT_PANEL_COLORS.text)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    panel.title = title

    local subtitle = EXUI:CreateVisualFontString(panel, _G.EXFONTFRAME, "GameFontHighlightSmall")
    subtitle:SetText(L["选择需要显示的模块；左键拖拽模块，右键打开设置"])
    EXUI.ControlAppearance.ApplyTextRole(subtitle, "body", EDIT_PANEL_COLORS.textDim)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)
    panel.subtitle = subtitle

    local closeSize = EDIT_PANEL_METRICS.size.floatingCloseSize
    local close = EXUI:CreateButton(panel, closeSize, closeSize, "", function() EXUI:ToggleEditMode(false) end)
    local closeIcon = EXUI:CreateVisualTexture(close, _G.EXBORDERFRAME)
    closeIcon:SetTexture(EXUI:GetIcon("x"))
    closeIcon:SetSize(EDIT_PANEL_METRICS.size.treeIconSize, EDIT_PANEL_METRICS.size.treeIconSize)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetVertexColor(unpack(EDIT_PANEL_COLORS.textDim))
    panel.close = close

    local overlay = EXUI:CreateCheckbox(panel, L["显示覆盖层"], state.overlayVisible, function(checked)
        EXUI:SetEditModeOverlayVisible(checked)
    end)
    panel.overlay = overlay

    local scrollFrame = EXUI:CreateScrollFrame(panel)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    panel.scrollFrame = scrollFrame
    panel.content = content

    panel.measure = EXUI:CreateVisualFontString(panel, _G.EXFONTFRAME, "GameFontHighlightSmall")
    EXUI.ControlAppearance.ApplyTextRole(panel.measure, "title", EDIT_PANEL_COLORS.text)
    panel.measure:Hide()

    -- 底部操作统一使用 CreateButton；宽度在重排时按真实文字测量。
    local showAll = EXUI:CreateButton(panel, 120, ExwindTools.GUIMetrics.size.buttonHeight, L["全部显示"], function()
        for id in pairs(settings.visibleByKey) do settings.visibleByKey[id] = nil end
        RefreshAll()
    end)
    panel.showAll = showAll

    local exit = EXUI:CreateButton(panel, 120, ExwindTools.GUIMetrics.size.buttonHeight, L["退出编辑模式"], function()
        EXUI:ToggleEditMode(false)
    end, { variant = "primary" })
    panel.exit = exit

    panel:RegisterEvent("UI_SCALE_CHANGED")
    panel:RegisterEvent("DISPLAY_SIZE_CHANGED")
    panel:SetScript("OnEvent", function()
        if state.phase == "ACTIVE" then EXUI:RefreshEditModeControlPanel() end
    end)

    panel:Hide()
    EXUI.EditModeControlPanel = panel
    return panel
end

local function EnsurePanelGroup(panel, definition)
    local group = panel.groups[definition.addon]
    if group then return group end
    local content = panel.content
    group = { addon = definition.addon, definition = definition, rows = {} }
    group.background = CreateFrame("Frame", nil, content)
    EXUI:SetControlSurface(group.background, EDIT_PANEL_METRICS.radius.card,
        EDIT_PANEL_COLORS.card, EDIT_PANEL_COLORS.cardBorder)
    group.header = EXUI:CreateCheckbox(group.background, definition.label, true, nil)
    group.header.label:SetTextColor(unpack(definition.title))
    panel.groups[definition.addon] = group
    return group
end

local function ConfigurePanelRow(row, module, width)
    row.label:SetText(module.name)
    row.label:SetTextColor(unpack(EDIT_PANEL_COLORS.text))
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.checkbox, "RIGHT", EDIT_PANEL_METRICS.space.descriptionGap, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetWordWrap(false)
    row:SetSize(width, EDIT_PANEL_METRICS.size.checkboxRowHeight)
    row:SetChecked(settings.visibleByKey[ModuleID(module)] ~= false)
    row.checkbox:SetScript("OnClick", function(button)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        EXUI:SetEditModeModuleVisible(module.addon, module.key, button:GetChecked() == true)
    end)
end

local function LayoutEditModePanelChrome(panel, longestName)
    local gm = EDIT_PANEL_METRICS
    local pad, gap, line = gm.space.cardBodyPadding, gm.space.settingsV2Gap, gm.size.controlHeight
    local scrollInset = EXUI.MODERN_SCROLL_FRAME_RIGHT_INSET
    local checkboxInset = gm.size.checkboxRowHeight + gm.space.descriptionGap
    local function ButtonWidth(button)
        return math.max(gm.size.buttonMinWidth,
            math.ceil(button:GetFontString():GetUnboundedStringWidth()) + gm.space.buttonPaddingX * 2)
    end
    local showWidth, exitWidth = ButtonWidth(panel.showAll), ButtonWidth(panel.exit)
    local overlayWidth = math.ceil(panel.overlay.label:GetUnboundedStringWidth()) + checkboxInset
    local footerWidth = showWidth + exitWidth + overlayWidth + gap * 2 + pad * 2
    local naturalColumn = math.max(gm.size.minTextWidth, longestName) + checkboxInset
    local naturalWidth = math.max(naturalColumn * 2 + gm.space.columnGap + pad * 3 + scrollInset,
        footerWidth, panel.title:GetUnboundedStringWidth() + gm.size.floatingCloseSize + pad * 2 + gap)
    local availableWidth = math.max(1, UIParent:GetWidth() - pad * 4)
    local width = math.min(math.ceil(naturalWidth), gm.size.menuMaxWidth * 2, availableWidth)
    panel:SetWidth(width)

    panel.close:ClearAllPoints()
    panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad, -pad)
    panel.title:ClearAllPoints()
    panel.title:SetPoint("LEFT", panel, "TOPLEFT", pad, -pad - gm.size.floatingCloseSize / 2)
    panel.title:SetPoint("RIGHT", panel.close, "LEFT", -gap, 0)
    panel.subtitle:ClearAllPoints()
    panel.subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", pad,
        -pad - gm.size.floatingCloseSize - gm.space.descriptionGap)
    panel.subtitle:SetWidth(math.max(1, width - pad * 2))
    local headerHeight = pad + gm.size.floatingCloseSize + gm.space.descriptionGap
        + math.max(gm.font.text, panel.subtitle:GetStringHeight()) + gm.space.sectionGroupGap

    panel.showAll:ClearAllPoints()
    panel.showAll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, pad)
    panel.showAll:SetSize(showWidth, line)
    panel.exit:ClearAllPoints()
    panel.exit:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -pad, pad)
    panel.exit:SetSize(exitWidth, line)
    panel.overlay:ClearAllPoints()
    local footerHeight = line + pad * 2 + gm.space.sectionTop
    if width < footerWidth then
        panel.overlay:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, pad + line + gm.space.descriptionGap)
        panel.overlay:SetSize(math.max(1, width - pad * 2), line)
        footerHeight = footerHeight + line + gm.space.descriptionGap
    else
        panel.overlay:SetPoint("LEFT", panel.showAll, "RIGHT", gap, 0)
        panel.overlay:SetSize(width - pad * 2 - showWidth - exitWidth - gap * 2, line)
    end
    panel.scrollFrame:ClearAllPoints()
    panel.scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -headerHeight)
    panel.scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -scrollInset, footerHeight)
    local contentWidth = math.max(1, width - pad - scrollInset)
    local minColumn = gm.size.minTextWidth + checkboxInset
    local columns = contentWidth - pad * 2 >= minColumn * 2 + gm.space.columnGap and 2 or 1
    return contentWidth, columns, headerHeight, footerHeight
end

function EXUI:RefreshEditModeControlPanel()
    local panel = EnsurePanel()
    panel.overlay:SetChecked(state.overlayVisible)

    local byAddon, longestName = {}, 0
    for _, module in pairs(state.modules) do
        byAddon[module.addon] = byAddon[module.addon] or {}
        byAddon[module.addon][#byAddon[module.addon] + 1] = module
        panel.measure:SetText(module.name)
        longestName = math.max(longestName, math.ceil(panel.measure:GetUnboundedStringWidth()))
    end

    local ordered = {}
    for _, definition in ipairs(EDIT_PANEL_GROUPS) do
        if byAddon[definition.addon] then
            ordered[#ordered + 1] = definition
            byAddon[definition.addon] = nil
        end
    end
    local extraAddons = {}
    for addon in pairs(byAddon) do extraAddons[#extraAddons + 1] = addon end
    table.sort(extraAddons)
    for _, addon in ipairs(extraAddons) do
        ordered[#ordered + 1] = {
            addon = addon,
            label = addon,
            title = { 0.86, 0.86, 0.92, 1.00 },
        }
    end

    local gm = EDIT_PANEL_METRICS
    local pad, gap, line = gm.space.cardBodyPadding, gm.space.settingsV2Gap, gm.size.checkboxRowHeight
    local contentWidth, columns, headerHeight, footerHeight = LayoutEditModePanelChrome(panel, longestName)
    local columnWidth = math.max(1, (contentWidth - pad * 2 - (columns - 1) * gm.space.columnGap) / columns)
    local content = panel.content
    local y = 0
    local usedGroups = {}
    for _, definition in ipairs(ordered) do
        local addon = definition.addon
        local entries = byAddon[definition.addon]
        if not entries then
            entries = {}
            for _, module in pairs(state.modules) do
                if module.addon == definition.addon then entries[#entries + 1] = module end
            end
        end
        table.sort(entries, function(a, b) return ModuleID(a) < ModuleID(b) end)
        local group = EnsurePanelGroup(panel, definition)
        usedGroups[definition.addon] = true

        group.header:ClearAllPoints()
        group.header:SetPoint("TOPLEFT", group.background, "TOPLEFT", pad, -pad)
        group.header:SetSize(math.max(1, contentWidth - pad * 2), line)
        group.header.label:ClearAllPoints()
        group.header.label:SetPoint("LEFT", group.header.checkbox, "RIGHT", gm.space.descriptionGap, 0)
        group.header.label:SetPoint("RIGHT", group.header, "RIGHT", 0, 0)
        group.header.label:SetWordWrap(false)
        group.header.label:SetText(definition.label)
        group.header.label:SetTextColor(unpack(definition.title))
        group.header:SetChecked(AreAddonModulesVisible(entries))
        group.header.checkbox:SetScript("OnClick", function(button)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            SetAddonModulesVisible(addon, button:GetChecked() == true)
        end)
        group.header:Show()

        local rowsTop = -pad - line - gap
        for index, module in ipairs(entries) do
            local row = group.rows[index]
            if not row then
                row = EXUI:CreateCheckbox(group.background, "", true, nil)
                group.rows[index] = row
            end
            local column = (index - 1) % columns
            local rowIndex = math.floor((index - 1) / columns)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", group.background, "TOPLEFT", pad + column * (columnWidth + gm.space.columnGap),
                rowsTop - rowIndex * (line + gm.space.treeRowGap))
            ConfigurePanelRow(row, module, columnWidth)
            row:Show()
        end
        for index = #entries + 1, #group.rows do group.rows[index]:Hide() end

        local rowCount = math.ceil(#entries / columns)
        local groupHeight = pad * 2 + line + gap + rowCount * line + math.max(0, rowCount - 1) * gm.space.treeRowGap
        group.background:ClearAllPoints()
        group.background:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        group.background:SetSize(contentWidth, groupHeight)
        group.background:Show()
        y = y - groupHeight - gap
    end
    for addon, group in pairs(panel.groups) do
        if not usedGroups[addon] then
            group.background:Hide()
            group.header:Hide()
            for _, row in ipairs(group.rows) do row:Hide() end
        end
    end

    local contentHeight = math.max(1, -y - gap)
    content:SetSize(contentWidth, contentHeight)
    -- 宽度足够时两列完整展示模块，窄屏改为单列；只有屏幕高度容纳不下时，ScrollFrame
    -- 才成为兜底，避免为了固定窗口高度而平白让玩家滚动。
    local desiredHeight = contentHeight + headerHeight + footerHeight
    local screenHeight = tonumber(UIParent:GetHeight()) or desiredHeight
    local maxHeight = math.max(1, screenHeight - pad * 4)
    panel:SetHeight(math.min(desiredHeight, maxHeight))
    if panel.__resetPositionOnNextRefresh then
        PositionEditModeControlPanel(panel)
        panel.__resetPositionOnNextRefresh = nil
    end
    if state.phase == "ACTIVE" then
        RaiseEditModeControlPanel(panel)
        panel:Show()
    else
        panel:Hide()
    end
end

function EXUI:ShowEditModeControlPanel()
    EnsurePanel():Show()
    EXUI:RefreshEditModeControlPanel()
end
