-- =========================================================
-- ExwindGrid.lua - 可视化网格布局引擎 (v4.2 增强版)
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools then
    error(L["[ExwindGrid] 错误: ExwindTools.lua 必须在 ExwindGrid.lua 之前加载!"])
end

-- 确保 EXUI 命名空间存在（可能在 ExwindToolsUI.lua 之前加载）
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI
local GM = ExwindTools.GUIMetrics

local Grid = {
    Cols = 50,
    CellSize = 0,
    Padding = 2,
    ActiveLayout = {},
    Widgets = {},
    CustomRenderers = {},
    ExportReferences = setmetatable({}, { __mode = "k" }),
    IsLiveEditing = false,
    ContainerCols = setmetatable({}, { __mode = "k" }),
    ContainerPadding = setmetatable({}, { __mode = "k" }),
    ContainerStates = setmetatable({}, { __mode = "k" }),
    CardSessions = setmetatable({}, { __mode = "k" }),
    CardSessionOwners = setmetatable({}, { __mode = "k" }),
    CardScrollSessions = setmetatable({}, { __mode = "k" }),
    CardBodyOnlyComponents = {
        fontgroup = true,
        icongroup = true,
        soundgroup = true,
        timerbargroup = true,
        widgetlayout = true,
        modulecommonsettings = true,
        anchorgroup = true,
        glow_settings = true,
    },
    EditorGridLinesByContainer = setmetatable({}, { __mode = "k" }),
    EditorRowGuidesByContainer = setmetatable({}, { __mode = "k" }),
    _effectiveCols = 50,
}

-- 挂载到多个位置方便访问
ExwindTools.Grid = Grid
EXUI.Grid = Grid
_G.ExwindGrid = Grid

local function NormalizeCols(cols)
    local n = tonumber(cols)
    if not n then return nil end
    n = math.floor(n)
    if n < 10 then n = 10 end
    if n > 200 then n = 200 end
    return n
end

local function GetContainerState(self, container)
    if not container then return nil end
    local state = self.ContainerStates[container]
    if not state then
        state = {
            widgets = {},
            instances = {},
            widgetMap = {},
            layout = nil,
            config = nil,
            moduleKey = nil,
        }
        self.ContainerStates[container] = state
    end
    return state
end

local function ActivateContainerState(self, container, state)
    if not container or not state then return end
    self._activeContainer = container
    self.Widgets = state.widgets
    self.WidgetInstances = state.instances
    self.WidgetMap = state.widgetMap
    self.ActiveLayout = state.layout or {}
    self.LastConfig = state.config
    self.ModuleKey = state.moduleKey
end

local function WalkLayoutItems(items, callback)
    for _, item in ipairs(items or {}) do
        callback(item)
        if type(item.children) == "table" then WalkLayoutItems(item.children, callback) end
    end
end

local function GetExportSession(grid)
    local container = grid and (grid.LiveEditContainer or grid.LiveContainer)
    local state = container and grid.ContainerStates[container]
    return state and state.exportSession or nil
end

-- 在线编辑器看到的是测量后的工作布局，不能把它整表当成源码 GUI 导出。
-- 会话开始时只给现有项分配稳定标识；后续只记录用户真正改过的字段。
function Grid:BeginModuleSpecExportSession(container)
    local state = GetContainerState(self, container)
    if not state then return end
    local session = { nextID = 0, baseline = {}, changes = {}, added = {}, addedOrder = {}, deleted = {} }
    WalkLayoutItems(state.layout, function(item)
        session.nextID = session.nextID + 1
        local id = "existing:" .. session.nextID
        item._exGridExportID = id
        session.baseline[id] = {
            sourceKey = item.key,
            declaredY = tonumber(item._declaredY) or tonumber(item.y) or 1,
            renderedY = tonumber(item.y) or 1,
            declaredH = tonumber(item._declaredH) or tonumber(item.h) or 1,
            renderedH = tonumber(item.h) or 1,
        }
    end)
    state.exportSession = session
end

function Grid:RecordModuleSpecLayoutChange(item, changes)
    if type(item) ~= "table" or type(changes) ~= "table" then return end

    -- Card 编辑器操作的是测量后的 Body 工作副本。把允许编辑的字段同步回
    -- session.declaration 内对应的纯声明 item；否则下一次 Card reflow 会从
    -- 原声明重建并吞掉用户刚完成的拖动/改名/缩放。
    local cardSource = item._exCardSourceItem
    if type(cardSource) == "table" then
        for field, value in pairs(changes) do
            if field == "y" and type(value) == "number" then
                value = math.max(1, math.floor(value
                    + (tonumber(item._declaredY) or tonumber(cardSource.y) or 1)
                    - (tonumber(item._exCardRenderedY) or tonumber(item.y) or 1)))
            elseif field == "h" and type(value) == "number" then
                value = math.max(1, math.floor(value
                    + (tonumber(item._declaredH) or tonumber(cardSource.h) or 1)
                    - (tonumber(item._exCardRenderedH) or tonumber(item.h) or 1)))
            end
            cardSource[field] = value
        end
        return
    end

    local session, id = GetExportSession(self), item._exGridExportID
    local baseline = session and id and session.baseline[id]
    if not baseline then return end
    local target = session.changes[id] or {}
    for field, value in pairs(changes) do
        if field == "y" and type(value) == "number" then
            value = math.max(1, math.floor(value + baseline.declaredY - baseline.renderedY))
        elseif field == "h" and type(value) == "number" then
            value = math.max(1, math.floor(value + baseline.declaredH - baseline.renderedH))
        end
        target[field] = value
    end
    session.changes[id] = target
end

