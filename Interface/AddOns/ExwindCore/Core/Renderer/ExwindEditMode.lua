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
        fill = { r = 0.56, g = 0.25, b = 0.88, a = 0.16 },
        border = { r = 0.84, g = 0.62, b = 1.00, a = 1.00 },
        borderSize = 2,
        title = { r = 0.96, g = 0.88, b = 1.00, a = 1.00 },
        titleOutline = "OUTLINE",
        titleShadow = { r = 0.12, g = 0.02, b = 0.22, a = 1.00, x = 2, y = -2 },
    },
}

local state = {
    phase = "OFF",
    modules = {},
    routers = {},
    editSessionProviders = {},
    editSessions = {},
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
        local left = bounds.anchorOffsetX - bounds.width * 0.5
        local right = bounds.anchorOffsetX + bounds.width * 0.5
        local bottom = bounds.anchorOffsetY - bounds.height * 0.5
        local top = bounds.anchorOffsetY + bounds.height * 0.5
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
    local object = session.objectMap and session.objectMap[rootID]
    local title = object and object.name or session.provider.name
    local worldBounds = GetPresentationWorldBounds(session, rootID, entity)
    EXUI:SetEditModeVisualLayerShown(
        entity.host,
        shown == true,
        GetProfile(session.provider),
        title,
        GetTitleSize(session.provider),
        worldBounds
    )
end

local function DestroyPresentationEntity(session, rootID)
    local entity = session.entities[rootID]
    if not entity then return end
    -- Remove ownership before destroying UI so a provider release callback
    -- cannot re-enter a half-destroyed entity.
    session.entities[rootID] = nil
    SetPresentationOverlay(session, rootID, entity, false)
    -- A transaction entity is atomic.  Core always owns the release moment;
    -- renderer entities never acquire StandardPreview, and preview entities
    -- retain their existing terminal unmount behaviour.
    if entity.rendererActive then
        session.provider.ReleaseWorld(rootID, entity.renderer)
        entity.renderer = nil
        entity.rendererActive = nil
    else
        for _, preview in ipairs(entity.previews or {}) do
            preview:Unmount()
        end
    end
    if entity.host then
        entity.host:SetScript("OnDragStart", nil)
        entity.host:SetScript("OnDragStop", nil)
        entity.host:SetScript("OnUpdate", nil)
        entity.host:EnableMouse(false)
        entity.host:Hide()
    end
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

local function CreatePresentationEntity(session, rootID)
    local project, usesWorldRenderer = ValidatePresentationProject(session.provider, rootID, session.provider.Project(rootID))
    local host = CreateFrame("Frame", nil, EnsurePresentationRoot())
    host:SetFrameStrata("FULLSCREEN_DIALOG")
    host:SetFrameLevel(2)
    host:SetMovable(false)
    host:EnableMouse(true)
    host:RegisterForDrag("LeftButton")
    ApplyPresentationPlacement(host, project.placement)
    local entity = { host = host, previews = {}, placement = project.placement }
    session.entities[rootID] = entity
    if usesWorldRenderer then
        -- The renderer is allowed to return a collection handle.  Core treats
        -- it as opaque and passes it back only to ReleaseWorld/GetWorldBounds;
        -- the host itself remains Core-owned for selection and root dragging.
        entity.renderer = session.provider.RenderWorld(rootID, host, project)
        entity.rendererActive = true
    else
        -- All layers share the one movable root.  Their own item anchors live
        -- in declaration/model data, so Core never manufactures offsets or
        -- titles. StandardPreview may calculate a content envelope while
        -- materializing; restore root placement below to keep drag geometry
        -- owned solely by the transaction placement.
        for _, layer in ipairs(project.layers) do
            local preview = EXUI:CreateStandardPreview(host, {
                interactionMode = "world",
                worldAnchorMode = "semantic-root",
            })
            entity.previews[#entity.previews + 1] = preview
            preview:Materialize(layer.definition, layer.model)
        end
    end
    ApplyPresentationPlacement(host, project.placement)
    host:Show()
    SetPresentationOverlay(session, rootID, entity, state.overlayVisible)
    host:SetScript("OnDragStart", function(frame)
        local scale = frame:GetEffectiveScale() or 1
        local cursorX, cursorY = GetCursorPosition()
        local placement = entity.placement or {}
        frame.__presentationDrag = { scale = scale, cursorX = cursorX / scale, cursorY = cursorY / scale, x = tonumber(placement.x) or 0, y = tonumber(placement.y) or 0 }
        frame:SetScript("OnUpdate", function(dragFrame)
            local drag = dragFrame.__presentationDrag
            if not drag then return end
            local nowX, nowY = GetCursorPosition()
            drag.xNow, drag.yNow = drag.x + nowX / drag.scale - drag.cursorX, drag.y + nowY / drag.scale - drag.cursorY
            local temporary = entity.placement or {}
            ApplyPresentationPlacement(dragFrame, { point = temporary.point, relativePoint = temporary.relativePoint, width = temporary.width, height = temporary.height, x = drag.xNow, y = drag.yNow })
        end)
    end)
    host:SetScript("OnDragStop", function(frame)
        local drag = frame.__presentationDrag
        frame.__presentationDrag = nil
        frame:SetScript("OnUpdate", nil)
        if not drag then return end
        -- OnUpdate may not run between the final cursor movement and mouse-up.
        -- Commit must therefore derive the release point directly instead of
        -- silently persisting the previous frame (or even the drag origin).
        local cursorX, cursorY = GetCursorPosition()
        local finalX = drag.x + cursorX / drag.scale - drag.cursorX
        local finalY = drag.y + cursorY / drag.scale - drag.cursorY
        local committed = session.provider.Commit(rootID, {
            type = "rootMoved",
            position = { x = finalX, y = finalY },
        })
        if committed ~= true then
            error("presentation provider rejected rootMoved for " .. session.provider.id .. ":" .. rootID, 2)
        end
        entity.placement = entity.placement or {}
        entity.placement.x, entity.placement.y = finalX, finalY
        ApplyPresentationPlacement(frame, entity.placement)
        local notification = session.provider.ResolveNotification(rootID, {
            type = "rootMoved",
            position = { x = finalX, y = finalY },
        })
        if type(notification) ~= "table" then
            error("presentation provider ResolveNotification must return table for " .. session.provider.id .. ":" .. rootID, 2)
        end
        local moduleKey = EXUI:RequireModuleKey(notification.moduleKey, "presentation provider ResolveNotification")
        local changedPaths = notification.changedPaths
        if type(changedPaths) ~= "table" or #changedPaths == 0 then
            error("presentation provider ResolveNotification requires non-empty changedPaths", 2)
        end
        for _, changedPath in ipairs(changedPaths) do
            if type(changedPath) ~= "string" or changedPath == "" then
                error("presentation provider ResolveNotification changedPaths must contain non-empty strings", 2)
            end
            EXUI:NotifyModuleValueChanged(moduleKey, changedPath, "committed")
        end
    end)
    return entity
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

local function ReconcileEditSession(providerID)
    local session = GetSession(providerID)
    if session.reconciling then return end
    session.reconciling = true
    session.phase = "RECONCILING"
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
        if session.provider.contract == "presentation-transaction" then DestroyPresentationEntity(session, entry.id)
        else ReleaseWorldPreview(entry.module); session.entities[entry.id] = nil end
    end
    for objectID in pairs(materializedTarget) do
        if session.provider.contract == "presentation-transaction" then
            -- A configuration refresh is an entirely new entity. StandardPreview
            -- is never reused after Unmount.
            if session.dirtyRoots and session.dirtyRoots[objectID] and session.entities[objectID] then
                DestroyPresentationEntity(session, objectID)
            end
        end
        if not session.entities[objectID] then MaterializeSessionEntity(session, objectID) end
    end
    session.dirtyRoots = {}
    session.phase = "ACTIVE"
    session.reconciling = false
    if session.provider.contract == "presentation-transaction" then
        local suppressed = {}
        for rootID in pairs(target) do suppressed[rootID] = true end
        session.provider.SetPresentation(session.token, suppressed)
    end
    return target
end

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
            or type(provider.Commit) ~= "function" or type(provider.SetPresentation) ~= "function" or type(provider.ResolveNotification) ~= "function" then
            error("RegisterEditSessionProvider: presentation-transaction requires Catalog, RootOf, Project, Commit, SetPresentation, ResolveNotification", 2)
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

function EXUI:BeginEditSession(providerID)
    local provider = GetSessionProvider(providerID)
    -- UnifiedPanel can call a provider's Show route more than once without an
    -- intervening OnHide.  Opening the same provider session is idempotent:
    -- retain its focus/manual set rather than throwing or resetting choices.
    if state.editSessions[providerID] then return true, state.editSessions[providerID] end
    local session = {
        provider = provider, phase = "OPENING", token = {}, focusID = nil,
        manualSelection = {}, entities = {}, objectMap = {}, dirtyRoots = {},
        panelOnlyRoots = {}, panelOnlyRootsByOwner = {},
    }
    state.editSessions[providerID] = session
    local objects = GetSessionObjectMap(provider)
    for objectID, object in pairs(objects) do
        if object.supported and object.loadMatched then session.manualSelection[objectID] = true end
    end
    ReconcileEditSession(providerID)
    return true, session
end

function EXUI:EndEditSession(providerID)
    local session = state.editSessions[providerID]
    if not session then return false end
    session.phase = "CLOSING"
    local entityIDs = {}
    for objectID in pairs(session.entities) do entityIDs[#entityIDs + 1] = objectID end
    for _, objectID in ipairs(entityIDs) do
        local module = session.entities[objectID]
        if session.provider.contract == "presentation-transaction" then DestroyPresentationEntity(session, objectID)
        else ReleaseWorldPreview(module) end
    end
    if session.provider.contract == "presentation-transaction" then session.provider.SetPresentation(session.token, {}) end
    state.editSessions[providerID] = nil
    return true
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
    ReconcileEditSession(providerID)
    return true
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
    ReconcileEditSession(providerID)
    return true
end

local function ReplaceSessionManualSelection(providerID, predicate)
    local session = GetSession(providerID)
    local objects = GetSessionObjectMap(session.provider)
    session.manualSelection = {}
    for objectID, object in pairs(objects) do
        if object.supported and predicate(object) then session.manualSelection[objectID] = true end
    end
    ReconcileEditSession(providerID)
end

function EXUI:ReplaceEditSessionManualWithLoaded(providerID)
    ReplaceSessionManualSelection(providerID, function(object) return object.loadMatched end)
end

function EXUI:ReplaceEditSessionManualWithAll(providerID)
    ReplaceSessionManualSelection(providerID, function() return true end)
end

function EXUI:ClearEditSessionManualSelection(providerID)
    local session = GetSession(providerID)
    session.manualSelection = {}
    ReconcileEditSession(providerID)
end

function EXUI:IsEditSessionObjectSelected(providerID, objectID)
    local session = state.editSessions[providerID]
    return session and session.manualSelection[objectID] == true or false
end

function EXUI:RefreshEditSessionProvider(providerID)
    if not state.editSessions[providerID] then return false end
    ReconcileEditSession(providerID)
    return true
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
    ReconcileEditSession(providerID)
    return true
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
    ReconcileEditSession(providerID)
    return true
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
        end
    end
    EXUI:RefreshEditModeControlPanel()
end

local EDIT_PANEL_GROUPS = {
    {
        addon = "EXBoss",
        label = L["EXBOSS"],
        fill = { 0.78, 0.58, 0.14, 0.14 },
        title = { 1.00, 0.91, 0.62, 1.00 },
    },
    {
        addon = "ExwindTools",
        label = L["EXTOOLS"],
        fill = { 0.48, 0.24, 0.80, 0.15 },
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

local function EnsurePanel()
    if EXUI.EditModeControlPanel then return EXUI.EditModeControlPanel end
    local panel = CreateFrame("Frame", "ExwindEditModeControlPanel", UIParent, "BackdropTemplate")
    panel:SetSize(520, 500)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(200)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(false)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.055, 0.045, 0.085, 0.98)
    panel:SetBackdropBorderColor(0.62, 0.42, 0.90, 0.92)
    panel.groups = {}

    local title = EXUI:CreateVisualFontString(panel, _G.EXFONTFRAME, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -13)
    title:SetText(L["EXWIND 编辑模式"])
    title:SetTextColor(0.94, 0.86, 1.00, 1.00)
    panel.title = title

    local subtitle = EXUI:CreateVisualFontString(panel, _G.EXFONTFRAME, "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText(L["选择需要显示的模块；左键拖拽模块，右键打开设置"])
    subtitle:SetTextColor(0.60, 0.55, 0.70, 1.00)
    panel.subtitle = subtitle

    -- 关闭键沿用暴雪标准模板，这是项目里统一面板等处一贯的做法，不算需要
    -- 换成 EXUI 封装的"设置控件"。其余交互控件（勾选框、按钮）以下全部改用
    -- EXUI:CreateCheckbox / CreateSmallButton，不再手写 CheckButton/Button。
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() EXUI:ToggleEditMode(false) end)

    local overlay = EXUI:CreateCheckbox(panel, L["显示覆盖层"], state.overlayVisible, function(checked)
        EXUI:SetEditModeOverlayVisible(checked)
    end)
    overlay:SetSize(146, 28)
    overlay:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -42, -12)
    panel.overlay = overlay

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetPoint("TOPLEFT", 12, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(470, 1)
    scrollFrame:SetScrollChild(content)
    panel.scrollFrame = scrollFrame
    panel.content = content

    local showAll = EXUI:CreateSmallButton(panel, L["全部显示"], function()
        for id in pairs(settings.visibleByKey) do settings.visibleByKey[id] = nil end
        RefreshAll()
    end)
    showAll:SetSize(118, 24)
    showAll:SetPoint("BOTTOMLEFT", 14, 14)
    panel.showAll = showAll

    local exit = EXUI:CreateSmallButton(panel, L["退出编辑模式"], function()
        EXUI:ToggleEditMode(false)
    end)
    exit:SetSize(118, 24)
    exit:SetPoint("BOTTOMRIGHT", -14, 14)
    panel.exit = exit

    panel:Hide()
    EXUI.EditModeControlPanel = panel
    return panel
end

local function EnsurePanelGroup(panel, definition)
    local group = panel.groups[definition.addon]
    if group then return group end
    local content = panel.content
    group = { addon = definition.addon, definition = definition, rows = {} }
    group.background = content:CreateTexture(nil, "BACKGROUND")
    group.background:SetTexture("Interface\\Buttons\\WHITE8X8")
    group.header = EXUI:CreateCheckbox(content, definition.label, true, nil)
    group.header:SetSize(220, 28)
    group.header.label:SetTextColor(unpack(definition.title))
    panel.groups[definition.addon] = group
    return group
end

local function ConfigurePanelRow(row, module)
    row.label:SetText(module.name)
    row.label:SetTextColor(0.88, 0.86, 0.94, 1.00)
    row.label:SetWidth(184)
    row:SetChecked(settings.visibleByKey[ModuleID(module)] ~= false)
    row.checkbox:SetScript("OnClick", function(button)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        EXUI:SetEditModeModuleVisible(module.addon, module.key, button:GetChecked() == true)
    end)
end

function EXUI:RefreshEditModeControlPanel()
    local panel = EnsurePanel()
    panel.overlay:SetChecked(state.overlayVisible)

    local byAddon = {}
    for _, module in pairs(state.modules) do
        byAddon[module.addon] = byAddon[module.addon] or {}
        byAddon[module.addon][#byAddon[module.addon] + 1] = module
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
            fill = { 0.32, 0.32, 0.38, 0.12 },
            title = { 0.86, 0.86, 0.92, 1.00 },
        }
    end

    local content = panel.content
    local y = -8
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
        group.header:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y)
        group.header.label:SetText(definition.label)
        group.header.label:SetTextColor(unpack(definition.title))
        group.header:SetChecked(AreAddonModulesVisible(entries))
        group.header.checkbox:SetScript("OnClick", function(button)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            SetAddonModulesVisible(addon, button:GetChecked() == true)
        end)
        group.header:Show()

        local rowsTop = y - 30
        for index, module in ipairs(entries) do
            local row = group.rows[index]
            if not row then
                row = EXUI:CreateCheckbox(content, "", true, nil)
                row:SetSize(220, 26)
                group.rows[index] = row
            end
            local column = (index - 1) % 2
            local rowIndex = math.floor((index - 1) / 2)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", column == 0 and 10 or 242, rowsTop - rowIndex * 26)
            ConfigurePanelRow(row, module)
            row:Show()
        end
        for index = #entries + 1, #group.rows do group.rows[index]:Hide() end

        local rowCount = math.ceil(#entries / 2)
        local groupHeight = 36 + rowCount * 26
        group.background:ClearAllPoints()
        group.background:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y + 4)
        group.background:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y + 4)
        group.background:SetHeight(groupHeight)
        group.background:SetVertexColor(unpack(definition.fill))
        group.background:Show()
        y = y - groupHeight - 8
    end
    for addon, group in pairs(panel.groups) do
        if not usedGroups[addon] then
            group.background:Hide()
            group.header:Hide()
            for _, row in ipairs(group.rows) do row:Hide() end
        end
    end

    local contentHeight = math.max(1, -y + 4)
    content:SetSize(470, contentHeight)
    -- 两列布局优先完整展示所有模块；只有当前屏幕确实容纳不下时，ScrollFrame
    -- 才成为兜底，避免为了固定窗口高度而平白让玩家滚动。
    local desiredHeight = contentHeight + 108
    local screenHeight = tonumber(UIParent:GetHeight()) or desiredHeight
    local maxHeight = math.max(320, screenHeight - 48)
    panel:SetHeight(math.min(desiredHeight, maxHeight))
    if panel.__resetPositionOnNextRefresh then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        panel.__resetPositionOnNextRefresh = nil
    end
    if state.phase == "ACTIVE" then panel:Show() else panel:Hide() end
end

function EXUI:ShowEditModeControlPanel()
    EnsurePanel():Show()
    EXUI:RefreshEditModeControlPanel()
end