function Grid:RecordModuleSpecLayoutAddition(item)
    if type(item) ~= "table" then return end
    local session = GetExportSession(self)
    if not session then return end
    session.nextID = session.nextID + 1
    local id = "added:" .. session.nextID
    item._exGridExportID = id
    session.added[id] = true
    session.addedOrder[#session.addedOrder + 1] = id
end

function Grid:RecordModuleSpecLayoutDeletion(item)
    if type(item) ~= "table" then return end
    local session, id = GetExportSession(self), item._exGridExportID
    if session and id then session.deleted[id] = true end
end

-- 编辑覆盖层不能作为卡片子 Frame：Unified Shell 的内容 host 与卡片不在同一
-- 层级树中，低层 GridCard 的子 Frame 无法越过 Shell 内容层接收鼠标。覆盖层
-- 必须作为当前 Grid 容器的 sibling，并在卡片回池前显式解除临时交互状态。
local function ReleaseEditOverlay(widget)
    local overlay = widget and widget.dragOverlay
    if not overlay then return end

    overlay:SetScript("OnUpdate", nil)
    overlay:SetScript("OnMouseDown", nil)
    overlay:SetScript("OnMouseUp", nil)
    overlay.isResizing = nil
    overlay:Hide()
    overlay:ClearAllPoints()

    if overlay.resizer then
        overlay.resizer:SetScript("OnUpdate", nil)
        overlay.resizer:SetScript("OnMouseDown", nil)
        overlay.resizer:SetScript("OnMouseUp", nil)
        overlay.resizer:Hide()
    end

    -- 卡片仍是覆盖层的持久 owner；下一次进入编辑模式会重新挂到目标 container。
    overlay:SetParent(widget)
end

-- 普通 GridCard 的 backdrop 属于卡片本体。卡片内容若由更高 frame level 的
-- sibling 渲染（例如 virtual list），会局部盖住 backdrop 的细边框。需要完整
-- 外框的卡片可通过 keepBorderVisible 启用这个无背景轮廓层。
local function ReleaseCardOutline(widget)
    local outline = widget and widget._gridCardOutline
    if not outline then return end
    outline:Hide()
    outline:ClearAllPoints()
    outline:SetParent(nil)
end

-- Grid 只承载设置页的静态 GUI。cellSize 来自容器宽度 / 列数，通常是浮点数；
-- 若最后仍以普通 SetPoint/SetSize 落地，输入框、按钮、卡片边框与分隔线会落在
-- 半个物理像素上。不要把这套修正扩散到 runtime renderer：这里只对 Grid widget
-- 的最终宿主 Frame 生效。
local function SetPhysicalPoint(region, point, relativeTo, relativePoint, x, y)
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(region, point, relativeTo, relativePoint, x or 0, y or 0, 0, 0)
    else
        region:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    end
end

local function SetPhysicalSize(region, width, height)
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(region, width, height, 1, 1)
    else
        region:SetSize(width, height)
    end
end

local function SetPhysicalLineThickness(line)
    if not line then return end
    local PixelUtil = _G.PixelUtil
    if line.SetThickness then
        local scale = line:GetEffectiveScale() or 1
        local thickness = PixelUtil and PixelUtil.GetNearestPixelSize
            and PixelUtil.GetNearestPixelSize(1, scale, 1) or 1
        line:SetThickness(thickness)
    elseif line.SetHeight then
        if PixelUtil and PixelUtil.SetHeight then
            PixelUtil.SetHeight(line, 1, 1)
        else
            line:SetHeight(1)
        end
    end
end

local function RefreshCardOutlineGeometry(outline)
    if not outline then return end

    SetPhysicalLineThickness(outline.top)
    outline.top:ClearAllPoints()
    SetPhysicalPoint(outline.top, "TOPLEFT", outline, "TOPLEFT", 0, 0)
    SetPhysicalPoint(outline.top, "TOPRIGHT", outline, "TOPRIGHT", 0, 0)

    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(outline.right, 1, 1)
    else
        outline.right:SetWidth(1)
    end
    outline.right:ClearAllPoints()
    SetPhysicalPoint(outline.right, "TOPRIGHT", outline, "TOPRIGHT", 0, 0)
    SetPhysicalPoint(outline.right, "BOTTOMRIGHT", outline, "BOTTOMRIGHT", 0, 0)

    SetPhysicalLineThickness(outline.bottom)
    outline.bottom:ClearAllPoints()
    SetPhysicalPoint(outline.bottom, "BOTTOMLEFT", outline, "BOTTOMLEFT", 0, 0)
    SetPhysicalPoint(outline.bottom, "BOTTOMRIGHT", outline, "BOTTOMRIGHT", 0, 0)

    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(outline.left, 1, 1)
    else
        outline.left:SetWidth(1)
    end
    outline.left:ClearAllPoints()
    SetPhysicalPoint(outline.left, "TOPLEFT", outline, "TOPLEFT", 0, 0)
    SetPhysicalPoint(outline.left, "BOTTOMLEFT", outline, "BOTTOMLEFT", 0, 0)
end

local function EnsureCardOutline(widget, container, color)
    if not (widget and container) then return end
    local outline = widget._gridCardOutline
    if not outline then
        outline = CreateFrame("Frame", nil, container)
        outline:EnableMouse(false)
        outline.top = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.right = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.bottom = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.left = EXUI:CreateVisualTexture(outline, EXBORDERFRAME)
        outline.top:SetPoint("TOPLEFT")
        outline.top:SetPoint("TOPRIGHT")
        outline.top:SetHeight(1)
        outline.right:SetPoint("TOPRIGHT")
        outline.right:SetPoint("BOTTOMRIGHT")
        outline.right:SetWidth(1)
        outline.bottom:SetPoint("BOTTOMLEFT")
        outline.bottom:SetPoint("BOTTOMRIGHT")
        outline.bottom:SetHeight(1)
        outline.left:SetPoint("TOPLEFT")
        outline.left:SetPoint("BOTTOMLEFT")
        outline.left:SetWidth(1)
        widget._gridCardOutline = outline
    end

    outline:SetParent(container)
    outline:SetFrameStrata(container:GetFrameStrata() or "LOW")
    outline:SetFrameLevel((container:GetFrameLevel() or 1) + 30)
    outline:ClearAllPoints()
    outline:SetAllPoints(widget)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    outline.top:SetColorTexture(r, g, b, a)
    outline.right:SetColorTexture(r, g, b, a)
    outline.bottom:SetColorTexture(r, g, b, a)
    outline.left:SetColorTexture(r, g, b, a)

    -- 参考 Blizzard NamePlateBorderTemplateMixin：1px 边线的锚点和厚度
    -- 都经 PixelUtil 量化，避免 UI Scale / 非整数 Grid Cell 使纹理落在半像素。
    RefreshCardOutlineGeometry(outline)
    outline:Show()
end

function Grid:SetContainerCols(container, cols)
    if not container then return false end
    local n = NormalizeCols(cols)
    if not n then
        self.ContainerCols[container] = nil
        return false
    end
    self.ContainerCols[container] = n
    return true
end

function Grid:ClearContainerCols(container)
    if not container then return end
    self.ContainerCols[container] = nil
end

function Grid:GetContainerCols(container)
    if not container then return nil end
    return self.ContainerCols[container]
end

function Grid:SetContainerPadding(container, padding)
    if not container then return false end
    if type(padding) ~= "table" then
        self.ContainerPadding[container] = nil
        return false
    end
    self.ContainerPadding[container] = {
        left = tonumber(padding.left) or 10,
        right = tonumber(padding.right) or 10,
        top = tonumber(padding.top) or 10,
        bottom = tonumber(padding.bottom) or 0,
    }
    return true
end

function Grid:ClearContainerPadding(container)
    if not container then return end
    self.ContainerPadding[container] = nil
end

function Grid:GetContainerPadding(container)
    if not container then
        return { left = 10, right = 10, top = 10, bottom = 0 }
    end
    return self.ContainerPadding[container] or { left = 10, right = 10, top = 10, bottom = 0 }
end

function Grid:UpdateMetrics(containerWidth, container)
    local cols = self:GetContainerCols(container) or self.Cols
    local padding = self:GetContainerPadding(container)
    self._effectiveCols = cols
    self.CellSize = (containerWidth - padding.left - padding.right) / cols
end

function Grid:GetPixelRect(x, y, w, h, container)
    local padding = self:GetContainerPadding(container or self._activeContainer)
    local px = (x - 1) * self.CellSize + padding.left
    local py = -(y - 1) * self.CellSize - padding.top
    local pw = w * self.CellSize - self.Padding
    local ph = (h or 2) * self.CellSize - self.Padding
    return px, py, pw, ph
end

local function DefaultControlHeight(element)
    if element.h ~= nil then return nil end
    local kind = element.type
    if kind == "input" or kind == "button" or kind == "checkbox" or kind == "color" then
        return GM.size.controlHeight
    end
end

-- 这是 Grid 唯一的最终布局落点。所有由 Grid 承载的都是设置页静态 GUI；
-- 不在这里出现 runtime 条、图标或文字 renderer。用 PixelUtil 同时量化位置和尺寸，
-- 避免只量化 1px 线却仍把其父 Frame 放在半像素上的伪修复。
local function LayoutBossSummaryEnabled(widget)
    local saved = widget and widget._exGridBossSummaryEnabled
    if not saved then return false end
    widget:ClearAllPoints()
    widget:SetPoint("LEFT", saved.host, "LEFT", 0, 0)
    widget:SetPoint("RIGHT", saved.host, "RIGHT", 0, 0)
    widget:SetHeight(GM.size.checkboxRowHeight)
    return true
end

function Grid:ApplyPixelLayout(widget, container, element)
    if not (widget and container and element) then return end
    if LayoutBossSummaryEnabled(widget) then return end

    local px, py, pw, ph = self:GetPixelRect(element.x, element.y, element.w, element.h, container)
    local width = widget._exGridWidth or pw
    local height = widget._exGridFixedHeight or widget._exGridCardMeasuredHeight
        or DefaultControlHeight(element) or ph

    -- Grid is the final size owner. A text button may grow into free space on
    -- its row, but cannot cover the next declared control or the card edge.
    -- Explicit compact/icon buttons keep their declared width.
    if element.type == "button" and widget._exButtonCompact ~= true then
        local theme = EXUI and EXUI.ModernTheme
        local style = theme and theme.buttonStyle
        local metrics = theme and theme.metrics
        local minimumWidth = style and tonumber(style.minWidth)
        local label = widget.GetFontString and widget:GetFontString()
        local textWidth = label and label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or 0
        local naturalWidth = textWidth + GM.space.buttonPaddingX * 2
        local paddingY = style and tonumber(style.paddingY)
        local textHeight = metrics and tonumber(metrics.button)
        width = math.max(width, minimumWidth or 0)
        if naturalWidth > width then
            local padding = self:GetContainerPadding(container)
            local right = container:GetWidth() - padding.right
            local state = self.ContainerStates[container]
            local top, bottom = tonumber(element.y) or 0,
                (tonumber(element.y) or 0) + (tonumber(element.h) or 2)
            for _, peer in ipairs(state and state.layout or {}) do
                local peerX, peerY = tonumber(peer.x), tonumber(peer.y)
                if peer ~= element and peerX and peerY and peerX > (tonumber(element.x) or 0)
                    and top < peerY + (tonumber(peer.h) or 2) and peerY < bottom then
                    local peerPixelX = (peerX - 1) * self.CellSize + padding.left
                    right = math.min(right, peerPixelX - self.Padding)
                end
            end
            width = math.min(naturalWidth, math.max(width, right - px))
        end
        if paddingY and textHeight then
            height = math.max(height, textHeight + paddingY * 2)
        end
    end

    widget:ClearAllPoints()
    SetPhysicalPoint(widget, "TOPLEFT", container, "TOPLEFT", px, py)
    SetPhysicalSize(widget, width, height)

    -- Every composite finishes from the actual pixel-aligned host size. The
    -- same entry is used by constructors and pooled reuse; no extra panel.
    if type(widget._exCompositeReflow) == "function" then
        EXUI:LayoutCompositeGroup(widget, widget:GetWidth(), widget:GetHeight())
        -- Existing editor-created empty cards retain their declared height.
        if widget._exCompositeOpts and widget._exCompositeOpts.gridEditableHeight == true then
            SetPhysicalSize(widget, width, height)
            EXUI:RefreshCompositeSurfaces(widget)
        end
    end

    -- Factory 创建的 Header/Divider 分别使用 Texture / SimpleLine；两者都以
    -- 同一个真实物理像素为粗细，且在每次最终布局时重套。
    if element.type == "divider" then
        if widget.separator then
            if _G.PixelUtil and _G.PixelUtil.SetHeight then
                _G.PixelUtil.SetHeight(widget.separator, 1, 1)
            else
                widget.separator:SetHeight(1)
            end
        else
            SetPhysicalLineThickness(widget.line)
        end
    elseif element.type == "header" then
        SetPhysicalLineThickness(widget.Line)
    end
    RefreshCardOutlineGeometry(widget._gridCardOutline)
end

function Grid:RefreshPixelLayout(container)
    local settingsList = self:GetSettingsListSession(container)
    if settingsList then return settingsList:Relayout() end
    local state = self.ContainerStates[container]
    if not (container and state and state.instances) then return end
    if container._exGridPixelLayoutBusy then return end
    if not container.GetWidth or container:GetWidth() <= 0 then return end

    container._exGridPixelLayoutBusy = true
    -- Grid 的 metrics 是历史共享字段。临时切到目标容器计算后必须还原，不能把
    -- 当前编辑容器的 metrics 偷换为另一个已显示页面的 metrics。
    local previousCellSize, previousCols = self.CellSize, self._effectiveCols
    self:UpdateMetrics(container:GetWidth(), container)

    for _, widget in ipairs(state.instances) do
        local element = widget and widget._exGridPixelElement
        if element and widget.GetParent and widget:GetParent() == container then
            self:ApplyPixelLayout(widget, container, element)
        end
    end

    self.CellSize, self._effectiveCols = previousCellSize, previousCols
    container._exGridPixelLayoutBusy = nil
end

function Grid:EnsurePixelLayoutHooks(container)
    if not container or container._exGridPixelLayoutHooksInstalled then return end
    container._exGridPixelLayoutHooksInstalled = true

    container:HookScript("OnShow", function(host)
        if not Grid:RequestReflow(host) then
            Grid:RefreshPixelLayout(host)
        end
    end)
    container:HookScript("OnSizeChanged", function(host)
        if not Grid:RequestReflow(host) then
            Grid:RefreshPixelLayout(host)
        end
    end)

    if not self._pixelLayoutWatcher then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("UI_SCALE_CHANGED")
        watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
        watcher:SetScript("OnEvent", function()
            for host in pairs(Grid.ContainerStates) do
                if host and host.IsShown and host:IsShown() then
                    if not Grid:RequestReflow(host) then
                        Grid:RefreshPixelLayout(host)
                    end
                end
            end
        end)
        self._pixelLayoutWatcher = watcher
    end
end

function Grid:GetGridPos(lx, ly, container)
    local padding = self:GetContainerPadding(container or self._activeContainer)
    local gx = math.floor((lx - (padding.left * 0.5)) / self.CellSize) + 1
    local gy = math.floor((math.abs(ly) - (padding.top * 0.5)) / self.CellSize) + 1
    local cols = self._effectiveCols or self.Cols
    return math.max(1, math.min(gx, cols)), math.max(1, gy)
end

function Grid:RegisterCustomRenderer(key, renderer)
    if type(key) ~= "string" or key == "" then
        return false
    end
    if type(renderer) ~= "table" then
        return false
    end
    self.CustomRenderers[key] = renderer
    return true
end

function Grid:GetCustomRenderer(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return self.CustomRenderers[key]
end

-- Core 公共自定义渲染器：人物卡片网格（实现与声明说明见 ExwindGUIComposite.lua 的 PersonCards）。
assert(EXUI.PersonCardsRenderer, "ExwindGUIComposite.lua must load before ExwindGrid.lua")
Grid:RegisterCustomRenderer("EXUI.PersonCards", EXUI.PersonCardsRenderer)

function Grid:ReleaseWidgetInstance(widget)
    if not widget then
        return
    end
    ReleaseEditOverlay(widget)
    ReleaseCardOutline(widget)
    local renderer = widget._customRenderer
    local rendererReleaseReason
    if renderer and type(renderer.release) == "function" then
        local released, reason = pcall(renderer.release, widget, widget._customContext)
        if not released then rendererReleaseReason = reason end
    end
    widget._customRenderer = nil
    widget._customRendererKey = nil
    widget._customContext = nil
    widget._exGridCardMeasuredHeight = nil
    widget._exGridRefreshItemRecordCell = nil
    local EXFactory = _G.ExwindFactory
    -- A few historical composite shells (the two GlowSettings definitions)
    -- are intentionally not pooled, but their standard child controls are.
    -- Return those children first; the shell then follows Release's existing
    -- _fromPool == nil path and is hidden/detached without inventing a pool.
    if EXFactory and widget._exGridOwnedControls then
        for index = #widget._exGridOwnedControls, 1, -1 do
            local control = widget._exGridOwnedControls[index]
            if control then EXFactory:ReleaseGridWidget(control) end
            widget._exGridOwnedControls[index] = nil
        end
        widget._exGridOwnedControls = nil
    end
    -- 组合控件宿主由其构造器登记清理函数。必须优先走这里，先断开子控件
    -- 回调/DB 引用，再归还外层宿主；不能把带旧闭包的控件直接塞回通用池。
    if EXFactory and widget._isCompositeHost then
        EXFactory:ReleaseCompositeHost(widget)
        if rendererReleaseReason then error(rendererReleaseReason, 0) end
        return
    end
    if EXFactory and widget._gridType then
        EXFactory:ReleaseGridWidget(widget)
    else
        widget:Hide()
        widget:SetParent(nil)
    end
    if rendererReleaseReason then error(rendererReleaseReason, 0) end
end

-- 布局导出无法从运行时 table 反查其 Lua 局部变量名。模块可显式登记规格表
-- 对应的源码表达式，使 ExportLayout 输出 `opts = MODULE_OPTIONS`，而不是静默丢失
-- 含函数的 opts 配置。
function Grid:RegisterExportReference(value, expression)
    if type(value) ~= "table" or type(expression) ~= "string" or expression == "" then
        return false
    end
    self.ExportReferences[value] = expression
    return true
end

-- 控件查找索引（Widgets）允许同一 key 被后续控件覆盖；生命周期不能依赖它。
-- 所有实际创建的实例均记录在 instances，按 AceGUI 的 children 模式逐个归还。
function Grid:ReleaseContainerWidgets(container)
    local cardSession = self.CardSessions[container]
    if cardSession and cardSession.exbossSummaryEnabled and not cardSession.released then
        return cardSession:Release()
    end
    local settingsList = self:GetSettingsListSession(container)
    if settingsList then settingsList:Release() end
    local state = GetContainerState(self, container)
    if not state then
        return false
    end
    local instances = state.instances or {}
    local released = {}
    local firstReleaseReason
    for i = #instances, 1, -1 do
        local widget = instances[i]
        instances[i] = nil
        if widget and not released[widget] then
            released[widget] = true
            local ok, reason = pcall(self.ReleaseWidgetInstance, self, widget)
            if not ok and firstReleaseReason == nil then firstReleaseReason = reason end
        end
    end
    table.wipe(state.widgets)
    table.wipe(state.widgetMap)
    if firstReleaseReason ~= nil then error(firstReleaseReason, 0) end
    return true
end

-- 模块通过标准预览 intent 写入自己的同一份 DB 后，页面需要让正在显示的
-- 组合控件立刻回读该 DB。Card root 先分发到各 Body，Body/旧 flat container
-- 仍只调 EXUI 的公开组合控件回刷入口；Grid 不解释模块字段、预览元素或路径。
function Grid:RefreshContainerControlsFromDB(container)
    local cardSession = self.CardSessions and self.CardSessions[container] or nil
    if cardSession and not cardSession.released then
        return cardSession:RefreshValues()
    end
    local state = GetContainerState(self, container)
    if not state then return false end
    local refreshed = false
    local ui = ExwindTools.UI
    for _, widget in ipairs(state.instances or {}) do
        if widget._exGridRefreshItemRecordCell then
            widget:_exGridRefreshItemRecordCell()
            refreshed = true
        else
            refreshed = ui:RefreshCompositeGroupFromDB(widget) or refreshed
        end
    end
    return refreshed
end

function Grid:AcquireCompositeHost(compositeType, parent)
    local EXFactory = _G.ExwindFactory
    local poolType = EXFactory and EXFactory.CompositePoolMap and EXFactory.CompositePoolMap[compositeType]
    if not poolType then
        return nil, false
    end
    return EXFactory:AcquireCompositeHost(poolType, parent)
end

function Grid:AttachCompositeRelease(host, releaseFn)
    local EXFactory = _G.ExwindFactory
    if not EXFactory then
        return false
    end
    return EXFactory:AttachPoolRelease(host, releaseFn)
end

local function ItemAllowsOverlap(item)
    return type(item) == "table" and (item.allowOverlap == true or item.type == "card")
end

function Grid:IsAreaEmpty(x, y, w, h, excludeKey, layout)
    -- [v2.0] 支持传入指定的 layout 子集（用于 TableGroup 内部排版检测）
    -- 但由于 v2.0 采用绝对坐标，其实还是应该检测全局
    -- 只是为了编辑器逻辑，可能需要调整
    local targetLayout = layout or self.ActiveLayout

    local function findByKey(items, key)
        if not key then return nil end
        for _, item in ipairs(items or {}) do
            if item.key == key then
                return item
            end
            if item.children then
                local found = findByKey(item.children, key)
                if found then
                    return found
                end
            end
        end
        return nil
    end

    local excludeItem = findByKey(targetLayout, excludeKey)
    if ItemAllowsOverlap(excludeItem) then
        return true
    end

    -- 递归检查函数
    local function checkRecursive(items)
        for _, item in ipairs(items) do
            if item.key ~= excludeKey and not ItemAllowsOverlap(item) then
                -- 核心：所有组件在运行时都使用绝对坐标 (item.x, item.y)
                -- 所以直接比较坐标即可，无需关心层级
                if not (x + w <= item.x or x >= item.x + item.w or
                        y + (h or 2) <= item.y or y >= item.y + (item.h or 2)) then
                    return false
                end

                -- 如果是 TableGroup，递归检查其子元素
                if item.children then
                    if not checkRecursive(item.children) then return false end
                end
            end
        end
        return true
    end

    if layout then
        -- 如果指定了子集，只检查子集（通常用于局部重排）
        return checkRecursive(layout)
    else
        -- 默认检查全局所有元素
        return checkRecursive(self.ActiveLayout)
    end
end

-- [Core] 提前声明 Helper，供 ValidateContext 调用
local function GetConfigPath(config, path)
    if not config or not path then return config end
    local keys = { strsplit(".", path) }
    local curr = config
    for i = 1, #keys do
        local k = tonumber(keys[i]) or keys[i]
        if type(curr) ~= "table" then return nil end
        curr = curr[k]
    end
    return curr
end

-- [v2.0 New] 数据有效性验证
function Grid:ValidateContext(config, contextPath)
    if not contextPath or contextPath == "" then return true end
    local data = GetConfigPath(config, contextPath)
    return (data ~= nil)
end

-- [v2.0 New] 递归渲染核心
function Grid:RenderItems(container, items, contextPath, config, moduleKey)
    for _, item in ipairs(items) do
        -- 1. 计算当前组件的绝对数据路径 (Scoped Context)
        local currentPath = contextPath
        if item.parentKey then
            if currentPath then
                currentPath = currentPath .. "." .. item.parentKey
            else
                currentPath = item.parentKey
            end
        end

        -- 2. 数据有效性熔断保护
        -- 如果当前路径无效（例如 rows.5 已被删除），则跳过渲染或回退
        if currentPath and not self:ValidateContext(config, currentPath) then

        else
            if item.type == "TableGroup" then
                -- [逻辑容器模式]
                -- Header/Label 渲染 (如果有)
                if item.label then
                    -- TableGroup 自身作为一个 Label/Header 组件存在
                    self:CreateWidget(container, item, config, moduleKey, currentPath)
                end

                -- 递归渲染子元素
                -- 关键：container 保持不变 (MainFrame)，传递新的 ContextPath
                if item.children then
                    self:RenderItems(container, item.children, currentPath, config, moduleKey)
                end
            else
                -- [普通组件]
                -- 使用计算好的 Absolute Path 进行数据绑定
                -- 传递 currentPath 给 CreateWidget，它将用作 fullKey
                self:CreateWidget(container, item, config, moduleKey, currentPath)
            end
        end

        -- 在协程内每处理完一个 item 就 yield，让 LibAsync 分帧执行
        if coroutine.running() then
            coroutine.yield()
        end
    end
end

-- 组件可在 schema 上声明 `measure`：
--   true       使用 EXUI 已登记的标准组件测量器；
--   function   measure(pixelWidth, opts, scopedDB, item) -> height 或高度表；
--   table      { minHeight = n, preferredHeight = n }。
-- 这是创建 Frame 前的纯合同，禁止依赖屏幕扫描、OnUpdate 或延迟布局。测量到的
-- h 仅作用于本次渲染副本，布局声明本身仍是唯一的 x/y/w/h 真源。
local function NormalizeMeasuredHeight(measurement)
    if type(measurement) == "number" then
        return measurement
    end
    if type(measurement) ~= "table" then return nil end
    local preferred = tonumber(measurement.preferredHeight or measurement.height)
    local minimum = tonumber(measurement.minHeight)
    if preferred and minimum then return math.max(preferred, minimum) end
    return preferred or minimum
end

local function GetMeasureResult(grid, item, pixelWidth, scopedDB)
    local declaration = item.measure
    if type(declaration) == "function" then
        return declaration(pixelWidth, item.opts or {}, scopedDB, item)
    end
    if type(declaration) == "table" then
        return declaration
    end
    if declaration ~= true then return nil end

    if item.type == "custom" then
        local renderer = grid:GetCustomRenderer(item.renderer or item.customType or item.widgetType)
        if renderer and type(renderer.measure) == "function" then
            return renderer.measure(pixelWidth, item.opts or {}, scopedDB, item)
        end
    end
    if EXUI and type(EXUI.MeasureGridComponent) == "function" then
        return EXUI:MeasureGridComponent(item.type, pixelWidth, item.opts or {}, scopedDB, item)
    end
    return nil
end

local function CopyMeasuredItems(grid, container, sourceItems, config, contextPath)
    local measured, shift = {}, 0
    for _, source in ipairs(sourceItems or {}) do
        local item = {}
        for key, value in pairs(source) do item[key] = value end

        local currentPath = contextPath
        if item.parentKey then
            currentPath = currentPath and (currentPath .. "." .. item.parentKey) or item.parentKey
        end
        local scopedDB = currentPath and GetConfigPath(config, currentPath) or config
        local isEditorModuleCommonCard = item.type == "modulecommonsettings"
            and type(item.key) == "string"
            and item.key:match("^modulecommonsettings_%d+$") ~= nil

        -- 旧会话里已经创建的在线编辑器卡片仍带有旧的 measure=true；在渲染
        -- 副本上收窄移除，让它和新的自由背景卡片一样保留手动 h。
        if isEditorModuleCommonCard then item.measure = false end

        -- modulecommonsettings 早已有动态高度行为；迁到同一公开 measure 合同，
        -- 保持全宽模块卡片的既有紧凑 Flow，而其他历史控件不会因本改动改变。
        if item.measure == nil
            and item.type == "modulecommonsettings"
            and type(item.opts) == "table"
            and (tonumber(item.w) or 0) == grid._effectiveCols then
            item.measure = true
        end

        -- Slider 的共享封装拥有固定的“标题/数值 header row + 下方轨道”高度。
        -- 默认用同一 measure 合同扩展逻辑占位，避免旧 h=2 声明让下一项压住轨道；
        -- 明确 measure=false 的在线编辑布局仍可保留人工高度。
        if item.measure == nil and item.type == "slider" then
            item.measure = true
        end

        if item.y then
            local declaredY = tonumber(source.y) or 1
            item._declaredY = declaredY
            item.y = math.max(1, declaredY - shift)
        end

        local oldHeight = math.max(1, tonumber(source.h) or 2)
        local _, _, pixelWidth = grid:GetPixelRect(item.x, item.y, item.w, item.h, container)
        local pixelHeight = NormalizeMeasuredHeight(GetMeasureResult(grid, item, pixelWidth, scopedDB))
        if pixelHeight and pixelHeight > 0 and grid.CellSize > 0 then
            local measuredHeight = math.max(1, math.ceil((pixelHeight + grid.Padding) / grid.CellSize))
            item._declaredH = oldHeight
            item.h = measuredHeight
            -- 每个声明项都是一个 section；后续项维持其相对于这个 section
            -- 的原始留白。显式 measure 才启用此重排，因此不会影响旧 schema。
            shift = shift + (oldHeight - measuredHeight)
        end

        if source.children then
            item.children = CopyMeasuredItems(grid, container, source.children, config, currentPath)
        end
        measured[#measured + 1] = item
    end
    return measured
end

local function BuildMeasuredLayout(grid, container, layoutData, config)
    return CopyMeasuredItems(grid, container, layoutData, config, nil)
end

function Grid:Render(container, layoutData, config, moduleKey, onFinished)
    if not container or not layoutData then return end

    if type(config) == "string" then
        moduleKey = config
        config = ExwindTools:GetModuleDB(moduleKey)
    end

    self:UpdateMetrics(container:GetWidth(), container)
    local renderedLayout = BuildMeasuredLayout(self, container, layoutData, config)
    local state = GetContainerState(self, container)
    state.layout = renderedLayout
    state.config = config
    state.moduleKey = moduleKey
    ActivateContainerState(self, container, state)
    self:EnsurePixelLayoutHooks(container)

    -- 仅归还当前容器的旧组件。必须遍历实际实例列表，不能只遍历 key 索引；
    -- TableGroup 的同名字段会覆盖 Widgets[key]，但每个实例都必须各自回池。
    self:ReleaseContainerWidgets(container)

    -- [v2.0] 启动递归渲染
    self:RenderItems(container, renderedLayout, nil, config, moduleKey)

    -- 计算最大高度 (需要递归遍历所有元素)
    local maxH = 1
    local function findMaxH(items)
        for _, ele in ipairs(items) do
            if ele.y then
                maxH = math.max(maxH, ele.y + (ele.h or 2))
            end
            if ele.children then findMaxH(ele.children) end
        end
    end
    findMaxH(renderedLayout)

    local contentHeight = maxH * self.CellSize + 80
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(container, contentHeight, 1)
    else
        container:SetHeight(contentHeight)
    end

    -- live edit 是容器级上下文。即使别的容器在运行时重渲染，
    -- 也不能把当前编辑会话的 ActiveLayout / WidgetMap / ModuleKey 偷换掉。
    local liveContainer = self.LiveEditContainer or self.LiveContainer
    if self.IsLiveEditing and liveContainer and liveContainer ~= container then
        local liveState = GetContainerState(self, liveContainer)
        if liveState then
            ActivateContainerState(self, liveContainer, liveState)
            if liveContainer.GetWidth then
                self:UpdateMetrics(liveContainer:GetWidth(), liveContainer)
            end
        end
    end

    if onFinished then onFinished() end
end

-- (GetConfigPath moved to top)

local function GetConfigValue(config, ele)
    if not config then return nil end

    local curr = config
    if ele.parentKey then
        curr = GetConfigPath(config, ele.parentKey)
    end

    if not curr or type(curr) ~= "table" then return nil end

    -- [Core] setKey 优先级最高，用于分离 GridKey 和 DBKey
    if ele.setKey then
        local sk = tonumber(ele.setKey) or ele.setKey
        return curr[sk]
    end

    -- [v4.3.2 Fix] subKey 优先级高于 ele.key
    -- 用法: parentKey="current", subKey="iconSize" → 读取 config.current.iconSize
    -- ele.key (如 "current_iconSize") 仅用于 Grid 组件标识，不参与数据路径
    if ele.subKey then
        local sk = tonumber(ele.subKey) or ele.subKey
        return curr[sk]
    end

    local key = ele.key
    local numKey = tonumber(key)
    local finalKey = numKey or key

    return curr[finalKey]
end

-- [v4.3.1] 递归查找布局项
local function FindLayoutItem(items, key)
    for _, item in ipairs(items) do
        if item.key == key then return item end
        if item.children then
            local found = FindLayoutItem(item.children, key)
            if found then return found end
        end
    end
    return nil
end

local function BindTooltip(target, ele, enableMouse)
    if not target or not target.SetScript then
        return
    end
    -- OnEnter/OnLeave 这两个槽位同时承载 Core 的 hover 画器，画器是
    -- HookScript 接在同一槽位的链上；SetScript 会把整条链一起清掉
    -- （用户 2026-10-05 游戏内实测）。所以先走 ClearControlScript 既清槽位
    -- 又丢掉画器的安装记录，再用 SetScript 放 tooltip；调用方紧随其后的
    -- ApplyControlAppearance 会把画器重新 Hook 到 tooltip 之上，两者共存。
    -- 重复调用也只覆盖 tooltip 处理器本身，不会叠加。
    EXUI:ClearControlScript(target, "OnEnter")
    EXUI:ClearControlScript(target, "OnLeave")
    if ele.tooltip or ele.spellID then
        if enableMouse and target.EnableMouse then
            target:EnableMouse(true)
        end
        target:SetScript("OnEnter", function(self)
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if ele.spellID then
                _G.GameTooltip:SetSpellByID(ele.spellID)
            elseif ele.tooltip then
                _G.GameTooltip:SetText(ele.tooltip, 1, 1, 1, 1, true)
            end
            _G.GameTooltip:Show()
        end)
        target:SetScript("OnLeave", function()
            _G.GameTooltip:Hide()
        end)
    else
        if enableMouse and target.EnableMouse then
            target:EnableMouse(false)
        end
        -- 置 nil 的一支由上面的 ClearControlScript 一并完成，这里不再裸 SetScript。
    end
end


local function SetConfigValue(config, ele, val, moduleKey, fullKey, phase)
    if not config then return end

    -- [Core] setKey 优先级最高 (Force Global/Local Override)
    if ele.setKey then
        local sk = tonumber(ele.setKey) or ele.setKey
        if config[sk] == val then return false end
        config[sk] = val
        if moduleKey and phase ~= "silent" then EXUI:NotifyModuleValueChanged(moduleKey, tostring(ele.setKey), phase == "live" and "changing" or "committed") end
        return true
    end

    -- 解析路径并赋值
    local finalPath = fullKey
    if finalPath then
        local parts = { strsplit(".", finalPath) }
        local ptr = config
        for i = 1, #parts - 1 do
            local k = tonumber(parts[i]) or parts[i]
            if not ptr[k] then ptr[k] = {} end
            ptr = ptr[k]
        end
        local lastKey = tonumber(parts[#parts]) or parts[#parts]
        if ptr[lastKey] == val then return false end
        ptr[lastKey] = val
    else
        local fk = tonumber(ele.key) or ele.key
        if config[fk] == val then return false end
        config[fk] = val
    end

    if moduleKey and phase ~= "silent" then EXUI:NotifyModuleValueChanged(moduleKey, fullKey or tostring(ele.key), phase == "live" and "changing" or "committed") end
    return true
end

-- Grid is the only place that combines a module's identity with the resolved
-- ModuleDB path.  Composite controls receive this private Core context; layout
-- declarations never carry input or refresh wiring.
local function BuildCompositeOptions(sourceOpts, moduleKey, pathPrefix)
    local opts = {}
    if type(sourceOpts) == "table" then
        for key, value in pairs(sourceOpts) do opts[key] = value end
    end
    if moduleKey then
        opts._exWriteContext = { moduleKey = moduleKey, pathPrefix = pathPrefix }
    end
    return opts
end

-- 旧版的 `condition and nil or key` 在 Lua 中永远回退到 key，因此已经声明
-- bindRoot 的 AnchorGroup 仍会多写出一层 `anchor` / `anchorGroup`。修正后，
-- 把那层旧表保留原样；仅在真实字段为空时，接回旧输入框中可能手动填写的目标。
-- 已由选择器写入的真实目标优先级最高，绝不覆盖。
local function MigrateLegacyDirectAnchorInput(anchorConfig, widgetKey, opts)
    if type(anchorConfig) ~= "table" or type(widgetKey) ~= "string" or widgetKey == "" then
        return false
    end

    local legacy = anchorConfig[widgetKey]
    if type(legacy) ~= "table" or legacy.__exAnchorDirectBindingMigrated then
        return false
    end
    legacy.__exAnchorDirectBindingMigrated = true

    opts = type(opts) == "table" and opts or {}
    local targetKey = opts.attachTargetKey or "customAttachTarget"
    local enabledKey = opts.attachEnabledKey or "attachToCustom"
    local legacyTarget = legacy[targetKey]
    local currentTarget = anchorConfig[targetKey]
    if (currentTarget == nil or currentTarget == "")
        and type(legacyTarget) == "string" and legacyTarget ~= "" then
        anchorConfig[targetKey] = legacyTarget
        if anchorConfig[enabledKey] ~= true then
            anchorConfig[enabledKey] = legacy[enabledKey] == true
        end
        return true
    end

    return false
end

local function NotifyCompositeWrite(moduleKey, fullPath)
    if moduleKey then EXUI:NotifyModuleValueChanged(moduleKey, fullPath, "committed") end
end

function Grid:CreateWidget(container, ele, config, moduleKey, contextPath)
    -- [v4.3.2] 构造当前组件的完整数据路径
    -- 关键: 当有 subKey 时，使用 subKey 作为数据键 (ele.key 仅用于 Grid 组件标识)
    local fullPath
    local dataKey = ele.subKey or ele.key -- subKey 优先级高于 key

    if contextPath then
        fullPath = contextPath .. "." .. dataKey
    else
        if ele.parentKey then
            fullPath = ele.parentKey .. "." .. dataKey
        else
            fullPath = tostring(dataKey)
        end
    end

    local px, py, pw, ph = self:GetPixelRect(ele.x, ele.y, ele.w, ele.h, container)
    ph = DefaultControlHeight(ele) or ph
    local widget
    local invalidItemRecord

    -- [v4.3.2] 获取值：setKey 最高优先，然后使用构造好的 fullPath
    local curVal
    if ele.setKey then
        curVal = config[ele.setKey]
    else
        curVal = GetConfigPath(config, fullPath)
    end

    local function Setter(v)
        SetConfigValue(config, ele, v, moduleKey, fullPath, "commit")
    end

    local function LiveSetter(v)
        SetConfigValue(config, ele, v, moduleKey, fullPath, "live")
    end

    local function ReadCurrentValue()
        if ele.setKey then return config[tonumber(ele.setKey) or ele.setKey] end
        return GetConfigPath(config, fullPath)
    end

    -- ... (Create Logic) ...
    if ele.type == "header" then
        local text = ele.label
        if type(text) == "function" then text = text() end
        widget = EXUI:CreateHeader(container, text or "", pw)
    elseif ele.type == "subheader" then
        local text = ele.label
        if type(text) == "function" then text = text() end
        widget = EXUI:CreateSubheader(container, text or "", pw)
    elseif ele.type == "divider" then
        widget = EXUI:CreateSettingsSeparator(container, pw)
    elseif ele.type == "button" then
        widget = EXUI:CreateButton(container, pw, ph, ele.label, function()
            if ele.func then ele.func() end
            if ele.key and moduleKey then
                ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = ele.key, fullPath = fullPath, ts = GetTime() })
            end
        end, { variant = ele.variant, compact = ele.compact == true })
    elseif ele.type == "picbutton" then
        local nTex, pTex = ele.iconNormal, ele.iconPushed
        if ele.atlas then
            nTex = ele.atlas .. "_Normal"; pTex = ele.atlas .. "_Pushed"
        end
        widget = EXUI:CreatePicButton(container, pw, ph, nTex, pTex, ele.iconHighlight, function()
            if ele.key and moduleKey then
                ExwindTools:UpdateState(moduleKey .. ".ButtonClicked",
                    { key = ele.key, fullPath = fullPath, ts = GetTime() })
            end
        end)
    elseif ele.type == "checkbox" then
        widget = EXUI:CreateCheckbox(container, ele.label, curVal == true, function(v)
            Setter(v == true)
        end)
    elseif ele.type == "slider" then
        widget = EXUI:CreateSlider(container, pw, ele.label, ele.min or 0, ele.max or 100, curVal or 0, ele.step or 1,
            nil, {
                onLive = LiveSetter,
                onCommit = Setter,
            })
    elseif ele.type == "input" then
        widget = EXUI:CreateEditBox(container, curVal or "", pw, ph, ele.label, {
            onChanged = nil,
            onEnter = Setter,
            onEditFocusLost = Setter,
            labelPos = ele.labelPos,
            labelSize = ele.labelSize
        })
    elseif ele.type == "color" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateColorButton(container, ele.label, subConfig, ele.key, true, function()
            NotifyCompositeWrite(moduleKey, fullPath)
        end)
    elseif ele.type == "label" or ele.type == "description" then
        local text = ele.label
        if type(text) == "function" then text = text() end

        widget = EXUI:CreateDescription(container, text or "", pw)

        widget.text:ClearAllPoints()
        widget.text:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
        widget.text:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)
        widget.text:SetJustifyH("LEFT")
        widget.text:SetJustifyV("TOP")
        widget.text:SetWordWrap(ele.wordWrap ~= false)
        if widget.text.SetMaxLines then
            widget.text:SetMaxLines(tonumber(ele.maxLines) or 0)
        end
        widget.text:SetText(text or "")
        widget.labelText = widget.text -- 兼容

        -- [v4.3.13] 支持 tooltip
        BindTooltip(widget, ele, true)
    elseif ele.type == "card" then
        widget = EXUI:CreateCard(container, pw, ph)
        ReleaseCardOutline(widget)

        local title = ele.title
        if title == nil or title == "" then
            title = ele.label or ""
        end
        if type(title) == "function" then
            title = title()
        end
        local desc = ele.desc
        if desc == nil or desc == "" then
            desc = ele.descriptionText or ""
        end
        if type(desc) == "function" then
            desc = desc()
        end

        local padding = math.max(0, tonumber(ele.padding) or 12)
        local leftInset = padding + 8

        -- Grid Card 原生支持标题图标：调用方只提供 titleIcon 图片路径。
        -- 图标尺寸、左侧留白、文字间距和与标题底边对齐均在这里统一处理。
        local titleIcon = ele.titleIcon
        if type(titleIcon) == "function" then
            titleIcon = titleIcon()
        end
        local hasTitleIcon = type(titleIcon) == "string" and titleIcon ~= ""
        local titleIconSize = 22
        local titleIconLeft = 14
        local titleIconGap = 4
        local titleLeftInset = leftInset
        if hasTitleIcon and widget.Title then
            titleLeftInset = math.max(leftInset, titleIconLeft + titleIconSize + titleIconGap)
        end

        if widget.Title then
            widget.Title:ClearAllPoints()
            widget.Title:SetPoint("TOPLEFT", titleLeftInset, -padding)
            widget.Title:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -padding, -padding)
            widget.Title:SetText(tostring(title or ""))
        end

        if hasTitleIcon and widget.Title then
            if not widget.TitleIcon then
                widget.TitleIcon = EXUI:CreateVisualTexture(widget, EXBASEFRAME)
            end
            widget.TitleIcon:ClearAllPoints()
            widget.TitleIcon:SetSize(titleIconSize, titleIconSize)
            widget.TitleIcon:SetPoint("BOTTOMLEFT", widget.Title, "BOTTOMLEFT", titleIconLeft - titleLeftInset, 0)
            widget.TitleIcon:SetTexture(titleIcon)
            widget.TitleIcon:Show()
        elseif widget.TitleIcon then
            widget.TitleIcon:Hide()
        end
        if widget.Desc then
            widget.Desc:ClearAllPoints()
            if widget.Title then
                widget.Desc:SetPoint("TOPLEFT", widget.Title, "BOTTOMLEFT", 0, -6)
            else
                widget.Desc:SetPoint("TOPLEFT", widget, "TOPLEFT", leftInset, -padding)
            end
            widget.Desc:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -padding, 0)
            widget.Desc:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", padding, padding)
            widget.Desc:SetText(tostring(desc or ""))
        end

        if ele.mouse == true then
            if widget.EnableMouse then
                widget:EnableMouse(true)
            end
        else
            if widget.EnableMouse then
                widget:EnableMouse(false)
            end
        end

        if widget.SetFrameStrata then
            widget:SetFrameStrata("LOW")
        end
        if widget.SetFrameLevel then
            widget:SetFrameLevel(math.max(0, (container:GetFrameLevel() or 0) - 5))
        end

        if ele.frameLevelOffset and widget.SetFrameLevel then
            widget:SetFrameLevel((container:GetFrameLevel() or 0) + tonumber(ele.frameLevelOffset))
        end
    elseif ele.type == "custom" then
        local rendererKey = ele.renderer or ele.customType or ele.widgetType
        local renderer
        if ele._tableControls then
            rendererKey = ele._tableControls
            renderer = self.TableControls and self.TableControls[rendererKey]
            if not renderer then error("[ExwindGrid] missing table control factory", 0) end
        else renderer = self:GetCustomRenderer(rendererKey) end
        if renderer then
            local EXFactory = _G.ExwindFactory
            if EXFactory then
                widget = EXFactory:Acquire("GridCustomHost", container)
                widget._gridType = "GridCustomHost"
            else
                widget = CreateFrame("Frame", nil, container, "BackdropTemplate")
            end

            -- 自定义渲染器由对象池复用，必须在每次挂载时恢复当前 Grid 容器的
            -- strata/level，不能保留上一页的 LOW/MEDIUM 层级。
            if widget.SetFrameStrata then
                widget:SetFrameStrata(container:GetFrameStrata() or "MEDIUM")
            end
            if widget.SetFrameLevel then
                widget:SetFrameLevel((container:GetFrameLevel() or 0) + 1)
            end

            local ctx = {
                grid = self,
                widget = widget,
                element = ele,
                container = container,
                config = config,
                moduleKey = moduleKey,
                fullPath = fullPath,
                contextPath = contextPath,
                currentValue = curVal,
                setter = Setter,
                value = curVal,
                _layoutWidth = pw,
                _layoutHeight = ph,
            }

            -- Card custom content keeps the established renderer signature, but
            -- receives geometry notification helpers through the same ctx.  The
            -- owner lookup is container-scoped so pooled custom hosts never keep
            -- a previous card/session closure after ReleaseContainerWidgets.
            local cardOwner = self.CardSessionOwners[container]
            if cardOwner and cardOwner.session and cardOwner.card then
                local contentGeneration = cardOwner.card.contentGeneration
                local function IsCurrentCardContent()
                    return not cardOwner.session.released
                        and cardOwner.card.contentGeneration == contentGeneration
                end
                ctx.session = cardOwner.session
                ctx.cardId = cardOwner.card.id
                ctx.pageId = cardOwner.session.context and cardOwner.session.context.pageId
                ctx.regionId = cardOwner.session.context and cardOwner.session.context.regionId
                ctx.IsCurrent = IsCurrentCardContent
                local activeSetter = ctx.setter
                ctx.setter = function(first, second)
                    if not IsCurrentCardContent() then return false end
                    local value
                    if first == ctx then value = second else value = first end
                    return activeSetter(value)
                end
                ctx.SetContentHeight = function(first, second)
                    if not IsCurrentCardContent() then return false end
                    local height
                    if first == ctx then height = second else height = first end
                    return cardOwner.session:_SetReportedContentHeight(cardOwner.card,
                        ele._exCardSourceItem or ele, height)
                end
                ctx.GetContentWidth = function()
                    if not IsCurrentCardContent() then return 0 end
                    return tonumber(ctx._layoutWidth) or pw
                end
                ctx.RequestReflow = function()
                    if not IsCurrentCardContent() then return false end
                    return self:RequestReflow(container)
                end
            end

            if widget._customRendererKey ~= rendererKey and widget._customRenderer and type(widget._customRenderer.release) == "function" then
                local released, releaseReason = pcall(widget._customRenderer.release,
                    widget, widget._customContext)
                if not released then
                    widget._customRenderer = nil
                    widget._customRendererKey = nil
                    widget._customContext = nil
                    local cleaned, cleanupReason = pcall(self.ReleaseWidgetInstance, self, widget)
                    if not cleaned then
                        error(tostring(releaseReason) .. "; stale custom cleanup failed: "
                            .. tostring(cleanupReason), 0)
                    end
                    error(releaseReason, 0)
                end
            end

            widget._customRenderer = renderer
            widget._customRendererKey = rendererKey
            widget._customContext = ctx

            if type(renderer.mount) == "function" then
                local mounted, mountReason = pcall(renderer.mount, widget, ctx)
                if not mounted then
                    local cleaned, cleanupReason = pcall(self.ReleaseWidgetInstance, self, widget)
                    if not cleaned then
                        error(tostring(mountReason) .. "; custom cleanup failed: "
                            .. tostring(cleanupReason), 0)
                    end
                    error(mountReason, 0)
                end
            end
        else
            widget = EXUI:CreateHeader(container, L["未注册的自定义组件"], pw)
        end
    elseif ele.type == "dropdown" or ele.type == "select" then
        local rawItems = ele.items
        if rawItems == nil and type(ele.options) == "table" then
            rawItems = {}
            local optionKeys = {}
            for value in pairs(ele.options) do optionKeys[#optionKeys + 1] = value end
            table.sort(optionKeys, function(a, b) return tostring(a) < tostring(b) end)
            for _, value in ipairs(optionKeys) do
                rawItems[#rawItems + 1] = { ele.options[value], value }
            end
        end
        local itemsList = {}
        local function ParseInlineDropdownItems(rawText)
            local parsed = {}
            for s in string.gmatch(rawText or "", "([^,]+)") do
                local value, display = s:match("^([^:]+):(.+)$")
                if value and display then
                    table.insert(parsed, { display, value })
                else
                    table.insert(parsed, s)
                end
            end
            return parsed
        end

        if type(rawItems) == "string" and rawItems:sub(1, 5) == "func:" then
            local funcPath = rawItems:match("func:(.+%(%))") or rawItems:sub(6)
            funcPath = funcPath:gsub("%(%)", "")
            local func = _G
            for part in string.gmatch(funcPath, "([^%.]+)") do
                if func then func = func[part] else break end
            end
            local dynamicData = (type(func) == "function" and func()) or "Run_Time_Generated"
            if type(dynamicData) == "table" then
                itemsList = dynamicData
            else
                itemsList = ParseInlineDropdownItems(dynamicData)
            end
        else
            if type(rawItems) == "table" then
                itemsList = rawItems
            elseif type(rawItems) == "string" then
                itemsList = ParseInlineDropdownItems(rawItems)
            end
        end

        widget = EXUI:CreateDropdown(container, pw, ele.label, itemsList, curVal, Setter, ele)
    elseif ele.type == "multiselect" then
        local itemsList = {}
        -- (Complex items logic omitted for brevity, use existing)
        local rawItems = ele.items
        if type(rawItems) == "string" and rawItems:sub(1, 5) == "func:" then
            local funcPath = rawItems:match("func:(.+%(%))") or rawItems:sub(6)
            funcPath = funcPath:gsub("%(%)", "") -- clean ()
            local func = _G
            for part in string.gmatch(funcPath, "([^%.]+)") do
                if func then func = func[part] else break end
            end
            local dynamicStr = (type(func) == "function" and func()) or "Run_Time_Generated"
            for s in string.gmatch(dynamicStr, "([^,]+)") do table.insert(itemsList, s) end
        else
            if type(rawItems) == "table" then
                itemsList = rawItems
            elseif type(rawItems) == "string" then
                for s in string.gmatch(rawItems, "([^,]+)") do table.insert(itemsList, s) end
            end
        end

        if not curVal then
            SetConfigValue(config, ele, {}, moduleKey, fullPath, "silent"); curVal = GetConfigPath(config, fullPath)
        end
        -- Multiselect 的回调比较特殊，它不需要传值，而是当内部状态变更时触发 StateUpdate
        widget = EXUI:CreateMultiSelectDropdown(container, pw, ele.label, itemsList, curVal, function()
            NotifyCompositeWrite(moduleKey, fullPath)
        end, ele)
    elseif ele.type == "itemenabled"
        or ele.type == "itemquantity" or ele.type == "itemdelete" then
        if type(curVal) ~= "table" then
            invalidItemRecord = true
            local text = "—"
            widget = EXUI:CreateDescription(container, text, pw)
        elseif ele.type == "itemenabled" then
            widget = EXUI:CreateCheckbox(container, ele.label or "", curVal.enabled == true, function(value)
                curVal.enabled = value == true
                Setter(curVal)
            end)
            widget._exGridRefreshItemRecordCell = function(self)
                self:SetChecked(curVal.enabled == true)
            end
        elseif ele.type == "itemquantity" then
            widget = EXUI:CreateEditBox(container, tostring(curVal.quantity or 1), pw, GM.size.inputHeight, nil, {})
            widget:SetJustifyH("CENTER")
            widget:SetNumeric(true)
            -- Preserve the original ItemConfig Enter/focus-loss write order,
            -- including ClearFocus before the Enter handler's same-record Setter.
            widget:SetScript("OnEnterPressed", function(self)
                curVal.quantity = tonumber(self:GetText()) or 1
                self:ClearFocus()
                Setter(curVal)
            end)
            widget:SetScript("OnEditFocusLost", function(self)
                curVal.quantity = tonumber(self:GetText()) or 1
                Setter(curVal)
            end)
            widget._exGridRefreshItemRecordCell = function(self)
                self:SetText(tostring(curVal.quantity or 1))
            end
        else
            if ele.canDelete ~= true then
                error("[ExwindGrid] item delete requires the original delete permission", 2)
            end
            widget = EXUI:CreateButton(container, pw, ph, "×", function()
                if moduleKey then
                    ExwindTools:UpdateState(moduleKey .. ".ItemConfigDelete", { key = dataKey })
                end
                if type(ele.onDelete) == "function" then ele.onDelete(curVal, config) end
            end, { variant = "danger", compact = true })
        end
    elseif ele.type == "segmented" then
        widget = EXUI:CreateSegmentedControl(container, pw, ele.items or {}, curVal, Setter)
    elseif ele.type == "previewcanvas" then
        local elements = type(curVal) == "table" and curVal or (ele.elements or {})
        widget = EXUI:CreatePreviewCanvas(container, pw, ph, elements, {
            onSelect = ele.onSelect,
            onMove = function(key, relX, relY)
                local target = type(elements[key]) == "table" and elements[key] or nil
                if target then target.x, target.y = relX, relY end
                NotifyCompositeWrite(moduleKey, fullPath)
                if ele.onMove then ele.onMove(key, relX, relY, elements) end
            end,
        })
    elseif ele.type == "tabgroup" then
        widget = EXUI:CreateTabGroup(container, {
            width = pw,
            items = ele.items or {},
            value = curVal,
            disabled = ele.disabled,
            sizing = ele.sizing,
            minItemWidth = ele.minItemWidth,
            itemHeight = ele.itemHeight,
            onChange = Setter,
        })
    elseif ele.type == "lsm_font" then
        widget = EXUI:CreateLSMDropdown(container, "font", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_sound" then
        widget = EXUI:CreateLSMSoundDropdown(container, pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_texture" then
        widget = EXUI:CreateLSMTextureDropdown(container, "statusbar", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_border" then
        widget = EXUI:CreateLSMTextureDropdown(container, "border", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "lsm_background" then
        widget = EXUI:CreateLSMTextureDropdown(container, "background", pw, ele.label, curVal, Setter, ele)
    elseif ele.type == "fontgroup" then
        if not curVal then
            local defaultFontTable = { font = "Friz Quadrata TT", size = 14, r = 1, g = 1, b = 1, a = 1, outline = "", shadow = false, x = 0, y = 0 }
            Setter(defaultFontTable)
            curVal = defaultFontTable
        end
        local fontGroupWidth = pw
        widget = EXUI:CreateFontGroup(container, fontGroupWidth, ele.label, curVal, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = fontGroupWidth
    elseif ele.type == "glow_settings" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateGlowSettings(container, pw, ele.label, subConfig, ele.key,
            function() NotifyCompositeWrite(moduleKey, fullPath) end,
            BuildCompositeOptions(ele.opts, moduleKey, fullPath))
    elseif ele.type == "widgetlayout" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        local layoutWidth = pw
        widget = EXUI:CreateWidgetLayoutGroup(container, layoutWidth, ele.label, subConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = layoutWidth
    elseif ele.type == "modulecommonsettings" then
        local commonConfig = config
        if contextPath then
            commonConfig = GetConfigPath(config, contextPath) or config
        end
        local bindKey = (type(ele.opts) == "table" and ele.opts.bindRoot == true) and nil or ele.key
        local commonPath = bindKey and fullPath or (contextPath or "")
        local commonOpts = BuildCompositeOptions(ele.opts, moduleKey, commonPath)
        -- 新增元素的 key 是编辑器唯一生成的；仅这类背景卡片允许 Grid h 覆盖
        -- 内容 Flow 的高度，正式模块通用设置组继续自动测高。
        if type(ele.key) == "string" and ele.key:match("^modulecommonsettings_%d+$") then
            commonOpts.gridEditableHeight = true
        end
        widget = EXUI:CreateModuleCommonSettingsGroup(container, pw, ele.label, commonConfig, bindKey, function() NotifyCompositeWrite(moduleKey, commonPath) end, commonOpts)
        widget._exGridWidth = pw
    elseif ele.type == "anchorgroup" then
        local anchorConfig = config
        if contextPath then
            anchorConfig = GetConfigPath(config, contextPath) or config
        end
        local bindRoot = type(ele.opts) == "table" and ele.opts.bindRoot == true
        local bindKey = nil
        local migratedLegacyInput = false
        if bindRoot then
            migratedLegacyInput = MigrateLegacyDirectAnchorInput(anchorConfig, ele.key, ele.opts)
        else
            bindKey = ele.key
        end
        local anchorPath = fullPath
        if not bindKey then
            local targetKey = type(ele.opts) == "table" and ele.opts.attachTargetKey or nil
            targetKey = type(targetKey) == "string" and targetKey ~= "" and targetKey or "customAttachTarget"
            anchorPath = contextPath and (contextPath .. "." .. targetKey) or targetKey
        end
        widget = EXUI:CreateAnchorGroup(container, pw, ele.label, anchorConfig, bindKey, function() NotifyCompositeWrite(moduleKey, anchorPath) end, BuildCompositeOptions(ele.opts, moduleKey, anchorPath))
        widget._exGridWidth = pw
        if migratedLegacyInput then
            NotifyCompositeWrite(moduleKey, anchorPath)
        end
    elseif ele.type == "texturegroup" then
        local bindValue = type(ele.opts) == "table" and ele.opts.bindValue == true
        local subConfig = bindValue and curVal or config
        if not bindValue and contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        local textureWidth = pw
        widget = EXUI:CreateTextureGroup(container, textureWidth, ele.label, subConfig,
            bindValue and nil or ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end,
            BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = textureWidth
    elseif ele.type == "icongroup" then
        local bindRoot = type(ele.opts) == "table" and ele.opts.bindRoot == true
        local bindValue = type(ele.opts) == "table" and ele.opts.bindValue == true
        -- bindRoot is a persistence contract, not merely a key-elision hint:
        -- a root-bound IconGroup must receive the page binding root even if a
        -- surrounding Grid context path is present.
        local subConfig = bindValue and curVal or config
        if not bindValue and not bindRoot and contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        -- Composite groups normally own a nested table named after their Grid
        -- key.  Some pages (EXAura B1/C1) deliberately bind the icon visual
        -- directly to the supplied display root instead.  Mirror the
        -- established modulecommonsettings/anchorgroup bindRoot contract so
        -- this never creates a synthetic `display.icon` table.
        -- Lua 的 `condition and nil or fallback` 会永远落到 fallback；
        -- root 绑定必须显式保留 nil，不能把 Grid key "icon" 传进去。
        local bindKey = nil
        if not bindRoot and not bindValue then bindKey = ele.key end
        local iconGroupWidth = pw
        local iconPath = bindValue and fullPath or (bindKey and fullPath or (contextPath or ""))
        widget = EXUI:CreateIconGroup(container, iconGroupWidth, ele.label, subConfig, bindKey, function() NotifyCompositeWrite(moduleKey, iconPath) end, BuildCompositeOptions(ele.opts, moduleKey, iconPath))
        widget._exGridWidth = iconGroupWidth
    elseif ele.type == "soundgroup" then
        local subConfig = config
        if contextPath then
            subConfig = GetConfigPath(config, contextPath) or config
        end
        widget = EXUI:CreateSoundGroup(container, pw, ele.label, subConfig, ele.key, function() NotifyCompositeWrite(moduleKey, fullPath) end, BuildCompositeOptions(ele.opts, moduleKey, fullPath))
        widget._exGridWidth = pw
    elseif ele.type == "timerBarGroup" or ele.type == "timerbargroup" then
        -- The timer-bar composite has the same root-binding contract as the
        -- icon composite.  In root mode its defaults and all edits apply to
        -- `config` itself, never to an incidental table named after the Grid
        -- component (for example display.timerBar).
        local bindRoot = type(ele.opts) == "table" and ele.opts.bindRoot == true
        if bindRoot then
            curVal = config
        end
        if not curVal then
            local defaultTimerTable = {
                width = 240,
                height = 24,
                texture = "Clean",
                barColorR = 1,
                barColorG = 0.7,
                barColorB = 0,
                barColorA = 1,
                barBgColorR = 0,
                barBgColorG = 0,
                barBgColorB = 0,
                barBgColorA = 0.5,
                showIcon = true,
                iconSide = "LEFT",
                iconWidth = 24,
                iconHeight = 24,
                iconOffsetX = -5,
                iconOffsetY = 0,
            }
            Setter(defaultTimerTable)
            curVal = defaultTimerTable
        end
        local timerBarGroupWidth = pw
        local timerBarPath = bindRoot and (contextPath or "") or fullPath
        widget = EXUI:CreateTimerBarGroup(container, timerBarGroupWidth, ele.label, curVal, nil, function() NotifyCompositeWrite(moduleKey, timerBarPath) end, BuildCompositeOptions(ele.opts, moduleKey, timerBarPath))
        widget._exGridWidth = timerBarGroupWidth
    end

    if widget then
        widget:SetParent(container)
        if ele.type ~= "card" and widget.SetFrameStrata then
            widget:SetFrameStrata(container:GetFrameStrata() or "MEDIUM")
        end
        if ele.type ~= "card" and widget.SetFrameLevel then
            widget:SetFrameLevel((container:GetFrameLevel() or 0) + 1)
        end
        if widget.checkbox then
            if widget.checkbox.SetFrameStrata then
                widget.checkbox:SetFrameStrata(container:GetFrameStrata() or "MEDIUM")
            end
            if widget.checkbox.SetFrameLevel then
                widget.checkbox:SetFrameLevel((widget:GetFrameLevel() or 0) + 1)
            end
        end
        -- 下拉菜单的 logical h 仍用于 Grid 的占位/碰撞计算；但 DropdownButton
        -- 的物理高度由模板固定，不能被 h 拉伸（箭头与背景切片不会等比例缩放）。
        -- 其余控件继续使用原本的全尺寸行为。
        -- 所有 Grid 元素均为静态 GUI；这里是唯一最终落点，不能再按 schema
        -- 的 pixelPerfect 标记分裂成两条布局链。
        widget._exGridPixelElement = ele
        self:ApplyPixelLayout(widget, container, ele)

        if ele.type == "custom" and widget._customRenderer then
            widget._customContext = widget._customContext or {}
            widget._customContext.currentValue = curVal
            widget._customContext.value = curVal
            local updated, updateReason = true
            if type(widget._customRenderer.update) == "function" then
                updated, updateReason = pcall(widget._customRenderer.update,
                    widget, widget._customContext)
            elseif type(widget._customRenderer.render) == "function" then
                updated, updateReason = pcall(widget._customRenderer.render,
                    widget, widget._customContext)
            end
            if not updated then
                local cleaned, cleanupReason = pcall(self.ReleaseWidgetInstance, self, widget)
                if not cleaned then
                    error(tostring(updateReason) .. "; custom cleanup failed: "
                        .. tostring(cleanupReason), 0)
                end
                error(updateReason, 0)
            end
        end

        if ele.frameLevelOffset and widget.SetFrameLevel then
            widget:SetFrameLevel((container:GetFrameLevel() or 0) + tonumber(ele.frameLevelOffset))
        end

        if ele.type == "checkbox" or ele.type == "itemenabled" then
            if widget.EnableMouse then
                widget:EnableMouse(false)
            end
            -- 这些槽位上挂着 Core 的 checkbox 画器（本体 OnLeave 负责 pressed
            -- 复位）。裸 SetScript(nil) 会把画器连同安装记录的「已装」状态一起
            -- 留成不一致，下面的 ApplyControlAppearance 就补不回来；走
            -- ClearControlScript 同时丢掉记录，画器正好在那一步重装。
            EXUI:ClearControlScript(widget, "OnEnter")
            EXUI:ClearControlScript(widget, "OnLeave")
            if widget.checkbox then
                if widget.checkbox.EnableMouse then
                    widget.checkbox:EnableMouse(true)
                end
                EXUI:ClearControlScript(widget.checkbox, "OnEnter")
                EXUI:ClearControlScript(widget.checkbox, "OnLeave")
                EXUI:ClearControlScript(widget.checkbox, "PreClick")
                EXUI:ClearControlScript(widget.checkbox, "PostClick")
            end
        end

        widget:Show()
        if ele.disabled ~= nil and widget.SetDisabled then
            widget:SetDisabled(ele.disabled == true)
        elseif ele.disabled == true then
            if widget.checkbox and widget.checkbox.Disable then widget.checkbox:Disable()
            elseif widget.SetEnabled then widget:SetEnabled(false)
            elseif widget.Disable then widget:Disable() end
        elseif ele.disabled == false then
            if widget.checkbox and widget.checkbox.Enable then widget.checkbox:Enable()
            elseif widget.SetEnabled then widget:SetEnabled(true)
            elseif widget.Enable then widget:Enable() end
        end
        -- [v4.3.1] 映射到池类型
        local EXFactory = _G.ExwindFactory
        local gridType = ele.type == "select" and "dropdown" or ele.type
        if invalidItemRecord then gridType = "description"
        elseif gridType == "itemenabled" then gridType = "checkbox"
        elseif gridType == "itemquantity" then gridType = "input"
        elseif gridType == "itemdelete" then gridType = "button" end
        if EXFactory and EXFactory.GridTypeMap then
            widget._gridType = EXFactory.GridTypeMap[gridType] or gridType
        else
            widget._gridType = gridType
        end
        self.Widgets[ele.key] = widget
        self.WidgetInstances = self.WidgetInstances or {}
        self.WidgetInstances[#self.WidgetInstances + 1] = widget

        -- [v2.0] 反向索引注册
        -- 这里我们不再在 Widgets 表里只存 key，而是存下所有 meta 信息
        -- 核心：编辑器交互（拖拽）需要读取这些信息
        if not self.WidgetMap then self.WidgetMap = {} end
        -- [v4.3 Fix] 移除 parentContainer 引用，避免循环引用导致内存泄漏
        -- 所有 widget 都同一个 container 下，无需单独存储
        self.WidgetMap[widget] = {
            item = ele,     -- 引用 Layout Item
            path = fullPath -- 完整数据路径
        }

        widget._exLabelWrap = (ele.labelWrap == true)
        widget._exLabelMaxLines = tonumber(ele.labelMaxLines) or nil

        if ele.type ~= "card" and ele.type ~= "custom" then
            EXUI:UpdateLabelStyle(widget, ele.labelSize, ele.labelPos)
        end
        if EXUI.ApplyControlAppearance then EXUI:ApplyControlAppearance(widget) end

        if self.IsLiveEditing and (self.LiveEditContainer or self.LiveContainer) == container then
            self:WrapWidgetForEdit(widget, ele.key, container)
        end
    end

    return widget
end

-- =========================================================
-- Settings lists only arrange existing controls. Their owners, parents,
-- configuration references and callbacks remain outside this presentation API.
-- =========================================================
do
    local sessions = setmetatable({}, { __mode = "k" })
    local SettingsListMixin = {}

    local function IsSettingsDescription(widget, allowBareRegion)
        if not widget then return false end
        if widget.IsObjectType and widget:IsObjectType("FontString") then return allowBareRegion ~= false end
        local text = widget.text
        return (widget._gridType == "GridDescription" or widget._gridType == "label")
            and widget._fromPool == "GridDescription"
            and text and text.IsObjectType and text:IsObjectType("FontString") or false
    end

    -- [WEB-REQ 28] 普通行右侧控件的最小可用宽（窄栏下文字列收窄/控件换行的依据）；
    -- 整行、特殊 profile（EXBoss 技能行）与非矩形控件返回 nil，沿用旧算法。
    local function SettingsRowControlMinWidth(widget, ordinaryControl, row)
        if row.fullWidth == true or not widget then return nil end
        if ordinaryControl then
            return widget._gridType == "GridSlider" and GM.size.settingsRowSliderMinWidth
                or GM.size.settingsRowControlMinWidth
        end
        if widget._gridType == "GridButton" then return GM.size.settingsRowControlMinWidth end
        return nil
    end

    local function IsOrdinarySettingsControl(widget)
        if not widget then return false end
        local kind = widget._gridType
        if kind == "GridInput" then
            return widget.IsObjectType and widget:IsObjectType("EditBox")
                and widget.IsMultiLine and not widget:IsMultiLine()
        end
        return kind == "GridDropdown" or kind == "GridLSMDropdown" or kind == "GridMultiselect"
            or kind == "GridColorButton" or kind == "GridSlider"
    end

    -- Input must be the current unscaled available width, never a previous result.
    function Grid:ResolveSettingsListWidth(rawAvailableWidth, percent)
        local width = math.max(1, tonumber(rawAvailableWidth) or 1)
        percent = percent == nil and 75 or percent
        if type(percent) ~= "number" or percent ~= percent or percent <= 0 or percent > 100 then
            error("[ExwindGrid] settingsListWidthPercent must be a finite number in (0, 100]", 2)
        end
        return math.max(1, math.floor(width * (percent / 100) + 0.5))
    end

    function Grid:GetSettingsListSession(parent)
        local session = parent and sessions[parent]
        return session and not session.released and session or nil
    end

    function SettingsListMixin:ScheduleDeferredCardHoverRefresh(widgets)
        if self.released or not (_G.C_Timer and type(_G.C_Timer.After) == "function") then return end
        local owner = self.grid.CardSessionOwners[self.parent]
        local cardSession = owner and owner.session
        local request = self.cardHoverRefreshRequest
        if request then
            request.widgets = widgets
            return
        end
        request = {
            widgets = widgets, parent = self.parent,
            cardSession = cardSession, generation = cardSession and cardSession.generation,
        }
        self.cardHoverRefreshRequest = request
        _G.C_Timer.After(0, function()
            if self.released or sessions[request.parent] ~= self
                or self.cardHoverRefreshRequest ~= request then return end
            self.cardHoverRefreshRequest = nil
            local currentOwner = self.grid.CardSessionOwners[request.parent]
            local currentSession = currentOwner and currentOwner.session
            if currentSession ~= request.cardSession or (currentSession
                and (currentSession.released or currentSession.generation ~= request.generation)) then
                self.cardHoverRefreshNeeded = nil
                return
            end
            -- A later stable layout consumes this request if another layout
            -- is already pending. This callback never polls or reschedules itself.
            if self.busy or (currentSession and (currentSession.reflowBusy
                or currentSession.reflowPending or currentSession.reflowScheduled)) then return end
            self.cardHoverRefreshNeeded = nil
            self:RefreshCardVisuals(false, request.widgets)
        end)
    end

    function SettingsListMixin:RefreshCardVisuals(allowDeferred, expectedWidgets)
        if self.released then return end
        local widgets, needsDeferred = {}, false
        local function Refresh(widget)
            if not widget or widget._exSettingsPresentation ~= "card" then return end
            local expected = expectedWidgets and expectedWidgets[widget]
            if expectedWidgets and (not expected or widget:GetParent() ~= expected.parent
                or widget.checkbox ~= expected.checkbox
                or widget._exSettingsListVisualState ~= expected.visualState) then return end
            if allowDeferred == false then
                EXUI:RefreshSettingsListCardHoverVisual(widget)
                return
            end
            local _, wasPending = EXUI:RefreshSettingsListCardVisual(widget)
            needsDeferred = needsDeferred or wasPending
            widgets[widget] = {
                parent = widget:GetParent(), checkbox = widget.checkbox,
                visualState = widget._exSettingsListVisualState,
            }
        end
        for _, entry in ipairs(self.entries) do
            Refresh(entry.widget)
            for _, control in ipairs(entry.controls or entry.cells or {}) do
                Refresh(control.widget)
            end
        end
        if allowDeferred ~= false then
            self.cardHoverRefreshNeeded = self.cardHoverRefreshNeeded or needsDeferred
            if self.cardHoverRefreshNeeded then self:ScheduleDeferredCardHoverRefresh(widgets) end
        end
    end

    local function LayoutSettingsList(session, width)
        width = math.max(1, tonumber(width) or session.parent:GetWidth())
        if session.headerlessColumns then
            session.columnRects = EXUI:ResolveSettingsTableColumns(width, session.headerlessColumns)
        end
        for _, saved in ipairs(session.suppressedDividers or {}) do saved.widget:Hide() end
        for _, entry in ipairs(session.entries) do
            if entry.widget then
                entry.visible = entry.widget:IsShown()
            elseif entry.controls or entry.cells then
                local hasWidget, shown = false, false
                for _, control in ipairs(entry.controls or entry.cells) do
                    if control.widget then
                        hasWidget = true
                        shown = shown or control.widget:IsShown()
                    end
                end
                entry.visible = not hasWidget or shown
            else
                entry.visible = true
            end
        end
        local nextRow, nextSection = false, nil
        for index = #session.entries, 1, -1 do
            local entry = session.entries[index]
            if entry.visible then
                if not entry.informational and (entry.widget or entry.controls or entry.cells) then
                    EXUI:SetSettingsRowLast(entry.host,
                        session.showDividers == false or not nextRow or nextSection ~= entry.section)
                    nextRow, nextSection = true, entry.section
                else
                    nextRow, nextSection = false, nil
                end
            end
        end
        local y = 0
        for _, entry in ipairs(session.entries) do
            entry.host:SetShown(entry.visible)
            if entry.visible then
            local rowWidth = math.max(1, width - (entry.indent or 0))
            local height
            if entry.tableHeader then
                height, session.columnRects = EXUI:UpdateSettingsTableHeaderLayout(entry.host, rowWidth)
            elseif entry.cells then
                local metrics = {}
                for index, cell in ipairs(entry.cells) do
                    metrics[index] = {
                        height = cell.widget and cell.widget:GetHeight() or 0,
                        visible = not cell.widget or cell.widget:IsShown(),
                    }
                end
                local rects
                height, rects = EXUI:UpdateSettingsTableRowLayout(
                    entry.host, rowWidth, session.columnRects, metrics)
                for index, cell in ipairs(entry.cells) do
                    if cell.widget and cell.widget:IsShown() then
                        cell.widget:SetWidth(rects[index].width)
                        if cell.ordinaryControl then
                            EXUI:UpdateSettingsListControlLayout(cell.widget, rects[index].width)
                            if cell.widget._gridType == "GridButton" then
                                EXUI:ApplyControlAppearance(cell.widget)
                            end
                            metrics[index].height = cell.widget:GetHeight()
                        end
                        local textRegion = cell.widget.text
                            or (cell.widget.GetStringHeight and cell.widget)
                        if cell.role == "tableText" and textRegion then
                            local measuredHeight = math.max(cell.borrowedKind == "text" and 1 or GM.size.checkboxRowHeight, textRegion:GetStringHeight())
                            cell.widget:SetHeight(measuredHeight)
                            metrics[index].height = measuredHeight
                        elseif cell.widget._gridType == "GridDescription" and cell.widget.text then
                            local measuredHeight = math.max(cell.height, cell.widget.text:GetStringHeight())
                            cell.widget:SetHeight(measuredHeight)
                            metrics[index].height = measuredHeight
                        end
                    end
                end
                height, rects = EXUI:UpdateSettingsTableRowLayout(
                    entry.host, rowWidth, session.columnRects, metrics)
                for index, cell in ipairs(entry.cells) do
                    if cell.widget and cell.widget:IsShown() then
                        cell.widget:ClearAllPoints()
                        cell.widget:SetPoint("TOPLEFT", entry.host, "TOPLEFT", rects[index].x, -rects[index].y)
                    end
                end
            elseif entry.controls then
                local metrics = {}
                -- 选项块（card）的文字区 = 宽度 - 左 14 - 右 30（右侧给蓝色对勾角标），
                -- 所以自然宽必须按文字实际宽度算；同一行所有选项块取同一个最大值，保持等宽。
                -- 这个自然宽同时就是选项块的请求宽度：选项块不参与剩余空间平分，
                -- 否则一行只放得下一个，整行被单个块吃满。
                local cardNaturalWidth
                for _, control in ipairs(entry.controls) do
                    if control.presentation == "card" and control.widget:IsShown() then
                        local card = control.widget.checkbox._exSettingsCardSurface
                        local natural = 14 + (control.widget._exSettingsCardIcon and 24 or 0)
                            + math.ceil(card.Title:GetUnboundedStringWidth()) + 30
                        cardNaturalWidth = math.max(cardNaturalWidth or 0, natural)
                    end
                end
                for index, control in ipairs(entry.controls) do
                    local naturalWidth = control.presentation == "card"
                        and cardNaturalWidth or control.preparedWidth
                    metrics[index] = {
                        minWidth = control.presentation == "card" and cardNaturalWidth or nil,
                        widget = entry.specializationControlsLayout and control.widget or nil,
                        slotKind = entry.specializationControlsLayout,
                        height = control.widget:GetHeight(),
                        role = control.role,
                        presentation = control.presentation,
                        align = control.align,
                        visible = control.widget:IsShown(),
                        width = (control.requestedWidth == "content" and naturalWidth
                            or control.requestedWidth)
                            or (control.presentation == "card" and naturalWidth or nil),
                    }
                end
                local rects
                local fit
                height, rects, fit = EXUI:UpdateSettingsRowControlsLayout(entry.host, rowWidth, metrics,
                    entry.htmlControlsLayout and width or nil)
                if entry.specializationControlsLayout and fit and not fit.fits then
                    local message = string.format("specialization row %s requires %.1f width; available %.1f; preserving full labels and controls without wrapping",
                        tostring(entry.label or ""), fit.requiredWidth, fit.availableWidth)
                    if entry.widthDiagnostic ~= message then
                        entry.widthDiagnostic = message
                        local owner = session.grid.CardSessionOwners[session.parent]
                        if owner and owner.session then
                            owner.session:_Diagnostic(owner.card,
                                "specialization-width:" .. tostring(entry.host), message)
                        elseif _G.print then
                            _G.print("[ExwindGrid] " .. message)
                        end
                    end
                end
                for index, control in ipairs(entry.controls) do
                    local widget = control.widget
                    if widget:IsShown() then
                    widget:SetWidth(rects[index].width)
                    local measuredHeight = metrics[index].height
                    if widget._gridType == "GridDescription" and widget.text then
                        measuredHeight = math.max(control.height, widget.text:GetStringHeight())
                        widget:SetHeight(measuredHeight)
                    elseif control.role == "label" and widget.IsObjectType
                        and widget:IsObjectType("FontString") then
                        measuredHeight = math.max(1, math.ceil(widget:GetStringHeight()))
                        widget:SetHeight(measuredHeight)
                    elseif session.presentationProfile == "exbossSkill" and entry.htmlControlsLayout
                        and control.role == "label" and widget._gridType == "GridCheckbox" and widget.label then
                        -- Only the row reserves wrapped label space. The original
                        -- checkbox and its GM.size.checkboxRowHeight control body keep their size.
                        measuredHeight = math.max(GM.size.checkboxRowHeight, math.ceil(widget.label:GetStringHeight()))
                        metrics[index].labelBodyHeight = widget:GetHeight()
                    end
                    metrics[index].height = measuredHeight
                    end
                end
                height, rects = EXUI:UpdateSettingsRowControlsLayout(entry.host, rowWidth, metrics,
                    entry.htmlControlsLayout and width or nil)
                for index, control in ipairs(entry.controls) do
                    if control.widget:IsShown() then
                    local rect = rects[index]
                    local labelBodyHeight = metrics[index].labelBodyHeight
                    local labelOffset = labelBodyHeight
                        and math.max(0, (rect.height - labelBodyHeight) * 0.5) or 0
                    control.widget:ClearAllPoints()
                    control.widget:SetPoint("TOPLEFT", entry.host, "TOPLEFT", rect.x, -(rect.y + labelOffset))
                    end
                end
            elseif entry.informational then
                height = EXUI:UpdateSettingsSectionLayout(entry.host, rowWidth)
            elseif entry.widget then
                local widget = entry.widget
                if widget._exSettingsPresentation == "card" then
                    local inset, titleHeight = 10, 38
                    local description = entry.descriptionWidget
                    local cardHeight = titleHeight
                    widget:SetWidth(rowWidth)
                    if description and description:IsShown() then
                        local text = description.text or description.labelText
                        local descriptionWidth = math.max(1, rowWidth - 48)
                        description:SetWidth(descriptionWidth)
                        text:SetWidth(descriptionWidth)
                        local descriptionHeight = math.max(1, math.ceil(text:GetStringHeight()))
                        description:SetSize(descriptionWidth, descriptionHeight)
                        description:ClearAllPoints()
                        description:SetPoint("TOPLEFT", widget, "TOPLEFT", 38, -titleHeight)
                        description:SetFrameLevel(widget.checkbox:GetFrameLevel() + 2)
                        cardHeight = titleHeight + descriptionHeight + inset
                    end
                    widget:SetHeight(cardHeight)
                    widget:ClearAllPoints()
                    widget:SetPoint("TOPLEFT", entry.host, "TOPLEFT", 0, -4)
                    height = cardHeight + 8
                    entry.host:SetSize(rowWidth, height)
                    if entry.host._exSettingsRowDivider then entry.host._exSettingsRowDivider:Hide() end
                else
                local controlHeight = math.max(1, widget:GetHeight())
                local x, controlY, controlWidth
                height, x, controlY, controlWidth = EXUI:UpdateSettingsRowLayout(
                    entry.host, rowWidth, controlHeight, entry.descriptionWidget)
                widget:SetWidth(controlWidth)
                if entry.reflowComposite and type(widget._exCompositeReflow) == "function" then
                    EXUI:LayoutCompositeGroup(widget, widget:GetWidth(), controlHeight)
                end
                if entry.valuePosition or entry.ordinaryControl then
                    EXUI:UpdateSettingsListControlLayout(widget, controlWidth)
                end
                -- Re-read geometry after the existing presentation reflow;
                -- this layer never calls a value refresh or a data callback.
                controlHeight = math.max(1, widget:GetHeight())
                height, x, controlY, controlWidth = EXUI:UpdateSettingsRowLayout(
                    entry.host, rowWidth, controlHeight, entry.descriptionWidget)
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", entry.host, "TOPLEFT", x, -controlY)
                end
            else
                height = EXUI:UpdateSettingsSectionLayout(entry.host, rowWidth)
            end
            entry.host:ClearAllPoints()
            entry.host:SetPoint("TOPLEFT", session.parent, "TOPLEFT", entry.indent or 0, -y)
            y = y + math.max(0, height or 0) + entry.gap
            end
        end
        session.height = math.max(1, y)
        if not session.grid.CardSessionOwners[session.parent] then
            session.parent:SetHeight(session.height)
            session:RefreshCardVisuals()
        end
        return session.height
    end

    function SettingsListMixin:Relayout(width, cardVisualReflow)
        if self.released then return self.height or 1 end
        if self.visualLayoutBusy then return self.height or 1 end
        if self.busy then
            if cardVisualReflow then
                self.relayoutPending = true
                if width ~= nil then self.relayoutPendingWidth = width end
            end
            return self.height or 1
        end
        local result
        -- A final card paint can discover its new natural width after the
        -- first measurement. Consume that visual request once, without timers
        -- or recursive layout; the second pass measures the stored new width.
        for pass = 1, 2 do
            self.busy = true
            local ok
            ok, result = pcall(LayoutSettingsList, self, width)
            self.busy = nil
            local pending, pendingWidth = self.relayoutPending, self.relayoutPendingWidth
            self.relayoutPending, self.relayoutPendingWidth = nil, nil
            if not ok then error(result, 0) end
            if not pending or self.released then break end
            width = pendingWidth or width
        end
        -- Optional owner geometry runs synchronously after the standard rows.
        -- Keep the layout guard held: sizing an existing frame may invoke its
        -- size handler, but must never start another list layout from here.
        if not self.released and type(self.onVisualLayout) == "function" then
            self.busy, self.visualLayoutBusy = true, true
            local ok, height = pcall(self.onVisualLayout, self, width, result)
            self.busy, self.visualLayoutBusy = nil, nil
            if not ok then error(height, 0) end
            if not self.released and type(height) == "number" and height == height
                and height > 0 and height < math.huge then
                self.height, result = height, height
            end
        end
        return result
    end

    function SettingsListMixin:Release()
        if self.released then return end
        self.released = true
        self.onVisualLayout, self.visualLayoutBusy = nil, nil
        local function ReleaseVisibilityOwner(widget)
            if widget and widget._exSettingsListVisibilityOwner == self then
                widget._exSettingsListVisibilityOwner = nil
            end
        end
        if self.summaryEnabled then
            local saved = self.summaryEnabled
            local widget = saved.widget
            widget._exGridBossSummaryEnabled = nil
            EXUI:RestoreSettingsListControl(widget)
            widget:ClearAllPoints()
            widget:SetParent(saved.parent)
            widget:SetSize(saved.width, saved.height)
            for _, point in ipairs(saved.points) do widget:SetPoint(unpack(point)) end
            widget:SetShown(saved.shown)
            self.summaryEnabled = nil
        end
        self.relayoutPending, self.relayoutPendingWidth = nil, nil
        self.cardHoverRefreshRequest, self.cardHoverRefreshNeeded = nil, nil
        sessions[self.parent] = nil
        for _, saved in ipairs(self.suppressedDividers or {}) do saved.widget:SetShown(saved.shown) end
        for _, saved in ipairs(self.externalDescriptions or {}) do
            local widget = saved.widget
            ReleaseVisibilityOwner(widget)
            EXUI:RestoreSettingsListControl(widget)
            widget:ClearAllPoints()
            widget:SetSize(saved.width, saved.height)
            for _, point in ipairs(saved.points) do widget:SetPoint(unpack(point)) end
        end
        for _, entry in ipairs(self.entries) do
            if entry.descriptionWidget then
                local widget = entry.descriptionWidget
                ReleaseVisibilityOwner(widget)
                EXUI:RestoreSettingsListControl(widget)
                widget:ClearAllPoints()
                widget:SetSize(entry.descriptionWidth, entry.descriptionHeight)
                if entry.descriptionFrameLevel then widget:SetFrameLevel(entry.descriptionFrameLevel) end
                for _, point in ipairs(entry.descriptionPoints) do widget:SetPoint(unpack(point)) end
            end
            for _, cell in ipairs(entry.cells or {}) do
                if cell.widget then
                    ReleaseVisibilityOwner(cell.widget)
                    EXUI:RestoreSettingsListControl(cell.widget)
                    cell.widget:ClearAllPoints()
                    cell.widget:SetSize(cell.width, cell.height)
                    for _, point in ipairs(cell.points) do cell.widget:SetPoint(unpack(point)) end
                end
            end
            for _, control in ipairs(entry.controls or {}) do
                local widget = control.widget
                ReleaseVisibilityOwner(widget)
                EXUI:RestoreSettingsListControl(widget)
                widget:ClearAllPoints()
                widget:SetSize(control.width, control.height)
                for _, point in ipairs(control.points) do widget:SetPoint(unpack(point)) end
            end
            if entry.widget then
                local widget = entry.widget
                ReleaseVisibilityOwner(widget)
                EXUI:RestoreSettingsListControl(widget)
                widget:ClearAllPoints()
                widget:SetSize(entry.width, entry.height)
                for _, point in ipairs(entry.points) do
                    widget:SetPoint(unpack(point))
                end
            end
            entry.host:Release()
        end
        if self.card then EXUI:RestoreSettingsListCard(self.card) end
        self.headerlessColumns, self.columnRects = nil, nil
        self.entries = {}
    end

    function Grid:MountSettingsList(parent, declaration)
        if not parent or type(declaration) ~= "table" then
            error("[ExwindGrid] settings list requires a parent and presentation declaration", 2)
        end
        if declaration.showDividers ~= nil and type(declaration.showDividers) ~= "boolean" then
            error("[ExwindGrid] settings list showDividers must be boolean", 2)
        end
        if self:GetSettingsListSession(parent) then
            error("[ExwindGrid] release the existing settings list before mounting", 2)
        end
        if declaration.presentationProfile ~= nil and declaration.presentationProfile ~= "exbossSkill" then
            error("[ExwindGrid] unsupported settings-list presentationProfile", 2)
        end
        local seen = {}
        for _, widget in ipairs(declaration.externalDescriptionWidgets or {}) do
            if not IsSettingsDescription(widget) or widget:GetParent() ~= parent or seen[widget] then
                error("[ExwindGrid] external descriptions require unique original same-parent text controls", 2)
            end
            seen[widget] = true
        end
        for _, section in ipairs(declaration.sections or {}) do
            for _, row in ipairs(section.rows or {}) do
                if row.controlsLayout ~= nil then
                    local specialization = row.controlsLayout == "specQueue" or row.controlsLayout == "specAlpha"
                    local html = row.controlsLayout == "fieldRow" or row.controlsLayout == "compactVoice"
                    if (not specialization and not html)
                        or type(row.controls) ~= "table" or row.cells or row.widget or row.subtitle
                        or row.fullWidth or row.description ~= nil or row.descriptionWidget
                        or row.informational or row.presentation or row.controlWidth
                        or row.inputWidthPercent or row.valuePosition then
                        error("[ExwindGrid] controlsLayout requires an ordinary controls row and a supported layout", 2)
                    end
                    local labels = 0
                    for _, control in ipairs(row.controls) do
                        local widget = control.widget
                        local input = widget and widget._gridType == "GridInput" and widget.IsMultiLine
                            and not widget:IsMultiLine() and widget.label
                        local slider = widget and widget._gridType == "GridSlider" and widget.Title
                            and widget.numberInput
                        if specialization and ((row.controlsLayout == "specQueue" and not input)
                            or (row.controlsLayout == "specAlpha" and not slider)
                            or control.width ~= nil or control.role ~= nil or control.presentation ~= nil
                            or control.align ~= nil or control.hideLabel == true) then
                            error("[ExwindGrid] specialization slots require original inputs/sliders with their visible labels and no size/style overrides", 2)
                        end
                        if control.role == "label" then labels = labels + 1 end
                    end
                    if html then
                        local first = row.controls[1]
                        if labels ~= 1 or not first or first.role ~= "label" or not first.widget
                            or first.widget._gridType ~= "GridCheckbox" or first.hideLabel == true
                            or (row.label ~= nil and row.label ~= "") then
                            error("[ExwindGrid] HTML controls rows require their original checkbox as the sole first label", 2)
                        end
                        if row.controlsLayout == "fieldRow" and (#row.controls < 2 or #row.controls > 3) then
                            error("[ExwindGrid] fieldRow requires a label and one or two original controls", 2)
                        end
                        if row.controlsLayout == "compactVoice" then
                            local source, preview = row.controls[2], row.controls[#row.controls]
                            if #row.controls < 4 or not source.widget or source.widget._gridType ~= "GridDropdown"
                                or not preview.widget or preview.widget._gridType ~= "GridButton" then
                                error("[ExwindGrid] compactVoice requires label, source dropdown, original content candidates and final preview button", 2)
                            end
                        end
                    end
                end
                if row.subtitle == nil then
                if row.informational and (not IsSettingsDescription(row.widget) or row.controls
                    or row.cells or row.fullWidth or row.descriptionWidget or row.description ~= nil) then
                    error("[ExwindGrid] informational content requires a single original text control", 2)
                end
                if (row.controls and row.widget) or (row.cells and (row.controls or row.widget)) then
                    error("[ExwindGrid] settings list row must use only one control layout", 2)
                end
                if row.cells and (not declaration.columns or #row.cells ~= #declaration.columns) then
                    error("[ExwindGrid] table row must match its declared columns", 2)
                end
                local controls = row.cells or row.controls or {{ widget = row.widget }}
                if #controls == 0 then error("[ExwindGrid] settings list controls cannot be empty", 2) end
                for _, control in ipairs(controls) do
                    local widget = control.widget
                    if row.cells and control.text ~= nil then
                        if widget or type(control.text) ~= "string" then
                            error("[ExwindGrid] table text cell must contain only visual text", 2)
                        end
                    elseif not widget or not widget.GetParent or widget:GetParent() ~= parent then
                        error("[ExwindGrid] settings list controls must already belong to its parent", 2)
                    elseif seen[widget] then
                        error("[ExwindGrid] a settings list control cannot appear twice", 2)
                    else
                        seen[widget] = true
                    end
                end
                if row.descriptionWidget then
                    local description = row.descriptionWidget
                    if row.controls or row.cells or row.fullWidth or row.description ~= nil
                        or not IsSettingsDescription(description, false)
                        or not description.GetParent or description:GetParent() ~= parent then
                        error("[ExwindGrid] original description requires a same-parent ordinary single-control row", 2)
                    end
                    if seen[description] then
                        error("[ExwindGrid] a settings list control cannot appear twice", 2)
                    end
                    seen[description] = true
                end
                end
            end
        end
        local session = setmetatable({ grid = self, parent = parent, entries = {},
            showDividers = declaration.showDividers,
            presentationProfile = declaration.presentationProfile,
            headerlessColumns = declaration.tableHeader == false and declaration.columns or nil },
            { __index = SettingsListMixin })
        sessions[parent] = session
        local function WatchVisibility(widget)
            if not widget or type(widget.HookScript) ~= "function" then return end
            if not widget._exSettingsListVisibilityHook then
                widget._exSettingsListVisibilityHook = true
                local function Request(control)
                    local owner = control._exSettingsListVisibilityOwner
                    if owner and not owner.released and not owner.busy then
                        if not owner.grid:RequestReflow(owner.parent) then owner:Relayout() end
                    end
                end
                widget:HookScript("OnShow", Request)
                widget:HookScript("OnHide", Request)
            end
            widget._exSettingsListVisibilityOwner = session
        end
        local function AddHeading(options)
            if options.title == nil and options.description == nil then return end
            local host = EXUI:CreateSettingsSection(parent, options)
            session.entries[#session.entries + 1] = { host = host, gap = 8 }
        end
        local ok, reason = pcall(function()
            session.suppressedDividers = {}
            session.externalDescriptions = {}
            for _, widget in ipairs(declaration.externalDescriptionWidgets or {}) do
                local saved = { widget = widget, width = widget:GetWidth(), height = widget:GetHeight(), points = {} }
                session.externalDescriptions[#session.externalDescriptions + 1] = saved
                for index = 1, widget:GetNumPoints() do saved.points[index] = { widget:GetPoint(index) } end
                EXUI:PrepareSettingsListControl(widget, {
                    role = "description", descriptionFontSize = declaration.externalDescriptionFontSize,
                })
                WatchVisibility(widget)
            end
            AddHeading({ title = declaration.title, description = declaration.description,
                descriptionWidgets = declaration.headingDescriptionWidgets, kind = "page" })
            if declaration.columns and declaration.tableHeader ~= false then
                local host = EXUI:CreateSettingsTableHeader(parent, { columns = declaration.columns })
                session.entries[#session.entries + 1] = { host = host, tableHeader = true, gap = 0 }
            end
            for _, section in ipairs(declaration.sections or {}) do
                AddHeading({ title = section.title, description = section.description, kind = "section" })
                for rowIndex, row in ipairs(section.rows or {}) do
                    local informational = row.informational == true
                        or (row.allowInformationFallback ~= false and not row.children
                            and (row.indent == nil or row.indent == 0)
                            and row.fullWidth == true and (row.label == nil or row.label == "")
                            and row.description == nil and not row.descriptionWidget
                            and not row.controls and not row.cells and IsSettingsDescription(row.widget))
                    if row.subtitle ~= nil then
                        local host = EXUI:CreateSettingsSection(parent, {
                            kind = "subsection", title = row.subtitle,
                        })
                        session.entries[#session.entries + 1] = {
                            host = host, gap = 0, indent = row.indent, section = section,
                        }
                    elseif row.widget and row.widget._gridType == "GridDivider"
                        and not row.controls and not row.cells and not row.descriptionWidget then
                        session.suppressedDividers[#session.suppressedDividers + 1] = {
                            widget = row.widget, shown = row.widget:IsShown(),
                        }
                        row.widget:Hide()
                    else
                    local widget = row.widget
                    local ordinaryControl = not row.fullWidth and not informational
                        and not row.controls and not row.cells
                        and row.presentation ~= "card" and row.presentation ~= "switch"
                        and IsOrdinarySettingsControl(widget)
                    local staticCells = {}
                    for index, cell in ipairs(row.cells or {}) do staticCells[index] = cell.text ~= nil and cell or nil end
                    local specializationLayout = row.controlsLayout == "specQueue" or row.controlsLayout == "specAlpha"
                    local htmlLayout = row.controlsLayout == "fieldRow" or row.controlsLayout == "compactVoice"
                    local host = informational and EXUI:CreateSettingsSection(parent, {
                        kind = "information", descriptionWidgets = { widget },
                        presentationProfile = session.presentationProfile,
                    }) or row.cells and EXUI:CreateSettingsTableRow(parent, {
                        staticCells = staticCells, isLast = rowIndex == #section.rows,
                    }) or EXUI:CreateSettingsRow(parent, {
                        presentationProfile = session.presentationProfile,
                        label = row.label, description = row.description,
                        contentWidth = specializationLayout and "intrinsic" or nil,
                        singleLineControls = specializationLayout,
                        htmlControlsLayout = htmlLayout and row.controlsLayout or nil,
                        controlWidth = row.controlWidth,
                        controlKind = ordinaryControl and "ordinary" or nil,
                        controlMinWidth = SettingsRowControlMinWidth(widget, ordinaryControl, row),
                        inputWidthPercent = row.inputWidthPercent,
                        fullWidth = row.fullWidth == true,
                        isLast = rowIndex == #section.rows,
                    })
                    local entry = { host = host, gap = 0, indent = row.indent, section = section,
                        informational = informational, ordinaryControl = ordinaryControl, omitEmpty = row.omitEmpty == true,
                        specializationControlsLayout = specializationLayout and row.controlsLayout or nil,
                        htmlControlsLayout = htmlLayout and row.controlsLayout or nil, label = row.label }
                    session.entries[#session.entries + 1] = entry
                    if row.descriptionWidget then
                        local description = row.descriptionWidget
                        entry.descriptionWidget, entry.descriptionPoints = description, {}
                        entry.descriptionWidth, entry.descriptionHeight = description:GetWidth(), description:GetHeight()
                        entry.descriptionFrameLevel = description:GetFrameLevel()
                        for index = 1, description:GetNumPoints() do
                            entry.descriptionPoints[index] = { description:GetPoint(index) }
                        end
                        EXUI:PrepareSettingsListControl(description, { role = "description" })
                        WatchVisibility(description)
                    end
                    if row.cells then
                        entry.cells = {}
                        for _, cell in ipairs(row.cells) do
                            local control = cell.widget
                            local saved = { text = cell.text, widget = control,
                                borrowedKind = cell.borrowedKind,
                                ordinaryControl = cell.ordinaryControl }
                            entry.cells[#entry.cells + 1] = saved
                            if control then
                                saved.role = (IsSettingsDescription(control, false) or cell.borrowedKind == "text") and "tableText" or nil
                                saved.width, saved.height, saved.points = control:GetWidth(), control:GetHeight(), {}
                                for index = 1, control:GetNumPoints() do
                                    saved.points[index] = { control:GetPoint(index) }
                                end
                                EXUI:PrepareSettingsListControl(control, {
                                    hideLabel = cell.hideLabel ~= false and saved.role ~= "tableText", role = saved.role,
                                    presentation = cell.presentation,
                                    ordinaryControl = cell.ordinaryControl,
                                    valuePosition = cell.valuePosition,
                                    borrowedKind = cell.borrowedKind,
                                })
                                WatchVisibility(control)
                            end
                        end
                    elseif row.controls then
                        entry.controls = {}
                        for _, spec in ipairs(row.controls) do
                            local control = spec.widget
                            local saved = { widget = control, requestedWidth = spec.width, presentation = spec.presentation,
                                role = spec.role,
                                align = spec.align,
                                width = control:GetWidth(), height = control:GetHeight(), points = {} }
                            for index = 1, control:GetNumPoints() do
                                saved.points[index] = { control:GetPoint(index) }
                            end
                            entry.controls[#entry.controls + 1] = saved
                            EXUI:PrepareSettingsListControl(control, {
                                presentation = spec.presentation,
                                cardIcon = spec.cardIcon,
                                cardCheckSize = spec.cardCheckSize, cardTextSize = spec.cardTextSize,
                                width = spec.width,
                                role = spec.role,
                                hideLabel = spec.hideLabel == true,
                            })
                            WatchVisibility(control)
                            saved.preparedWidth = control:GetWidth()
                        end
                    else
                        entry.widget, entry.points = widget, {}
                        entry.reflowComposite = row.fullWidth == true and type(widget._exCompositeReflow) == "function"
                        entry.valuePosition = row.fullWidth ~= true and widget._gridType == "GridSlider"
                            and (row.valuePosition or "right") or nil
                        entry.width, entry.height = widget:GetWidth(), widget:GetHeight()
                        for index = 1, widget:GetNumPoints() do
                            entry.points[index] = { widget:GetPoint(index) }
                        end
                        EXUI:PrepareSettingsListControl(widget, {
                            ordinaryControl = ordinaryControl,
                            role = informational and "description" or nil,
                            descriptionFontSize = informational and row.descriptionFontSize or nil,
                            hideLabel = not informational and row.fullWidth ~= true and row.label ~= nil,
                            presentation = row.presentation,
                            cardDescription = row.presentation == "card" and row.descriptionWidget ~= nil,
                            cardIcon = row.cardIcon,
                            cardCheckSize = row.cardCheckSize, cardTextSize = row.cardTextSize,
                            valuePosition = entry.valuePosition,
                        })
                        WatchVisibility(widget)
                    end
                    end
                end
            end
            self:EnsurePixelLayoutHooks(parent)
            session:Relayout()
        end)
        if not ok then
            session:Release()
            error(reason, 0)
        end
        return session
    end

    function Grid:MountDeclaredSettingsLists(cardSession, declaration)
        local hasSettingsList = false
        local pageDescriptions, pageKeysByCard = {}, {}
        for _, spec in ipairs(declaration.settingsPageDescriptions or {}) do
            local owner = cardSession.byId[spec.card]
            if not owner or not owner.definition.settingsList or spec.key == nil then
                error("[ExwindGrid] page descriptions require an existing settings-list card", 2)
            end
            local keys = pageKeysByCard[spec.card] or {}
            pageKeysByCard[spec.card] = keys
            keys[#keys + 1] = spec.key
        end
        cardSession.settingsGroups = {}
        local groupIds = {}
        for _, definition in ipairs(declaration.settingsGroups or {}) do
            if not definition.id or groupIds[definition.id] then
                error("[ExwindGrid] settings group requires a unique id", 2)
            end
            groupIds[definition.id] = true
            local group = {
                members = {}, title = definition.title,
                collapsible = definition.collapsible ~= false,
            }
            cardSession.settingsGroups[#cardSession.settingsGroups + 1] = group
            for index, cardId in ipairs(definition.cards or {}) do
                local member = cardSession.byId[cardId]
                if not member or not member.definition.settingsList or member.settingsGroup then
                    error("[ExwindGrid] settings group requires unique existing settings-list cards", 2)
                end
                group.members[index] = member
                member.settingsGroup, member.settingsGroupIndex = group, index
            end
            if #group.members == 0 then
                error("[ExwindGrid] settings group must contain an existing card", 2)
            end
            local firstPlacement = group.members[1].definition.placement
            if not firstPlacement and group.members[1].previous ~= nil then
                error("[ExwindGrid] first settings group member requires an explicit placement", 2)
            end
            local firstTarget = firstPlacement and cardSession.byId[firstPlacement.target]
            if firstTarget and firstTarget.settingsGroup == group then
                error("[ExwindGrid] first settings group member must target outside its group", 2)
            end
            if definition.table ~= nil then
                if type(definition.table) ~= "table" or type(definition.table.columns) ~= "table"
                    or #definition.table.columns == 0 or group.collapsible then
                    error("[ExwindGrid] shared table requires columns and a non-collapsible group", 2)
                end
                for key in pairs(definition.table) do
                    if key ~= "columns" then
                        error("[ExwindGrid] shared table accepts only shared columns", 2)
                    end
                end
                group.tableColumns = definition.table.columns
                group.anchorMember = group.members[1]
                local addMember, records = nil, {}
                for _, member in ipairs(group.members) do
                    local list = member.definition.settingsList
                    if list.columns ~= nil or list.tableHeader ~= nil then
                        error("[ExwindGrid] shared table members cannot override columns or headers", 2)
                    end
                    if list.supportsAdd ~= nil and type(list.supportsAdd) ~= "boolean" then
                        error("[ExwindGrid] supportsAdd must be boolean", 2)
                    end
                    if list.supportsAdd then
                        if addMember or type(list.rows) ~= "table" or #list.rows ~= 1 then
                            error("[ExwindGrid] shared table supports one original add row in one member", 2)
                        end
                        addMember = member
                    else
                        records[#records + 1] = member
                    end
                end
                -- Reorder presentation references only; original cards, widgets and DB contexts stay put.
                group.members = {}
                if addMember then group.members[1] = addMember end
                for _, member in ipairs(records) do group.members[#group.members + 1] = member end
                for index, member in ipairs(group.members) do member.settingsGroupIndex = index end
            end
        end
        for _, definition in ipairs(declaration.cards) do
            local presentation = definition.settingsList
            if presentation then
                hasSettingsList = true
                local cardState = cardSession.byId[definition.id]
                local tableGroup = cardState.settingsGroup and cardState.settingsGroup.tableColumns
                    and cardState.settingsGroup
                local addRow = tableGroup and presentation.supportsAdd == true
                if presentation.supportsAdd ~= nil and not tableGroup then
                    error("[ExwindGrid] supportsAdd requires a shared table group", 2)
                end
                local rows, covered = {}, {}
                local externalDescriptions, sectionDescriptions = {}, {}
                local summaryWidget, summaryHost
                if presentation.summaryEnabled ~= nil then
                    local region = cardSession.context.regionId
                    if presentation.summaryEnabled ~= true or definition.id ~= "master"
                        or (region ~= "boss-spell-editor" and region ~= "trash-spell-editor")
                        or cardState.settingsGroup or cardState.content.kind ~= "grid" then
                        error("[ExwindGrid] summaryEnabled is reserved for the two EXBoss master controls", 2)
                    end
                    for key in pairs(presentation) do
                        if key ~= "summaryEnabled" then
                            error("[ExwindGrid] summaryEnabled cannot be combined with settings-list rows or styles", 2)
                        end
                    end
                    local items = cardState.content.items
                    if type(items) ~= "table" or #items ~= 1
                        or items[1].key ~= "enabled" or items[1].type ~= "checkbox" then
                        error("[ExwindGrid] summaryEnabled requires only the original enabled checkbox", 2)
                    end
                    summaryWidget = cardSession:GetWidget("master", "enabled")
                    summaryHost = cardSession.context.exbossSummaryEnableHost
                    if not summaryWidget or summaryWidget._gridType ~= "GridCheckbox"
                        or summaryWidget:GetParent() ~= cardState.body
                        or (type(summaryHost) ~= "table" and type(summaryHost) ~= "userdata")
                        or type(summaryHost.GetObjectType) ~= "function"
                        or summaryHost:GetObjectType() ~= "Frame" then
                        error("[ExwindGrid] summaryEnabled requires its original checkbox and an existing summary Frame", 2)
                    end
                    if #(pageKeysByCard[definition.id] or {}) > 0 then
                        error("[ExwindGrid] summaryEnabled cannot also supply page descriptions", 2)
                    end
                    covered[summaryWidget] = true
                    cardState.summaryEnabled = true
                    cardSession.exbossSummaryEnabled = true
                end
                local function ResolveDescription(key, target)
                    local widget = cardSession:GetWidget(definition.id, key)
                    if not IsSettingsDescription(widget) or widget:GetParent() ~= cardState.body or covered[widget] then
                        error("[ExwindGrid] heading descriptions require unique original same-card text controls", 2)
                    end
                    covered[widget] = true
                    externalDescriptions[#externalDescriptions + 1] = widget
                    target[#target + 1] = widget
                end
                for _, key in ipairs(pageKeysByCard[definition.id] or {}) do ResolveDescription(key, pageDescriptions) end
                for _, key in ipairs(presentation.descriptionKeys or {}) do ResolveDescription(key, sectionDescriptions) end
                local function ResolveRow(row, child)
                    if tableGroup then
                        if type(row.cells) ~= "table" or #row.cells ~= #tableGroup.tableColumns then
                            error("[ExwindGrid] shared table rows require one cell per shared column", 2)
                        end
                        if addRow then
                            for key in pairs(row) do
                                if key ~= "cells" then
                                    error("[ExwindGrid] shared add row accepts only original control cells", 2)
                                end
                            end
                            for _, cell in ipairs(row.cells) do
                                for key in pairs(cell) do
                                    if key ~= "key" and key ~= "text" then
                                        error("[ExwindGrid] shared add cells cannot override position or style", 2)
                                    end
                                end
                                if cell.text ~= nil and cell.text ~= "" then
                                    error("[ExwindGrid] shared add row permits only empty text placeholders", 2)
                                end
                            end
                        end
                    end
                    if child and (row.children or row.controls or row.cells) then
                        error("[ExwindGrid] settings children support only one level of subtitle or single-control rows", 2)
                    end
                    if row.subtitle ~= nil then
                        if not child or type(row.subtitle) ~= "string" or row.key ~= nil then
                            error("[ExwindGrid] subtitle requires explicit text in a child presentation row", 2)
                        end
                        rows[#rows + 1] = { subtitle = row.subtitle, indent = 20 }
                        return
                    end
                    if row.children and row.key == nil then
                        error("[ExwindGrid] settings children require an original single-control parent row", 2)
                    end
                    if row.informational and (row.children or child or row.fullWidth or row.controls
                        or row.cells or row.descriptionKey ~= nil or row.description ~= nil) then
                        error("[ExwindGrid] informational content requires a standalone original text row", 2)
                    end
                    if (row.controls and row.key ~= nil) or (row.cells and (row.controls or row.key ~= nil)) then
                        error("[ExwindGrid] settings list row must use only key, controls or cells", 2)
                    end
                    local resolved = {
                        label = row.label, description = row.description,
                        controlsLayout = row.controlsLayout,
                        fullWidth = row.fullWidth, presentation = row.presentation,
                        cardIcon = row.cardIcon,
                        cardCheckSize = row.cardCheckSize, cardTextSize = row.cardTextSize,
                        controlWidth = row.controlWidth,
                        inputWidthPercent = row.inputWidthPercent,
                        valuePosition = row.valuePosition,
                        informational = row.informational == true,
                        allowInformationFallback = not row.children and not child,
                        indent = child and 20 or 0,
                    }
                    if row.controls then resolved.controls = {} end
                    if row.cells then resolved.cells = {} end
                    for _, spec in ipairs(row.cells or row.controls or {{ key = row.key }}) do
                        if row.cells and spec.text ~= nil then
                            if spec.key ~= nil or type(spec.text) ~= "string" then
                                error("[ExwindGrid] table text cell must contain only visual text", 2)
                            end
                            resolved.cells[#resolved.cells + 1] = { text = spec.text }
                        else
                            local widget = cardSession:GetWidget(definition.id, spec.key)
                            if not widget then
                                error("[ExwindGrid] settings list widget not found: " .. tostring(spec.key), 2)
                            end
                            if covered[widget] then
                                error("[ExwindGrid] a settings list control cannot appear twice", 2)
                            end
                            if addRow and widget._gridType ~= "GridButton"
                                and not (widget._gridType == "GridInput" and widget.IsMultiLine
                                    and not widget:IsMultiLine()) then
                                error("[ExwindGrid] shared add row requires original single-line inputs and buttons", 2)
                            end
                            covered[widget] = true
                            if row.cells then
                                resolved.cells[#resolved.cells + 1] = {
                                    widget = widget,
                                    presentation = addRow and widget._gridType == "GridButton"
                                        and "primary" or spec.presentation,
                                    ordinaryControl = addRow and true or nil,
                                }
                            elseif row.controls then
                                resolved.controls[#resolved.controls + 1] = {
                                    widget = widget, width = spec.width, presentation = spec.presentation,
                                    cardIcon = spec.cardIcon,
                                    cardCheckSize = spec.cardCheckSize, cardTextSize = spec.cardTextSize,
                                    role = spec.role,
                                    align = spec.align, hideLabel = spec.hideLabel,
                                }
                            else
                                resolved.widget = widget
                            end
                        end
                    end
                    if row.descriptionKey ~= nil then
                        if row.controls or row.cells or row.fullWidth or row.children or child
                            or row.description ~= nil then
                            error("[ExwindGrid] descriptionKey requires an ordinary single-control row without another description or children", 2)
                        end
                        local description = cardSession:GetWidget(definition.id, row.descriptionKey)
                        if not IsSettingsDescription(description, false) then
                            error("[ExwindGrid] descriptionKey must reference an original description control", 2)
                        end
                        if covered[description] then
                            error("[ExwindGrid] a settings list control cannot appear twice", 2)
                        end
                        covered[description] = true
                        resolved.descriptionWidget = description
                    end
                    rows[#rows + 1] = resolved
                    for _, childRow in ipairs(row.children or {}) do ResolveRow(childRow, true) end
                end
                for _, row in ipairs(presentation.rows or {}) do ResolveRow(row, false) end
                local state = self.ContainerStates[cardState.body]
                for _, widget in ipairs(state and state.instances or {}) do
                    if not covered[widget] then
                        error("[ExwindGrid] settings list must include every original card control", 2)
                    end
                end
                cardState.pageDescriptionOnly = #rows == 0 and #externalDescriptions > 0
                    and #sectionDescriptions == 0 and not cardState.settingsGroup
                local groupCollapsible = cardState.settingsGroup and cardState.settingsGroup.collapsible
                if summaryWidget then groupCollapsible = false end
                local flattened, flatReason = EXUI:PrepareSettingsListCard(cardState.card, {
                    presentationProfile = presentation.cardPresentation,
                    descriptionOnly = cardState.pageDescriptionOnly,
                    preserveHeader = not cardState.pageDescriptionOnly and presentation.preserveHeader == true,
                    groupMember = cardState.settingsGroup ~= nil or summaryWidget ~= nil,
                    groupCollapsible = groupCollapsible,
                    collapsed = cardState.settingsGroup ~= nil and cardState.settingsGroup.collapsible
                        and cardState.settingsGroupIndex > 1,
                    isLast = summaryWidget ~= nil or (cardState.settingsGroup ~= nil
                        and cardState.settingsGroupIndex == #cardState.settingsGroup.members),
                })
                if not flattened then
                    error("[ExwindGrid] settings list cannot flatten card " .. definition.id
                        .. ": " .. tostring(flatReason), 2)
                end
                local tableHeader = presentation.tableHeader
                if tableGroup then tableHeader = cardState.settingsGroupIndex == 1 end
                cardState.emptySharedTableMember = tableGroup ~= nil and tableHeader == false
                    and #rows == 0 and #externalDescriptions == 0 and #sectionDescriptions == 0
                local mounted, list = pcall(self.MountSettingsList, self, cardState.body, {
                    showDividers = presentation.showDividers,
                    presentationProfile = presentation.cardPresentation,
                    columns = tableGroup and tableGroup.tableColumns or presentation.columns,
                    tableHeader = tableHeader,
                    externalDescriptionWidgets = externalDescriptions,
                    sections = {{ rows = rows }},
                })
                if not mounted then
                    EXUI:RestoreSettingsListCard(cardState.card)
                    error(list, 0)
                end
                list.card = cardState.card
                if summaryWidget then
                    local saved = {
                        widget = summaryWidget, host = summaryHost, parent = summaryWidget:GetParent(),
                        width = summaryWidget:GetWidth(), height = summaryWidget:GetHeight(),
                        shown = summaryWidget:IsShown(), points = {},
                    }
                    for index = 1, summaryWidget:GetNumPoints() do
                        saved.points[index] = { summaryWidget:GetPoint(index) }
                    end
                    -- The original body remains the sole lifecycle/data owner, even outside its ScrollFrame.
                    list.summaryEnabled = saved
                    EXUI:PrepareSettingsListControl(summaryWidget, {})
                    summaryWidget._exGridBossSummaryEnabled = saved
                    summaryWidget:ClearAllPoints()
                    summaryWidget:SetParent(summaryHost)
                    LayoutBossSummaryEnabled(summaryWidget)
                end
                cardState.settingsDescriptionWidgets = sectionDescriptions
                if not cardState.settingsGroup and not cardState.pageDescriptionOnly
                    and (presentation.title ~= nil or presentation.description ~= nil or #sectionDescriptions > 0) then
                    cardState.settingsSection = EXUI:CreateSettingsSection(cardSession.parent, {
                        kind = "section", title = presentation.title,
                        description = presentation.description,
                        descriptionWidgets = sectionDescriptions,
                    })
                end
            end
        end
        for _, group in ipairs(cardSession.settingsGroups) do
            local descriptions = {}
            for _, member in ipairs(group.members) do
                for _, widget in ipairs(member.settingsDescriptionWidgets or {}) do
                    descriptions[#descriptions + 1] = widget
                end
            end
            group.surface = EXUI:CreateSettingsCardGroupSurface(cardSession.parent, {})
            group.members[1].settingsSection = EXUI:CreateSettingsSection(cardSession.parent, {
                kind = "section", title = group.title,
                descriptionWidgets = descriptions,
            })
        end
        local context = cardSession.context
        cardSession.hasSettingsList = hasSettingsList
        cardSession.settingsPageDescriptionWidgets = pageDescriptions
        local title = context.settingsPageTitle
        local description = context.settingsPageDescription
        if hasSettingsList then
            if title == nil then title = declaration.title end
            if description == nil then description = declaration.description end
        end
        if title ~= nil or description ~= nil or #pageDescriptions > 0 then
            cardSession.settingsHeading = EXUI:CreateSettingsSection(cardSession.parent, {
                kind = "page", title = title, description = description,
                descriptionWidgets = pageDescriptions,
            })
        end
    end
end

-- =========================================================
-- Settings Card containers (gui.version = 1)
-- =========================================================
-- This is an explicit opt-in path. Historical type="card" Grid items remain
-- plain background widgets and are never promoted into content owners.

Grid.CardLayoutDefaults = Grid.CardLayoutDefaults or {
    gap = 12,
    left = 12,
    right = 12,
    top = 0,
    bottom = 0,
}

local CARD_GRID_COLS = 200
-- SettingsCard body 左右各有 12px 内边距；Font/Icon 的窄版内部仍需至少
-- 110px 才能维持两列字段为正宽。用外壳最小 136px 留出边框取整余量。
local CARD_COMPOSITE_MIN_OUTER_WIDTH = 136
local CARD_CONTAINER_TARGET = "$container"
local CARD_POINT_FACTORS = {
    TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}

local CardSessionMixin = {}

local function CopyShallow(source)
    local copy = {}
    for key, value in pairs(type(source) == "table" and source or {}) do
        copy[key] = value
    end
    return copy
end

local function CardLocation(context, cardId)
    context = type(context) == "table" and context or {}
    return tostring(context.pageId or "<page>") .. "/"
        .. tostring(context.regionId or "<region>") .. "/"
        .. tostring(cardId or "<card>")
end

local function ValidateGridCardItems(items, location)
    if type(items) ~= "table" then
        return nil, location .. ": grid content requires an items array"
    end
    for index, item in ipairs(items) do
        local itemLocation = location .. "/item[" .. tostring(index) .. "]"
        if type(item) ~= "table" then
            return nil, itemLocation .. ": item must be a table"
        end
        if type(item.type) ~= "string" or item.type == "" then
            return nil, itemLocation .. ": item.type must be a non-empty string"
        end
        if item.key == nil then
            return nil, itemLocation .. ": item.key is required"
        end
        for _, field in ipairs({ "x", "y", "w", "h" }) do
            if type(item[field]) ~= "number" or item[field] <= 0 then
                return nil, itemLocation .. ": item." .. field .. " must be greater than zero"
            end
        end
        if item.children then
            local ok, reason = ValidateGridCardItems(item.children, itemLocation)
            if not ok then return nil, reason end
        end
    end
    return true
end

local function ValidateCardContent(grid, content, location)
    if type(content) ~= "table" then
        return nil, location .. ": content must be a table"
    end
    local kind = content.kind
    if kind ~= "grid" and kind ~= "composite" and kind ~= "custom" then
        return nil, location .. ": content.kind must be grid, composite, or custom"
    end
    if kind == "grid" then
        if content.component ~= nil or content.renderer ~= nil then
            return nil, location .. ": grid content cannot declare component or renderer"
        end
        if content.ownsScroll ~= nil then
            return nil, location .. ": grid content cannot declare ownsScroll"
        end
        return ValidateGridCardItems(content.items, location)
    end
    if kind == "composite" then
        if content.items ~= nil or content.renderer ~= nil then
            return nil, location .. ": composite content cannot declare items or renderer"
        end
        if content.ownsScroll ~= nil then
            return nil, location .. ": composite content cannot declare ownsScroll"
        end
        if type(content.component) ~= "string" or content.component == "" then
            return nil, location .. ": composite content requires component"
        end
        local component = string.lower(content.component)
        if not grid.CardBodyOnlyComponents[component] then
            return nil, location .. ": composite component does not implement the Card bodyOnly contract: "
                .. tostring(content.component)
        end
        local measures = EXUI and EXUI.GridComponentMeasures
        if type(measures) ~= "table" or type(measures[component]) ~= "function" then
            return nil, location .. ": composite component has no registered Grid measure: "
                .. tostring(content.component)
        end
        if content.key == nil then
            return nil, location .. ": composite content requires key"
        end
        return true
    end
    if content.items ~= nil or content.component ~= nil then
        return nil, location .. ": custom content cannot declare items or component"
    end
    if type(content.renderer) ~= "string" or content.renderer == "" then
        return nil, location .. ": custom content requires renderer"
    end
    if content.ownsScroll ~= nil and type(content.ownsScroll) ~= "boolean" then
        return nil, location .. ": custom content.ownsScroll must be boolean"
    end
    if not grid:GetCustomRenderer(content.renderer) then
        return nil, location .. ": unregistered custom renderer: " .. tostring(content.renderer)
    end
    if content.height ~= nil and (type(content.height) ~= "number" or content.height < 0) then
        return nil, location .. ": custom content.height must be zero or greater"
    end
    if content.height ~= nil and content.measure ~= nil then
        return nil, location .. ": custom content cannot declare both height and measure"
    end
    if content.measure ~= nil and type(content.measure) ~= "function"
        and type(content.measure) ~= "table" and content.measure ~= true then
        return nil, location .. ": custom content.measure must be true, a function, or a table"
    end
    return true
end

function Grid:ValidateCardDeclaration(declaration, context)
    if type(declaration) == "table" and declaration.sections ~= nil then
        return self:ValidateSettingsDeclaration(declaration, context)
    end
    context = type(context) == "table" and context or {}
    if type(declaration) ~= "table" then
        return nil, "[ExwindGrid] settings-card declaration must be a table"
    end
    if declaration.version ~= 1 then
        return nil, "[ExwindGrid] settings-card declaration requires version = 1"
    end
    if declaration.static ~= nil or declaration.fields ~= nil or declaration.groups ~= nil then
        return nil, "[ExwindGrid] settings-card declaration cannot contain legacy static/fields/groups"
    end
    if type(declaration.cards) ~= "table" then
        return nil, "[ExwindGrid] settings-card declaration requires cards"
    end
    local breakpoint = declaration.settingsLayoutBreakpoint
    if breakpoint ~= nil and (type(breakpoint) ~= "number" or breakpoint ~= breakpoint
        or breakpoint <= 0 or breakpoint == math.huge) then
        return nil, "[ExwindGrid] settingsLayoutBreakpoint must be a finite positive number"
    end
    local widthPercent = declaration.settingsListWidthPercent
    if widthPercent ~= nil and (type(widthPercent) ~= "number" or widthPercent ~= widthPercent
        or widthPercent <= 0 or widthPercent > 100) then
        return nil, "[ExwindGrid] settingsListWidthPercent must be a finite number in (0, 100]"
    end

    local arrayCount, maxIndex = 0, 0
    for key in pairs(declaration.cards) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return nil, "[ExwindGrid] settings-card cards must be an ordered array"
        end
        arrayCount = arrayCount + 1
        maxIndex = math.max(maxIndex, key)
    end
    if maxIndex ~= arrayCount then
        return nil, "[ExwindGrid] settings-card cards array cannot contain holes"
    end

    local ids = {}
    for index, definition in ipairs(declaration.cards) do
        local definitionId = type(definition) == "table" and definition.id or nil
        local base = "[ExwindGrid] " .. CardLocation(context, definitionId)
        if type(definition) ~= "table" then
            return nil, base .. ": card entry " .. tostring(index) .. " must be a table"
        end
        if type(definition.id) ~= "string" or definition.id == "" then
            return nil, base .. ": card.id must be a non-empty string"
        end
        if ids[definition.id] then return nil, base .. ": duplicate card.id" end
        ids[definition.id] = true
        if definition.equalHeightGroup ~= nil and (type(definition.equalHeightGroup) ~= "string"
            or definition.equalHeightGroup == "") then
            return nil, base .. ": equalHeightGroup must be a non-empty string"
        end
        local presentation = definition.settingsList
        if type(presentation) == "table" and presentation.cardPresentation ~= nil then
            local region = context.regionId
            local allowedCard = definition.id == "text" or definition.id == "voice"
                or definition.id == "target"
                or (region == "boss-spell-editor" and definition.id == "display")
                or (region == "trash-spell-editor" and definition.id == "cast")
            if presentation.cardPresentation ~= "exbossSkill"
                or (region ~= "boss-spell-editor" and region ~= "trash-spell-editor")
                or not allowedCard or presentation.preserveHeader ~= true
                or presentation.summaryEnabled ~= nil
                or type(definition.content) ~= "table" or definition.content.kind ~= "grid" then
                return nil, base .. ": cardPresentation=exbossSkill requires an approved EXBoss skill card with preserved header"
            end
        end
        for _, field in ipairs({ "icon", "headerIcon" }) do
            local icon = definition[field]
            if icon ~= nil and type(icon) ~= "string" and type(icon) ~= "number" then
                return nil, base .. ": card." .. field .. " must be a string or number"
            end
        end
        if definition.collapsed == true and definition.collapsible ~= true then
            return nil, base .. ": collapsed=true requires collapsible=true"
        end
        if definition.minBodyHeight ~= nil and type(definition.minBodyHeight) ~= "number" then
            return nil, base .. ": minBodyHeight must be a number"
        end
        if definition.maxBodyHeight ~= nil and type(definition.maxBodyHeight) ~= "number" then
            return nil, base .. ": maxBodyHeight must be a number"
        end
        local minimum = definition.minBodyHeight or 0
        local maximum = definition.maxBodyHeight
        if minimum < 0 or (maximum and maximum < 0) or (maximum and minimum > maximum) then
            return nil, base .. ": invalid minBodyHeight/maxBodyHeight"
        end
        local placement = definition.placement
        if placement ~= nil then
            if type(placement) ~= "table" then return nil, base .. ": placement must be a table" end
            local narrow = placement.narrow
            if narrow ~= nil then
                if breakpoint == nil or type(narrow) ~= "table" then
                    return nil, base .. ": placement.narrow requires a table and settingsLayoutBreakpoint"
                end
                for field in pairs(narrow) do
                    if field ~= "target" and field ~= "side" and field ~= "align"
                        and field ~= "gap" and field ~= "width" then
                        return nil, base .. ": unsupported placement.narrow field"
                    end
                end
                if narrow.target ~= nil and type(narrow.target) ~= "string" then
                    return nil, base .. ": placement.narrow.target must be a string"
                end
                if narrow.side ~= nil and narrow.side ~= "below" and narrow.side ~= "right" then
                    return nil, base .. ": placement.narrow.side must be below or right"
                end
                if narrow.align ~= nil and narrow.align ~= "start"
                    and narrow.align ~= "center" and narrow.align ~= "end" then
                    return nil, base .. ": invalid placement.narrow.align"
                end
                if narrow.gap ~= nil and (type(narrow.gap) ~= "number" or narrow.gap ~= narrow.gap
                    or narrow.gap < 0 or narrow.gap == math.huge) then
                    return nil, base .. ": placement.narrow.gap must be finite and nonnegative"
                end
                local width = narrow.width
                if width ~= nil then
                    local value = type(width) == "table" and width.ratio or width
                    if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
                        return nil, base .. ": invalid placement.narrow.width"
                    end
                    if type(width) == "table" then
                        for field in pairs(width) do
                            if field ~= "ratio" and field ~= "offset" then
                                return nil, base .. ": unsupported placement.narrow.width field"
                            end
                        end
                        local offset = width.offset
                        if offset ~= nil and (type(offset) ~= "number" or offset ~= offset
                            or math.abs(offset) == math.huge) then
                            return nil, base .. ": invalid placement.narrow.width.offset"
                        end
                    end
                end
            end
            if placement.rowAfter ~= nil then
                local rowAfter = placement.rowAfter
                if type(rowAfter) ~= "table" or #rowAfter < 1 or #rowAfter > 2
                    or placement.target == nil or placement.target == CARD_CONTAINER_TARGET
                    or (placement.side ~= nil and placement.side ~= "below")
                    or (placement.align ~= nil and placement.align ~= "start") then
                    return nil, base .. ": rowAfter requires one or two card ids and below/start placement"
                end
                local count = 0
                for index, id in pairs(rowAfter) do
                    if type(index) ~= "number" or index ~= math.floor(index) or index < 1
                        or index > #rowAfter or type(id) ~= "string" or id == "" then
                        return nil, base .. ": rowAfter must be an ordered array of card ids"
                    end
                    count = count + 1
                end
                if count ~= #rowAfter then return nil, base .. ": rowAfter cannot contain holes" end
            end
            if placement.target ~= nil and type(placement.target) ~= "string" then
                return nil, base .. ": placement.target must be a string"
            end
            if placement.side ~= nil and placement.side ~= "below" and placement.side ~= "right" then
                return nil, base .. ": placement.side must be below or right"
            end
            if placement.align ~= nil
                and placement.align ~= "start" and placement.align ~= "center" and placement.align ~= "end" then
                return nil, base .. ": placement.align must be start, center, or end"
            end
            if placement.point ~= nil and not CARD_POINT_FACTORS[placement.point] then
                return nil, base .. ": unknown placement.point"
            end
            if placement.relativePoint ~= nil and not CARD_POINT_FACTORS[placement.relativePoint] then
                return nil, base .. ": unknown placement.relativePoint"
            end
            for _, field in ipairs({ "x", "y", "gap" }) do
                if placement[field] ~= nil and type(placement[field]) ~= "number" then
                    return nil, base .. ": placement." .. field .. " must be a number"
                end
            end
            if placement.gap ~= nil and placement.gap < 0 then
                return nil, base .. ": placement.gap cannot be negative"
            end
            local width = placement.width
            if width ~= nil then
                if type(width) == "number" then
                    if width <= 0 then return nil, base .. ": placement.width must be greater than zero" end
                elseif type(width) == "table" then
                    if type(width.ratio) ~= "number" or width.ratio <= 0 then
                        return nil, base .. ": placement.width.ratio must be greater than zero"
                    end
                    if width.offset ~= nil and type(width.offset) ~= "number" then
                        return nil, base .. ": placement.width.offset must be a number"
                    end
                else
                    return nil, base .. ": placement.width must be a number or { ratio, offset }"
                end
            end
        end
        local ok, reason = ValidateCardContent(self, definition.content, base)
        if not ok then return nil, reason end
        if maximum ~= nil
            and not (definition.content.kind == "custom" and definition.content.ownsScroll == true) then
            return nil, base .. ": maxBodyHeight requires custom content with ownsScroll=true"
        end
        if definition.content.kind == "composite" and type(placement) == "table"
            and type(placement.width) == "number"
            and placement.width < CARD_COMPOSITE_MIN_OUTER_WIDTH then
            return nil, base .. ": composite Card width must be at least "
                .. tostring(CARD_COMPOSITE_MIN_OUTER_WIDTH)
        end
    end
    return true
end

local function ResolveCardBinding(session, definition, content)
    local context = session.context
    local bindingName = definition.binding
    if bindingName == nil then bindingName = context.defaultBinding end
    local binding
    if type(bindingName) == "table" then
        binding = bindingName
    elseif bindingName ~= nil then
        binding = type(context.bindings) == "table" and context.bindings[bindingName] or nil
        if not binding then
            error("[ExwindGrid] " .. CardLocation(context, definition.id)
                .. ": binding not found: " .. tostring(bindingName), 0)
        end
    else
        binding = context.binding or context
    end
    if type(binding) ~= "table" then
        error("[ExwindGrid] " .. CardLocation(context, definition.id)
            .. ": binding must be a table", 0)
    end

    local config
    if type(binding.getConfig) == "function" then
        config = binding.getConfig(binding, context, definition.id)
    else
        config = binding.config
    end
    if config == nil and binding == context then config = context.config end
    if config == nil and content.kind == "custom" then
        session._emptyConfig = session._emptyConfig or {}
        config = session._emptyConfig
    end
    if type(config) ~= "table" then
        error("[ExwindGrid] " .. CardLocation(context, definition.id)
            .. ": content binding must resolve to a table", 0)
    end
    return {
        source = binding,
        config = config,
        moduleKey = binding.moduleKey or context.moduleKey,
    }
end

local function BuildCardContentSource(cardState, content)
    if content.kind == "grid" then return content.items end

    local opts = CopyShallow(content.opts)
    if content.kind == "composite" then opts.bodyOnly = true end
    if cardState.session.typedSections and type(content.component) == "string"
        and string.lower(content.component) == "modulecommonsettings" then
        opts.presentation = "settings-list"
        opts._exTypedSettings = true
    end
    local item = {
        type = content.kind == "composite" and string.lower(content.component) or "custom",
        key = content.key or ("__card_custom_" .. cardState.id),
        renderer = content.renderer,
        label = content.label or cardState.definition.title,
        x = 1, y = 1, w = CARD_GRID_COLS, h = 1,
        opts = opts,
        parentKey = content.parentKey,
        subKey = content.subKey,
        setKey = content.setKey,
        _exCardState = cardState,
    }
    if content.kind == "composite" then
        item.measure = true
    elseif content.height ~= nil then
        item.measure = { preferredHeight = content.height, minHeight = content.height }
    elseif content.measure ~= nil then
        item.measure = content.measure
    else
        item.measure = true
    end
    return { item }
end

local function CardContentOwnsScroll(content)
    return type(content) == "table" and content.kind == "custom"
        and content.ownsScroll == true
end

-- Card bodies deliberately do not use CopyMeasuredItems: every relayout starts
-- from the immutable declaration and never accumulates the previous pass's y/h
-- offsets. Fixed Grid rows remain fixed; shared slots contribute one maximum
-- bottom edge instead of being summed repeatedly.
local function BuildCardMeasuredItems(grid, container, sourceItems, config, contextPath, cardState)
    local measured = {}
    for _, source in ipairs(sourceItems or {}) do
        local item = CopyShallow(source)
        item._exCardSourceItem = source
        item._declaredY = math.max(1, tonumber(source.y) or 1)
        item._declaredH = math.max(1, tonumber(source.h) or 1)
        local currentPath = contextPath
        if item.parentKey then
            currentPath = currentPath and (currentPath .. "." .. item.parentKey) or item.parentKey
        end
        local scopedDB = currentPath and GetConfigPath(config, currentPath) or config
        local isEditorModuleCommonCard = item.type == "modulecommonsettings"
            and type(item.key) == "string" and item.key:match("^modulecommonsettings_%d+$") ~= nil
        if isEditorModuleCommonCard then item.measure = false end
        if item.measure == nil and item.type == "modulecommonsettings"
            and type(item.opts) == "table" and (tonumber(item.w) or 0) == grid._effectiveCols then
            item.measure = true
        end
        if item.measure == nil and item.type == "slider" then item.measure = true end

        local pixelHeight
        local reportedHeight = cardState.reportedHeights and cardState.reportedHeights[source]
        if reportedHeight ~= nil then
            pixelHeight = reportedHeight
        else
            local _, _, pixelWidth = grid:GetPixelRect(item.x, item.y, item.w, item.h, container)
            pixelHeight = NormalizeMeasuredHeight(GetMeasureResult(grid, item, pixelWidth, scopedDB))
        end
        if pixelHeight and pixelHeight >= 0 and grid.CellSize > 0 then
            item.h = math.max(1, math.ceil((pixelHeight + grid.Padding) / grid.CellSize))
            item._exMeasuredPixelHeight = pixelHeight
        end
        item._exCardRenderedY = math.max(1, tonumber(item.y) or 1)
        item._exCardRenderedH = math.max(1, tonumber(item.h) or 1)
        if source.children then
            item.children = BuildCardMeasuredItems(grid, container, source.children, config, currentPath, cardState)
        end
        measured[#measured + 1] = item
    end
    return measured
end

local function WalkRenderableCardItems(grid, items, config, contextPath, callback)
    for _, item in ipairs(items or {}) do
        local currentPath = contextPath
        if item.parentKey then
            currentPath = currentPath and (currentPath .. "." .. item.parentKey) or item.parentKey
        end
        if not currentPath or grid:ValidateContext(config, currentPath) then
            if item.type == "TableGroup" then
                if item.label then callback(item, currentPath) end
                if item.children then
                    WalkRenderableCardItems(grid, item.children, config, currentPath, callback)
                end
            else
                callback(item, currentPath)
            end
        end
    end
end

local function CurrentCardItemValue(config, item, fullPath)
    if item.setKey then return config[item.setKey] end
    return GetConfigPath(config, fullPath)
end

local function CardItemIdentity(item, contextPath)
    local function Part(value)
        return type(value) .. ":" .. tostring(value)
    end
    local dataKey = item.subKey or item.key
    local fullPath
    if contextPath then
        fullPath = contextPath .. "." .. tostring(dataKey)
    elseif item.parentKey then
        fullPath = tostring(item.parentKey) .. "." .. tostring(dataKey)
    else
        fullPath = tostring(dataKey)
    end
    return table.concat({
        Part(item.type),
        Part(item.key),
        Part(item.subKey),
        Part(item.setKey),
        Part(item.renderer or item.customType or item.widgetType),
        Part(fullPath),
    }, "\30")
end

local function ReflowCardBody(grid, cardState, bodyWidth)
    local body = cardState.body
    local state = GetContainerState(grid, body)
    grid:SetContainerCols(body, CARD_GRID_COLS)
    grid:SetContainerPadding(body, {
        left = 0,
        right = 0,
        top = cardState.content.kind == "grid" and 12 or 0,
        bottom = 0,
    })
    grid:UpdateMetrics(math.max(1, bodyWidth), body)

    local layout = BuildCardMeasuredItems(grid, body, cardState.sourceItems,
        cardState.binding.config, nil, cardState)
    state.config = cardState.binding.config
    state.moduleKey = cardState.binding.moduleKey

    local renderables = {}
    WalkRenderableCardItems(grid, layout, cardState.binding.config, nil, function(item, contextPath)
        renderables[#renderables + 1] = {
            item = item,
            identity = CardItemIdentity(item, contextPath),
        }
    end)
    if #renderables ~= cardState.renderableCount then
        cardState.session:_Diagnostic(cardState, "structure",
            "content structure changed; call ReplaceCardContent(cardId, content) to rebuild only this card")
        return cardState.lastContentHeight or 0
    end
    for ordinal, entry in ipairs(renderables) do
        if cardState.identityByOrdinal[ordinal] ~= entry.identity then
            cardState.session:_Diagnostic(cardState, "structure",
                "content identity changed; call ReplaceCardContent(cardId, content) to rebuild only this card")
            return cardState.lastContentHeight or 0
        end
    end

    state.layout = layout
    if grid.IsLiveEditing and grid.LiveEditContainer == body then
        grid.ActiveLayout = layout
    end
    local maxBottom = 0
    for ordinal, entry in ipairs(renderables) do
        local item = entry.item
        local widget = cardState.widgetsByOrdinal[ordinal]
        local _, py, pw, ph = grid:GetPixelRect(item.x, item.y, item.w, item.h, body)
        if widget then
            local meta = state.widgetMap and state.widgetMap[widget]
            if meta then meta.item = item end
            if type(widget._exCompositeReflow) == "function" then
                widget._exGridWidth = pw
            end
            widget._exGridCardMeasuredHeight = widget._exGridFixedHeight == nil
                and item._exMeasuredPixelHeight or nil
            widget._exGridPixelElement = item
            grid:ApplyPixelLayout(widget, body, item)
            if item.type == "custom" and widget._customRenderer then
                local ctx = widget._customContext or {}
                ctx._layoutWidth = pw
                ctx._layoutHeight = item._exMeasuredPixelHeight or ph
                if type(widget._customRenderer.layout) == "function" then
                    widget._customRenderer.layout(widget, ctx,
                        ctx._layoutWidth, ctx._layoutHeight)
                end
            end
            local actualHeight = item._exMeasuredPixelHeight
                or widget._exGridFixedHeight
                or (widget.GetHeight and widget:GetHeight())
                or ph
            maxBottom = math.max(maxBottom, -py + math.max(0, tonumber(actualHeight) or ph))
        end
    end
    local settingsList = grid:GetSettingsListSession(body)
    if settingsList then return settingsList:Relayout(bodyWidth) end
    return math.max(0, maxBottom)
end

local function MountCardBody(grid, cardState)
    local body = cardState.body
    local state = GetContainerState(grid, body)
    cardState.contentGeneration = (cardState.contentGeneration or 0) + 1
    grid:ReleaseContainerWidgets(body)
    state.layout = nil
    state.config = cardState.binding.config
    state.moduleKey = cardState.binding.moduleKey
    ActivateContainerState(grid, body, state)
    grid:SetContainerCols(body, CARD_GRID_COLS)
    grid:SetContainerPadding(body, {
        left = 0,
        right = 0,
        top = cardState.content.kind == "grid" and 12 or 0,
        bottom = 0,
    })
    grid:UpdateMetrics(math.max(1, body:GetWidth()), body)
    cardState.widgetsByOrdinal = {}
    cardState.identityByOrdinal = {}
    cardState.renderableCount = 0

    local layout = BuildCardMeasuredItems(grid, body, cardState.sourceItems,
        cardState.binding.config, nil, cardState)
    state.layout = layout
    WalkRenderableCardItems(grid, layout, cardState.binding.config, nil, function(item, contextPath)
        cardState.renderableCount = cardState.renderableCount + 1
        local widget = grid:CreateWidget(body, item, cardState.binding.config,
            cardState.binding.moduleKey, contextPath)
        cardState.widgetsByOrdinal[cardState.renderableCount] = widget or false
        cardState.identityByOrdinal[cardState.renderableCount] = CardItemIdentity(item, contextPath)
    end)
    grid:EnsurePixelLayoutHooks(body)
end

local function CardLayoutMetrics(session)
    local defaults = Grid.CardLayoutDefaults
    local shared = type(EXUI.GetSettingsCardLayoutDefaults) == "function"
        and EXUI:GetSettingsCardLayoutDefaults() or nil
    shared = type(shared) == "table" and shared or {}
    local supplied = type(session.context.layoutDefaults) == "table" and session.context.layoutDefaults or {}
    local function Metric(key)
        local value = supplied[key]
        if value == nil then value = shared[key] end
        if value == nil then value = defaults[key] end
        return tonumber(value) or 0
    end
    return {
        gap = math.max(0, Metric("gap")),
        left = math.max(0, Metric("left")),
        right = math.max(0, Metric("right")),
        top = math.max(0, Metric("top")),
        bottom = math.max(0, Metric("bottom")),
    }
end

local function ResolveDeclaredWidth(widthDeclaration, availableWidth)
    if type(widthDeclaration) == "number" then return math.max(1, widthDeclaration) end
    if type(widthDeclaration) == "table" then
        return math.max(1, availableWidth * widthDeclaration.ratio + (tonumber(widthDeclaration.offset) or 0))
    end
    return nil
end

function CardSessionMixin:_Diagnostic(cardState, code, detail)
    if self.released then return end
    local key = tostring(cardState and cardState.id) .. ":" .. tostring(code)
    if self._diagnosticKeys[key] then return end
    self._diagnosticKeys[key] = true
    local message = "[ExwindGrid] " .. CardLocation(self.context, cardState and cardState.id)
        .. ": " .. tostring(detail)
    self.diagnostics[#self.diagnostics + 1] = {
        cardId = cardState and cardState.id,
        code = code,
        message = message,
    }
    if type(self.context.onDiagnostic) == "function" then
        self.context.onDiagnostic(message, cardState and cardState.id, code)
    elseif _G.print then
        _G.print(message)
    end
end

function CardSessionMixin:GetDiagnostics()
    local result = {}
    for index, diagnostic in ipairs(self.diagnostics) do result[index] = diagnostic end
    return result
end

function CardSessionMixin:_SetReportedContentHeight(cardState, sourceItem, height)
    if self.released or not cardState then return false end
    height = tonumber(height)
    if not height or height ~= height or height < 0 then
        self:_Diagnostic(cardState, "height", "SetContentHeight requires a finite value >= 0")
        return false
    end
    -- Each custom element owns its measurement, even when several share one Card.
    local heights = cardState.reportedHeights
    local previous = heights and heights[sourceItem]
    if previous ~= nil and math.abs(previous - height) < 0.01 then
        return false
    end
    if not heights then
        heights = {}
        cardState.reportedHeights = heights
    end
    heights[sourceItem] = height
    self.grid:RequestReflow(cardState.body)
    return true
end

function CardSessionMixin:_QueueRelayout()
    if self.released then return false end
    if self.reflowBusy then
        self.reflowPending = true
        return true
    end
    if self.reflowScheduled then return true end
    self.reflowScheduled = true
    self.reflowTicket = (self.reflowTicket or 0) + 1
    local ticket = self.reflowTicket
    local generation = self.generation
    local function Run()
        if self.released or self.generation ~= generation or self.reflowTicket ~= ticket then return end
        self.reflowScheduled = nil
        self:Relayout()
    end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Run)
    else
        Run()
    end
    return true
end

function Grid:RequestReflow(container)
    local owner = container and self.CardSessionOwners[container]
    local session = owner and owner.session or (container and self.CardSessions[container])
    if not session or session.released then return false end
    return session:_QueueRelayout()
end

local function RestoreGridActivation(grid, snapshot)
    grid.CellSize = snapshot.cellSize
    grid._effectiveCols = snapshot.cols
    grid._activeContainer = snapshot.container
    grid.Widgets = snapshot.widgets
    grid.WidgetInstances = snapshot.instances
    grid.WidgetMap = snapshot.widgetMap
    grid.ActiveLayout = snapshot.layout
    grid.LastConfig = snapshot.config
    grid.ModuleKey = snapshot.moduleKey
end

local function SnapshotGridActivation(grid)
    return {
        cellSize = grid.CellSize,
        cols = grid._effectiveCols,
        container = grid._activeContainer,
        widgets = grid.Widgets,
        instances = grid.WidgetInstances,
        widgetMap = grid.WidgetMap,
        layout = grid.ActiveLayout,
        config = grid.LastConfig,
        moduleKey = grid.ModuleKey,
    }
end

local function SetCardWidth(card, width)
    local PixelUtil = _G.PixelUtil
    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(card, width, 1)
    else
        card:SetWidth(width)
    end
end

local function SetCardHeight(card, height)
    local PixelUtil = _G.PixelUtil
    height = math.max(1, height)
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(card, height, 1)
    else
        card:SetHeight(height)
    end
end

local function MeasureSessionCards(session, availableWidth)
    local grid = session.grid
    local equalHeightGroups = {}
    for _, cardState in ipairs(session.cards) do
        local group = cardState.settingsGroup
        local placement = (group and group.tableColumns and group.anchorMember or cardState).definition.placement
        if session.settingsLayoutNarrow and placement and placement.narrow then
            placement = placement.narrow
        end
        cardState.layoutPlacement = placement
        placement = placement or {}
        local width = ResolveDeclaredWidth(placement.width, availableWidth)
        if not width then width = availableWidth end
        if session.hasSettingsList then width = math.min(width, availableWidth) end
        cardState.width = math.max(1, width)
        if cardState.content.kind == "composite"
            and cardState.width < CARD_COMPOSITE_MIN_OUTER_WIDTH then
            error("[ExwindGrid] " .. CardLocation(session.context, cardState.id)
                .. ": resolved composite Card width must be at least "
                .. tostring(CARD_COMPOSITE_MIN_OUTER_WIDTH), 0)
        end
        SetCardWidth(cardState.card, cardState.width)

        local bodyWidth = cardState.body:GetWidth()
        if not bodyWidth or bodyWidth <= 1 then bodyWidth = cardState.width end
        local contentHeight = ReflowCardBody(grid, cardState, bodyWidth)
        if cardState.lastContentHeight == nil
            or math.abs(cardState.lastContentHeight - contentHeight) >= 0.01 then
            cardState.lastContentHeight = contentHeight
            cardState.card:SetContentHeight(contentHeight)
        end
        local preferred = cardState.card:GetPreferredHeight(cardState.width)
        if type(preferred) ~= "number" or preferred ~= preferred or preferred <= 0 then
            error("[ExwindGrid] " .. CardLocation(session.context, cardState.id)
                .. ": Card:GetPreferredHeight(width) returned an invalid height", 0)
        end
        cardState.outerHeight = preferred
        cardState.layoutHeight = cardState.visible and not cardState.pageDescriptionOnly
            and not cardState.emptySharedTableMember and not cardState.summaryEnabled and preferred or 0
        local heightGroup = cardState.definition.equalHeightGroup
        if heightGroup and cardState.layoutHeight > 0 then
            local equal = equalHeightGroups[heightGroup]
            if not equal then
                equal = { height = 0, members = {} }
                equalHeightGroups[heightGroup] = equal
            end
            equal.height = math.max(equal.height, preferred)
            equal.members[#equal.members + 1] = cardState
        else
            SetCardHeight(cardState.card, preferred)
        end
        if cardState.settingsSection then
            cardState.settingsSectionHeight = EXUI:UpdateSettingsSectionLayout(
                cardState.settingsSection, cardState.width)
            if cardState.visible then
                cardState.layoutHeight = cardState.layoutHeight + cardState.settingsSectionHeight
            end
        end
    end
    for _, equal in pairs(equalHeightGroups) do
        for _, cardState in ipairs(equal.members) do
            local extraHeight = cardState.layoutHeight - cardState.outerHeight
            cardState.outerHeight = equal.height
            cardState.layoutHeight = equal.height + extraHeight
            SetCardHeight(cardState.card, equal.height)
        end
    end
end

local function SetRelativeCardAnchor(cardState, target, placement, gap, parent, rowBottom)
    local side = placement.side or "below"
    local align = placement.align or "start"
    local x = tonumber(placement.x) or 0
    local y = tonumber(placement.y) or 0
    if side == "right" then
        cardState.x = target.x + target.width + gap + x
        if align == "center" then
            cardState.y = target.y + (target.layoutHeight - cardState.layoutHeight) * 0.5 - y
        elseif align == "end" then
            cardState.y = target.y + target.layoutHeight - cardState.layoutHeight - y
        else
            cardState.y = target.y - y
        end
    else
        if align == "center" then
            cardState.x = target.x + (target.width - cardState.width) * 0.5 + x
        elseif align == "end" then
            cardState.x = target.x + target.width - cardState.width + x
        else
            cardState.x = target.x + x
        end
        cardState.y = (rowBottom or (target.y + target.layoutHeight)) + gap - y
    end
    cardState.card:ClearAllPoints()
    cardState.card:SetPoint("TOPLEFT", parent, "TOPLEFT", cardState.x, -cardState.y)
end

local function ResolveSessionPositions(session, metrics, parentWidth, parentHeight)
    local status = {}
    local gap = metrics.gap
    local contentWidth = math.max(1, parentWidth - metrics.left - metrics.right)
    local contentHeight = math.max(1, parentHeight - metrics.top - metrics.bottom)
    for _, cardState in ipairs(session.cards) do cardState.usedFallback = nil end

    local function Fallback(cardState, code, detail)
        session:_Diagnostic(cardState, code, detail)
        cardState.usedFallback = true
        status[cardState] = "done"
    end

    local Resolve
    Resolve = function(cardState)
        if status[cardState] == "done" then return end
        if status[cardState] == "visiting" then
            Fallback(cardState, "cycle", "card placement cycle detected; using safe vertical fallback")
            return
        end
        status[cardState] = "visiting"
        local placement = cardState.layoutPlacement
        local settingsGroup = cardState.settingsGroup
        if settingsGroup and cardState.settingsGroupIndex > 1 then
            placement = {
                target = settingsGroup.members[cardState.settingsGroupIndex - 1].id,
                side = "below", align = "start", gap = 0,
            }
        elseif settingsGroup and settingsGroup.tableColumns and not placement then
            placement = { target = CARD_CONTAINER_TARGET, point = "TOPLEFT", relativePoint = "TOPLEFT" }
        end
        local targetId
        if placement then
            targetId = placement.target or CARD_CONTAINER_TARGET
        elseif cardState.previous then
            -- 默认纵排只在可见 Card 之间留一个 gap。隐藏 Card 仍保留稳定
            -- id/内容与显式 placement 语义，但不能作为隐式前驱累计空白。
            local previousVisible = cardState.previous
            while previousVisible and not previousVisible.visible do
                previousVisible = previousVisible.previous
            end
            if not previousVisible then
                targetId = CARD_CONTAINER_TARGET
                placement = {
                    target = targetId,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    x = 0,
                    y = 0,
                }
            else
                targetId = previousVisible.id
                placement = { target = targetId, side = "below", align = "start" }
            end
        else
            targetId = CARD_CONTAINER_TARGET
            placement = {
                target = targetId,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                x = 0,
                y = 0,
            }
        end

        if targetId ~= CARD_CONTAINER_TARGET then
            if targetId == cardState.id then
                Fallback(cardState, "self",
                    "card placement cannot target itself; using safe vertical fallback")
                return
            end
            local target = session.byId[targetId]
            if not target then
                Fallback(cardState, "missing", "card placement target not found: "
                    .. tostring(targetId) .. "; using safe vertical fallback")
                return
            end
            if target.settingsGroup and target.settingsGroup ~= settingsGroup
                and (placement.side or "below") == "below" then
                local members = target.settingsGroup.members
                target = members[#members]
            end
            Resolve(target)
            if status[cardState] == "done" then return end
            cardState.leadingPageDescriptionOnly = cardState.pageDescriptionOnly
                and target.leadingPageDescriptionOnly == true
            if target.usedFallback then
                Fallback(cardState, "dependency",
                    "card placement target used fallback; using the same safe vertical fallback")
                return
            end
            local actualGap = placement.gap ~= nil and placement.gap or gap
            if placement.gap == nil and cardState.definition.settingsList
                and (placement.side or "below") == "below" then
                actualGap = 26
            end
            if placement.gap == nil and cardState.pageDescriptionOnly
                and (placement.side or "below") == "below" then actualGap = 0 end
            if placement.gap == nil and target.leadingPageDescriptionOnly
                and (placement.side or "below") == "below" then actualGap = 0 end
            local rowBottom
            for _, id in ipairs(placement.rowAfter or {}) do
                local member = session.byId[id]
                if not member then
                    Fallback(cardState, "missing", "rowAfter card not found: " .. id)
                    return
                end
                Resolve(member)
                if status[cardState] == "done" then return end
                if member.usedFallback then
                    Fallback(cardState, "dependency", "rowAfter card used safe vertical fallback")
                    return
                end
                if member.visible then
                    rowBottom = math.max(rowBottom or (member.y + member.layoutHeight),
                        member.y + member.layoutHeight)
                end
            end
            if placement.rowAfter and rowBottom == nil then rowBottom = target.y end
            SetRelativeCardAnchor(cardState, target, placement, actualGap, session.parent, rowBottom)
        else
            cardState.leadingPageDescriptionOnly = cardState.pageDescriptionOnly == true
            local point = placement.point or "TOPLEFT"
            local relativePoint = placement.relativePoint or point
            local x, y = tonumber(placement.x) or 0, tonumber(placement.y) or 0
            local ownFactor = CARD_POINT_FACTORS[point]
            local relativeFactor = CARD_POINT_FACTORS[relativePoint]
            cardState.x = metrics.left + contentWidth * relativeFactor[1]
                + x - cardState.width * ownFactor[1]
            cardState.y = metrics.top + contentHeight * relativeFactor[2] - y
                - cardState.layoutHeight * ownFactor[2]
            cardState.card:ClearAllPoints()
            cardState.card:SetPoint("TOPLEFT", session.parent, "TOPLEFT", cardState.x, -cardState.y)
        end
        status[cardState] = "done"
    end

    for _, cardState in ipairs(session.cards) do Resolve(cardState) end

    local fallbackY = metrics.top
    for _, cardState in ipairs(session.cards) do
        if not cardState.usedFallback and cardState.visible then
            fallbackY = math.max(fallbackY, cardState.y + cardState.layoutHeight + gap)
        end
    end
    for _, cardState in ipairs(session.cards) do
        if cardState.usedFallback then
            cardState.card:ClearAllPoints()
            cardState.card:SetPoint("TOPLEFT", session.parent, "TOPLEFT", metrics.left, -fallbackY)
            cardState.x, cardState.y = metrics.left, fallbackY
            if cardState.layoutHeight > 0 then fallbackY = fallbackY + cardState.layoutHeight + gap end
        end
    end
end

local function ClampSessionScroll(session, totalHeight)
    local scrollFrame = session.context.scrollFrame
    if not scrollFrame or type(scrollFrame.GetVerticalScroll) ~= "function"
        or type(scrollFrame.SetVerticalScroll) ~= "function" then return end
    local current = tonumber(scrollFrame:GetVerticalScroll()) or 0
    local viewport = type(scrollFrame.GetHeight) == "function" and scrollFrame:GetHeight() or 0
    local maximum = math.max(0, totalHeight - (tonumber(viewport) or 0))
    local clamped = math.max(0, math.min(current, maximum))
    if math.abs(clamped - current) >= 0.01 then scrollFrame:SetVerticalScroll(clamped) end
end

local function PerformSessionRelayout(session)
    local parent = session.parent
    local parentWidth = math.max(1, parent:GetWidth())
    local metrics = CardLayoutMetrics(session)
    local availableWidth = math.max(1, parentWidth - metrics.left - metrics.right)
    if session.hasSettingsList then
        local percent = session.declaration.settingsListWidthPercent
        if session.typedSections then percent = 75 end
        local rawAvailableWidth = availableWidth
        availableWidth = Grid:ResolveSettingsListWidth(rawAvailableWidth, percent)
        if session.typedSections then
            -- Ordinary pages share one Core-owned 75% column. Centering the
            -- unused width here keeps modules from declaring outer coordinates.
            metrics.left = metrics.left + math.floor((rawAvailableWidth - availableWidth) * 0.5 + 0.5)
            metrics.gap = type(EXUI.GetSettingsSectionGroupGap) == "function"
                and EXUI:GetSettingsSectionGroupGap() or 16
        end
        parentWidth = metrics.left + availableWidth + metrics.right
    end
    local breakpoint = session.declaration.settingsLayoutBreakpoint
    session.settingsLayoutNarrow = session.hasSettingsList and breakpoint ~= nil
        and availableWidth <= breakpoint or false
    local pageHeadingHeight = 0
    if session.settingsHeading then
        metrics.top = metrics.top + 16
        local heading = session.settingsHeading
        local height = EXUI:UpdateSettingsSectionLayout(heading, availableWidth)
        pageHeadingHeight = height
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", parent, "TOPLEFT", metrics.left, -metrics.top)
        metrics.top = metrics.top + height
    end
    local parentHeight = tonumber(session.context.viewportHeight)
        or (session.context.scrollFrame and session.context.scrollFrame:GetHeight())
        or parent:GetHeight()
        or 1

    local snapshot = SnapshotGridActivation(session.grid)
    local measured, measureReason = pcall(MeasureSessionCards, session, availableWidth)
    RestoreGridActivation(session.grid, snapshot)
    if not measured then error(measureReason, 0) end
    -- Original Grid reflow retains ownership of each text control and runs first.
    -- Reapply only heading presentation anchors after every card has been measured.
    if session.settingsHeading and #(session.settingsPageDescriptionWidgets or {}) > 0 then
        local height = EXUI:UpdateSettingsSectionLayout(session.settingsHeading, availableWidth)
        metrics.top = metrics.top + height - pageHeadingHeight
    end
    for _, cardState in ipairs(session.cards) do
        if cardState.settingsSection then
            local height = EXUI:UpdateSettingsSectionLayout(cardState.settingsSection, cardState.width)
            if cardState.visible then
                cardState.layoutHeight = cardState.layoutHeight + height - (cardState.settingsSectionHeight or 0)
            end
            cardState.settingsSectionHeight = height
        end
    end
    ResolveSessionPositions(session, metrics, parentWidth, math.max(1, parentHeight))

    local maxBottom = metrics.top
    for _, cardState in ipairs(session.cards) do
        cardState.card:SetShown(cardState.visible)
        if cardState.settingsSection then
            local heading = cardState.settingsSection
            heading:SetShown(cardState.visible)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", parent, "TOPLEFT", cardState.x, -cardState.y)
            cardState.card:ClearAllPoints()
            cardState.card:SetPoint("TOPLEFT", parent, "TOPLEFT", cardState.x,
                -(cardState.y + cardState.settingsSectionHeight))
        end
        if cardState.visible and not cardState.pageDescriptionOnly then
            maxBottom = math.max(maxBottom, cardState.y + cardState.layoutHeight)
        end
    end
    for _, group in ipairs(session.settingsGroups or {}) do
        local left, top, right, bottom
        local lastVisible
        for index = #group.members, 1, -1 do
            local member = group.members[index]
            if member.visible and not member.emptySharedTableMember then lastVisible = member; break end
        end
        for _, member in ipairs(group.members) do
            EXUI:SetSettingsCardGroupMemberLast(member.card,
                member == lastVisible or not member.visible or member.emptySharedTableMember)
            if member.visible and not member.emptySharedTableMember then
                local memberTop = member.y + (member.settingsSectionHeight or 0)
                left = left and math.min(left, member.x) or member.x
                top = top and math.min(top, memberTop) or memberTop
                right = math.max(right or 0, member.x + member.width)
                bottom = math.max(bottom or 0, member.y + member.layoutHeight)
            end
        end
        local surface = group.surface
        surface:SetShown(left ~= nil)
        if left then
            EXUI:UpdateSettingsCardGroupSurfaceLayout(surface, right - left, bottom - top)
            surface:ClearAllPoints()
            surface:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
        end
    end
    local totalHeight = math.max(1, maxBottom + metrics.bottom)
    if session.totalHeight == nil or math.abs(session.totalHeight - totalHeight) >= 0.01 then
        session.totalHeight = totalHeight
        SetCardHeight(parent, totalHeight)
        if type(session.context.onContentHeightChanged) == "function" then
            session.context.onContentHeightChanged(totalHeight, session)
        end
    end
    ClampSessionScroll(session, totalHeight)
    for _, cardState in ipairs(session.cards) do
        local list = session.grid:GetSettingsListSession(cardState.body)
        if list then list:RefreshCardVisuals() end
    end
    if session.typedSections then session.grid:CheckSettingsDeclarationBounds(session) end
end

function CardSessionMixin:Relayout()
    if self.released then return false end
    if self.reflowBusy then
        self.reflowPending = true
        return false
    end
    self.reflowScheduled = nil
    self.reflowTicket = (self.reflowTicket or 0) + 1
    self.reflowBusy = true
    local ok, reason = pcall(PerformSessionRelayout, self)
    self.reflowBusy = nil
    if not ok then error(reason, 0) end
    if self.reflowPending then
        self.reflowPending = nil
        self:_QueueRelayout()
    end
    return true
end

function CardSessionMixin:RefreshValues()
    if self.released then return false end
    for _, cardState in ipairs(self.cards) do
        self.grid:RefreshContainerControlsFromDB(cardState.body)
        local state = self.grid.ContainerStates[cardState.body]
        for _, widget in ipairs(state and state.instances or {}) do
            if widget._customRenderer then
                local ctx = widget._customContext or {}
                local meta = state.widgetMap and state.widgetMap[widget]
                ctx.currentValue = CurrentCardItemValue(cardState.binding.config,
                    ctx.element or {}, meta and meta.path)
                ctx.value = ctx.currentValue
                if type(widget._customRenderer.update) == "function" then
                    widget._customRenderer.update(widget, ctx)
                elseif type(widget._customRenderer.render) == "function" then
                    widget._customRenderer.render(widget, ctx)
                end
            end
        end
    end
    return true
end

function CardSessionMixin:GetWidget(cardId, widgetKey)
    if self.released then return nil end
    local cardState = self.byId[cardId]
    if not cardState then return nil end
    local state = self.grid.ContainerStates[cardState.body]
    return state and state.widgets and state.widgets[widgetKey] or nil
end

function CardSessionMixin:FindWidget(widgetKey)
    if self.released then return nil end
    local found, foundCardId
    for _, cardState in ipairs(self.cards) do
        local state = self.grid.ContainerStates[cardState.body]
        local widget = state and state.widgets and state.widgets[widgetKey]
        if widget then
            if found and found ~= widget then
                error("[ExwindGrid] widget key is not unique across cards: "
                    .. tostring(widgetKey) .. "; pass cardId to GetWidget", 2)
            end
            found, foundCardId = widget, cardState.id
        end
    end
    return found, foundCardId
end

local function ReleaseCardBody(session, cardState)
    cardState.contentGeneration = (cardState.contentGeneration or 0) + 1
    local released, releaseReason = pcall(session.grid.ReleaseContainerWidgets,
        session.grid, cardState.body)
    session.grid.ContainerStates[cardState.body] = nil
    session.grid:ClearContainerCols(cardState.body)
    session.grid:ClearContainerPadding(cardState.body)
    cardState.widgetsByOrdinal = {}
    cardState.identityByOrdinal = {}
    cardState.renderableCount = 0
    cardState.reportedHeights = nil
    cardState.lastContentHeight = nil
    if not released then error(releaseReason, 0) end
end

function CardSessionMixin:ReplaceCardContent(cardId, content)
    if self.typedSections then
        error("[ExwindGrid] typed sections must be replaced with ReplaceSettingsSection", 2)
    end
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    if cardState.summaryEnabled then
        error("[ExwindGrid] summaryEnabled master requires releasing and remounting the whole card session", 2)
    end
    local ok, reason = ValidateCardContent(self.grid, content,
        "[ExwindGrid] " .. CardLocation(self.context, cardId))
    if not ok then error(reason, 2) end
    if CardContentOwnsScroll(content) ~= CardContentOwnsScroll(cardState.content) then
        error("[ExwindGrid] " .. CardLocation(self.context, cardId)
            .. ": changing content.ownsScroll requires releasing and remounting the card session", 2)
    end
    local previousContent = cardState.content
    local previousBinding = cardState.binding
    local previousSourceItems = cardState.sourceItems
    local nextBinding = ResolveCardBinding(self, cardState.definition, content)
    local nextSourceItems = BuildCardContentSource(cardState, content)
    local released, releaseReason = pcall(ReleaseCardBody, self, cardState)
    if not released then
        local activation = SnapshotGridActivation(self.grid)
        local restored, restoreReason = pcall(MountCardBody, self.grid, cardState)
        RestoreGridActivation(self.grid, activation)
        if not restored then
            local invalidated, invalidateReason = pcall(self.Release, self)
            local message = tostring(releaseReason) .. "; rollback failed: " .. tostring(restoreReason)
            if not invalidated then
                message = message .. "; session invalidation failed: " .. tostring(invalidateReason)
            end
            error(message, 2)
        end
        error(releaseReason, 2)
    end
    cardState.content = content
    cardState.binding = nextBinding
    cardState.sourceItems = nextSourceItems
    local activation = SnapshotGridActivation(self.grid)
    local mounted, mountReason = pcall(MountCardBody, self.grid, cardState)
    RestoreGridActivation(self.grid, activation)
    if not mounted then
        local cleaned, cleanupReason = pcall(ReleaseCardBody, self, cardState)
        cardState.content = previousContent
        cardState.binding = previousBinding
        cardState.sourceItems = previousSourceItems
        activation = SnapshotGridActivation(self.grid)
        local restored, restoreReason = pcall(MountCardBody, self.grid, cardState)
        RestoreGridActivation(self.grid, activation)
        if not restored then
            local message = tostring(mountReason)
            if not cleaned then
                message = message .. "; failed-content cleanup failed: " .. tostring(cleanupReason)
            end
            message = message .. "; rollback failed: " .. tostring(restoreReason)
            local invalidated, invalidateReason = pcall(self.Release, self)
            if not invalidated then
                message = message .. "; session invalidation failed: " .. tostring(invalidateReason)
            end
            error(message, 2)
        end
        if not cleaned then
            error(tostring(mountReason) .. "; failed-content cleanup failed: "
                .. tostring(cleanupReason), 2)
        end
        error(mountReason, 2)
    end
    self.grid:RequestReflow(cardState.body)
    return true
end

function CardSessionMixin:RebindCardContent(cardId)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    return self:ReplaceCardContent(cardId, cardState.content)
end

function CardSessionMixin:SetCardVisible(cardId, visible)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    visible = visible ~= false
    if cardState.visible == visible then return false end
    cardState.visible = visible
    self.grid:RequestReflow(cardState.card)
    return true
end

function CardSessionMixin:SetCardCollapsed(cardId, collapsed, silent)
    if self.released then return false end
    local cardState = self.byId[cardId]
    if not cardState then error("[ExwindGrid] unknown cardId: " .. tostring(cardId), 2) end
    cardState.card:SetCollapsed(collapsed == true, silent == true)
    if silent == true then self.grid:RequestReflow(cardState.card) end
    return true
end

function CardSessionMixin:Release()
    if self.released then return false end
    self.released = true
    self.generation = self.generation + 1
    self.reflowScheduled = nil
    self.reflowPending = nil
    self.reflowTicket = (self.reflowTicket or 0) + 1
    local scrollFrame = self.context and self.context.scrollFrame
    local scrollSessions = scrollFrame and self.grid.CardScrollSessions[scrollFrame]
    if scrollSessions then scrollSessions[self] = nil end
    local firstReleaseReason
    local function Capture(ok, reason)
        if not ok and firstReleaseReason == nil then firstReleaseReason = reason end
    end
    for index = #self.cards, 1, -1 do
        local cardState = self.cards[index]
        if type(cardState.card.SetLayoutInvalidationHandler) == "function" then
            Capture(pcall(cardState.card.SetLayoutInvalidationHandler, cardState.card, nil))
        end
        Capture(pcall(ReleaseCardBody, self, cardState))
        self.grid.CardSessionOwners[cardState.body] = nil
        self.grid.CardSessionOwners[cardState.card] = nil
        if type(EXUI.RestoreSettingsListCard) == "function" then
            Capture(pcall(EXUI.RestoreSettingsListCard, EXUI, cardState.card))
        end
        if type(cardState.card.Release) == "function" then
            Capture(pcall(cardState.card.Release, cardState.card))
        end
        if cardState.settingsSection then
            Capture(pcall(cardState.settingsSection.Release, cardState.settingsSection))
            cardState.settingsSection = nil
        end
        self.cards[index] = nil
    end
    for _, group in ipairs(self.settingsGroups or {}) do
        if group.surface then Capture(pcall(group.surface.Release, group.surface)) end
    end
    self.settingsGroups = nil
    if self.settingsHeading then
        Capture(pcall(self.settingsHeading.Release, self.settingsHeading))
        self.settingsHeading = nil
    end
    if self.grid.CardSessions[self.parent] == self then self.grid.CardSessions[self.parent] = nil end
    self.grid.CardSessionOwners[self.parent] = nil
    self.byId = {}
    if self.typedWidgets then table.wipe(self.typedWidgets) end
    if firstReleaseReason ~= nil then error(firstReleaseReason, 0) end
    return true
end

function Grid:MountCards(parent, declaration, context)
    if type(declaration) == "table" and declaration.sections ~= nil then
        return self:MountSettingsDeclaration(parent, declaration, context)
    end
    if not parent then error("[ExwindGrid] MountCards requires parent", 2) end
    context = type(context) == "table" and context or {}
    local ok, reason = self:ValidateCardDeclaration(declaration, context)
    if not ok then error(reason, 2) end
    if type(EXUI.CreateSettingsCard) ~= "function" then
        error("[ExwindGrid] EXUI:CreateSettingsCard is not available", 2)
    end
    local existing = self.CardSessions[parent]
    if existing and not existing.released then
        error("[ExwindGrid] parent already owns an active card session; Release it before remounting", 2)
    end

    local session = setmetatable({
        grid = self,
        parent = parent,
        declaration = declaration,
        context = context,
        cards = {},
        byId = {},
        diagnostics = {},
        _diagnosticKeys = {},
        generation = 1,
    }, { __index = CardSessionMixin })
    self.CardSessions[parent] = session
    self.CardSessionOwners[parent] = { session = session }

    local snapshot = SnapshotGridActivation(self)
    local mounted, mountReason = pcall(function()
        local previous
        for _, definition in ipairs(declaration.cards) do
            local card = EXUI:CreateSettingsCard(parent, {
                id = definition.id,
                title = definition.title,
                icon = definition.icon,
                headerIcon = definition.headerIcon,
                collapsible = definition.collapsible == true,
                collapsed = definition.collapsed == true,
                minBodyHeight = tonumber(definition.minBodyHeight) or 0,
                maxBodyHeight = definition.maxBodyHeight and tonumber(definition.maxBodyHeight) or nil,
                ownsScroll = CardContentOwnsScroll(definition.content),
            })
            if not card then
                error("[ExwindGrid] " .. CardLocation(context, definition.id)
                    .. ": CreateSettingsCard returned nil", 0)
            end
            if type(card.GetBody) ~= "function"
                or type(card.SetContentHeight) ~= "function"
                or type(card.SetLayoutInvalidationHandler) ~= "function"
                or type(card.GetPreferredHeight) ~= "function"
                or type(card.SetCollapsed) ~= "function"
                or type(card.Release) ~= "function" then
                if type(card.Release) == "function" then
                    pcall(card.Release, card)
                else
                    if type(card.Hide) == "function" then pcall(card.Hide, card) end
                    if type(card.SetParent) == "function" then pcall(card.SetParent, card, nil) end
                end
                error("[ExwindGrid] " .. CardLocation(context, definition.id)
                    .. ": SettingsCard does not implement the required layout contract", 0)
            end
            local gotBody, body = pcall(card.GetBody, card)
            if not gotBody or not body then
                pcall(card.Release, card)
                error("[ExwindGrid] " .. CardLocation(context, definition.id)
                    .. ": SettingsCard:GetBody() did not return a body frame", 0)
            end
            local cardState = {
                session = session,
                id = definition.id,
                definition = definition,
                content = definition.content,
                card = card,
                body = body,
                previous = previous,
                visible = definition.hidden ~= true and definition.visible ~= false,
                widgetsByOrdinal = {},
            }
            session.cards[#session.cards + 1] = cardState
            session.byId[cardState.id] = cardState
            previous = cardState
            self.CardSessionOwners[card] = { session = session, card = cardState }
            self.CardSessionOwners[body] = { session = session, card = cardState }
            cardState.binding = ResolveCardBinding(session, definition, definition.content)
            cardState.sourceItems = BuildCardContentSource(cardState, definition.content)
            card:SetCollapsed(definition.collapsed == true, true)
            card:SetLayoutInvalidationHandler(function()
                self:RequestReflow(card)
            end)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            SetCardWidth(card, math.max(1, parent:GetWidth()))
            card:SetShown(cardState.visible)
            MountCardBody(self, cardState)
        end
    end)
    RestoreGridActivation(self, snapshot)
    if not mounted then
        local released, releaseReason = pcall(session.Release, session)
        if not released then
            error(tostring(mountReason) .. "; session cleanup failed: "
                .. tostring(releaseReason), 0)
        end
        error(mountReason, 0)
    end

    if not parent._exCardSessionSizeHook then
        parent._exCardSessionSizeHook = true
        parent:HookScript("OnSizeChanged", function(host, width)
            local owner = Grid.CardSessionOwners[host]
            local active = owner and owner.session
            if active and not active.released then
                width = tonumber(width) or host:GetWidth()
                if active._lastParentWidth == nil
                    or math.abs(active._lastParentWidth - width) >= 0.01 then
                    active._lastParentWidth = width
                    Grid:RequestReflow(host)
                end
            end
        end)
    end
    session._lastParentWidth = parent:GetWidth()

    local scrollFrame = context.scrollFrame
    if scrollFrame and type(scrollFrame.HookScript) == "function" then
        local scrollSessions = self.CardScrollSessions[scrollFrame]
        if not scrollSessions then
            scrollSessions = setmetatable({}, { __mode = "k" })
            self.CardScrollSessions[scrollFrame] = scrollSessions
        end
        scrollSessions[session] = true
        if not scrollFrame._exGridCardSessionSizeHook then
            scrollFrame._exGridCardSessionSizeHook = true
            scrollFrame:HookScript("OnSizeChanged", function(host)
                local activeSessions = Grid.CardScrollSessions[host]
                if not activeSessions then return end
                for active in pairs(activeSessions) do
                    if not active.released then Grid:RequestReflow(active.parent) end
                end
            end)
        end
    end
    local laidOut, layoutReason = pcall(function()
        self:MountDeclaredSettingsLists(session, declaration)
        return session:Relayout()
    end)
    if not laidOut then
        local released, releaseReason = pcall(session.Release, session)
        if not released then
            error(tostring(layoutReason) .. "; session cleanup failed: "
                .. tostring(releaseReason), 0)
        end
        error(layoutReason, 0)
    end
    return session
end

-- Typed ordinary pages have one author declaration.  The objects below are
-- measured visual state, not a second cards/settingsList declaration or DB.
do
    local function Fail(location, message)
        error("[ExwindGrid] " .. location .. ": " .. message, 0)
    end
    local function Fields(value, allowed, location)
        if type(value) ~= "table" then Fail(location, "expected a table") end
        for key in pairs(value) do
            if not allowed[key] then Fail(location, "unsupported field " .. tostring(key)) end
        end
    end
    local function Array(value, location)
        if type(value) ~= "table" then Fail(location, "expected an ordered array") end
        local count, last = 0, 0
        for key in pairs(value) do
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
                Fail(location, "expected an ordered array")
            end
            count, last = count + 1, math.max(last, key)
        end
        if count ~= last then Fail(location, "array cannot contain holes") end
        return count
    end
    local function String(value, location, optional)
        if optional and value == nil then return end
        if type(value) ~= "string" or (not optional and value == "") then
            Fail(location, "expected a string")
        end
    end
    local function Finite(value, location)
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
            Fail(location, "expected a finite number")
        end
    end
    local function Key(value, location)
        if type(value) == "number" then Finite(value, location)
        else String(value, location) end
    end
    local itemFields = { key=true, type=true, label=true, description=true, inputWidthPercent=true,
        parentKey=true, subKey=true, setKey=true, options=true, optionsSource=true,
        min=true, max=true, step=true, itemID=true, canDelete=true, baseLabel=true, func=true, multiple=true,
        media=true, search=true, originalOptions=true, presentation=true }
    local ordinaryTypes = { switch=true, input=true, select=true, slider=true, color=true, button=true }
    local recordTypes = { itemenabled=true, itemquantity=true, itemdelete=true }
    local tableInformationTypes = { description=true }
    local function Item(item, location, keys, tableCell, moduleKey)
        Fields(item, itemFields, location)
        Key(item.key, location .. ".key")
        if keys[item.key] then Fail(location, "duplicate control key " .. item.key) end
        keys[item.key] = true
        if not ordinaryTypes[item.type]
            and not (tableCell and (recordTypes[item.type] or tableInformationTypes[item.type])) then
            Fail(location, "unsupported control type " .. tostring(item.type))
        end
        String(item.label, location .. ".label", tableCell)
        if item.presentation ~= nil and (item.type ~= "switch"
            or (item.presentation ~= "card" and item.presentation ~= "card")) then
            Fail(location, "presentation requires an original switch with card appearance")
        end
        if type(item.description) == "table" then
            local description = item.description
            Fields(description, { key=true, type=true, label=true }, location .. ".description")
            if description.type ~= "label" and description.type ~= "description" then
                Fail(location, "description must retain its original label/description factory")
            end
            Key(description.key, location .. ".description.key")
            if keys[description.key] then Fail(location, "duplicate description key " .. description.key) end
            keys[description.key] = true
            String(description.label, location .. ".description.label", true)
            if description.label == nil then Fail(location, "description requires label") end
        else
            String(item.description, location .. ".description", true)
        end
        if item.func ~= nil and (item.type ~= "button" or type(item.func) ~= "function") then
            Fail(location, "func must be the original button callback")
        end
        if item.inputWidthPercent ~= nil then
            if item.type ~= "input" then Fail(location, "inputWidthPercent requires input") end
            Finite(item.inputWidthPercent, location .. ".inputWidthPercent")
            if item.inputWidthPercent <= 0 then Fail(location, "inputWidthPercent must be positive") end
        end
        if item.multiple ~= nil and (item.type ~= "select" or type(item.multiple) ~= "boolean") then
            Fail(location, "multiple is only a boolean on select")
        end
        if item.baseLabel ~= nil then
            if tableCell or moduleKey ~= "ExClass.SpellQueue" then
                Fail(location, "baseLabel is reserved for the existing SpellQueue GUI label cache")
            end
            String(item.baseLabel, location .. ".baseLabel", true)
        end
        String(item.parentKey, location .. ".parentKey", true)
        for _, name in ipairs({ "subKey", "setKey" }) do
            local value = item[name]
            if value ~= nil and type(value) ~= "string" and type(value) ~= "number" then
                Fail(location, name .. " must retain a string or numeric original key")
            end
        end
        if item.type == "select" then
            local sources = (item.options ~= nil and 1 or 0) + (item.optionsSource ~= nil and 1 or 0)
                + (item.media ~= nil and 1 or 0) + (item.originalOptions ~= nil and 1 or 0)
            if sources ~= 1 then
                Fail(location, "select requires exactly one of options, optionsSource, originalOptions, or media")
            end
            if item.media ~= nil then
                if (item.media ~= "sound" and item.media ~= "background" and item.media ~= "border")
                    or item.multiple ~= nil then
                    Fail(location, "media requires an original single-select sound/background/border factory")
                end
            elseif item.originalOptions ~= nil then
                if type(item.originalOptions) ~= "table" then
                    Fail(location, "originalOptions must reference the original dropdown items table")
                end
            elseif item.optionsSource ~= nil then
                String(item.optionsSource, location .. ".optionsSource")
                if not item.optionsSource:match("^[%a_][%w_%.]*$") then
                    Fail(location, "optionsSource must name an existing global list provider")
                end
            else
                Array(item.options, location .. ".options")
                local values = {}
                for index, option in ipairs(item.options) do
                    local at = location .. ".options[" .. index .. "]"
                    Fields(option, { value=true, label=true }, at)
                    String(option.label, at .. ".label", true)
                    if option.label == nil then Fail(at, "label is required") end
                    local t = type(option.value)
                    if t ~= "string" and t ~= "number" and t ~= "boolean" then
                        Fail(at, "value must retain its original scalar type")
                    end
                    if t == "number" then Finite(option.value, at .. ".value") end
                    if values[option.value] then Fail(at, "duplicate option value") end
                    values[option.value] = true
                end
            end
        elseif item.options ~= nil or item.optionsSource ~= nil or item.media ~= nil or item.originalOptions ~= nil then
            Fail(location, "options are only supported by select")
        end
        if item.search ~= nil and (item.type ~= "select" or type(item.search) ~= "boolean") then
            Fail(location, "search must retain the original selector boolean")
        end
        if item.type == "slider" then
            for _, name in ipairs({ "min", "max", "step" }) do
                if item[name] ~= nil then Finite(item[name], location .. "." .. name) end
            end
            if (item.min or 0) > (item.max or 100) or (item.step or 1) <= 0 then
                Fail(location, "invalid slider bounds or step")
            end
        elseif item.min ~= nil or item.max ~= nil or item.step ~= nil then
            Fail(location, "min/max/step require the original slider semantics")
        end
        if recordTypes[item.type] then
            if item.itemID == nil then Fail(location, "original itemID is required") end
            Finite(item.itemID, location .. ".itemID")
            if item.canDelete ~= nil and (item.type ~= "itemdelete" or type(item.canDelete) ~= "boolean") then
                Fail(location, "canDelete is only a boolean on itemdelete")
            end
        elseif item.itemID ~= nil or item.canDelete ~= nil then
            Fail(location, "item metadata requires an original item-record control")
        end
        if tableInformationTypes[item.type] then
            if item.label == nil then Fail(location, "table description requires its original label") end
            if item.parentKey ~= nil or item.subKey ~= nil or item.setKey ~= nil then
                Fail(location, "table descriptions are informational and cannot bind configuration")
            end
        end
        if tableCell and item.description ~= nil then
            Fail(location, "table cells do not support descriptions")
        end
    end
    local function TableRow(row, count, location, keys)
        Fields(row, { cells=true }, location)
        if Array(row.cells, location .. ".cells") ~= count then Fail(location, "cell count must match columns") end
        for index, cell in ipairs(row.cells) do
            local at = location .. ".cells[" .. index .. "]"
            if type(cell) == "table" and cell.text ~= nil then
                Fields(cell, { text=true, icon=true, itemID=true }, at)
                String(cell.text, at .. ".text", true)
                if cell.icon ~= nil and type(cell.icon) ~= "string" and type(cell.icon) ~= "number" then Fail(at .. ".icon", "texture path or file ID required") end
                if type(cell.icon) == "number" then Finite(cell.icon, at .. ".icon") end
                if cell.itemID ~= nil then Finite(cell.itemID, at .. ".itemID") end
            else
                Item(cell, at, keys, true)
            end
        end
    end
    local sectionFields = {
        settings = { kind=true, id=true, title=true, description=true, footerDescription=true, binding=true,
            items=true },
        table = { kind=true, id=true, title=true, description=true, binding=true,
            columns=true, supportsAdd=true, add=true, records=true,
            controlFactory=true, key=true, parentKey=true, subKey=true, setKey=true },
        composite = { kind=true, id=true, title=true, description=true, binding=true,
            component=true, key=true, parentKey=true, subKey=true, setKey=true, opts=true },
        custom = { kind=true, id=true, title=true, description=true, binding=true,
            renderer=true, key=true, parentKey=true, subKey=true, setKey=true, opts=true },
    }
    local componentOptions = {
        fontgroup = { bodyOnly="boolean", offsetMin="number", offsetMax="number",
            shadowOffsetMin="number", shadowOffsetMax="number", unboundedWidth="boolean" },
        icongroup = { bindRoot="boolean", bindValue="boolean", hideIconID="boolean", hidePositionControls="boolean",
            offsetMin="number", offsetMax="number", offsetStep="number", enableOffset="boolean" },
        timerbargroup = { bindRoot="boolean", iconOffsetMin="number", iconOffsetMax="number", fillModeOnly="boolean", applicationBar="boolean" },
        anchorgroup = { bindRoot="boolean", offsetXKey="string", offsetYKey="string", attachEnabledKey="string",
            attachTargetKey="string", allowCustomAttach="boolean", defaultOffsetX="number", defaultOffsetY="number", onPickFrame="function" },
        soundgroup = { sources="table", packItems="provider", secondaryCheckbox="table", testLabel="string", testButtonKey="string", onTest="function" },
        widgetlayout = { allowedDirections="table", wrapDirections="table", defaultWrapDirection="string",
            maxVisibleMin="number", maxVisibleMax="number", defaultMaxVisible="number", includeMaxPerRow="boolean", includeWrapDirection="boolean" },
        modulecommonsettings = { bindRoot="boolean", fields="table", poolType="string",
            presentation="string", fixedLayout="table", maxColumns="number", minCellWidth="number",
            rowHeight="number", firstRowHeight="number", rowStep="number", firstRowStep="number",
            contentTopInset="number", heightOffset="number",
            onFieldChanged="function", onStructureChanged="function" },
        glow_settings = {},
    }
    local function CompositeOptions(section, location)
        local allowed = componentOptions[string.lower(section.component)]
        local opts = section.opts
        if opts == nil then return end
        Fields(opts, allowed or {}, location .. ".opts")
        for name, value in pairs(opts) do
            local expected = allowed[name]
            if expected == "provider" then
                if type(value) ~= "table" and type(value) ~= "function" then Fail(location, name .. " requires the original list or provider") end
            elseif type(value) ~= expected then Fail(location, "opts." .. name .. " must be " .. expected) end
            if expected == "number" then Finite(value, location .. ".opts." .. name) end
        end
        for _, name in ipairs({ "sources", "allowedDirections", "wrapDirections" }) do
            if opts[name] then
                Array(opts[name], location .. ".opts." .. name)
                for _, value in ipairs(opts[name]) do
                    String(value, location .. ".opts." .. name)
                    if name == "sources" and value ~= "pack" and value ~= "lsm" and value ~= "file" and value ~= "tts" then
                        Fail(location, "unknown sound source " .. value)
                    end
                end
            end
        end
        if opts.secondaryCheckbox then
            Fields(opts.secondaryCheckbox, { key=true, label=true }, location .. ".secondaryCheckbox")
            String(opts.secondaryCheckbox.key, location .. ".secondaryCheckbox.key")
            String(opts.secondaryCheckbox.label, location .. ".secondaryCheckbox.label")
        end
        if string.lower(section.component) == "modulecommonsettings" then
            if opts.presentation ~= nil and opts.presentation ~= "settings-list" then
                Fail(location, "modulecommonsettings presentation must be settings-list")
            end
            if opts.fixedLayout ~= nil then
                local fixed = opts.fixedLayout
                Fields(fixed, { logicalWidth=true, controlW=true, controlH=true, slotX=true,
                    firstY=true, rowStep=true, cardTopInset=true, cardBottomInset=true,
                    visibleBottomSafety=true }, location .. ".opts.fixedLayout")
                for _, name in ipairs({ "logicalWidth", "controlW", "controlH", "firstY", "rowStep",
                    "cardTopInset", "cardBottomInset", "visibleBottomSafety" }) do
                    if fixed[name] ~= nil then Finite(fixed[name], location .. ".opts.fixedLayout." .. name) end
                end
                for _, name in ipairs({ "logicalWidth", "controlW", "controlH", "rowStep" }) do
                    if fixed[name] ~= nil and fixed[name] <= 0 then
                        Fail(location, "opts.fixedLayout." .. name .. " must be positive")
                    end
                end
                for _, name in ipairs({ "cardTopInset", "cardBottomInset", "visibleBottomSafety" }) do
                    if fixed[name] ~= nil and fixed[name] < 0 then
                        Fail(location, "opts.fixedLayout." .. name .. " cannot be negative")
                    end
                end
                if fixed.slotX ~= nil then
                    Array(fixed.slotX, location .. ".opts.fixedLayout.slotX")
                    if #fixed.slotX == 0 then Fail(location, "opts.fixedLayout.slotX cannot be empty") end
                    for index, value in ipairs(fixed.slotX) do
                        Finite(value, location .. ".opts.fixedLayout.slotX[" .. index .. "]")
                    end
                end
            end
        end
        if opts.fields then
            Array(opts.fields, location .. ".fields")
            local kinds = { button=true, checkbox=true, dropdown=true, lsm_background=true,
                lsm_border=true, lsm_texture=true, input=true, color=true, slider=true }
            local fieldNames = { key=true, path=true, type=true, label=true, description=true,
                disabled=true,
                min=true, max=true, step=true, items=true, onClick=true, row=true, column=true,
                presentation=true, valuePosition=true, controlWidth=true, inputWidthPercent=true,
                minWidth=true, preferredWidth=true, width=true, span=true, fullWidth=true, variant=true }
            for index, field in ipairs(opts.fields) do
                local at = location .. ".fields[" .. index .. "]"
                Fields(field, fieldNames, at)
                if not kinds[field.type] then Fail(at, "unsupported original common-settings field type") end
                String(field.label, at .. ".label", true)
                String(field.description, at .. ".description", true)
                if field.disabled ~= nil and type(field.disabled) ~= "boolean" then
                    Fail(at, "disabled must be boolean")
                end
                if field.type ~= "button" then String(field.path or field.key, at .. ".path/key") end
                if field.key ~= nil then String(field.key, at .. ".key") end
                if field.path ~= nil then String(field.path, at .. ".path") end
                if field.items ~= nil and (field.type ~= "dropdown" or type(field.items) ~= "table") then Fail(at, "items require dropdown") end
                if field.onClick ~= nil and (field.type ~= "button" or type(field.onClick) ~= "function") then Fail(at, "onClick requires an original button callback") end
                if field.presentation ~= nil and field.presentation ~= "switch" and field.presentation ~= "card" then
                    Fail(at, "presentation must be switch or card")
                end
                if field.valuePosition ~= nil and field.valuePosition ~= "right" and field.valuePosition ~= "top" then
                    Fail(at, "valuePosition must be right or top")
                end
                if field.fullWidth ~= nil and type(field.fullWidth) ~= "boolean" then
                    Fail(at, "fullWidth must be boolean")
                end
                if field.variant ~= nil and type(field.variant) ~= "string" then
                    Fail(at, "variant must be string")
                end
                for _, name in ipairs({ "row", "column", "controlWidth", "inputWidthPercent",
                    "minWidth", "preferredWidth", "width", "span" }) do
                    if field[name] ~= nil then Finite(field[name], at .. "." .. name) end
                end
                for _, name in ipairs({ "row", "column", "span" }) do
                    if field[name] ~= nil and (field[name] < 1 or field[name] % 1 ~= 0) then
                        Fail(at, name .. " must be a positive integer")
                    end
                end
                for _, name in ipairs({ "min", "max", "step" }) do
                    if field[name] ~= nil then
                        if field.type ~= "slider" then Fail(at, "numeric bounds only apply to original slider") end
                        Finite(field[name], at .. "." .. name)
                    end
                end
            end
        end
    end
    function Grid:ValidateSettingsDeclaration(declaration, context)
        context = context or {}
        local location = CardLocation(context, "sections")
        local ok, reason = pcall(function()
            Fields(declaration, { version=true, title=true, description=true, sections=true }, location)
            if declaration.version ~= 1 then Fail(location, "typed sections require version=1") end
            String(declaration.title, location .. ".title", true)
            String(declaration.description, location .. ".description", true)
            Array(declaration.sections, location)
            local ids = {}
            for index, section in ipairs(declaration.sections) do
                local at = location .. "[" .. index .. "]"
                if type(section) ~= "table" or not sectionFields[section.kind] then
                    Fail(at, "kind must be settings, table, composite, or custom; special pages retain their cards declaration")
                end
                Fields(section, sectionFields[section.kind], at)
                String(section.id, at .. ".id")
                if ids[section.id] then Fail(at, "duplicate section id " .. section.id) end
                ids[section.id] = true
                at = CardLocation(context, section.id)
                String(section.title, at .. ".title")
                if type(section.description) == "table" then
                    if section.kind ~= "settings" then Fail(at, "identified descriptions require a settings section") end
                    Fields(section.description, { key=true, type=true, label=true, fontSize=true }, at .. ".description")
                    if section.description.type ~= "description" then Fail(at, "identified description must retain type=description") end
                    Key(section.description.key, at .. ".description.key")
                    String(section.description.label, at .. ".description.label", true)
                    if section.description.label == nil then Fail(at, "identified description requires label") end
                    if section.description.fontSize ~= nil then
                        Finite(section.description.fontSize, at .. ".description.fontSize")
                        if section.description.fontSize <= 0 then Fail(at, "description fontSize must be positive") end
                    end
                else String(section.description, at .. ".description", true) end
                if section.binding ~= nil and type(section.binding) ~= "string" and type(section.binding) ~= "table" then
                    Fail(at, "binding must reference the original named or complete binding object")
                end
                local keys = {}
                if type(section.description) == "table" then keys[section.description.key] = true end
                if section.kind == "settings" then
                    Array(section.items, at .. ".items")
                    for ordinal, item in ipairs(section.items) do
                        local where = at .. ".items[" .. ordinal .. "]"
                        if type(item) == "table" and item.controls ~= nil then
                            Fields(item, { label=true, controls=true }, where)
                            String(item.label, where .. ".label")
                            if Array(item.controls, where .. ".controls") == 0 then Fail(where, "control row cannot be empty") end
                            for index, control in ipairs(item.controls) do
                                local cell = where .. ".controls[" .. index .. "]"
                                Fields(control, { type=true, key=true, label=true, presentation=true,
                                    parentKey=true, subKey=true, setKey=true }, cell)
                                if control.type ~= "switch" then Fail(cell, "control row requires original independent switches") end
                                Item(control, cell, keys, false, context.moduleKey or context.pageId)
                            end
                        else
                            Item(item, where, keys, false, context.moduleKey or context.pageId)
                        end
                    end
                    if section.footerDescription ~= nil then
                        local footer = section.footerDescription
                        Fields(footer, { key=true, type=true, label=true, fontSize=true }, at .. ".footerDescription")
                        if footer.type ~= "description" then Fail(at, "footer must retain its original description factory") end
                        Key(footer.key, at .. ".footerDescription.key")
                        if keys[footer.key] then Fail(at, "duplicate footer key " .. footer.key) end
                        keys[footer.key] = true
                        String(footer.label, at .. ".footerDescription.label", true)
                        if footer.label == nil then Fail(at, "footer description requires label") end
                        if footer.fontSize ~= nil then
                            Finite(footer.fontSize, at .. ".footerDescription.fontSize")
                            if footer.fontSize <= 0 then Fail(at, "footer fontSize must be positive") end
                        end
                    end
                elseif section.kind == "table" then
                    local columns = Array(section.columns, at .. ".columns")
                    if columns == 0 then Fail(at, "table requires columns") end
                    for ordinal, column in ipairs(section.columns) do
                        Fields(column, { title=true }, at .. ".columns[" .. ordinal .. "]")
                        String(column.title, at .. ".column.title", true)
                        if column.title == nil then Fail(at, "column title is required") end
                    end
                    if type(section.supportsAdd) ~= "boolean" then Fail(at, "supportsAdd must be a boolean") end
                    if section.controlFactory ~= nil then
                        String(section.controlFactory, at .. ".controlFactory")
                        if not self.TableControls or not self.TableControls[section.controlFactory] then
                            Fail(at, "unregistered table control factory")
                        end
                        Key(section.key, at .. ".key")
                        String(section.parentKey, at .. ".parentKey", true)
                        for _, name in ipairs({ "subKey", "setKey" }) do
                            if section[name] ~= nil then Key(section[name], at .. "." .. name) end
                        end
                        if section.add ~= nil or section.records ~= nil then
                            Fail(at, "controlFactory excludes literal add/records")
                        end
                    else
                    for _, name in ipairs({ "key", "parentKey", "subKey", "setKey" }) do
                        if section[name] ~= nil then Fail(at, name .. " requires controlFactory") end
                    end
                    if section.supportsAdd then
                        TableRow(section.add, columns, at .. ".add", keys)
                    elseif section.add ~= nil then Fail(at, "supportsAdd=false forbids add") end
                    Array(section.records, at .. ".records")
                    for ordinal, row in ipairs(section.records) do
                        TableRow(row, columns, at .. ".records[" .. ordinal .. "]", keys)
                    end
                    end
                elseif section.kind == "composite" then
                    Key(section.key, at .. ".key")
                    String(section.component, at .. ".component")
                    local valid, why = ValidateCardContent(self, section, at)
                    if not valid then Fail(at, why) end
                    String(section.parentKey, at .. ".parentKey", true)
                    for _, name in ipairs({ "subKey", "setKey" }) do
                        if section[name] ~= nil and type(section[name]) ~= "string" and type(section[name]) ~= "number" then
                            Fail(at, name .. " must retain its original string or numeric key")
                        end
                    end
                    if section.opts ~= nil and type(section.opts) ~= "table" then Fail(at, "opts must be original component options") end
                    CompositeOptions(section, at)
                else
                    String(section.renderer, at .. ".renderer")
                    if section.key ~= nil then Key(section.key, at .. ".key") end
                    String(section.parentKey, at .. ".parentKey", true)
                    for _, name in ipairs({ "subKey", "setKey" }) do
                        if section[name] ~= nil and type(section[name]) ~= "string" and type(section[name]) ~= "number" then
                            Fail(at, name .. " must retain its original string or numeric key")
                        end
                    end
                    if section.opts ~= nil and type(section.opts) ~= "table" then
                        Fail(at, "opts must be the original custom renderer options")
                    end
                    local valid, why = ValidateCardContent(self, section, at)
                    if not valid then Fail(at, why) end
                end
            end
        end)
        if not ok then return nil, reason end
        return true
    end

    local specializationClasses = {}
    for _, class in ipairs({
        { "死亡骑士", 250,251,252 }, { "战士", 73,71,72 }, { "圣骑士", 66,70,65 },
        { "猎人", 255,254,253 }, { "萨满祭司", 262,263,264 }, { "唤魔师", 1467,1473,1468 },
        { "恶魔猎手", 581,577,1480 }, { "潜行者", 260,259,261 }, { "武僧", 268,269,270 },
        { "德鲁伊", 104,103,102,105 }, { "法师", 64,63,62 }, { "术士", 267,265,266 }, { "牧师", 256,257,258 },
    }) do
        for index=2,#class do specializationClasses[class[index]] = class[1] end
    end
    local function SpecializationPresentation(cardState, item)
        local moduleKey = cardState.binding.moduleKey
        local mode = moduleKey == "ExClass.SpellQueue" and "specQueue"
            or (moduleKey == "ExClass.SpellEffectAlpha" and "specAlpha" or nil)
        if not mode or (item.parentKey ~= "specs" and item.parentKey ~= "specsAI")
            or (mode == "specQueue" and item.type ~= "input")
            or (mode == "specAlpha" and item.type ~= "slider") then return end
        -- This lookup only selects the two already-approved visual exceptions;
        -- the original numeric/string key itself is never rewritten.
        local class = specializationClasses[tonumber(item.key)]
        if class then return mode, class end
    end
    local function ControlSource(item, ordinal, cardState)
        local source = CopyShallow(item)
        source.type = item.type == "switch" and "checkbox" or item.type
        source.description, source.optionsSource, source.baseLabel = nil, nil, nil
        if SpecializationPresentation(cardState, item) == "specQueue" then
            source.labelPos, source.labelSize = "left", 18
        end
        if item.type == "select" then
            source.options = nil
            source.multiple = nil
            source.media = nil
            source.originalOptions = nil
            if item.multiple == true then source.type = "multiselect" end
            if item.media == "sound" then
                source.type = "lsm_sound"
            elseif item.media == "background" then
                source.type = "lsm_background"
            elseif item.media == "border" then
                source.type = "lsm_border"
            elseif item.originalOptions ~= nil then
                -- Preserve the original list reference, including tuple metadata;
                -- providers have already run at their original declaration site.
                source.items = item.originalOptions
            elseif item.optionsSource then
                -- The same original provider is resolved by CreateWidget.
                local provider = _G
                for part in item.optionsSource:gmatch("[^%.]+") do
                    provider = type(provider) == "table" and provider[part] or nil
                end
                if type(provider) ~= "function" then
                    Fail(item.key, "optionsSource does not name a registered original provider: " .. item.optionsSource)
                end
                source.items = "func:" .. item.optionsSource
            else
                source.items = {}
                for _, option in ipairs(item.options) do
                    source.items[#source.items + 1] = { option.label, option.value }
                end
            end
        end
        source.x, source.y, source.w, source.h = 1, ordinal, CARD_GRID_COLS, 1
        source.measure = { preferredHeight=GM.size.controlHeight, minHeight=GM.size.controlHeight }
        return source
    end
    local function BuildTypedTable(section, resolve)
        local rows, columns = {}, {}
        for index, column in ipairs(section.columns) do columns[index] = { title=column.title, weight=1 } end
        local widths = { switch=64, itemenabled=64, itemquantity=100, itemdelete=96, button=96 }
        local function Row(record, add)
            local row = { cells={} }
            for index, item in ipairs(record.cells) do
                if item.text ~= nil then
                    row.cells[index] = { text=item.text, icon=item.icon, itemID=item.itemID }
                    if item.icon then columns[index].weight = 1.6 end
                else
                    local widget, borrowedKind = resolve(item)
                    row.cells[index] = { widget=widget,
                        ordinaryControl=item.type ~= "actions" and not tableInformationTypes[item.type], borrowedKind=borrowedKind,
                        hideLabel=#columns > 1,
                        valuePosition=item.type == "slider" and "right" or nil,
                        presentation=add and item.type == "button" and "primary" or nil }
                    local fixed = widths[item.type]
                    if fixed and #columns > 1 then columns[index].width = math.max(columns[index].width or 0, fixed) end
                    if item.icon then columns[index].weight = 1.6 end
                end
            end
            rows[#rows + 1] = row
        end
        -- The only table row assembler serves factories and borrowed controls.
        if section.supportsAdd then Row(section.add, true) end
        for _, record in ipairs(section.records) do Row(record, false) end
        return rows, columns
    end
    local function PrepareTypedCard(cardState)
        local ok, why = EXUI:PrepareSettingsListCard(cardState.card, {})
        if not ok then Fail(CardLocation(cardState.session.context, cardState.id), tostring(why)) end
    end

    local function BuildTypedBody(grid, cardState)
        local section = cardState.definition
        if section.kind == "table" and section.controlFactory then
            cardState.sourceItems = {{ key=section.key, type="custom",
                parentKey=section.parentKey, subKey=section.subKey, setKey=section.setKey,
                _tableControls=section.controlFactory, _tableSection=section,
                x=1, y=1, w=CARD_GRID_COLS, h=1 }}
            MountCardBody(grid, cardState)
            PrepareTypedCard(cardState)
            return
        end
        if section.kind == "composite" or section.kind == "custom" then
            cardState.sourceItems = BuildCardContentSource(cardState, section)
            MountCardBody(grid, cardState)
            PrepareTypedCard(cardState)
            return
        end
        local sources = {}
        local function Add(item)
            if item.text == nil then sources[#sources + 1] = ControlSource(item, #sources + 1, cardState) end
        end
        if type(section.description) == "table" then Add(section.description) end
        if section.kind == "settings" then
            for _, item in ipairs(section.items) do
                if item.controls then
                    for _, control in ipairs(item.controls) do Add(control) end
                else
                    Add(item)
                    if type(item.description) == "table" then Add(item.description) end
                end
            end
            if section.footerDescription then Add(section.footerDescription) end
        else
            if section.supportsAdd then for _, item in ipairs(section.add.cells) do Add(item) end end
            for _, row in ipairs(section.records) do for _, item in ipairs(row.cells) do Add(item) end end
        end
        cardState.sourceItems = sources
        MountCardBody(grid, cardState)
        local rows, columns = {}, nil
        local function Widget(item)
            local widget = cardState.session:GetWidget(cardState.id, item.key)
            if not widget then Fail(CardLocation(cardState.session.context, cardState.id), "factory did not mount " .. item.key) end
            return widget
        end
        local sectionDescriptionWidget = type(section.description) == "table"
            and Widget(section.description) or nil
        local footerDescriptionWidget = section.footerDescription and Widget(section.footerDescription) or nil
        local externalDescriptions = {}
        if sectionDescriptionWidget then externalDescriptions[#externalDescriptions + 1] = sectionDescriptionWidget end
        if footerDescriptionWidget then externalDescriptions[#externalDescriptions + 1] = footerDescriptionWidget end
        cardState.settingsDescriptionWidgets = #externalDescriptions > 0 and externalDescriptions or nil
        if cardState.settingsSection then
            cardState.settingsSection._exSettingsSectionDescriptionWidgets = cardState.settingsDescriptionWidgets or {}
        end
        if section.kind == "settings" then
            local lastClass, classRow
            for _, item in ipairs(section.items) do
                if item.controls then
                    local row = { label=item.label, controls={} }
                    for _, control in ipairs(item.controls) do
                        row.controls[#row.controls+1] = {
                            widget=Widget(control), presentation=control.presentation or "card", hideLabel=false,
                        }
                    end
                    rows[#rows+1] = row
                    lastClass, classRow = nil, nil
                else
                local mode, class = SpecializationPresentation(cardState, item)
                if mode then
                    if lastClass ~= class then
                        classRow = { label=L[class], controls={}, controlsLayout=mode }
                        rows[#rows+1] = classRow
                    end
                    classRow.controls[#classRow.controls+1] = { widget=Widget(item), hideLabel=false }
                    lastClass = class
                else
                    rows[#rows + 1] = { widget=Widget(item), label=item.label,
                        description=type(item.description) == "string" and item.description or nil,
                        descriptionWidget=type(item.description) == "table" and Widget(item.description) or nil,
                        inputWidthPercent=item.inputWidthPercent,
                        -- [WEB-REQ 26] 单个 switch 项必须透传声明的 card；未声明才用默认的 switch 开关。
                        presentation=item.type == "switch" and (item.presentation or "switch") or nil }
                    lastClass, classRow = nil, nil
                end
                end
            end
            -- A retained footer FontString is displayed below the external section
            -- title, never as an independent gray row inside the settings card.
        else
            rows, columns = BuildTypedTable(section, Widget)
        end
        PrepareTypedCard(cardState)
        local list = grid:MountSettingsList(cardState.body, {
            columns=columns, externalDescriptionWidgets=cardState.settingsDescriptionWidgets,
            externalDescriptionFontSize=(sectionDescriptionWidget and section.description.fontSize)
                or (section.footerDescription and section.footerDescription.fontSize) or nil,
            sections={{ rows=rows }},
        })
        list.card = cardState.card
    end

    -- This entry borrows existing same-parent regions. It never becomes their
    -- factory/pool/data owner and never reparents or rewires them.
    function Grid:MountSettingsForm(parent, declaration, context)
        context = context or {}
        local at = CardLocation(context, type(declaration) == "table" and declaration.id or "form")
        if not parent or type(parent.GetHeight) ~= "function" or type(parent.SetHeight) ~= "function" then
            Fail(at, "borrowed table requires its original parent")
        end
        Fields(declaration, { kind=true, id=true, title=true, description=true,
            columns=true, supportsAdd=true, add=true, records=true }, at)
        if declaration.kind ~= "table" then Fail(at, "borrowed form requires kind=table") end
        String(declaration.id, at .. ".id")
        if type(declaration.title) ~= "string" then Fail(at, "table title must be a string") end
        local descriptionWidget
        if type(declaration.description) == "table" then
            Fields(declaration.description, { widget=true, type=true }, at .. ".description")
            descriptionWidget = declaration.description.widget
            if declaration.description.type ~= "text"
                or (type(descriptionWidget) ~= "table" and type(descriptionWidget) ~= "userdata")
                or type(descriptionWidget.IsObjectType) ~= "function"
                or not descriptionWidget:IsObjectType("FontString")
                or type(descriptionWidget.GetStringHeight) ~= "function" then
                Fail(at, "description must borrow its original FontString")
            end
            for _, method in ipairs({ "GetParent", "GetNumPoints", "GetPoint", "GetWidth", "GetHeight",
                "SetWidth", "SetHeight", "SetSize", "IsShown", "ClearAllPoints", "SetPoint" }) do
                if type(descriptionWidget[method]) ~= "function" then Fail(at, "description lacks " .. method) end
            end
            if descriptionWidget:GetParent() ~= parent then Fail(at, "description must retain its original parent") end
        else
            String(declaration.description, at .. ".description", true)
        end
        local count = Array(declaration.columns, at .. ".columns")
        if count == 0 then Fail(at, "form requires columns") end
        for _, column in ipairs(declaration.columns) do
            Fields(column, { title=true }, at .. ".column")
            String(column.title, at .. ".column.title", true)
            if column.title == nil then Fail(at, "column title is required") end
        end
        if type(declaration.supportsAdd) ~= "boolean" then Fail(at, "supportsAdd must be boolean") end
        local kinds = { input=true, switch=true, select=true, slider=true, color=true, button=true, text=true, multiline=true, actions=true }
        local seen = {}
        if descriptionWidget then seen[descriptionWidget] = true end
        local function Row(row, location)
            Fields(row, { cells=true }, location)
            if Array(row.cells, location .. ".cells") ~= count then Fail(location, "cell count must match columns") end
            for index, cell in ipairs(row.cells) do
                local where = location .. ".cells[" .. index .. "]"
                if type(cell) == "table" and cell.text ~= nil then
                    Fields(cell, { text=true }, where)
                    if cell.text ~= "" then Fail(where, "borrowed table text must use its original FontString; only empty placeholders are allowed") end
                else
                    Fields(cell, { widget=true, type=true }, where)
                    if not kinds[cell.type] then Fail(where, "unsupported borrowed control kind") end
                    local widget = cell.widget
                    if type(widget) ~= "table" and type(widget) ~= "userdata" then
                        Fail(where, "borrowed control must be an original region")
                    end
                    for _, method in ipairs({ "GetParent", "GetNumPoints", "GetPoint", "GetWidth", "GetHeight",
                        "SetWidth", "SetHeight", "SetSize", "IsShown", "ClearAllPoints", "SetPoint" }) do
                        if type(widget[method]) ~= "function" then Fail(where, "borrowed region lacks " .. method) end
                    end
                    if widget:GetParent() ~= parent then
                        Fail(where, "borrowed control must be an existing same-parent region")
                    end
                    if cell.type == "actions" and widget._isCompositeHost ~= true then
                        Fail(where, "borrowed actions require their original CompositeHost")
                    end
                    if cell.type == "slider" and widget._gridType ~= "GridSlider" then
                        Fail(where, "borrowed slider requires its original GridSlider")
                    end
                    if cell.type == "text" and widget._gridType == nil
                        and (type(widget.IsObjectType) ~= "function" or not widget:IsObjectType("FontString")
                            or type(widget.GetStringHeight) ~= "function") then
                        Fail(where, "borrowed text must be the original FontString")
                    end
                    if seen[widget] then Fail(where, "borrowed control cannot appear twice") end
                    seen[widget] = true
                end
            end
        end
        if declaration.supportsAdd then Row(declaration.add, at .. ".add")
        elseif declaration.add ~= nil then Fail(at, "supportsAdd=false forbids add") end
        Array(declaration.records, at .. ".records")
        for index, row in ipairs(declaration.records) do Row(row, at .. ".records[" .. index .. "]") end
        local rows, columns = BuildTypedTable(declaration, function(cell)
            if cell.type == "actions" then return cell.widget end
            return cell.widget, cell.widget._gridType == nil and cell.type or nil
        end)
        local height = parent:GetHeight()
        local mounted, list = pcall(self.MountSettingsList, self, parent, {
            title=declaration.title ~= "" and declaration.title or nil,
            description=not descriptionWidget and declaration.description or nil,
            headingDescriptionWidgets=descriptionWidget and {descriptionWidget} or nil,
            externalDescriptionWidgets=descriptionWidget and {descriptionWidget} or nil,
            columns=columns, sections={{ rows=rows }} })
        if not mounted then parent:SetHeight(height); error(list, 0) end
        local release = list.Release
        function list:Release()
            if self.released then return end
            release(self)
            parent:SetHeight(height)
        end
        return list
    end

    -- Factories own original controls and callbacks only. The core owns every
    -- table row, header, measurement and layout; no module renderer is admitted.
    function Grid:RegisterTableControls(key, lifecycle)
        String(key, "table control factory")
        Fields(lifecycle, { mount=true, update=true, release=true }, key)
        for _, name in ipairs({ "mount", "update", "release" }) do
            if type(lifecycle[name]) ~= "function" then Fail(key, name .. " must be a function") end
        end
        local mount, update, release = lifecycle.mount, lifecycle.update, lifecycle.release
        local function ReleasePresentation(ctx)
            local list = ctx._tablePresentation
            ctx._tablePresentation = nil
            if list then list:Release() end
        end
        local function Layout(host, ctx, width)
            local list = ctx._tablePresentation
            if not list then Fail(key, "factory did not supply table controls") end
            local height = list:Relayout(width)
            host:SetHeight(math.max(1, height))
            return height
        end
        local adapter = {
            mount = function(host, ctx)
                ctx.ReleaseTablePresentation = function()
                    if ctx.IsCurrent and not ctx.IsCurrent() then return false end
                    ReleasePresentation(ctx)
                    return true
                end
                ctx.SetTableControls = function(first, second)
                    if ctx.IsCurrent and not ctx.IsCurrent() then return false end
                    local controls = first == ctx and second or first
                    Fields(controls, { add=true, records=true }, key .. ".controls")
                    if ctx._tablePresentation then Fail(key, "release presentation before replacing controls") end
                    local section = ctx.element._tableSection
                    ctx._tablePresentation = self:MountSettingsForm(host, {
                        kind="table", id=section.id, title="", columns=section.columns,
                        supportsAdd=section.supportsAdd, add=controls.add, records=controls.records,
                    }, { pageId=ctx.pageId, regionId=ctx.regionId, moduleKey=ctx.moduleKey })
                    Layout(host, ctx, ctx:GetContentWidth())
                    if ctx.RequestReflow then ctx:RequestReflow() end
                    return true
                end
                mount(host, ctx)
                if not ctx._tablePresentation then Fail(key, "mount must supply table controls") end
            end,
            update = function(host, ctx)
                update(host, ctx)
                if not ctx._tablePresentation then Fail(key, "update must supply table controls") end
            end,
            layout = Layout,
            release = function(host, ctx)
                -- Original controls must still be alive while their borrowed
                -- geometry is restored, even when construction failed.
                local presented, presentationReason = pcall(ReleasePresentation, ctx)
                local released, releaseReason = pcall(release, host, ctx)
                ctx.ReleaseTablePresentation, ctx.SetTableControls = nil, nil
                if not presented then error(presentationReason, 0) end
                if not released then error(releaseReason, 0) end
            end,
        }
        self.TableControls = self.TableControls or {}
        self.TableControls[key] = adapter
        return true
    end

    function Grid:CheckSettingsDeclarationBounds(session)
        local function Check(frames, location)
            local rectangles = {}
            for _, entry in ipairs(frames) do
                local frame = entry.frame
                if frame and frame:IsShown() and frame.GetRect then
                    local x, y, w, h = frame:GetRect()
                    if x and y and w and h and w > 0 and h > 0 then
                        for _, other in ipairs(rectangles) do
                            if frame:GetParent() == other.parent
                                and math.min(x+w, other.x+other.w) - math.max(x, other.x) > 0.5
                                and math.min(y+h, other.y+other.h) - math.max(y, other.y) > 0.5 then
                                Fail(location, "visible sibling overlap: " .. entry.key .. " / " .. other.key)
                            end
                        end
                        rectangles[#rectangles+1] = { x=x, y=y, w=w, h=h, parent=frame:GetParent(), key=entry.key }
                    end
                end
            end
        end
        local cards = {}
        if session.settingsHeading then cards[#cards+1] = { frame=session.settingsHeading, key="page heading" } end
        for _, section in ipairs(session.cards) do
            if section.visible then
                cards[#cards+1] = { frame=section.card, key=section.id }
                if section.settingsSection then
                    cards[#cards+1] = { frame=section.settingsSection, key=section.id .. " heading" }
                end
                local state, widgets = self.ContainerStates[section.body], {}
                for _, widget in ipairs(state and state.instances or {}) do
                    local meta = state.widgetMap[widget]
                    widgets[#widgets+1] = { frame=widget, key=tostring(meta and meta.item and meta.item.key or "control") }
                end
                Check(widgets, CardLocation(session.context, section.id))
            end
        end
        Check(cards, CardLocation(session.context, "sections"))
    end

    function CardSessionMixin:ReplaceSettingsSection(sectionId, replacement)
        if self.released or not self.typedSections then
            error("[ExwindGrid] ReplaceSettingsSection requires an active typed page", 2)
        end
        local cardState = self.byId[sectionId]
        if not cardState then error("[ExwindGrid] unknown section " .. tostring(sectionId), 2) end
        local previous = cardState.definition
        local location = CardLocation(self.context, sectionId)
        -- A presentation refresh cannot quietly select a different DB or binding.
        for _, field in ipairs({ "id", "kind", "title", "description", "binding",
            "component", "renderer", "controlFactory", "key", "parentKey", "subKey", "setKey" }) do
            if type(replacement) ~= "table" or replacement[field] ~= previous[field] then
                Fail(location, "ReplaceSettingsSection must preserve " .. field .. "; remount the original page explicitly")
            end
        end
        local declaration = CopyShallow(self.declaration)
        declaration.sections = {}
        local replacedIndex
        for index, section in ipairs(self.declaration.sections) do
            declaration.sections[index] = section.id == sectionId and replacement or section
            if section.id == sectionId then replacedIndex = index end
        end
        local valid, reason = self.grid:ValidateSettingsDeclaration(declaration, self.context)
        if not valid then error(reason, 2) end
        local oldOptions, newOptions = previous.opts or {}, replacement.opts or {}
        for _, field in ipairs({ "bindRoot", "bindValue", "offsetXKey", "offsetYKey", "attachEnabledKey", "attachTargetKey", "poolType" }) do
            if oldOptions[field] ~= newOptions[field] then
                Fail(location, "replacement changes original composite binding option " .. field)
            end
        end
        local function Controls(section)
            local indexed = {}
            local function Add(item)
                for _, control in ipairs(item.controls or {}) do Add(control) end
                if item.key ~= nil then indexed[item.key] = item end
                if type(item.description) == "table" then Add(item.description) end
            end
            if type(section.description) == "table" then Add(section.description) end
            if section.footerDescription then Add(section.footerDescription) end
            for _, item in ipairs(section.items or {}) do Add(item) end
            if section.add then for _, item in ipairs(section.add.cells) do Add(item) end end
            for _, row in ipairs(section.records or {}) do for _, item in ipairs(row.cells) do Add(item) end end
            for _, field in ipairs(section.opts and section.opts.fields or {}) do
                local key = field.key or field.path
                if key ~= nil then indexed[key] = field end
            end
            return indexed
        end
        local oldControls = Controls(previous)
        for key, control in pairs(Controls(replacement)) do
            local old = oldControls[key]
            if old then
                if (old.multiple == true) ~= (control.multiple == true) then
                    Fail(location, "replacement changes original select mode for " .. tostring(key))
                end
                for _, field in ipairs({ "type", "media", "parentKey", "subKey", "setKey", "path" }) do
                    if old[field] ~= control[field] then
                        Fail(location, "replacement changes original control " .. tostring(key) .. " binding/type field " .. field)
                    end
                end
            end
        end
        -- New/deleted record keys and display itemID are legitimate dynamic UI;
        -- closure identity is not a data-binding identity and is not compared.
        local snapshot = SnapshotGridActivation(self.grid)
        local ok, failure = pcall(function()
            ReleaseCardBody(self, cardState)
            cardState.definition, cardState.content = replacement, replacement
            BuildTypedBody(self.grid, cardState)
            self.declaration.sections[replacedIndex] = replacement
            self:Relayout()
            self.grid:IndexSettingsDeclarationWidgets(self, false)
        end)
        RestoreGridActivation(self.grid, snapshot)
        if not ok then
            -- Do not run a failed factory a second time or synthesize a fallback DB.
            self:Release()
            error("[ExwindGrid] " .. location .. ": section replacement failed: " .. tostring(failure), 0)
        end
        return true
    end

    function Grid:IndexSettingsDeclarationWidgets(session, activate)
        local widgets = session.typedWidgets or {}
        table.wipe(widgets)
        for _, section in ipairs(session.cards) do
            local state = self.ContainerStates[section.body]
            for key, widget in pairs(state and state.widgets or {}) do widgets[key] = widget end
        end
        session.typedWidgets = widgets
        -- Preserve the established public GUI lookup (including live_status).
        -- These are the original widget references, never configuration copies.
        if activate then self.Widgets = widgets end
    end

    function Grid:MountSettingsDeclaration(parent, declaration, context)
        if not parent then error("[ExwindGrid] typed declaration requires a parent", 2) end
        context = context or {}
        local valid, why = self:ValidateSettingsDeclaration(declaration, context)
        if not valid then error(why, 2) end
        if self.CardSessions[parent] and not self.CardSessions[parent].released then
            error("[ExwindGrid] release the previous page session before mounting", 2)
        end
        local session = setmetatable({ grid=self, parent=parent, declaration=declaration,
            context=context, cards={}, byId={}, diagnostics={}, _diagnosticKeys={},
            generation=1, hasSettingsList=true, typedSections=true }, { __index=CardSessionMixin })
        self.CardSessions[parent] = session
        self.CardSessionOwners[parent] = { session=session }
        local snapshot = SnapshotGridActivation(self)
        local mounted, reason = pcall(function()
            local title = declaration.title or context.settingsPageTitle
            local description = declaration.description or context.settingsPageDescription
            if title or description then
                session.settingsHeading = EXUI:CreateSettingsSection(parent, { kind="page", title=title, description=description })
            end
            local previous
            for _, section in ipairs(declaration.sections) do
                local card = EXUI:CreateSettingsCard(parent, {
                    id=section.id, title=section.title,
                })
                local cardState = { session=session, id=section.id, definition=section, content=section,
                    card=card, body=card:GetBody(), previous=previous, visible=true, widgetsByOrdinal={} }
                session.cards[#session.cards + 1], session.byId[section.id] = cardState, cardState
                previous = cardState
                self.CardSessionOwners[card] = { session=session, card=cardState }
                self.CardSessionOwners[cardState.body] = { session=session, card=cardState }
                -- Preserve the established resolver and its complete original source binding.
                cardState.binding = ResolveCardBinding(session, section, section)
                cardState.originalBinding = cardState.binding.source
                card:SetWidth(math.max(1, parent:GetWidth()))
                card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
                -- Normal typed sections always use the shared flat section heading.
                -- Special cards/settingsGroups retain their original collapse behavior.
                cardState.settingsSection = EXUI:CreateSettingsSection(parent,
                    { kind="section", title=section.title,
                        description=type(section.description) == "string" and section.description or nil,
                        descriptionWidgets=cardState.settingsDescriptionWidgets })
                BuildTypedBody(self, cardState)
                card:SetLayoutInvalidationHandler(function() self:RequestReflow(card) end)
            end
            session:Relayout()
        end)
        RestoreGridActivation(self, snapshot)
        if not mounted then
            local released, releaseReason = pcall(session.Release, session)
            if not released then reason = tostring(reason) .. "; cleanup: " .. tostring(releaseReason) end
            error(reason, 0)
        end
        self:IndexSettingsDeclarationWidgets(session, true)
        if not parent._exCardSessionSizeHook then
            parent._exCardSessionSizeHook = true
            parent:HookScript("OnSizeChanged", function(host, width)
                local active = Grid.CardSessions[host]
                if active and not active.released and active._lastParentWidth ~= width then
                    active._lastParentWidth = width
                    Grid:RequestReflow(host)
                end
            end)
        end
        session._lastParentWidth = parent:GetWidth()
        local scroll = context.scrollFrame
        if scroll and scroll.HookScript then
            local sessions = self.CardScrollSessions[scroll]
            if not sessions then sessions = setmetatable({}, { __mode="k" }); self.CardScrollSessions[scroll] = sessions end
            sessions[session] = true
            if not scroll._exGridCardSessionSizeHook then
                scroll._exGridCardSessionSizeHook = true
                scroll:HookScript("OnSizeChanged", function(host)
                    for active in pairs(Grid.CardScrollSessions[host] or {}) do
                        if not active.released then Grid:RequestReflow(active.parent) end
                    end
                end)
            end
        end
        return session
    end
end

-- Unified mounted-page accessors.  Shared page/preview code should use these
-- instead of assuming that every control lives directly in ContainerStates.
-- The legacy single-grid route remains the fallback when no card session owns
-- the supplied container.
function Grid:GetMountedCardSession(container)
    local session = container and self.CardSessions[container] or nil
    if session and not session.released then return session end
    return nil
end

function Grid:GetMountedOwner(container)
    local session = self:GetMountedCardSession(container)
    if session then return session end
    return container and self.ContainerStates[container] or nil
end

function Grid:IsMountedOwnerCurrent(container, owner)
    if not container or not owner then return false end
    local session = self:GetMountedCardSession(container)
    if session then return session == owner end
    return self.ContainerStates[container] == owner
end

function Grid:GetMountedContainerStates(container)
    local mounted = {}
    local session = self:GetMountedCardSession(container)
    if session then
        for _, cardState in ipairs(session.cards) do
            local state = self.ContainerStates[cardState.body]
            if state then
                mounted[#mounted + 1] = {
                    state = state,
                    container = cardState.body,
                    cardId = cardState.id,
                }
            end
        end
        return mounted, session
    end

    local state = container and self.ContainerStates[container] or nil
    if state then
        mounted[1] = { state = state, container = container }
    end
    return mounted, state
end

function Grid:FindMountedWidget(container, widgetKey, cardId)
    local session = self:GetMountedCardSession(container)
    if session then
        local widget, resolvedCardId
        if cardId ~= nil then
            widget = session:GetWidget(cardId, widgetKey)
            resolvedCardId = cardId
        else
            widget, resolvedCardId = session:FindWidget(widgetKey)
        end
        local cardState = resolvedCardId and session.byId[resolvedCardId] or nil
        local body = cardState and cardState.body or nil
        local state = body and self.ContainerStates[body] or nil
        return widget, state, resolvedCardId, body
    end

    local state = container and self.ContainerStates[container] or nil
    local widget = state and state.widgets and state.widgets[widgetKey] or nil
    return widget, state, nil, container
end

function Grid:RefreshMountedValues(container)
    local session = self:GetMountedCardSession(container)
    if session then
        session:RefreshValues()
        return true
    end
    if container and self.ContainerStates[container] then
        self:RefreshContainerControlsFromDB(container)
        return true
    end
    return false
end

function Grid:GetLiveCardSession()
    local session = self.LiveCardSession
    if session and not session.released then return session end
    session = self.LiveContainer and self:GetMountedCardSession(self.LiveContainer) or nil
    return session
end

local function HideEditorGuideSet(lines)
    for _, region in ipairs(lines or {}) do
        if region and region.Hide then region:Hide() end
    end
end

function Grid:ActivateLiveEditContainer(container)
    if not self.IsLiveEditing or not container then return false end
    local state = self.ContainerStates[container]
    if not state then return false end

    if self.LiveEditContainer ~= container then
        HideEditorGuideSet(self.GridLines)
        HideEditorGuideSet(self.RowGuides)
    end
    ActivateContainerState(self, container, state)
    self.LiveEditContainer = container
    self:UpdateMetrics(container:GetWidth(), container)
    self:DrawEditorGrid(container)
    self:DrawRowGuides(container)
    return true
end

function Grid:WrapCardBodyForLiveEdit(cardState)
    if not cardState or not cardState.body or cardState.content.kind ~= "grid" then return false end
    local state = self.ContainerStates[cardState.body]
    if not state then return false end
    for key, widget in pairs(state.widgets or {}) do
        self:WrapWidgetForEdit(widget, key, cardState.body)
    end
    return true
end

-- Flat 页面继续直接 Render；Card 页面则只重建被编辑的 Body，并继续使用原
-- Card session 做测量、定位与回收。这样在线编辑不会把多卡声明压成一张平面表。
function Grid:RefreshLiveEditLayout(container)
    container = container or self.LiveEditContainer or self.LiveContainer
    local owner = container and self.CardSessionOwners[container]
    if owner and owner.session and owner.card and not owner.session.released then
        local session, cardState = owner.session, owner.card
        if cardState.content.kind ~= "grid" then return false end
        session:ReplaceCardContent(cardState.id, cardState.content)
        self:ActivateLiveEditContainer(cardState.body)
        self:WrapCardBodyForLiveEdit(cardState)
        if self.PropPanel then self.PropPanel:Hide() end
        self.Cur = nil
        return true
    end

    if not container then return false end
    self:Render(container, self.ActiveLayout, self.LastConfig, self.ModuleKey)
    return true
end

function Grid:ToggleLiveEdit(container)
    local cardSession = container and self:GetMountedCardSession(container) or nil
    if container and not cardSession then
        local state = GetContainerState(self, container)
        ActivateContainerState(self, container, state)
    end
    self.IsLiveEditing = not self.IsLiveEditing
    self.LiveContainer = container

    if self.IsLiveEditing then
        self.LiveCardSession = cardSession
        if cardSession then
            local firstEditable
            for _, cardState in ipairs(cardSession.cards) do
                if cardState.content.kind == "grid" then
                    firstEditable = firstEditable or cardState.body
                    self:WrapCardBodyForLiveEdit(cardState)
                end
            end
            if firstEditable then self:ActivateLiveEditContainer(firstEditable) end
        elseif container then
            self._activeContainer = container
            self.LiveEditContainer = container
            self:UpdateMetrics(container:GetWidth(), container)
            self:BeginModuleSpecExportSession(container)
            self:DrawEditorGrid(container)
            self:DrawRowGuides(container) -- [新增] 绘制行号尺
            for k, w in pairs(self.Widgets) do self:WrapWidgetForEdit(w, k, container) end
        end
        self:ShowToolbar(); self:ShowPalette(); self:CreatePropertyPanel()

        print(L["|cff00ffff[ExwindGrid]|r 编辑模式已激活。请在左侧点击行号进行管理。"])
    else
        HideEditorGuideSet(self.GridLines)
        HideEditorGuideSet(self.RowGuides)

        -- 恢复容器状态
        if container and not self.LiveCardSession then
            container:EnableMouse(false)
            -- 清理脚本以防万一
            if container.SetScript then
            end
        end

        if self.LiveCardSession and not self.LiveCardSession.released then
            for _, cardState in ipairs(self.LiveCardSession.cards) do
                local state = self.ContainerStates[cardState.body]
                for _, widget in ipairs(state and state.instances or {}) do
                    if widget.dragOverlay then widget.dragOverlay:Hide() end
                end
            end
        else
            for _, w in pairs(self.Widgets) do if w.dragOverlay then w.dragOverlay:Hide() end end
        end
        if self.LiveToolbar then self.LiveToolbar:Hide() end
        if self.Palette then self.Palette:Hide() end
        if self.PropPanel then self.PropPanel:Hide() end
        self.LiveCardSession = nil
        self.LiveEditContainer = nil
        self.Cur = nil
    end
end

function Grid:ShiftRows(startY, delta)
    for _, item in ipairs(self.ActiveLayout) do
        if item.y >= startY then
            item.y = item.y + delta
            self:RecordModuleSpecLayoutChange(item, { y = item.y })
        end
    end
    -- 修正可能的负数 y
    for _, item in ipairs(self.ActiveLayout) do
        if item.y < 1 then
            item.y = 1
            self:RecordModuleSpecLayoutChange(item, { y = item.y })
        end
    end
    self:RefreshLiveEditLayout(self.LiveEditContainer or self.LiveContainer)
end

function Grid:ShowRowContextMenu(row, x, y)
    EXUI:ShowContextMenu({
        title = string.format("%s %d", L["行"] or "Row", row),
        x = x, y = y,
        items = {
            { text = L["插入行"], icon = "add", onClick = function()
                Grid:ShiftRows(row, 1)
            end },
            { divider = true },
            { text = L["删除行"], icon = "delete", danger = true, onClick = function()
                Grid:ShiftRows(row + 1, -1)
            end },
        },
    })
end

function Grid:WrapWidgetForEdit(widget, key, container)
    local drag = widget.dragOverlay or CreateFrame("Button", nil, container, "BackdropTemplate")
    drag:SetParent(container)
    drag:ClearAllPoints()
    drag:SetPoint("TOPLEFT", widget, "TOPLEFT")
    drag:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT")
    drag:SetFrameStrata(container:GetFrameStrata())
    drag:SetFrameLevel((container:GetFrameLevel() or 0) + 20)
    drag:EnableMouse(true)
    drag:RegisterForClicks("LeftButtonUp", "RightButtonUp"); drag:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); drag
        :SetBackdropColor(0, 0.5, 1, 0.15); drag:Show(); widget.dragOverlay = drag
    if widget.SetMovable then widget:SetMovable(true) end
    drag:SetScript("OnMouseDown",
        function(f, b)
            Grid:ActivateLiveEditContainer(container)
            if b == "LeftButton" then
                widget:StartMoving(); widget.isDragging = true
            end
        end)
    drag:SetScript("OnMouseUp", function(f, b)
        if b == "RightButton" then
            Grid:ShowPropertyPanelFor(key); return
        end
        if widget.isDragging then
            widget:StopMovingOrSizing(); widget.isDragging = false
            local lx, ly = widget:GetLeft() - container:GetLeft(), widget:GetTop() - container:GetTop()
            local nx, ny = Grid:GetGridPos(lx + 2, ly - 2, container)

            -- [v2.0 Fix] 使用反向索引查找 LayoutItem，不再遍历 ActiveLayout
            -- 这样即便是 TableGroup 深层子元素也能被正确更新位置
            if Grid.WidgetMap and Grid.WidgetMap[widget] then
                local meta = Grid.WidgetMap[widget]
                local item = meta.item

                -- 检测碰撞
                -- 严格来说 IsAreaEmpty 应该检测全局防止重叠
                if Grid:IsAreaEmpty(nx, ny, item.w, item.h, item.key) then -- 这里暂时检测全局
                    item.x, item.y = nx, ny
                    Grid:RecordModuleSpecLayoutChange(item, { x = item.x, y = item.y })
                    Grid:RefreshPropertyPanelPosition(item)
                end

                -- 刷新
                Grid:RefreshLiveEditLayout(container)
            end
        end
    end)

    -- [Resizer] 右下角调整大小手柄
    if not drag.resizer then
        local r = CreateFrame("Button", nil, drag)
        r:SetSize(12, 12)
        r:SetPoint("BOTTOMRIGHT", 0, 0)
        r:EnableMouse(true)
        r:RegisterForClicks("LeftButtonUp")
        r:SetFrameLevel(drag:GetFrameLevel() + 1)
        local t = EXUI:CreateVisualTexture(r, EXEDITORFRAME)
        t:SetAllPoints(); t:SetColorTexture(1, 1, 0, 0.5)
        drag.resizer = r
    end

    -- GridCard 会经对象池复用；这里每次进入编辑模式都重新绑定手柄，避免旧
    -- 卡片/旧容器的闭包残留，同时不干预卡片本身的拖动路径。
    local r = drag.resizer
    r:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        Grid:ActivateLiveEditContainer(container)
        widget.isDragging = false
        drag.isResizing = true
        r:SetScript("OnUpdate", function()
            local mx, my = GetCursorPosition()
            local s = widget:GetEffectiveScale()
            mx, my = mx / s, my / s
            local wx, wy = widget:GetLeft(), widget:GetTop()
            local newW = (mx - wx) + 5
            local newH = (wy - my) + 5

            -- Dropdown/LSM 的固定高度不仅是最终渲染规则，也是 Grid 编辑
            -- 规则；否则预览会在重绘后回到固定高度（GM.size.dropdownHeight），但逻辑 h 已扩大，留下
            -- 看不见的碰撞占位。固定高度控件在编辑时只允许调整宽度。
            local fixedHeight = widget._exGridFixedHeight
            local previewHeight = fixedHeight or math.max(10, newH)
            widget:SetSize(math.max(10, newW), previewHeight)

            -- 可选：显示 Tooltip 提示当前 Grid 网格大小
            local gw = math.max(1, math.floor(newW / Grid.CellSize + 0.5))
            local meta = Grid.WidgetMap and Grid.WidgetMap[widget]
            local gh = fixedHeight and (meta and meta.item.h or 1)
                or math.max(1, math.floor(newH / Grid.CellSize + 0.5))
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format("W: %d  H: %d", gw, gh))
            GameTooltip:Show()
        end)
    end)
    r:SetScript("OnMouseUp", function()
        if drag.isResizing then
            drag.isResizing = false
            r:SetScript("OnUpdate", nil)
            GameTooltip:Hide()

            local mx, my = GetCursorPosition()
            local s = widget:GetEffectiveScale()
            mx, my = mx / s, my / s
            local wx, wy = widget:GetLeft(), widget:GetTop()

            -- Calculate new Width/Height in Grid Units
            local gw = math.max(1, math.floor(((mx - wx) + 10) / Grid.CellSize))
            local gh = math.max(1, math.floor(((wy - my) + 10) / Grid.CellSize))

            -- Update using Reverse Index
            if Grid.WidgetMap and Grid.WidgetMap[widget] then
                local meta = Grid.WidgetMap[widget]
                local item = meta.item
                if widget._exGridFixedHeight then
                    gh = item.h
                end
                if Grid:IsAreaEmpty(item.x, item.y, gw, gh, item.key) then
                    item.w, item.h = gw, gh
                    Grid:RecordModuleSpecLayoutChange(item, { w = item.w, h = item.h })
                end
                Grid:RefreshLiveEditLayout(container)
            end
        end
    end)
    drag.resizer:SetFrameLevel(drag:GetFrameLevel() + 1)
    drag.resizer:Show()
end

-- [新增] 绘制左侧行号 Excel 风格
function Grid:DrawRowGuides(container)
    local rowGuides = self.EditorRowGuidesByContainer[container]
    if not rowGuides then
        rowGuides = {}
        self.EditorRowGuidesByContainer[container] = rowGuides
    end
    self.RowGuides = rowGuides
    -- 先隐藏旧的
    for _, b in ipairs(rowGuides) do b:Hide() end

    local rowsToDraw = 100 -- 默认画 100 行，如果内容更多可以扩展

    for i = 1, rowsToDraw do
        local btn = rowGuides[i]
        if not btn then
            -- 使用 Button 模板，天生支持 OnClick，无报错风险
            btn = CreateFrame("Button", nil, container, "BackdropTemplate")
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8) -- 深灰色背景
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.3)
            btn:RegisterForClicks("RightButtonUp")   -- 只响右键即可，或者左键也没事

            -- 行号文字
            btn.text = EXUI:CreateVisualFontString(btn, EXFONTFRAME, "GameFontHighlightSmall")
            btn.text:SetPoint("CENTER", 0, 0)

            rowGuides[i] = btn
        end

        -- 更新以适应当前的 Parent (container)
        btn:SetParent(container)
        btn:SetSize(20, self.CellSize) --稍微变窄一点，减少遮挡
        -- 位置：x = 0 (Canvas左侧内部), y = 对应行的 grid y
        local padding = self:GetContainerPadding(container)
        local py = -(i - 1) * self.CellSize - padding.top
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, py)

        btn.text:SetText(i)

        -- 交互逻辑
        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                Grid:ActivateLiveEditContainer(container)
                -- 呼出菜单
                local mx, my = GetCursorPosition()
                local s = self:GetEffectiveScale()
                mx, my = mx / s, my / s
                Grid:ShowRowContextMenu(i, mx, my)
            end
        end)

        -- 鼠标悬停变色效果
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0, 0.6, 1, 0.8) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.2, 0.2, 0.2, 0.8) end)

        btn:Show()
    end
end

-- [v4.3.2] 统一物理像素线宽计算 (参考暴雪源码)
local function SetupLineThickness(line, pixelWidth)
    local scale = line:GetEffectiveScale()
    if _G.PixelUtil and _G.PixelUtil.GetNearestPixelSize then
        line:SetThickness(_G.PixelUtil.GetNearestPixelSize(pixelWidth, scale, pixelWidth))
    else
        line:SetThickness(pixelWidth)
    end
end

function Grid:DrawEditorGrid(canvas)
    local gridLines = self.EditorGridLinesByContainer[canvas]
    if not gridLines then
        gridLines = {}
        self.EditorGridLinesByContainer[canvas] = gridLines
    end
    self.GridLines = gridLines
    -- 清理旧的（由于 Line 和 Texture 是不同对象，需要彻底重置）
    for _, l in ipairs(gridLines) do
        if l.Hide then l:Hide() end
    end

    local idx = 1
    local linePixelWidth = 1.2 -- 稍微加粗，确保可见
    local gridAlpha = 0.15     -- 提高透明度，确保在深色背景下可见
    local padding = self:GetContainerPadding(canvas)
    local cols = self:GetContainerCols(canvas) or self.Cols

    -- 绘制垂直线
    for i = 0, cols do
        local l = gridLines[idx]
        if not l or (l.GetObjectType and l:GetObjectType() ~= "Line") then
            l = canvas:CreateLine(nil, "BACKGROUND")
            gridLines[idx] = l
        end

        l:SetColorTexture(1, 1, 1, gridAlpha)
        -- [Fix] 显式传入 canvas 作为锚点目标，防止坐标偏移
        l:SetStartPoint("TOPLEFT", canvas, padding.left + i * self.CellSize, 0)
        l:SetEndPoint("BOTTOMLEFT", canvas, padding.left + i * self.CellSize, -3000)
        SetupLineThickness(l, linePixelWidth)
        l:Show()
        idx = idx + 1
    end

    -- 绘制水平线
    for i = 0, 150 do
        local l = gridLines[idx]
        if not l or (l.GetObjectType and l:GetObjectType() ~= "Line") then
            l = canvas:CreateLine(nil, "BACKGROUND")
            gridLines[idx] = l
        end

        l:SetColorTexture(1, 1, 1, gridAlpha)
        -- [Fix] 显式传入 canvas 作为锚点目标
        l:SetStartPoint("TOPLEFT", canvas, 0, -padding.top - i * self.CellSize)
        l:SetEndPoint("TOPRIGHT", canvas, 0, -padding.top - i * self.CellSize)
        SetupLineThickness(l, linePixelWidth)
        l:Show()
        idx = idx + 1
    end
end

function Grid:ShowToolbar()
    if self.LiveToolbar then
        if self.LiveToolbar.ExportButton then
            self.LiveToolbar.ExportButton:SetText(self:GetLiveCardSession()
                and L["导出 Card 包"] or L["导出导入包"])
        end
        self.LiveToolbar:Show(); return
    end
    local tb = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tb:SetSize(500, 44)
    tb:SetPoint("TOP", 0, -10)
    tb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    tb:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    tb:SetFrameStrata("HIGH")

    local b1 = EXUI:CreateButton(tb, 140, 28,
        self:GetLiveCardSession() and L["导出 Card 包"] or L["导出导入包"],
        function() Grid:ExportImportPackage() end, { compact = true })
    b1:SetPoint("LEFT", 10, 0)
    tb.ExportButton = b1

    local b2 = EXUI:CreateButton(tb, 100, 28, L["保存退出"],
        function() Grid:ToggleLiveEdit(Grid.LiveContainer) end, { compact = true })
    b2:SetPoint("LEFT", 155, 0)

    local b3 = EXUI:CreateButton(tb, 100, 28, L["组件库"],
        function() if Grid.Palette:IsShown() then Grid.Palette:Hide() else Grid.Palette:Show() end end,
        { compact = true })
    b3:SetPoint("LEFT", 260, 0)

    local b4 = EXUI:CreateButton(tb, 125, 28, L["导出默认值"],
        function() Grid:ExportDefaultsImportPackage() end, { compact = true })
    b4:SetPoint("LEFT", 365, 0)

    self.LiveToolbar = tb
end

function Grid:ShowPalette()
    if self.Palette then
        self.Palette:Show(); return
    end
    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); p:SetSize(160, 500); p:SetPoint("RIGHT", -20, 0); p
        :SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); p
        :SetBackdropColor(0.1, 0.1, 0.1, 0.95); p:SetFrameStrata("HIGH"); p:EnableMouse(true); p:SetMovable(true); p
        :RegisterForDrag("LeftButton"); p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop",
        p.StopMovingOrSizing)
    local types = {
        { t = "checkbox", n = L["勾选框"] }, { t = "button", n = L["按钮"] }, { t = "slider", n = L["滑动条"] }, { t = "input", n = L["输入框"] },
        { t = "header", n = L["大标题"] }, { t = "subheader", n = L["中标题"] }, { t = "divider", n = L["分隔线"] },
        { t = "label", n = L["文本"] }, { t = "description", n = L["描述"] }, { t = "card", n = L["卡片"] }, { t = "modulecommonsettings", n = L["模块通用设置"] }, { t = "custom", n = L["自定义宿主"] }, { t = "color", n = L["颜色"] },
        { t = "dropdown", n = L["单选下拉"] }, { t = "multiselect", n = L["多选下拉"] },
        { t = "lsm_font", n = L["LSM字体"] }, { t = "lsm_sound", n = L["LSM音效"] },
        { t = "lsm_texture", n = L["LSM材质"] }, { t = "lsm_border", n = L["LSM边框"] }, { t = "lsm_background", n = L["LSM背景"] },
        { t = "fontgroup", n = L["字体组"] },
        { t = "widgetlayout", n = L["Widget排列"] }, { t = "texturegroup", n = L["材质组"] }
    }
    local y = -15
    for _, i in ipairs(types) do
        local b = EXUI:CreateButton(p, 140, 24, i.n, function()
                Grid:AddNewWidget(i.t, Grid.LiveEditContainer or Grid.LiveContainer)
            end, { compact = true })
        b:SetPoint("TOP", 0, y)
        y = y - 28
    end
    self.Palette = p
end

function Grid:AddNewWidget(t, c)
    c = c or self.LiveEditContainer or self.LiveContainer
    if c then self:ActivateLiveEditContainer(c) end
    local k = t .. "_" .. math.random(1000, 9999); local w, h = 12, 2
    if t == "checkbox" then
        w, h = 2, 2
    elseif t:find("header") or t == "divider" then
        w, h = 47, 1
    elseif t == "card" or t == "custom" or t == "modulecommonsettings" then
        w, h = 24, 8
    elseif t == "fontgroup" then
        w, h =
            47, 10
    elseif t == "widgetlayout" then
        w, h = 47, 10
    elseif t == "texturegroup" then
        w, h = 47, 21
    end
    local e = { key = k, type = t, x = 1, y = 1, w = w, h = h, label = L["新组件"] }
    if t == "card" then
        e.title = L["卡片标题"]
        e.desc = L["卡片描述"]
        e.allowOverlap = true
        e.accentAlign = "left"
    elseif t == "custom" then
        e.renderer = "Module.RendererKey"
        e.allowOverlap = false
    elseif t == "modulecommonsettings" then
        -- 直接使用正式 ModuleCommon 组件，不复制它的视觉常量；因此新增卡片的
        -- 背景、标题、绿色强调线与所有已封装设置组严格一致。
        e.label = L["模块通用设置"]
        -- 在线编辑器新增的它是可自由调整的背景卡片：与 card 一样不占用物理
        -- 碰撞格，也不把空 fields 的 20px 测量结果覆写用户声明的高度。
        e.allowOverlap = true
        e.measure = false
        e.opts = { bindRoot = true, fields = {}, gridEditableHeight = true }
    end
    if t == "slider" then
        e.min = 0; e.max = 100
    elseif t:find("dropdown") or t == "multiselect" then
        e.items = "A,B,C"
    end
    for i = 1, 200 do
        if t == "card" or t == "modulecommonsettings" or Grid:IsAreaEmpty(1, i, w, h) then
            e.y = i
            local owner = c and Grid.CardSessionOwners[c]
            if owner and owner.card and owner.card.content.kind == "grid" then
                table.insert(owner.card.content.items, e)
            else
                table.insert(Grid.ActiveLayout, e)
                Grid:RecordModuleSpecLayoutAddition(e)
            end
            break
        end
    end
    Grid:RefreshLiveEditLayout(c)
end

local function RemoveCardSourceItem(items, target)
    for index, item in ipairs(items or {}) do
        if item == target then
            table.remove(items, index)
            return true
        end
        if type(item.children) == "table" and RemoveCardSourceItem(item.children, target) then
            return true
        end
    end
    return false
end

function Grid:CreatePropertyPanel()
    if self.PropPanel then return end
    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); p:SetSize(320, 780); p:SetPoint("LEFT", 20, 0); p
        :SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }); p
        :SetBackdropColor(0.05, 0.05, 0.1, 0.98); p:SetFrameStrata("DIALOG"); p:EnableMouse(true); p:SetMovable(true); p
        :RegisterForDrag("LeftButton"); p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop",
        p.StopMovingOrSizing)
    local function CI(l, y)
        local f = CreateFrame("Frame", nil, p); f:SetSize(280, 50); f:SetPoint("TOPLEFT", 20, y)
        local fs = EXUI:CreateVisualFontString(f, EXFONTFRAME, "GameFontHighlightSmall"); fs:SetPoint("TOPLEFT", 0, 0); fs
            :SetText(l)
        local eb = EXUI:CreateEditBox(f, "", 280, 26); eb:SetPoint("TOPLEFT", 0, -18); f.eb = eb; f.fs = fs; return f
    end

    -- [UI Polish] 压缩纵向间距 (从 60px -> 50px)，让底部内容上移
    p.k = CI(L["唯一 Key (Grid ID):"], -40)
    p.sk = CI(L["DB Key (setKey, 可选):"], -90)
    p.l = CI(L["显示标签:"], -140)
    p.w = CI(L["宽度 (1-50):"], -190); p.h = CI(L["高度:"], -240)
    -- Grid 的实时拖动和此面板必须共用 layout item 的 x/y；不要把它们映射到
    -- 模块 AnchorController 的世界坐标，二者是不同层级的唯一位置来源。
    p.x = CI(L["X轴:"], -290); p.y = CI(L["Y轴:"], -340)
    p.i = CI(L["选项列表 (逗号分隔):"], -390)
    p.min = CI(L["Slider 最小值:"], -440); p.max = CI(L["Slider 最大值:"], -490)

    -- [New] 标签位置与大小 (现在整体上移了约 100px)
    p.lpos = CI("Label Pos (left / top...):", -540)
    p.lsize = CI("Label Size (10-30):", -590)

    -- [Core] 切换为实时交互模式：隐藏输入框
    p.lpos.eb:Hide(); p.lsize.eb:Hide()

    -- [New] 标签大小滑块 (实时生效)
    p.lsize.slider = EXUI:CreateSlider(p.lsize, 260, nil, 10, 32, 16, 1, nil, function(v)
        local e = Grid.Cur
        if e then
            e.labelSize = v
            Grid:RecordModuleSpecLayoutChange(e, { labelSize = e.labelSize })
            p.lsize.fs:SetText("Label Size: " .. v)
            if Grid.Widgets[e.key] then
                -- [Real-time] 立即更新样式
                EXUI:UpdateLabelStyle(Grid.Widgets[e.key], e.labelSize, e.labelPos)
            end
        end
    end)
    p.lsize.slider:SetPoint("TOPLEFT", 0, -20) -- 稍微靠左对齐

    -- 标签位置切换按钮 (实时生效)
    local function CreatePosBtn(txt, val, x)
        local b = CreateFrame("Button", nil, p.lpos, "UIPanelButtonTemplate")
        b:SetSize(60, 22)
        -- 紧贴 label 下方布局
        b:SetPoint("TOPLEFT", x, -18)
        b:SetText(txt)
        b:SetScript("OnClick", function()
            local e = Grid.Cur
            if e then
                e.labelPos = val
                if e._exCardSourceItem then e._exCardSourceItem.labelPos = val end
                Grid:RecordModuleSpecLayoutChange(e, { labelPos = e.labelPos })
                -- [Real-time] 立即更新样式
                if Grid.Widgets[e.key] then
                    EXUI:UpdateLabelStyle(Grid.Widgets[e.key], e.labelSize, e.labelPos)
                end
            end
        end)
        return b
    end
    p.lpos.b1 = CreatePosBtn("Left", "left", 0)
    p.lpos.b2 = CreatePosBtn("Top", "top", 70)
    p.lpos.b3 = CreatePosBtn("Right", "right", 140)
    p.lpos.b4 = CreatePosBtn("Default", nil, 210); p.lpos.b4:SetWidth(60)

    local s = EXUI:CreateButton(p, 130, 32, L["保存设置"], function()
        local e = Grid.Cur; if e then
            local before = { key = e.key, label = e.label, w = e.w, h = e.h, x = e.x, y = e.y }
            e.key = p.k.eb:GetText();
            -- [New] 保存 setKey
            local sk = p.sk.eb:GetText()
            e.setKey = (sk ~= "" and sk) or nil

            -- [修复] 将 UI 中的转义管道还原为普通管道存储
            e.label = p.l.eb:GetText():gsub("||", "|");
            e.w = tonumber(p.w.eb:GetText()) or e.w;
            e.h = tonumber(p.h.eb:GetText()) or e.h;
            -- 与 WrapWidgetForEdit 的拖动提交共用同一份 Grid layout 坐标。手输
            -- 坐标在保存后走 Render，因此页面会立即按新位置重新投影。
            e.x = math.max(1, math.floor(tonumber(p.x.eb:GetText()) or e.x or 1));
            e.y = math.max(1, math.floor(tonumber(p.y.eb:GetText()) or e.y or 1));
            if e.type == "slider" then
                e.min = tonumber(p.min.eb:GetText());
                e.max = tonumber(p.max.eb:GetText())
                -- [Revert] 移除 Step 保存逻辑
            end
            if p.i:IsShown() then
                local rawItems = p.i.eb:GetText():gsub("||", "|")
                if type(e.items) == "table" then
                    -- 表型下拉项用于结构化选项；属性面板当前仅做展示，不在这里降级成字符串
                else
                    e.items = rawItems
                end
            end

            local changes = {}
            for _, field in ipairs({ "key", "label", "w", "h", "x", "y" }) do
                if e[field] ~= before[field] then changes[field] = e[field] end
            end
            Grid:RecordModuleSpecLayoutChange(e, changes)
            if e._exCardSourceItem then
                -- nil 不能进入 changes 表；Card 纯声明需显式同步这些属性，
                -- 同时保持 legacy MODULE_SPEC 只接受原有可编辑字段的白名单。
                e._exCardSourceItem.setKey = e.setKey
                e._exCardSourceItem.min = e.min
                e._exCardSourceItem.max = e.max
                e._exCardSourceItem.items = e.items
            end

            -- [Core] Label 属性已由实时控件更新到 'e' 中，此处**不要**从隐藏的 EditBox 覆盖它们
        end
        p:Hide(); Grid:RefreshLiveEditLayout(Grid.LiveEditContainer or Grid.LiveContainer)
    end, { compact = true })
    s:SetPoint("BOTTOMLEFT", 20, 20)


    local d = EXUI:CreateButton(p, 130, 32, L["删除组件"], function()
        local current = Grid.Cur
        local source = current and current._exCardSourceItem
        local owner = Grid.LiveEditContainer and Grid.CardSessionOwners[Grid.LiveEditContainer]
        if source and owner and owner.card and owner.card.content.kind == "grid" then
            RemoveCardSourceItem(owner.card.content.items, source)
        else
            for i, e in ipairs(Grid.ActiveLayout) do
                if current and e.key == current.key then
                    Grid:RecordModuleSpecLayoutDeletion(e)
                    table.remove(Grid.ActiveLayout, i); break
                end
            end
        end
        p:Hide(); Grid:RefreshLiveEditLayout(Grid.LiveEditContainer or Grid.LiveContainer)
    end, { variant = "danger", compact = true })
    d:SetPoint("BOTTOMRIGHT", -20, 20)
    self.PropPanel = p
end

-- 拖动的写入点在 WrapWidgetForEdit；属性面板若正显示该 layout item，必须立刻
-- 回读同一 x/y，不能维护第二份面板位置缓存。
function Grid:RefreshPropertyPanelPosition(item)
    local panel = self.PropPanel
    if not panel or not panel:IsShown() or self.Cur ~= item then
        return
    end
    panel.x.eb:SetText(tostring(item.x or 1))
    panel.y.eb:SetText(tostring(item.y or 1))
end

function Grid:ShowPropertyPanelFor(key)
    if not self.IsLiveEditing then return end

    -- [v4.3.1] 递归查找，支持 TableGroup 内部组件
    local item = FindLayoutItem(self.ActiveLayout, key)
    if not item then
        print(L["[ExwindGrid] 错误: 未找到组件配置: "] .. key); return
    end

    local panel = self.PropPanel
    if not panel then
        self:CreatePropertyPanel(); panel = self.PropPanel
    end
    Grid.Cur = item

    -- [修复] 使用双管道转义，防止 UI 引擎在 EditBox 内直接渲染图标代码
    panel.k.eb:SetText(item.key or "")
    panel.sk.eb:SetText(item.setKey or item.subKey or "")
    panel.l.eb:SetText((item.label or ""):gsub("|", "||"))
    panel.w.eb:SetText(tostring(item.w or 10))
    panel.h.eb:SetText(tostring(item.h or 2))
    panel.x.eb:SetText(tostring(item.x or 1))
    panel.y.eb:SetText(tostring(item.y or 1))

    panel.i:Hide(); panel.min:Hide(); panel.max:Hide()
    if item.type:find("dropdown") or item.type == "multiselect" then
        panel.i:Show()
        local itemsText = ""
        if type(item.items) == "string" then
            itemsText = item.items
        elseif type(item.items) == "table" then
            local parts = {}
            for _, entry in ipairs(item.items) do
                if type(entry) == "table" then
                    local label = tostring(entry[1] or "")
                    local value = tostring(entry[2] or entry[1] or "")
                    if value ~= "" and value ~= label then
                        parts[#parts + 1] = label .. "=" .. value
                    else
                        parts[#parts + 1] = label
                    end
                else
                    parts[#parts + 1] = tostring(entry)
                end
            end
            itemsText = table.concat(parts, ", ")
        end
        panel.i.eb:SetText(itemsText:gsub("|", "||"))
    end
    if item.type == "slider" then
        panel.min:Show(); panel.max:Show()
        panel.min.eb:SetText(tostring(item.min or 0))
        panel.max.eb:SetText(tostring(item.max or 100))
    end

    -- [New] 回填实时控件的状态
    if panel.lsize and panel.lsize.slider then
        panel.lsize.slider:SetValue(item.labelSize or 16)
        panel.lsize.fs:SetText("Label Size: " .. (item.labelSize or 16))
    end
    -- LabelPos 按钮不需要回填状态，点击即生效

    panel:Raise()
    panel:Show()
end

function Grid:ExportLayout()
    if self:GetLiveCardSession() then
        error(L["[ExwindGrid] Card 页面必须导出完整 version=1/cards 声明，不能扁平化为 legacy layout"], 2)
    end
    local layoutStr = "local layout = {\n"
    local defaults = {}

    local replacements = self.ExportReplacements or {}
    local exportReferences = self.ExportReferences or {}
    local localeAPI = _G.ExwindLocale
    local localeReverseMap

    local function ShouldForceLocaleLabelExport()
        if type(localeAPI) ~= "table" then
            return false
        end

        local currentLocale = type(localeAPI.GetCurrentLocale) == "function" and localeAPI.GetCurrentLocale() or
            localeAPI._currentLocale
        return currentLocale == "zhCN" or currentLocale == "zhTW"
    end

    local function BuildLocaleReverseMap()
        if localeReverseMap then
            return localeReverseMap
        end

        localeReverseMap = {}
        if type(localeAPI) ~= "table" or type(localeAPI._stores) ~= "table" then
            return localeReverseMap
        end

        local function AddStore(store)
            if type(store) ~= "table" then
                return
            end
            for key, value in pairs(store) do
                if type(key) == "string" and type(value) == "string" and localeReverseMap[value] == nil then
                    localeReverseMap[value] = key
                end
            end
        end

        AddStore(localeAPI._stores[localeAPI._currentLocale])
        AddStore(localeAPI._stores[localeAPI._defaultLocale])

        return localeReverseMap
    end

    local function TryFormatLocalizedLabel(labelValue)
        if type(labelValue) ~= "string" or labelValue == "" then
            return nil
        end

        local reverseMap = BuildLocaleReverseMap()
        local localeKey = reverseMap[labelValue]
        if type(localeKey) == "string" and localeKey ~= "" then
            return string.format(", label = L[%q]", localeKey)
        end

        if ShouldForceLocaleLabelExport() then
            return string.format(", label = L[%q]", labelValue)
        end

        return nil
    end

    local function FormatLabelValue(item)
        if type(item.labelExpr) == "string" and item.labelExpr ~= "" then
            return ", label = " .. item.labelExpr
        end

        if type(item.baseLabel) == "string" and item.baseLabel ~= "" then
            if item.baseLabel:match("^L%[.*%]$") then
                return ", label = " .. item.baseLabel
            end
            local localizedBaseLabel = TryFormatLocalizedLabel(item.baseLabel)
            if localizedBaseLabel then
                return localizedBaseLabel
            end
            return string.format(", label = %q", item.baseLabel)
        end

        local localizedLabel = TryFormatLocalizedLabel(item.label)
        if localizedLabel then
            return localizedLabel
        end

        if type(item.label) == "string" then
            return string.format(", label = %q", item.label)
        end
        if type(item.label) == "number" then
            return string.format(", label = %q", tostring(item.label))
        end
        return ", label = \"--[[ Function ]]\""
    end

    -- Helper: 格式化值
    local function formatVal(val, keyName)
        if type(val) == "string" and replacements[val] then
            return ", " .. keyName .. " = " .. replacements[val]
        else
            return ", " .. keyName .. " = " .. string.format("%q", val)
        end
    end

    -- 递归导出核心
    local function recursiveExport(items, indent, contextPath)
        local str = ""
        local pad = string.rep("    ", indent)

        for _, e in ipairs(items) do
            -- 1. 确定当前组件的数据上下文
            local itemScope = contextPath
            if e.parentKey then
                itemScope = itemScope and (itemScope .. "." .. e.parentKey) or e.parentKey
            end
            local fullPath = itemScope and (itemScope .. "." .. e.key) or tostring(e.key)

            -- 2. 导出属性字符串构造
            local ex = ""
            if e.min then ex = ex .. ", min = " .. e.min end; if e.max then ex = ex .. ", max = " .. e.max end

            if e.opts ~= nil then
                local optsExpression = exportReferences[e.opts] or replacements[e.opts]
                if type(optsExpression) == "string" and optsExpression ~= "" then
                    ex = ex .. ", opts = " .. optsExpression
                elseif type(e.opts) == "table" then
                    -- table 内含函数时不能安全反序列化；留下可见标记，要求模块登记命名引用，
                    -- 禁止像旧实现那样静默丢掉 opts。
                    ex = ex .. ", --[[ opts: use Grid:RegisterExportReference(table, \"MODULE_OPTS\") ]]"
                end
            end

            if e.items and e.items ~= "" then
                if replacements[e.items] then
                    ex = ex .. ", items = " .. replacements[e.items]
                elseif type(e.items) == "string" and e.items:sub(1, 5) == "func:" then
                    ex = ex .. ", items = " .. string.format("%q", e.items)
                elseif type(e.items) == "table" then
                    local function serializeTable(t)
                        local s = "{"
                        for k, v in ipairs(t) do
                            if type(v) == "table" then
                                s = s .. serializeTable(v)
                            else
                                s = s .. string.format("%q", v)
                            end
                            if k < #t then s = s .. ", " end
                        end
                        return s .. "}"
                    end
                    ex = ex .. ", items = " .. serializeTable(e.items)
                else
                    ex = ex .. ", items = " .. string.format("%q", e.items)
                end
            end

            if e.parentKey then ex = ex .. formatVal(e.parentKey, "parentKey") end
            if e.setKey then ex = ex .. formatVal(e.setKey, "setKey") end
            if e.subKey then ex = ex .. formatVal(e.subKey, "subKey") end
            if e.labelPos then ex = ex .. ", labelPos = " .. string.format("%q", e.labelPos) end
            if e.labelSize and e.labelSize ~= 16 then ex = ex .. ", labelSize = " .. e.labelSize end

            local labelStr = FormatLabelValue(e)

            local keyExport = (type(e.key) == "number") and tostring(e.key) or string.format("%q", tostring(e.key))

            -- 3. 收集默认值（核心更新：全量收集与颜色处理）
            local function AddToDefaults(path, val)
                if val == nil then return end
                local pathKeys = { strsplit(".", tostring(path)) }
                local ptr = defaults
                for i = 1, #pathKeys - 1 do
                    local k = tonumber(pathKeys[i]) or pathKeys[i]
                    if not ptr[k] then ptr[k] = {} end
                    ptr = ptr[k]
                end
                local lastK = tonumber(pathKeys[#pathKeys]) or pathKeys[#pathKeys]
                ptr[lastK] = val
            end

            local keyStr = tostring(e.key)
            if keyStr and not keyStr:find("^header") and not keyStr:find("^divider") and e.type ~= "TableGroup" then
                -- 颜色组件特殊处理：导出后缀格式 (xxxR, xxxG, xxxB, xxxA)
                if e.type == "color" then
                    local colorConfig = contextPath and GetConfigPath(self.LastConfig, contextPath) or self.LastConfig
                    if colorConfig then
                        local colorKey = tostring(e.key)
                        local basePath = contextPath and (contextPath .. ".") or ""
                        AddToDefaults(basePath .. colorKey .. "R", colorConfig[colorKey .. "R"] or 1)
                        AddToDefaults(basePath .. colorKey .. "G", colorConfig[colorKey .. "G"] or 1)
                        AddToDefaults(basePath .. colorKey .. "B", colorConfig[colorKey .. "B"] or 1)
                        AddToDefaults(basePath .. colorKey .. "A", colorConfig[colorKey .. "A"] or 1)
                    end
                else
                    AddToDefaults(e.setKey or fullPath,
                        (e.setKey and self.LastConfig[e.setKey]) or GetConfigPath(self.LastConfig, fullPath))
                end
            end

            -- 4. 处理递归与动态列表补全
            if e.type == "TableGroup" then
                if e.children and #e.children > 0 then
                    -- 动态索引探测：如果当前是 rows.1，则扫描 rows.2, 3... 补全 defaults 表
                    local prefix, idx = tostring(e.parentKey):match("^(.-)%.(%d+)$")
                    if prefix and idx then
                        local collection = GetConfigPath(self.LastConfig, prefix)
                        if type(collection) == "table" then
                            for i in pairs(collection) do recursiveExport(e.children, indent + 1, prefix .. "." .. i) end
                        end
                    end
                    str = str ..
                        string.format(
                            "%s{ key = %s, type = %q, x = %d, y = %d, w = %d, h = %d%s%s, children = {\n%s%s} },\n",
                            pad, keyExport, e.type, e.x, e.y, e.w, e.h, labelStr, ex,
                            recursiveExport(e.children, indent + 1, itemScope), pad)
                end
            else
                str = str ..
                    string.format("%s{ key = %s, type = %q, x = %d, y = %d, w = %d, h = %d%s%s },\n", pad, keyExport,
                        e.type,
                        e.x, e.y, e.w, e.h, labelStr, ex)
            end
        end
        return str
    end

    layoutStr = layoutStr .. recursiveExport(self.ActiveLayout, 1, nil)
    layoutStr = layoutStr .. "}\n"

    -- 自动补充顶层必要字段（如 pos）
    if self.LastConfig and self.LastConfig.pos and not defaults.pos then
        defaults.pos = self.LastConfig.pos
    end

    return layoutStr, defaults
end

-- 序列化表为 Lua 代码字符串
local function serializeTable(t, indent, localizeLabels)
    local s = "{\n"

    -- 检测是否是连续数组
    local isArray = true
    local maxIndex = 0
    for k, _ in pairs(t) do
        if type(k) == "number" and k > 0 and math.floor(k) == k then
            if k > maxIndex then maxIndex = k end
        else
            isArray = false
            break
        end
    end
    if isArray and maxIndex > 0 then
        for i = 1, maxIndex do
            if t[i] == nil then
                isArray = false; break
            end
        end
    end

    if isArray and maxIndex > 0 then
        -- 连续数组：使用隐式索引
        for i = 1, maxIndex do
            local v = t[i]
            s = s .. string.rep("    ", indent)
            if type(v) == "table" then
                s = s .. serializeTable(v, indent + 1, localizeLabels) .. ",\n"
            elseif type(v) == "string" then
                s = s .. string.format("%q", v) .. ",\n"
            else
                s = s .. tostring(v) .. ",\n"
            end
        end
    else
        -- 非连续表：使用显式键
        local keys = {}
        for k in pairs(t) do table.insert(keys, k) end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

        for _, k in ipairs(keys) do
            local v = t[k]
            local keyStr
            if type(k) == "number" then
                keyStr = "[" .. k .. "]"
            elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
                keyStr = k
            else
                keyStr = "[" .. string.format("%q", k) .. "]"
            end
            s = s .. string.rep("    ", indent) .. keyStr .. " = "
            if type(v) == "table" then
                s = s .. serializeTable(v, indent + 1, localizeLabels) .. ",\n"
            elseif type(v) == "string" then
                if localizeLabels and k == "label" then
                    s = s .. "L[" .. string.format("%q", v) .. "],\n"
                else
                    s = s .. string.format("%q", v) .. ",\n"
                end
            else
                s = s .. tostring(v) .. ",\n"
            end
        end
    end
    return s .. string.rep("    ", indent - 1) .. "}"
end

-- Card session 的 declaration 是登记纯声明的运行副本，也是在线编辑的结构真源。
-- 导出必须整棵保留 version/cards/placement/content，禁止把各 Body 拼回 legacy layout。
function Grid:BuildCardPageExportData()
    local session = self:GetLiveCardSession()
    if not session then return nil end
    local moduleKey = session.context and session.context.moduleKey or self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出失败：当前页面没有模块标识"], 2)
    end
    local ok, reason = self:ValidateCardDeclaration(session.declaration, session.context)
    if not ok then error(reason, 2) end

    local defaults
    local declarations = ExwindTools.ModuleDefaultDeclarations
    if type(declarations) == "table" and declarations[moduleKey] then
        defaults = ExwindTools:ExportModuleDefaults(moduleKey)
    end
    return {
        moduleKey = moduleKey,
        gui = session.declaration,
        defaults = defaults,
    }
end

local function CopyModuleSpecExportValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then error(L["[ExwindGrid] MODULE_SPEC 导出不支持循环表"], 3) end
    local copied = {}
    seen[value] = true
    for key, child in pairs(value) do
        copied[CopyModuleSpecExportValue(key, seen)] = CopyModuleSpecExportValue(child, seen)
    end
    seen[value] = nil
    return copied
end

local function CopyAddedLayoutItem(value, seen)
    if type(value) ~= "table" then
        if type(value) == "function" then error(L["[ExwindGrid] 新增组件不能导出运行时回调"], 3) end
        return value
    end
    seen = seen or {}
    if seen[value] then error(L["[ExwindGrid] 新增组件不能导出循环表"], 3) end
    local copied = {}
    seen[value] = true
    for key, child in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
            copied[CopyAddedLayoutItem(key, seen)] = CopyAddedLayoutItem(child, seen)
        end
    end
    seen[value] = nil
    return copied
end

local function IndexModuleSpecGuiItems(items, index)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            local key = item.key and tostring(item.key) or nil
            if key then
                if index[key] then error(L["[ExwindGrid] MODULE_SPEC.gui 中存在重复 key："] .. key, 3) end
                index[key] = item
            end
            if type(item.children) == "table" then IndexModuleSpecGuiItems(item.children, index) end
        end
    end
end

local function PruneModuleSpecGuiItems(items, deletedKeys)
    local kept = {}
    for _, item in ipairs(items or {}) do
        if not deletedKeys[tostring(item.key)] then
            if type(item.children) == "table" then item.children = PruneModuleSpecGuiItems(item.children, deletedKeys) end
            kept[#kept + 1] = item
        end
    end
    return kept
end

local function ResolveCurrentModuleSpec(moduleKey)
    local getController = EXUI and EXUI.GetCentralModuleController
    local controller = type(getController) == "function" and getController(EXUI, moduleKey) or nil
    if type(controller) ~= "table" or type(controller.spec) ~= "table" then return nil end
    return CopyModuleSpecExportValue(controller.spec)
end

-- 将编辑会话投影回原 MODULE_SPEC 的可编辑部分。原始 gui 表是唯一真源：
-- 已有行仅允许改名称与格子位置/尺寸；删除与新增整行是仅有的结构性操作。
function Grid:BuildModuleSpecExportData()
    local moduleKey = self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出失败：当前页面没有模块标识"], 2)
    end

    local spec = ResolveCurrentModuleSpec(moduleKey)
    if not spec then return nil, L["当前页面没有可导出的模块定义"] end
    if type(spec.gui) ~= "table" or type(spec.gui.static) ~= "table" or type(spec.gui.fields) ~= "table" then
        error(L["[ExwindGrid] 当前 MODULE_SPEC 缺少 gui.static/gui.fields"], 2)
    end

    -- 正式 defaults 声明决定可导出的字段；这里读的是当前游戏内 ModuleDB，
    -- 不会把运行时缓存或未声明字段混进源码。
    spec.defaults = ExwindTools:ExportModuleDefaults(moduleKey)

    local session = GetExportSession(self)
    if session then
        local deletedKeys = {}
        for id in pairs(session.deleted) do
            local baseline = session.baseline[id]
            if baseline then deletedKeys[tostring(baseline.sourceKey)] = true end
        end
        spec.gui.static = PruneModuleSpecGuiItems(spec.gui.static, deletedKeys)
        spec.gui.fields = PruneModuleSpecGuiItems(spec.gui.fields, deletedKeys)

        local sourceByKey = {}
        IndexModuleSpecGuiItems(spec.gui.static, sourceByKey)
        IndexModuleSpecGuiItems(spec.gui.fields, sourceByKey)
        for id, changes in pairs(session.changes) do
            local baseline = session.baseline[id]
            local target = baseline and sourceByKey[tostring(baseline.sourceKey)] or nil
            if target then
                for _, field in ipairs({ "label", "x", "y", "w", "h" }) do
                    if changes[field] ~= nil then target[field] = changes[field] end
                end
            end
        end

        local activeByID = {}
        WalkLayoutItems(self.ActiveLayout, function(item)
            if item._exGridExportID then activeByID[item._exGridExportID] = item end
        end)
        for _, id in ipairs(session.addedOrder or {}) do
            if not session.deleted[id] then
                local item = activeByID[id]
                if item then spec.gui.static[#spec.gui.static + 1] = CopyAddedLayoutItem(item) end
            end
        end
    end

    return { defaults = spec.defaults, gui = spec.gui }
end

function Grid:BuildModuleSpecExport()
    local data, reason = self:BuildModuleSpecExportData()
    if not data then return nil, reason end
    return "local MODULE_SPEC = " .. serializeTable(data, 1)
end

-- SPECIAL 等旧页面可以没有 MODULE_SPEC 和源码 GUI 真源，但只要模块正式声明了
-- 默认值，就仍可安全导出 defaults；绝不从 Grid 工作布局反推或导出它的 layout。
function Grid:BuildDeclaredDefaultsExportData()
    local moduleKey = self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出默认值失败：当前页面没有模块标识"], 2)
    end
    local declarations = ExwindTools.ModuleDefaultDeclarations
    if type(declarations) ~= "table" or not declarations[moduleKey] then
        return nil, L["当前页面没有已声明的默认值真源"]
    end
    return { moduleKey = moduleKey, defaults = ExwindTools:ExportModuleDefaults(moduleKey) }
end

function Grid:ExportModuleSpec()
    local moduleSpecStr, reason = self:BuildModuleSpecExport()
    if not moduleSpecStr then
        print("|cffff8080[ExwindGrid]|r " .. (reason or L["当前页面没有可导出的模块定义"]))
        return false
    end
    EXUI:ShowDialog({
        sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
        id = "EX_EXPORT_MODULE_SPEC", title = L["复制 MODULE_SPEC（当前预设默认值与 GUI 布局）:"], width = 650,
        input = { text = moduleSpecStr:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
        cancelButton = "close", defaultButton = "close",
        buttons = { { id = "close", text = L["好的"], variant = "primary" } },
    })
end

-- 独立默认值包不读取 MODULE_SPEC.gui，也不读取在线编辑器的工作布局。
-- 因此 SPECIAL 旧页面只要正式声明 defaults，就能安全导出给离线导入器。
function Grid:ExportDefaultsImportPackage()
    local defaultData, reason = self:BuildDeclaredDefaultsExportData()
    if not defaultData then
        print("|cffff8080[ExwindGrid]|r " .. (reason or L["当前页面没有可导出的默认值真源"]))
        return false
    end
    local package = "-- EXWIND_GRID_DEFAULTS_IMPORT v1\n"
        .. "local EXWIND_GRID_DEFAULTS_IMPORT = {\n"
        .. "    moduleKey = " .. string.format("%q", defaultData.moduleKey) .. ",\n"
        .. "    defaults = " .. serializeTable(defaultData.defaults, 2) .. ",\n"
        .. "}\n"
    EXUI:ShowDialog({
        sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
        id = "EX_EXPORT_DEFAULTS_IMPORT_PACKAGE", title = L["复制默认值导入包（发送给 Codex 验收并导入）:"], width = 650,
        input = { text = package:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
        cancelButton = "close", defaultButton = "close",
        buttons = { { id = "close", text = L["好的"], variant = "primary" } },
    })
    return true
end

-- 标准模块一律导出带模块名的完整包。离线验收脚本会先验证模块名、GUI 白名单
-- 与 defaults 字段形状，全部通过后才允许将这两个区块写回 MODULE_SPEC。
function Grid:ExportImportPackage()
    local moduleKey = self.ModuleKey
    local cardPage = self:BuildCardPageExportData()
    if cardPage then
        -- 目前没有游戏内 Card package importer；这是供复制、审查和源码回填
        -- 的完整导出载荷。名称不得暗示已经实现未授权的配置导入流程。
        local package = "-- EXWIND_GRID_CARD_EXPORT v1\n"
            .. "local EXWIND_GRID_CARD_EXPORT = {\n"
            .. "    moduleKey = " .. string.format("%q", cardPage.moduleKey) .. ",\n"
            .. "    gui = " .. serializeTable(cardPage.gui, 2, true) .. ",\n"
        if cardPage.defaults ~= nil then
            package = package .. "    defaults = " .. serializeTable(cardPage.defaults, 2) .. ",\n"
        end
        package = package .. "}\n"
        EXUI:ShowDialog({
            sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
            id = "EX_EXPORT_IMPORT_PACKAGE", title = L["复制完整 Card 导出包（发送给 Codex 验收）:"], width = 650,
            input = { text = package:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
            cancelButton = "close", defaultButton = "close",
            buttons = { { id = "close", text = L["好的"], variant = "primary" } },
        })
        return true
    end

    local moduleSpec, reason = self:BuildModuleSpecExportData()
    local package, dialogText
    if not moduleSpec then
        local defaultData, defaultsReason = self:BuildDeclaredDefaultsExportData()
        if not defaultData then
            print("|cffff8080[ExwindGrid]|r " .. (defaultsReason or reason or L["当前页面没有可导出的正式真源"]))
            return false
        end
        package = "-- EXWIND_GRID_DEFAULTS_IMPORT v1\n"
            .. "local EXWIND_GRID_DEFAULTS_IMPORT = {\n"
            .. "    moduleKey = " .. string.format("%q", defaultData.moduleKey) .. ",\n"
            .. "    defaults = " .. serializeTable(defaultData.defaults, 2) .. ",\n"
            .. "}\n"
        dialogText = L["复制默认值导入包（发送给 Codex 验收并导入）:"]
    else
        package = "-- EXWIND_GRID_IMPORT v1\n"
            .. "local EXWIND_GRID_IMPORT = {\n"
            .. "    moduleKey = " .. string.format("%q", moduleKey) .. ",\n"
            .. "    gui = " .. serializeTable(moduleSpec.gui, 2, true) .. ",\n"
            .. "    defaults = " .. serializeTable(moduleSpec.defaults, 2) .. ",\n"
            .. "}\n"
        dialogText = L["复制完整导入包（发送给 Codex 验收并导入）:"]
    end

    EXUI:ShowDialog({
        sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
        id = "EX_EXPORT_IMPORT_PACKAGE", title = dialogText, width = 650,
        input = { text = package:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
        cancelButton = "close", defaultButton = "close",
        buttons = { { id = "close", text = L["好的"], variant = "primary" } },
    })
end

-- 仅导出布局
function Grid:ExportLayoutOnly()
    local cardPage = self:BuildCardPageExportData()
    if cardPage then
        local layoutStr = "gui = " .. serializeTable(cardPage.gui, 1, true)
        EXUI:ShowDialog({
            sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
            id = "EX_EXPORT_LAYOUT", title = L["复制 Card gui 区块（保留 version/cards 结构）:"], width = 650,
            input = { text = layoutStr:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
            cancelButton = "close", defaultButton = "close",
            buttons = { { id = "close", text = L["好的"], variant = "primary" } },
        })
        return true
    end

    local moduleSpec, reason = self:BuildModuleSpecExportData()
    local layoutStr, dialogText
    if moduleSpec then
        -- 标准模块必须直接替换 MODULE_SPEC.gui；不能再给它遗留 layout 表，
        -- 否则 fields/static 的声明信息会在粘贴后丢失。
        layoutStr = "gui = " .. serializeTable(moduleSpec.gui, 1, true)
        dialogText = L["复制 gui 区块（替换 MODULE_SPEC 内的 gui）:"]
    else
        layoutStr = self:ExportLayout()
        dialogText = L["复制布局代码 (粘贴到模块结尾):"]
    end

    EXUI:ShowDialog({
        sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
        id = "EX_EXPORT_LAYOUT", title = dialogText, width = 650,
        input = { text = layoutStr:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
        cancelButton = "close", defaultButton = "close",
        buttons = { { id = "close", text = L["好的"], variant = "primary" } },
    })
end

-- 仅导出默认值
function Grid:ExportDefaultsOnly()
    local moduleKey = self.ModuleKey
    if type(moduleKey) ~= "string" or moduleKey == "" then
        error(L["[ExwindGrid] 导出默认值失败：当前页面没有模块标识"], 2)
    end

    local moduleSpec = self:BuildModuleSpecExportData()
    local defaultsStr, dialogText
    if moduleSpec then
        -- 标准模块直接替换 MODULE_SPEC.defaults，保留其余 MODULE_SPEC 字段。
        defaultsStr = "defaults = " .. serializeTable(moduleSpec.defaults, 1)
        dialogText = L["复制 defaults 区块（替换 MODULE_SPEC 内的 defaults）:"]
    else
        -- 旧页面（例如 MiniTools）没有 MODULE_SPEC 时，导出当前 Grid 已声明字段的
        -- 预设值，绝不整表搬运 ModuleDB。
        local registered = ExwindTools.ModuleDefaultDeclarations and ExwindTools.ModuleDefaultDeclarations[moduleKey]
        local defaults
        if registered then
            defaults = ExwindTools:ExportModuleDefaults(moduleKey)
        else
            local _, gridDefaults = self:ExportLayout()
            defaults = gridDefaults
        end
        defaultsStr = "local EX_DEFAULTS = " .. serializeTable(defaults, 1)
        dialogText = L["复制默认值代码 (粘贴到模块开头):"]
    end

    EXUI:ShowDialog({
        sourceAddon = "ExwindCore", sourceModule = self.ModuleKey or L["布局"],
        id = "EX_EXPORT_DEFAULTS", title = dialogText, width = 650,
        input = { text = defaultsStr:gsub("|", "||"), multiline = true, readOnly = true, highlight = true },
        cancelButton = "close", defaultButton = "close",
        buttons = { { id = "close", text = L["好的"], variant = "primary" } },
    })
end

function ExwindTools:ToggleDevMode()
    if not self.UI or not self.UI.ActivePageFrame then
        return
    end
    self.Grid:ToggleLiveEdit(self.UI.ActivePageFrame)
end
